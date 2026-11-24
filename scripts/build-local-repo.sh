#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname -- "${SCRIPT_DIR}")"

REPO_NAME="openbot"
REPO_BASE_DIR="${REPO_ROOT}/repo"
TARGET_ARCH="$(uname -m)"
GPG_KEY_ID="${GPG_KEY_ID:-}"
SIGN_REPO="false"
NODEPS="false"
CLEAN_BUILD="false"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Build openbot-bin using makepkg and publish it to a local pacman repository
using repo-add.

Options:
  --arch <x86_64|aarch64>  Target architecture (default: host ${TARGET_ARCH})
  --repo-dir <path>        Output repo base directory (default: ./repo)
  --repo-name <name>       Pacman repository name (default: openbot)
  --sign                   Sign package & repo database with GPG
  --gpg-key <key-id>       GPG key ID/fingerprint (implies --sign)
  --nodeps                 Pass --nodeps to makepkg (skip host dep checks)
  --clean                  Clean src/ and pkg/ before building
  -h, --help               Show this help message

Environment:
  GPG_KEY_ID               Default GPG key ID if --gpg-key is not specified
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      TARGET_ARCH="$2"
      shift 2
      ;;
    --repo-dir)
      REPO_BASE_DIR="$2"
      shift 2
      ;;
    --repo-name)
      REPO_NAME="$2"
      shift 2
      ;;
    --sign)
      SIGN_REPO="true"
      shift
      ;;
    --gpg-key)
      GPG_KEY_ID="$2"
      SIGN_REPO="true"
      shift 2
      ;;
    --nodeps)
      NODEPS="true"
      shift
      ;;
    --clean)
      CLEAN_BUILD="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Error: do not run this script as root (makepkg refuses root)." >&2
  exit 1
fi

case "${TARGET_ARCH}" in
  x86_64|aarch64) ;;
  *)
    echo "Error: unsupported architecture '${TARGET_ARCH}'. Use x86_64 or aarch64." >&2
    exit 1
    ;;
esac

for cmd in makepkg repo-add; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: required command not found: ${cmd}" >&2
    exit 1
  fi
done

ARCH_REPO_DIR="${REPO_BASE_DIR}/${TARGET_ARCH}"
mkdir -p "${ARCH_REPO_DIR}"

MAKEPKG_ARGS=(-f)
if [[ "${CLEAN_BUILD}" == "true" ]]; then
  MAKEPKG_ARGS+=(-C)
fi

HOST_ARCH="$(uname -m)"
TEMP_CONF=""
trap '[[ -n "${TEMP_CONF}" ]] && rm -f "${TEMP_CONF}"' EXIT

if [[ "${TARGET_ARCH}" != "${HOST_ARCH}" ]]; then
  echo "Cross-arch build detected (${HOST_ARCH} -> ${TARGET_ARCH}); forcing --nodeps."
  NODEPS="true"
  TEMP_CONF="$(mktemp)"
  cp /etc/makepkg.conf "${TEMP_CONF}"
  sed -i -E "s|^CARCH=.*|CARCH=\"${TARGET_ARCH}\"|" "${TEMP_CONF}"
  MAKEPKG_ARGS+=(--config "${TEMP_CONF}")
fi

if [[ "${NODEPS}" == "true" ]]; then
  MAKEPKG_ARGS+=(-d)
else
  MAKEPKG_ARGS+=(-s --noconfirm)
fi

if [[ "${SIGN_REPO}" == "true" ]]; then
  MAKEPKG_ARGS+=(--sign)
  if [[ -n "${GPG_KEY_ID}" ]]; then
    MAKEPKG_ARGS+=(--key "${GPG_KEY_ID}")
  fi
fi

echo "Building openbot-bin for ${TARGET_ARCH}..."
(
  cd "${REPO_ROOT}"
  PKGDEST="${ARCH_REPO_DIR}" makepkg "${MAKEPKG_ARGS[@]}"
  makepkg --printsrcinfo > "${REPO_ROOT}/.SRCINFO"
)

PKG_FILE="$(find "${ARCH_REPO_DIR}" -maxdepth 1 -type f -name "openbot-bin-*-${TARGET_ARCH}.pkg.tar.*" ! -name "*.sig" | sort -V | tail -n1)"
if [[ -z "${PKG_FILE}" ]]; then
  echo "Error: built package file not found in ${ARCH_REPO_DIR}" >&2
  exit 1
fi

REPO_ADD_ARGS=(-R)
if [[ "${SIGN_REPO}" == "true" ]]; then
  REPO_ADD_ARGS+=(-s)
  if [[ -n "${GPG_KEY_ID}" ]]; then
    REPO_ADD_ARGS+=(-k "${GPG_KEY_ID}")
  fi
fi

DB_FILE="${ARCH_REPO_DIR}/${REPO_NAME}.db.tar.gz"
echo "Updating repository database ${DB_FILE}..."
repo-add "${REPO_ADD_ARGS[@]}" "${DB_FILE}" "${PKG_FILE}"

echo ""
echo "Local Arch repository ready!"
echo "  Package : ${PKG_FILE}"
echo "  DB      : ${DB_FILE}"
echo ""
echo "Add this block to /etc/pacman.conf:"
echo ""
echo "[${REPO_NAME}]"
if [[ "${SIGN_REPO}" == "true" ]]; then
  echo "SigLevel = Required DatabaseOptional"
else
  echo "SigLevel = Optional TrustAll"
fi
echo "Server = file://${REPO_BASE_DIR}/\$arch"
echo ""
echo "Then install with:"
echo "  sudo pacman -Syu openbot-bin"
