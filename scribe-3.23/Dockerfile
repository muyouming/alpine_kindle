FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils e2fsprogs qemu-user-static \
        zip unzip file git python3 procps netpbm \
    && rm -rf /var/lib/apt/lists/*

COPY init.sh /usr/local/bin/init.sh
RUN chmod 755 /usr/local/bin/init.sh

ENTRYPOINT ["/usr/local/bin/init.sh"]
CMD ["sleep", "infinity"]
