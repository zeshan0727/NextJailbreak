#!/bin/bash
set -euo pipefail

# Install unmodified LGPL-compatible FFmpegKit min 8.1.2 frameworks.
# The original MediaConvert IPA is NOT used as a binary source.
DEST="NextCast/Vendor/FFmpeg"
mkdir -p "$DEST"
RELEASE="https://github.com/sk3llo/ffmpeg_kit_flutter/releases/download/8.1.2-min"

if [ ! -d "$DEST/ffmpegkit.xcframework" ]; then
  echo "Installing ffmpegkit 8.1.2..."
  tmp="$(mktemp -d)"
  curl --fail --location --retry 5 --retry-delay 5 --connect-timeout 30 \
       "$RELEASE/ffmpegkit.xcframework.zip" --output "$tmp/ffmpegkit.zip"
  echo "3758f051a89f67442eeb17aa9f2e0aa3386a966338deb09dd2e6769aba4b7972  $tmp/ffmpegkit.zip" | shasum -a 256 -c -
  unzip -q "$tmp/ffmpegkit.zip" -d "$DEST"
  test -d "$DEST/ffmpegkit.xcframework"
  rm -rf "$tmp"
fi
if [ ! -d "$DEST/libavcodec.xcframework" ]; then
  echo "Installing libavcodec 8.1.2..."
  tmp="$(mktemp -d)"
  curl --fail --location --retry 5 --retry-delay 5 --connect-timeout 30 \
       "$RELEASE/libavcodec.xcframework.zip" --output "$tmp/libavcodec.zip"
  echo "1e43d72539bbf0fc99fc74b451763dddcdd6aa0cc6ae7d5c9e144a31de2b6cfc  $tmp/libavcodec.zip" | shasum -a 256 -c -
  unzip -q "$tmp/libavcodec.zip" -d "$DEST"
  test -d "$DEST/libavcodec.xcframework"
  rm -rf "$tmp"
fi
if [ ! -d "$DEST/libavdevice.xcframework" ]; then
  echo "Installing libavdevice 8.1.2..."
  tmp="$(mktemp -d)"
  curl --fail --location --retry 5 --retry-delay 5 --connect-timeout 30 \
       "$RELEASE/libavdevice.xcframework.zip" --output "$tmp/libavdevice.zip"
  echo "127f9e5290b8e5125a402c9c99482e731ed670c93ec0babf777e4af8274b703c  $tmp/libavdevice.zip" | shasum -a 256 -c -
  unzip -q "$tmp/libavdevice.zip" -d "$DEST"
  test -d "$DEST/libavdevice.xcframework"
  rm -rf "$tmp"
fi
if [ ! -d "$DEST/libavfilter.xcframework" ]; then
  echo "Installing libavfilter 8.1.2..."
  tmp="$(mktemp -d)"
  curl --fail --location --retry 5 --retry-delay 5 --connect-timeout 30 \
       "$RELEASE/libavfilter.xcframework.zip" --output "$tmp/libavfilter.zip"
  echo "81ac35ca0961cfc41dd910963b00582e956c0c6ba8f0d49cd6d355ce9f9c840b  $tmp/libavfilter.zip" | shasum -a 256 -c -
  unzip -q "$tmp/libavfilter.zip" -d "$DEST"
  test -d "$DEST/libavfilter.xcframework"
  rm -rf "$tmp"
fi
if [ ! -d "$DEST/libavformat.xcframework" ]; then
  echo "Installing libavformat 8.1.2..."
  tmp="$(mktemp -d)"
  curl --fail --location --retry 5 --retry-delay 5 --connect-timeout 30 \
       "$RELEASE/libavformat.xcframework.zip" --output "$tmp/libavformat.zip"
  echo "2996af84ac2de0c782bc407e794ce51b14269b34f832c9b76554d1b31b8ec1d2  $tmp/libavformat.zip" | shasum -a 256 -c -
  unzip -q "$tmp/libavformat.zip" -d "$DEST"
  test -d "$DEST/libavformat.xcframework"
  rm -rf "$tmp"
fi
if [ ! -d "$DEST/libavutil.xcframework" ]; then
  echo "Installing libavutil 8.1.2..."
  tmp="$(mktemp -d)"
  curl --fail --location --retry 5 --retry-delay 5 --connect-timeout 30 \
       "$RELEASE/libavutil.xcframework.zip" --output "$tmp/libavutil.zip"
  echo "a1ecbd41172995f3303f71b1486683e5cd47aeb28c58038873d11ec3fdbb6674  $tmp/libavutil.zip" | shasum -a 256 -c -
  unzip -q "$tmp/libavutil.zip" -d "$DEST"
  test -d "$DEST/libavutil.xcframework"
  rm -rf "$tmp"
fi
if [ ! -d "$DEST/libswresample.xcframework" ]; then
  echo "Installing libswresample 8.1.2..."
  tmp="$(mktemp -d)"
  curl --fail --location --retry 5 --retry-delay 5 --connect-timeout 30 \
       "$RELEASE/libswresample.xcframework.zip" --output "$tmp/libswresample.zip"
  echo "f1465f88a72da4093ab1edb6cccd5e5d27ad7e00afb9227b2d290d85ed53814d  $tmp/libswresample.zip" | shasum -a 256 -c -
  unzip -q "$tmp/libswresample.zip" -d "$DEST"
  test -d "$DEST/libswresample.xcframework"
  rm -rf "$tmp"
fi
if [ ! -d "$DEST/libswscale.xcframework" ]; then
  echo "Installing libswscale 8.1.2..."
  tmp="$(mktemp -d)"
  curl --fail --location --retry 5 --retry-delay 5 --connect-timeout 30 \
       "$RELEASE/libswscale.xcframework.zip" --output "$tmp/libswscale.zip"
  echo "da2802037839a59b6cba113dc923f4565de7d2fdf384f84d2a3503c2a299a363  $tmp/libswscale.zip" | shasum -a 256 -c -
  unzip -q "$tmp/libswscale.zip" -d "$DEST"
  test -d "$DEST/libswscale.xcframework"
  rm -rf "$tmp"
fi

echo "FFmpeg 8.1.2 min XCFrameworks present:"
find "$DEST" -maxdepth 1 -type d -name '*.xcframework' -print | sort
