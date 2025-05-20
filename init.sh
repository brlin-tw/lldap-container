#!/usr/bin/env bash
# Initialize the LLDAP service with robust configuration.
#
# Copyright 2024 The LLDAP Project contributors <https://github.com/lldap/lldap/commits/83508a3/generate_secrets.sh>
# Copyright 2025 林博仁(Buo-ren Lin) <buo.ren.lin@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is derived from the original script by the LLDAP project:
# https://github.com/lldap/lldap/blob/83508a3/generate_secrets.sh

printf \
    'Info: Configuring the defensive interpreter behaviors...\n'
set_opts=(
    # Terminate script execution when an unhandled error occurs
    -o errexit
    -o errtrace

    # Terminate script execution when an unset parameter variable is
    # referenced
    -o nounset
)
if ! set "${set_opts[@]}"; then
    printf \
        'Error: Unable to configure the defensive interpreter behaviors.\n' \
        1>&2
    exit 1
fi

printf \
    'Info: Checking the existence of the required commands...\n'
required_commands=(
    # For generating random secrets
    head
    tr

    realpath

    # For generating environment file from template
    sed
)
flag_required_command_check_failed=false
for command in "${required_commands[@]}"; do
    if ! command -v "${command}" >/dev/null; then
        flag_required_command_check_failed=true
        printf \
            'Error: This program requires the "%s" command to be available in your command search PATHs.\n' \
            "${command}" \
            1>&2
    fi
done
if test "${flag_required_command_check_failed}" == true; then
    printf \
        'Error: Required command check failed, please check your installation.\n' \
        1>&2
    exit 1
fi

printf \
    'Info: Configuring the convenience variables...\n'
if test -v BASH_SOURCE; then
    # Convenience variables may not need to be referenced
    # shellcheck disable=SC2034
    {
        printf \
            'Info: Determining the absolute path of the program...\n'
        if ! script="$(
            realpath \
                --strip \
                "${BASH_SOURCE[0]}"
            )"; then
            printf \
                'Error: Unable to determine the absolute path of the program.\n' \
                1>&2
            exit 1
        fi
        script_dir="${script%/*}"
        script_filename="${script##*/}"
        script_name="${script_filename%%.*}"
    }
fi
# Convenience variables may not need to be referenced
# shellcheck disable=SC2034
{
    script_basecommand="${0}"
    script_args=("${@}")
}

printf \
    'Info: Setting the ERR trap...\n'
trap_err(){
    printf \
        'Error: The program prematurely terminated due to an unhandled error.\n' \
        1>&2
    exit 99
}
if ! trap trap_err ERR; then
    printf \
        'Error: Unable to set the ERR trap.\n' \
        1>&2
    exit 1
fi

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

sed_opts=(
    --in-place=".backup-${operation_timestamp}"

    # NOTE: SPACE is used as the separator of the s sed command
    -e "s __LLDAP_JWT_SECRET__ ${lldap_jwt_secret} "
    -e "s __LLDAP_KEY_SEED__ ${lldap_key_seed} "
)
if ! sed "${sed_opts[@]}" .env.template >.env; then
    printf 'Error: Unable to generate .env file from template.\n' >&2
    exit 1
fi

printf 'Operation completed successfully.\n'
