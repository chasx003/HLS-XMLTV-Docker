ARG NGINX_VERSION=1.17.7
ARG NGINX_RTMP_VERSION=1.2.1
ARG FFMPEG_VERSION=4.2.2

FROM alpine:3.8 as build-nginx
ARG NGINX_VERSION
ARG NGINX_RTMP_VERSION

RUN apk add --update \
  build-base \
  ca-certificates \
  curl \
  gcc \
  libc-dev \
  libgcc \
  linux-headers \
  make \
  musl-dev \
  openssl \
  openssl-dev \
  pcre \
  pcre-dev \
  pkgconf \
  pkgconfig \
  zlib-dev


# Get nginx source.
RUN cd /tmp && \
  wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar zxf nginx-${NGINX_VERSION}.tar.gz && \
  rm nginx-${NGINX_VERSION}.tar.gz


# Get nginx-rtmp module.
RUN cd /tmp && \
  wget https://github.com/arut/nginx-rtmp-module/archive/v${NGINX_RTMP_VERSION}.tar.gz && \
  tar zxf v${NGINX_RTMP_VERSION}.tar.gz && rm v${NGINX_RTMP_VERSION}.tar.gz


# Compile nginx with nginx-rtmp module.
RUN cd /tmp/nginx-${NGINX_VERSION} && \
  ./configure \
  --prefix=/usr/local/nginx \
  --add-module=/tmp/nginx-rtmp-module-${NGINX_RTMP_VERSION} \
  --conf-path=/etc/nginx/nginx.conf \
  --with-threads \
  --with-file-aio \
  --with-http_ssl_module \
  --with-debug && \
  cd /tmp/nginx-${NGINX_VERSION} && make && make install

FROM alpine:3.8 as build-ffmpeg
ARG FFMPEG_VERSION
ARG PREFIX=/usr/local
ARG MAKEFLAGS="-j4"

# FFmpeg build dependencies.
RUN apk add --update \
  build-base \
  coreutils \
  freetype-dev \
  lame-dev \
  libogg-dev \
  libass \
  libass-dev \
  libvpx-dev \
  libvorbis-dev \
  libwebp-dev \
  libtheora-dev \
  opus-dev \
  pkgconf \
  pkgconfig \
  rtmpdump-dev \
  wget \
  x264-dev \
  x265-dev \
  yasm

RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories
RUN apk add --update fdk-aac-dev

# Get FFmpeg source.
RUN cd /tmp/ && \
  wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
  tar zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && rm ffmpeg-${FFMPEG_VERSION}.tar.gz

# Compile ffmpeg.
RUN cd /tmp/ffmpeg-${FFMPEG_VERSION} && \
  ./configure \
  --prefix=${PREFIX} \
  --enable-version3 \
  --enable-gpl \
  --enable-nonfree \
  --enable-small \
  --enable-libmp3lame \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libvpx \
  --enable-libtheora \
  --enable-libvorbis \
  --enable-libopus \
  --enable-libfdk-aac \
  --enable-libass \
  --enable-libwebp \
  --enable-librtmp \
  --enable-postproc \
  --enable-avresample \
  --enable-libfreetype \
  --enable-openssl \
  --disable-debug \
  --disable-doc \
  --disable-ffplay \
  --extra-libs="-lpthread -lm" && \
  make && make install && make distclean


RUN cd /tmp/ && \
  wget https://github.com/deanochips/HLS-XMLTV---Home-Broadcasting/archive/master.tar.gz && \
  tar zxf master.tar.gz

RUN mv /tmp/HLS-XMLTV---Home-Broadcasting-master /HLS_XMLTV

