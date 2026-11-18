#!/usr/bin/env bash

# Checks a built image before it is pushed: the binaries run on the platform,
# each knows its models, the start script renders a complete configuration for
# each design from environment variables, concentratord accepts it with every
# region and channel file shipped, and the start script hands over to
# concentratord. Nothing here reaches concentrator hardware: the containers get
# no devices, and the configuration checks stop before any GPIO or SPI access.
#
#   docker/smoke-test.sh IMAGE PLATFORM

set -euo pipefail

IMAGE=$1
PLATFORM=$2

# --init keeps the tested command from becoming PID 1, which signals sent from
# inside the container (such as the timeout below) cannot kill.
run() { docker run --rm --init --platform "${PLATFORM}" --network none "$@"; }

fail() { echo "FAIL: $*" >&2; exit 1; }

# expect TEXT LABEL WANTED... : every WANTED string must appear in TEXT.
expect() {
    local text=$1 label=$2 wanted
    shift 2
    for wanted in "$@"; do
        grep -qF -- "${wanted}" <<< "${text}" || fail "'${wanted}' missing from the ${label}"
    done
}

# The single-quoted scripts below run inside the container, so their variables
# must not expand here.

echo "== ${PLATFORM}: binaries"
# shellcheck disable=SC2016
run "${IMAGE}" sh -c 'for d in sx1301 sx1302 2g4; do ./$d/chirpstack-concentratord-$d -V; done; ./gateway-id -V; gpioset --version | head -n1'

echo "== ${PLATFORM}: model lists"
# shellcheck disable=SC2016
MODELS=$(run "${IMAGE}" sh -c 'for d in sx1301 sx1302 2g4; do echo "$d: $(tr "\n" " " < models/$d)"; done')
echo "${MODELS}"
# waveshare_sx1302_lorawan_gateway_hat has a match arm spanning several lines.
expect "${MODELS}" "model lists" "sx1301: " "rak_2245" "sx1302: " "rak_2287" "elecrow_lr1302" \
    "waveshare_sx1302_lorawan_gateway_hat" "2g4: " "rak_5148"

# One configuration per design. RAK7243 (sx1301) also exercises the product
# name translation, its built-in GPS and DEBUG, the old name of LOGGING_LEVEL.
SX1301=(-e MODEL=RAK7243 -e REGION=US915 -e GATEWAY_EUI=0102030405060708 -e DEBUG=debug -e RESET_GPIO=25)
SX1302=(-e MODEL=rak_2287 -e REGION=EU868 -e SOCKET_NAME=slot1 -e RESET_GPIO=23 -e GPIO_CHIP=gpiochip0)
SX1280=(-e MODEL=RAK5148)

echo "== ${PLATFORM}: configurations"
CONFIG=$(run "${SX1301[@]}" "${IMAGE}" bash start --render)
expect "${CONFIG}" "sx1301 configuration" 'model="rak_2245"' 'region="US915"' 'model_flags=["GNSS"]' \
    'gateway_id="0102030405060708"' 'log_level="DEBUG"' 'sx1301_reset_pin=25'
CONFIG=$(run "${SX1302[@]}" "${IMAGE}" bash start --render)
expect "${CONFIG}" "sx1302 configuration" 'model="rak_2287"' 'region="EU868"' 'model_flags=[]' \
    'event_bind="ipc:///tmp/slot1_event"' 'sx1302_reset_pin=23' 'sx1302_reset_chip="/dev/gpiochip0"' \
    'gateway_id=""'
CONFIG=$(run "${SX1280[@]}" "${IMAGE}" bash start --render)
expect "${CONFIG}" "2g4 configuration" 'model="rak_5148"' 'model_flags=[]' 'frequency = 2403000000'
CONFIG=$(run -e MODEL=rak_2287 "${IMAGE}" bash start --render)
if grep -q 'reset_pin' <<< "${CONFIG}"; then
    fail "a reset pin was set although RESET_GPIO was not, overriding the model's default"
