#!/usr/bin/env bash
#  pre_build:
#creating dynamically an array from string
IFS=',' read -r -a ecr_repositories <<< "$ecr"
aws ecr get-login-password  --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin  "$account_id.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
echo "$dockerhub_password" | docker login --username "$dockerhub_user" --password-stdin
app_image_version=$(grep -Po '(?<=^export IMAGE_TAG=).+$' build.sh)
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
  ecr_urls+=("$repo")
  docker pull "$repo" || true
done
export ecr_urls
#docker run -it --rm hseeberger/scala-sbt:8u212_1.2.8_2.12.8 bash
echo "[ECHO] Running using sbt publish to compile STEP at $(date)"
aws_path=/root/.aws
aws_config=$aws_path/config
aws_cred=$aws_path/credentials
sbt_path=/root/.sbt
sbt_cred=$sbt_path/.s3credentials
mkdir -p $aws_path $sbt_path
echo "[default]\nregion=$s3_aws_default_region\noutput=json" > $aws_config
cat $aws_config
echo "[default]\naws_access_key_id=$s3_aws_access_key_id\naws_secret_access_key=$s3_sakey" > $aws_cred
cat $aws_cred
echo "roleArn=$s3_aws_role_arn" >  $sbt_cred
cat $sbt_cred 
#docker run -v $( pwd ):$( pwd )  -v $aws_path:$aws_path -v /root/.m2:/root/.m2 -v /root/.sbt:/root/.sbt -v /root/.ivy2:/root/.ivy2 -w $( pwd ) -e sbt_opts $repo:$sbt_image_version sbt -no-colors -Denv=$environment $more_options clean docker:stage &&
BUILDS=("docker run -v $( pwd ):$( pwd )  -v $aws_path:$aws_path -v /root/.m2:/root/.m2 -v /root/.sbt:/root/.sbt -v /root/.ivy2:/root/.ivy2 -w $( pwd ) -e sbt_opts hseeberger/scala-sbt:8u212_1.2.8_2.12.8  sbt -no-colors -Denv=$environment $more_options clean docker:stage && cd target/docker/stage/ && docker build -t ${ecr_urls[0]} --cache-from  ${ecr_urls[0]} .")
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
