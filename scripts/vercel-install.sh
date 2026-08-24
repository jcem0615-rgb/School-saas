#!/usr/bin/env bash
# Vercel's build image has no Flutter SDK, so the install step fetches one.
#
# Cloned rather than downloaded from the release tarball: the Linux
# archives are .tar.xz, and whether xz is present in the build image is
# not something this repo controls. git always is.
set -euo pipefail

FLUTTER_VERSION="3.47.1"

if [ ! -d "_flutter" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git _flutter
fi

export PATH="$PWD/_flutter/bin:$PATH"
# The SDK is checked out by a different user than the one running the
# build, and the flutter tool shells out to git against its own directory.
git config --global --add safe.directory "$PWD/_flutter"

flutter --version
cd app
flutter pub get
