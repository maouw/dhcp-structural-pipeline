#!/usr/bin/env bash
set -eE -o pipefail
shopt -qs lastpipe

nproc="$(nproc || grep -c '^processor[[:space:]]*:' /proc/cpuinfo || true)"
nproc="${nproc:-1}"
arg="${1:-1}"
declare -i result
case "${arg}" in
[0-9]*%)
    arg="${arg%%%}"
	result=$(((nproc * arg) / 100))
    ((result < 1)) && result=1
    ;;
=[0-9]*)
	if ((arg < 1)); then
		result=1
	elif ((arg > nproc)); then
		result="${nproc}"
	else
		result="${arg}"
	fi ;;
*) result=nproc
	;;
esac
echo "${result}"
