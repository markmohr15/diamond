#!/usr/bin/env bash
# Regenerate golden images on GitHub's runner, which is where CI compares them,
# and unpack the ones that changed into the working tree.
#
#   tools/goldens-ci.sh          regenerate every golden
#   tools/goldens-ci.sh -n zone  regenerate only tests matching "zone"
#
# The runner renders the commit on the remote branch, not your working tree,
# so push first: this refuses to run while HEAD and its upstream differ.
#
# Needs the gh CLI, signed in. The workflow (.github/workflows/goldens.yml)
# can only be triggered once it exists on main.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO}"

NAME_FILTER=""
if [[ "${1:-}" == "-n" ]]; then
  NAME_FILTER="${2:?-n needs a test name}"
fi

BRANCH="$(git branch --show-current)"
if [[ -z "${BRANCH}" ]]; then
  echo "detached HEAD — check out a branch first" >&2
  exit 1
fi

git fetch -q origin "${BRANCH}" 2>/dev/null || {
  echo "${BRANCH} is not on origin — push it first" >&2
  exit 1
}
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/${BRANCH}")" ]]; then
  echo "HEAD differs from origin/${BRANCH} — push first, the runner renders the remote commit" >&2
  exit 1
fi

# Remember the newest run before triggering, so the one we wait on is ours.
BEFORE="$(gh run list --workflow goldens.yml --branch "${BRANCH}" --limit 1 \
  --json databaseId --jq '.[0].databaseId // 0')"

echo "==> triggering goldens on ${BRANCH} at $(git rev-parse --short HEAD)"
gh workflow run goldens.yml --ref "${BRANCH}" -f name="${NAME_FILTER}"

RUN=""
for _ in $(seq 1 30); do
  RUN="$(gh run list --workflow goldens.yml --branch "${BRANCH}" --limit 1 \
    --json databaseId --jq '.[0].databaseId // 0')"
  [[ "${RUN}" != "${BEFORE}" ]] && break
  sleep 2
done
if [[ "${RUN}" == "${BEFORE}" ]]; then
  echo "the run never appeared — check the Actions tab" >&2
  exit 1
fi

gh run watch "${RUN}" --exit-status

OUT="$(mktemp -d)"
trap 'rm -rf "${OUT}"' EXIT
gh run download "${RUN}" -n goldens -D "${OUT}"

COUNT="$(wc -l < "${OUT}/changed.txt" | tr -d ' ')"
if [[ "${COUNT}" == "0" ]]; then
  echo "==> no golden changed"
  exit 0
fi

tar -xzf "${OUT}/goldens.tgz" -C "${REPO}"
echo "==> ${COUNT} golden(s) updated. Review the diff before committing:"
echo "    git status --short -- '*.png'"
