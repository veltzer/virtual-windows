#!/bin/bash -eu
# Define the Windows VM with virt-install and boot it from the install ISO.
#
# Windows 11 refuses to install without UEFI Secure Boot and a TPM 2.0, so the
# VM gets OVMF secure-boot firmware and an emulated (swtpm) TPM. The install
# ISO and the VirtIO driver ISO (mandatory, see download_virtio.sh) are
# attached read-only with <seclabel model='dac' relabel='no'/> so libvirt does
# not chown them to libvirt-qemu on every boot (see start_vm.sh for the story).
#
# Usage: ./create_vm.sh            create the VM, then open its console
#        ./create_vm.sh --dry-run  only print the domain XML virt-install would use
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

if [[ ! -f "${ISO}" ]]; then
	echo "error: ISO not found: ${ISO} (see README.md for how to download it)" >&2
	exit 1
fi
require_virtio_iso
if ((!dry_run)) && vm_exists; then
	echo "error: VM '${VM_NAME}' already exists (state: $(vm_state)); run ./delete_vm.sh first" >&2
	exit 1
fi

# shellcheck disable=SC2054  # commas are virt-install suboption separators inside quoted strings
args=(
	--connect "${LIBVIRT_URI}"
	--name "${VM_NAME}"
	--osinfo win11
	--memory "${VM_MEMORY_MB}"
	--vcpus "${VM_VCPUS}"
	--cpu host-passthrough
	--machine q35
	--boot "firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no,bootmenu.enable=yes"
	--tpm "model=tpm-tis,backend.type=emulator,backend.version=2.0"
	--disk "path=${VM_DISK},size=${VM_DISK_GB},format=qcow2,bus=sata,driver.discard=unmap,boot.order=1"
	--disk "path=${ISO},device=cdrom,bus=sata,readonly=on,source.seclabel0.model=dac,source.seclabel0.relabel=no"
	--disk "path=${VIRTIO_ISO},device=cdrom,bus=sata,readonly=on,source.seclabel0.model=dac,source.seclabel0.relabel=no"
	--network network=default,model=e1000e
	--graphics spice
	--video vga
	--sound ich9
	--noautoconsole
)
if ((dry_run)); then
	sys_python virt-install "${args[@]}" --dry-run --print-xml --check path_in_use=off
	exit 0
fi

echo "creating VM '${VM_NAME}': ${VM_MEMORY_MB} MB RAM, ${VM_VCPUS} vCPUs, ${VM_DISK_GB} GB disk at ${VM_DISK}"
sys_python virt-install "${args[@]}"

echo
echo "VM created and booting from the ISO. Windows setup is interactive; see README.md."
echo "Account details for the setup wizard: ./show_credentials.sh"
exec "${VM_DIR}/start_vm.sh"
