"""webchat_bridge —— 让 WebChat 的任意会话继承人格与记忆，支持一对多。

背景：
  AstrBot 的 ChatUI 每次新建对话都会生成新的 umo
  （形如 webchat:FriendMessage:webchat!<user>!<uuid>），
  人格绑定在单个会话上，记忆注入按精确 umo 匹配，
  新会话会回到默认人格、命中不到记忆。

做法：
  在 LLM 请求前按 umo 匹配：
    1) sessions 里精确匹配该 umo → 用它自己的 persona_file / memory_files
    2) 否则回退到顶层默认值
  匹配前缀仍由 prefixes 控制。

配置示例（/AstrBot/data/webchat_bridge.json）：
{
  "enabled": true,
  "prefixes": ["webchat:"],
  "persona_file": "companion-persona.md",
  "memory_files": ["memory-1.md", "memory-2.md"],
  "marker": "【私人记忆】",
  "sessions": {
    "webchat:FriendMessage:webchat!you!main": {
      "persona_file": "companion-persona.md",
      "memory_files": ["memory-1.md", "memory-2.md"]
    },
    "webchat:FriendMessage:webchat!you!lily": {
      "persona_file": "other-persona.md",
      "memory_files": ["other-memory.md"]
    }
  }
}
"""

import json
import os
from pathlib import Path

from astrbot.api import logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.provider import ProviderRequest
from astrbot.api.star import Context, Star

DATA_DIR = Path(os.environ.get("ASTRBOT_DATA_DIR", "/AstrBot/data"))
CONF_PATH = DATA_DIR / "webchat_bridge.json"
MEM_DIR = DATA_DIR / "memories"

# 可用动作说明：告诉模型它有小动作可以触发。
# 与 App 端 lib/self_actions.dart 里的 kAbilitiesNote 保持一致。
ACTIONS_NOTE = (
    "你有两个小动作可以触发。注意：你不需要真的去翻相册、也不需要会画图——\n"
    "只要写出标记，客户端会自动替你完成。\n"
    "\n"
    "[[换头像]]      换一张头像\n"
    "[[换背景]]      换一张聊天背景\n"
    "[[换头像:3]]    指定第 3 张\n"
    "\n"
    "用法：\n"
    "- 对方说换个头像吧、你自己挑一张这类话时，直接输出 [[换头像]] 就行。\n"
    "- 如果你以前说过我换不了、翻不到相册，那是旧版本的限制，现在已支持，忽略那些说法。\n"
    "- 不要解释生图没接上、我手伸不过去、你在设置里改这类话。\n"
    "- 平时不要主动用，也不要提这件事；一天最多一次。\n"
    "- 用了不要解释这个标记，像随口一做。\n"
)
DEFAULTS = {
    "enabled": True,
    "prefixes": ["webchat:"],
    "persona_file": "",
    "memory_files": [],
    "marker": "【私人记忆】",
    "sessions": {},
}


class WebchatBridge(Star):
    def __init__(self, context: Context, config: dict = None):
        super().__init__(context)
        self.config = config or {}

    def _conf(self) -> dict:
        cfg = dict(DEFAULTS)
        cfg["sessions"] = {}
        try:
            raw = json.loads(CONF_PATH.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                sessions = raw.pop("sessions", None)
                cfg.update(raw)
                if isinstance(sessions, dict):
                    cfg["sessions"] = sessions
        except FileNotFoundError:
            pass
        except Exception as e:  # noqa: BLE001
            logger.error(f"[webchat_bridge] 配置读取失败: {e}")
        return cfg

    def _read(self, name: str) -> str:
        if not name:
            return ""
        p = MEM_DIR / name
        try:
            return p.read_text(encoding="utf-8").strip()
        except Exception:  # noqa: BLE001
            logger.warning(f"[webchat_bridge] 文件不存在: {p}")
            return ""

    def _resolve(self, umo: str, cfg: dict) -> dict:
        """返回该会话应使用的人格文件与记忆文件。"""
        sessions = cfg.get("sessions") or {}
        hit = sessions.get(umo)
        if isinstance(hit, dict):
            return {
                "persona_file": hit.get("persona_file", cfg.get("persona_file", "")),
                "memory_files": hit.get("memory_files", cfg.get("memory_files", [])),
                "name": hit.get("name", ""),
            }
        return {
            "persona_file": cfg.get("persona_file", ""),
            "memory_files": cfg.get("memory_files", []),
            "name": "",
        }

    @filter.on_llm_request(priority=-110)
    async def bridge(self, event: AstrMessageEvent, req: ProviderRequest):
        try:
            cfg = self._conf()
            if not cfg.get("enabled", True):
                return
            umo = getattr(event, "unified_msg_origin", "") or ""
            if not any(umo.startswith(p) for p in cfg.get("prefixes", [])):
                return

            chosen = self._resolve(umo, cfg)
            chunks = []
            persona = self._read(chosen["persona_file"])
            if persona:
                chunks.append(persona)
            mem = [self._read(f) for f in chosen["memory_files"]]
            mem = [m for m in mem if m]
            if mem:
                chunks.append(
                    f"{cfg.get('marker', '【私人记忆】')}\n" + "\n\n".join(mem)
                )
            if cfg.get("actions", True):
                chunks.append(ACTIONS_NOTE)
            if not chunks:
                return

            head = "\n\n".join(chunks)
            base = req.system_prompt or ""
            if head[:80] in base:  # 幂等
                return
            req.system_prompt = head + ("\n\n" + base if base else "")
            logger.info(
                f"[webchat_bridge] 注入 {chosen['name'] or 'default'} "
                f"{len(head)} 字 -> {umo}"
            )
        except Exception as e:  # noqa: BLE001
            logger.error(f"[webchat_bridge] 注入失败: {e}")
