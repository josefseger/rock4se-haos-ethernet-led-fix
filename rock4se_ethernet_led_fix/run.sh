#!/usr/bin/with-contenv bashio
set -euo pipefail

INTERFACE="end0"
FIX_LEDCR="0x2f71"
FIX_EEELCR="0x6007"
HAOS_NATIVE_LEDCR="0x6251"
HAOS_NATIVE_EEELCR="0x600f"
STATE_FILE="/data/native-led-values"
CHECK_INTERVAL=60

read_registers() {
    /usr/local/bin/rtl8211f-ledctl read "${INTERFACE}"
}

get_value() {
    local key="$1"
    awk -F= -v k="${key}" '$1 == k { print $2 }'
}

wait_for_phy() {
    local attempt
    for attempt in $(seq 1 60); do
        if [[ -e "/sys/class/net/${INTERFACE}" ]]; then
            if output="$(read_registers 2>/dev/null)"; then
                printf '%s\n' "${output}"
                return 0
            fi
        fi
        if (( attempt == 1 )); then
            bashio::log.info "Waiting for ${INTERFACE} and RTL8211F PHY to become available..."
        fi
        sleep 2
    done
    bashio::log.fatal "${INTERFACE} / RTL8211F PHY did not become available within 120 seconds."
    exit 1
}

save_native_if_needed() {
    local ledcr="$1"
    local eeelcr="$2"

    # Never overwrite an already captured native state.
    if [[ -f "${STATE_FILE}" ]]; then
        return 0
    fi

    # If the PHY is already in the desired fixed state, we cannot infer the
    # pre-fix values. This can happen after manual testing before app install.
    # restore_native() has a verified HAOS fallback for that case.
    if [[ "${ledcr}" == "${FIX_LEDCR}" && "${eeelcr}" == "${FIX_EEELCR}" ]]; then
        bashio::log.info "PHY was already using the fixed LED values; native state was not captured."
        return 0
    fi

    printf 'LEDCR=%s\nEEELCR=%s\n' "${ledcr}" "${eeelcr}" > "${STATE_FILE}"
    bashio::log.info "Saved native PHY LED values: LEDCR=${ledcr}, EEELCR=${eeelcr}"
}

apply_fix() {
    local output ledcr eeelcr
    output="$(read_registers)"
    ledcr="$(printf '%s\n' "${output}" | get_value LEDCR)"
    eeelcr="$(printf '%s\n' "${output}" | get_value EEELCR)"

    save_native_if_needed "${ledcr}" "${eeelcr}"

    if [[ "${ledcr}" == "${FIX_LEDCR}" && "${eeelcr}" == "${FIX_EEELCR}" ]]; then
        bashio::log.info "Ethernet LED fix already active: LEDCR=${ledcr}, EEELCR=${eeelcr}"
        return 0
    fi

    bashio::log.info "Applying Debian-style RTL8211F LED values: LEDCR=${FIX_LEDCR}, EEELCR=${FIX_EEELCR}"
    /usr/local/bin/rtl8211f-ledctl write "${INTERFACE}" "${FIX_LEDCR}" "${FIX_EEELCR}" >/dev/null

    output="$(read_registers)"
    ledcr="$(printf '%s\n' "${output}" | get_value LEDCR)"
    eeelcr="$(printf '%s\n' "${output}" | get_value EEELCR)"
    if [[ "${ledcr}" != "${FIX_LEDCR}" || "${eeelcr}" != "${FIX_EEELCR}" ]]; then
        bashio::log.fatal "PHY LED register verification failed: LEDCR=${ledcr}, EEELCR=${eeelcr}"
        exit 1
    fi
    bashio::log.info "Ethernet LED fix active: yellow=steady link, green=traffic activity."
}

restore_native() {
    local native_ledcr native_eeelcr source_description output ledcr eeelcr

    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}"
        native_ledcr="${LEDCR:-}"
        native_eeelcr="${EEELCR:-}"
        source_description="saved native values"

        if [[ -z "${native_ledcr}" || -z "${native_eeelcr}" ]]; then
            bashio::log.warning "Saved native LED state is invalid; using verified HAOS defaults instead."
            native_ledcr="${HAOS_NATIVE_LEDCR}"
            native_eeelcr="${HAOS_NATIVE_EEELCR}"
            source_description="verified HAOS defaults"
        fi
    else
        # The first development/test install may start while the PHY has
        # already been manually changed to the Debian values. We measured the
        # original HAOS values on this exact ROCK 4 SE / RTL8211F-VD setup.
        native_ledcr="${HAOS_NATIVE_LEDCR}"
        native_eeelcr="${HAOS_NATIVE_EEELCR}"
        source_description="verified HAOS defaults"
    fi

    bashio::log.info "LED fix disabled; restoring ${source_description}: LEDCR=${native_ledcr}, EEELCR=${native_eeelcr}"
    /usr/local/bin/rtl8211f-ledctl write "${INTERFACE}" "${native_ledcr}" "${native_eeelcr}" >/dev/null

    output="$(read_registers)"
    ledcr="$(printf '%s\n' "${output}" | get_value LEDCR)"
    eeelcr="$(printf '%s\n' "${output}" | get_value EEELCR)"

    if [[ "${ledcr}" != "${native_ledcr}" || "${eeelcr}" != "${native_eeelcr}" ]]; then
        bashio::log.fatal "Native PHY LED register verification failed: LEDCR=${ledcr}, EEELCR=${eeelcr}"
        exit 1
    fi

    bashio::log.info "Native Ethernet LED configuration active: LEDCR=${ledcr}, EEELCR=${eeelcr}"
}

ENABLED="$(bashio::config 'led_fix')"
INITIAL="$(wait_for_phy)"
PHY_ID="$(printf '%s\n' "${INITIAL}" | get_value PHY_ID)"
LEDCR="$(printf '%s\n' "${INITIAL}" | get_value LEDCR)"
EEELCR="$(printf '%s\n' "${INITIAL}" | get_value EEELCR)"

bashio::log.info "Detected ${INTERFACE}: PHY_ID=${PHY_ID}, LEDCR=${LEDCR}, EEELCR=${EEELCR}"

if bashio::var.true "${ENABLED}"; then
    apply_fix
    while true; do
        sleep "${CHECK_INTERVAL}"
        if ! output="$(read_registers 2>&1)"; then
            bashio::log.warning "Unable to read PHY registers; will retry in ${CHECK_INTERVAL}s: ${output}"
            continue
        fi
        current_ledcr="$(printf '%s\n' "${output}" | get_value LEDCR)"
        current_eeelcr="$(printf '%s\n' "${output}" | get_value EEELCR)"
        if [[ "${current_ledcr}" != "${FIX_LEDCR}" || "${current_eeelcr}" != "${FIX_EEELCR}" ]]; then
            bashio::log.warning "PHY LED configuration reverted (LEDCR=${current_ledcr}, EEELCR=${current_eeelcr}); reapplying fix."
            apply_fix
        fi
    done
else
    restore_native
    bashio::log.info "Ethernet LED fix is disabled. App will remain idle."
    while true; do sleep 3600; done
fi
