#!/usr/bin/env bash
echo $1 | tr '[:upper:]' '[:lower:]' | awk '/-snapshot/{gsub(/-snapshot/, "")};{print}'

