#!/usr/bin/env bash
# 验证部署是否成功。可重复执行，成功退出码 0。
#
# 用法：
#   bash scripts/check.sh <AstrBot 数据目录>
#   BRIDGE_TOKEN=xxx BRIDGE_URL=https://你的域名 bash scripts/check.sh <目录>
set -uo pipefail

DATA="${1:-${ASTRBOT_DATA:-}}"
TOKEN="${BRIDGE_TOKEN:-}"
URL="${BRIDGE_URL:-}"
FAIL=0

ok()   { echo "  ✅ $*"; }
bad()  { echo "  ❌ $*"; FAIL=1; }
warn() { echo "  ⚠️  $*"; }

echo "== 1. 插件文件 =="
for p in openai_bridge webchat_bridge; do
  if [ -f "$DATA/plugins/$p/main.py" ]; then
    ok "$p 已安装"
  else
    bad "$p 缺失（期望 $DATA/plugins/$p/main.py）"
  fi
done

echo "== 2. 配置文件 =="
CONF="$DATA/webchat_bridge.json"
if [ -f "$CONF" ]; then
  if python3 -c "import json,sys; json.load(open('$CONF'))" 2>/dev/null; then
    ok "webchat_bridge.json 是合法 JSON"
    PERSONA="$(python3 -c "
import json
c=json.load(open('$CONF'))
print(c.get('persona_file') or '')
" 2>/dev/null)"
    if [ -n "$PERSONA" ]; then
      if [ -f "$DATA/memories/$PERSONA" ]; then
        ok "人格文件存在: $PERSONA"
      else
        bad "人格文件找不到: $DATA/memories/$PERSONA"
      fi
    else
      warn "persona_file 为空 —— 能聊天，但不会有人格"
    fi
  else
    bad "webchat_bridge.json 不是合法 JSON"
  fi
else
  bad "缺少 $CONF（运行 install.sh 生成模板）"
fi

echo "== 3. 容器状态 =="
if command -v docker >/dev/null 2>&1; then
  NAME="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i astrbot | head -n1 || true)"
  if [ -n "$NAME" ]; then
    ok "容器在运行: $NAME"

    # 检查的目录必须就是容器挂载的那个目录，否则装到别处也会"通过"
    MOUNT="$(docker inspect "$NAME" \
      --format '{{range .Mounts}}{{.Source}} => {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null \
      | awk -F' => ' '$2=="/AstrBot/data"{print $1}' | head -n1)"
    if [ -n "$MOUNT" ] && [ -n "$DATA" ]; then
      if [ "$(cd "$DATA" 2>/dev/null && pwd -P)" = "$(cd "$MOUNT" 2>/dev/null && pwd -P)" ]; then
        ok "数据目录与容器挂载一致: $MOUNT"
      else
        bad "你检查的是 $DATA，但容器实际挂载的是 $MOUNT —— 插件装错地方了"
      fi
    else
      warn "没解析到容器挂载目录，跳过一致性检查"
    fi
    if docker logs --tail 300 "$NAME" 2>&1 | grep -q "registered /v1/chat/completions"; then
      ok "日志里已注册 /v1/chat/completions"
    else
      warn "日志里没看到注册记录（可能刚重启，或用的是别的日志级别）"
    fi
  else
    bad "没有找到运行中的 AstrBot 容器"
  fi
else
  warn "没有 docker 命令，跳过容器检查"
fi

echo "== 4. 接口连通性 =="
if [ -z "$URL" ] || [ -z "$TOKEN" ]; then
  warn "未提供 BRIDGE_URL / BRIDGE_TOKEN，跳过（文件检查通过即可先用）"
else
  # 允许用户只填域名，自动补成插件路径
  B="${URL%/}"
  B="${B%/v1}"
  case "$B" in
    */api/v1/plugins/extensions) ;;
    *) B="$B/api/v1/plugins/extensions" ;;
  esac
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    "$B/v1/models" -H "Authorization: Bearer $TOKEN" || echo 000)"
  case "$CODE" in
    200) ok "GET /v1/models → 200" ;;
    401) bad "GET /v1/models → 401（令牌不对）" ;;
    404) bad "GET /v1/models → 404（插件没加载，或路径少了 /api/v1/plugins/extensions）" ;;
    000) bad "连不上 $B（域名/端口/证书）" ;;
    *)   bad "GET /v1/models → $CODE" ;;
  esac

  PCODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    "$B/v1/personas" -H "Authorization: Bearer $TOKEN" || echo 000)"
  if [ "$PCODE" = "200" ]; then
    ok "GET /v1/personas → 200"
  else
    warn "GET /v1/personas → $PCODE（人格列表不可用，但聊天可能仍正常）"
  fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "结果: 通过"
  exit 0
else
  echo "结果: 有失败项，见上面的 ❌"
  exit 1
fi
