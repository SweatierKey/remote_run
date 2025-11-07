#!/usr/bin/env bash

SCRIPT="$1"
shift

REMOTE_ARGS=()
EXTRA_FILES=()
HOSTS=()

while [[ "$#" -gt 0 ]]; do
	if [[ "$1" == "--" ]]; then
		shift
		REMOTE_ARGS=("$@")
		break
	elif [[ -f "$1" ]]; then
		EXTRA_FILES+=("$1")
		shift
	else
		HOSTS+=("$1")
		shift
	fi
done

echo "SCRIPT: ${SCRIPT}"
echo "REMOTE_ARGS: ${REMOTE_ARGS[@]}"
echo "EXTRA_FILES: ${EXTRA_FILES[@]}"
echo "HOSTS: ${HOSTS[@]}"
