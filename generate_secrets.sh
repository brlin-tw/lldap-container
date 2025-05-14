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

/bin/echo -n "LLDAP_JWT_SECRET='"
print_random
echo "'"
/bin/echo -n "LLDAP_KEY_SEED='"
print_random
echo "'"
