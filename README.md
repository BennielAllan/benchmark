## 描述
为了测类openai api接口的长上下文服务(sharegpt太短)，修改了vllm的serving benchmark里的random逻辑使之使用"a "*n来保证token长度。  
另外修改了chat/completions的计数逻辑使输出计数计算了reasoning_content的长度，原版会因为没算reasoning content导致输出token计算错误。  
为了保证输出长度达到设定的output len，需要使用--ignore-eos ，如果api侧不支持ignore-eos如modelverse，则需要调试"a "来找到能让模型输出到所需长度的prompt。

## 安装
```pip install -r requirements.txt```

## 启动vLLM服务
在进行benchmark测试前启动vllm服务。按如下脚本启动服务。根据实际的机器配置（GPU卡数）设置tp与pp，以及最大并发数（--max-num-seqs）。
```
vllm serve models/DeepSeek-R1 \
    -tp 8 \
    -pp 2 \
    --served-model-name deepseek-ai/DeepSeek-R1 \ # 模型服务名
    --max-num-seqs 512 \
    --trust-remote-code \
    --enable-reasoning \                          # 启用思维链解析
    --reasoning-parser deepseek_r1                # 思维链解析模板设置
```
## 运行benchmark
涉及模型输入tokens计数,需要提供tokenizer,如果是远程测试，可以git clone 模型仓库，会默认下载tokenizer，不需要git lfs pull下载模型权重 
### I.用随机token进行benchmark

```
## 如果有密钥
export OPENAI_API_KEY=meow12345

## port+host形式测/v1/completions
python bench_serve.py \
    --backend vllm \
    --model deepseek-ai/DeepSeek-R1 \         # 对应模型服务名
    --tokenizer /data/models/DeepSeek-R1/ \   # 模型tokenizer位置
    --request-rate inf \                      # 所有请求发出时间
    --num-prompts 32 \                        # 总共发出请求数
    --dataset-name random \
    --max-concurrency 16 \                    # 预设的最大并发数
    --random-input-len 5734 \                 # 随机输入长度
    --random-output-len 1434 \                # 随机输出长度
    --ignore-eos \                            # 选择忽视eos token
    --host 127.0.0.1 \
    --port 8000 \
    --seed 42

## url形式测/v1/chat/completions,如modelverse的服务
python bench_serve.py \
    --backend openai-chat \
    --model deepseek-ai/DeepSeek-R1 \
    --tokenizer /data/models/DeepSeek-R1 \
    --request-rate inf \
    --num-prompts 32  \
    --max-concurrency 16 \
    --dataset-name random \
    --random-input-len 5734 \
    --random-output-len 1434 \
    --ignore-eos \
    --base_url https://deepseek.modelverse.cn \
    --endpoint /v1/chat/completions \
    --seed 42
```
### II.用sharegpt数据集进行benchmark
```
# 下载sharegpt数据集
wget https://huggingface.co/datasets/anon8231489123/ShareGPT_Vicuna_unfiltered/resolve/main/ShareGPT_V3_unfiltered_cleaned_split.json
# 国内网络环境可以用hf-mirror源
wget https://hf-mirror.com/datasets/anon8231489123/ShareGPT_Vicuna_unfiltered/resolve/main/ShareGPT_V3_unfiltered_cleaned_split.json

python bench_serve.py \
    --backend openai-chat \
    --model deepseek-ai/DeepSeek-R1 \
    --tokenizer /data/models/DeepSeek-R1 \
    --request-rate inf \
    --num-prompts 32  \
    --max-concurrency 16 \
    --dataset-name sharegpt \
    --dataset-path ShareGPT_V3_unfiltered_cleaned_split.json \ # sharegpt数据集路径
    --sharegpt-output-len 1024 \
    --ignore-eos \
    --host 127.0.0.1 \
    --port 8000 \
    --seed 42
```

#### 其中 --num-prompts 控制总共测几条数据 --max-concurrency 控制客户端同时会发给server端几条请求，如4就会发4条，且等4条都返回再处理下4条

## 使用此方法的测试链接
[线上 API 对比](https://ones.dml.ucloud.cn/wiki#/team/BVSybaCU/page/M4ndYSXo)  
[Atlas 800T A2 DS-R1测试,贵安部分](https://ones.dml.ucloud.cn/wiki#/team/BVSybaCU/page/LcCWQHLA)  

## 历史测试记录——以DeepSeek-R1为例
在DeepSeek-R1 H20测试中，并发在512～1024左右压满；在32～64左右可以保持单请求10 token/s；仅处理单并发时速度约为17 token/s。 ([DeepSeek-R1测试（vLLM v0.7.1)](https://u04wb5irxz.feishu.cn/sheets/SVNhswE0wh1cH6tJWSrcoU4Knyg?sheet=sHJovZ))

## 命令备忘
```
curl http://0.0.0.0:8000/v1/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "model": "qwen",
    "prompt": "你好啊，我是这个世界上最帅的人。",
    "ignore_eos": true,
    "max_tokens": 4096
  }'
```
