# syntax=docker/dockerfile:1

FROM swift:6.3.1-noble AS toolchain
RUN swift sdk install \
        https://download.swift.org/swift-6.3.1-release/static-sdk/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz \
        --checksum fac05271c1f7d060bd203240ce5251d5ca902d30ac899f553765dbb3a88b97ad

FROM toolchain AS build
WORKDIR /workspace
COPY . .
# Build the static-musl binary for the image's own architecture (the static SDK bundle
# ships both x86_64 and aarch64). `uname -m` under BuildKit reflects the target platform —
# x86_64 on GitHub's amd64 runners, aarch64 on Apple Silicon — so the binary matches the
# runtime and doesn't hit "exec format error".
RUN --mount=type=cache,target=/workspace/.build \
    ARCH="$(uname -m)" && \
    swift build -c release --swift-sdk "${ARCH}-swift-linux-musl" && \
    cp ".build/${ARCH}-swift-linux-musl/release/TaskCluster" /TaskCluster

FROM scratch AS runtime
COPY --from=build /TaskCluster /TaskCluster
EXPOSE 8080
ENTRYPOINT ["/TaskCluster"]
