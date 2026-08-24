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
flutter build web --release --dart-define=DEMO_MODE=true
