#!/bin/bash

#########################################################################
# wrapper.sh
#   Wrapper script for the Datapower logs CLI tool. This can be used to
#   look up a custom Datapower host inventory on a secure management
#   server, to help ease the lookup of server details.
#
# Author:   Brendon Stephens
# Created:  June 2025
#########################################################################

set -e # exit on error

while [[ $# -gt 0 ]]; do
    case "$1" in
    --domain)
        DOMAIN="$2"
        shift 2
        ;;
    -u | --user)
        USERNAME="$2"
        shift 2
        ;;
    --password)
        PASSWORD="$2"
        shift 2
        ;;
    -h | --help)
        echo "Wrapper script to support server inventory lookup."
        _dplogs.sh -h
        exit 0
        ;;
    -*)
        # forward the arg
        FORWARD_ARGS+=("$1")
        # if next arg is not another arg/null
        if [[ "$2" != -* && -n "$2" ]]; then
            # forward the arg value
            FORWARD_ARGS+=("$2")
            shift
        fi
        shift
        ;;
    *)
        # if we haven't set host, assume this arg is the host
        if [[ -z "$HOST" ]]; then
            HOST="$1"
            shift
        else
            # pass the rest down as args
            FORWARD_ARGS+=("$1")
            shift
        fi
        ;;
    esac
done

# tty aliases (when piping cmds)
exec 3</dev/tty
exec 4>/dev/tty

select_option() {
    local OPTIONS=("$@")
    select SELECTED in "${OPTIONS[@]}"; do
        if [[ -n $SELECTED ]]; then
            if [[ $SELECTED == $WILD ]]; then
                SELECTED='*'
            fi
            break
        else
            echo "Invalid selection"
            exit 1
        fi
    done <&3 >&4 # always read from tty (pipe support)
    echo "$SELECTED"
}

# TODO: Update with custom logic to lookup user based on host
lookup_host_user() {
    local HOST=$1
    # custom logic to lookup host cred on secure mgmt server
    echo "admin"
}

# TODO: Update with custom logic to lookup password based on host
lookup_host_pass() {
    local HOST=$1
    echo "admin"
}

echo

# TODO: Update with custom logic to lookup host from server inventory

# if host is not already provided
if [[ -z "$HOST" ]]; then
    if [[ -z "$DOMAIN" ]]; then
        # select a host and domain
        echo "Select the cluster:"
        CLUSTER=$(select_option "ClusterA" "ClusterB" "ClusterC")
        echo
        echo "Select the environment:"
        ENV=$(select_option "dev" "test" "stage" "prod")
        echo
        echo "Select the host:"
        HOST=$(select_option "${ENV,,}01.${CLUSTER,,}.com" "${ENV,,}02.${CLUSTER,,}.com" "${ENV,,}03.${CLUSTER,,}.com")
        echo
        echo "Select the domain:"
        DOMAIN=$(select_option "DomainA" "DomainB" "DomainC")
    else
        # only select a host
        echo "Select the environment:"
        ENV=$(select_option "dev" "test" "stage" "prod")
        echo
        echo "Select the host:"
        HOST=$(select_option "${ENV,,}01.${CLUSTER,,}.com" "${ENV,,}02.${CLUSTER,,}.com" "${ENV,,}03.${CLUSTER,,}.com")
        echo
    fi
else
    # if we have a host but not domain
    if [[ -z "$DOMAIN" ]]; then
        # select a domain
        echo "Select the domain:"
        DOMAIN=$(select_option "DomainA" "DomainB" "DomainC")
    fi
fi

echo

# lookup the creds for the host
USERNAME=$(lookup_host_user "$HOST")
PASSWORD=$(lookup_host_pass "$HOST")

#echo "Calling dplogs.sh with the following arguments:"
#echo "  Username    : $USERNAME"
#echo "  Password    : $PASSWORD"
#echo "  Host        : $HOST"
#echo "  Args        : ${FORWARD_ARGS[@]}"

./dplogs.sh localhost --user "admin" --password "admin" --domain "default" "${FORWARD_ARGS[@]}"
