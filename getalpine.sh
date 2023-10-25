#!/bin/sh

set -e

# SYNC alpine_version_str
version=3.18.4

podman export $(podman create --platform=linux/arm64 alpine:$version) | gzip -9 > alpine-aarch64.tar.gz
podman export $(podman create --platform=linux/amd64 alpine:$version) | gzip -9 > alpine-x86_64.tar.gz
podman export $(podman create --platform=linux/arm alpine:$version) | gzip -9 > alpine-arm.tar.gz
podman export $(podman create --platform=linux/386 alpine:$version) | gzip -9 > alpine-x86.tar.gz
