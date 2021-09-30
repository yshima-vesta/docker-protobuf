ARG ARCH=amd64
ARG ALPINE_VERSION=3.14
ARG GRPC_CSHARP_VERSION=1.41.0
ARG GRPC_VERSION=1.41.0
ARG UPX_VERSION=3.96

FROM alpine:${ALPINE_VERSION} AS protoc_base
RUN apk add --no-cache build-base curl cmake autoconf libtool git zlib-dev linux-headers && \
    mkdir -p /out

FROM protoc_base AS protoc_builder
ARG GRPC_VERSION
RUN apk add --no-cache automake ninja && \
    git clone --recursive --depth=1 -b v${GRPC_VERSION} https://github.com/grpc/grpc.git /grpc && \
    ln -s /grpc/third_party/protobuf /protobuf && \
    mkdir -p /grpc/cmake/build && \
    cd /grpc/cmake/build && \
    cmake \
        -GNinja \
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DgRPC_INSTALL=ON \
        -DgRPC_BUILD_TESTS=OFF \
        ../.. && \
    cmake --build . --target plugins && \
    cmake --build . --target install && \
    DESTDIR=/out cmake --build . --target install


FROM protoc_base AS protoc_cs_builder
ARG GRPC_CSHARP_VERSION
RUN git clone --recursive --depth=1 -b v${GRPC_CSHARP_VERSION} https://github.com/grpc/grpc.git /grpc && \
    ln -s /grpc/third_party/protobuf /protobuf && \
    mkdir -p /grpc/cmake/build && \
    cd /grpc/cmake/build && \
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DgRPC_BUILD_TESTS=OFF \
        -DgRPC_BUILD_GRPC_CPP_PLUGIN=ON \
        -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF \
        -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF \
        -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF \
        -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF \
        -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF \
        -DgRPC_INSTALL=ON \
        -DCMAKE_INSTALL_PREFIX=/out/usr \
        ../.. && \
    make -j4 install && \
    rm -Rf /grpc


FROM alpine:${ALPINE_VERSION} AS packer
RUN apk add --no-cache curl
ARG UPX_VERSION
ARG ARCH
RUN mkdir -p /upx && curl -sSL https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-${ARCH}_linux.tar.xz | tar xJ --strip 1 -C /upx && \
    install -D /upx/upx /usr/local/bin/upx
# Use all output including headers and protoc from protoc_builder
COPY --from=protoc_builder /out/ /out/
# Use protoc and plugin from protoc_cs_builder
COPY --from=protoc_cs_builder /out/usr/bin/protoc-* /out/usr/bin/protoc-csharp
COPY --from=protoc_cs_builder /out/usr/bin/grpc_csharp_plugin /out/usr/bin/grpc_csharp_plugin
RUN upx --lzma $(find /out/usr/bin/ \
        -type f -name 'grpc_*' \
        -not -name 'grpc_node_plugin' \
        -not -name 'grpc_php_plugin' \
        -not -name 'grpc_ruby_plugin' \
        -not -name 'grpc_python_plugin' \
        -or -name 'protoc-gen-*' \
    )
RUN find /out -name "*.a" -delete -or -name "*.la" -delete


FROM alpine:${ALPINE_VERSION} AS release
COPY --from=packer /out/ /
RUN apk add --no-cache bash libstdc++ && \
    ln -s /usr/bin/grpc_csharp_plugin /usr/bin/protoc-gen-grpc-csharp && \
    mkdir -p /{protos,outputs}
COPY protoc-wrapper /usr/bin/protoc-wrapper
ENV LD_LIBRARY_PATH='/usr/lib:/usr/lib64:/usr/lib/local'
ENTRYPOINT ["protoc-wrapper", "-I/usr/include"]
CMD ["--proto_path=/protos", "--csharp_out=/outputs", "/protos/*.proto"]
