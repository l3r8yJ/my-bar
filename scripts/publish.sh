#!/bin/sh
set -eu
sh "$(dirname "$0")/validate-version.sh" "$@"
version=$1
sha256sum --check SHA256SUMS
if draft=$(gh release view "$version" --json isDraft --jq .isDraft); then
    if [ "$draft" != true ]; then
        echo 'Release already published; existing assets will not be replaced.'
        exit 0
    fi
    gh release upload "$version" ./*.tar.gz SHA256SUMS --clobber
else
    gh release create "$version" ./*.tar.gz SHA256SUMS \
        --verify-tag --draft --generate-notes --title "$version"
fi
gh release edit "$version" --draft=false
