# webchat_bridge

让 AstrBot 的 WebChat 会话**自动继承人格与记忆**，支持一个账号下并存多个角色。

## 解决的问题

AstrBot 的 ChatUI 每次新建对话都会生成新的 `umo`（形如
`webchat:FriendMessage:webchat!<user>!<uuid>`），而人格绑定和记忆注入是按
`umo` 精确匹配的。结果是：

```
新建一个对话 → 人格回到默认 → 记忆命中不到 → 像换了一个人
```

这个插件在 LLM 请求发出前，按 `umo` 前缀匹配，把指定的人格文件和记忆文件
拼进系统提示词，于是**任何新会话都保持同一个身份**。

## 安装

```bash
# AstrBot 数据目录下
cd /AstrBot/data/plugins
git clone <this-repo> webchat_bridge   # 或直接复制目录
```

重启 AstrBot。日志里出现加载成功即可。

## 配置

配置放在 **AstrBot 数据目录**下的 `webchat_bridge.json`：

```bash
cp config.example.json /AstrBot/data/webchat_bridge.json
```

```json
{
  "enabled": true,
  "prefixes": ["webchat:"],
  "persona_file": "companion-persona.md",
  "memory_files": ["memory-1.md"],
  "marker": "【私人记忆】",
  "sessions": {
    "webchat:FriendMessage:webchat!you!main": {
      "persona_file": "companion-persona.md",
      "memory_files": ["memory-1.md"]
    }
  }
}
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `enabled` | 总开关 |
| `prefixes` | 只对这些 `umo` 前缀生效，默认 `webchat:` |
| `persona_file` | 默认人格文件（相对 `memories/` 目录） |
| `memory_files` | 默认记忆文件列表 |
| `marker` | 记忆段的前缀标记，便于模型区分 |
| `sessions` | 按 `umo` 精确覆盖，实现"一个账号多个角色" |

人格与记忆文件都放在 `<AstrBot 数据目录>/memories/` 下，文件内容就是给模型看的
自然语言文本，没有固定格式。

## 数据目录

默认 `/AstrBot/data`（Docker 官方镜像的路径）。其他部署方式用环境变量覆盖：

```bash
export ASTRBOT_DATA_DIR=/your/astrbot/data
```

## 说明

- 不写数据库，只读配置和文本文件；卸载即恢复原状
- 注入是幂等的：同一段内容不会重复塞进提示词
- 日志会打印每个会话注入的字数和来源
