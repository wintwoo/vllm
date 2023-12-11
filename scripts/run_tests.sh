#!/bin/bash

VLLM_HOST=[VLLM_HOST]
VLLM_PORT=8000
ZONE=asia-southeast1-b

OUTPUT_DIR=/mnt/disks/data
LLAMA2_7B_DIR=/mnt/disks/data/llama2-7b-chat-hf
LLAMA2_13B_DIR=/mnt/disks/data/llama2-13b-chat-hf
LLAMA2_17B_DIR=/mnt/disks/data/llama2-70b-chat-hf

# L4_7B="$LLAMA2_7B_DIR,1,1,1:2:4
# $LLAMA2_7B_DIR,2,1,1:2:4
# $LLAMA2_7B_DIR,4,1,1:2:4
# $LLAMA2_7B_DIR,8,1,1:2:4"

# L4_13B="$LLAMA2_13B_DIR,2,1,1:2:4
# $LLAMA2_13B_DIR,4,1,1:2:4
# $LLAMA2_13B_DIR,8,1,1:2:4"

# L4_70B="$LLAMA2_70B_DIR,4,1,1:2:4
# $LLAMA2_70B_DIR,8,1,1:2:4"

L4_7B="$LLAMA2_7B_DIR,1,1:2:4"


while IFS= read -r line; do
    tokens=(${line//,/ })
    echo Model: ${tokens[0]}, TP size: ${tokens[1]}
    # start vllm server
    gcloud compute ssh $VLLM_HOST --zone $ZONE --command \
        "source /etc/profile && screen -L -Logfile /tmp/out.log -d -m python3 -m vllm.entrypoints.api_server --model ${tokens[0]} --disable-log-requests --tensor-parallel-size ${tokens[1]} --swap-space 16 --max-model-len 2048"
    # run benchmarks at different request rates
    IFS=':' read -ra request_rates <<< ${tokens[2]}
    for i in "${request_rates[@]}"; do
        python3 benchmarks/benchmark_serving.py \
            --backend vllm \
            --tokenizer $HOME/llama2_tokenizer \
            --dataset $HOME/ShareGPT_V3_unfiltered_cleaned_split.json \
            --output_dir $HOME/results \
            --num_prompts 1000 \
            --request-rate $i
    done
    # kill vllm server
    gcloud compute ssh $VLLM_HOST --zone $ZONE --command \
        "pkill -U wwoo python3"

done <<< "$L4_7B"