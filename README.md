# toolapkai-packages

Build paket Termux dengan prefix `/data/data/com.user.toolapkai/files/usr`
untuk app toolAPKAI. Hasilnya diterbitkan sebagai repo apt di branch `apt-repo`.

## Pakai

1. Actions → Build Packages → Run workflow.
2. `packages`: paket dari termux-packages (default `git`).
3. `custom_packages`: nama folder di `custom-packages/` (opsional).
4. `force_rebuild`: tidak dicentang = build hanya kalau commit termux-packages
   terbaru, daftar paket, atau isi `custom-packages/` berubah. Dicentang = paksa ulang.

## Pasang di terminal app

echo 'deb [trusted=yes] https://raw.githubusercontent.com/<USER>/toolapkai-packages/apt-repo ./' \
  > $PREFIX/etc/apt/sources.list.d/toolapkai.list
apt update

Repo tidak ditandatangani GPG (`trusted=yes`): untuk pemakaian pribadi saja.
