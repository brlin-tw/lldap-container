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
    # For creating file backups
    cp

    # For generating random secrets
    head
    tr

    # For validating user-specified FQDN
    idn

    # For generating self-signed certificate for testing
    openssl

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

print_random(){
    LC_ALL=C tr -dc 'A-Za-z0-9!#%&()*+,-./:;<=>?@[\]^_{|}~' </dev/urandom | head -c 32
}

# Check whether the supplied FQDN is valid
is_valid_fqdn(){
    local fqdn="${1}"; shift

    # Convert to ASCII-compatible encoding (ACE) using idn for IDN support
    local ace_fqdn
    if ! ace_fqdn="$(
        idn \
            --quiet \
            --idna-to-ascii \
            "${fqdn}" \
            2>/dev/null
        )"; then
        printf \
            '%s: Error: Unable to convert user-specified domain name(%s) to ASCII-compatible encoding(ACE).\n' \
            "${FUNCNAME[0]}" \
            "${fqdn}" \
            1>&2
        return 2
    fi

    local regex_fqdn='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9-]{2,}$'
    if ! [[ "${ace_fqdn}" =~ ${regex_fqdn} ]]; then
        return 1
    fi
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

while true; do
    read -r -p 'Do you want to enable LDAPS? (Y/n) ' response
    case "${response}" in
        ""|[Yy]*) enable_ldaps=true; break;;
        [Nn]*) enable_ldaps=false; break;;
        * ) printf 'Please answer Y or N.\n' 1>&2;;
    esac
done

if test "${enable_ldaps}" = true; then
    while true; do
        read -r -p 'Please enter the FQDN of the LLDAP service: [lldap.example.com] ' fqdn

        if test -z "${fqdn}"; then
            fqdn=lldap.example.com
            printf \
                'Info: Using "%s" as the FQDN of the LLDAP service.\n' \
                "${fqdn}"
            break
        fi

        if ! is_valid_fqdn "${fqdn}"; then
            printf \
                'Error: "%s" is not a valid FQDN. Please try again.\n' \
                "${fqdn}" \
                1>&2
            continue
        fi
        break
    done

    ssl_dir="${script_dir}/ssl"
    cert="${ssl_dir}/${fqdn}.crt"
    key="${ssl_dir}/${fqdn}.key"

    if ! test -e "${cert}"; then
        while true; do
            read -r -p 'Please enter the valid days of the newly-generated TLS certificate [30]: ' cert_valid_days

            if test -z "${cert_valid_days}"; then
                cert_valid_days=30
                printf \
                    'Info: Using "%s" as the valid days of the newly-generated TLS certificate.\n' \
                    "${cert_valid_days}"
                break
            fi

            regex_positive_integers='^[1-9][0-9]*$'
            if ! [[ "${cert_valid_days}" =~ ${regex_positive_integers} ]]; then
                printf \
                    'Error: "%s" is not a valid input.  Please try again.\n' \
                    "${cert_valid_days}" \
                    1>&2
                continue
            fi

            break
        done

        if ! test -e "${key}"; then
            printf \
                'Info: Generating a private key for testing...\n'
            openssl_genpkey_opts=(
                -algorithm EC
                -pkeyopt ec_paramgen_curve:P-256
                -out "${key}"
            )
            if ! openssl genpkey "${openssl_genpkey_opts[@]}"; then
                printf \
                    'Error: Unable to generate a private key for testing.\n' \
                    1>&2
                exit 2
            fi
        fi

        printf \
            'Info: Issuing a self-signed TLS certificate for testing...\n'
        openssl_req_opts=(
            -new

            # Directly generate a X.509 certificate without using CSR
            -x509

            -days "${cert_valid_days}"
            -key "${key}"
            -out "${cert}"

            -subj "/CN=${fqdn}"
            -addext "subjectAltName = DNS:${fqdn}"
            -utf8
        )
        if ! openssl req "${openssl_req_opts[@]}"; then
            printf \
                'Error: Unable to issue a self-signed TLS certificate for testing.\n' \
                1>&2
            exit 2
        fi
    fi
fi

sed_opts=(
    --regexp-extended

    # NOTE: SPACE is used as the separator of the s sed command
    -e "s __LLDAP_JWT_SECRET__ ${lldap_jwt_secret} "
    -e "s __LLDAP_KEY_SEED__ ${lldap_key_seed} "
)

if test "${enable_ldaps}" = true; then
    sed_opts+=(
        -e 's/^#LLDAP_LDAPS_OPTIONS__ENABLED=.*/LLDAP_LDAPS_OPTIONS__ENABLED=true/'
        -e "s|^#LLDAP_LDAPS_OPTIONS__CERT_FILE=.*|LLDAP_LDAPS_OPTIONS__CERT_FILE=/ssl/${fqdn}.crt|"
        -e "s|^#LLDAP_LDAPS_OPTIONS__KEY_FILE=.*|LLDAP_LDAPS_OPTIONS__KEY_FILE=/ssl/${fqdn}.key|"
        -e 's/#- "6360:6360"/- "6360:6360"/'
    )
fi

templates=(
    .env.template
    compose.yml.template
)
for template in "${templates[@]}"; do
    file="${script_dir}/${template%.template}"

    if test -e "${file}"; then
        backup_file="${file}.backup-${operation_timestamp}"
        printf \
            'Info: Backing up existing "%s" file to "%s"...\n' \
            "${file}" \
            "${backup_file}"
        if ! cp -a "${file}" "${backup_file}"; then
            printf \
                'Error: Unable to back up existing "%s" file.\n' \
                "${file}" \
                >&2
            exit 1
        fi
    fi

    if ! sed "${sed_opts[@]}" "${template}" >"${file}"; then
        printf \
            'Error: Unable to generate "%s" file from template.\n' \
            "${file}" \
            >&2
        exit 1
    fi
done

printf 'Operation completed successfully.\n'
