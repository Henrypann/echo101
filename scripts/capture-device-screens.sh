#!/bin/sh
# Renders real native views using DEBUG-only isolated, synthetic libraries.
# This is visual evidence, not a substitute for interaction or audio tests.
set -eu
ECHO_DEVICE=${1:?Pass the paired iPhone device identifier}
ECHO_REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
mkdir -p "$ECHO_REPO/docs/screenshots"
restore_family_launch() {
  xcrun devicectl device process launch --device "$ECHO_DEVICE" --terminate-existing com.henrypann.echo101 || true
}
trap restore_family_launch EXIT
for ECHO_CASE in today-light explore-light listen-light world-light overview-light moment-light review-light settings-light today-dark settings-dark explore-large overview-large review-large; do
  ECHO_PAGE=${ECHO_CASE%-*}
  ECHO_STYLE=${ECHO_CASE##*-}
  ECHO_RUN=$(uuidgen)
  if [ "$ECHO_STYLE" = large ]; then
    set -- --appearance light --large-text
  else
    set -- --appearance "$ECHO_STYLE"
  fi
  xcrun devicectl device process launch --device "$ECHO_DEVICE" --terminate-existing com.henrypann.echo101 \
    --uitesting --test-run-id "$ECHO_RUN" --seed-samples --snapshot --snapshot-page "$ECHO_PAGE" "$@"
  sleep 5
  xcrun devicectl device copy from --device "$ECHO_DEVICE" \
    --domain-type appDataContainer --domain-identifier com.henrypann.echo101 \
    --source "Library/Application Support/EchoTests-$ECHO_RUN/Screenshot.png" \
    --destination "$ECHO_REPO/docs/screenshots/$ECHO_CASE.png"
done
