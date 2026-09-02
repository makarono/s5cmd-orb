#!/bin/sh
ORB_EVAL_TARGET="$(circleci env subst "${ORB_EVAL_TARGET}")"
ORB_STR_ARGUMENTS="$(echo "${ORB_STR_ARGUMENTS}" | circleci env subst)"
ORB_STR_PROFILE_NAME="$(circleci env subst "${ORB_STR_PROFILE_NAME}")"
ORB_STR_ENDPOINT_URL="$(circleci env subst "${ORB_STR_ENDPOINT_URL}")"

set -- s5cmd
if [ -n "${ORB_STR_PROFILE_NAME}" ]; then
    set -- "$@" --profile "${ORB_STR_PROFILE_NAME}"
fi
if [ -n "${ORB_STR_ENDPOINT_URL}" ]; then
    set -- "$@" --endpoint-url "${ORB_STR_ENDPOINT_URL}"
fi
set -- "$@" rm
if [ -n "${ORB_STR_ARGUMENTS}" ]; then
    IFS=' '
    for arg in $(echo "${ORB_STR_ARGUMENTS}" | sed 's/,[ ]*/,/g'); do
        set -- "$@" "$arg"
    done
fi
set -- "$@" "${ORB_EVAL_TARGET}"

set -x
"$@"
set +x
