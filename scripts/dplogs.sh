#!/bin/bash

#########################################################################
# dplogs.sh - Lightweight CLI tool for fetching Datapower logs via SOMA.
#
# Author:   Brendon Stephens
# Created:  June 2025
#########################################################################

set -e # exit on error

usage() {
    echo
    echo "Usage: $0 <host> [options]"
    echo
    echo "Required:"
    echo "  <host>                  Datapower hostname to query"
    echo "  --user <username>      HTTP basic auth username"
    echo
    echo "Options:"
    echo "  -f                      Follow mode (like tail -f)"
    echo "  -p <pattern>            Regex pattern to filter on"
    echo "  --lines <N>             Show only last N lines"
    echo "  --file <path>           File to fetch (default: logtemp:/default-log)"
    echo "  --domain <name>         Datapower domain to query (default: default)"
    echo "  -u, --user <username>   HTTP basic auth username"
    echo "  --password <password>   HTTP basic auth password (will prompt if not set)"
    echo "  -h, --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0 localhost -u admin"
    echo "      Show the last 100 lines from 'default-log' in 'default' domain"
    echo
    echo "  $0 localhost -u admin -f"
    echo "      Follow log output in real-time (like tail -f)"
    echo
    echo "  $0 localhost -u admin --domain prod --file error.log --lines 200"
    echo "      Show last 200 lines of 'error.log' in 'prod' domain"
    echo
    echo "  $0 localhost -u admin -p 'fail|error|denied'"
    echo "      Show lines matching failure-related keywords"
    echo
    echo "  $0 localhost -u admin -f --file error.log -p '0x8120002f|handshake'"
    echo "      Follow 'error.log' and highlight SSL handshake failures"
    echo
    echo "  $0 localhost -u admin -p 'GatewayScript.*(Exception|Error|throw)'"
    echo "      Show GatewayScript runtime errors and exception traces"
}

SLEEP_INTERVAL=0.5

HOST=""
USERNAME=""
PASSWORD=""
FOLLOW=false
PATTERN=""
LINE_LIMIT=50
DOMAIN="default"
FILE="default-log"

REQUIRED_CMDS=(curl base64 awk sed grep)

for CMD in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "Missing required dependency: $CMD" >&2
        exit 1
    fi
done

while [[ $# -gt 0 ]]; do
    case "$1" in
    -f)
        FOLLOW=true
        shift
        ;;
    -p)
        PATTERN="$2"
        shift 2
        ;;
    --lines)
        LINE_LIMIT="$2"
        shift 2
        ;;
    --domain)
        DOMAIN="$2"
        shift 2
        ;;
    --file)
        FILE="$2"
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

if [[ -z "$PASSWORD" ]]; then
    read -s -p "Password for $USERNAME@$HOST: " PASSWORD
    echo
fi

# store req/res in temp files
REQ_XML=$(mktemp)
RES_XML=$(mktemp)

# clean up the req/res files on exit
cleanup() {
    rm -f "$REQ_XML" "$RES_XML"
}

# always cleanup, regardless of how we exit
trap cleanup EXIT INT TERM

if [[ ! "$FILE" == *":/"* ]]; then
    FILE="logtemp:/$FILE"
fi

echo "Running dplogs.sh with args:"
echo "  Host         : $HOST"
echo "  Domain       : $DOMAIN"
echo "  Username     : $USERNAME"
#echo "  Password     : $PASSWORD"
echo "  Log File     : $FILE"
#echo "  Request XML  : $REQ_XML"
#echo "  Response XML : $RES_XML"
echo

# build the soma request xml
cat <<EOF >$REQ_XML
<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
    <env:Body>
        <man:request domain="${DOMAIN}" xmlns:man="http://www.datapower.com/schemas/management">
            <man:get-file name="${FILE}"/>
        </man:request>
    </env:Body>
</env:Envelope>
EOF

