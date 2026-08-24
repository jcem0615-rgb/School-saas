#!/usr/bin/env bash
# Runs in a fresh shell from the install step, so PATH is set again --
# only the filesystem carries over between the two.
set -euo pipefail

export PATH="$PWD/_flutter/bin:$PATH"
git config --global --add safe.directory "$PWD/_flutter" || true

cd app
# Demo mode: this deployment has no Firebase project behind it, and the
# in-memory store is what makes the URL worth opening at all. Point it at
# a real backend by adding the FIREBASE_* values from
# lib/firebase_config.dart as Vercel environment variables and switching
# this to DEMO_MODE=false.
#
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
flutter build web --release \
  --no-web-resources-cdn \
  --dart-define=DEMO_MODE=true
