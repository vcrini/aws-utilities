#!/usr/bin/env bash
echo $1 | tr '[:upper:]' '[:lower:]' | awk -F'-' '{print $1}'

