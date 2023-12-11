#!/bin/bash

VLLM_HOST=[VLLM_HOST]
VLLM_CLIENT=[VLLM_CLIENT]
VLLM_PORT=8000
ZONE=asia-southeast1-b

OUTPUT_DIR=[OUTPUT_DIR] # benchmark result files
VLLM_SRC=[VLLM_SRC] # where you cloned this repo
VLLM_DATASET=[VLLM_DATASET] # path to the VLLM benchmark dataset
VLLM_TOKENIZER=[VLLM_TOKENIZER] # path to the Llama2 tokenizer files

LLAMA2_7B_DIR=[LLAMA2_7B_DIR] # 7B pretrained weights dir
LLAMA2_13B_DIR=[LLAMA2_13B_DIR] # 13B pretrained weights dir
LLAMA2_70B_DIR=[LLAMA2_70B_DIR] # 70B pretrained weights dir

NUM_PROMPTS=10

# Benchmarks to run - format:
# BENCH="model_dir,gpu_type,tensor_parallel_size,request_rate_1:request_rate_2:request_rate_3 ..."
#
# Pass to the run_benchmark function using
# run_benchmark $BENCH

L4_7B="$LLAMA2_7B_DIR,l4,1,inf:1:2:3:4
$LLAMA2_7B_DIR,l4,2,inf:1:2:3:4,5,6
$LLAMA2_7B_DIR,l4,4,inf:1:2:3:4,5,6:7:8"

L4_13B="$LLAMA2_13B_DIR,l4,2,inf:1:2:3:4
$LLAMA2_13B_DIR,l4,4,inf:1,2:3:4:5:6
$LLAMA2_13B_DIR,l4,8,inf:1:2:3:4,5,6,7,8"

L4_70B="$LLAMA2_70B_DIR,l4,2,inf:1:2:3:4
$LLAMA2_70B_DIR,l4,4,inf:1,2:3:4:5:6
$LLAMA2_70B_DIR,l4,8,inf:1:2:3:4,5,6,7,8"

TEST_7B="$LLAMA2_7B_DIR,l4,1,inf:1"

run_benchmark() {
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
                echo Waiting for vllm to start up, output is [$last_log] ...
            fi
        done
        # run benchmarks at different request rates
        IFS=':' read -ra request_rates <<< ${tokens[3]}
        for i in "${request_rates[@]}"; do
            echo Running benchmark at $i qps with tp_size ${tokens[2]}
            gcloud compute ssh $VLLM_CLIENT --zone $ZONE --command \
                "source /etc/profile && cd $VLLM_SRC && screen -L -Logfile /tmp/out.log -d -m python3 benchmarks/benchmark_serving.py --backend vllm --host $VLLM_HOST --port $VLLM_PORT --gpu_type ${tokens[1]} --tokenizer $VLLM_TOKENIZER --dataset $VLLM_DATASET --output_dir $OUTPUT_DIR --num-prompts $NUM_PROMPTS --request-rate $i --tp_size ${tokens[2]} --fixed_output_length"
            while true; do
                last_log=$(gcloud compute ssh $VLLM_CLIENT --zone $ZONE --command \
                    "ps -ef | grep benchmark_serving.py | grep -v grep")
                if [[ "$last_log" = "" ]]; then
                    echo Benchmark complete!
                    break
                else
                    echo Waiting for benchmark to complete ...
                fi
            done
        done
        # kill vllm server
        echo Stopping vllm server ...
        gcloud compute ssh $VLLM_HOST --zone $ZONE --command \
            "pkill -9 -U $(whoami) python3"
        sleep 15
    done <<< "$1"
}

# run_benchmark $L4_7B
# run_benchmark $L4_13B
# run_benchmark $L4_70B
run_benchmark $TEST_7B