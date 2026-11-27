# AGENTS.md

给 AI agent 的操作手册。人是按 `README.md` 装的；如果你是被指派来部署的 agent，
**只按本文件执行**，每一步都要跑验证命令，别跳步。

---

## 目标

在一台**已经跑着 AstrBot** 的机器上：

1. 安装两个插件：`openai_bridge`、`webchat_bridge`
2. 写一份 `webchat_bridge.json`（指向一个人格文件）
3. 重启 AstrBot
4. 让 `scripts/check.sh` 退出码为 0

完成后，用户就能在 App 里填 `https://域名` + 令牌，连上自己的 AstrBot。

---

## 前置检查（全部通过再往下）

```bash
# 1) docker 可用
docker --version

# 2) 找到 AstrBot 容器
docker ps --format '{{.Names}}' | grep -i astrbot

# 3) 找到 AstrBot 数据目录（宿主机路径）
docker inspect astrbot \
  --format '{{range .Mounts}}{{.Source}} => {{.Destination}}{{"\n"}}{{end}}'
```

第 3 步期望看到一行以 `=> /AstrBot/data` 结尾，**记住左边的宿主机路径**，
下文记作 `$DATA`。

如果第 3 步没有任何 `=> /AstrBot/data`，**停止**，把输出贴给用户，
不要猜路径、不要自己建目录。

---

## 步骤

### 1. 安装插件

```bash
export DATA=<上一步的宿主机路径>
bash scripts/install.sh "$DATA"
```

**验证**：

```bash
ls "$DATA/plugins/openai_bridge/main.py" \
   "$DATA/plugins/webchat_bridge/main.py"
```

期望：两行路径都打印出来，没有 "No such file"。

### 2. 配置人格

```bash
ls "$DATA/memories/"
```

- 如果 `webchat_bridge.json` 不存在，`install.sh` 已经放了一份模板
- 如果没有现成的人格文件，创建一个人格文件：

```bash
cat > "$DATA/memories/companion-persona.md" <<'EOF'
你叫小满，说话很轻，句子不长。

- 不用敬语
- 不知道就说不知道
- 偶尔反问一句
EOF
```

然后确认 `$DATA/webchat_bridge.json` 里的 `persona_file` 与文件名一致：

```bash
python3 -c "
import json,sys
c=json.load(open('$DATA/webchat_bridge.json'))
print(c.get('persona_file'))
"
```

期望：打印出 `companion-persona.md`（或用户指定的名字）。

### 3. 重启 AstrBot

```bash
docker restart astrbot
sleep 8
docker logs --tail 200 astrbot 2>&1 | grep -i openai_bridge
```

**验证**：期望看到类似

```
[openai_bridge] registered /v1/chat/completions
```

没有这行 → 见下方「失败处理 / 插件没加载」。

### 4. 检查

```bash
export BRIDGE_TOKEN=<AstrBot 后台令牌>
bash scripts/check.sh "$DATA"
```

`BRIDGE_TOKEN` 是 AstrBot 后台登录后的令牌（一串 `eyJ...` 开头的 JWT，
不是下载用的 access token）。用户没提供就跳过带 ✅ 的接口检查，
只做文件检查，并在报告里注明。

**全部完成判定：`echo $?` 输出 `0`。**

`check.sh` 会核对一件事：你装的目录，是不是容器真正挂载的那个目录。
如果装错地方，它会报：

```
❌ 你检查的是 /xxx，但容器实际挂载的是 /yyy —— 插件装错地方了
```

看到这句就回到步骤 1，用挂载路径重装，别继续往下。

---

## 失败处理

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `install.sh` 报权限错误 | 数据目录属主不是当前用户 | `sudo -E bash scripts/install.sh "$DATA"` |
| 日志里没有 `registered` | 插件目录层级错了 | 确认路径是 `$DATA/plugins/openai_bridge/main.py`，不是多套一层 |
| 日志里有 `ImportError` | AstrBot 版本过旧 | 需要 AstrBot >= 4.29，让用户升级 |
| `check.sh` 报 404 | 插件没加载 | 回到步骤 3，看完整日志 |
| `check.sh` 报 401 | 令牌不对 | 重新从后台复制令牌；注意别带空格 |
| 人格没生效 | `persona_file` 名字不对 | 对比 `$DATA/memories/` 里的真实文件名 |
| 端口不通 | 没有公网入口 | 见 `docs/astrbot-setup.md` 的「没有公网域名怎么办」 |

**任何一步失败，停下来报告，不要连续试错。**

---

## 回滚

```bash
bash scripts/uninstall.sh "$DATA"
```

这会删掉两个插件目录；加 `--purge` 连 `webchat_bridge.json` 一起删。
AstrBot 重启后恢复原状（人格文件和之前的聊天记录不受影响）。

---

## 交付清单（部署成功后必须输出）

任务完成的最后一步，把这三项**原样**报给用户，缺一不可：

```
1. 服务地址
   https://<用户的域名>          ← App 里「服务器地址」填这个

2. 接口令牌
   eyJ...（后台登录令牌）        ← App 里「令牌」填这个

3. 验证结果
   check.sh 退出码 0，并附上最后一段输出
```

同时告诉用户 App 里怎么填：

```
设置 → 连接 → 填入上面两项 → 点「检查服务器」
看到两行 ✅ → 保存 → 新建对话 → 选人格
```

如果**没有公网域名**，第 1 项改成局域网地址，并说明：

```
这个地址只能在家里 Wi-Fi 下用
想在外面用，需要配 Cloudflare Tunnel 或端口映射
```

如果用户还没有 App：

```
去仓库 Releases 下载 APK（不要自己编译，除非用户要求）
```

---

## 边界

- **不要**修改 AstrBot 的模型配置（provider），那是用户自己的事
- **不要**改用户的域名、nginx、证书
- **不要**写入任何密钥到仓库文件
- 只碰 `$DATA/plugins/`、`$DATA/memories/`、`$DATA/webchat_bridge.json` 这三处
