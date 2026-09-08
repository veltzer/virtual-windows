#!/bin/bash -eu
# Shut the Windows VM down cleanly (ACPI power button), or pull the plug.
#
# Usage: ./stop_vm.sh          ask Windows to shut down
#        ./stop_vm.sh --force  kill the VM immediately (like yanking the power)
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

state="$(vm_state)"
if [[ "${state}" == "undefined" ]]; then
	echo "error: VM '${VM_NAME}' does not exist" >&2
	exit 1
fi
if [[ "${state}" != "running" ]]; then
	echo "VM '${VM_NAME}' is not running (state: ${state})"
	exit 0
fi

if [[ "${1:-}" == "--force" ]]; then
	virsh -c "${LIBVIRT_URI}" destroy "${VM_NAME}"
else
	virsh -c "${LIBVIRT_URI}" shutdown "${VM_NAME}"
	echo "shutdown requested; Windows may take a minute. Use --force if it hangs."
fi
