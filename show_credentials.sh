#!/bin/bash -eu
# Print the Windows account details kept in pass(1), for typing into the
# Windows setup wizard (local account + security questions) and the login
# screen. Nothing is stored in this directory.
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

show() {
	local label="$1" entry="$2"
	printf '%-28s %s\n' "${label}:" "$(pass show "${PASS_PREFIX}/${entry}")"
}

show "user" user
show "password" password
show "first pet's name" security/first-pet-name
show "first school's name" security/first-school-name
show "childhood nickname" security/childhood-nickname
