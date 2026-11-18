FROM alpine:3.24

ARG TARGETARCH
ARG TARGETVARIANT

# libgpiod provides gpioset, used to reset USB concentrators through GPIOs.
RUN apk add --no-cache bash gettext-envsubst libgpiod

WORKDIR /opt/chirpstack

# One binary per concentrator design, each in its own folder. The release
# tarballs call the 32-bit ARM build "armv7hf"; buildx calls it arm/v7.
RUN --mount=type=bind,from=dist,target=/dist \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64) arch=amd64 ;; \
      arm64) arch=arm64 ;; \
      armv7) arch=armv7hf ;; \
      *) echo "unsupported platform: ${TARGETARCH}${TARGETVARIANT}" >&2; exit 1 ;; \
    esac; \
    for design in sx1301 sx1302 2g4; do \
      set -- /dist/chirpstack-concentratord-"${design}"_*_"${arch}".tar.gz; \
      if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then \
        echo "expected exactly one ${design} ${arch} tarball in the dist context, found: $*" >&2; exit 1; \
      fi; \
      mkdir "${design}" && tar -xzf "$1" -C "${design}"; \
    done; \
    ln -s sx1302/gateway-id gateway-id

# The region and channel files, and the list of models each binary supports,
# come from each design's folder in the repository (in CI, as of the release
# tag), so they always match the binaries. The models are the arms of the
# "match config.gateway.model" block, which ends with an "unexpected gateway
# model" panic; some arms span several lines. An empty list means the source
# changed shape and the patterns below need updating.
COPY --from=src-sx1301 config/region_*.toml config/channels_*.toml configs/sx1301/
COPY --from=src-sx1302 config/region_*.toml config/channels_*.toml configs/sx1302/
COPY --from=src-2g4 config/region_*.toml config/channels_*.toml configs/2g4/
RUN --mount=type=bind,from=src-sx1301,target=/src/sx1301 \
    --mount=type=bind,from=src-sx1302,target=/src/sx1302 \
    --mount=type=bind,from=src-2g4,target=/src/2g4 \
    mkdir models; \
    for design in sx1301 sx1302 2g4; do \
      sed -n '/match config\.gateway\.model/,/unexpected gateway model/p' "/src/${design}/src/config/mod.rs" \
        | sed -nE 's/^ *"([a-z0-9_]+)" =>.*/\1/p' | sort -u > "models/${design}"; \
      if [ ! -s "models/${design}" ]; then \
        echo "no models found for ${design} in src/config/mod.rs" >&2; exit 1; \
      fi; \
    done

COPY runner/ ./

# The start script writes the configuration here; nothing else in the work
# directory is written at run time.
RUN mkdir run && chown nobody:nogroup run

# Concentratord only stops cleanly on SIGINT. Running as PID 1, it would
# ignore Docker's default SIGTERM, so docker stop would end in a SIGKILL.
STOPSIGNAL SIGINT

USER nobody:nogroup
ENV PATH="${PATH}:/opt/chirpstack"
CMD ["bash", "start"]
