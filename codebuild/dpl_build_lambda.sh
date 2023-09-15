#!/usr/bin/env bash
#  pre_build:
#creating dynamically an array from string
echo "start script"
sh build_lambda.sh

#aws lambda create-event-source-mapping --function-name "$LAMBDA_NAME" --event-source-arn  "$QUEUE"
#exit
layer2_name=$(echo "$LAMBDA_LAYER_2" | perl -ne 'print $1 if /:([^:]+)$/')
layer2_archive=fileb://layer.zip
requested_layer_version=$(jq .version < config.json)
aws lambda get-layer-version --layer-name "$layer2_name" --version-number "$requested_layer_version"
exit
get_function=$(aws lambda get-function  --function-name "$LAMBDA_NAME")
get_layer_version=$(echo "$get_function" | jq '.Configuration|.Layers|.[1]'| jq .Arn | perl -ne 'print "$1\n" if /:(\d+)\"/')
echo "version found: $get_layer_version"
put_layer_version=$(jq .version < config.json)
echo "version requested: $put_layer_version"
if [ "$get_layer_version" -ne "$put_layer_version" ] 
then
  #if it fails does not return error code !=0 but fails publish
  sh build_layer.sh
  #echo "error code $?"
  aws lambda publish-layer-version  --layer-name "$layer2_name" --zip-file $layer2_archive
fi
if [ "$CREATE_LAMBDA" = "true" ] 
then
  aws lambda create-function --function-name "$LAMBDA_NAME" --zip-file fileb://lambda.zip --handler "$LAMBDA_HANDLER" --runtime "$LAMBDA_RUNTIME" --role "$LAMBDA_ROLE" --layers "$LAMBDA_LAYER_1:$LAMBDA_LAYER_1_VERSION" "$LAMBDA_LAYER_2:$put_layer_version" --timeout "$LAMBDA_TIMEOUT" --memory-size "$LAMBDA_MEMORY_SIZE"  
  aws lambda create-event-source-mapping --function-name "$LAMBDA_NAME" --event-source-arn  "$QUEUE"
else
  aws lambda update-function-configuration --function-name "$LAMBDA_NAME"  --handler "$LAMBDA_HANDLER" --runtime "$LAMBDA_RUNTIME" --role "$LAMBDA_ROLE" --layers "$LAMBDA_LAYER_1:$LAMBDA_LAYER_1_VERSION" "$LAMBDA_LAYER_2:$put_layer_version" --timeout "$LAMBDA_TIMEOUT" --memory-size "$LAMBDA_MEMORY_SIZE"
  aws lambda update-function-code --function-name "$LAMBDA_NAME" --zip-file fileb://lambda.zip --publish
fi
aws lambda put-function-concurrency --function-name "$LAMBDA_NAME" --reserved-concurrent-executions "$LAMBDA_CONCURRENCY"
echo "end script"

