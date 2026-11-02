#!/bin/bash
# Menyimpan state build ke Release "state" supaya stage berikutnya bisa lanjut.
# Dipotong per 1900 MB karena batas satu berkas Release 2 GiB.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${APP_PACKAGE:?}" "${RUN_NUMBER:?}" "${TP_SHA:?}"
TMP=${RUNNER_TEMP:-/tmp}
NAME=$(printf 'state-%06d' "$RUN_NUMBER")
OUT=$TMP/stateout
rm -rf "$OUT" && mkdir -p "$OUT"

PATHS=()
for p in /data/data/.built-packages "/data/data/$APP_PACKAGE" "$HOME/.termux-build/_buildall-aarch64"; do
  [ -e "$p" ] && PATHS+=("${p#/}")
done
[ "${#PATHS[@]}" -gt 0 ] || { echo "tidak ada state untuk disimpan"; exit 0; }

tar -C / -cf - "${PATHS[@]}" | zstd -T0 -3 | split -b 1900M -d -a 2 - "$OUT/$NAME.tar.zst.part"
printf '%s' "$TP_SHA" > "$OUT/SHA.txt"
ls -la "$OUT"

gh release view state --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1 || \
  gh release create state --repo "$GITHUB_REPOSITORY" --title "State build bertahap" \
    --notes "Jangan dihapus: dipakai workflow Build All untuk melanjutkan build."
gh release upload state --repo "$GITHUB_REPOSITORY" --clobber "$OUT"/*

# Hapus state lama setelah yang baru terunggah penuh.
gh release view state --repo "$GITHUB_REPOSITORY" --json assets -q '.assets[].name' \
  | grep -E '^state-[0-9]{6}\.tar\.zst\.part' | grep -v "^$NAME\." \
  | while read -r old; do
      gh release delete-asset state "$old" -y --repo "$GITHUB_REPOSITORY" || true
    done
echo "state tersimpan: $NAME"
