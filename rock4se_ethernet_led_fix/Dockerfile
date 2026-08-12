FROM ghcr.io/home-assistant/base:latest AS builder

RUN apk add --no-cache build-base linux-headers
COPY src/rtl8211f-ledctl.c /src/rtl8211f-ledctl.c
RUN cc -O2 -Wall -Wextra -Werror -o /rtl8211f-ledctl /src/rtl8211f-ledctl.c

FROM ghcr.io/home-assistant/base:latest

ARG BUILD_VERSION
ARG BUILD_ARCH

LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="app" \
  io.hass.arch="${BUILD_ARCH}"

COPY --from=builder /rtl8211f-ledctl /usr/local/bin/rtl8211f-ledctl
COPY run.sh /run.sh
RUN chmod 0755 /run.sh /usr/local/bin/rtl8211f-ledctl

CMD ["/run.sh"]
