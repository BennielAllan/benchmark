model=deepseek-ai/DeepSeek-R1
tokenizer=/workspace/models/DeepSeek-R1
API_KEY='NOT USED'

# 长文本(input_mean+output_mean<=65536左右)
# 小并发(max_concurrency=16)
for concurrency in 4 8 16; do

  genai-perf profile \
    --model ${model} \
    --tokenizer ${tokenizer} \
    --endpoint-type chat \
    --endpoint /v1/chat/completions \
    --streaming \
    --url http://localhost:8000 \
    --synthetic-input-tokens-mean 64500 \
    --synthetic-input-tokens-stddev 0 \
    --output-tokens-mean 1000 \
    --output-tokens-stddev 0 \
    --extra-inputs ignore_eos:true \
    --concurrency ${concurrency} \
    --request-count $(($concurrency*10)) \
    --warmup-request-count $(($concurrency*2)) \
    --num-dataset-entries $(($concurrency*12)) \
    --random-seed 42 \
    -- \
    -v \
    -H 'Authorization: Bearer '${API_KEY}' \
    -H 'Accept: text/event-stream'
done