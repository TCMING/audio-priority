#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
[[ -x '.build/音频自动切换.app/Contents/MacOS/control' ]] || ./build.sh
if [[ -e '/Applications/音频自动切换.app' ]]; then
    echo '应用程序里已有同名 App，请先退出，再在 Finder 中替换。'
fi
open -R '.build/音频自动切换.app'
open /Applications
