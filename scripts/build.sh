#!/usr/bin/env bash
# Build OpenSCAD for Windows ARM64, bundle it, zip it.
# Usage: build.sh <upstream_src_dir> <dist_dir> <short_sha>
set -e
shopt -s nullglob
# Normalize a path to MSYS2 POSIX form. Handles:
#   C:\foo\bar, C:/foo/bar, /c/foo/bar, relative paths.
to_posix() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p"
  else
    case "$p" in
      [A-Za-z]:\\*|[A-Za-z]:/*)
        local drive="${p:0:1}"
        local rest="${p:2}"
        rest="${rest//\\//}"
        printf '/%s%s' "$(printf '%s' "$drive" | tr 'A-Z' 'a-z')" "$rest"
        ;;
      /*) printf '%s' "$p" ;;
      *) printf '%s/%s' "$PWD" "$p" ;;
    esac
  fi
}
src="$(to_posix "$1")"
dist="$(to_posix "$2")"
short="$3"
scriptdir="$(cd "$(dirname "$0")" && pwd)"
day="$(date +%Y%m%d)"
cd "$src"
mkdir -p build && cd build
cmake .. -G"Ninja" -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DEXPERIMENTAL=ON -DSNAPSHOT=ON -DUSE_QT6=ON -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
cmake --build . -j"$(nproc)"
cmake --install . --prefix=.
mkdir -p bundle
cp openscad.exe bundle/
for d in color-schemes examples fonts libraries locale shaders templates mimalloc.dll mimalloc-redirect.dll; do
  [ -e "$d" ] && cp -r "$d" bundle/
done
for plugdir in platforms imageformats styles iconengines; do
  plugsrc="/clangarm64/share/qt6/plugins/$plugdir"
  if [ -d "$plugsrc" ]; then
    mkdir -p "bundle/$plugdir"
    cp "$plugsrc"/*.dll "bundle/$plugdir/"
  fi
done
bash "$scriptdir/collect-dlls.sh" "$PWD/bundle"
mkdir -p "$dist"
echo "dist dir: $dist"
zip="openscad-arm64-$day-$short.zip"
python3 - "$PWD/bundle" "$dist/$zip" <<'EOF'
import os, sys, zipfile
bundle, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for root, dirs, files in os.walk(bundle):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, bundle))
EOF
echo "wrote $dist/$zip"
