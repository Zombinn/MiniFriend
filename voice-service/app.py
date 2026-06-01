"""MiniFriend 语音服务 (FastAPI)。

POST /tts   { "text": "...", "backend"?: "voxcpm", "reference_wav"?: "/path" }
            -> audio/wav

GET  /health
GET  /backends
"""

from __future__ import annotations

import io
import threading

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

import config
from backends import available, get_converter, get_tts

app = FastAPI(title="MiniFriend Voice Service")

# VoxCPM 单实例不支持并发合成，用锁强制串行
# 并发请求会互相干扰模型状态导致杂音
_tts_lock = threading.Lock()


@app.on_event("startup")
def warmup_on_startup():
    """服务启动后在后台线程预加载模型 + 静默合成一次。
    这样首条用户消息到来时模型已热，不需要等待冷启动的 10+ 秒。"""
    def _warmup():
        try:
            print("[warmup] 开始预加载模型…")
            engine = get_tts(
                config.TTS_BACKEND,
                model_id=config.VOXCPM_MODEL,
                device=config.VOXCPM_DEVICE,
                lora_weights_path=config.VOXCPM_LORA or None,
            )
            engine.load()
            # 静默合成一句短文本，触发 ONNX + KV cache 预热
            engine.synthesize("你好")
            print("[warmup] ✅ 模型预热完成，首句延迟已消除")
        except Exception as e:
            print(f"[warmup] ⚠️  预热失败（不影响正常使用）: {e}")

    threading.Thread(target=_warmup, daemon=True).start()


class TTSRequest(BaseModel):
    text: str
    backend: str | None = None
    reference_wav: str | None = None
    prompt_text: str | None = None  # 参考音频转录，提升克隆保真度
    converter: str | None = None  # 变声层；当前 stub，传了会报 501


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/backends")
def backends():
    return available()


@app.post("/tts")
def tts(req: TTSRequest):
    if not req.text.strip():
        raise HTTPException(400, "text 为空")

    backend_name = req.backend or config.TTS_BACKEND
    reference = req.reference_wav or config.reference_wav_or_none()
    prompt_text = req.prompt_text or (config.REFERENCE_TEXT or None)

    try:
        engine = get_tts(
            backend_name,
            model_id=config.VOXCPM_MODEL,
            device=config.VOXCPM_DEVICE,
            lora_weights_path=config.VOXCPM_LORA or None,
        ) if backend_name == "voxcpm" else get_tts(backend_name)
        with _tts_lock:   # 强制串行：同一时刻只有一个合成任务在跑
            result = engine.synthesize(req.text, reference_wav=reference, prompt_text=prompt_text)
    except Exception as e:  # noqa: BLE001 - 把后端错误透传给客户端
        raise HTTPException(500, f"合成失败: {e}") from e

    # 方案 B 第二级变声层（当前 stub）
    converter_name = req.converter or config.VOICE_CONVERTER
    if converter_name:
        try:
            conv = get_converter(converter_name)
            conv.load()
            result = conv.convert(result.wav_bytes, result.sample_rate)
        except NotImplementedError as e:
            raise HTTPException(501, str(e)) from e

    return Response(content=result.wav_bytes, media_type="audio/wav")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=config.HOST, port=config.PORT)
