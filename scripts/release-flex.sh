#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE_NAME=docker.flexible-software.com/flex.litellm

docker build -t "$IMAGE_NAME:latest" -f Dockerfile .
docker push "$IMAGE_NAME:latest"
