#!/bin/bash

VLLM_HOST=[VLLM_HOST]
VLLM_CLIENT=[VLLM_CLIENT]
VLLM_PORT=8000
ZONE=asia-southeast1-b

OUTPUT_DIR=[OUTPUT_DIR]
VLLM_SRC=[VLLM_SRC_PATH]
VLLM_DATASET=[VLLM_DATASET]
VLLM_TOKENIZER=[VLLM_TOKENIZER]

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

L4_7B="$LLAMA2_7B_DIR,l4,1,inf:1:2:4"


while IFS= read -r line; do
    tokens=(${line//,/ })
    echo Model: ${tokens[0]}, GPU type: ${tokens[1]}, TP size: ${tokens[2]}
    # start vllm server
    gcloud compute ssh $VLLM_HOST --zone $ZONE --command \
        "source /etc/profile && screen -L -Logfile /tmp/out.log -d -m python3 -m vllm.entrypoints.api_server --model ${tokens[0]} --disable-log-requests --tensor-parallel-size ${tokens[2]} --swap-space 16 --max-model-len 2048"
    # wait for vllm server to start
    while true; do
        echo Waiting a few minutes for vllm server ...
        sleep 120
        last_log=$(gcloud compute ssh $VLLM_HOST --zone $ZONE --command "tail -n1 /tmp/out.log")
        if [[ "$last_log" =~ ^.*Uvicorn[[:space:]]running.*$ ]]; then
            break
        else

            echo Waiting longer, output is [$last_log] ...
        fi
    done
    # run benchmarks at different request rates
    IFS=':' read -ra request_rates <<< ${tokens[3]}
    for i in "${request_rates[@]}"; do
        echo Running benchmark at $i qps
        gcloud compute ssh $VLLM_CLIENT --zone $ZONE --command \
            "source /etc/profile && cd $VLLM_SRC && python3 benchmarks/benchmark_serving.py --backend vllm --host $VLLM_HOST --port $VLLM_PORT --gpu_type ${tokens[1]} --tokenizer $VLLM_TOKENIZER --dataset $VLLM_DATASET --output_dir $OUTPUT_DIR --num-prompts 10 --request-rate $i"
    done
    # kill vllm server
    gcloud compute ssh $VLLM_HOST --zone $ZONE --command \
        "pkill -U $(whoami) python3"
    sleep 30
done <<< "$L4_7B"