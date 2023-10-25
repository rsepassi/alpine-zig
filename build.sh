#!/bin/sh
# Called from build.zig

exec >/dev/null 2>&1

set -e

BWRAP_BIN=$1
ALPINE_TAR=$2
APK_CACHE_DIR=$3
BUILD_DIR=$4
SCRATCH_DIR=$5
OUT_DIR=$6

# Remaining args go to build script
shift 6
EXTRA_ARGS="$@"

mkdir -p $APK_CACHE_DIR
mkdir -p $SCRATCH_DIR
mkdir -p $OUT_DIR

# Extract Alpine rootfs
rootfs=$SCRATCH_DIR/rootfs
mkdir -p $rootfs
tar xf $ALPINE_TAR -C $rootfs

# Copy user build directory so that intermediates don't pollute
build_dir_cp=$SCRATCH_DIR/build
cp -r $BUILD_DIR $SCRATCH_DIR/
mv $SCRATCH_DIR/$(basename $BUILD_DIR) $SCRATCH_DIR/build

# Either copy resolv.conf from the host or create a simple one
if [ -f "/etc/resolv.conf" ]
then
  cp /etc/resolv.conf $SCRATCH_DIR/resolv.conf
else
  cat << EOF > $SCRATCH_DIR/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi

# Run build in the sandbox
$BWRAP_BIN \
  --chdir /root/build \
  --bind $rootfs / \
  --bind $APK_CACHE_DIR /etc/apk/cache \
  --bind $build_dir_cp /root/build \
  --ro-bind $SCRATCH_DIR/resolv.conf /etc/resolv.conf \
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

# Clean up
rm -rf $SCRATCH_DIR/*
