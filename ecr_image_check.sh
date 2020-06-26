#!/usr/bin/env bash
# Example:
#    ./ecr_image_check.sh image_repo application_name version

if [[ $# -lt 3 ]]; then
    echo "Usage: $( basename $0 ) <image-repo> <application-name> <image-tag>"
    exit 1
fi

image_repo=$1
application_name=$2
app_image_version=$3

if echo $app_image_version | grep -iq snapshot; then
  app_repo=$image_repo$application_name-snapshot
else
  app_repo=$image_repo$application_name
  if utilities/find-ecr-image.sh $application_name $app_image_version >/dev/null; then
    echo "KO -> ECR image present but it's marked as immutable ... exiting"
    exit 1
  fi
fi
echo $app_repo



