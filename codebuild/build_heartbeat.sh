#!/usr/bin/env bash
#  pre_build:
#creating dynamically an array from string
IFS=',' read -r -a ecr_repositories <<< "$ecr"
echo "0.2 -> *${ecr_repositories[0]}*"
pwd
aws ecr get-login-password  --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin  "$account_id.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
#docker login --username "$dockerhub_user" --password "$dockerhub_password"
echo "$dockerhub_password" | docker login --username "$dockerhub_user" --password-stdin
app_image_version=$(grep -Po '(?<=^export IMAGE_TAG=).+$' build.sh)
ecr_urls=()
for ((i=0; i<${#ecr_repositories[@]}; i++))
do
  echo "ecr ${ecr_repositories[$i]}:"
  repo=$("utilities/ecr_image_check.sh $image_repo ${ecr_repositories[$i]} $app_image_version")
  echo "repo->$repo"
  image_version=$("utilities/remove_snapshot.sh $app_image_version")
  echo "image_version->$image_version"
  repo=$repo:$app_image_version
  echo "repo->$repo"
  ecr_urls+=("$repo")
  docker pull "$repo" || true
done
export ecr_urls

BUILDS=("docker build -t ${ecr_urls[0]} --cache-from  ${ecr_urls[0]} --build-arg environment .")
for ((i=0; i<${#BUILDS[@]}; i++))
do 
  echo "${BUILDS[$i]}"
  eval "${BUILDS[$i]}" 
done

#\\  post_build:
echo "[ECHO] Running post_build STEP at $(date)"
echo "${ecr_urls[0]}"
for ((i=0; i<${#ecr_urls[@]}; i++))
do 
 echo "[ECHO] Docker push image $${ecr_urls[$i]}"
 docker push "${ecr_urls[$i]}"
done 

help1="paste following content in 'imagedefinitions.json' inside repository '%s' if not present\n" 
echo "$help1"
printf '[{"name":"app","imageUri":"%s"}]' "${ecr_urls[0]}"| python -m json.tool
printf 'app=%s' "${ecr_urls[0]}" > tag

# to put in other file
#artifacts:
#    files:
#      - build.sh
#      - ecs-params.yml
#      - docker-compose.yml
#      - docker-compose.aws.yml
#      - tag
