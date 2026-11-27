# 排错手册

给 agent 用：出错时先看这张表，别猜。

---

## 先做三步诊断

```bash
# 1. 域名/端口通不通（App 里填的地址）
curl -s -o /dev/null -w "%{http_code}\n" https://你的地址/

# 2. 聊天接口通不通（要令牌）
curl -s -o /dev/null -w "%{http_code}\n" \
  https://你的地址/api/v1/plugins/extensions/v1/models \
  -H "Authorization: Bearer 令牌"

# 3. 本地检查（在服务器上）
bash scripts/check.sh /AstrBot/data
```

对照结果：

| 第 1 步 | 第 2 步 | 结论 |
| --- | --- | --- |
| 000 | - | DNS / 端口 / 防火墙 / 隧道 |
| 200 或 404 | 000 | 地址路径不对 |
| 200/404 | 401 | 令牌不对 |
| 200/404 | 404 | 插件没装或没加载 |
| 200/404 | 200 | 服务端没问题，问题在 App 侧 |

---

## 装 App 阶段

**安装时提示"未知来源"**

```
正常。这是没上架应用商店的包，点"仍然安装"。
小米还要在设置里给浏览器/文件管理器"安装未知应用"权限。
```

**安装包下载失败**

```
换镜像：
https://gh-proxy.com/ + 原地址
https://ghfast.top/  + 原地址
```

**打开就闪退**

```
Android 版本低于 8 不支持
```

---

## 路径 A（API 直连）排错

**点创建后报 401**

```
key 不完整。
有些 key 是 "前缀.后缀" 两段，中间有个点，只复制前半段一定 401。
让他回控制台重新复制整串。
```

**报 404**

```
接口地址写错。常见错误：
  少了 /v1 或 /v4
  多了空格
  把 "https://" 一起复制了两遍
```

**一直转圈，最后说"没有收到回复"**

```
模型名不对，或模型不支持这个接口。
用 App 里模型名输入框右边的刷新按钮重新选一个。
```

**转圈很久才出字**

```
选到了"思考型"模型（glm-4.6 / deepseek-reasoner）。
换 glm-4-flash、glm-4.5-air、deepseek-chat 这类非思考模型。
```

**开着 VPN 时很慢**

```
国内模型服务走 VPN 反而绕远，让他关掉 VPN 再试。
```

**聊两句就忘了**

```
路径 A 本来没有记忆，这是设计如此，不是 bug。
要记忆请走路径 B。
```

---

## 路径 B（自建 AstrBot）排错

**check.sh 报「插件缺失」**

```
两个插件目录层级错了。
正确：/AstrBot/data/plugins/openai_bridge/main.py
错误：/AstrBot/data/plugins/openai_bridge/openai_bridge/main.py
```

**check.sh 报「你检查的是 X，但容器实际挂载的是 Y」**

```
装到别的目录去了。
用 docker inspect 找到真正挂载的宿主机路径，重新安装。
```

**check.sh 报 401**

```
令牌不对。注意要的是 AstrBot 后台登录后的令牌（eyJ 开头），
不是下载用的 access token。
```

**check.sh 报 404**

```
插件没加载。看日志：
docker logs --tail 200 astrbot | grep -i openai_bridge
期望看到 "registered /v1/chat/completions"。
没有这行 → 插件目录或版本问题。
```

**能连上，但人格不生效**

```
1. webchat_bridge 装了吗
2. webchat_bridge.json 里的 persona_file 名字对不对
3. 看日志有没有：
   docker logs astrbot | grep webchat_bridge
   期望看到 "[webchat_bridge] 注入 ..."
```

**她不知道"换头像"这类小动作**

```
webchat_bridge.json 里 "actions" 要是 true（默认就是）。
改完必须 docker restart astrbot。
```

**Cloudflare Tunnel 的地址过一会就失效**

```
cloudflared tunnel --url 是临时隧道，重启就变。
长期用改成命名隧道（tunnel create + route dns）。
```

**手机连不上，但电脑浏览器能打开**

```
1. 证书问题：地址必须是 https，http 会被安卓拦
2. 隧道没转发对端口
3. 手机上开着 VPN，先关掉
```

**App 里「检查服务器」两行 ✅ 但新建对话拉不到人格**

```
personas 接口返回空。检查 /AstrBot/data/memories/ 里有没有 .md 文件，
以及 webchat_bridge.json 的 persona_file 是否指向它。
```

---

## 日志在哪

```bash
# AstrBot 全部
docker logs --tail 200 astrbot

# 只看插件相关
docker logs --tail 300 astrbot 2>&1 | grep -Ei "openai_bridge|webchat_bridge|meme_manager"

# 实时跟
docker logs -f astrbot
```

---

## 还是不行时收集这些

```
1. curl 三步诊断的输出
2. check.sh 的完整输出
3. docker logs --tail 200 astrbot
4. App 里报错的那句话（截图）
```

凑齐这四样，基本能定位。
