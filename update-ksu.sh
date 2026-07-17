#!/bin/bash

set -e

KSU_REPO="https://github.com/backslashxx/KernelSU"
KSU_DRIVER="drivers/kernelsu"
VERSION=""

usage() {
    echo "Usage: $0 [-v <version_tag>]"
    echo "Example: $0 -v v1.0.1"
    echo "If no version is specified, it will automatically pull the latest tag."
    exit 1
}

while getopts ":v:h" opt; do
    case "${opt}" in
        v)
            VERSION=${OPTARG}
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -${OPTARG}" >&2
            usage
            ;;
        :)
            echo "Option -${OPTARG} requires an argument." >&2
            usage
            ;;
    esac
done

rm -rf "$KSU_DRIVER" ksu-temp
git clone "$KSU_REPO" ksu-temp

if [ -z "$VERSION" ]; then
    echo "No version specified. Fetching the latest release tag..."
    TARGET_TAG=$(git -C ksu-temp describe --tags "$(git -C ksu-temp rev-list --tags --max-count=1)")
else
    TARGET_TAG="$VERSION"
    if ! git -C ksu-temp rev-parse "$TARGET_TAG" >/dev/null 2>&1; then
        if git -C ksu-temp rev-parse "v$TARGET_TAG" >/dev/null 2>&1; then
            TARGET_TAG="v$TARGET_TAG"
        fi
    fi
fi

echo "Checking out to KernelSU version: $TARGET_TAG"

if ! git -C ksu-temp checkout "$TARGET_TAG"; then
    echo "❌ Error: Tag '$TARGET_TAG' not found in KernelSU repository."
    rm -rf ksu-temp
    exit 1
fi

mv ksu-temp/kernel "$KSU_DRIVER"
rm -rf ksu-temp

git add "$KSU_DRIVER"
git commit -m "drivers: Update KernelSU to v$TARGET_TAG"

echo "✅ KernelSU successfully updated to $TARGET_TAG!"
