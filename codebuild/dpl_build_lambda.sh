#!/usr/bin/env bash
#  pre_build:
echo "start script"
IFS=',' read -r -a delete_events <<< "$DELETE_EVENTS"
parent_directory=$(dirname "$PWD")
sh build_lambda.sh
function wait_lambda {
  #for max 6 times sleeps for n seconds if function is not active
  get_function=""
  max_count=6
  count=0
  while [ "$get_function" != "ActiveSuccessful" ] && [ "$count" -lt "$max_count" ]; do
    count=$((count = count + 1))
    echo "$get_function"
    get_function=$(aws lambda get-function --function-name "$LAMBDA_NAME" | jq -r '.Configuration|[.State,.LastUpdateStatus]|join("")')
    sleep 10
  done
}

layer2_name=$(echo "$LAMBDA_LAYER_2" | perl -ne 'print $1 if /:([^:]+)$/')
layer2_archive=fileb://$parent_directory/lambda_layer_2.zip
layer1_name=$(echo "$LAMBDA_LAYER_1" | perl -ne 'print $1 if /:([^:]+)$/')
layer1_archive=fileb://$parent_directory/lambda_layer.zip
lambda_archive=fileb://$parent_directory/lambda_code.zip
requested_layer1_version=$(jq .lambda_layer_1_version <config.json)
requested_layer2_version=$(jq .lambda_layer_2_version <config.json)
if aws lambda get-layer-version --layer-name "$layer1_name" --version-number "$requested_layer1_version"; then
  echo "version found"
else
  echo "error code $?"
  echo "version not found, building layer"
  sh build_layer.sh
  #check size, to remove
  pwd
  ls -lht
  ls -lht ..
  aws lambda publish-layer-version --layer-name "$layer1_name" --zip-file "$layer1_archive"
fi
if aws lambda get-layer-version --layer-name "$layer2_name" --version-number "$requested_layer2_version"; then
  echo "version found"
else
  echo "error code $?"
  echo "version not found, building layer"
  sh build_layer_2.sh
  #check size, to remove
  pwd
  ls -lht
  ls -lht ..
  aws lambda publish-layer-version --layer-name "$layer2_name" --zip-file "$layer2_archive"
fi
if [ "$CREATE_LAMBDA" = "true" ]; then
  for ((i=0; i<${#delete_events[@]}; i++)); do
    aws lambda delete-event-source-mapping --uuid  "${delete_events[$i]}"
  done

  aws lambda create-function --function-name "$LAMBDA_NAME" --zip-file "$lambda_archive" --handler "$LAMBDA_HANDLER" --runtime "$LAMBDA_RUNTIME" --role "$LAMBDA_ROLE" --layers "$LAMBDA_LAYER_0:$LAMBDA_LAYER_0_VERSION" "$LAMBDA_LAYER_1:$requested_layer1_version" "$LAMBDA_LAYER_2:$requested_layer2_version" --timeout "$LAMBDA_TIMEOUT" --memory-size "$LAMBDA_MEMORY_SIZE"  --vpc-config SubnetIds="$LAMBDA_SUBNET",SecurityGroupIds="$LAMBDA_SECURITY_GROUP"
  aws lambda create-event-source-mapping --function-name "$LAMBDA_NAME" --event-source-arn "$QUEUE" --batch-size "$QUEUE_BATCH_SIZE" --maximum-batching-window-in-seconds "$QUEUE_BATCH_WINDOW" --scaling-config MaximumConcurrency="$QUEUE_MAXIMUM_CONCURRENCY"
  aws lambda create-event-source-mapping --function-name "$LAMBDA_NAME" --event-source-arn "$QUEUE2" --batch-size "$QUEUE2_BATCH_SIZE" --maximum-batching-window-in-seconds "$QUEUE2_BATCH_WINDOW" --scaling-config MaximumConcurrency="$QUEUE2_MAXIMUM_CONCURRENCY"
else
  aws lambda update-function-configuration --function-name "$LAMBDA_NAME" --handler "$LAMBDA_HANDLER" --runtime "$LAMBDA_RUNTIME" --role "$LAMBDA_ROLE" --layers "$LAMBDA_LAYER_0:$LAMBDA_LAYER_0_VERSION" "$LAMBDA_LAYER_1:$requested_layer1_version" "$LAMBDA_LAYER_2:$requested_layer2_version" --timeout "$LAMBDA_TIMEOUT" --memory-size "$LAMBDA_MEMORY_SIZE"
  wait_lambda
  aws lambda update-function-code --function-name "$LAMBDA_NAME" --zip-file "$lambda_archive" --publish
fi
aws lambda put-function-concurrency --function-name "$LAMBDA_NAME" --reserved-concurrent-executions "$LAMBDA_CONCURRENCY"
echo "end script"
