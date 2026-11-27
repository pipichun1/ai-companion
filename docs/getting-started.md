# 快速上手

两条路，先挑一条走通，再考虑要不要升级。

---

## 路线 A：先试试软件（不用服务器、不用域名）

最快，10 分钟能看到效果。

### 1. 装 App

去 [Releases](https://github.com/pipichun1/dafeiyu-apk/releases) 下载最新 APK。

国内下载慢的话，在地址前面加镜像：

```
https://gh-proxy.com/ + 原地址
https://ghfast.top/  + 原地址
```

### 2. 准备一个模型 key

随便挑一家，都有免费额度：

| 服务商 | 接口地址 | 模型名 | 拿 key |
| --- | --- | --- | --- |
| 智谱 | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-flash`（免费）/ `glm-4.5-air` | bigmodel.cn |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` | platform.deepseek.com |
| 通义 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-flash` | dashscope.aliyun.com |
| Kimi | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` | platform.moonshot.cn |

### 3. 建一个会话

```
打开 App → 右下角 + → 起个名字
→ 打开「使用其他模型的接口」
→ 填 接口地址 / 密钥 / 点右边刷新按钮选模型
→ 人设（可选，写一段它该怎么说话）
→ 创建
```

### 4. 能聊了

这一层没有记忆、没有主动消息，人格只是一段 system prompt。
想验证"这个 App 好不好用"够了。

---

## 路线 B：完整版（人格 + 记忆 + 多会话托管）

需要一台能跑 AstrBot 的机器（家里的旧电脑、NAS、云服务器都行）。

### 1. 装 AstrBot

按它官方文档装好，配好至少一个模型服务。

### 2. 装两个插件

把本仓库的 `plugins/openai_bridge` 和 `plugins/webchat_bridge`
放进 AstrBot 的数据目录：

```bash
cp -r plugins/openai_bridge   /AstrBot/data/plugins/
cp -r plugins/webchat_bridge  /AstrBot/data/plugins/
```

或者直接让你的 AI agent 读 [`AGENTS.md`](../AGENTS.md) 自动完成。

### 3. 写人格

```bash
sed -n '1,200p' plugins/webchat_bridge/config.example.json \
  > /AstrBot/data/webchat_bridge.json

cat > /AstrBot/data/memories/companion-persona.md <<'EOF'
你叫小满，说话很轻，句子不长。

- 不用敬语
- 不知道就说不知道
- 偶尔反问一句
EOF
```

然后把 `webchat_bridge.json` 里的 `persona_file` 改成 `companion-persona.md`。

### 4. 重启并验证

```bash
docker restart astrbot

BRIDGE_URL=https://你的地址 BRIDGE_TOKEN=后台令牌 \
  bash scripts/check.sh /AstrBot/data
```

退出码 0 就是通了。

### 5. App 里连

```
设置 → 连接 → 填地址和令牌 → 点「检查服务器」
看到两行 ✅ 就对了
```

详细排错见 [`astrbot-setup.md`](astrbot-setup.md)。

---

## 没有域名怎么办

真正的门槛不是域名，是**手机能不能用 HTTPS 访问到你的服务**。
安卓 9 以后默认禁止明文 HTTP，所以需要一个 https 地址。

按你的条件挑：

| 你的情况 | 方案 | 成本 |
| --- | --- | --- |
| 有公网 IP | Cloudflare Tunnel（推荐） | 免费 |
| 有公网 IP + 端口 | 买个便宜域名 + 免费证书 | 十几块/年 |
| 没有公网 IP | Cloudflare Tunnel（不用开端口） | 免费 |
| 只在自己家 Wi-Fi 用 | 内网地址 + 允许明文，或 Tailscale | 免费 |

### Cloudflare Tunnel（最常用）

```bash
# 装一次
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared

# 临时试用（每次重启域名会变）
cloudflared tunnel --url http://127.0.0.1:6185

# 长期用（需要 Cloudflare 账号，域名可绑也可以不绑）
cloudflared tunnel login
cloudflared tunnel create astrbot
cloudflared tunnel route dns astrbot astrbot.你的域名
cloudflared tunnel run astrbot
```

### Tailscale（双方都在内网）

```bash
# 服务器和手机都装 Tailscale，登录同一账号
# 然后在 App 里填服务器的 Tailscale IP，例如 http://100.x.x.x:6185
```

⚠️ 这种情况是明文 HTTP，安卓可能拦截。要么用 Tailscale 的 HTTPS 功能，
要么接受"只在家里用"。

---

## 常见问题

**装完 App 打不开 / 闪退**

```
看一下安卓版本，需要 Android 8 以上
```

**填完地址点创建，报 401**

```
key 不对。注意有些 key 是"前缀.后缀"两段，复制全了
```

**检查服务器报 404**

```
插件没装好，或地址少了 /api/v1/plugins/extensions 这一段
```

**能聊，但人格不生效**

```
webchat_bridge 没装，或者 webchat_bridge.json 里 persona_file 名字不对
```

**聊几句就忘了前面说的**

```
路线 A 本来就没有记忆；想要记忆请走路线 B
```

---

## 我该选哪条

```
只想试试 ─────────────► 路线 A
想要"她记得我" ────────► 路线 B
想开源给别人用 ────────► 路线 B + 自己写人格与文档
```
