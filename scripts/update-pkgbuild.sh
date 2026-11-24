#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname -- "${SCRIPT_DIR}")"
PKGBUILD_PATH="${REPO_ROOT}/PKGBUILD"
SRCINFO_PATH="${REPO_ROOT}/.SRCINFO"
UPSTREAM_REPO="nightly-labs/openbot"

TARGET_VERSION=""
BUMP_PKGREL="false"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS] [VERSION]

Fetch the latest (or specified) release of ${UPSTREAM_REPO}, verify upstream
SHA256 checksums, and update PKGBUILD + .SRCINFO.

Options:
  --bump-pkgrel    Increment pkgrel if pkgver is unchanged
  -h, --help       Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") v0.77.0
  $(basename "$0") 0.77.0
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump-pkgrel)
      BUMP_PKGREL="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      TARGET_VERSION="$1"
      shift
      ;;
  esac
done

for cmd in curl jq sha256sum python3; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: required command not found: ${cmd}" >&2
    exit 1
  fi
done

curl_gh() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$@"
  else
    curl -fsSL "$@"
  fi
}

if [[ -z "${TARGET_VERSION}" ]]; then
  echo "Checking latest release for ${UPSTREAM_REPO}..."
  TAG_NAME="$(curl_gh "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" | jq -r '.tag_name')"
else
  TAG_NAME="v${TARGET_VERSION#v}"
fi

if [[ -z "${TAG_NAME}" || "${TAG_NAME}" == "null" ]]; then
  echo "Error: failed to resolve release tag." >&2
  exit 1
fi

NEW_PKGVER="${TAG_NAME#v}"
CURRENT_PKGVER="$(awk -F= '/^pkgver=/{print $2; exit}' "${PKGBUILD_PATH}" | tr -d "'\"" )"
CURRENT_PKGREL="$(awk -F= '/^pkgrel=/{print $2; exit}' "${PKGBUILD_PATH}" | tr -d "'\"" )"

echo "Current PKGBUILD version : ${CURRENT_PKGVER}-${CURRENT_PKGREL}"
echo "Target upstream version  : ${NEW_PKGVER} (tag: ${TAG_NAME})"

if [[ "${NEW_PKGVER}" == "${CURRENT_PKGVER}" && "${BUMP_PKGREL}" != "true" ]]; then
  echo "PKGBUILD is already at ${NEW_PKGVER}. Nothing to update."
  exit 0
fi

if [[ "${NEW_PKGVER}" == "${CURRENT_PKGVER}" ]]; then
  NEW_PKGREL=$((CURRENT_PKGREL + 1))
else
  NEW_PKGREL=1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SHA_FILE="${TMP_DIR}/SHA256SUMS.txt"
BASE_DL="https://github.com/${UPSTREAM_REPO}/releases/download/${TAG_NAME}"
BASE_RAW="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${TAG_NAME}"

if ! curl_gh "${BASE_DL}/SHA256SUMS.txt" -o "${SHA_FILE}" 2>/dev/null; then
  # Fallback to per-arch checksum files if combined SHA256SUMS.txt is absent
  : > "${SHA_FILE}"
  curl_gh "${BASE_DL}/SHA256SUMS-linux.txt" >> "${SHA_FILE}" || true
  curl_gh "${BASE_DL}/SHA256SUMS-linux-arm64.txt" >> "${SHA_FILE}" || true
fi

extract_sha() {
  local filename="$1"
  awk -v f="${filename}" '{
    gsub(/\r/, "", $0);
    name = $2;
    sub(/^\*/, "", name);
    if (name == f) { print $1; exit }
  }' "${SHA_FILE}"
}

X86_ASSET="OpenBot-${NEW_PKGVER}-x86_64.AppImage"
ARM_ASSET="OpenBot-${NEW_PKGVER}-arm64.AppImage"

SHA_X86="$(extract_sha "${X86_ASSET}")"
SHA_ARM="$(extract_sha "${ARM_ASSET}")"

if [[ -z "${SHA_X86}" ]]; then
  echo "Checksum for ${X86_ASSET} not in SHA256SUMS; downloading to compute..."
  curl_gh "${BASE_DL}/${X86_ASSET}" -o "${TMP_DIR}/${X86_ASSET}"
  SHA_X86="$(sha256sum "${TMP_DIR}/${X86_ASSET}" | awk '{print $1}')"
fi

if [[ -z "${SHA_ARM}" ]]; then
  echo "Checksum for ${ARM_ASSET} not in SHA256SUMS; downloading to compute..."
  curl_gh "${BASE_DL}/${ARM_ASSET}" -o "${TMP_DIR}/${ARM_ASSET}"
  SHA_ARM="$(sha256sum "${TMP_DIR}/${ARM_ASSET}" | awk '{print $1}')"
fi

echo "Computing SHA256 for LICENSE and NOTICE..."
SHA_LICENSE="$(curl_gh "${BASE_RAW}/LICENSE" | sha256sum | awk '{print $1}')"
SHA_NOTICE="$(curl_gh "${BASE_RAW}/NOTICE" | sha256sum | awk '{print $1}')"

echo "Resolved checksums:"
echo "  LICENSE : ${SHA_LICENSE}"
echo "  NOTICE  : ${SHA_NOTICE}"
echo "  x86_64  : ${SHA_X86}"
echo "  aarch64 : ${SHA_ARM}"

python3 - "${PKGBUILD_PATH}" "${NEW_PKGVER}" "${NEW_PKGREL}" "${SHA_LICENSE}" "${SHA_NOTICE}" "${SHA_X86}" "${SHA_ARM}" <<'PYEOF'
import re
import sys

pkgbuild_path, pkgver, pkgrel, sha_lic, sha_notice, sha_x86, sha_arm = sys.argv[1:8]

with open(pkgbuild_path, "r", encoding="utf-8") as f:
    content = f.read()

content = re.sub(r"^pkgver=.*$", f"pkgver={pkgver}", content, count=1, flags=re.MULTILINE)
content = re.sub(r"^pkgrel=.*$", f"pkgrel={pkgrel}", content, count=1, flags=re.MULTILINE)
content = re.sub(
    r"sha256sums=\(\s*'[^']*'\s*'[^']*'\s*\)",
    f"sha256sums=(\n  '{sha_lic}'\n  '{sha_notice}'\n)",
    content,
    count=1,
    flags=re.MULTILINE,
)
content = re.sub(
    r"sha256sums_x86_64=\(\s*'[^']*'\s*\)",
    f"sha256sums_x86_64=(\n  '{sha_x86}'\n)",
    content,
    count=1,
    flags=re.MULTILINE,
)
content = re.sub(
    r"sha256sums_aarch64=\(\s*'[^']*'\s*\)",
    f"sha256sums_aarch64=(\n  '{sha_arm}'\n)",
    content,
    count=1,
    flags=re.MULTILINE,
)

with open(pkgbuild_path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

if command -v makepkg >/dev/null 2>&1 && [[ "$(id -u)" -ne 0 ]]; then
  echo "Regenerating .SRCINFO..."
  (cd "${REPO_ROOT}" && makepkg --printsrcinfo > "${SRCINFO_PATH}")
else
  echo "Note: skipping makepkg --printsrcinfo (missing makepkg or running as root)."
fi

echo "Updated PKGBUILD to ${NEW_PKGVER}-${NEW_PKGREL}."
