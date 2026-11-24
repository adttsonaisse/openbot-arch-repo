# openbot-arch-repo (`openbot-bin`)

Custom Arch Linux `pacman` repository untuk [**OpenBot**](https://github.com/nightly-labs/openbot) (paket `openbot-bin`), mendukung arsitektur `x86_64` dan `aarch64`.

Paket ini dibangun dengan mengekstrak AppImage resmi dari `nightly-labs/openbot` (tanpa memodifikasi `resources/app.asar`), mengatur permission `chrome-sandbox` (`4755`), memasang symlink `/usr/bin/openbot`, `.desktop` + `openbot://` URI handler, ikon, serta `LICENSE` + `NOTICE`.

> [!WARNING]
> **Catatan Lisensi (`PolyForm-Noncommercial-1.0.0`)**
>
> OpenBot dirilis di bawah lisensi **PolyForm Noncommercial License 1.0.0** (bukan FOSS / bukan lisensi komersial). Penggunaan hanya diperbolehkan untuk keperluan **non-komersial** sesuai ketentuan lisensi upstream di `nightly-labs/openbot`. File `LICENSE` dan `NOTICE` ikut terpasang di `/usr/share/licenses/openbot-bin/`.

---

## Struktur Repo

- `PKGBUILD` & `.SRCINFO` — resep paket `openbot-bin` (`x86_64` & `aarch64`)
- `scripts/build-local-repo.sh` — script build lokal (`makepkg` + `repo-add`)
- `scripts/update-pkgbuild.sh` — script cek rilis terbaru & update `PKGBUILD` + `.SRCINFO`
- `.github/workflows/build-arch-repo.yml` — workflow GitHub Actions harian yang otomatis build di container `archlinux:base-devel` lalu publish ke GitHub Releases (`arch-x86_64` dan `arch-aarch64`)

> Kenapa pakai GitHub Releases dan bukan `gh-pages`? Karena ukuran `.pkg.tar.zst` hasil ekstrak AppImage OpenBot berkisar ~150–200 MB, melewati batas file 100 MB GitHub Git push. GitHub Releases mendukung asset hingga 2 GB per file dan cocok dengan variabel `$arch` milik `pacman`.

---

## Cara 1: Pakai Repo via GitHub Releases (Recommended)

### 1. Setup & Aktifkan GitHub Actions di Repo Kamu

1. Push repo ini ke GitHub kamu sendiri (misal `https://github.com/adttsonaisse/openbot-arch-repo`).
2. Pastikan GitHub Actions punya izin tulis (*Settings -> Actions -> General -> Workflow permissions -> Read and write permissions*).
3. Untuk build pertama kali, buka tab **Actions -> Build & Publish Arch Linux Repo -> Run workflow**.
   Setelah selesai, akan muncul release tag `arch-x86_64` dan `arch-aarch64` berisi `.pkg.tar.zst`, `openbot.db`, dan `openbot.files`.
   Selanjutnya workflow otomatis mengecek rilis baru `nightly-labs/openbot` setiap hari pukul `03:00 UTC` (`10:00 WIB`).

*(Opsional) GPG Signing di CI:*
Jika ingin paket dan database repo bertanda tangan GPG, tambahkan repository secrets:
- `GPG_PRIVATE_KEY`: private key GPG ASCII-armored (`gpg --armor --export-secret-keys <KEY_ID>`)
- `GPG_PASSPHRASE`: passphrase key tersebut (kosongkan jika key CI tanpa passphrase)

### 2. Tambahkan ke `/etc/pacman.conf`

Ganti `adttsonaisse/openbot-arch-repo` dengan username dan nama repo GitHub kamu:

```ini
[openbot]
SigLevel = Optional TrustAll
Server = https://github.com/adttsonaisse/openbot-arch-repo/releases/download/arch-$arch
```

Jika kamu mengaktifkan GPG signing di CI, import public key-nya (`openbot-repo.asc` di release asset) terlebih dahulu lalu ubah `SigLevel`:

```bash
curl -fsSL https://github.com/adttsonaisse/openbot-arch-repo/releases/download/arch-x86_64/openbot-repo.asc | sudo pacman-key --add -
sudo pacman-key --lsign-key <GPG_KEY_FINGERPRINT>
```

```ini
[openbot]
SigLevel = Required DatabaseOptional
Server = https://github.com/adttsonaisse/openbot-arch-repo/releases/download/arch-$arch
```

### 3. Install OpenBot

```bash
sudo pacman -Syu openbot-bin
```

Untuk update versi baru di kemudian hari, cukup jalankan `sudo pacman -Syu`.

---

## Cara 2: Build & Host Local Repo Sendiri

Kalau mau build langsung di mesin Arch Linux kamu dan simpan sebagai repo lokal (`file://`):

```bash
# 1. Build paket + generate repo database di ./repo/<arch>/
./scripts/build-local-repo.sh --clean

# (Opsional) Build dengan GPG signing:
./scripts/build-local-repo.sh --clean --gpg-key <GPG_KEY_ID>

# (Opsional) Build hanya tanpa install GUI deps di mesin build / cross-arch:
./scripts/build-local-repo.sh --clean --nodeps
./scripts/build-local-repo.sh --clean --arch aarch64 --nodeps
```

Tambahkan output konfigurasi yang dicetak script ke `/etc/pacman.conf` (ganti `/ABS/PATH/TO/openbot-arch-repo` dengan path absolut folder repo ini):

```ini
[openbot]
SigLevel = Optional TrustAll
Server = file:///ABS/PATH/TO/openbot-arch-repo/repo/$arch
```

Lalu install:

```bash
sudo pacman -Syu openbot-bin
```

---

## Update Versi Manual (`PKGBUILD`)

Untuk mengecek rilis terbaru `nightly-labs/openbot` secara manual dan memperbarui `PKGBUILD` + `.SRCINFO`:

```bash
./scripts/update-pkgbuild.sh
# atau spesifik versi tertentu:
./scripts/update-pkgbuild.sh 0.77.0
```
