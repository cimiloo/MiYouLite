#!/bin/bash
# 在 ubuntu runner 上准备 theos + iOS toolchain + SDK，用于交叉编译 iOS app
set -e
echo "== 1. apt 依赖 =="
sudo apt-get update -y
sudo apt-get install -y build-essential fakeroot rsync curl perl zip git \
  libxml2 libtinfo6 libz3-dev libplist-utils wget xz-utils unzip

echo "== 2. 克隆 theos =="
export THEOS="$GITHUB_WORKSPACE/theos"
if [ ! -d "$THEOS" ]; then
  git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS"
fi
echo "THEOS=$THEOS" >> "$GITHUB_ENV"

echo "== 3. iOS toolchain =="
mkdir -p "$THEOS/toolchain"
if [ ! -d "$THEOS/toolchain/linux" ] && [ ! -d "$THEOS/toolchain/iphone" ]; then
  wget --no-verbose -O /tmp/swift-toolchain.tar.xz \
    https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu22.04.tar.xz
  ls -la /tmp/swift-toolchain.tar.xz
  tar -xf /tmp/swift-toolchain.tar.xz -C "$THEOS/toolchain"
fi
echo "-- toolchain 目录 --"
ls -la "$THEOS/toolchain" || true

echo "== 4. iOS SDK =="
mkdir -p "$THEOS/sdks"
if [ -z "$(ls -A "$THEOS/sdks")" ]; then
  wget --no-verbose -O /tmp/sdks.zip https://github.com/theos/sdks/archive/master.zip
  mkdir -p /tmp/sdksx
  unzip -q /tmp/sdks.zip -d /tmp/sdksx
  find /tmp/sdksx -maxdepth 2 -name "*.sdk" -type d | head -20
  mv /tmp/sdksx/sdks-master/*.sdk "$THEOS/sdks/" || true
fi
echo "-- SDK 目录 --"
ls "$THEOS/sdks" || true

echo "== 5. 环境检查 =="
which clang || true
clang --version || true
ls "$THEOS/toolchain"/*/bin 2>/dev/null | head -20 || true
echo "DONE"
