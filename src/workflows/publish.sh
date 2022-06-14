#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

fail_if_unset () {
  local var_name="$1"
  if [[ -z "${!var_name:-""}" ]]; then
    printf '%s not set\n' "$var_name" >&2
    exit 1
  fi
}

package_exists () {
  npm view --json "$1" &>/dev/null;
}

fail_if_unset NODE_AUTH_TOKEN

git_username="GitHub Actions"
git_useremail="GitHub-Actions@cow.fi"

package_name="$(jq --raw-output .name ./package.json)"
version="$(jq --raw-output .version ./package.json)"

if package_exists "$package_name" && grep --silent --line-regexp --fixed-strings -- "$version" \
    <(npm view --json "$package_name" | jq '.versions[] | .' --raw-output); then
  echo "Version $version already published"
  exit 1
fi

version_tag="v$version"
if git fetch --end-of-options origin "refs/tags/$version_tag" 2>/dev/null; then
  echo "Tag $version_tag is already present"
  exit 1
fi

yarn publish --access public

if ! git config --get user.name &>/dev/null; then
  git config user.name "$git_username"
  git config user.email "$git_useremail"
fi
git tag -m "Version $version" --end-of-options "$version_tag"

git push origin "refs/tags/$version_tag"

echo "Package $package_name version $version successfully published."
