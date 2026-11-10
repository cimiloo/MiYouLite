#!/bin/bash
# 在 ubuntu-22.04 runner 上准备 theos + iOS toolchain + SDK
set -o pipefail
FAIL=0

echo "===== 系统 ====="
cat /etc/os-release | head -3

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
if [ ! -d "$THEOS/makefiles" ]; then
  git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS" || { echo "theos 克隆失败"; exit 10; }
fi
echo "THEOS=$THEOS" >> "$GITHUB_ENV"
ls "$THEOS/makefiles" | head -3

echo "===== iOS toolchain ====="
mkdir -p "$THEOS/toolchain"
if ! ls -d "$THEOS"/toolchain/*/ >/dev/null 2>&1; then
  echo "下载 swift toolchain ..."
  wget --no-verbose -O /tmp/tc.tar.xz \
    https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu22.04.tar.xz
  echo "下载结果: $? 大小: $(stat -c%s /tmp/tc.tar.xz 2>/dev/null) 字节"
  tar -xf /tmp/tc.tar.xz -C "$THEOS/toolchain" || { echo "toolchain 解压失败"; FAIL=1; }
else
  echo "toolchain 已存在，跳过"
fi
echo "-- toolchain 内容 --"
find "$THEOS/toolchain" -maxdepth 2 -type d | head -10

echo "===== iOS SDK ====="
mkdir -p "$THEOS/sdks"
if ! ls "$THEOS"/sdks/*.sdk >/dev/null 2>&1; then
  echo "稀疏检出 iPhoneOS16.5.sdk ..."
  rm -rf /tmp/sdksrepo
  git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git /tmp/sdksrepo || { echo "SDK 仓库克隆失败"; FAIL=1; }
  if [ -d /tmp/sdksrepo ]; then
    ( cd /tmp/sdksrepo && git sparse-checkout set iPhoneOS16.5.sdk ) || { echo "稀疏检出失败"; FAIL=1; }
    du -sh /tmp/sdksrepo/iPhoneOS16.5.sdk 2>/dev/null || true
    cp -R /tmp/sdksrepo/iPhoneOS16.5.sdk "$THEOS/sdks/" || { echo "SDK 拷贝失败"; FAIL=1; }
  fi
else
  echo "SDK 已存在，跳过"
fi
echo "-- SDK 列表 --"
ls "$THEOS/sdks"

echo "===== ldid ====="
if ! command -v ldid >/dev/null; then
  wget --no-verbose -O /tmp/ldid https://github.com/ProcursusTeam/ldid/releases/latest/download/ldid_linux_x86_64 || true
  if [ -s /tmp/ldid ]; then
    chmod +x /tmp/ldid && sudo mv /tmp/ldid /usr/local/bin/ldid && echo "ldid 已安装"
  else
    echo "warn ldid 未装上（TrollStore 侧会重新签名，不影响）"
  fi
else
  echo "ldid 已存在"
fi

echo "===== 工具检查 ====="
for c in clang make ldid; do printf "%-8s " "$c"; command -v "$c" || echo "（缺失）"; done
find "$THEOS/toolchain" -name "ld64*" 2>/dev/null | head -3

if [ "$FAIL" != "0" ]; then echo "===== SETUP FAILED ====="; exit 20; fi
echo "===== SETUP DONE ====="
