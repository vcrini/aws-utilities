#!/usr/bin/env bash
#  pre_build:
#creating dynamically an array from string
printenv
IFS=',' read -r -a ecr_repositories <<< "$ECR"
IFS=',' read -r -a dpath <<< "$DOCKERFILE_PATH"
IFS=',' read -r -a dcontext <<< "$DOCKERFILE_CONTEXT"
aws ecr get-login-password  --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin  "$ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
echo "$DOCKERHUB_PASSWORD" | docker login --username "$DOCKERHUB_USER" --password-stdin
# testing before for a non scala version then for a scala
app_image_version=$(grep -Po '(?<=^export IMAGE_TAG=).+$' build.sh||grep -Po '(?<=^version := ")[^"]+' build.sbt)
ecr_urls=()
for ((i=0; i<${#ecr_repositories[@]}; i++))
do
  echo "ecr ${ecr_repositories[$i]}:"
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
#if it's a scala project, then S3_AWS_ACCESS_KEY_ID is defined
if grep -q . <<< "$S3_AWS_ACCESS_KEY_ID"; then
  # if is a scala project use scala image
  echo "[ECHO] Running using sbt publish to compile STEP at $(date)"
  aws_path=/root/.aws
  aws_config=$aws_path/config
  aws_cred=$aws_path/credentials
  sbt_path=/root/.sbt
  sbt_cred=$sbt_path/.s3credentials
  mkdir -p $aws_path $sbt_path
  printf "[default]\nregion=%s\noutput=json" "$S3_AWS_DEFAULT_REGION" > $aws_config
  cat $aws_config
  printf "[default]\naws_access_key_id=%s\naws_secret_access_key=%s" "$S3_AWS_ACCESS_KEY_ID" "$S3_SAKEY" > $aws_cred
  cat $aws_cred
  printf "roleArn=%s" "$S3_AWS_ROLE_ARN">  $sbt_cred
  cat $sbt_cred 
  BUILDS=("docker run -v $( pwd ):$( pwd )  -v $aws_path:$aws_path -v /root/.m2:/root/.m2 -v /root/.sbt:/root/.sbt -v /root/.ivy2:/root/.ivy2 -w $( pwd ) -e SBT_OPTS hseeberger/scala-sbt:8u212_1.2.8_2.12.8  sbt -no-colors -Denv=$environment $more_options clean docker:stage && cd target/docker/stage/ && docker build -t ${ecr_urls[0]} --cache-from  ${ecr_urls[0]} ." "docker build -t  ${ecr_urls[1]} --cache-from ${ecr_urls[1]} -f Dockerfile.httpd .")
  #cycling again on ecr repositories so if a single repo is given revproxy section is skipped
  for ((i=0; i<${#ecr_repositories[@]}; i++))
  do 
    echo "${BUILDS[$i]}"
    eval "${BUILDS[$i]}" 
  done
else
  # otherwise no particular images are used
  for ((i=0; i<${#ecr_repositories[@]}; i++))
  do 
    BUILD="docker build -t ${ecr_urls[$i]} --cache-from  ${ecr_urls[$i]} --build-arg environment -f ${dpath[$i]} ${dcontext[$i]}"
    echo "$BUILD"
    eval "$BUILD" 
  done
fi

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
