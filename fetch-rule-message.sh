#!/bin/bash
# Fetch a rule's short description from getrector.com and write it as a message file.
# Needs: curl, php
set -e

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ] || [ -z "$2" ]; then
    echo "fetch-rule-message.sh <Rule\\Class\\Name> <message-file-path>"
    exit
fi

rule="$1"
messageFilePath="$2"

if ! command -v curl > /dev/null 2>&1; then
    echo "curl executable not found" >&2
    exit 1
fi

if ! command -v php > /dev/null 2>&1; then
    echo "php executable not found" >&2
    exit 1
fi

shortName=$(echo "$rule" | sed 's/^.*\\//')
url="https://getrector.com/find-rule?query=$shortName"

html=$(curl -fsSL "$url") || {
    echo "Failed to fetch $url" >&2
    exit 1
}

description=$(php -r '
    [$html, $shortName] = [$argv[1], $argv[2]];
    // Rule blocks on getrector.com look like:
    // <h3 ...><a ...>RuleName</a></h3>\n<p>Description</p>
    $pattern = "/<h3[^>]*>\s*<a[^>]*>\s*" . preg_quote($shortName, "/") . "\s*<\/a>\s*<\/h3>\s*<p[^>]*>(.*?)<\/p>/s";
    if (preg_match($pattern, $html, $matches)) {
        echo trim(html_entity_decode(strip_tags($matches[1]), ENT_QUOTES | ENT_HTML5));
        exit(0);
    }
    exit(1);
' "$html" "$shortName") || {
    echo "Could not find rule '$shortName' on $url" >&2
    exit 1
}

if [ -z "$description" ]; then
    echo "Empty description parsed for '$shortName' from $url" >&2
    exit 1
fi

echo "$description" > "$messageFilePath"
echo "Wrote $messageFilePath:" >&2
echo "  $description" >&2
