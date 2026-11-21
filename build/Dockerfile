FROM ubuntu:22.04@sha256:e0f80c829509ef4df9e76bd8944eb7b8ec25cbb379b112a7f9448b2c77a77c9b
RUN apt-get -o Acquire::Retries=3 -o Acquire::ForceIPv4=true -o Acquire::http::Timeout=25 update && \
    DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 -o Acquire::ForceIPv4=true -o Acquire::http::Timeout=25 install -y --no-install-recommends \
       ca-certificates qemu-user-static proot rsync device-tree-compiler e2fsprogs \
       file kmod initramfs-tools-core cpio zstd lz4 python3 xz-utils util-linux gdisk dosfstools mtools u-boot-tools kmod && \
    dpkg-query -W > /opt/build-tool-packages && rm -rf /var/lib/apt/lists/*
