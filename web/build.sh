#!/usr/bin/env bash
# 重新生成 dist/web.js。
#
# 改了 web/web.mbt 或库代码之后跑一次，页面才会看到新逻辑。
# 产物是提交进仓库的，所以别人 clone 下来直接打开 index.html 就能用，
# 不必先构建。

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

moon build --target js --release

mkdir -p web/dist
cp _build/js/release/build/web/web.js web/dist/web.js
mkdir -p web/licenses
cp LICENSE web/licenses/project.LICENSE
cp THIRD_PARTY_NOTICES.md web/licenses/THIRD_PARTY_NOTICES.md
cp .mooncakes/hustcer/fzip/LICENSE web/licenses/fzip.LICENSE
cp .mooncakes/Milky2018/xml/LICENSE web/licenses/xml.LICENSE
cp "${MOON_HOME:-$HOME/.moon}/lib/core/LICENSE" web/licenses/moonbit-core.LICENSE
cp "${MOON_HOME:-$HOME/.moon}/lib/core/NOTICE" web/licenses/moonbit-core.NOTICE

echo "已生成 web/dist/web.js（$(wc -c < web/dist/web.js) 字节）"
