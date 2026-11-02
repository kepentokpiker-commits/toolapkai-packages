# toolapkai-packages

Build semua paket Termux dengan prefix `/data/data/com.user.toolapkai/files/usr`
untuk app toolAPKAI, diterbitkan sebagai repo apt berlayout sama seperti repo resmi
(`dists/stable/main/binary-aarch64`, bertanda tangan GPG) supaya `pkg update` dan
`pkg upgrade` bekerja seperti biasa, tetapi memakai repo ini.

## Persiapan sekali saja

1. Buat kunci GPG tanpa kedaluwarsa, lalu isi **Settings > Secrets and variables > Actions**:
   - Secret `GPG_PRIVATE_KEY`: hasil `gpg --armor --export-secret-keys <id>`
   - Secret `GPG_PASSPHRASE`: kata sandi kunci (kosongkan kalau tanpa sandi)
   - Variable `APT_BASE_URL`: alamat Worker tanpa garis miring akhir,
     misalnya `https://toolapkai.NAMAKAMU.workers.dev`
2. Deploy `worker/apt-proxy.js` di Cloudflare Workers (gratis). Ganti `OWNER` dan `REPO`
   di bagian atas file. Worker meneruskan indeks dari branch `apt-repo` dan mengalihkan
   unduhan `.deb` ke GitHub Releases.
3. Settings > Actions > General > Workflow permissions: pilih **Read and write**.

## Menjalankan

1. Actions > **Build All Packages (bertahap)** > Run workflow. Biarkan `auto_continue` dicentang:
   setiap stage membangun paket sampai batas waktu, menerbitkan hasilnya, menyimpan state,
   lalu menjalankan stage berikutnya sendiri sampai semua paket selesai.
2. Paket yang gagal dicatat di ringkasan run dan dilewati. Daftar penuh ada di state.
3. Setelah beberapa stage, jalankan **Build Bootstrap** untuk mengambil `bootstrap-aarch64.zip`
   dari Release `bootstrap`.

## Struktur

- `scripts/patch-tp.sh`: ganti prefix, URL repo, dan keyring di salinan termux-packages
- `scripts/stage-build.sh`: build berurutan dengan batas waktu, lanjut dari state
- `scripts/publish-stage.sh`: unggah `.deb` ke Release dan buat indeks apt bertanda tangan
- `scripts/state-save.sh`, `scripts/state-restore.sh`: simpan/pulihkan state antar-stage
  (Release `state`, jangan dihapus)
- `custom-packages/`: paket sendiri; folder di sini disalin ke `packages/` dan menimpa yang resmi
  (termasuk `termux-keyring` yang berisi kunci publik repo ini)
