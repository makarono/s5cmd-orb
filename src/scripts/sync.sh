#!/bin/sh
ORB_EVAL_FROM="$(circleci env subst "${ORB_EVAL_FROM}")"
ORB_EVAL_TO="$(circleci env subst "${ORB_EVAL_TO}")"
ORB_STR_ARGUMENTS="$(echo "${ORB_STR_ARGUMENTS}" | circleci env subst)"
ORB_STR_PROFILE_NAME="$(circleci env subst "${ORB_STR_PROFILE_NAME}")"
ORB_STR_ENDPOINT_URL="$(circleci env subst "${ORB_STR_ENDPOINT_URL}")"
ORB_STR_NUMWORKERS="$(circleci env subst "${ORB_STR_NUMWORKERS}")"

set -- s5cmd
if [ -n "${ORB_STR_PROFILE_NAME}" ]; then
    set -- "$@" --profile "${ORB_STR_PROFILE_NAME}"
fi
if [ -n "${ORB_STR_ENDPOINT_URL}" ]; then
    set -- "$@" --endpoint-url "${ORB_STR_ENDPOINT_URL}"
fi
if [ -n "${ORB_STR_NUMWORKERS}" ]; then
    set -- "$@" --numworkers "${ORB_STR_NUMWORKERS}"
fi
set -- "$@" sync
if [ -n "${ORB_STR_ARGUMENTS}" ]; then
    IFS=' '
    for arg in $(echo "${ORB_STR_ARGUMENTS}" | sed 's/,[ ]*/,/g'); do
        set -- "$@" "$arg"
    done
fi
set -- "$@" "${ORB_EVAL_FROM}" "${ORB_EVAL_TO}"

set -x
"$@"
set +x
