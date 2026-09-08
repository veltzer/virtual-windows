#!/bin/bash -eu
# Remove the Windows VM and its disk so create_vm.sh can start from scratch.
# The install ISO and the VirtIO ISO are never touched.
#
# Usage: ./delete_vm.sh        ask for confirmation, then delete
#        ./delete_vm.sh --yes  delete without asking
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

if ! vm_exists; then
	echo "VM '${VM_NAME}' does not exist; nothing to do"
	exit 0
fi

echo "This deletes VM '${VM_NAME}' and its disk ${VM_DISK} (everything installed in Windows is lost)."
if [[ "${1:-}" != "--yes" ]]; then
	read -r -p "Type the VM name to confirm: " answer
	if [[ "${answer}" != "${VM_NAME}" ]]; then
		echo "aborted"
		exit 1
	fi
fi

if [[ "$(vm_state)" == "running" ]]; then
	virsh -c "${LIBVIRT_URI}" destroy "${VM_NAME}"
fi
# --nvram drops the UEFI variable store, --tpm the swtpm state; both are
# created per VM and useless without it.
virsh -c "${LIBVIRT_URI}" undefine "${VM_NAME}" --nvram --tpm
if [[ -e "${VM_DISK}" ]]; then
	virsh -c "${LIBVIRT_URI}" vol-delete "${VM_DISK}"
fi
echo "VM '${VM_NAME}' deleted"
