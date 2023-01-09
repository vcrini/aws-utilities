#!/usr/bin/env bash
#  pre_build:
#creating dynamically an array from string
IFS=',' read -r -a ecr_repositories <<< "$ECR"
aws ecr get-login-password  --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin  "$ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
echo "$DOCKERHUB_PASSWORD" | docker login --username "$DOCKERHUB_USER" --password-stdin
app_image_version=$(grep -Po '(?<=^version=).+' build.txt)
ecr_urls=()
for ((i=0; i<${#ecr_repositories[@]}; i++))
do
  echo "ecr: ${ecr_repositories[$i]}"
  echo "version: $app_image_version"
  repo=$(utilities/ecr_image_check.sh "$IMAGE_REPO" "${ecr_repositories[$i]}" "$app_image_version")
  echo "repo->$repo"
  image_version=$(utilities/remove_snapshot.sh "$app_image_version")
  echo "image_version->$image_version"
  repo=$repo:$app_image_version
  echo "repo->$repo"
  ecr_urls+=("$repo")
  docker pull "$repo" || true
done
export ecr_urls
echo "[ECHO] Running using sbt publish to compile STEP at $(date)"
BUILDS=("docker build -t ${ecr_urls[0]} --build-arg keytab_filename --cache-from  ${ecr_urls[0]} --file backend/Dockerfile ." "docker build -t ${ecr_urls[1]} --build-arg SERVER_NAME --build-arg BACKEND_CONTAINER --cache-from ${ecr_urls[1]} --file nginx/Dockerfile ." "docker build -t ${ecr_urls[2]} --build-arg keytab_filename --cache-from  ${ecr_urls[2]} --file backend/Dockerfile.crono ." "docker build -t ${ecr_urls[3]}  --build-arg REACT_APP_API_URL --build-arg REACT_APP_ME_ENDPOINT --build-arg REACT_APP_API_VERSION --build-arg REACT_APP_OPENID_URL --build-arg REACT_APP_TEST_ENVIRONMENT --cache-from  ${ecr_urls[3]} --file frontend/Dockerfile frontend")

#cycling again on ecr repositories so if a single repo is given revproxy section is skipped
for ((i=0; i<${#ecr_repositories[@]}; i++))
do 
  echo "${BUILDS[$i]}"
  eval "${BUILDS[$i]}" 
done

#\\  post_build:
echo "[ECHO] Running post_build STEP at $(date)"
echo "${ecr_urls[0]}"
for ((i=0; i<${#ecr_urls[@]}; i++))
do 
 echo "[ECHO] Docker push image ${ecr_urls[$i]}"
 docker push "${ecr_urls[$i]}"
done 

help1="paste following content in 'imagedefinitions.json' inside repository '%s' if not present\n" 
echo "$help1"
printf '[{"name":"app","imageUri":"%s"},{"name":"web","imageUri":"%s"},{"name":"crono","imageUri":"%s"},{"name":"frontend","imageUri":"%s"}]' ${ecr_urls[0]} ${ecr_urls[1]} ${ecr_urls[2]} ${ecr_urls[3]} | python -m json.tool
printf 'app=%s' "${ecr_urls[0]}" > tag
