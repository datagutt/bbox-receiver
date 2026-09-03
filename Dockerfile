FROM alpine:3.24 AS builder
RUN apk update &&\
    apk upgrade &&\ 
    apk add --no-cache linux-headers alpine-sdk cmake tcl openssl-dev zlib-dev spdlog spdlog-dev cmake

WORKDIR /tmp

# belabox patched srt
# Pinned commit on IRLServer/srt belabox-dev branch
ARG BELABOX_SRT_VERSION=0fc2aad3b2cba0b73c26ff8a0bba5b48717ff5b3
RUN mkdir -p /build; \
    git clone https://github.com/IRLServer/srt.git /build/srt; \
    cd /build/srt; \
    git checkout $BELABOX_SRT_VERSION; \
    ./configure; \
    make -j${nproc}; \
    make install;

# belabox patched srtla
# Pinned commit on IRLServer/srtla main branch
ARG SRTLA_VERSION=39e324a9420763720b9f16c463971ababa757bc1
RUN mkdir -p /build; \
    git clone https://github.com/IRLServer/srtla.git /build/srtla; \
    cd /build/srtla; \
    git checkout $SRTLA_VERSION; \
    git submodule init && git submodule update --recursive; \
    cmake .; \
    make -j${nproc};

RUN cp /build/srtla/srtla_rec /usr/local/bin/srtla_rec
# I honestly don't know why this is needed after rebasing with mainstream SRT
RUN cp /build/srt/srtcore/srt_compat.h /usr/local/include/srt/

ENV LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib64
# use custom irl srt server from irlserver
# Pinned commit on IRLServer/irl-srt-server main branch
ARG SRT_LIVE_SERVER_VERSION=37912ba6b5dd360a8411b960e57e1142c9293173
RUN set -xe; \
    mkdir -p /build; \
    git clone https://github.com/IRLServer/irl-srt-server.git /build/srt-live-server; \
    cd /build/srt-live-server; \
    git checkout $SRT_LIVE_SERVER_VERSION; \
    git submodule update --init; \
    cmake . -DCMAKE_BUILD_TYPE=Release; \
    make -j${nproc}; \
    cp bin/* /usr/local/bin;


# runtime container with server
#
FROM node:alpine3.24
ENV LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib64
RUN apk add --update --no-cache openssl libstdc++ supervisor perl coreutils spdlog spdlog-dev

COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/include /usr/local/include
COPY --from=builder /usr/local/bin /usr/local/bin

COPY files/sls.conf /etc/sls/sls.conf
COPY files/supervisord.conf /etc/supervisord.conf
COPY files/logprefix /usr/local/bin/logprefix
COPY server/ /app
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh
RUN chmod 755 /usr/local/bin/logprefix;

WORKDIR /app

EXPOSE 5000/udp 4000/udp 4001/udp 8181/tcp 8282/udp 3000/tcp
ENTRYPOINT ["/entrypoint.sh"]
