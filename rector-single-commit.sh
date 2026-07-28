#!/bin/bash
# Create single commits for all php-rector rules
# Needs:
# - git
# - jq
# - rector (in vendor/bin or RECTOR_PATH)
set -e

globalPath=""
commitMessagePrefix=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            echo "rector-single-commit.sh [commit message prefix] [--global-path[=PATH]]"
            echo "Options:"
            echo " -h, --help: Show help"
            echo " --global-path[=PATH]: Use a global rector executable instead of ./vendor/bin/rector"
            echo "     (default: \$HOME/.config/composer/vendor/bin/rector)"
            exit
            ;;
        --global-path=*)
            globalPath="${1#--global-path=}"
            shift
            ;;
        --global-path)
            globalPath="$HOME/.config/composer/vendor/bin/rector"
            shift
            ;;
        *)
            commitMessagePrefix="$1"
            shift
            ;;
    esac
done

messagesDir=$(dirname "$0")/messages
if [ -n "$globalPath" ]; then
    rectorPath="$globalPath"
else
    rectorPath=${RECTOR_PATH:-./vendor/bin/rector}
fi
if [ ! -x "$rectorPath" ]; then
    echo "rector executable not found at $rectorPath" >&2
    exit 1
fi

if ! command -v jq > /dev/null 2>&1; then
    echo "jq executable not found" >&2
    exit 1
fi

if [ ! -f "./rector.php" ]; then
    echo "rector.php configuration file missing" >&2
    exit 1
fi

if [ ! -z "$(git status --porcelain)" ]; then
    echo "git repository status is not clean. Commit all changes first" >&2
    exit 2
fi

# "sh" (dash) breaks here with backslashes in the output, e.g. "TYPO311\v0"
# "bash" works fine
rules=$(
    "$rectorPath" process --dry-run --clear-cache --output-format=json\
        | jq -r '.file_diffs[]?.applied_rectors[]'\
        | sort | uniq
     )
if [ -z "$rules" ]; then
    echo "Nothing to do; the code is clean"
    exit
fi

numRules=$(echo "$rules"|wc -l)
echo "Rector wants to apply $numRules rules to the code"
nl="
"
for rule in $rules; do
    echo Applying rule: $rule

    messageFile=$(echo "$rule"| tr '\\' '.')
    messageFilePath="$messagesDir/${messageFile}.txt"
    if [ ! -f "$messageFilePath" ]; then
        echo "No commit message file for rule" >&2
        echo " $rule" >&2
        echo -n " https://getrector.com/find-rule?query="
        echo "$rule" | sed 's/^.*\\//'
        echo " $messageFilePath" >&2
        exit 3
    fi

    messageFileContents=$(<"$messageFilePath")
    commitMessage="$commitMessagePrefix$messageFileContents"
    commitMessage+="${nl}${nl}Applied rule:${nl}$rule"

    "$rectorPath" process --clear-cache --no-diffs --only="$rule"

    if [ -z "$(git status --porcelain)" ]; then
        echo "WARN: No code changes" >&2
        continue
    fi

    git commit\
        --all\
        --author='Rector <rector@getrector.com>'\
        --message="$commitMessage"
done

echo "Complete"
