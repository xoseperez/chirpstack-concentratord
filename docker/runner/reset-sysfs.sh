#!/usr/bin/env bash

# Resets a USB concentrator through GPIOs with the legacy sysfs interface
# (/sys/class/gpio), before concentratord starts. Run by ./start, which exports:
#
#   RESET_GPIO      reset line(s), comma-separated; 0 for none
#   RESET_ACTIVE    level that holds the concentrator in reset (0 or 1)
#   POWER_EN_GPIO   power-enable line; 0 for none
#   POWER_EN_LOGIC  level that powers the concentrator (0 or 1)

wait_gpio() {
    sleep 0.01
}

# Drive a line as an output: set_gpio GPIO VALUE...
# Each value is held for 10 ms; the line is released afterwards.
set_gpio() {
    local gpio=$1 value
    shift
    if [[ -d "/sys/class/gpio/gpio${gpio}" ]]; then
        echo "${gpio}" > /sys/class/gpio/unexport; wait_gpio
    fi
    echo "${gpio}" > /sys/class/gpio/export; wait_gpio
    if [[ ! -d "/sys/class/gpio/gpio${gpio}" ]]; then
        echo "WARNING: /sys/class/gpio/gpio${gpio} does not exist"
        return
    fi
    echo out > "/sys/class/gpio/gpio${gpio}/direction"; wait_gpio
    for value in "$@"; do
        echo "${value}" > "/sys/class/gpio/gpio${gpio}/value"; wait_gpio
    done
    echo "${gpio}" > /sys/class/gpio/unexport; wait_gpio
}

INACTIVE=$(( 1 - RESET_ACTIVE ))

if [[ "${POWER_EN_GPIO}" != "0" ]]; then
    echo "Concentrator enabled through GPIO${POWER_EN_GPIO} (using sysfs)"
    set_gpio "${POWER_EN_GPIO}" "${POWER_EN_LOGIC}"
fi

for GPIO in ${RESET_GPIO//,/ }; do
    if [[ "${GPIO}" != "0" ]]; then
        echo "Concentrator reset through GPIO${GPIO} (using sysfs)"
        set_gpio "${GPIO}" "${INACTIVE}" "${RESET_ACTIVE}" "${INACTIVE}"
    fi
done

exit 0
