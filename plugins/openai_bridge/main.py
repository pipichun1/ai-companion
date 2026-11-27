"""OpenAI compatible bridge: expose AstrBot webchat sessions as /v1/chat/completions.

Works with NextChat / LobeChat style frontends. Persona, memory and context
compression all stay inside AstrBot.

Routes:
  POST /api/v1/plugins/extensions/v1/chat/completions
  GET  /api/v1/plugins/extensions/v1/models

Auth: Authorization: Bearer <astrbot dashboard token>
"""

import asyncio
import base64
import json
import os
import time
import uuid

from astrbot.api import logger
from astrbot.api.star import Context, Star
from astrbot.api.web import request as web_request
from astrbot.core.platform.sources.webchat.webchat_queue_mgr import webchat_queue_mgr
from starlette.responses import JSONResponse, StreamingResponse

SESSION_USER = "you"
DEFAULT_CID = "main"
TIMEOUT_SECONDS = 240
# 对外暴露的模型名（客户端里显示的名字，可随意改）
MODEL_ID = os.environ.get("BRIDGE_MODEL_ID", "astrbot")

DATA_DIR = os.environ.get("ASTRBOT_DATA_DIR", "/AstrBot/data")
IMAGE_DIR = os.path.join(DATA_DIR, "temp", "openai_bridge")


def _extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text":
                parts.append(part.get("text") or "")
        return "".join(parts)
    return ""


def _extract_images(content):
    """从 OpenAI 多模态 content 里取出 data URL 形式的图片。"""
    if not isinstance(content, list):
        return []
    urls = []
    for part in content:
        if not isinstance(part, dict):
            continue
        if part.get("type") != "image_url":
            continue
        image_url = part.get("image_url")
        url = None
        if isinstance(image_url, dict):
            url = image_url.get("url")
        elif isinstance(image_url, str):
            url = image_url
        if isinstance(url, str) and url.startswith("data:"):
            urls.append(url)
    return urls


def _save_image(data_url):
    """把 data URL 存成容器内的文件，返回路径。"""
    try:
        header, _, b64data = data_url.partition(",")
        suffix = ".jpg"
        if "image/png" in header:
            suffix = ".png"
        elif "image/webp" in header:
            suffix = ".webp"
        elif "image/gif" in header:
            suffix = ".gif"
        raw = base64.b64decode(b64data)
        os.makedirs(IMAGE_DIR, exist_ok=True)
        path = os.path.join(IMAGE_DIR, f"{uuid.uuid4().hex}{suffix}")
        with open(path, "wb") as f:
            f.write(raw)
        return path
    except Exception as exc:  # noqa: BLE001
        logger.warning(f"[openai_bridge] save image failed: {exc}")
        return None


def _build_parts(text, content):
    parts = []
    if str(text or "").strip():
        parts.append({"type": "plain", "text": text})
    for data_url in _extract_images(content):
        path = _save_image(data_url)
        if path:
            parts.append({"type": "image", "path": path})
    if not parts:
        parts.append({"type": "plain", "text": text or ""})
    return parts


def _is_stats(chunk):
    """AstrBot appends a token_usage JSON blob as a plain chunk; drop it."""
    return '"token_usage"' in (chunk or "")


def _sse(piece):
    payload = {
        "id": "chatcmpl-astrbot",
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": MODEL_ID,
        "choices": [
            {
                "index": 0,
                "delta": {"content": piece} if piece else {"role": "assistant"},
                "finish_reason": None,
            }
        ],
    }
    return "data: " + json.dumps(payload, ensure_ascii=False) + "\n\n"


CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
}


