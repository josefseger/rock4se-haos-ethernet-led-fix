#!/usr/bin/with-contenv bashio
set -euo pipefail

INTERFACE="end0"
FIX_LEDCR="0x2f71"
FIX_EEELCR="0x6007"
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

    if [[ "${ledcr}" == "${FIX_LEDCR}" && "${eeelcr}" == "${FIX_EEELCR}" ]]; then
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
    local native_ledcr native_eeelcr

    if [[ ! -f "${STATE_FILE}" ]]; then
        bashio::log.info "LED fix disabled. No saved native values exist, so no PHY registers will be changed."
        return 0
    fi

    # shellcheck disable=SC1090
    source "${STATE_FILE}"
    native_ledcr="${LEDCR:-}"
    native_eeelcr="${EEELCR:-}"

    if [[ -z "${native_ledcr}" || -z "${native_eeelcr}" ]]; then
        bashio::log.warning "Saved native LED state is invalid; leaving PHY registers unchanged."
        return 0
    fi

    bashio::log.info "LED fix disabled; restoring saved native values: LEDCR=${native_ledcr}, EEELCR=${native_eeelcr}"
    /usr/local/bin/rtl8211f-ledctl write "${INTERFACE}" "${native_ledcr}" "${native_eeelcr}" >/dev/null
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
