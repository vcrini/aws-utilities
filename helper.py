#!/usr/bin/env python3
# version 0.2

import argparse
import json
import logging
import os
import subprocess
import sys


def convert(string):
    return string.upper().replace('-', '_')


def command(command, args, exit_on_error=True):
    logging.info("Launching " + command)
    returncode = 0
    if args.dryrun:
        logging.info("this is a dry run")
    else:
        returncode = subprocess.call(command, shell=True)
    if exit_on_error and returncode != 0:
        sys.exit(returncode)


parser = argparse.ArgumentParser()
group = parser.add_mutually_exclusive_group()
group.add_argument('--dummy_command', action='store_true')
group.add_argument('--docker_build', action='store_true')
group.add_argument('--docker_pull', action='store_true')
group.add_argument('--docker_pull_or_die', action='store_true')
group.add_argument('--docker_push', action='store_true')
group.add_argument('--docker_tag', action='store_true')
group.add_argument('--ecs_compose', action='store_true')
group.add_argument('--ecs_compose_test', action='store_true')
group.add_argument('--write_image_definitions', action='store_true')
parser.add_argument('--debug', action='store_true')
parser.add_argument('--dryrun', action='store_true')
args = parser.parse_args()
datefmt = '%d-%b-%y %H:%M:%S'
fmt = '[ECHO] %(message)s at %(asctime)s'
if args.debug:
    logging.basicConfig(format=fmt, datefmt=datefmt, level=logging.DEBUG)
else:
    logging.basicConfig(format=fmt, datefmt=datefmt, level=logging.INFO)
# reading  json passed as standard input
data = json.load(sys.stdin)
items = ["{}:{}".format(x['name'], x['version']) for x in data]
# parsing commands
if args.dummy_command:
    command("ls -l", args)
elif args.docker_push:
    image_repo = os.environ['image_repo']
    for x in items:
        repo = "{}{}".format(image_repo, x)
        logging.info("Pushing {}".format(repo))
        command('docker push ' + repo, args)
elif args.docker_pull:
    # reading environment variables
    image_repo = os.environ['image_repo']
    logging.debug("items: {}".format(items))
    for x in items:
        repo = "{}{}".format(image_repo, x)
        logging.info("Pulling {}".format(repo))
        command('docker pull {}'.format(repo), args, False)
elif args.docker_pull_or_die:
    # reading environment variables
    image_repo = os.environ['image_repo']
    for x in items:
        repo = "{}{}".format(image_repo, x)
        logging.info("Pulling {}".format(repo))
        command('docker pull {}'.format(repo), args)
elif args.docker_tag:
    image_repo = os.environ['image_repo']
    for x in items:
        repo = "{}{}".format(image_repo, x)
        logging.info("Tagging {}".format(repo))
        command('docker tag {} {}'.format(repo, repo), args)
elif args.docker_build:
    image_repo = os.environ['image_repo']
    for x in data:
        repo = "{}{}:{}".format(image_repo, x['name'], x['version'])
        dockerfile = x['dockerfile']
        logging.info("Building {}".format(repo))
        command('docker build -t {} --cache-from {} -f {} .'.format(repo,
                                                                    repo, dockerfile), args)
elif args.ecs_compose_test:
    cluster = os.environ['AWS_ECS_CLUSTER']
    service_name = os.environ['AWS_SERVICE_NAME']
    logging.info("Building ecs environment variables test")
    for x in data:
        name = "{}_VERSION".format(convert(x['name']))
        os.putenv(name, x['version'])
        logging.debug("{} -> {}".format(name, x['version']))
    command("../utilities/ecs-cli compose --verbose  --cluster {} --project-name {} --file ../docker-compose.yml --file ../docker-compose.aws.yml --file ../docker-compose.aws.deploy.yml --ecs-params ../ecs-params.yml --target-group-arn arn:aws:elasticloadbalancing:eu-west-1:092467779203:targetgroup/fdh-all-adv-auth-tg/e926bcd8e7d9ab12 --target-group-arn arn:aws:elasticloadbalancing:eu-west-1:092467779203:targetgroup/fdh-all-adv-dashboard-tg/74e58b99ea8b261f --target-group-arn arn:aws:elasticloadbalancing:eu-west-1:092467779203:targetgroup/fdh-all-adv-python-tg/0382f3a4d7bdae02 service up".format(cluster, service_name), args)
elif args.ecs_compose:
    # TODO add cluster, project name, remove --force-deployment, putting --timeout 0
    logging.info("Building ecs environment variables")
    for x in data:
        name = "{}_VERSION".format(convert(x['name']))
        os.putenv(name, x['version'])
        logging.debug("{} -> {}".format(name, x['version']))
    command("../utilities/ecs-cli compose --verbose --file docker-compose.yml --file docker-compose.aws.yml --file ../docker-compose.aws.deploy.yml --ecs-params ../ecs-params.yml service up  --force-deployment", args)

elif args.write_image_definitions:
    image_repo = os.environ['image_repo']
    image_definitions = []
    for x in data:
        element = {"name": x['name'], "imageUri": "{}{}:{}".format(
            image_repo, x['name'], x['version'])}
        image_definitions.append(element)
    with open("/tmp/imagedefinitions.json", "w") as f:
        json.dump(image_definitions, f)
