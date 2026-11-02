#!/bin/bash
# Menerbitkan .deb hasil stage:
#  - .deb diunggah ke GitHub Release (tag debs-<waktu>-<n>)
#  - indeks apt (dists/stable/main/binary-aarch64) dibuat ulang di branch apt-repo,
#    ditandatangani GPG, dengan layout sama seperti repo resmi Termux
# Perlu: dpkg-dev, apt-utils, gnupg, gh.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${GPG_PRIVATE_KEY:?}" "${TP_SHA:?}"
APT_BRANCH=${APT_BRANCH:-apt-repo}
REPO=termux-main
ROOT=$PWD
OUTDIR=$ROOT/tp/output

shopt -s nullglob
DEBS=("$OUTDIR"/*.deb)
if [ "${#DEBS[@]}" -eq 0 ]; then
  echo "tidak ada .deb baru, indeks tidak diubah"
  exit 0
fi

# 1. Nama berkas yang aman untuk GitHub Release (karakter selain A-Za-z0-9._- diganti _).
UP=$ROOT/upload
rm -rf "$UP" && mkdir -p "$UP"
for f in "${DEBS[@]}"; do
  b=$(basename "$f")
  s=$(printf '%s' "$b" | sed -E 's/[^A-Za-z0-9._-]/_/g')
  ln "$f" "$UP/$s" 2>/dev/null || cp "$f" "$UP/$s"
done

# 2. Unggah ke Release, maksimal 800 berkas per tag.
STAMP=$(date -u +%Y%m%d-%H%M%S)
cd "$UP"
ls -1 *.deb | split -l 800 -d -a 2 - "$ROOT/chunk."
cd "$ROOT"
TAGS=()
for c in chunk.*; do
  TAG="debs-$STAMP-${c##*.}"
  TAGS+=("$TAG")
  gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --title "Paket $TAG" \
    --notes "Paket .deb toolAPKAI (commit termux-packages ${TP_SHA})." >/dev/null
  mkdir -p "$ROOT/frag/$TAG"
  ( cd "$UP" && tr '\n' '\0' < "$ROOT/$c" | xargs -0 -n 40 gh release upload "$TAG" --repo "$GITHUB_REPOSITORY" )
  # Potongan indeks untuk tag ini; Filename diarahkan ke pool/<tag>/<berkas>.
  while IFS= read -r f; do
    ln "$UP/$f" "$ROOT/frag/$TAG/$f" 2>/dev/null || cp "$UP/$f" "$ROOT/frag/$TAG/$f"
  done < "$ROOT/$c"
  ( cd "$ROOT/frag/$TAG" && dpkg-scanpackages -m . /dev/null ) \
    | sed -E "s#^Filename: \./#Filename: pool/$TAG/#" > "$ROOT/frag/$TAG.Packages"
  rm -rf "$ROOT/frag/$TAG"
done

# 3. Ambil isi branch apt-repo (hanya folder index/), buang sisa layout lama.
SITE=$ROOT/site
rm -rf "$SITE" && mkdir -p "$SITE"
if git ls-remote --exit-code --heads origin "$APT_BRANCH" >/dev/null 2>&1; then
  git fetch -q --depth 1 origin "refs/heads/$APT_BRANCH:refs/remotes/origin/$APT_BRANCH"
  git archive "origin/$APT_BRANCH" | tar -x -C "$SITE"
fi
cd "$SITE"
find . -maxdepth 1 -type f \( -name '*.deb' -o -name 'Packages*' -o -name Release -o -name BUILT.txt -o -name PAKET.md \) -delete
mkdir -p "$REPO/index"
for t in "${TAGS[@]}"; do cp "$ROOT/frag/$t.Packages" "$REPO/index/$t.Packages"; done

# 4. Gabungkan semua potongan indeks (yang lebih baru menimpa yang lama).
python3 - "$REPO" <<'PY'
import glob, sys, os
repo = sys.argv[1]
best = {}
for f in sorted(glob.glob(os.path.join(repo, 'index', '*.Packages'))):
    for st in open(f, encoding='utf-8').read().split('\n\n'):
        st = st.strip('\n')
        if not st.strip():
            continue
        d = {}
        for line in st.split('\n'):
            if line[:1] in (' ', '\t'):
                continue
            k, _, v = line.partition(':')
            d[k] = v.strip()
        best[(d.get('Package', ''), d.get('Architecture', ''))] = st
d = os.path.join(repo, 'dists', 'stable', 'main', 'binary-aarch64')
os.makedirs(d, exist_ok=True)
with open(os.path.join(d, 'Packages'), 'w', encoding='utf-8') as o:
    o.write('\n\n'.join(best[k] for k in sorted(best)) + '\n')
print('total paket di indeks:', len(best))
PY
D=$REPO/dists/stable
( cd "$D/main/binary-aarch64" && gzip -9 -k -f Packages && xz -9 -k -f Packages )

# 5. Release + tanda tangan.
( cd "$REPO" && apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=toolAPKAI \
    -o APT::FTPArchive::Release::Label=toolAPKAI \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o APT::FTPArchive::Release::Architectures=aarch64 \
    -o APT::FTPArchive::Release::Components=main \
    release dists/stable > "$ROOT/Release.tmp" )
mv "$ROOT/Release.tmp" "$D/Release"

export GNUPGHOME
GNUPGHOME=$(mktemp -d); chmod 700 "$GNUPGHOME"
printf '%s\n' "$GPG_PRIVATE_KEY" | gpg --batch --quiet --import
KEYID=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
GPGARGS=(--batch --yes --pinentry-mode loopback --passphrase "${GPG_PASSPHRASE:-}" --local-user "$KEYID")
gpg "${GPGARGS[@]}" --clearsign -o "$D/InRelease" "$D/Release"
gpg "${GPGARGS[@]}" --detach-sign --armor -o "$D/Release.gpg" "$D/Release"
gpg --batch --export "$KEYID" > "$SITE/toolapkai.gpg"
rm -rf "$GNUPGHOME"

# 6. Dorong ke branch apt-repo (satu commit, isinya kecil: hanya indeks).
git init -q
git config user.name github-actions
git config user.email actions@users.noreply.github.com
git checkout -q -b "$APT_BRANCH"
git add -A
git commit -q -m "apt repo: ${TP_SHA} (${TAGS[*]})"
git remote add origin "https://x-access-token:${GH_TOKEN:?}@github.com/${GITHUB_REPOSITORY}.git"
git push -q -f origin "$APT_BRANCH"
{
  echo "### Repo apt diperbarui"
  echo "- .deb baru: ${#DEBS[@]} (tag: ${TAGS[*]})"
  echo "- jumlah paket di indeks: $(grep -c '^Package:' "$REPO/dists/stable/main/binary-aarch64/Packages")"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
