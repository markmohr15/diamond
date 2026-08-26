#!/usr/bin/env bash
# Regenerate golden images on Linux, which is where CI compares them.
#
# Goldens are pixels, and pixels are platform-specific: the same widget
# rasterizes slightly differently on macOS and Linux (curve anti-aliasing,
# and — once fonts are bundled — text hinting). Generating on a Mac and
# comparing on Linux is what makes CI fail with no code change behind it.
#
# So goldens are generated in the same container family CI runs, on the
# Flutter version .github/workflows/ci.yml pins. Bump both together.
#
# --run-skipped is not optional: the two platform-sensitive goldens are
# skipped by dart_test.yaml so a local `flutter test` stays green, and without
# it they are the only two this script would silently *not* regenerate — which
# stays invisible until a visual change lands and CI compares fresh renders
# against stale images.
#
#   tools/goldens.sh          regenerate every golden
#   tools/goldens.sh -n zone  regenerate only tests matching "zone"
set -euo pipefail

FLUTTER_VERSION=3.41.8
IMAGE="ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAME_FILTER=()
if [[ "${1:-}" == "-n" && -n "${2:-}" ]]; then
  NAME_FILTER=(--plain-name "$2")
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker is not running — start it and retry" >&2
  exit 1
fi

echo "==> regenerating goldens in ${IMAGE} (linux/amd64)"

# --platform is explicit: on an Apple-silicon host the default would be an
# arm64 image, which rasterizes differently from CI's amd64 runner and would
# reintroduce exactly the drift this script exists to remove. It is emulated
# and therefore slow; that is the price of matching CI.
docker run --rm \
  --platform linux/amd64 \
  -v "${REPO}:/repo" \
  -w /repo/app \
  "${IMAGE}" \
  bash -lc "git config --global --add safe.directory /repo &&
            flutter pub get &&
            flutter test --tags golden --run-skipped --update-goldens ${NAME_FILTER[*]:-}"

# `flutter pub get` inside the container rewrote .dart_tool/package_config.json
# with container paths, so the host toolchain can no longer resolve packages.
# Put it back, or the next local `flutter test` fails for a reason that has
# nothing to do with the code.
echo "==> restoring host package config"
(cd "${REPO}/app" && flutter pub get >/dev/null)

echo "==> done. Review the diff before committing:"
echo "    git status --short -- '*.png'"
