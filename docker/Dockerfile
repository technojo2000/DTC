# Static, stripped cross-builds of DTC (with libyaml) using zig cc.
# Sources come from the dtc/ and libyaml/ git submodules.
#   git submodule update --init
#   ./build.sh   (see README.md)

FROM debian:trixie-slim AS build

ARG ZIG_VERSION=0.16.0
ARG DTC_VERSION=unknown

RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates curl xz-utils make flex bison pkg-config file zip \
	&& rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
	| tar -xJ -C /opt \
	&& ln -s "/opt/zig-x86_64-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig \
	&& zig version

COPY dtc/ /src/dtc/
COPY libyaml/ /src/libyaml/
COPY docker/build-all.sh /usr/local/bin/build-all.sh
RUN DTC_VERSION="${DTC_VERSION}" build-all.sh

FROM scratch
COPY --from=build /out/ /
