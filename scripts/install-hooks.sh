#!/bin/sh
# Installs lefthook's git hooks, run by pnpm install (postinstall). Nothing to install outside a
# git repository, such as an image built from the sources.
set -eu

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
exec lefthook install
