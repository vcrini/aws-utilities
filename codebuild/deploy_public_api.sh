#!/usr/bin/env bash
#  build:
#creating dynamically an array from string
IFS=',' read -r -a ecr_repositories <<< "$ecr"
tag=`cat tag`
app_image_version=`grep -Po '(?<=^export IMAGE_TAG=).+$' build.sh`
cd target/docker/stage
ecr_urls=()
for ((i=0; i<${#ecr_repositories[@]}; i++))
do
  echo "ecr ${ecr_repositories[$i]}:"
  repo=`utilities/ecr_image_check.sh $image_repo ${ecr_repositories[$i]} $app_image_version`
  echo "repo->$repo"
  image_version=`utilities/remove_snapshot.sh $app_image_version` 
  echo "image_version->$image_version"
  repo=$repo:$app_image_version
  echo "repo->$repo"
  ecr_urls+=($repo)
done
export repo=${ecr_urls[0]}
if [ "$AWS_DESIRED_COUNT" -gt "0" ]; then
   CMD="utilities/ecs-cli compose --cluster $AWS_ECS_CLUSTER --project-name $AWS_SERVICE_NAME$version_count --file docker-compose.yml --file docker-compose.aws.yml --ecs-params ecs-params.yml service up --deployment-max-percent $DEPLOYMENT_MAX_PERCENT --deployment-min-healthy-percent $DEPLOYMENT_MIN_HEALTHY_PERCENT  --force-deployment --tags $tag"
   echo $CMD
   exec $CMD
   else
   #CMD="utilities/ecs-cli compose --cluster $AWS_ECS_CLUSTER --project-name $AWS_SERVICE_NAME$version_count --file docker-compose.yml --file docker-compose.aws.yml --ecs-params ecs-params.yml service create --deployment-max-percent $DEPLOYMENT_MAX_PERCENT --deployment-min-healthy-percent $DEPLOYMENT_MIN_HEALTHY_PERCENT  --tags $tag | grep -o idempotent | head -1 || true"
   CMD="utilities/ecs-cli compose --cluster $AWS_ECS_CLUSTER --project-name $AWS_SERVICE_NAME$version_count --file docker-compose.yml --file docker-compose.aws.yml --ecs-params ecs-params.yml service create --deployment-max-percent $DEPLOYMENT_MAX_PERCENT --deployment-min-healthy-percent $DEPLOYMENT_MIN_HEALTHY_PERCENT  --tags $tag || true"
   
   echo "launching service creation"
   echo $CMD
   raw_output=$(bash -c "$CMD")
   output=$(echo $raw_output | grep -o idempotent | head -n1)
   #output=$(bash -c "echo $raw_output | grep -o idempotent | head -1")
   #output=$(bash -c "$filtered_output")
   echo ".1: output = $output"
   if [ "$output" = "idempotent" ]; then
      echo ".2"
      CMD="utilities/ecs-cli compose --cluster $AWS_ECS_CLUSTER --project-name $AWS_SERVICE_NAME$version_count --file docker-compose.yml --file docker-compose.aws.yml --ecs-params ecs-params.yml create --tags $tag | perl -ne 'print \$1 if /TaskDefinition=.([^\"]+)\"/'"
      echo $CMD
      echo "creating new task definition"
      task_definition=$(bash -c "$CMD")
      echo "task_definition is $task_definition"
      CMD="aws ecs update-service --no-cli-pager --cluster $AWS_ECS_CLUSTER --service $AWS_SERVICE_NAME$version_count --task-definition $task_definition"
      echo "applying task definition"
      echo $CMD
      echo ".2.2"
      eval "$CMD"
      echo ".2.3"
   fi
fi
echo ".3"
CMD="aws ecs describe-services  --cluster $AWS_ECS_CLUSTER  --services $AWS_SERVICE_NAME | jq '.services[0].desiredCount'"
echo $CMD
desiredCount=$(bash -c "$CMD")
echo "desiredCount= $desiredCount"
echo "AWS_DESIRED_COUNT= $AWS_DESIRED_COUNT"
if [ "$AWS_DESIRED_COUNT" -ne "$desiredCount" ]; then
   CMD="utilities/ecs-cli compose --cluster $AWS_ECS_CLUSTER --project-name $AWS_SERVICE_NAME$version_count service scale --deployment-max-percent $DEPLOYMENT_MAX_PERCENT --deployment-min-healthy-percent $DEPLOYMENT_MIN_HEALTHY_PERCENT $AWS_DESIRED_COUNT"
   echo $CMD
   exec $CMD
fi