# Panduan Update SyStats (Sparkle 2)

Diadaptasi dari pola [BatteryLenovoAssistent](EFI/BatteryLenovoAssistent/SUMMARY_SPARKLE.md).

## Prasyarat sekali saja

Simpan private key Ed25519 sebagai **GitHub Repository Secret**:

1. Buka repo → **Settings → Secrets and variables → Actions → New repository secret**.
2. Nama: `SPARKLE_PRIVATE_KEY`
3. Isi (base64, 96 byte — JANGAN pernah di-commit):

```
BASE64_PRIVATE_KEY_PLACEHOLDER
```

> Private key tidak pernah masuk git. `.gitignore` sudah mengabaikan
> `.sparkle-tools/`, `private-key*.txt`, `priv.pem`, dan `*.tar.xz`.

Public key terpasang di `Config/Info.plist` (`SUPublicEDKey`) dan **tidak boleh diubah** setelah app didistribusikan, kalau tidak user lama gagal verifikasi update.

## Alur rilis

1. Naikkan versi di `project.yml`:
   - `MARKETING_VERSION` → mis. `1.2.0`
   - `CURRENT_PROJECT_VERSION` → mis. `2` (build number)
2. Commit & push ke `main`.
3. Push tag: `git tag -a v1.2.0 -m "v1.2.0" && git push origin v1.2.0`.
4. Workflow `.github/workflows/build-release.yml` otomatis:
   - build universal + ad-hoc sign;
   - buat `SyStats-v1.2.0.zip` + `.dmg` + `SHA256SUMS.txt`;
   - upload ke GitHub Release;
   - **tanda tangani zip** dengan `SPARKLE_PRIVATE_KEY`;
   - **menulis item terbaru ke `appcast.xml`** dan commit balik ke `main` (dengan `[skip ci]`).
5. Sparkle di app membaca `appcast.xml` dari:
   ```
   https://raw.githubusercontent.com/Syuhadak27/SyStats/main/appcast.xml
   ```
   Automatic checks tiap 24 jam, atau user klik **Check for Updates…** di popover.

## Verifikasi feed

```bash
curl -fsSL https://raw.githubusercontent.com/Syuhadak27/SyStats/main/appcast.xml | xmllint --noout -
```

## Catatan

- Nama aset zip mengikuti `github.ref_name` (mis. `SyStats-v1.2.0.zip`), sama seperti pola workflow yang sudah ada.
- Jika secret belum diset, workflow tetap sukses build & release, tapi **appcast tidak diperbarui** (ada warning di log).
- Jangan mengubah isi zip setelah ditandatangani — signature jadi invalid.
