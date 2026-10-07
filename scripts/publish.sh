#!/bin/sh
set -eu
sh "$(dirname "$0")/validate-version.sh" "$@"
version=$1
sha256sum --check SHA256SUMS
if state=$(gh release view "$version" --json isDraft,isPrerelease,assets --jq 'if .isDraft then "draft" elif .isPrerelease and (.assets | length) == 0 then "empty-prerelease" else "published" end'); then
    case "$state" in
        published)
            echo 'Release already published; existing assets will not be replaced.'
            exit 0
            ;;
        empty-prerelease) gh release edit "$version" --draft=true ;;
        draft) ;;
        *) echo 'Unexpected release state' >&2; exit 1 ;;
    esac
    gh release upload "$version" ./*.tar.gz ./*.pkg.tar.zst PKGBUILD SRCINFO SHA256SUMS --clobber
else
    gh release create "$version" ./*.tar.gz ./*.pkg.tar.zst PKGBUILD SRCINFO SHA256SUMS \
        --verify-tag --draft --generate-notes --title "$version"
fi
gh release edit "$version" --draft=false --prerelease=false --title "$version"
