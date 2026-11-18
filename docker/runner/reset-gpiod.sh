#!/usr/bin/env bash

# Resets a USB concentrator through GPIOs with libgpiod (version 2 command
# line), before concentratord starts. Run by ./start, which exports:
#
#   GPIO_CHIP       chip holding the lines, such as gpiochip0
#   RESET_GPIO      reset line(s), comma-separated; 0 for none
#   RESET_ACTIVE    level that holds the concentrator in reset (0 or 1)
#   POWER_EN_GPIO   power-enable line; 0 for none
#   POWER_EN_LOGIC  level that powers the concentrator (0 or 1)
#
# gpioset only guarantees a value while it runs. The Raspberry Pi kernel keeps
# released outputs driven, so the lines stay as set after it exits.

INACTIVE=$(( 1 - RESET_ACTIVE ))

if [[ "${POWER_EN_GPIO}" != "0" ]]; then
    echo "Concentrator enabled through ${GPIO_CHIP}:${POWER_EN_GPIO} (using libgpiod)"
    gpioset -c "${GPIO_CHIP}" -p 100ms -t 0 "${POWER_EN_GPIO}=${POWER_EN_LOGIC}" \
        || echo "WARNING: could not set ${GPIO_CHIP}:${POWER_EN_GPIO}"
fi

# Pulse each reset line: inactive, active for 100 ms, inactive again. With a
# last toggle period of 0, gpioset exits right after the last toggle.
for GPIO in ${RESET_GPIO//,/ }; do
    if [[ "${GPIO}" != "0" ]]; then
        echo "Concentrator reset through ${GPIO_CHIP}:${GPIO} (using libgpiod)"
        gpioset -c "${GPIO_CHIP}" -p 100ms -t 100ms,100ms,0 "${GPIO}=${INACTIVE}" \
            || echo "WARNING: could not reset through ${GPIO_CHIP}:${GPIO}"
    fi
done

exit 0
