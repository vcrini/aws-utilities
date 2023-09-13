#!/usr/bin/env bash
#  pre_build:
#creating dynamically an array from string
printenv
echo "start script"
aws --version
sh build_lambda.sh
#aws lambda create-function --function-name "$LAMBDA_NAME" --zip-file fileb://lambda.zip --handler "$LAMBDA_HANDLER" --runtime "$LAMBDA_RUNTIME" --role "$LAMBDA_ROLE" --layers arn:aws:lambda:eu-west-1:580247275435:layer:LambdaInsightsExtension:38 arn:aws:lambda:eu-west-1:796341525871:layer:bitdpl-test-ordsimalg:2 
#aws lambda get-layer-version  --layer-name bitdpl-test-ordsimalg --version-number 2
get_function=$(aws lambda get-function  --function-name "$LAMBDA_NAME")
echo "$get_function"
get_layer_version=$(echo "$get_function" | jq '.Layers|.[1]'| jq .Arn | perl -ne 'print "$1\n" if /:(\d+)\"/')
echo "version found: $get_layer_version"
put_layer_version=$(jq .version < config.json)
echo "version requested: $put_layer_version"
if [ "$get_layer_version" -eq "$put_layer_version" ] 
then
  sh build_layer.sh
  aws lambda publish-layer-version  --layer-name bitdpl-test-ordsimalg --zip-file fileb://layer.zip  
fi
aws lambda update-function-configuration --function-name "$LAMBDA_NAME"  --handler "$LAMBDA_HANDLER" --runtime "$LAMBDA_RUNTIME" --role "$LAMBDA_ROLE" --layers "$LAMBDA_LAYER_1:$LAMBDA_LAYER_1_VERSION" "$LAMBDA_LAYER_2:$put_layer_version" --timeout $LAMBDA_TIMEOUT --memory-size $LAMBDA_MEMORY_SIZE
aws lambda put-function-concurrency --function-name "$LAMBDA_NAME" --reserved-concurrency-executions "$LAMBDA_CONCURRENCY"
aws lambda update-function-code --function-name "$LAMBDA_NAME" --zip-file fileb://lambda.zip --publish
aws lambda list-event-source-mappings  --function-name "$LAMBDA_NAME"
echo "end script"

