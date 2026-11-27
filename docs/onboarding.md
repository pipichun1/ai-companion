# 给 agent 的引导剧本：帮一个人用上这个 App

> 遇到报错先翻 [	roubleshooting.md](troubleshooting.md)，别靠猜。

你的角色：**陪一个不太懂技术的人，从零到能用**。全程你说、他做。
他看不到代码，也不知道 GitHub 是什么。

先做判断，再走对应的路。不要一上来就讲技术细节。

---

## 第 0 步：先问三个问题

```
1. 你手机是安卓还是 iPhone？
2. 你手上有没有一台一直开着的电脑或服务器？（NAS、云服务器、旧笔记本都算）
3. 你希望她"记得你说过的话、会主动找你"，还是先随便聊聊就行？
```

按答案分流：

| 情况 | 走哪条 |
| --- | --- |
| iPhone | **停止**，说明只有安卓版 |
| 想"记得我" + 有常开的机器 | **路径 B：自建 AstrBot** |
| 想"记得我" + 没有机器 | 先走 **A**，之后想升级再谈 B（B 必须有机器） |
| 随便聊聊 / 只想知道好不好用 | **路径 A：API 直连** |

两个路径都要先装 App，先做第 1 步。

---

## 第 1 步（两条路都要）：装 App

让他用手机浏览器打开（原样发，别改）：

```
https://gh-proxy.com/https://github.com/pipichun1/dafeiyu-apk/releases/download/v1.35.5/dafeiyu-1.35.5.apk
```

下载不动就换备用：

```
https://ghfast.top/https://github.com/pipichun1/dafeiyu-apk/releases/download/v1.35.5/dafeiyu-1.35.5.apk
```

安装时系统会拦「未知来源」，告诉他：

```
点"仍然安装"，这是没上架商店的包，正常
```

**完成标志**：桌面有图标，能打开。

---

## 路径 A：API 直连（快，没记忆）

### A1. 拿一个 key

推荐智谱（有免费额度、国内直连）：

```
1. https://open.bigmodel.cn
2. 手机号注册 + 验证码
3. 按提示实名（身份证 + 刷脸）
4. 左侧「API Keys」→ 新建 → 复制
```

⚠️ key 形如 `xxxxxxxx.xxxxxxxx`，**中间有个点，两段都要**。
只复制一半会报 401，这是最常见的坑。

其他可选：

| 服务 | 接口地址 | 模型名 |
| --- | --- | --- |
| 智谱 | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-flash`（免费） |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| 通义 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-flash` |
| Kimi | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` |

### A2. 建对话（一次只说一步）

```
1. 打开 App，点右下角 "+"
2. 第一栏随便起个名，比如"小助手"
3. 打开"使用其他模型的接口"开关
4. 三个框：
   接口地址 → https://open.bigmodel.cn/api/paas/v4
   密钥     → 粘贴 key
   模型名   → 点右边刷新图标，从列表里选 glm-4-flash
5. 人设可以先空着，点"创建"
```

### A3. 验证

```
打一句"你好"
```

成功 = 她回话，而且是逐段出现，不是长时间空白。

排错：

| 现象 | 原因 | 修法 |
| --- | --- | --- |
| 401 | key 不完整 | 重新复制，别漏点后面那半段 |
| 404 | 地址写错 | 检查 `/v4`、`/v1` 有没有漏 |
| 一直转圈 | 网络 | 关掉 VPN 再试 |
| "没有收到回复" | 模型名不对 | 用刷新按钮重新选 |

**到这里路径 A 就结束了。** 告诉他：这条路的她不会记得前面聊过什么，
想要"记得"就得走 B。

---

## 路径 B：自建 AstrBot（有记忆、有性格）

前提：他有一台常开的机器，能装 Docker。没有就别走这条。

先确认：

```bash
docker --version
```

没有 docker 就先教他装（这一步由他在机器上执行，你给命令）。

### B1. 装 AstrBot

```bash
mkdir -p /opt/astrbot/data
docker run -d --name astrbot \
  -p 6185:6185 \
  -v /opt/astrbot/data:/AstrBot/data \
  --restart unless-stopped \
  soulter/astrbot:latest
```

装完让他打开 `http://机器IP:6185`，默认账号 `astrbot` / `astrbot`，
进去后先改密码，再在「模型服务」里配一个 provider（key 同上）。

### B2. 装两个插件

```bash
git clone https://github.com/pipichun1/ai-companion /tmp/ac
cp -r /tmp/ac/plugins/openai_bridge  /opt/astrbot/data/plugins/
cp -r /tmp/ac/plugins/webchat_bridge /opt/astrbot/data/plugins/
cp /tmp/ac/plugins/webchat_bridge/config.example.json /opt/astrbot/data/webchat_bridge.json
docker restart astrbot
```

### B3. 写人格

```bash
mkdir -p /opt/astrbot/data/memories
cat > /opt/astrbot/data/memories/companion-persona.md <<'EOF'
你叫小满，说话很轻，句子不长。

- 不用敬语
- 不知道就说不知道
- 偶尔反问一句
EOF
```

然后确认 `webchat_bridge.json` 里 `persona_file` 是 `companion-persona.md`。

### B4. 弄一个手机能访问的地址

他没域名也没公网 IP 也没关系，用 Cloudflare Tunnel：

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared
cloudflared tunnel --url http://127.0.0.1:6185
```

它会打印一个 `https://xxx.trycloudflare.com` 地址。
⚠️ 这个地址每次重启都会变，适合先试用。

### B5. 验证

```bash
cd /tmp/ac
BRIDGE_URL=https://那个地址 BRIDGE_TOKEN=后台令牌 bash scripts/check.sh /opt/astrbot/data
```

退出码 0 = 通了。输出里应该有两行 ✅。

### B6. App 里连

```
设置 → 连接 → 填地址和令牌 → 点「检查服务器」
看到两行 ✅ → 保存 → 新建对话 → 会列出人格 → 选一个
```

---

## 收尾：让他试着玩，并收集反馈

告诉他这些操作：

```
- 长按消息：引用 / 复制 / 复制全部 / 删除
- 长按文字本身：可以拖选一段再复制
- 主页长按对话卡片：拖动排序
- 卡片右侧 "⋯"：改名、换头像、换背景、删除
- 设置 → 主题：换配色和主页背景
```

问三个问题：

```
1. 有没有哪一步不知道点哪里？
2. 有没有哪句话看不懂？
3. 最别扭的地方是什么？
```

---

## 你能做的 / 不能做的

**可以**

- 一步步告诉他点哪、填什么
- 解释报错
- 在他的机器上执行命令（如果他授权）
- 帮他写一段人设

**不可以**

- 替他注册账号（要验证码和实名）
- 索要他的 API key「帮他填」——让他自己粘贴
- 让他把 key 发到群里或贴到公开地方
- 建议他关掉服务器防火墙还把端口暴露到公网（优先用 Cloudflare Tunnel）
