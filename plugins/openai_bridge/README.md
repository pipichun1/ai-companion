# openai_bridge

把 AstrBot 的会话能力暴露成 **OpenAI 兼容接口**，让任何支持"自定义 API 地址"的
聊天前端（NextChat、LobeChat、自研 App 等）直接接进来。

人格、记忆、上下文压缩、工具调用，统统仍然由 AstrBot 负责。

## 提供的接口

| 方法 | 路径 | 作用 |
| --- | --- | --- |
| POST | `/api/v1/plugins/extensions/v1/chat/completions` | 对话（支持流式） |
| GET | `/api/v1/plugins/extensions/v1/models` | 模型列表 |
| GET | `/api/v1/plugins/extensions/v1/personas` | 人格列表 |
| POST | `/api/v1/plugins/extensions/v1/sessions` | 新建会话 |
| POST | `/api/v1/plugins/extensions/v1/sessions/delete` | 删除会话及其云端记忆 |

鉴权：`Authorization: Bearer <AstrBot 后台令牌>`

## 安装

```bash
cd /AstrBot/data/plugins
git clone <this-repo> openai_bridge
```

改 `metadata.yaml` 里的 `author` 为你自己，然后重启 AstrBot。

## 客户端怎么填

```
接口地址   https://<你的域名>/api/v1/plugins/extensions/v1
密钥       <AstrBot 后台令牌>
模型名     任意（插件只把它当作显示名，真实模型由 AstrBot 的 provider 决定）
```

## 会话与人格怎么对应

每次 `POST /sessions` 会给一个 `conv_id`，插件会：

1. 在 `<数据目录>/webchat_bridge.json` 的 `sessions` 里登记一条
   `umo → persona_file`
2. 之后该 `conv_id` 的对话都走这个人格

所以它和 `webchat_bridge` 是**配套使用**的：

```
openai_bridge   负责"对外接口"和"会话注册"
webchat_bridge  负责"把人格与记忆塞进提示词"
```

只装 `openai_bridge` 也能聊，但人格不会生效。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ASTRBOT_DATA_DIR` | `/AstrBot/data` | AstrBot 数据目录 |
| `BRIDGE_MODEL_ID` | `astrbot` | 返回给客户端的模型名 |

## 说明

- 图片消息会被临时落盘后转交 AstrBot 的多模态流程
- 流式输出会过滤掉 AstrBot 的 token 统计块
- 删除会话会同时清理该会话在数据库里的对话记录与人格映射