fi
for DESIGN_ENV in SX1301 SX1302 SX1280; do
    declare -n ENV_REF=${DESIGN_ENV}
    CONFIG=$(run "${ENV_REF[@]}" "${IMAGE}" bash start --render)
    if grep -nE '\$\{|\{\{' <<< "${CONFIG}"; then
        fail "placeholders left in the ${DESIGN_ENV} configuration"
    fi
done

echo "== ${PLATFORM}: concentratord accepts the configurations"
# "configfile" loads the configuration, model included, and prints it back
# without touching any hardware.
PARSED=$(run "${SX1301[@]}" "${IMAGE}" bash -c 'bash start --render > /dev/null 2>&1 &&
    ./sx1301/chirpstack-concentratord-sx1301 -c run/concentratord.toml -c configs/sx1301/region_us915.toml -c configs/sx1301/channels_us915_0.toml configfile') \
    || fail "concentratord rejected the sx1301 configuration"
expect "${PARSED}" "parsed sx1301 configuration" 'model="rak_2245"' 'region="US915"' 'gateway_id="0102030405060708"'
PARSED=$(run "${SX1302[@]}" "${IMAGE}" bash -c 'bash start --render > /dev/null 2>&1 &&
    ./sx1302/chirpstack-concentratord-sx1302 -c run/concentratord.toml -c configs/sx1302/region_eu868.toml -c configs/sx1302/channels_eu868.toml configfile') \
    || fail "concentratord rejected the sx1302 configuration"
expect "${PARSED}" "parsed sx1302 configuration" 'model="rak_2287"' 'region="EU868"' 'event_bind="ipc:///tmp/slot1_event"'
PARSED=$(run "${SX1280[@]}" "${IMAGE}" bash -c 'bash start --render > /dev/null 2>&1 &&
    ./2g4/chirpstack-concentratord-2g4 -c run/concentratord.toml -c configs/2g4/region_ism2400.toml -c configs/2g4/channels_ism2400.toml configfile') \
    || fail "concentratord rejected the 2g4 configuration"
expect "${PARSED}" "parsed 2g4 configuration" 'model="rak_5148"'

echo "== ${PLATFORM}: every region and channel plan parses"
# Through the start script, as a user would pick them. The RAK models used
# support every region; a channel plan such as us915_3 belongs to region us915,
# while as923_2 is a region of its own.
# shellcheck disable=SC2016
run -e GATEWAY_EUI=0102030405060708 "${IMAGE}" bash -c '
    declare -A MODELS=([sx1301]=rak_2245 [sx1302]=rak_2287 [2g4]=rak_5148)
    count=0
    for design in sx1301 sx1302 2g4; do
        for file in configs/$design/channels_*.toml; do
            plan=${file##*/channels_}; plan=${plan%.toml}
            region=$plan
            [[ -f configs/$design/region_$region.toml ]] || region=${plan%_*}
            MODEL=${MODELS[$design]} REGION=$region CHANNELS=$plan bash start --render > /dev/null 2>&1 \
                || { echo "start script rejected $design $region $plan"; exit 1; }
            ./$design/chirpstack-concentratord-$design -c run/concentratord.toml \
                -c configs/$design/region_$region.toml -c "$file" configfile > /dev/null \
                || { echo "concentratord rejected $design $region $plan"; exit 1; }
            count=$((count + 1))
        done
    done
    echo "$count channel plans parse"' || fail "a region or channel plan was rejected"

echo "== ${PLATFORM}: start script hands over to concentratord"
# Without the concentrator, concentratord panics while setting up its pins or
# device; that panic shows it was started with a configuration it accepted.
OUTPUT=$(run "${SX1302[@]}" "${IMAGE}" timeout -s KILL 10 bash start 2>&1 || true)
echo "${OUTPUT}"
expect "${OUTPUT}" "start output" "Design:         sx1302" "panicked at"
if grep -q 'Error parsing config file' <<< "${OUTPUT}"; then
    fail "concentratord could not parse its configuration"
fi

echo "== ${PLATFORM}: OK"
