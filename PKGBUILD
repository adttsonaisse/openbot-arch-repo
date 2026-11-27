# Maintainer: openbot-arch-repo contributors
pkgname=openbot-bin
pkgver=0.80.0
pkgrel=1
pkgdesc="A local-first multi-agent desktop workspace (prebuilt AppImage)"
arch=('x86_64' 'aarch64')
url="https://github.com/nightly-labs/openbot"
license=('LicenseRef-PolyForm-Noncommercial-1.0.0')
depends=(
  'alsa-lib'
  'ca-certificates'
  'curl'
  'dbus'
  'gcc-libs'
  'glib2'
  'gtk3'
  'libsecret'
  'libx11'
  'libxcb'
  'libxfixes'
  'libxrandr'
  'libxss'
  'libxtst'
  'mesa'
  'nss'
  'openssl'
  'xdg-utils'
)
makedepends=('squashfs-tools')
optdepends=(
  'at-spi2-core: accessibility support'
  'bubblewrap: sandboxing support for agent tools'
  'git: repository and workspace integration'
  'gnome-keyring: secret storage backend'
  'libcap: POSIX capabilities support'
  'libevdev: input device support for desktop automation'
  'libpulse: PulseAudio / PipeWire audio support'
  'libva: hardware video acceleration'
  'noto-fonts-emoji: emoji rendering support'
  'numactl: NUMA scheduling support'
  'socat: socket relay utilities'
  'ttf-dejavu: default sans/monospace font fallback'
)
provides=('openbot')
conflicts=('openbot')
options=('!strip' '!debug')

source=(
  "${pkgname}-${pkgver}-LICENSE::https://raw.githubusercontent.com/nightly-labs/openbot/v${pkgver}/LICENSE"
  "${pkgname}-${pkgver}-NOTICE::https://raw.githubusercontent.com/nightly-labs/openbot/v${pkgver}/NOTICE"
)
source_x86_64=(
  "OpenBot-${pkgver}-x86_64.AppImage::https://github.com/nightly-labs/openbot/releases/download/v${pkgver}/OpenBot-${pkgver}-x86_64.AppImage"
)
source_aarch64=(
  "OpenBot-${pkgver}-arm64.AppImage::https://github.com/nightly-labs/openbot/releases/download/v${pkgver}/OpenBot-${pkgver}-arm64.AppImage"
)

noextract=(
  "OpenBot-${pkgver}-x86_64.AppImage"
  "OpenBot-${pkgver}-arm64.AppImage"
)

sha256sums=(
  'ffe034ecf735f296ca53cbd856c944849f0c80c7e1490ce162038a99ad89c728'
  '59332c2016e4c4133f07ca2155901752d8c89d6303db5bf3b82f5cbbddaed2d4'
)
sha256sums_x86_64=(
  '0e7815be73f39d248e2dd9f9617e40870105aeefe241a8fef4feb900b92c2944'
)
sha256sums_aarch64=(
  'a4cdab96cf371eb2358549a8ea0466e3e3274cd85183d17738314e12b31a1f5a'
)

prepare() {
  cd "${srcdir}"
  rm -rf squashfs-root

  local _appimage
  if [[ "${CARCH}" == "aarch64" ]]; then
    _appimage="OpenBot-${pkgver}-arm64.AppImage"
  else
    _appimage="OpenBot-${pkgver}-x86_64.AppImage"
  fi

  chmod +x "${_appimage}"
  if ! "./${_appimage}" --appimage-extract >/dev/null 2>&1; then
    # Fallback for cross-architecture builds (e.g. building aarch64 on x86_64)
    local _shoff _shentsize _shnum _offset
    _shoff=$(LC_ALL=C readelf -h "${_appimage}" | awk '/Start of section headers:/ {print $5}')
    _shentsize=$(LC_ALL=C readelf -h "${_appimage}" | awk '/Size of section headers:/ {print $5}')
    _shnum=$(LC_ALL=C readelf -h "${_appimage}" | awk '/Number of section headers:/ {print $5}')
    _offset=$((_shoff + _shentsize * _shnum))
    unsquashfs -q -f -d squashfs-root -o "${_offset}" "${_appimage}"
  fi
}

package() {
  cd "${srcdir}"

  install -dm755 "${pkgdir}/opt/${pkgname}"
  cp -a squashfs-root/. "${pkgdir}/opt/${pkgname}/"

  # Remove AppImage-specific entrypoints; preserve resources/app.asar untouched
  rm -f \
    "${pkgdir}/opt/${pkgname}/AppRun" \
    "${pkgdir}/opt/${pkgname}/.DirIcon" \
    "${pkgdir}/opt/${pkgname}/"*.desktop

  chmod -R a+rX "${pkgdir}/opt/${pkgname}"

  # Fix permissions on SUID sandbox helper
  if [[ -f "${pkgdir}/opt/${pkgname}/chrome-sandbox" ]]; then
    chmod 4755 "${pkgdir}/opt/${pkgname}/chrome-sandbox"
  fi

  # Symlink main binary
  install -dm755 "${pkgdir}/usr/bin"
  ln -s "/opt/${pkgname}/openbot" "${pkgdir}/usr/bin/openbot"

  # Patch and install .desktop file
  local _desktop_src
  _desktop_src=$(find squashfs-root -maxdepth 1 -name '*.desktop' | head -n1)
  if [[ -n "${_desktop_src}" ]]; then
    install -dm755 "${pkgdir}/usr/share/applications"
    sed -E \
      -e 's|^Exec=.*|Exec=/usr/bin/openbot %U|' \
      -e 's|^Icon=.*|Icon=openbot|' \
      "${_desktop_src}" > "${pkgdir}/usr/share/applications/openbot.desktop"
    if ! grep -q '^MimeType=' "${pkgdir}/usr/share/applications/openbot.desktop"; then
      printf 'MimeType=x-scheme-handler/openbot;\n' >> "${pkgdir}/usr/share/applications/openbot.desktop"
    fi
    chmod 644 "${pkgdir}/usr/share/applications/openbot.desktop"
  fi

  # Install icons (hicolor if present + pixmaps fallback)
  if [[ -d "squashfs-root/usr/share/icons/hicolor" ]]; then
    install -dm755 "${pkgdir}/usr/share/icons"
    cp -a squashfs-root/usr/share/icons/hicolor "${pkgdir}/usr/share/icons/"
    find "${pkgdir}/usr/share/icons/hicolor" -type d -exec chmod 755 {} +
    find "${pkgdir}/usr/share/icons/hicolor" -type f -exec chmod 644 {} +
  fi

  local _icon_src=""
  for _candidate in \
    "squashfs-root/openbot.png" \
    "squashfs-root/resources/icons/icon-production.png" \
    "squashfs-root/usr/share/icons/hicolor/512x512/apps/openbot.png" \
    "squashfs-root/usr/share/icons/hicolor/256x256/apps/openbot.png"; do
    if [[ -f "${_candidate}" ]]; then
      _icon_src="${_candidate}"
      break
    fi
  done
  if [[ -n "${_icon_src}" ]]; then
    install -Dm644 "${_icon_src}" "${pkgdir}/usr/share/pixmaps/openbot.png"
  fi

  # Install PolyForm-Noncommercial-1.0.0 LICENSE and NOTICE
  install -Dm644 "${srcdir}/${pkgname}-${pkgver}-LICENSE" \
    "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
  install -Dm644 "${srcdir}/${pkgname}-${pkgver}-NOTICE" \
    "${pkgdir}/usr/share/licenses/${pkgname}/NOTICE"
}
