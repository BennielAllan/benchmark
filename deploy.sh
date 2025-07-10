#!/bin/bash

# 获取参数
if [ $# -lt 2 ]; then
    echo "用法: $0 <云平台名称> <数据盘位置>"
    exit 1
fi
# 数据盘位置
CLOUD_NAME="$1"
DATA_DIR="$2"
# 存放测试结果
mkdir "$CLOUD_NAME"

# 重试函数，参数：命令 and 提示信息
retry() {
    local cmd="$1"
    local msg="$2"
    local max=10
    local delay=2
    local n=1
    while true; do
        eval "$cmd" && break || {
            if (( n < max )); then
                echo -n "=========="
                echo "$(date '+%Y-%m-%d %H:%M:%S') $msg，重试第 $n 次..." | tee -a deploy.log
                sleep $delay
                ((n++))
            else
                echo -n "!!!!!!!!!!"
                echo "$(date '+%Y-%m-%d %H:%M:%S') $msg，已达到最大重试次数 $max 次。" | tee -a deploy.log
                return 1
            fi
        }
    done
}

apt update
########## 环境部署 ##########
# 安装libgl1
retry "apt install -y libgl1" "安装libGL.so.1失败" || exit 1
# 安装netcat
retry "apt install -y netcat" "安装netcat失败" || exit 1

# # 获取miniconda3安装脚本
# retry "wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" "下载 Miniconda 安装脚本失败" || exit 1
# # 运行安装脚本，问是否都选择是，安装目录指定位置：/home/ubuntu/miniconda3
# chmod +x Miniconda3-latest-Linux-x86_64.sh
# retry "bash Miniconda3-latest-Linux-x86_64.sh -b -p /home/ubuntu/miniconda3" "Miniconda 安装失败" || exit 1
# # 安装完成若没有进入到Base虚拟环境
# source /home/ubuntu/miniconda3/bin/activate

########## 测试推理速度 ##########
# 创建并进入虚拟环境
retry "conda create -n r1 python=3.11 -y" "创建虚拟环境失败" || exit 1
conda activate r1
# 安装测试脚本依赖
retry "pip install -r requirements.txt" "安装测试脚本依赖失败" || exit 1
# 安装vllm
retry "pip install vllm" "安装 vllm 失败" || exit 1
# 下载模型
apt install -y git-lfs
retry "(cd $DATA_DIR && git clone https://www.modelscope.cn/deepseek-ai/DeepSeek-R1-0528-Qwen3-8B.git)" "下载 DeepSeek-R1-0528-Qwen3-8B 模型失败" || exit 1
# 启动模型
vllm serve $DATA_DIR/DeepSeek-R1-0528-Qwen3-8B/ --served-model-name deepseek-r1 -tp 1 --max-model-len 32768 --max-num-seqs 4 > /dev/null 2>&1 &
# 保存进程ID以便后续停止
VLLM_PID=$!
# 等待端口8000开放
for i in {1..6000}; do
    if nc -z 127.0.0.1 8000; then
        break
    fi
    sleep 1
    done
# 测试
python bench_serve.py \
    --backend vllm \
    --model deepseek-r1 \
    --tokenizer $DATA_DIR/DeepSeek-R1-0528-Qwen3-8B \
    --request-rate inf \
    --num-prompts 32 \
    --dataset-name random \
    --max-concurrency 16 \
    --random-input-len 5734 \
    --random-output-len 1434 \
    --ignore-eos \
    --host 127.0.0.1 \
    --port 8000 \
    --seed 42 \
    | tee $CLOUD_NAME/reasoning_result.txt
# 关闭模型服务
kill $VLLM_PID

