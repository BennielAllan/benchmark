#!/bin/bash

# 获取参数
if [ $# -lt 2 ]; then
    echo "用法: $0 <云平台名称> <数据盘位置>"
    exit 1
fi
# 数据盘位置
CLOUD_NAME="$1"
DATA_DIR="$2"

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

########## 环境部署 ##########
# 获取安装脚本
retry "wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" "下载 Miniconda 安装脚本失败" || exit 1
# 运行安装脚本，问是否都选择是，安装目录指定位置：/home/ubuntu/miniconda3
chmod +x Miniconda3-latest-Linux-x86_64.sh
retry "bash Miniconda3-latest-Linux-x86_64.sh -b -p /home/ubuntu/miniconda3" "Miniconda 安装失败" || exit 1
# 安装完成若没有进入到Base虚拟环境
source /home/ubuntu/miniconda3/bin/activate

########## 测试推理速度 ##########
# 创建并进入虚拟环境
retry "conda create -n r1 python=3.11 -y" "创建虚拟环境失败" || exit 1
conda activate r1
# 安装vllm
retry "pip install vllm" "安装 vllm 失败" || exit 1
# 下载模型
sudo apt update && sudo apt install -y git-lfs
retry "cd $DATA_DIR && git clone https://www.modelscope.cn/deepseek-ai/DeepSeek-R1-0528-Qwen3-8B.git" "下载 DeepSeek-R1-0528-Qwen3-8B 模型失败" || exit 1
# 启动模型
vllm serve $DATA_DIR/DeepSeek-R1-0528-Qwen3-8B/ --served-model-name deepseek-r1 -tp 1 --max-model-len 32768 --max-num-seqs 4 &
# 测试
python bench_serve.py \
    --backend vllm \
    --model deepseek-r1 \
    --tokenizer /root/DeepSeek-R1-0528-Qwen3-8B \
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

########## 测试文生图速度 ##########
# 创建新的虚拟环境
retry "conda create -n sd python=3.10 -y" "创建sd虚拟环境失败" || exit 1
conda activate sd
# 安装xformers
retry "pip3 install -U xformers --index-url https://download.pytorch.org/whl/cu126" "安装xformers失败" || exit 1
# 下载 stable diffusion
retry "cd $DATA_DIR && git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git" "下载stable diffusion失败" || exit 1
retry "pip install -r $DATA_DIR/stable-diffusion-webui/requirements.txt" "安装stable diffusion失败" || exit 1
# 运行 sd
sudo -u ubuntu bash -c "cd $DATA_DIR/stable-diffusion-webui && python launch.py --xformers --listen --api &"
# 测试
echo 512 | python test_sd.py 512 | tee $CLOUD_NAME/sd_result.txt

########## 测试机器性能 ##########
# 测试 CPU 性能
retry "sudo apt install -y sysbench" "安装sysbench失败" || exit 1
## 测试单线程CPU计算能力
sysbench cpu --cpu-max-prime=20000 --threads=1 run | tee $CLOUD_NAME/cpu_single_thread.txt
## 测试多线程CPU计算能力
sysbench cpu --cpu-max-prime=20000 --threads=$(nproc) run | tee $CLOUD_NAME/cpu_multi_thread.txt

# 测试 IO 性能
retry "sudo apt install -y fio" "安装fio失败" || exit 1
## 随机读测试
fio --name=randread --ioengine=libaio --bs=4k --rw=randread --size=1G --numjobs=4 --iodepth=32 --runtime=60 --group_reporting | tee $CLOUD_NAME/io_randread.txt
## 随机写测试
fio --name=randwrite --ioengine=libaio --bs=4k --rw=randwrite --size=1G --numjobs=4 --iodepth=32 --runtime=60 --group_reporting | tee $CLOUD_NAME/io_randwrite.txt
## 顺序读测试
fio --name=seqread --ioengine=libaio --bs=1M --rw=read --size=2G --numjobs=1 --iodepth=1 --runtime=60 --group_reporting | tee $CLOUD_NAME/io_seqread.txt
## 顺序写测试
fio --name=seqwrite --ioengine=libaio --bs=1M --rw=write --size=2G --numjobs=1 --iodepth=1 --runtime=60 --group_reporting | tee $CLOUD_NAME/io_seqwrite.txt
## 混合随机读写测试
fio --name=mixed --ioengine=libaio --bs=4k --rw=randrw --rwmixread=70 --size=1G --numjobs=4 --iodepth=16 --runtime=60 --group_reporting | tee $CLOUD_NAME/io_mixed.txt

# 测试网络性能
retry "sudo DEBIAN_FRONTEND=noninteractive apt install -y iperf3" "安装iperf3失败" || exit 1
## TCP带宽测试（单连接）
iperf3 -c 47.121.185.46 -t 60 -i 10 | tee $CLOUD_NAME/net_tcp_single.txt
## TCP带宽测试（多连接）
iperf3 -c 47.121.185.46 -t 60 -P 4 -i 10 | tee $CLOUD_NAME/net_tcp_multi.txt
## TCP下载带宽
iperf3 -c 47.121.185.46 -R -t 60 -i 10 | tee $CLOUD_NAME/net_tcp_download.txt
## TCP双向同时测试
iperf3 -c 47.121.185.46 --bidir -t 60 -i 10 | tee $CLOUD_NAME/net_tcp_bidir.txt
## UDP带宽和丢包测试
iperf3 -c 47.121.185.46 -u -b 1G -t 60 -i 10 | tee $CLOUD_NAME/net_udp.txt