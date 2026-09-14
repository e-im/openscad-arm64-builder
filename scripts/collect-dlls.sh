#!/usr/bin/env bash
# Collect the MSYS2/MinGW DLL closure for a Windows bundle dir.
#
# Usage: collect-dlls.sh <bundle_dir>
#
# Copies every DLL that the bundle's EXE/plugin binaries need from the
# current MSYS2 environment next to the binaries, so the bundle runs on
# machines without MSYS2 installed. System (C:\Windows) DLLs are excluded.
# Fails loudly if the closure looks incomplete.
set -u

bundle="$1"

mapfile -t targets < <(find "$bundle" -maxdepth 1 -name '*.exe'; find "$bundle"/*/ -maxdepth 1 -name '*.dll' 2>/dev/null)
echo "${#targets[@]} binaries to scan"

pacman -S --noconfirm --needed mingw-w64-clang-aarch64-ntldd || true
if ! command -v ntldd >/dev/null 2>&1; then
  echo "ERROR: ntldd is not available and no fallback is implemented" >&2
  exit 1
fi

echo "using ntldd recursive walk"
: > /tmp/dlllist.txt
for t in "${targets[@]}"; do
  # NOTE: ntldd prints Windows paths (C:\...), not msys POSIX paths.
  ntldd -R "$t" 2>/dev/null | grep -oiE '[a-z]:\\[^ ]*\.dll' >> /tmp/dlllist.txt || true
done
# Normalize C:\foo\bar -> /c/foo/bar, drop C:\Windows system DLLs.
sed -e 's|\\|/|g' -e 's|^\([A-Za-z]\):|/\L\1|' /tmp/dlllist.txt \
  | grep -vi '^/c/windows' | sort -u -o /tmp/dlllist.txt

total=$(wc -l < /tmp/dlllist.txt | tr -d ' ')
echo "$total DLLs to copy"
[ "$total" -ge 20 ] || { echo "ERROR: suspiciously small closure ($total DLLs)" >&2; exit 1; }
for need in Qt6Core 'libc++' libintl mimalloc; do
  grep -qi "$need" /tmp/dlllist.txt || { echo "ERROR: $need missing from DLL closure" >&2; exit 1; }
done

n=0
while IFS= read -r dep; do
  n=$((n + 1)); base="$(basename "$dep")"
  echo "[$n/$total] $base"
  if [ -f "$bundle/$base" ]; then
    :
  elif [ -f "$dep" ]; then
    cp "$dep" "$bundle/"
  else
    echo "ERROR: listed DLL not found: $dep" >&2
    exit 1
  fi
done < /tmp/dlllist.txt
echo "bundled $(ls "$bundle"/*.dll | wc -l) DLLs, $(du -sh "$bundle" | cut -f1) total"
