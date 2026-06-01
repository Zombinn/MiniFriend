"""VoxCPM 后端：LoRA 微调音色 TTS。

优化点：
- DiT estimator (VoxCPMLocDiT) 用 ONNX Runtime 替换，推理速度 2.4x，整体提速 ~55%
- inference_timesteps 默认改为 4（实测 3.6s/句，音质可接受）
- 禁用 Badcase 重试，防止无限循环卡死服务
- GQA (enable_gqa) 兼容补丁，防止 MPS/ONNX 报错
"""

from __future__ import annotations

import io
import wave

import numpy as np

from .base import SynthesisResult, TTSBackend


def _apply_gqa_patch() -> None:
    """VoxCPM 用 enable_gqa=True，ONNX export 和 MPS 都不支持。
    打补丁：手动 expand kv heads，去掉 enable_gqa 参数。"""
    import torch.nn.functional as F

    if getattr(F, "_gqa_patched", False):
        return
    _orig = F.scaled_dot_product_attention

    def _patched(q, k, v, **kw):
        kw.pop("enable_gqa", None)
        if q.shape[-3] != k.shape[-3] and q.shape[-3] % k.shape[-3] == 0:
            f = q.shape[-3] // k.shape[-3]
            k = k.repeat_interleave(f, dim=-3)
            v = v.repeat_interleave(f, dim=-3)
        return _orig(q, k, v, **kw)

    F.scaled_dot_product_attention = _patched
    F._gqa_patched = True


def _build_onnx_estimator(estimator, onnx_path: str):
    """把 VoxCPMLocDiT estimator 导出为 ONNX，返回 ONNX Runtime 包装器。
    已存在则直接加载，不重复导出。"""
    import os
    import torch
    import onnxruntime as ort

    if not os.path.exists(onnx_path):
        print(f"[voxcpm] 导出 DiT estimator → {onnx_path} …")
        dummy = dict(
            x=torch.randn(2, 64, 2),
            mu=torch.randn(2, 1024),
            t=torch.rand(2),
            cond=torch.randn(2, 64, 2),
            dt=torch.rand(2),
        )
        estimator_fp32 = estimator.float()
        estimator_fp32.eval()
        with torch.no_grad():
            torch.onnx.export(
                estimator_fp32,
                tuple(dummy.values()),
                onnx_path,
                opset_version=17,
                input_names=list(dummy.keys()),
                output_names=["out"],
                dynamic_axes={"x": {1: "seq"}, "mu": {1: "d"}, "cond": {1: "seq"}},
                do_constant_folding=True,
            )
        print(f"[voxcpm] ONNX 导出完成（{os.path.getsize(onnx_path)//1024//1024}MB）")

    sess = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])

    import torch

    class OnnxEstimator(torch.nn.Module):
        def __init__(self, pytorch_fallback):
            super().__init__()
            self._fb = pytorch_fallback   # 保留原始 PyTorch estimator 作为降级选项

        def forward(self, x, mu, t, cond, dt):
            try:
                out = sess.run(None, {
                    "x":    x.float().numpy(),
                    "mu":   mu.float().numpy(),
                    "t":    t.float().numpy(),
                    "cond": cond.float().numpy(),
                    "dt":   dt.float().numpy(),
                })[0]
                result = torch.from_numpy(out).to(x.dtype)
                # 简单质量检查：输出全 NaN 或值域异常则降级
                if torch.isnan(result).any() or result.abs().max() > 100:
                    raise ValueError("ONNX 输出异常，降级 PyTorch")
                return result
            except Exception as e:
                print(f"[voxcpm] ONNX 降级 PyTorch: {e}")
                return self._fb(x, mu, t, cond, dt)

    return OnnxEstimator(estimator)


class VoxCPMBackend(TTSBackend):
    name = "voxcpm"

    def __init__(
        self,
        model_id: str = "openbmb/VoxCPM-0.5B",
        cfg_value: float = 2.0,
        inference_timesteps: int = 6,      # ts=6 平衡速度与音质（纯 PyTorch ~9s/句，无噪声）
        load_denoiser: bool = False,
        device: str = "cpu",
        lora_weights_path: str | None = None,
        use_onnx_dit: bool = True,          # ONNX 加速 DiT，~55% 提速，锁住并发后无噪声
        onnx_path: str = "dit_estimator.onnx",
    ):
        self.model_id = model_id
        self.cfg_value = cfg_value
        self.inference_timesteps = inference_timesteps
        self.load_denoiser = load_denoiser
        self.device = device
        self.lora_weights_path = lora_weights_path or None
        self.use_onnx_dit = use_onnx_dit
        self.onnx_path = onnx_path
        self._model = None
        self._loaded = False

    def load(self) -> None:
        if self._loaded:
            return
        import json, os

        _apply_gqa_patch()

        from voxcpm import VoxCPM

        kwargs: dict = {"load_denoiser": self.load_denoiser, "device": self.device}
        if self.lora_weights_path:
            kwargs["lora_weights_path"] = self.lora_weights_path
            cfg_json = os.path.join(self.lora_weights_path, "lora_config.json")
            if os.path.isfile(cfg_json):
                from voxcpm.model.voxcpm import LoRAConfig
                with open(cfg_json, encoding="utf-8") as f:
                    cfg = json.load(f).get("lora_config", {})
                kwargs["lora_config"] = LoRAConfig(**cfg)

        self._model = VoxCPM.from_pretrained(self.model_id, **kwargs)

        # ONNX DiT 替换
        if self.use_onnx_dit:
            try:
                onnx_estimator = _build_onnx_estimator(
                    self._model.tts_model.feat_decoder.estimator,
                    self.onnx_path,
                )
                self._model.tts_model.feat_decoder.estimator = onnx_estimator
                print(f"[voxcpm] ONNX DiT 加速已启用（ts={self.inference_timesteps}）")
            except Exception as e:
                print(f"[voxcpm] ONNX 加载失败，回退 PyTorch：{e}")

        self._loaded = True

    def synthesize(
        self,
        text: str,
        reference_wav: str | None = None,
        prompt_text: str | None = None,
    ) -> SynthesisResult:
        if not self._loaded:
            self.load()

        kwargs: dict = {
            "text": text,
            "cfg_value": self.cfg_value,
            "inference_timesteps": self.inference_timesteps,
            "retry_badcase": False,                 # 关掉重试，避免卡死；纯 PyTorch 质量稳定不需要
        }
        if reference_wav:
            kwargs["prompt_wav_path"] = reference_wav
            if prompt_text:
                kwargs["prompt_text"] = prompt_text

        wav = self._model.generate(**kwargs)
        sample_rate = self._model.tts_model.sample_rate
        return SynthesisResult(wav_bytes=_float_to_wav(wav, sample_rate), sample_rate=sample_rate)


def _float_to_wav(samples, sample_rate: int) -> bytes:
    """float32 [-1,1] numpy 波形 → 16-bit PCM wav 字节。"""
    arr = np.asarray(samples, dtype=np.float32).squeeze()
    arr = np.clip(arr, -1.0, 1.0)
    pcm16 = (arr * 32767.0).astype("<i2")
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm16.tobytes())
    return buf.getvalue()
