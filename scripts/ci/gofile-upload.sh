#!/usr/bin/env bash
#
# Upload one or more files to Gofile and print the download page URL(s).
#
# Environment:
#   GOFILE_TOKEN      Optional Gofile account token. Guest uploads work without it.
#   GOFILE_FOLDER_ID  Optional destination folder ID. Requires GOFILE_TOKEN.
#   GOFILE_SERVER     Optional server override, e.g. store1.
#
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: $0 FILE [FILE...]" >&2
    exit 2
fi

TOKEN="${GOFILE_TOKEN:-}"
FOLDER_ID="${GOFILE_FOLDER_ID:-}"
SERVER="${GOFILE_SERVER:-}"

if [ -n "$FOLDER_ID" ] && [ -z "$TOKEN" ]; then
    echo "::warning title=Gofile folder ignored::GOFILE_FOLDER_ID requires GOFILE_TOKEN; uploading to the guest root instead."
    FOLDER_ID=""
fi

if [ -z "$SERVER" ]; then
    SERVERS_JSON=$(curl -fsS --retry 5 --retry-delay 3 https://api.gofile.io/servers)
    SERVER=$(jq -r '.data.servers[0].name // empty' <<<"$SERVERS_JSON")
fi
if [ -z "$SERVER" ]; then
    echo "::error title=Gofile::Could not get an upload server from the Gofile API."
    exit 1
fi
echo "==> Gofile upload server: $SERVER"

LINKS_FILE="${GOFILE_LINKS_FILE:-$PWD/gofile-links.txt}"
: > "$LINKS_FILE"
FIRST_URL=""

for FILE in "$@"; do
    if [ ! -f "$FILE" ]; then
        echo "::error title=Gofile::File not found: $FILE"
        exit 1
    fi

    NAME=$(basename "$FILE")
    echo "==> Uploading $NAME ($(du -h "$FILE" | cut -f1))"

    CURL_ARGS=(-fsS --retry 5 --retry-delay 10 -X POST
        "https://${SERVER}.gofile.io/contents/uploadfile"
        -F "file=@${FILE}")
    if [ -n "$TOKEN" ]; then
        CURL_ARGS+=(-H "Authorization: Bearer ${TOKEN}")
    fi
    if [ -n "$FOLDER_ID" ]; then
        CURL_ARGS+=(-F "folderId=${FOLDER_ID}")
    fi

    RESPONSE=$(curl "${CURL_ARGS[@]}")
    STATUS=$(jq -r '.status // empty' <<<"$RESPONSE")
    URL=$(jq -r '.data.downloadPage // empty' <<<"$RESPONSE")

    if [ "$STATUS" != "ok" ] || [ -z "$URL" ]; then
        echo "::error title=Gofile upload failed::${NAME}"
        echo "$RESPONSE" >&2
        exit 1
    fi

    echo "$NAME"$'\t'"$URL" >> "$LINKS_FILE"
    echo "==> $NAME -> $URL"
    if [ -z "$FIRST_URL" ]; then
        FIRST_URL="$URL"
    fi
done

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "url=$FIRST_URL"
        echo "links_file=$LINKS_FILE"
    } >> "$GITHUB_OUTPUT"
fi

echo "==> Gofile links written to $LINKS_FILE"
