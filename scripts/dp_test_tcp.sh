#!/bin/bash

#########################################################################
# dp_test_tcp.sh
#   Script to run a tcp connection test on a Datapower host.
#
# Author:   Brendon Stephens
# Created:  August 2025
#########################################################################

set -e # exit on error

usage() {
    echo
    echo "Usage: $0 <host> --remote-host <host> --user <username> --remote-port <port> [--iface <iface> --wait <seconds> --password <password>]"
    echo
    echo "Required:"
    echo "  <host>                  Datapower hostname to query"
    echo "  --remote-host <host>    The remote host to test"
    echo "  --remote-port <port>    The remote port to test"
    echo "  -u, --user <username>   HTTP basic auth username"
    echo "Options:"
    echo "  --password <password>   HTTP basic auth password (will prompt if not set)"
    echo "  --iface <interface>     The eth interface to run the test from"
    echo "                             Valid values: app1, app2, mgmt1, mgmt2"
    echo "  --wait <seconds>        Time to wait until timeout (default 2)"
    echo "  -h, --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0 datapower01.example.org --user admin --remote-host ldap.example.org --remote-port 636 --wait 1 --iface mgmt1"
}

# Defaults
WAIT=2

while [[ $# -gt 0 ]]; do
    case "$1" in
    --iface | --interface)
        INTERFACE="${2,,}"
        shift 2
        ;;
    --remote-host)
        REMOTE_HOST=$2
        shift 2
        ;;
    --remote-port)
        REMOTE_PORT=$2
        shift 2
        ;;
    --wait)
        WAIT="$2"
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
        usage
        exit 0
        ;;
    -*)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
    *)
        HOST="$1"
        shift
        ;;
    esac
done

if [[ -z "$HOST" ]]; then
    echo "Error: host is required"
    usage
    exit 1
fi

if [[ -z "$USERNAME" ]]; then
    echo "Error: --user <username> is required"
    usage
    exit 1
fi

if [[ -z "$REMOTE_HOST" ]]; then
    echo "Error: --remote-host is required"
    usage
    exit 1
fi

if [[ -z "$REMOTE_PORT" ]]; then
    echo "Error: --remote-port is required"
    usage
    exit 1
fi

if [[ -z "$PASSWORD" ]]; then
    read -s -p "Password for $USERNAME@$HOST: " PASSWORD
    echo
fi

echo

# store req/res in temp files
REQ_XML=$(mktemp)
RES_XML=$(mktemp)

# clean up the req/res files on exit
cleanup() {
    rm -f "$REQ_XML" "$RES_XML"
}

# always cleanup, regardless of how we exit
trap cleanup EXIT INT TERM

echo "Running dp_test_tcp.sh with args:"
echo "  Host           : $HOST"
#echo "  Username       : $USERNAME"
#echo "  Password      : $PASSWORD"
echo "  Remote Host    : $REMOTE_HOST"
echo "  Remote Port    : $REMOTE_PORT"
echo "  Interface      : $INTERFACE"
echo "  Timeout        : $WAIT second(s)"
#echo "  Request XML   : $REQ_XML"
#echo "  Response XML  : $RES_XML"
echo

# build the soma request xml
cat <<EOF >$REQ_XML
<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
   <env:Body>
        <man:request xmlns:man="http://www.datapower.com/schemas/management" domain="default">
        <man:do-action>
            <TCPConnectionTest>
                <RemoteHost>$REMOTE_HOST</RemoteHost>
                <RemotePort>$REMOTE_PORT</RemotePort>
                <timeout>$WAIT</timeout>
                <LocalAddress>$INTERFACE</LocalAddress>
            </TCPConnectionTest>
        </man:do-action>
        </man:request>
   </env:Body>
</env:Envelope>
EOF

HTTP_STATUS=""
RESPONSE=""

RESPONSE=$(curl -ks -w "%{http_code}" -o "$RES_XML" \
    -u "$USERNAME:$PASSWORD" \
    -H "Content-Type: text/xml; charset=utf-8" \
    -X POST "https://$HOST:5550/service/mgmt/current" \
    -d "@$REQ_XML")
RC=$?
HTTP_STATUS="${RESPONSE: -3}"

if [[ $RC -ne 0 ]]; then
    echo "Error: Could not execute test on server (curl exit code $RC)" >&2
    exit 1
elif [[ "$HTTP_STATUS" -ne 200 ]]; then
    echo "Error: Test on server failed (http status: $RC)" >&2
    cat "$RES_XML" >&2
    exit 1
else
    # check for soap fault
    if grep -q "<faultcode>" "$RES_XML"; then
        echo "Error: Datapower returned soap fault" >&2
        cat "$RES_XML" >&2
    elif grep -q ">Authentication failure<" "$RES_XML"; then
        echo "Error: Datapower returned authentication failure. Check username and password." >&2
        exit 1
    elif grep -q "error-log" "$RES_XML"; then
        echo "Error: Connection test failed." >&2
        echo "  $(sed -n 's/.*<dp:log-event.*>\(.*\)<\/dp:log-event>.*/\1/p' $RES_XML)"
        exit 1
    else
        echo "Success: Connection test was successful"
        exit 0
    fi
fi
