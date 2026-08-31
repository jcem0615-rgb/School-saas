#!/usr/bin/env bash
# Runs in a fresh shell from the install step, so PATH is set again --
# only the filesystem carries over between the two.
set -euo pipefail

export PATH="$PWD/_flutter/bin:$PATH"
git config --global --add safe.directory "$PWD/_flutter" || true

cd app

# Demo mode unless the deployment says otherwise. Set DEMO_MODE=false
# along with the FIREBASE_* values below and the next deploy is the real
# thing -- no code change.
#
# Where to set them moved. This script once ran inside Vercel's build
# container, so the answer was "the Vercel project's environment
# variables"; the build happens in GitHub Actions now, and values set in
# Vercel are read by nothing. They go in the repository's Actions
# Variables, which .github/workflows/deploy-web.yml passes in.
DEMO_MODE="${DEMO_MODE:-true}"

DEFINES=( --dart-define=DEMO_MODE="$DEMO_MODE" )

if [ "$DEMO_MODE" = "false" ]; then
  # Fail here rather than build a site that loads and then dies on a
  # missing key. The app checks this too (lib/firebase_config.dart), but
  # by then it is a white screen in front of a customer instead of a red
  # line in a build log.
  MISSING=()
  for KEY in FIREBASE_API_KEY FIREBASE_APP_ID FIREBASE_PROJECT_ID \
             FIREBASE_MESSAGING_SENDER_ID; do
    [ -n "${!KEY:-}" ] || MISSING+=("$KEY")
  done
  if [ ${#MISSING[@]} -gt 0 ]; then
    echo "DEMO_MODE=false needs the Firebase project settings." >&2
    echo "Missing: ${MISSING[*]}" >&2
    echo "Add them under Settings -> Secrets and variables -> Actions" >&2
    echo "-> Variables, on the repository. They are client identifiers," >&2
    echo "not secrets -- see app/lib/firebase_config.dart." >&2
    exit 1
  fi

  # Optional ones are passed only when set: an empty --dart-define is not
  # the same as an absent one, and the SDK would take "" as a real value.
  for KEY in FIREBASE_API_KEY FIREBASE_APP_ID FIREBASE_PROJECT_ID \
             FIREBASE_MESSAGING_SENDER_ID FIREBASE_STORAGE_BUCKET \
             FIREBASE_AUTH_DOMAIN; do
    [ -n "${!KEY:-}" ] && DEFINES+=( --dart-define="$KEY=${!KEY}" )
  done
fi

# --no-web-resources-cdn is not optional here. By default the build
# fetches CanvasKit -- the renderer itself -- from
# https://www.gstatic.com/flutter-canvaskit/<engine>/ at startup, even
# though an identical copy is written to build/web/canvaskit and served
# from the same origin. If that fetch fails, the page stays blank, since
# the thing that failed to load is the thing that draws.
#
# A school on a filtered connection is exactly the audience for this app,
# and the same CDN dependency already cost it every glyph of text once.
#
# The dart-define FLUTTER_WEB_CANVASKIT_URL looks like it should do this
# and does not: it reaches the Dart side, while flutter.js decides from
# `useLocalCanvasKit` in the generated build config, which only this flag
# sets.
# --pwa-strategy=none stops Flutter generating and registering
# flutter_service_worker.js.
#
# That service worker caches the whole app and serves it ahead of the
# network, which is the classic way a redeploying site goes blank: a
# visitor who loaded an earlier build keeps being served its asset list,
# and once one entry no longer matches, main.dart.js never runs and the
# page is white with nothing in the console a user would think to look
# at. A hard reload fixes it; nobody knows to try one.
#
# Flutter's own generated bootstrap already says this worker is
# deprecated and will be removed. Offline caching is worth little to a
# site whose whole point is being opened once from a link, and it is
# worth a great deal less than a page that reliably loads.
echo "Building web (DEMO_MODE=$DEMO_MODE)"
flutter build web --release --no-web-resources-cdn --pwa-strategy=none "${DEFINES[@]}"
