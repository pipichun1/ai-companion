#!/usr/bin/env bash
# 安装两个插件到 AstrBot 数据目录。可重复执行。
#
# 用法：
#   bash scripts/install.sh <AstrBot 数据目录>
#   ASTRBOT_DATA=/opt/astrbot/data bash scripts/install.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${1:-${ASTRBOT_DATA:-}}"

die() { echo "错误: $*" >&2; exit 1; }

[ -n "$DATA" ] || die "缺少 AstrBot 数据目录。用法: bash scripts/install.sh <数据目录>"
[ -d "$DATA" ] || die "目录不存在: $DATA"

# 找一个容器名，用于提示重启
CONTAINER=""
if command -v docker >/dev/null 2>&1; then
  CONTAINER="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i astrbot | head -n1 || true)"
fi

echo "==> 数据目录: $DATA"
[ -n "$CONTAINER" ] && echo "==> 容器: $CONTAINER"

mkdir -p "$DATA/plugins" "$DATA/memories"

install_plugin() {
  local name="$1"
  local src="$REPO_ROOT/plugins/$name"
  local dst="$DATA/plugins/$name"

  [ -f "$src/main.py" ] || die "仓库里找不到 plugins/$name/main.py"

  if [ -d "$dst" ]; then
    if [ -f "$dst/backup.tar.gz" ]; then
      rm -f "$dst/backup.tar.gz"
    fi
    tar -czf "$dst/backup.tar.gz" -C "$dst" \
      --exclude=backup.tar.gz . 2>/dev/null || true
    echo "==> 已备份旧版本: $dst/backup.tar.gz"
  fi

  mkdir -p "$dst"
  cp -f "$src"/*.py "$src"/*.yaml "$dst"/ 2>/dev/null || true
  if [ -f "$src/README.md" ]; then
    cp -f "$src/README.md" "$dst"/
  fi
  rm -rf "$dst/__pycache__"
  echo "==> 已安装: $name"
}

install_plugin openai_bridge
install_plugin webchat_bridge

# 配置模板
CONF="$DATA/webchat_bridge.json"
if [ ! -f "$CONF" ]; then
  cp "$REPO_ROOT/plugins/webchat_bridge/config.example.json" "$CONF"
  echo "==> 已生成配置模板: $CONF（记得改 persona_file）"
else
  echo "==> 配置已存在，未改动: $CONF"
fi

echo
echo "完成。下一步："
echo "  1) 确认 $DATA/memories/ 里有你的 persona 文件"
echo "  2) 编辑 $CONF 的 persona_file"
[ -n "$CONTAINER" ] && echo "  3) docker restart $CONTAINER"
echo "  4) bash scripts/check.sh \"$DATA\""
