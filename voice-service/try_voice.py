"""命令行验证 VoxCPM 克隆：生成一句话并存成 wav。

用法:
  python try_voice.py "你好，我是你的桌面小助手" --ref /path/to/reference.wav --out out.wav
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

import config
from backends import get_tts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text", nargs="?", default="你好，我是你的桌面小助手，很高兴见到你。")
    ap.add_argument("--ref", default=config.reference_wav_or_none(), help="参考音频 wav 路径")
    ap.add_argument("--prompt-text", default=config.REFERENCE_TEXT or None,
                    help="参考音频的文字转录（提升克隆保真度）")
    ap.add_argument("--out", default="out.wav")
    ap.add_argument("--backend", default=config.TTS_BACKEND)
    args = ap.parse_args()

    print(f"[1/3] 加载后端 {args.backend} (首次会下载模型，请耐心)...")
    t0 = time.time()
    engine = get_tts(args.backend, model_id=config.VOXCPM_MODEL, device=config.VOXCPM_DEVICE,
                     lora_weights_path=config.VOXCPM_LORA or None) \
        if args.backend == "voxcpm" else get_tts(args.backend)
    engine.load()
    print(f"      加载完成 {time.time() - t0:.1f}s")

    print(f"[2/3] 合成: {args.text!r}  ref={args.ref}  prompt_text={args.prompt_text!r}")
    t0 = time.time()
    result = engine.synthesize(args.text, reference_wav=args.ref, prompt_text=args.prompt_text)
    print(f"      合成完成 {time.time() - t0:.1f}s  采样率={result.sample_rate}")

    Path(args.out).write_bytes(result.wav_bytes)
    print(f"[3/3] 已保存 -> {Path(args.out).resolve()}")


if __name__ == "__main__":
    main()
