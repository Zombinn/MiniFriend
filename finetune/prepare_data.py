#!/usr/bin/env python3
"""把一整段长录音切片 + 转录，生成 VoxCPM 微调所需的 JSONL manifest。

用 faster-whisper 一步得到「片段边界 + 文本」（天然对齐），再按边界切音频、
重采样到 16kHz 单声道，写出 train.jsonl / val.jsonl。

manifest 每行: {"audio": "clips/clip0001.wav", "text": "这一段说的话"}
  - 音频相对 manifest 所在目录，便于整目录拷到服务器
  - 不写 ref_audio：单说话人 LoRA 会把音色烤进模型，推理无需参考片段

用法（服务器，有 GPU 最佳）:
  pip install faster-whisper librosa soundfile
  python prepare_data.py \
      --src /path/to/all_voices_merged.wav \
      --out ./data \
      --whisper-model large-v3 \
      --lang zh

输出:
  ./data/clips/clip0001.wav ...
  ./data/train.jsonl
  ./data/val.jsonl
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import librosa
import soundfile as sf

TARGET_SR = 16_000
MIN_DUR = 1.5     # 太短的片段并到邻居
MAX_DUR = 20.0    # 太长的片段二次切分（VoxCPM 上限 30s，留余量）
PAD = 0.1         # 每段前后留白(秒)


def transcribe(src: str, model_name: str, lang: str, device: str = "auto"):
    """返回 [(start, end, text)]，按时间排序。"""
    from faster_whisper import WhisperModel

    # device/compute_type：auto=有 CUDA 用 float16 否则 CPU int8；也可强制 cpu/cuda
    if device == "auto":
        try:
            import torch
            device = "cuda" if torch.cuda.is_available() else "cpu"
        except Exception:
            device = "cpu"
    compute = "float16" if device == "cuda" else "int8"

    print(f"[whisper] 加载 {model_name} on {device} ({compute})")
    model = WhisperModel(model_name, device=device, compute_type=compute)
    segments, info = model.transcribe(src, language=lang, vad_filter=True)
    out = []
    for s in segments:
        txt = s.text.strip()
        if txt:
            out.append((float(s.start), float(s.end), txt))
    print(f"[whisper] 识别到 {len(out)} 个片段")
    return out


def merge_and_split(segs):
    """合并过短、切分过长，返回规整后的 [(start, end, text)]。"""
    merged = []
    for start, end, text in segs:
        if merged and (end - merged[-1][0]) <= MAX_DUR and (start - merged[-1][1]) < 0.4 \
                and (merged[-1][1] - merged[-1][0]) < MIN_DUR:
            ps, pe, pt = merged[-1]
            merged[-1] = (ps, end, (pt + text).strip())
        else:
            merged.append((start, end, text))

    final = []
    for start, end, text in merged:
        dur = end - start
        if dur <= MAX_DUR:
            final.append((start, end, text))
        else:  # 过长：按等分硬切（文本整体留在第一段，训练对长度不敏感）
            n = int(dur // MAX_DUR) + 1
            step = dur / n
            for i in range(n):
                s = start + i * step
                e = min(start + (i + 1) * step, end)
                final.append((s, e, text if i == 0 else ""))
    return [(s, e, t) for s, e, t in final if t]


def process_file(src, clips_dir, idx_start, model, lang, device):
    """转录+切分单个 wav，写出片段，返回 (entries, 下一个可用编号)。"""
    segs = merge_and_split(transcribe(src, model, lang, device))
    y, _ = librosa.load(src, sr=TARGET_SR, mono=True)
    total = len(y)

    entries = []
    i = idx_start
    for start, end, text in segs:
        a = max(0, int((start - PAD) * TARGET_SR))
        b = min(total, int((end + PAD) * TARGET_SR))
        if b - a < int(0.3 * TARGET_SR):
            continue
        clip = y[a:b]
        name = f"clip{i:05d}.wav"
        clip_path = clips_dir / name
        sf.write(clip_path, clip, TARGET_SR, subtype="PCM_16")
        # 绝对路径：datasets 的 Audio 特征按 cwd 解析相对路径，
        # 训练从 VoxCPM 仓库根目录跑时找不到 clips/，故写绝对路径
        entries.append({"audio": str(clip_path.resolve()), "text": text})
        i += 1
    return entries, i


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True,
                    help="长录音 wav 路径，或一个装满已分段 wav 的目录")
    ap.add_argument("--out", default="./data", help="输出目录")
    ap.add_argument("--whisper-model", default="large-v3")
    ap.add_argument("--whisper-device", default="auto", choices=["auto", "cpu", "cuda"],
                    help="转录设备。cuBLAS 报 libcublas.so.12 缺失时用 cpu 绕过")
    ap.add_argument("--lang", default="zh")
    ap.add_argument("--val-ratio", type=float, default=0.05, help="留作验证的比例")
    args = ap.parse_args()

    out = Path(args.out)
    clips_dir = out / "clips"
    clips_dir.mkdir(parents=True, exist_ok=True)

    src = Path(args.src)
    if src.is_dir():
        wavs = sorted([p for p in src.rglob("*.wav")])
        print(f"[input] 目录模式：{len(wavs)} 个 wav -> 逐个转录")
        entries, idx = [], 1
        for n, w in enumerate(wavs, 1):
            print(f"[{n}/{len(wavs)}] {w.name}")
            es, idx = process_file(str(w), clips_dir, idx,
                                   args.whisper_model, args.lang, args.whisper_device)
            entries.extend(es)
    else:
        print(f"[input] 单文件模式：{src.name}")
        entries, _ = process_file(str(src), clips_dir, 1,
                                  args.whisper_model, args.lang, args.whisper_device)

    print(f"[split] 共得到 {len(entries)} 个片段")

    # 切分 train / val
    n_val = max(1, int(len(entries) * args.val_ratio)) if len(entries) > 20 else 0
    val, train = entries[:n_val], entries[n_val:]

    with open(out / "train.jsonl", "w", encoding="utf-8") as f:
        for e in train:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    if val:
        with open(out / "val.jsonl", "w", encoding="utf-8") as f:
            for e in val:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")

    print(f"[done] train={len(train)} val={len(val)} 片段 -> {out}")
    print(f"       manifest: {out/'train.jsonl'}")
    print("       下一步: 用 voxcpm 校验 manifest，再跑 run_finetune.sh")


if __name__ == "__main__":
    main()
