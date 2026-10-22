# check=skip=FromPlatformFlagConstDisallowed
# example.sh with its tools pinned by checksum, so anyone can run it as CI does:
#
#   docker build -t parq-example .
#   docker run --rm --platform linux/amd64 -e REG=<a registry namespace you can push to> \
#     -v ~/.docker/config.json:/root/.docker/config.json:ro parq-example
#
# The mounted config.json has to hold your registry login itself, as oras login writes it on a CI
# runner; a login kept in a keychain doesn't reach the container.
#
# example.sh runs without Docker too. Run either way, it should make the same tables.
#
# The platform is pinned on purpose, like everything else, so the build check that warns about it is
# skipped on the first line.

FROM --platform=linux/amd64 debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad

# curl and unzip only move the publisher's bytes. The tools that write the tables and the manifests are
# pinned below, each by the checksum its publisher gives.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl unzip \
  && rm -rf /var/lib/apt/lists/*

ADD --checksum=sha256:3e29952507ebd202e8d0e2678df4490689bfc9c86534e240b541791b969df0e1 \
  https://github.com/duckdb/duckdb/releases/download/v1.4.1/duckdb_cli-linux-amd64.zip /tmp/duckdb.zip
ADD --checksum=sha256:5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5 \
  https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 /usr/local/bin/jq
ADD --checksum=sha256:f48a73ea6d026a862c3919fc773da9a8c86fc259c2c737d5baed3b8b9614ad22 \
  https://github.com/oras-project/oras/releases/download/v1.3.5/oras_1.3.5_linux_amd64.tar.gz /tmp/oras.tar.gz

RUN unzip -d /usr/local/bin /tmp/duckdb.zip duckdb \
  && tar -xzf /tmp/oras.tar.gz -C /usr/local/bin oras \
  && chmod +x /usr/local/bin/jq \
  && rm /tmp/duckdb.zip /tmp/oras.tar.gz

COPY example.sh /usr/local/bin/example.sh
WORKDIR /work
ENTRYPOINT ["sh", "/usr/local/bin/example.sh"]
