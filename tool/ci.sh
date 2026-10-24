#!/bin/sh
# What CI runs, on GitLab and on the GitHub mirror alike, so the two cannot
# drift apart:
#
#   tool/ci.sh test   analyze and test with the Flutter pinned in pubspec.yaml
#   tool/ci.sh osv    check pubspec.lock against known vulnerabilities
#
# FLUTTER_SDK points at an existing checkout instead of cloning one.
set -eu

case "${1:-}" in
test)
  # The release F-Droid builds with: the `flutter:` line in pubspec.yaml.
  version=$(sed -n 's/^  flutter: *//p' pubspec.yaml)
  sdk="${FLUTTER_SDK:-$HOME/flutter}"
  if [ ! -x "$sdk/bin/flutter" ]; then
    git clone --quiet --depth 1 --branch "$version" \
      https://github.com/flutter/flutter.git "$sdk"
  fi
  export PATH="$sdk/bin:$PATH"
  flutter config --no-analytics >/dev/null
  running=$(flutter --version --machine |
    sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')
  if [ "$running" != "$version" ]; then
    echo "Flutter $running, but pubspec.yaml pins $version" >&2
    exit 1
  fi
  # Exactly the versions in pubspec.lock; fails rather than resolve anew.
  flutter pub get --enforce-lockfile
  flutter analyze
  flutter test
  ;;
osv)
  # A pinned release, checked against its published checksum before it runs.
  release=2.7.0
  sum=160c6253e2922e9e0a6a9771c5c4c40a4b3c6090b34a3cdd5e80c96cc2e4218b
  bin="${TMPDIR:-/tmp}/osv-scanner"
  curl -sSfL -o "$bin" \
    "https://github.com/google/osv-scanner/releases/download/v$release/osv-scanner_linux_amd64"
  echo "$sum  $bin" | sha256sum -c -
  chmod +x "$bin"
  "$bin" scan source --lockfile pubspec.lock
  ;;
*)
  echo "usage: tool/ci.sh test|osv" >&2
  exit 2
  ;;
esac
