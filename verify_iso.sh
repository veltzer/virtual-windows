#!/bin/bash -eu
# Check the Windows ISO and the VirtIO driver ISO against the SHA-256 values
# pinned in config.sh. Takes a while: the Windows ISO alone is ~7 GB.
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

failed=0
check() {
	local label="$1" file="$2" expected="$3" actual
	if [[ ! -f "${file}" ]]; then
		echo "error: ${label} not found: ${file}" >&2
		failed=1
		return
	fi
	echo "computing sha256 of ${file} ..."
	actual="$(file_sha256 "${file}")"
	if [[ "${actual}" != "${expected}" ]]; then
		echo "error: ${label} checksum mismatch" >&2
		echo "  expected ${expected}" >&2
		echo "  actual   ${actual}" >&2
		failed=1
		return
	fi
	echo "${label} checksum OK"
}

check "Windows ISO" "${ISO}" "${ISO_SHA256}"
check "VirtIO ISO" "${VIRTIO_ISO}" "${VIRTIO_ISO_SHA256}"
if ((failed)); then
	echo "delete the failing file and download it again (./download_iso.sh, ./download_virtio.sh)" >&2
	exit 1
fi
