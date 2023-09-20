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

layer2_name=$(echo "$LAMBDA_LAYER_2" | perl -ne 'print $1 if /:([^:]+)$/')
layer2_archive=fileb://$parent_directory/lambda_layer.zip
lambda_archive=fileb://$parent_directory/lambda_code.zip
requested_layer_version=$(jq .version <config.json)
if aws lambda get-layer-version --layer-name "$layer2_name" --version-number "$requested_layer_version"; then
	echo "version found"
else
	echo "error code $?"
	echo "version not found, building layer"
	sh build_layer.sh
	#check size, to remove
	pwd
	ls -lht
	ls -lht ..
	aws lambda publish-layer-version --layer-name "$layer2_name" --zip-file "$layer2_archive"
fi
if [ "$CREATE_LAMBDA" = "true" ]; then
	aws lambda create-function --function-name "$LAMBDA_NAME" --zip-file "$lambda_archive" --handler "$LAMBDA_HANDLER" --runtime "$LAMBDA_RUNTIME" --role "$LAMBDA_ROLE" --layers "$LAMBDA_LAYER_1:$LAMBDA_LAYER_1_VERSION" "$LAMBDA_LAYER_2:$requested_layer_version" --timeout "$LAMBDA_TIMEOUT" --memory-size "$LAMBDA_MEMORY_SIZE"
	aws lambda create-event-source-mapping --function-name "$LAMBDA_NAME" --event-source-arn "$QUEUE"
else
	aws lambda update-function-configuration --function-name "$LAMBDA_NAME" --handler "$LAMBDA_HANDLER" --runtime "$LAMBDA_RUNTIME" --role "$LAMBDA_ROLE" --layers "$LAMBDA_LAYER_1:$LAMBDA_LAYER_1_VERSION" "$LAMBDA_LAYER_2:$requested_layer_version" --timeout "$LAMBDA_TIMEOUT" --memory-size "$LAMBDA_MEMORY_SIZE"
	wait_lambda
	aws lambda update-function-code --function-name "$LAMBDA_NAME" --zip-file "$lambda_archive" --publish
fi
aws lambda put-function-concurrency --function-name "$LAMBDA_NAME" --reserved-concurrent-executions "$LAMBDA_CONCURRENCY"
echo "end script"
