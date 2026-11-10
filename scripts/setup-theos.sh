#!/bin/bash
# 在 ubuntu-22.04 runner 上准备 theos + iOS toolchain + SDK
set -o pipefail

echo "===== 系统 ====="
cat /etc/os-release | head -3
uname -a

echo "===== apt 依赖 ====="
sudo apt-get update -y > /dev/null 2>&1
for p in build-essential fakeroot rsync curl perl zip git libtinfo5 libtinfo6 \
         libz3-dev libplist-utils wget xz-utils unzip libxml2; do
  if sudo apt-get install -y "$p" > /dev/null 2>&1; then
    echo "ok   $p"
  else
    echo "warn $p 装不上，继续"
  fi
done

echo "===== 克隆 theos ====="
export THEOS="$GITHUB_WORKSPACE/theos"
if [ ! -d "$THEOS" ]; then
  git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS" || exit 10
fi
echo "THEOS=$THEOS" >> "$GITHUB_ENV"
ls "$THEOS/makefiles" | head -5

echo "===== iOS toolchain ====="
mkdir -p "$THEOS/toolchain"
if [ -z "$(ls -A "$THEOS/toolchain" 2>/dev/null)" ]; then
  wget --no-verbose -O /tmp/tc.tar.xz \
    https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu22.04.tar.xz \
    || { echo "toolchain 下载失败"; exit 11; }
  tar -xf /tmp/tc.tar.xz -C "$THEOS/toolchain" || { echo "toolchain 解压失败"; exit 12; }
fi
echo "-- toolchain 内容 --"
ls -la "$THEOS/toolchain"

echo "===== iOS SDK ====="
mkdir -p "$THEOS/sdks"
if [ -z "$(ls -A "$THEOS/sdks")" ]; then
  wget --no-verbose -O /tmp/sdks.zip https://github.com/theos/sdks/archive/refs/heads/master.zip \
    || { echo "SDK 下载失败"; exit 13; }
  mkdir -p /tmp/sdksx
  unzip -q /tmp/sdks.zip -d /tmp/sdksx || { echo "SDK 解压失败"; exit 14; }
  mv /tmp/sdksx/*/*.sdk "$THEOS/sdks/" 2>/dev/null || true
fi
echo "-- SDK 列表 --"
ls "$THEOS/sdks"

echo "===== 工具检查 ====="
for c in clang make ldid; do
  printf "%-8s " "$c"
  command -v "$c" || echo "（缺失）"
done
ls "$THEOS/toolchain"/*/bin 2>/dev/null | head -15 || true

echo "===== SETUP DONE ====="
