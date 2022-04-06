#build chia exporter
FROM golang:1 as builder

RUN git clone https://github.com/Chia-Network/chia-exporter.git /app && cd /app && git fetch --tags && git checkout $(git describe --tags `git rev-list --tags --max-count=1`)
WORKDIR /app
RUN make build

# CHIA BUILD STEP
FROM python:3.9 AS chia_build

ARG BRANCH=latest
ARG COMMIT=""

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        lsb-release sudo

WORKDIR /chia-blockchain

RUN echo "cloning ${BRANCH}" && \
    git clone --branch ${BRANCH} --recurse-submodules=mozilla-ca https://github.com/Chia-Network/chia-blockchain.git . && \
    # If COMMIT is set, check out that commit, otherwise just continue
    ( [ ! -z "$COMMIT" ] && git checkout $COMMIT ) || true && \
    echo "running build-script" && \
    /bin/sh ./install.sh

# IMAGE BUILD
FROM python:3.9-slim

EXPOSE 8555 8444

ENV CHIA_ROOT=/home/chia/.chia/mainnet
ENV keys="generate"
ENV service="farmer"
ENV plots_dir="/plots"
ENV farmer_address=
ENV farmer_port=
ENV testnet="false"
ENV TZ="UTC"
ENV upnp="false"
ENV log_to_file="true"
ENV healthcheck="true"
ENV CHIA_EXPORTER_MAXMIND_DB_PATH=/GeoLite2-Country.mmdb

# Deprecated legacy options
ENV harvester="false"
ENV farmer="false"

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y tzdata curl && \
    rm -rf /var/lib/apt/lists/* && \
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata

COPY --from=chia_build /chia-blockchain /chia-blockchain
COPY --from=builder /app/bin/chia-exporter /chia-exporter
ADD ./GeoLite2-Country.mmdb /GeoLite2-Country.mmdb

ENV PATH=/chia-blockchain/venv/bin:$PATH
WORKDIR /chia-blockchain

COPY docker-start.sh /usr/local/bin/
COPY docker-entrypoint.sh /usr/local/bin/
COPY docker-healthcheck.sh /usr/local/bin/

HEALTHCHECK --interval=1m --timeout=10s --start-period=20m \
  CMD /bin/bash /usr/local/bin/docker-healthcheck.sh || exit 1

RUN useradd -ms /bin/bash -u 8444 chia && chown -R chia:chia /chia-blockchain && chown -R chia:chia /usr/local/bin/*
USER chia

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["docker-start.sh"]
