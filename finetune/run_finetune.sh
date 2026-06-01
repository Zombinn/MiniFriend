#!/usr/bin/env bash
# MiniFriend —— VoxCPM-0.5B 单说话人 LoRA 微调 runbook（在带 GPU 的服务器上跑）。
# 逐段按需执行；首次建议一段一段来，别盲目 ./run_finetune.sh 一把梭。
set -euo pipefail

# ============ 0. 改这些路径 ============
WORK=$HOME/minifriend_ft                 # 工作根目录
SRC_WAV=$WORK/all_voices_merged.wav      # 把你的 25min 录音传到这
VOXCPM_REPO=$WORK/VoxCPM                  # 官方仓库 clone 位置
BASE_MODEL=$WORK/VoxCPM-0.5B              # 预训练权重目录
DATA=$WORK/data                           # 切片+manifest 输出
CKPT=$WORK/checkpoints/minifriend_lora    # LoRA 输出
LOGS=$WORK/logs/minifriend_lora
mkdir -p "$WORK"

# ============ 1. 环境 ============
# 建议独立 conda/venv，Python 3.10–3.12，CUDA torch>=2.5
pip install "voxcpm" faster-whisper librosa soundfile \
            argbind tensorboardX transformers safetensors datasets accelerate

# ============ 2. 拿官方仓库（训练脚本要在仓库布局里跑）============
[ -d "$VOXCPM_REPO" ] || git clone https://github.com/OpenBMB/VoxCPM.git "$VOXCPM_REPO"

# ============ 3. 下载基座权重 VoxCPM-0.5B ============
python - <<PY
from huggingface_hub import snapshot_download
p = snapshot_download("openbmb/VoxCPM-0.5B", local_dir="$BASE_MODEL")
print("base model ->", p)
PY

# ============ 4. 切片 + 转录 -> manifest ============
# prepare_data.py 来自本目录(finetune/)，拷到服务器一起用
python prepare_data.py --src "$SRC_WAV" --out "$DATA" --whisper-model large-v3 --lang zh

# ============ 5. 校验 manifest（提前抓格式/采样率/缺文件问题）============
python - <<PY
from voxcpm.training.validate import validate_manifest, print_validation_report
r = validate_manifest("$DATA/train.jsonl", sample_rate=16000, verbose=True)
print_validation_report(r, "$DATA/train.jsonl")
assert r.is_valid, "manifest 校验未通过，先修上面报的错"
PY

# ============ 6. 用本目录的 yaml（记得把里面的 /path 改成上面变量的真实值）============
# 关键字段: pretrained_path=$BASE_MODEL  train_manifest=$DATA/train.jsonl
#           val_manifest=$DATA/val.jsonl save_path=$CKPT tensorboard=$LOGS
CFG=$VOXCPM_REPO/conf/minifriend_finetune_lora.yaml
cp ./voxcpm_finetune_lora.yaml "$CFG"
echo "去编辑 $CFG 把 /path/on/server/... 改成真实路径，然后继续第 7 步"

# ============ 7. 训练（从仓库根目录跑，脚本会把 src/ 加进 path）============
cd "$VOXCPM_REPO"
python scripts/train_voxcpm_finetune.py --config_path "$CFG"
# 监控: tensorboard --logdir "$LOGS"

# ============ 8. 产物 ============
# LoRA 权重在 $CKPT/latest/ :  lora_weights.safetensors (或 .ckpt) + lora_config.json
# 把整个 latest/ 目录传回本机，配置到 voice-service:
#   export MF_VOXCPM_LORA=/local/path/to/latest
# 推理即用你的音色，无需参考片段。
echo "完成。LoRA -> $CKPT/latest/"
