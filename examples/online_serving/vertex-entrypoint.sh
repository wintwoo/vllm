#!/bin/bash

# Define the prefix for environment variables to look for
PREFIX="VERTEX_VLLM_"
ARG_PREFIX="--"

# Initialize an array for storing the arguments
ARGS = ()

# Loop through all environment variables
while IFS='=' read -r key value; do
    # Remove the prefix from the key, convert to lowercase, and replace underscores with dashes
    arg_name=$(echo "${key#"${PREFIX}"}" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

    # Add the argument name and value to the ARGS array
    ARGS+=("${ARG_PREFIX}${arg_name}")
    if [ -n "$value" ]; then
        ARGS+=("$value")
    fi
done < <(env | grep "^${PREFIX}")

# Pass the collected arguments to the main entrypoint
exec python3 -m vllm.entrypoints.openai.api_server "${ARGS[@]}"