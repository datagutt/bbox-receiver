FROM alpine:3.20 as builder
RUN apk update && \
    apk upgrade && \
    apk add --no-cache linux-headers alpine-sdk cmake tcl openssl-dev zlib-dev spdlog spdlog-dev cmake

WORKDIR /tmp

# belabox patched srt
#
ARG BELABOX_SRT_VERSION=belabox
RUN mkdir -p /build; \
    git clone https://github.com/IRLServer/srt-new.git /build/srt; \
    cd /build/srt; \
    git checkout $BELABOX_SRT_VERSION; \
    ./configure; \
    make -j${nproc}; \
    make install;

# belabox patched srtla
#
ARG SRTLA_VERSION=irltk-fork
RUN mkdir -p /build; \
    git clone https://github.com/IRLServer/srtla.git /build/srtla; \
    cd /build/srtla; \
    git checkout $SRTLA_VERSION; \
    git submodule init && git submodule update --recursive; \
    cmake .; \
    make -j${nproc};

RUN cp /build/srtla/irltk_srtla_rec /usr/local/bin/srtla_rec
# I honestly don't know why this is needed after rebasing with mainstream SRT
RUN cp /build/srt/srtcore/srt_compat.h /usr/local/include/srt/

ENV LD_LIBRARY_PATH /lib:/usr/lib:/usr/local/lib64
ARG SRT_LIVE_SERVER_VERSION=master
# use custom irl srt server from irlserver
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
FROM node:alpine3.20
ENV LD_LIBRARY_PATH /lib:/usr/lib:/usr/local/lib64
RUN apk add --update --no-cache openssl libstdc++ supervisor perl coreutils spdlog spdlog-dev

COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/include /usr/local/include
COPY --from=builder /usr/local/bin /usr/local/bin

COPY files/sls.conf /etc/sls/sls.conf
COPY files/supervisord.conf /etc/supervisord.conf
COPY files/logprefix /usr/local/bin/logprefix
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh
RUN chmod 755 /usr/local/bin/logprefix;

EXPOSE 5000/udp 8181/tcp 8282/udp
ENTRYPOINT ["/entrypoint.sh"]
