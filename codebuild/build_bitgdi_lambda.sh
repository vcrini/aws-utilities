#!/usr/bin/env bash
#  pre_build:
echo "start script"

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

# ENVIRONMENT=$(perl -e '@_=map {"$_=$ENV{$_}"} qw(NON_PRIORITY_QUEUE_URL PRIORITY_QUEUE_URL PRIORITY_QUEUE_ARN OUTPUT_QUEUE_URL RDS_SQL_TYPE RDS_SERVER_NAME RDS_PORT RDS_DB_NAME RDS_USER); print join(",",@_)')
# echo "Environment is $ENVIRONMENT"
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
# if aws lambda get-layer-version --layer-name "$layer2_name" --version-number "$requested_layer2_version"; then
#   echo "version found"
# else
#   echo "error code $?"
#   echo "version not found, building layer"
#   sh build_layer_2.sh
#   #check size, to remove
#   pwd
#   ls -lht
#   ls -lht ..
#   aws lambda publish-layer-version --layer-name "$layer2_name" --zip-file "$layer2_archive"
# fi
if [ "$CREATE_LAMBDA" = "true" ]; then
  echo "this should never happen so now I exit with code 2"
  exit 2
else
  # maybe this can be removed
  aws lambda update-function-configuration --function-name "$LAMBDA_NAME" --handler "$LAMBDA_HANDLER" --runtime "$LAMBDA_RUNTIME" --role "$LAMBDA_ROLE" --layers "$LAMBDA_LAYER_1:$requested_layer1_version" --timeout "$LAMBDA_TIMEOUT" --memory-size "$LAMBDA_MEMORY_SIZE" --tracing-config Mode="$TRACING_CONFIG_MODE"
  wait_lambda
  aws lambda update-function-code --function-name "$LAMBDA_NAME" --zip-file "$lambda_archive" --publish
fi
# also this
# not using concurrency since it's not defined:w
# aws lambda put-function-concurrency --function-name "$LAMBDA_NAME" --reserved-concurrent-executions "$LAMBDA_CONCURRENCY"
echo "end script"
