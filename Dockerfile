# syntax=docker/dockerfile:1

# The toolchain is pinned to an **exact snapshot**, not to `swiftlang/swift:nightly-6.4.x-noble`. That
# tag moves, and a static SDK is tied to the compiler that built it — pairing a dated SDK with a moving
# image works until the day it silently does not. Swiftly installs the snapshot by name, so the toolchain
# and the SDK below name the same build and can only drift together.
#
# The package is tools-version 6.4 since the M6d port (WireMVC's core is proposal-native), which is why
# a released toolchain is not an option here.
FROM ubuntu:24.04 AS toolchain
ARG SWIFT_SNAPSHOT=6.4.x-snapshot-2026-08-01
ENV PATH=/root/.local/share/swiftly/bin:/root/.local/share/swiftly/toolchains/current/usr/bin:$PATH
# Everything the toolchain itself needs, installed *before* Swiftly: its post-install check enumerates
# these and exits non-zero if any are missing, even though the toolchain unpacked fine — so a missing
# package here fails the build with a message that reads like the install failed when it did not.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates binutils git gpg unzip \
        gnupg2 libedit2 libgcc-13-dev libpython3-dev libstdc++-13-dev libncurses-dev libz3-dev \
        pkg-config tzdata zlib1g-dev libcurl4-openssl-dev libxml2-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fL "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" | tar zxf - -C /usr/local/bin \
    && swiftly init --assume-yes --skip-install \
    && swiftly install "${SWIFT_SNAPSHOT}" --use --assume-yes

# The static SDK for that same snapshot. Pinned by checksum, as `swift sdk install` requires.
RUN swiftly run swift sdk install \
        https://download.swift.org/swift-6.4.x-branch/static-sdk/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-01-a/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-01-a_static-linux-0.1.0.artifactbundle.tar.gz \
        --checksum c060ee5d7331bcb6356d1c3bab0f0511a901186b7620c89ceadfc4301e89b831

FROM toolchain AS build
WORKDIR /workspace
COPY . .
# Build the static-musl binary for the image's own architecture (the static SDK bundle
# ships both x86_64 and aarch64). `uname -m` under BuildKit reflects the target platform —
# x86_64 on GitHub's amd64 runners, aarch64 on Apple Silicon — so the binary matches the
# runtime and doesn't hit "exec format error".
#
# `--build-system native` is **required**, not a preference, and the alternatives were measured on a
# 7.7 GiB builder rather than guessed at:
#
#   swiftbuild (the 6.4 default), default -j  → out of memory at   77s
#   swiftbuild, -j 2                          → out of memory at  269s
#   swiftbuild, -j 2, -no-whole-module-opt    → out of memory at  149s
#   swiftbuild, -j 1                          → out of memory at 1954s
#   native, -j 2                              → builds
#
# Serialising to one job made it twenty-five times slower and still did not fit, which is the useful
# result: this is not about parallelism. A *single* module — OpenAPIKit — exceeds the memory available
# under `swiftbuild` on its own, so throttling cannot help and disabling whole-module optimisation does
# not either. `-j 2` is kept only to leave headroom.
#
# It fails as `unable to open dependencies file (…-primary.d)` plus a `Failed frontend command:` with no
# diagnostic beneath it — the frontend was killed before it could write either. That reads like a compile
# error and is not one, which is why this is written down.
#
# **`native` is deprecated.** This build therefore depends on something with a stated end date. When it
# goes, the choices are a larger builder or dropping static-musl linking — the latter is not free, since
# Soto was chosen over aws-sdk-swift precisely because the latter would not compile against this SDK.
RUN --mount=type=cache,target=/workspace/.build \
    ARCH="$(uname -m)" && \
    swift build -c release -j 2 --build-system native \
        --swift-sdk "${ARCH}-swift-linux-musl" && \
    cp ".build/${ARCH}-swift-linux-musl/release/TaskCluster" /TaskCluster

FROM scratch AS runtime
COPY --from=build /TaskCluster /TaskCluster
EXPOSE 8080
ENTRYPOINT ["/TaskCluster"]
