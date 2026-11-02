#!/bin/bash
# Menyesuaikan salinan termux-packages (folder tp) untuk app toolAPKAI:
#   1. nama paket app + URL repo apt di scripts/properties.sh
#   2. menyalin semua custom-packages/* ke tp/packages/
#   3. mengisi kunci publik GPG kita ke paket termux-keyring
# Pemakaian: APP_PACKAGE=... APT_BASE_URL=... GPG_PRIVATE_KEY=... bash scripts/patch-tp.sh tp
set -euo pipefail

TP=${1:?pakai: patch-tp.sh <folder termux-packages>}
: "${APP_PACKAGE:?APP_PACKAGE kosong}"
: "${APT_BASE_URL:?Variabel repo APT_BASE_URL belum diisi (Settings > Variables > Actions)}"
: "${GPG_PRIVATE_KEY:?Secret GPG_PRIVATE_KEY belum diisi (Settings > Secrets > Actions)}"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
F=$TP/scripts/properties.sh
BASE=${APT_BASE_URL%/}

# 1. nama paket app dan URL repo
sed -i -E "s|^(TERMUX_APP__PACKAGE_NAME=).*|\1\"$APP_PACKAGE\"|" "$F"
sed -i -E "s|^(TERMUX_APP_PACKAGE=).*|\1\"$APP_PACKAGE\"|" "$F"
if ! grep -q "$APP_PACKAGE" "$F"; then
  echo "::error::Baris nama paket di $F tidak ditemukan."
  grep -n 'com\.termux' "$F" | head -20 || true
  exit 1
fi
# Semua URL repo resmi (termux-main, termux-root, termux-x11) diarahkan ke repo kita.
sed -i -E "s#https?://packages(-cf)?\.termux\.dev/apt#${BASE}#g" "$F"
if ! grep -q "$BASE" "$F"; then
  echo "::error::URL repo resmi tidak ditemukan di $F; cek variabel TERMUX_REPO_* secara manual."
  grep -n 'TERMUX_REPO' "$F" | head -20 || true
  exit 1
fi
echo "--- baris penting di properties.sh ---"
grep -nE "TERMUX_APP(__PACKAGE_NAME|_PACKAGE)=|TERMUX_REPO|${BASE}" "$F" | head -n 30

# 2. paket sendiri (termasuk override termux-keyring)
if [ -d "$ROOT/custom-packages" ]; then
  for d in "$ROOT"/custom-packages/*/; do
    [ -f "${d}build.sh" ] || continue
    n=$(basename "$d")
    rm -rf "$TP/packages/$n"
    cp -r "$d" "$TP/packages/$n"
    echo "paket sendiri: $n"
  done
fi

# 3. kunci publik GPG untuk termux-keyring
export GNUPGHOME
GNUPGHOME=$(mktemp -d)
chmod 700 "$GNUPGHOME"
printf '%s\n' "$GPG_PRIVATE_KEY" | gpg --batch --quiet --import
KEYID=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
[ -n "$KEYID" ] || { echo "::error::Kunci GPG tidak terbaca dari GPG_PRIVATE_KEY"; exit 1; }
gpg --batch --export "$KEYID" > "$TP/packages/termux-keyring/toolapkai.gpg"
[ -s "$TP/packages/termux-keyring/toolapkai.gpg" ] || { echo "::error::Ekspor kunci publik gagal"; exit 1; }
echo "kunci repo: $KEYID"
rm -rf "$GNUPGHOME"
