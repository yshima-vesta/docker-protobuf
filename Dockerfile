ARG ALPINE_VERSION
ARG GRPC_CSHARP_VERSION
ARG GRPC_VERSION

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
        # 不要なのでOFFにしたいがgRPCのバグでONでなければmake installに失敗する
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


FROM alpine:${ALPINE_VERSION} AS release
# Use all output including headers and protoc from protoc_builder
COPY --from=protoc_builder /out/ /
# Use protoc and plugin from protoc_cs_builder
COPY --from=protoc_cs_builder /out/usr/bin/protoc-* /usr/bin/protoc-csharp
COPY --from=protoc_cs_builder /out/usr/bin/grpc_csharp_plugin /usr/bin/grpc_csharp_plugin
RUN apk add --no-cache bash libstdc++ && \
    ln -s /usr/bin/grpc_csharp_plugin /usr/bin/protoc-gen-grpc-csharp && \
    mkdir -p /{protos,outputs}
COPY protoc-wrapper /usr/bin/protoc-wrapper
ENV LD_LIBRARY_PATH='/usr/lib:/usr/lib64:/usr/lib/local'
ENTRYPOINT ["protoc-wrapper"]
CMD ["--proto_path=/protos", "--csharp_out=/outputs", "/protos/*.proto"]
