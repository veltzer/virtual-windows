#!/bin/bash -eu
# Download the Windows 11 Enterprise evaluation ISO from the Microsoft
# Evaluation Center and record its SHA-256.
#
# The Evaluation Center publishes one stable go.microsoft.com/fwlink redirect
# per language that resolves to a static file on Microsoft's CDN: no session
# handshake, no expiring links, no per-IP rate limit. The SHA-256 comes from
# the "Windows11EnterpriseHashValues.pdf" linked from the same page; the
# download is checked against it and the value is pinned as ISO_SHA256 in
# config.sh. The evaluation runs for 90 days after installation.
#
# Usage: ./download_iso.sh              download the ISO (resumes a partial one)
#        ./download_iso.sh --print-url  only print the resolved link, file name and checksum
#        ./download_iso.sh --force      download even if the ISO already exists
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

print_url=0
force=0
for arg in "$@"; do
	case "${arg}" in
	--print-url) print_url=1 ;;
	--force) force=1 ;;
	*)
		echo "usage: $0 [--print-url] [--force]" >&2
		exit 2
		;;
	esac
done

for tool in curl pdftotext; do
	if ! command -v "${tool}" >/dev/null; then
		echo "error: ${tool} not found; run ./install_prereqs.sh" >&2
		exit 1
	fi
done

if ((!print_url && !force)) && [[ -f "${ISO}" ]]; then
	echo "already present: ${ISO} (use --force to download again, ./verify_iso.sh to check it)"
	exit 0
fi

user_agent="Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
fwlink="https://go.microsoft.com/fwlink/?linkid=${ISO_FWLINK}&clcid=0x409&culture=en-us&country=us"
hash_pdf_link="https://go.microsoft.com/fwlink/?linkid=${ISO_HASH_PDF_FWLINK}"
tmp_pdf="$(mktemp --suffix=.pdf)"
trap 'rm -f "${tmp_pdf}"' EXIT

# 1. Resolve the redirect to the CDN file without downloading it.
echo "resolving ${fwlink}"
url="$(curl --silent --show-error --fail --head --location --output /dev/null \
	--user-agent "${user_agent}" --write-out '%{url_effective}' "${fwlink}")"
file_name="$(basename "${url%%\?*}")"
size="$(curl --silent --show-error --fail --head --location --user-agent "${user_agent}" "${url}" |
	tr -d '\r' | grep -i '^content-length:' | tail -n1 | awk '{print $2}' || true)"
case "${file_name}" in
*ENTERPRISEEVAL*_"${ISO_LANGUAGE}".iso) ;;
*)
	echo "error: fwlink ${ISO_FWLINK} resolved to ${file_name}, not an Enterprise evaluation ISO for ${ISO_LANGUAGE}" >&2
	echo "check ISO_FWLINK/ISO_LANGUAGE in config.sh against ${ISO_EVAL_PAGE}" >&2
	exit 1
	;;
esac

# 2. Fetch the hash PDF and pick the row for this language. The row reads
#    "Description Enterprise Eval x64 Eval EN-US DVD9" and the SHA-256 is the
#    next line that is 64 hex digits.
echo "fetching hash values ${hash_pdf_link}"
curl --silent --show-error --fail --location --user-agent "${user_agent}" --output "${tmp_pdf}" "${hash_pdf_link}"
sha256="$(pdftotext -layout "${tmp_pdf}" - |
	awk -v label="${ISO_HASH_LABEL}" '
		index($0, label) { want = 1; next }
		want && /^[[:space:]]*[0-9A-Fa-f]{64}[[:space:]]*$/ { gsub(/[[:space:]]/, ""); print tolower($0); exit }
	' || true)"
if [[ -z "${sha256}" ]]; then
	echo "error: no SHA-256 for '${ISO_HASH_LABEL}' in the hash PDF; check ISO_HASH_LABEL in config.sh" >&2
	exit 1
fi

if [[ "${sha256}" != "${ISO_SHA256}" ]]; then
	echo "note: Microsoft publishes a newer build than the one pinned in config.sh (${ISO_SHA256})"
fi

if ((print_url)); then
	echo "file:   ${file_name}"
	echo "size:   ${size:-unknown} bytes"
	echo "sha256: ${sha256}"
	echo "url:    ${url}"
	exit 0
fi

# 3. Download (resuming a previous partial download), check it, pin the hash.
echo "downloading ${file_name} (${size:-?} bytes) to ${ISO}"
curl --fail --location --progress-bar --continue-at - \
	--user-agent "${user_agent}" --output "${ISO}.part" "${url}"
echo "computing sha256 of ${ISO}.part ..."
actual="$(file_sha256 "${ISO}.part")"
if [[ "${actual}" != "${sha256}" ]]; then
	echo "error: downloaded ISO does not match Microsoft's published sha256" >&2
	echo "  expected ${sha256}" >&2
	echo "  actual   ${actual}" >&2
	echo "removing ${ISO}.part; run the script again" >&2
	rm -f "${ISO}.part"
	exit 1
fi
mv "${ISO}.part" "${ISO}"
echo "saved ${ISO}; checksum OK"
if [[ "${sha256}" != "${ISO_SHA256}" ]]; then
	set_config_sha256 ISO_SHA256 "${sha256}"
fi
