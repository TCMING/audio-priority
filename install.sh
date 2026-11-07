#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
[[ -x 'build/音频自动切换.app/Contents/MacOS/audio-priority' ]] || ./build.sh
export AUDIO_PRIORITY_SOURCE="$PWD/build/音频自动切换.app"
/usr/bin/swift scripts-install.swift
