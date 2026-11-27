# 在 AstrBot 上接入

目标：让你的 App（或任何 OpenAI 兼容前端）连上你自己的 AstrBot，
保留人格、记忆和多会话。

## 前置条件

```
1. 一个跑起来的 AstrBot（4.29+）
2. AstrBot 已经配好至少一个模型服务（provider）
3. AstrBot 后台能打开，知道后台令牌
```

## 三步装好

### 1. 放插件

把本仓库的 `plugins/openai_bridge` 和 `plugins/webchat_bridge`
复制进 AstrBot 的数据目录：

```bash
cp -r plugins/openai_bridge   /AstrBot/data/plugins/
cp -r plugins/webchat_bridge  /AstrBot/data/plugins/
```

### 2. 写配置

```bash
cp plugins/webchat_bridge/config.example.json /AstrBot/data/webchat_bridge.json
```

然后编辑它，把人设写进 `persona_file`：

```json
{
  "enabled": true,
  "persona_file": "companion-persona.md",
  "memory_files": [],
  "sessions": {}
}
```

人格文件放在 `/AstrBot/data/memories/` 下：

```bash
cat > /AstrBot/data/memories/companion-persona.md <<'EOF'
你叫小满，说话很轻，句子不长。

- 不用敬语
- 不知道就说不知道
- 偶尔反问一句
EOF
```

### 3. 重启 AstrBot

```bash
docker restart astrbot
```

日志里应该能看到：

```
[openai_bridge] registered /v1/chat/completions
```

## App 里填什么

```
设置 → 连接

服务器地址   https://<你的域名>
令牌         <AstrBot 后台令牌>
```

令牌是 AstrBot 后台登录后拿到的那串 `eyJ...` 开头的字符串（不是下载用的 token）。
在命令行的等价检查：

```bash
BRIDGE_URL=https://<你的域名> BRIDGE_TOKEN=<那串令牌> \
  bash scripts/check.sh <AstrBot 数据目录>
```

填完点 **「检查服务器」**，应该显示：

```
✅ 聊天接口正常
✅ 人格接口正常，共 1 个：小满
```

## 没有公网域名怎么办

三种办法：

```
1. Cloudflare Tunnel（免费，最省事）
2. 有公网 IP 的话直接开端口 + nginx 反代
3. 只在局域网用：填 http://192.168.x.x:6185
```

## 多角色

想在一个 App 里放多个角色，有两种做法：

**A. 多个 AstrBot 人格（推荐）**

在 `webchat_bridge.json` 的 `persona_file` 里放多个人格文件，
App 里新建对话时选不同人格即可。

**B. 不同人会话独立**

在 `sessions` 里按 `umo` 写死各自的 `persona_file` 与 `memory_files`，
适合"一个账号下多个完全独立的关系"。

## 常见问题

**检查服务器报 404**

```
多半是插件没装好，或者路径不对。
正确路径形如：https://域名/api/v1/plugins/extensions/v1/models
```

**能聊，但人格没生效**

```
webchat_bridge 没装，或者 webchat_bridge.json 里的 persona_file 名字不对。
看 AstrBot 日志里有没有 [webchat_bridge] 注入 的记录。
```

**新会话记不住之前的事**

```
记忆是按会话隔离的。
要共享记忆，把同一个 memory_files 写进多个会话的配置。
```

**直连大模型时，第一句话要等很久**

```
那是"思考型"模型在写推理过程，正文要等它想完才出来。
换成非思考型模型即可，首字延迟会明显下降：

  glm-4.5-air / glm-4-flash
  qwen-flash
  deepseek-chat
  gpt-4o-mini

反过来，如果你需要它想清楚再答（写长文、解逻辑题），
再切回 glm-4.6 / deepseek-reasoner 这类。
```
