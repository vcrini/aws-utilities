#!/usr/bin/env bash
#  pre_build:
#creating dynamically an array from string
printenv
aws ecr get-login-password  --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin  "$ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
echo "$DOCKERHUB_PASSWORD" | docker login --username "$DOCKERHUB_USER" --password-stdin
echo "TODO lambda deploy"

