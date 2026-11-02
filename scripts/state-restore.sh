#!/bin/bash
# Memulihkan state build dari Release "state" (hasil stage sebelumnya):
# sysroot prefix, daftar paket yang sudah dibuild, urutan build.
# Hasil: $RUNNER_TEMP/SHA.txt (commit termux-packages yang dipin) jika ada.
set -uo pipefail
: "${GITHUB_REPOSITORY:?}" "${APP_PACKAGE:?}"
TMP=${RUNNER_TEMP:-/tmp}

sudo mkdir -p /data/data
sudo chown "$(id -u):$(id -g)" /data /data/data

if [ "${RESET:-false}" = "true" ]; then
  echo "reset diminta: state lama dihapus, mulai dari awal"
  gh release delete state --cleanup-tag -y --repo "$GITHUB_REPOSITORY" 2>/dev/null || true
  exit 0
fi

ASSETS=$(gh release view state --repo "$GITHUB_REPOSITORY" --json assets -q '.assets[].name' 2>/dev/null || true)
if [ -z "$ASSETS" ]; then
  echo "belum ada state: ini stage pertama"
  exit 0
fi

if grep -qx 'SHA.txt' <<<"$ASSETS"; then
  gh release download state --repo "$GITHUB_REPOSITORY" --pattern SHA.txt --dir "$TMP" --clobber
  echo "commit termux-packages dipin: $(cat "$TMP/SHA.txt")"
fi

LATEST=$(grep -E '^state-[0-9]{6}\.tar\.zst\.part' <<<"$ASSETS" | sed -E 's/^state-([0-9]{6}).*/\1/' | sort -u | tail -n 1)
if [ -z "$LATEST" ]; then
  echo "tidak ada berkas state, mulai dari awal"
  exit 0
fi

echo "memulihkan state-$LATEST"
PARTS=$(grep -E "^state-${LATEST}\.tar\.zst\.part" <<<"$ASSETS" | sort)
set -o pipefail
if ! ( for p in $PARTS; do gh release download state --repo "$GITHUB_REPOSITORY" --pattern "$p" --output -; done ) \
     | zstd -dc | tar -C / -xf -; then
  echo "::error::Gagal memulihkan state-$LATEST"
  exit 1
fi
du -sh "/data/data/$APP_PACKAGE" 2>/dev/null || true
echo "state dipulihkan; paket selesai: $(wc -l < "$HOME/.termux-build/_buildall-aarch64/buildstatus.txt" 2>/dev/null || echo 0)"
