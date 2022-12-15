#!/usr/bin/env bash
#  build:
#creating dynamically an array from string
IFS=';' read -r -a tg <<< "$target_group_ecs_cli_string"
target_group="${tg[@]/#/--target-groups }"
echo "target_group: $target_group"
IFS=',' read -r -a ecr_repositories <<< "$ecr"
v=`grep -Po '(?<=^export IMAGE_TAG=).+$' build.sh`
#reading proxy version or take value from base image
version=($v  `grep -Po '(?<=^proxy_version := ")[^"]+' proxy_version.txt || $v`)
tag=`cat tag`
ecr_urls=()
for ((i=0; i<${#ecr_repositories[@]}; i++))
do
  echo "ecr: ${ecr_repositories[$i]}"
  # if more than 2 repos then use first version for everyone after 2
  if [ "$i" -gt "2" ]; then
    version=${version[0]}
  else 
    version=${version[$i]}
  fi
  echo "version: ${version}"
  repo=`utilities/ecr_image_check.sh $image_repo ${ecr_repositories[$i]} ${version}`
  echo "repo->$repo"
  image_version=`utilities/remove_snapshot.sh ${version}` 
  echo "image_version->$image_version"
  repo=$repo:${version}
  echo "repo->$repo"
  ecr_urls+=($repo)
done
#extracting old name format for compatibility with the old and avoid need to change all docker-compose using 
# nomenclature as ${app_repo}:${app_image_version} and ${proxy_repo}:${proxy_image_version}
#scala app
repo=${ecr_urls[0]}
IFS=':' read -r -a repo_and_version <<< "$repo"
export app_repo=${repo_and_version[0]}
export app_image_version=${repo_and_version[1]}
#rev proxy if present
repo=${ecr_urls[1]}
IFS=':' read -r -a repo_and_version <<< "$repo"
export proxy_repo=${repo_and_version[0]}
export proxy_image_version=${repo_and_version[1]}
if [ "$AWS_DESIRED_COUNT" -gt "0" ]; then
   CMD="utilities/ecs-cli compose --cluster $AWS_ECS_CLUSTER --project-name $AWS_SERVICE_NAME$version_count --file docker-compose.yml --file docker-compose.aws.yml --ecs-params ecs-params.yml service up --deployment-max-percent $DEPLOYMENT_MAX_PERCENT --deployment-min-healthy-percent $DEPLOYMENT_MIN_HEALTHY_PERCENT  $target_group --force-deployment --tags $tag"
   echo $CMD
   service_up=$(bash -c "$CMD")
   echo "service_up result is $service_up"
   else
   CMD="utilities/ecs-cli compose --cluster $AWS_ECS_CLUSTER --project-name $AWS_SERVICE_NAME$version_count --file docker-compose.yml --file docker-compose.aws.yml --ecs-params ecs-params.yml service create --deployment-max-percent $DEPLOYMENT_MAX_PERCENT --deployment-min-healthy-percent $DEPLOYMENT_MIN_HEALTHY_PERCENT  $target_group --tags $tag || true"
   
   echo "launching service creation"
   echo $CMD
   raw_output=$(bash -c "$CMD")
   output=$(echo $raw_output | grep -o idempotent | head -n1)
   if [ "$output" = "idempotent" ]; then
      CMD="utilities/ecs-cli compose --cluster $AWS_ECS_CLUSTER --project-name $AWS_SERVICE_NAME$version_count --file docker-compose.yml --file docker-compose.aws.yml --ecs-params ecs-params.yml create --tags $tag | perl -ne 'print \$1 if /TaskDefinition=.([^\"]+)\"/'"
      echo $CMD
      echo "creating new task definition"
      task_definition=$(bash -c "$CMD")
      echo "task_definition is $task_definition"
      CMD="aws ecs update-service --no-cli-pager --cluster $AWS_ECS_CLUSTER --service $AWS_SERVICE_NAME$version_count --task-definition $task_definition"
      echo "applying task definition"
      echo $CMD
      eval "$CMD"
   fi
fi
CMD="aws ecs describe-services  --cluster $AWS_ECS_CLUSTER  --services $AWS_SERVICE_NAME | jq '.services[0].desiredCount'"
echo $CMD
desiredCount=$(bash -c "$CMD")
echo "desiredCount= $desiredCount"
echo "AWS_DESIRED_COUNT= $AWS_DESIRED_COUNT"
if [ "$AWS_DESIRED_COUNT" -ne "$desiredCount" ]; then
   CMD="utilities/ecs-cli compose --cluster $AWS_ECS_CLUSTER --project-name $AWS_SERVICE_NAME$version_count service scale --deployment-max-percent $DEPLOYMENT_MAX_PERCENT --deployment-min-healthy-percent $DEPLOYMENT_MIN_HEALTHY_PERCENT $AWS_DESIRED_COUNT"
   echo $CMD
   service_scale=$(bash -c "$CMD")
   echo "service scale output is $service_scale"
fi
