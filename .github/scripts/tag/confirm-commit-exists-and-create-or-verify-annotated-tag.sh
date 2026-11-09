#!/usr/bin/env bash
# Extracted from .github/workflows/tag.yml
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }
tag="v$VERSION"
gh api "repos/$GH_REPO/commits/$COMMIT_SHA" --jq '.sha' > "$RUNNER_TEMP/verified-commit.txt" || fail "Commit $COMMIT_SHA does not exist in $GH_REPO."
[[ "$(cat "$RUNNER_TEMP/verified-commit.txt")" == "$COMMIT_SHA" ]] || fail "GitHub returned a different commit than Package metadata."

gh auth setup-git
git init tag-repo
git -C tag-repo remote add origin "https://github.com/$GH_REPO.git"
git -C tag-repo fetch --no-tags origin "$COMMIT_SHA" || fail "Could not fetch package commit $COMMIT_SHA from this repository."
[[ "$(git -C tag-repo rev-parse FETCH_HEAD^{commit})" == "$COMMIT_SHA" ]] || fail "Fetched commit differs from Package metadata."

if git -C tag-repo fetch --no-tags origin "refs/tags/$tag:refs/tags/$tag" 2>/dev/null; then
  existing_commit="$(git -C tag-repo rev-parse "$tag^{commit}")"
  [[ "$existing_commit" == "$COMMIT_SHA" ]] || fail "Tag $tag already points to $existing_commit, not $COMMIT_SHA; refusing to move it."
  echo "Tag $tag already points to the requested commit; treating this run as successful."
else
  git -C tag-repo -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' tag -a "$tag" "$COMMIT_SHA" -m "LLP $VERSION" || fail "Could not create annotated tag $tag."
  if ! git -C tag-repo push origin "refs/tags/$tag:refs/tags/$tag"; then
    git -C tag-repo tag -d "$tag" >/dev/null 2>&1 || true
    git -C tag-repo fetch --no-tags origin "refs/tags/$tag:refs/tags/$tag" >/dev/null 2>&1 || fail "Could not push tag $tag; no matching remote tag is available."
    existing_commit="$(git -C tag-repo rev-parse "$tag^{commit}")"
    [[ "$existing_commit" == "$COMMIT_SHA" ]] || fail "A concurrent tag $tag points to a different commit; refusing to overwrite it."
    echo "Concurrent run created the same tag and commit; treating this run as successful."
  fi
fi

git -C tag-repo fetch --no-tags origin "refs/tags/$tag:refs/tags/$tag" >/dev/null || fail "Could not verify remote tag $tag after creation."
final_commit="$(git -C tag-repo rev-parse "$tag^{commit}")"
[[ "$final_commit" == "$COMMIT_SHA" ]] || fail "Remote tag verification failed: $tag points to $final_commit."
tag_object="$(git -C tag-repo cat-file -t "refs/tags/$tag")"
[[ "$tag_object" == tag ]] || fail "Remote tag $tag exists but is not an annotated Git tag."
echo "tag_name=$tag" >> "$GITHUB_OUTPUT"
echo "commit_sha=$final_commit" >> "$GITHUB_OUTPUT"
echo "Tag Name: $tag"
echo "Commit SHA: $final_commit"
echo "Version: $VERSION"
echo "Package Run ID: $PACKAGE_RUN_ID"

