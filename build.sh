#!/bin/sh
set -e

exec > /dev/null 2>&1


BWRAP_BIN=$1
ALPINE_TAR=$2
APK_CACHE_DIR=$3
BUILD_DIR=$4
SCRATCH_DIR=$5
OUT_DIR=$6
shift 6
EXTRA_ARGS="$@"
echo "extra: $EXTRA_ARGS"

mkdir -p $APK_CACHE_DIR
mkdir -p $SCRATCH_DIR
mkdir -p $OUT_DIR

rootfs=$SCRATCH_DIR/rootfs
mkdir -p $rootfs
tar xf $ALPINE_TAR -C $rootfs

$BWRAP_BIN \
  --chdir / \
  --bind $rootfs / \
  --bind $APK_CACHE_DIR /etc/apk/cache \
  --ro-bind $BUILD_DIR /root/build \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --unshare-all \
  --share-net \
  --die-with-parent \
  --dev /dev \
  --proc /proc \
  --uid 0 \
  --gid 0 \
  --clearenv \
  --setenv HOME /root \
  --setenv USER root \
  --setenv PATH "/sbin:/usr/sbin:/bin:/usr/bin" \
  --bind $OUT_DIR /zig-out \
  /root/build/build "$EXTRA_ARGS"
