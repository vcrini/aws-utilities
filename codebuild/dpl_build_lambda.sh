#!/usr/bin/env bash
#  pre_build:
#creating dynamically an array from string
printenv
echo "start script"
aws --version
sh fake_script.sh
aws lambda create-function --function-name $LAMBDA_NAME --zip-file fileb://lambda.zip --handler $LAMBDA_HANDLER --runtime $LAMBDA_RUNTIME --role $LAMBDA_ROLE --layers arn:aws:lambda:eu-west-1:580247275435:layer:LambdaInsightsExtension:38 arn:aws:lambda:eu-west-1:796341525871:layer:bitdpl-test-ordsimalg:2 
echo "end script"