class OpenAIBridge(Star):
    def __init__(self, context: Context, config=None):
        super().__init__(context)
        self.config = config or {}
        context.register_web_api(
            "/v1/chat/completions",
            self.chat_completions,
            ["POST", "OPTIONS"],
            "OpenAI compatible chat completions",
        )
        context.register_web_api(
            "/v1/models",
            self.list_models,
            ["GET", "OPTIONS"],
            "OpenAI compatible model list",
        )
        context.register_web_api(
            "/v1/personas",
            self.list_personas,
            ["GET", "OPTIONS"],
            "Available personas",
        )
        context.register_web_api(
            "/v1/sessions",
            self.create_session,
            ["POST", "OPTIONS"],
            "Create a session bound to a persona",
        )
        context.register_web_api(
            "/v1/sessions/delete",
            self.delete_session,
            ["POST", "OPTIONS"],
            "Delete a session and its cloud memory",
        )
        logger.info("[openai_bridge] registered /v1/chat/completions")

    # ── 人格与会话管理 ────────────────────────────────────────
    def _bridge_conf_path(self):
        return os.path.join(DATA_DIR, "webchat_bridge.json")

    def _read_bridge_conf(self):
        import json as _json
        try:
            with open(self._bridge_conf_path(), encoding="utf-8") as f:
                data = _json.load(f)
            return data if isinstance(data, dict) else {}
        except Exception:  # noqa: BLE001
            return {}

    def _persona_title(self, persona_file: str) -> str:
        """从人格文件第一行取显示名，取不到就退回文件名。"""
        try:
            path = os.path.join(DATA_DIR, "memories", persona_file)
            head = open(path, encoding="utf-8").readline().strip()
            head = head.lstrip("#").strip()
            if "：" in head:
                name = head.split("：")[-1].strip()
                if name:
                    return name
        except Exception:  # noqa: BLE001
            pass
        return persona_file.replace("-persona.md", "")

    async def list_personas(self):
        if web_request.method.upper() == "OPTIONS":
            return JSONResponse({}, headers=CORS_HEADERS)
        cfg = self._read_bridge_conf()
        seen = {}
        default_persona = cfg.get("persona_file") or ""
        if default_persona:
            default_name = "默认"
            try:
                head = open(os.path.join(DATA_DIR, "memories", default_persona),
                            encoding="utf-8").readline()
                head = head.strip().lstrip("#").strip()
                if "：" in head:
                    default_name = head.split("：")[-1].strip() or default_name
            except Exception:  # noqa: BLE001
                pass
            seen[default_persona] = {
                "key": default_persona,
                "name": cfg.get("default_name") or default_name,
                "persona_file": default_persona,
                "memory_files": cfg.get("memory_files", []),
            }
        for umo, item in (cfg.get("sessions") or {}).items():
            if not isinstance(item, dict):
                continue
            pf = item.get("persona_file") or default_persona
            if not pf:
                continue
            if pf not in seen:
                seen[pf] = {
                    "key": pf,
                    "name": self._persona_title(pf),
                    "persona_file": pf,
                    "memory_files": item.get("memory_files", []),
                }
        # 扫描 memories 目录下的 *-persona.md，自动纳管
        try:
            import os as _os
            mem_dir = os.path.join(DATA_DIR, "memories")
            for fn in sorted(_os.listdir(mem_dir)):
                if not fn.endswith("-persona.md") or fn in seen:
                    continue
                display = fn.replace("-persona.md", "")
                try:
                    head = open(_os.path.join(mem_dir, fn),
                                encoding="utf-8").readline()
                    head = head.strip().lstrip("#").strip()
                    if "：" in head:
                        display = head.split("：")[-1].strip() or display
                except Exception:  # noqa: BLE001
                    pass
                seen[fn] = {
                    "key": fn,
                    "name": display,
                    "persona_file": fn,
                    "memory_files": [],
                }
        except Exception as exc:  # noqa: BLE001
            logger.warning(f"[openai_bridge] 扫描人格目录失败: {exc}")

        return JSONResponse(
            {"object": "list", "data": list(seen.values())},
            headers=CORS_HEADERS,
        )

    async def delete_session(self):
        """删除会话在云端的痕迹：上下文、消息历史、人格映射。"""
        if web_request.method.upper() == "OPTIONS":
            return JSONResponse({}, headers=CORS_HEADERS)
        import json as _json
        import sqlite3

        body = await web_request.json(default={}) or {}
        conv_id = str(body.get("conv_id") or "").strip()
        if not conv_id:
            return JSONResponse(
                {"error": {"message": "missing conv_id"}}, status_code=400
            )
        if conv_id in ("main", "test"):
            return JSONResponse(
                {"error": {"message": "refusing to delete default session"}},
                status_code=400,
            )

        umo = f"webchat:FriendMessage:webchat!{SESSION_USER}!{conv_id}"
        removed = {}

        try:
            con = sqlite3.connect(os.path.join(DATA_DIR, "data_v4.db"), timeout=10)
            cur = con.cursor()
            cur.execute("delete from conversations where user_id = ?", (umo,))
            removed["conversations"] = cur.rowcount
            cur.execute(
                "delete from platform_message_history where user_id = ?", (umo,)
            )
            removed["messages"] = cur.rowcount
            con.commit()
            con.close()
        except Exception as exc:  # noqa: BLE001
            logger.error(f"[openai_bridge] 删除云端记忆失败: {exc}")
            return JSONResponse(
                {"error": {"message": f"db error: {exc}"}}, status_code=500
            )

        try:
            cfg = self._read_bridge_conf()
            sessions = cfg.get("sessions") or {}
            if umo in sessions:
                sessions.pop(umo)
                cfg["sessions"] = sessions
                with open(self._bridge_conf_path(), "w", encoding="utf-8") as f:
                    _json.dump(cfg, f, ensure_ascii=False, indent=2)
                removed["binding"] = 1
        except Exception as exc:  # noqa: BLE001
            logger.warning(f"[openai_bridge] 删除人格映射失败: {exc}")

        logger.info(f"[openai_bridge] 删除会话 {conv_id}: {removed}")
        return JSONResponse(
            {"conv_id": conv_id, "removed": removed}, headers=CORS_HEADERS
        )

    async def create_session(self):
        if web_request.method.upper() == "OPTIONS":
            return JSONResponse({}, headers=CORS_HEADERS)
        import json as _json
        body = await web_request.json(default={}) or {}
        name = str(body.get("name") or "").strip() or "新会话"
        persona_file = str(body.get("persona_file") or "").strip()
        if not persona_file:
            return JSONResponse(
                {"error": {"message": "missing persona_file"}}, status_code=400
            )

        conv_id = "c" + uuid.uuid4().hex[:10]
        umo = f"webchat:FriendMessage:webchat!{SESSION_USER}!{conv_id}"

        cfg = self._read_bridge_conf()
        sessions = cfg.get("sessions")
        if not isinstance(sessions, dict):
            sessions = {}
        memory_files = []
        for item in sessions.values():
            if isinstance(item, dict) and item.get("persona_file") == persona_file:
                memory_files = item.get("memory_files", [])
                break
        sessions[umo] = {
            "name": name,
            "persona_file": persona_file,
            "memory_files": memory_files,
        }
        cfg["sessions"] = sessions
        try:
            with open(self._bridge_conf_path(), "w", encoding="utf-8") as f:
                _json.dump(cfg, f, ensure_ascii=False, indent=2)
        except Exception as exc:  # noqa: BLE001
            logger.error(f"[openai_bridge] 写配置失败: {exc}")
            return JSONResponse(
                {"error": {"message": "cannot persist session"}}, status_code=500
            )

        logger.info(f"[openai_bridge] 新建会话 {conv_id} -> {persona_file}")
        return JSONResponse(
            {
                "conv_id": conv_id,
                "name": name,
                "persona_file": persona_file,
                "umo": umo,
            },
            headers=CORS_HEADERS,
        )

    async def list_models(self):
        if web_request.method.upper() == "OPTIONS":
            return JSONResponse({}, headers=CORS_HEADERS)
        return JSONResponse(
            {
                "object": "list",
                "data": [{"id": MODEL_ID, "object": "model", "owned_by": "astrbot"}],
            },
            headers=CORS_HEADERS,
        )

    def _dispatch(self, parts, cid):
        request_id = uuid.uuid4().hex
        back = webchat_queue_mgr.get_or_create_back_queue(request_id, cid)
        front = webchat_queue_mgr.get_or_create_queue(cid)
        return request_id, back, front

    async def _converse(self, parts, cid):
        request_id, back, front = self._dispatch(parts, cid)
        await front.put(
            (
                SESSION_USER,
                cid,
                {
                    "message": parts,
                    "message_id": request_id,
                },
            )
        )
        chunks = []
        final = None
        try:
            while True:
                item = await asyncio.wait_for(back.get(), timeout=TIMEOUT_SECONDS)
                kind = item.get("type")
                if kind == "plain":
                    data = item.get("data") or ""
                    if data and not _is_stats(data):
                        chunks.append(data)
                elif kind == "complete":
                    final = item.get("data") or None
                elif kind == "end":
                    break
        except asyncio.TimeoutError:
            logger.warning("[openai_bridge] reply timeout")
        finally:
            webchat_queue_mgr.remove_back_queue(request_id)
        return (final or "".join(chunks)).strip()

    async def chat_completions(self):
        if web_request.method.upper() == "OPTIONS":
            return JSONResponse({}, headers=CORS_HEADERS)
        body = await web_request.json(default={}) or {}
        messages = body.get("messages") or []
        content = ""
        for message in reversed(messages):
            if message.get("role") == "user":
                content = message.get("content")
                break
        text = _extract_text(content)
        parts = _build_parts(text, content)
        if not str(text).strip() and len(parts) <= 1 and parts[0].get("type") == "plain":
            return JSONResponse(
                {"error": {"message": "empty user message"}}, status_code=400
            )

        raw_cid = str(body.get("user") or "").strip() or DEFAULT_CID
        cid = "".join(ch for ch in raw_cid if ch.isalnum() or ch in "-_")[:40]
        cid = cid or DEFAULT_CID

        if not body.get("stream"):
            reply = await self._converse(parts, cid)
            return JSONResponse(
                {
                    "id": "chatcmpl-astrbot",
                    "object": "chat.completion",
                    "created": int(time.time()),
                    "model": MODEL_ID,
                    "choices": [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": reply},
                            "finish_reason": "stop",
                        }
                    ],
                },
                headers=CORS_HEADERS,
            )

        request_id, back, front = self._dispatch(parts, cid)
        await front.put(
            (
                SESSION_USER,
                cid,
                {
                    "message": parts,
                    "message_id": request_id,
                },
            )
        )

        async def event_stream():
            try:
                yield _sse(None)
                collected = []
                final = None
                while True:
                    # 已经拿到完整回复后只再等 2 秒收尾，
                    # 避免某些回复不发 end 时白等到超时
                    wait_for = TIMEOUT_SECONDS if final is None else 2
                    try:
                        item = await asyncio.wait_for(back.get(), timeout=wait_for)
                    except asyncio.TimeoutError:
                        break
                    kind = item.get("type")
                    if kind == "plain":
                        data = item.get("data") or ""
                        if data and not _is_stats(data):
                            collected.append(data)
                    elif kind == "complete":
                        final = item.get("data") or None
                    elif kind == "end":
                        break
                text = (final or "".join(collected)).strip()
                # 逐段吐出，模拟打字机
                step = 4
                for i in range(0, len(text), step):
                    yield _sse(text[i:i + step])
                    await asyncio.sleep(0.02)
                yield "data: [DONE]\n\n"
            finally:
                webchat_queue_mgr.remove_back_queue(request_id)

        return StreamingResponse(
            event_stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", **CORS_HEADERS},
        )
