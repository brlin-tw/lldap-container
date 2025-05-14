#!/usr/bin/env bash
# This script generates random secrets for the LLDAP service.
#
# Copyright 2024 The LLDAP Project contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is derived from the original script by the LLDAP project:
# https://github.com/lldap/lldap/blob/83508a3/generate_secrets.sh

print_random () {
    LC_ALL=C tr -dc 'A-Za-z0-9!#%&()*+,-./:;<=>?@[\]^_{|}~' </dev/urandom | head -c 32
}

operation_timestamp="$(printf '%(%Y%m%d-%H%M%S)T\n')"

if ! lldap_jwt_secret="$(print_random)"; then
    printf 'Error: Unable to generate random string for LLDAP_JWT_SECRET.\n' >&2
    exit 1
fi

if ! lldap_key_seed="$(print_random)"; then
    printf 'Error: Unable to generate random string for LLDAP_KEY_SEED.\n' >&2
    exit 1
fi

if test -e .env; then
    backup_file=".env.backup-${operation_timestamp}"
    printf \
        'Info: Backing up existing .env file to "%s"...\n' \
        "${backup_file}"
    if ! cp -a .env "${backup_file}"; then
        printf 'Error: Unable to back up existing .env file.\n' >&2
        exit 1
    fi
fi

sed_opts=(
    # NOTE: SPACE is used as the separator of the s sed command
    -e "s __LLDAP_JWT_SECRET__ ${lldap_jwt_secret} "
    -e "s __LLDAP_KEY_SEED__ ${lldap_key_seed} "
)
if ! sed "${sed_opts[@]}" .env.template >.env; then
    printf 'Error: Unable to generate .env file from template.\n' >&2
    exit 1
fi

printf 'Operation completed successfully.\n'
