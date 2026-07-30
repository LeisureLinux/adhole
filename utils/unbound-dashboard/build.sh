#!/bin/bash
# 自动更新版本号并编译

# 读取当前版本号
VERSION=$(grep 'const Version' cmd/main.go | sed 's/.*"\(.*\)".*/\1/')
echo "当前版本: $VERSION"

# 解析版本号 x.y.z.timestamp
IFS='.' read -r MAJOR MINOR PATCH TIMESTAMP <<< "$VERSION"

# 更新 patch 版本
NEW_PATCH=$((PATCH + 1))

# 生成新的时间戳
NEW_TIMESTAMP=$(date +%Y%m%d%H%M%S)

# 新版本号
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}.${NEW_TIMESTAMP}"
echo "新版本: $NEW_VERSION"

# 更新 main.go 中的版本号
sed -i "s/const Version = \".*\"/const Version = \"$NEW_VERSION\"/" cmd/main.go

# 清理缓存
rm -rf /tmp/.gocache bins/unbound-dashboard-arm64

# 编译 ARM64 版本
echo "正在编译 ARM64 版本..."
GOOS=linux GOARCH=arm64 CGO_ENABLED=1 \
  CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ \
  GOCACHE=/tmp/.gocache \
  go build -o bins/unbound-dashboard-arm64 ./cmd/

if [ $? -eq 0 ]; then
  echo "✅ 编译成功!"
  ls -lh bins/unbound-dashboard-arm64
  md5sum bins/unbound-dashboard-arm64
else
  echo "❌ 编译失败!"
  exit 1
fi
