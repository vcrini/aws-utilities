#!/usr/bin/env bash
#  pre_build:
#creating dynamically an array from string
printenv
IFS=',' read -r -a ecr_repositories <<< "$ECR"
aws ecr get-login-password  --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin  "$ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
echo "$DOCKERHUB_PASSWORD" | docker login --username "$DOCKERHUB_USER" --password-stdin
version=("$(grep -Po '(?<=^version := ")[^"]+' build.sbt)" "$(grep -Po '(?<=^proxy_version := ")[^"]+' proxy_version.txt||true)")

ecr_urls=()
for ((i=0; i<${#ecr_repositories[@]}; i++))
do
  echo "ecr: ${ecr_repositories[$i]}"
  echo "version: ${version[$i]}"
  repo=$(utilities/ecr_image_check.sh "$IMAGE_REPO" "${ecr_repositories[$i]}" "${version[$i]}")
  echo "repo->$repo"
  image_version=$(utilities/remove_snapshot.sh "${version[$i]}")
  echo "image_version->$image_version"
  repo=$repo:${version[$i]}
  echo "repo->$repo"
  ecr_urls+=("$repo")
  docker pull "$repo" || true
  # checking for vulnerabilities
  docker scout cves "$repo" || true
   
done
export ecr_urls
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

echo "[ECHO] Running post_build STEP at $(date)"
echo "${ecr_urls[0]}"
for ((i=0; i<${#ecr_urls[@]}; i++))
do 
 echo "[ECHO] Docker push image ${ecr_urls[$i]}"
 docker push "${ecr_urls[$i]}"
done 

help1="paste following content in 'imagedefinitions.json' inside repository '%s' if not present\n" 
echo "$help1"
if [ ${#ecr_repositories[@]} -gt 1 ]
  then
    printf '[{"name":"app","imageUri":"%s"},{"name":"revproxy","imageUri":"%s"}]' "${ecr_urls[0]}" "${ecr_urls[1]}" | python -m json.tool
  else 
    printf '[{"name":"app","imageUri":"%s"}]' "${ecr_urls[0]}"| python -m json.tool
fi
printf 'app=%s' "${ecr_urls[0]}" > tag
