model=deepseek-ai/DeepSeek-R1
tokenizer=/workspace/models/DeepSeek-R1
API_KEY='NOT USED'

# 超长文本(input_mean+output_mean<=131072左右)
# 超小并发(max_concurrency=8)
for concurrency in 2 4 8; do

  genai-perf profile \
    --model ${model} \
    --tokenizer ${tokenizer} \
    --endpoint-type chat \
    --endpoint /v1/chat/completions \
    --streaming \
    --url http://localhost:8000 \
    --synthetic-input-tokens-mean 130000 \
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