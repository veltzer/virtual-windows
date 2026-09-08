#!/bin/bash -eu
# Fetch the VirtIO guest driver ISO and check it. Required: create_vm.sh and
# start_vm.sh refuse to run without it. Once installed inside Windows it
# provides faster disk and network drivers, the QEMU guest agent and the
# SPICE guest tools.
#
# The download site publishes no checksum for the ISO itself, but the RPM in
# the same directory packages the identical file and its header records the
# file's SHA-256. The first megabyte of the RPM holds the whole header, so
# that is all that gets fetched (see rpm_file_sha256.py).
#
# Usage: ./download_virtio.sh          download unless already present
#        ./download_virtio.sh --force  download even if the ISO already exists
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

force=0
case "${1:-}" in
"") ;;
--force) force=1 ;;
*)
	echo "usage: $0 [--force]" >&2
	exit 2
	;;
esac

if ((!force)) && [[ -f "${VIRTIO_ISO}" ]]; then
	echo "already present: ${VIRTIO_ISO} (use --force to download again, ./verify_iso.sh to check it)"
	exit 0
fi

rpm_head="$(mktemp)"
trap 'rm -f "${rpm_head}"' EXIT
echo "fetching the RPM header from ${VIRTIO_RPM_URL}"
curl --fail --location --silent --show-error --range 0-1048575 --output "${rpm_head}" "${VIRTIO_RPM_URL}"
published="$(python3 "${VM_DIR}/rpm_file_sha256.py" "${rpm_head}" .iso)"
echo "published sha256 ${published}"
if [[ "${published}" != "${VIRTIO_ISO_SHA256}" ]]; then
	echo "note: a newer VirtIO release than the one pinned in config.sh is available; pinning it after the download"
fi

echo "downloading ${VIRTIO_ISO_URL}"
curl --fail --location --progress-bar --continue-at - --output "${VIRTIO_ISO}.part" "${VIRTIO_ISO_URL}"
actual="$(file_sha256 "${VIRTIO_ISO}.part")"
if [[ "${actual}" != "${published}" ]]; then
	echo "error: downloaded ISO does not match the published sha256" >&2
	echo "  expected ${published}" >&2
	echo "  actual   ${actual}" >&2
	echo "removing ${VIRTIO_ISO}.part; run the script again" >&2
	rm -f "${VIRTIO_ISO}.part"
	exit 1
fi
mv "${VIRTIO_ISO}.part" "${VIRTIO_ISO}"
echo "saved ${VIRTIO_ISO}; checksum OK"
if [[ "${published}" != "${VIRTIO_ISO_SHA256}" ]]; then
	set_config_sha256 VIRTIO_ISO_SHA256 "${published}"
fi
