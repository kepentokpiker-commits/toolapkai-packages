#!/bin/bash
# Membangun paket sesuai urutan buildorder.py sampai waktu habis.
# Paket yang gagal dicatat dan dilewati (tidak menghentikan stage).
# Dijalankan dari root repo; termux-packages ada di ./tp
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
: "${MAX_SECONDS:=16200}"   # batas waktu stage (default 4,5 jam)
: "${PKG_TIMEOUT:=7200}"    # batas satu paket (default 2 jam)
ARCH=aarch64
STATE_DIR=$HOME/.termux-build/_buildall-$ARCH
LOGDIR=$ROOT/buildlogs
mkdir -p "$STATE_DIR" "$LOGDIR" "$ROOT/tp/output"
touch "$STATE_DIR/buildstatus.txt" "$STATE_DIR/failed.txt"
cd "$ROOT/tp"

if [ ! -s "$STATE_DIR/buildorder.txt" ]; then
  # Keluaran ditulis ke berkas sementara: kalau gagal di tengah jalan, urutan
  # setengah jadi tidak boleh ikut tersimpan ke state dan dipakai stage berikutnya.
  ./scripts/buildorder.py > "$STATE_DIR/buildorder.tmp" 2> "$STATE_DIR/buildorder.err"
  BO_RC=$?
  if [ "$BO_RC" -eq 0 ]; then
    mv "$STATE_DIR/buildorder.tmp" "$STATE_DIR/buildorder.txt"
  else
    echo "::error::buildorder.py gagal (exit $BO_RC)"
    cat "$STATE_DIR/buildorder.tmp" "$STATE_DIR/buildorder.err" > "$STATE_DIR/buildorder.all"
    echo "--- inti siklus (ringkas) ---"
    python3 "$ROOT/scripts/cycle-report.py" "$STATE_DIR/buildorder.all" | tee "$STATE_DIR/cycle-report.txt"
    echo "--- awal keluaran buildorder.py ---"
    head -n 40 "$STATE_DIR/buildorder.all"
    {
      echo "### buildorder.py gagal (exit $BO_RC)"
      echo "commit termux-packages: \`$(git rev-parse --short HEAD 2>/dev/null)\`"
      echo '```'
      head -n 40 "$STATE_DIR/cycle-report.txt"
      echo '```'
    } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
    rm -f "$STATE_DIR/buildorder.tmp"

    # Urutan cadangan: siklus induk <-> sub-paket dipecah sendiri.
    # Matikan dengan ALLOW_FALLBACK=0 kalau ingin gagal keras.
    : "${FALLBACK_MIN:=500}"
    if [ "${ALLOW_FALLBACK:-1}" = "1" ]; then
      echo "--- buildorder.py upstream gagal, memakai urutan cadangan ---"
      python3 "$ROOT/scripts/fallback-buildorder.py" . > "$STATE_DIR/buildorder.fb" 2> "$STATE_DIR/fallback.log"
      cat "$STATE_DIR/fallback.log"
      FB_N=$(grep -c . "$STATE_DIR/buildorder.fb")
      if [ "$FB_N" -ge "$FALLBACK_MIN" ]; then
        mv "$STATE_DIR/buildorder.fb" "$STATE_DIR/buildorder.txt"
        {
          echo "**Memakai urutan cadangan ($FB_N paket).** Siklus dipecah otomatis; paket yang salah urut mungkin gagal dan dilewati."
          echo '```'
          cat "$STATE_DIR/fallback.log"
          echo '```'
        } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
      else
        echo "::error::urutan cadangan hanya $FB_N paket (minimal $FALLBACK_MIN); dianggap salah baca"
        rm -f "$STATE_DIR/buildorder.fb"
        exit 1
      fi
    else
      exit 1
    fi
  fi
fi
TOTAL=$(grep -c . "$STATE_DIR/buildorder.txt")

START=$(date +%s)
BUILT=0
FAILED=0
STOP_REASON="semua paket sudah diproses"

while IFS= read -r path; do
  pkg=$(basename "$path")
  [ -n "$pkg" ] || continue
  grep -qxF "$pkg" "$STATE_DIR/buildstatus.txt" && continue
  grep -qxF "$pkg" <(cut -d'|' -f1 "$STATE_DIR/failed.txt") && continue

  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  REMAIN=$((MAX_SECONDS - ELAPSED))
  if [ "$REMAIN" -le 600 ]; then
    STOP_REASON="waktu stage habis"
    break
  fi
  LIMIT=$PKG_TIMEOUT
  [ "$REMAIN" -lt "$LIMIT" ] && LIMIT=$REMAIN

  echo "=== build $pkg (batas ${LIMIT}s, terpakai ${ELAPSED}s) ==="
  timeout -k 60 "$LIMIT" ./build-package.sh -a "$ARCH" -s "$pkg" > "$LOGDIR/$pkg.log" 2>&1
  RC=$?
  if [ "$RC" -eq 0 ]; then
    echo "$pkg" >> "$STATE_DIR/buildstatus.txt"
    BUILT=$((BUILT + 1))
    rm -rf "$HOME/.termux-build/$pkg" "$LOGDIR/$pkg.log"
  elif [ "$RC" -eq 124 ] && [ "$LIMIT" -lt "$PKG_TIMEOUT" ]; then
    # Terpotong batas waktu stage, bukan salah paketnya: coba lagi di stage berikutnya.
    echo "$pkg dipotong batas waktu stage, diulang di stage berikutnya"
    rm -rf "$HOME/.termux-build/$pkg"
    STOP_REASON="waktu stage habis (saat membangun $pkg)"
    break
  else
    echo "::warning::$pkg gagal (exit $RC)"
    echo "$pkg|exit $RC" >> "$STATE_DIR/failed.txt"
    FAILED=$((FAILED + 1))
    rm -rf "$HOME/.termux-build/$pkg"
    echo "--- akhir log $pkg ---"
    tail -n 25 "$LOGDIR/$pkg.log"
  fi
done < "$STATE_DIR/buildorder.txt"

DONE=$(grep -c . "$STATE_DIR/buildstatus.txt")
BAD=$(grep -c . "$STATE_DIR/failed.txt")
LEFT=$((TOTAL - DONE - BAD))
[ "$LEFT" -lt 0 ] && LEFT=0
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
{
  echo "### Hasil stage"
  echo "- dibuild di stage ini: **$BUILT**, gagal di stage ini: **$FAILED**"
  echo "- total selesai: **$DONE** dari $TOTAL, gagal permanen: **$BAD**, sisa: **$LEFT**"
  echo "- berhenti karena: $STOP_REASON"
  if [ "$BAD" -gt 0 ]; then
    echo "- paket gagal (daftar penuh di state):"
    echo '```'
    head -n 40 "$STATE_DIR/failed.txt"
    echo '```'
  fi
} >> "$SUMMARY"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "built=$BUILT"
    echo "failed=$FAILED"
    echo "left=$LEFT"
  } >> "$GITHUB_OUTPUT"
fi
exit 0