fetch_log() {
    local HTTP_STATUS
    local RESPONSE

    RESPONSE=$(curl -ks -w "%{http_code}" -o "$RES_XML" \
        -u "$USERNAME:$PASSWORD" \
        -H "Content-Type: text/xml; charset=utf-8" \
        -X POST "https://$HOST:5550/service/mgmt/current" \
        -d "@$REQ_XML")
    RC=$?
    HTTP_STATUS="${RESPONSE: -3}"

    if [[ $RC -ne 0 ]]; then
        echo "Error: Could not retrieve log file (curl exit code $RC)" >&2
        exit 1
    elif [[ "$HTTP_STATUS" -ne 200 ]]; then
        echo "Error: Could not retrieve log file (http status: $RC)" >&2
        cat "$RES_XML" >&2
        exit 1
    else
        # check for soap fault
        if grep -q "<faultcode>" "$RES_XML"; then
            echo "Error: Datapower returned soap fault" >&2
            cat "$RES_XML" >&2
        elif grep -q ">Authentication failure<" "$RES_XML"; then
            echo "Error: Datapower returned authentication failure. Check username and password, and that the domain exists" >&2
            exit 1
        elif grep -q ">Cannot read the specified file<" "$RES_XML"; then
            echo "Error: Datapower could not find the specified file: $FILE" >&2
            exit 1
        else
            # extract and decode log content
            #xmllint --xpath "string(//*[local-name()='file']/text())" "$RES_XML" | base64 -d

            # preference this dirty sed over the additional xmllint dependency
            sed -n 's/.*>\(.*\)<\/dp:file>.*/\1/p' "$RES_XML" | base64 -d
        fi
    fi
}

# make the output pretty with traffic light colours
colourize() {
    sed -E \
        -e 's/(fail(ed|ure)?|error|denied|unauthorized|rejected|fatal|critical|refused|invalid)/\x1b[31m\1\x1b[0m/Ig' \
        -e 's/(warn(ing)?|timeout|retry)/\x1b[33m\1\x1b[0m/Ig' \
        -e 's/\b(success|succeeded|ok|passed|allowed|authorized)\b/\x1b[32m\1\x1b[0m/Ig'
}

# restrict how many lines are output in the terminal
limit_lines() {
    if ((LINE_LIMIT > 0)); then
        tail -n "$((LINE_LIMIT))"
    else
        cat
    fi
}

# filter the output based on pattern
apply_pattern() {
    # exclude error codes that may spam the logs due to soma calls
    if [[ ! "$FILE" == *"audit"* ]]; then
        local EXCLUDE='xml-mgmt|xmlmgmt|xmlmgr|0x80c00004|0x8060022f|0x82400029|0x81000033|0x81000019|0x81000736|0x8120002f|0x8060015e'
    else
        local EXCLUDE='xml-mgmt|xmlmgmt|xmlmgr'
    fi

    awk -v pat="$PATTERN" -v exclude="$EXCLUDE" -v colour="\x1b[34m" -v reset="\x1b[0m" '
        BEGIN { n = 0; matched = 0 }

        # match timestamp to indicate the start of the log line
        #   20250618T091322.125Z
        #   Mon Jun 16
        /^[0-9]{8}T[0-9]{6}/ || /[A-Z][a-z]{2} [A-Z][a-z]{2} [0-9]{2}/ {

            # if weve been processing a block print it
            # a block is a group of lines related to a
            # single timestamp long line. (eg. stack trace)

            if (matched)
                for (i = 0; i < n; i++) print block[i]
                #print ""

            # now weve printed the block reset tracker
            n = 0; matched = 0

            # dont print the excluded lines
            if ($0 ~ exclude) next

            # colour code the patterned lines
            if (pat == "" || $0 ~ pat) {
                if (pat != "") gsub(pat, colour "&" reset, $0)
                matched = 1
            }

            block[n++] = $0
            next
        }

        # these lines are not new long entries,
        # so add them to the block and we will
        # print them next time we match a timestmap
        { block[n++] = $0 }

        END {
            if (matched)
                for (i = 0; i < n; i++) print block[i]
                #print ""
        }
    '
}

OUTPUT=$(fetch_log)
echo "$OUTPUT" | colourize | apply_pattern | limit_lines

# if we are not in follow mode, exit out.
if ! $FOLLOW; then
    exit 0
fi

sleep "$SLEEP_INTERVAL"

LAST_OUTPUT="$OUTPUT"
while true; do
    OUTPUT=$(fetch_log)

    # compare and filter new lines from the output
    NEW_LINES=$(diff <(echo "$LAST_OUTPUT") <(echo "$OUTPUT") | grep '^> ' | sed 's/^> //')

    [[ -n "$NEW_LINES" ]] && echo "$NEW_LINES" | colourize | apply_pattern

    LAST_OUTPUT="$OUTPUT"
    sleep "$SLEEP_INTERVAL"
done
