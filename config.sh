#!/bin/bash
# Shared settings for the Windows VM scripts. Sourced, never executed.
#
# Every value can be overridden from the environment, e.g.
#     VM_NAME=win11-test ./create_vm.sh --dry-run
# Edit the defaults here to change the VM permanently.

# Directory holding these scripts and the install ISO.
VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# libvirt system instance: QEMU runs as libvirt-qemu, images live under
# /var/lib/libvirt/images and the VM survives logout.
LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"

VM_NAME="${VM_NAME:-win11}"
VM_MEMORY_MB="${VM_MEMORY_MB:-8192}"
VM_VCPUS="${VM_VCPUS:-4}"
VM_DISK_GB="${VM_DISK_GB:-128}"
VM_DISK="${VM_DISK:-/var/lib/libvirt/images/${VM_NAME}.qcow2}"

# Windows install media: the Windows 11 Enterprise evaluation ISO from the
# Microsoft Evaluation Center (90-day evaluation, no product key needed).
# download_iso.sh resolves the fwlink, downloads the ISO to ${ISO} and writes
# the SHA-256 from Microsoft's hash PDF into the checksum file; verify_iso.sh
# checks the ISO against it.
ISO_EVAL_PAGE="${ISO_EVAL_PAGE:-https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise}"
# Language code as it appears at the end of the ISO file name.
ISO_LANGUAGE="${ISO_LANGUAGE:-en-us}"
# go.microsoft.com/fwlink id of the "64-bit edition" link for that language on
# the Evaluation Center page (2334167 = Windows 11 Enterprise 25H2, English US).
ISO_FWLINK="${ISO_FWLINK:-2334167}"
# fwlink id of Windows11EnterpriseHashValues.pdf and the row label in it.
ISO_HASH_PDF_FWLINK="${ISO_HASH_PDF_FWLINK:-2334901}"
ISO_HASH_LABEL="${ISO_HASH_LABEL:-Enterprise Eval x64 Eval ${ISO_LANGUAGE^^} DVD9}"
ISO="${ISO:-${VM_DIR}/Win11_Enterprise_Eval_x64_${ISO_LANGUAGE}.iso}"
# Expected SHA-256 of the ISO, from Microsoft's hash PDF. download_iso.sh
# updates this line when it fetches a newer build; verify_iso.sh checks it.
ISO_SHA256="${ISO_SHA256:-a61adeab895ef5a4db436e0a7011c92a2ff17bb0357f58b13bbc4062e535e7b9}"

# VirtIO guest driver ISO (see download_virtio.sh). Required: it is attached
# as a second cdrom so the drivers, guest agent and SPICE tools can be
# installed inside Windows, and the VM will not be created or started without it.
VIRTIO_ISO="${VIRTIO_ISO:-${VM_DIR}/virtio-win.iso}"
VIRTIO_ISO_URL="${VIRTIO_ISO_URL:-https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso}"
# The RPM next to the ISO packages the same file; its header records the
# ISO's SHA-256 (the CHECKSUM file there only covers the RPMs themselves).
VIRTIO_RPM_URL="${VIRTIO_RPM_URL:-https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.noarch.rpm}"
# Expected SHA-256 of the VirtIO ISO. download_virtio.sh updates this line
# when it fetches a newer release; verify_iso.sh checks it.
VIRTIO_ISO_SHA256="${VIRTIO_ISO_SHA256:-303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d}"

# pass(1) entries holding the Windows account details (see show_credentials.sh).
PASS_PREFIX="${PASS_PREFIX:-vms/windows}"

# virt-manager and virt-install start with `#!/usr/bin/env python3`, so when a
# venv (e.g. ~/.venv) is first on PATH they run under that interpreter and die
# with "No module named 'gi'". Run them under the system python explicitly.
sys_python() {
    local tool="$1"
    shift
    /usr/bin/python3 "$(command -v "${tool}")" "$@"
}

# Refuse to go on without the VirtIO driver ISO.
require_virtio_iso() {
    if [[ ! -f "${VIRTIO_ISO}" ]]; then
        echo "error: VirtIO driver ISO not found: ${VIRTIO_ISO}; run ./download_virtio.sh first" >&2
        exit 1
    fi
}

# Pin a new SHA-256 in config.sh: set_config_sha256 ISO_SHA256 <hex>
set_config_sha256() {
    local var="$1" sha="$2"
    sed -i -E "s|^(${var}=\"\\$\{${var}:-)[0-9a-f]{64}(\}\")|\1${sha}\2|" "${VM_DIR}/config.sh"
    if ! grep -qE "^${var}=\"\\$\{${var}:-${sha}\}\"" "${VM_DIR}/config.sh"; then
        echo "error: failed to update ${var} in ${VM_DIR}/config.sh; set it to ${sha} by hand" >&2
        return 1
    fi
    echo "updated ${var} in config.sh to ${sha}"
}

# sha256 of a file, hex only.
file_sha256() {
    sha256sum "$1" | cut -d' ' -f1
}

vm_exists() {
    virsh -c "${LIBVIRT_URI}" dominfo "${VM_NAME}" >/dev/null 2>&1
}

vm_state() {
    local state
    # virsh prints an empty line before failing on an unknown domain, so test
    # both the exit status and the output.
    if state="$(virsh -c "${LIBVIRT_URI}" domstate "${VM_NAME}" 2>/dev/null)" && [[ -n "${state}" ]]; then
        echo "${state}"
    else
        echo "undefined"
    fi
}
