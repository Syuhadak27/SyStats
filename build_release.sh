#!/usr/bin/env bash
#
# build_release.sh — Build Release + zip + tanda tangan Sparkle (Ed25519).
#
# Diadaptasi dari EFI/BatteryLenovoAssistent/build_release.sh.
# Versi dibaca dari CFBundleShortVersionString pada app hasil build (TIDAK di-hardcode).
# Private key TIDAK pernah di-commit. Sumber (pilih salah satu):
#   - Keychain Sparkle account "SyStats" (default; dipakai generate_keys)
#   - File lokal: $HOME/Documents/SyStats-PrivateKey.txt
#   - GitHub Actions Secret SPARKLE_PRIVATE_KEY (dipakai workflow)
#
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="${PROJECT:-SyStats.xcodeproj}"
SCHEME="${SCHEME:-SyStats}"
CONFIGURATION="Release"
DERIVED_DATA="${DERIVED_DATA:-build}"
APP_NAME="SyStats"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.10.1}"
CACHE_DIR="${HOME}/.cache/SyStats/sparkle-${SPARKLE_VERSION}"
PRIVATE_KEY="${SPARKLE_PRIVATE_KEY_FILE:-$HOME/Documents/SyStats-PrivateKey.txt}"

echo "==> 1/4 Build ${SCHEME} (${CONFIGURATION})"
if [ ! -d "${PROJECT}" ]; then
  echo "    ${PROJECT} belum ada — generate dulu: xcodegen generate --spec project.yml --project ."
  xcodegen generate --spec project.yml --project .
fi
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  -quiet \
  MACOSX_DEPLOYMENT_TARGET=13.0 \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS='x86_64 arm64' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [ ! -d "${APP}" ]; then
  echo "ERROR: app tidak ditemukan di ${APP}" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
echo "    Versi: ${VERSION} (build ${BUILD_NUMBER})"

echo "==> 2/4 Buat zip ${APP_NAME}-${VERSION}.zip"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
rm -f "${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP_NAME}"
LENGTH="$(stat -f%z "${ZIP_NAME}")"

echo "==> 3/4 Siapkan sign_update (Sparkle ${SPARKLE_VERSION})"
if [ ! -x "${CACHE_DIR}/sign_update" ]; then
  mkdir -p "${CACHE_DIR}"
  echo "    Mengunduh sign_update ke ${CACHE_DIR} ..."
  curl --fail --location --retry 3 --silent --show-error \
    -o "${CACHE_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  tar -xJf "${CACHE_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz" -C "${CACHE_DIR}" bin/sign_update
  mv "${CACHE_DIR}/bin/sign_update" "${CACHE_DIR}/sign_update"
  rm -rf "${CACHE_DIR}/bin"
  chmod +x "${CACHE_DIR}/sign_update"
fi
SIGN_UPDATE="${CACHE_DIR}/sign_update"

echo "==> 4/4 Tanda tangani zip"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  SIGNATURE="$("${SIGN_UPDATE}" --ed-key-file - -p "${ZIP_NAME}" <<< "${SPARKLE_PRIVATE_KEY}")"
elif [ -f "${PRIVATE_KEY}" ]; then
  chmod 600 "${PRIVATE_KEY}" 2>/dev/null || true
  SIGNATURE="$("${SIGN_UPDATE}" --ed-key-file "${PRIVATE_KEY}" -p "${ZIP_NAME}")"
else
  echo "    Tidak ada private key file; pakai Keychain account SyStats."
  SIGNATURE="$("${SIGN_UPDATE}" --account SyStats -p "${ZIP_NAME}")"
fi

cat <<EOF

SELESAI. Tempelkan ke appcast.xml (item untuk versi ${VERSION}):

  <enclosure
    url="https://github.com/Syuhadak27/SyStats/releases/download/v${VERSION}/${ZIP_NAME}"
    sparkle:version="${BUILD_NUMBER}"
    sparkle:shortVersionString="${VERSION}"
    sparkle:edSignature="${SIGNATURE}"
    type="application/octet-stream"
    length="${LENGTH}" />

Ringkasan:
  File zip : $(pwd)/${ZIP_NAME}
  Size     : ${LENGTH} bytes
  Signature: ${SIGNATURE}

Upload zip ke GitHub Releases tag v${VERSION}, lalu perbarui appcast.xml dan push ke main.
EOF
