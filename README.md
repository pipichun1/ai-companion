# AI 伴侣客户端

一个 Flutter 写的自托管 AI 伴侣客户端：多会话、多人格、每会话独立外观、相册。

可以连自己的 AstrBot（完整人格与记忆），也可以直连任意 OpenAI 兼容模型。

## 目录

```
app/                     Flutter 客户端
plugins/openai_bridge/   OpenAI 兼容层（对话、模型列表、人格列表、会话管理）
plugins/webchat_bridge/  人格与记忆注入
scripts/                 install / check / uninstall
docs/                    接入手册、已知限制、自测报告
AGENTS.md                给 AI agent 的部署手册
```

## 特性

```
多会话        每个会话独立人格、独立外观（头像/背景/配色）
流式回复      逐字显示，断网自动重试
直连模型      任意 OpenAI 兼容服务，会话级配置，可自定人设
AstrBot 接入  人格、记忆、上下文压缩、多会话托管
相册          收藏、批量导入、按来源筛选、设为会话外观
她的小动作    自己换头像/背景（可关、一天一次、带提示）
细节          震动反馈、拖动排序、引用、搜索、毛玻璃
```

---

> 想让 AI agent 陪着一个不懂技术的人从头装好？给它读 [`docs/onboarding.md`](docs/onboarding.md)。

## 先看这个

新手从 [`docs/getting-started.md`](docs/getting-started.md) 开始：

```
想先试试 ───────────► 路线 A：装 App + 填模型 key，不用服务器
想要人格与记忆 ─────► 路线 B：自己搭 AstrBot + 装两个插件
没有域名怎么办 ─────► 文档里有 Cloudflare Tunnel 等三种方案
```

## 两种用法

**直连模型（最轻）**

```
装 App → 新建对话 → 打开「使用其他模型的接口」
填 地址 / 密钥 / 模型名 / 人设（可选）→ 就能聊
```

不需要服务器，不需要注册账号。缺点：没有记忆，人设只是一段 system prompt。

**接自己的 AstrBot（完整）**

```
App → 你的域名 → AstrBot → 模型
人格、记忆、多会话、上下文压缩全部由 AstrBot 负责
```

需要两个插件：`openai_bridge`（暴露 OpenAI 兼容接口）+ `webchat_bridge`（注入人格与记忆）。

---

## 部署（给 agent 看的版本）

把仓库交给你的 AI agent，说：

```
按 AGENTS.md 部署
```

`AGENTS.md` 里写好了前置检查、四步操作、每步的验证命令和失败处理。

## 部署（人看的版本）

```bash
# 1. 找到 AstrBot 数据目录（宿主机路径）
docker inspect astrbot --format '{{range .Mounts}}{{.Source}} => {{.Destination}}{{"\n"}}{{end}}'
# 找到 "=> /AstrBot/data" 那一行左边的路径，记作 $DATA

# 2. 装插件
bash scripts/install.sh "$DATA"

# 3. 配人格
cp plugins/webchat_bridge/config.example.json "$DATA/webchat_bridge.json"
# 编辑 persona_file，指向 $DATA/memories/ 下的 md 文件

# 4. 重启并验证
docker restart astrbot
BRIDGE_URL=https://你的域名 BRIDGE_TOKEN=后台令牌 bash scripts/check.sh "$DATA"
```

`check.sh` 退出码为 0 即部署成功。

详细说明见 [`docs/astrbot-setup.md`](docs/astrbot-setup.md)。

---

## 目录

```
plugins/openai_bridge/    OpenAI 兼容层（对话、模型列表、人格列表、会话管理）
plugins/webchat_bridge/   人格与记忆注入
scripts/                  install / check / uninstall
docs/astrbot-setup.md     接入手册
AGENTS.md                 agent 操作手册
```

---

## 边界

- 仓库里不含任何人的**人格、记忆、聊天记录、密钥**
- 插件只读取你 `$DATA` 下的文件，不改数据库结构
- `uninstall.sh` 可完整回滚

## 许可

待定。
