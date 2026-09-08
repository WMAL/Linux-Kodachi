#!/usr/bin/env bash

# Kodachi Conky Script - Security Status Checks
# ===========================================================
#
# SPDX-License-Identifier: LicenseRef-Kodachi-SAN-1.1
# Copyright (c) 2013-2026 Warith Al Maawali
#
# This file is part of Kodachi OS.
# For full license terms, see LICENSE.md or visit:
# https://kodachi.cloud/docs/license.html
#
# Commercial or organizational use requires a written license.
# Contact: warith@digi77.com
#
# Author: Warith Al Maawali
# Version: 9.0.1
# Last updated: 2026-03-02
#
# Description:
# Returns security gauges state through the conky-status gateway only.
# Output format is binary for Conky gauges: 1=active, 0=inactive.
#
# Usage:
#   security-status.sh auth
#   security-status.sh vpn
#   security-status.sh torrified
#   security-status.sh dns
#   security-status.sh all

set -u

FIELD="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/conky-gateway-common.sh" 2>/dev/null || true
BIN=$(conky_gateway_find_binary 2>/dev/null || true)

to_bin() {
    local key="$1"
    if [[ -z "$BIN" ]]; then
        echo "0"
        return
    fi
    local raw
    raw=$(conky_gateway_get_or_default "$key" "false" 2 "$BIN")
    conky_gateway_bool_01 "$raw"
}

AUTH="$(to_bin security-status.auth)"
VPN="$(to_bin security-status.vpn)"
TORRIFIED="$(to_bin security-status.torrified)"
DNS="$(to_bin security-status.dns)"

case "$FIELD" in
    auth)
        echo "$AUTH"
        ;;
    vpn)
        echo "$VPN"
        ;;
    torrified)
        echo "$TORRIFIED"
        ;;
    dns)
        echo "$DNS"
        ;;
    all)
        echo "$AUTH $VPN $TORRIFIED $DNS"
        ;;
    *)
        echo "0"
        ;;
esac
