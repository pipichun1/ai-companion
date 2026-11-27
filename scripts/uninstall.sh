#!/usr/bin/env bash
# 卸载两个插件，恢复部署前状态。可重复执行。
#
# 用法：
#   bash scripts/uninstall.sh <AstrBot 数据目录>
#   bash scripts/uninstall.sh <目录> --purge     # 连配置文件一起删
set -euo pipefail

DATA="${1:-${ASTRBOT_DATA:-}}"
PURGE="${2:-}"

die() { echo "错误: $*" >&2; exit 1; }

[ -n "$DATA" ] || die "缺少 AstrBot 数据目录。用法: bash scripts/uninstall.sh <数据目录>"

for p in openai_bridge webchat_bridge; do
  dst="$DATA/plugins/$p"
  if [ -d "$dst" ]; then
    # 安装时的备份只用于"回到上一版"，不在这里还原
    # 卸载 = 彻底移除，避免用户以为已经删干净、实际还留着一份
    rm -rf "$dst"
    echo "==> 已移除: $p"
  else
    echo "==> $p 本来就不存在"
  fi
done

if [ "$PURGE" = "--purge" ]; then
  rm -f "$DATA/webchat_bridge.json"
  echo "==> 已删除配置文件"
else
  echo "==> 配置文件保留: $DATA/webchat_bridge.json（加 --purge 可删）"
fi

CONTAINER=""
if command -v docker >/dev/null 2>&1; then
  CONTAINER="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i astrbot | head -n1 || true)"
fi

echo
echo "完成。重启 AstrBot 生效："
if [ -n "$CONTAINER" ]; then
  echo "  docker restart $CONTAINER"
else
  echo "  （手动重启你的 AstrBot）"
fi