# Cleanup.
RUN rm -rf /var/cache/* /tmp/*

##########################
# Build the release image.
FROM alpine:3.8

RUN apk add --update --no-cache \
  ca-certificates \
  coreutils \
  ncurses \
  procps \
  bash \
  python3 \
  jq      \
  openssl \
  pcre \
  lame \
  libogg \
  libass \
  libvpx \
  libvorbis \
  libwebp \
  libtheora \
  opus \
  rtmpdump \
  x264-dev \
  x265-dev

COPY --from=build-nginx /usr/local/nginx /usr/local/nginx
COPY --from=build-ffmpeg /usr/local /usr/local
COPY --from=build-ffmpeg /usr/lib/libfdk-aac.so.2 /usr/lib/libfdk-aac.so.2
COPY --from=build-ffmpeg /HLS_XMLTV /opt/HLS_XMLTV

ENV PATH "${PATH}:/usr/local/nginx/sbin"
COPY nginx.conf /etc/nginx/nginx.conf
COPY mime.types /etc/nginx/mime.types
COPY run.sh /run.sh
RUN chmod +x /run.sh
RUN mkdir -p /opt/data && mkdir -p /var/www/html/streams && mkdir -p /var/www/html/xmltv

RUN ln -sf /dev/null /usr/local/nginx/logs/access.log


ENV HOME_DIR=/opt/HLS_XMLTV    \
    PYTHON=python3 \
    CACHE_DIR=/opt/HLS_XMLTV/cache    \
    CONCAT_LIST_DIR=/opt/HLS_XMLTV/concat_lists  \
    CHANNELS_DIR=/opt/HLS_XMLTV/channels \
    PLUGIN_DIR=/opt/HLS_XMLTV/plugins \ 
    TMP_DIR=/tmp   \
    XMLTV_DIR=/var/www/html/xmltv \
    STREAM_DIR=/var/www/html/streams \
    M3U_DIR=/var/www/html \
    PID_DIR=/tmp/hxhb/pid \
    TMP_TVLISTS_DIR=/tmp/hxhb/tv_lists \
    FFMPEG_LOG_DIR=/tmp/hxhb/logs/ffmpeg  \
    EPG_LOG_DIR=/tmp/hxhb/logs/epg \
    CACHE_SPLITTER_LOG_DIR=/tmp/hxhb/logs/cache_splitter \
    CLEAN_STREAM_DIR=OFF \
    STREAM_CLEANUP_TIME=5 \
    XMLTV_HTTP_DIR=http://192.168.1.214/xmltv \
    STREAM_HTTP_DIR=http://192.168.1.214/streams \
    M3U_HTTP_DIR=http://192.168.1.214 \
    FFMPEG_BIN_LOCATION=/usr/local/bin/ffmpeg \
    FFPROBE_BIN_LOCATION=/usr/local/bin/ffprobe \
    HLS_TIME=10 \
    HLS_LIST_SIZE=6


RUN chmod +x /opt/HLS_XMLTV/cron.sh && \
    chmod +x /opt/HLS_XMLTV/clear_cache.sh && \
    chmod +x /opt/HLS_XMLTV/generate_epg.sh && \
    chmod +x /opt/HLS_XMLTV/kill_stream.sh && \
    chmod +x /opt/HLS_XMLTV/plugins/randomize.sh && \
    chmod +x /opt/HLS_XMLTV/plugins/randomize_idents_only.sh && \
    chmod +x /opt/HLS_XMLTV/plugins/split_finished_cache_file.sh && \
    chmod +x /opt/HLS_XMLTV/plugins/xmltv-join && \
    chmod +x /opt/HLS_XMLTV/stream_laucher.sh && \
    mkdir -p -m777 $FFMPEG_LOG_DIR && \
    mkdir -p -m777 $EPG_LOG_DIR && \ 
    mkdir -p -m777 $PID_DIR && \ 
    mkdir -p -m777 $TMP_TVLISTS_DIR && \
    mkdir -p -m777 $CACHE_SPLITTER_LOG_DIR






EXPOSE 80

VOLUME /opt/HLS_XMLTV/



ENTRYPOINT ["/bin/bash", "-c", "/run.sh"]



