#!/usr/bin/env bash

# system-meta.sh
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
# Kodachi Conky helper script for dashboard/runtime panel data.
# Uses the conky-status gateway where applicable.

set -u
FIELD="${1:-files}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/conky-gateway-common.sh" 2>/dev/null || true
BIN=$(conky_gateway_find_binary 2>/dev/null || true)

sanitize_value() {
    local value="${1:-}"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="$(echo "$value" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    if [[ -z "$value" ]]; then
        echo "N/A"
    else
        echo "$value"
    fi
}

compose_version_with_build() {
    local version=""
    local build=""

    version="$(sanitize_value "${1:-}")"
    build="$(sanitize_value "${2:-}")"
    version="${version#v}"

    if [[ "$version" == "N/A" ]]; then
        echo "N/A"
        return 0
    fi

    # Conky is space-constrained: use the COMPACT dotted form "X.Y.Z.N".
    # Already-dotted (3+ segment) values pass through unchanged.
    if [[ "$version" =~ ^[0-9]+(\.[0-9]+){3,}$ ]]; then
        echo "$version"
        return 0
    fi

    if [[ "$build" =~ ^[0-9]+$ ]] && [[ "$version" =~ ^[0-9]+(\.[0-9]+){2}$ ]]; then
        printf '%s.%s\n' "$version" "$build"
        return 0
    fi

    echo "$version"
}

get_key() {
    local key="$1"
    local default_value="${2:-N/A}"
    if [[ -z "${BIN:-}" ]]; then
        sanitize_value "$default_value"
        return 0
    fi
    sanitize_value "$(conky_gateway_get_or_default "$key" "$default_value" 2 "$BIN")"
}

first_non_na() {
    local value
    for value in "$@"; do
        value="$(sanitize_value "$value")"
        if [[ "$value" != "N/A" ]]; then
            echo "$value"
            return 0
        fi
    done
    echo "N/A"
}

BUILD_META_FILE_CACHE="${BUILD_META_FILE_CACHE:-}"

resolve_build_meta_file() {
    if [[ -n "${BUILD_META_FILE_CACHE:-}" ]] && [[ -f "$BUILD_META_FILE_CACHE" ]]; then
        printf '%s\n' "$BUILD_META_FILE_CACHE"
        return 0
    fi

    local candidates=()
    local candidate=""

    if [[ -n "${KODACHI_BUILD_META_FILE:-}" ]]; then
        candidates+=("$KODACHI_BUILD_META_FILE")
    fi

    candidates+=(
        "/opt/kodachi/dashboard/hooks/config/build-meta.json"
        "$HOME/k900/dashboard/hooks/config/build-meta.json"
        "$HOME/dashboard/hooks/config/build-meta.json"
        "$HOME/Desktop/dashboard/hooks/config/build-meta.json"
        "/usr/share/kodachi/config/build-meta.json"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            BUILD_META_FILE_CACHE="$candidate"
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

build_meta_lookup() {
    local edition="${1:-}"
    local field="${2:-}"
    local meta_file=""

    [[ -n "$edition" && -n "$field" ]] || return 1
    meta_file="$(resolve_build_meta_file)" || return 1

    python3 - "$meta_file" "$edition" "$field" <<'PY'
import json
import sys
from pathlib import Path

meta_path, edition, field = sys.argv[1:4]

try:
    data = json.loads(Path(meta_path).read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(1)

editions = data.get("editions") or {}
entry = editions.get(edition) or {}

def clean(value):
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    text = str(value).strip()
    if not text or text.lower() == "null":
        return ""
    return text

root_version = clean(data.get("version"))
root_build = clean(data.get("build_number"))
root_nightly = clean(data.get("nightly_version"))
entry_build = clean(entry.get("build_number")) or (root_build if edition == "binary_pack" else "")
entry_nightly = clean(entry.get("nightly_version")) or (root_nightly if edition == "binary_pack" else "")

if field == "version":
    value = clean(entry.get("version")) or root_version
elif field == "build_number":
    value = entry_build
elif field == "nightly_version":
    # Conky uses the COMPACT dotted form "<stamp>.<build>" (e.g. 9.8.2.318).
    # entry_nightly already holds "<version>.<build>" from build-meta.json.
    value = entry_nightly
    if not value and root_version and entry_build:
        value = f"{root_version}.{entry_build}"
else:
    value = clean(entry.get(field))

if value:
    print(value)
PY
}

get_build_meta_value() {
    local edition="${1:-}"
    local field="${2:-}"
    sanitize_value "$(build_meta_lookup "$edition" "$field" 2>/dev/null || true)"
}

compose_version_from_keys() {
    local version_key="${1:-}"
    local build_key="${2:-}"

    compose_version_with_build \
        "$(get_key "$version_key" "N/A")" \
        "$(get_key "$build_key" "N/A")"
}

case "$FIELD" in
    files|timezone|resolution|boot|mode|hostname|kernel)
        get_key "system-meta.$FIELD" "N/A"
        ;;
    # Clock sync (On/Off/On*/Off*/?). Tor will not build circuits on a skewed
    # clock, so a privacy HUD should say whether the clock is trusted. A trailing
    # "*" is a reading carried from the previous cycle (detection phase tripped,
    # at most two cycles, then "?"). Added 2026-09-05.
    ntp)
        get_key "system-meta.ntp" "?"
        ;;
    ntp-conky)
        case "$(get_key "system-meta.ntp" "?")" in
            On)     printf '%s\n' '${color1}On' ;;
            Off)    printf '%s\n' '${color6}Off' ;;
            "On*")  printf '%s\n' '${color1}On${color6}*' ;;
            "Off*") printf '%s\n' '${color6}Off*' ;;
            *)      printf '%s\n' '${color3}?' ;;
        esac
        ;;
    binary_cur)
        first_non_na \
            "$(get_build_meta_value "binary_pack" "nightly_version")" \
            "$(compose_version_from_keys "system-meta.binary-cur" "system-meta.binary-nb")" \
            "$(compose_version_from_keys "data.versions.binary.cur" "data.versions.binary.nb")" \
            "$(get_build_meta_value "binary_pack" "version")" \
            "$(get_key "system-meta.binary-cur" "N/A")" \
            "$(get_key "data.versions.binary.cur" "N/A")" \
            "$(get_key "data.health.binary_version" "N/A")" \
            "$(compose_version_from_keys "data.versions.binary.on" "data.versions.binary.nb")" \
            "$(get_key "data.versions.binary.on" "N/A")"
        ;;
    binary_on)
        first_non_na \
            "$(compose_version_with_build "$(get_key "data.online_info.releases.binary_pack.nightly_version" "N/A")" "")" \
            "$(compose_version_from_keys "system-meta.binary-on" "system-meta.binary-nb")" \
            "$(compose_version_from_keys "data.versions.binary.on" "data.versions.binary.nb")" \
            "$(get_key "system-meta.binary-on" "N/A")" \
            "$(get_key "data.versions.binary.on" "N/A")"
        ;;
    binary_nb)
        first_non_na \
            "$(get_build_meta_value "binary_pack" "build_number")" \
            "$(get_key "system-meta.binary-nb" "N/A")" \
            "$(get_key "data.versions.binary.nb" "N/A")"
        ;;
    terminal_cur)
        first_non_na \
            "$(get_build_meta_value "terminal" "nightly_version")" \
            "$(compose_version_from_keys "system-meta.terminal-cur" "system-meta.terminal-nb")" \
            "$(compose_version_from_keys "data.versions.terminal.cur" "data.versions.terminal.nb")" \
            "$(get_build_meta_value "terminal" "version")" \
            "$(get_key "system-meta.terminal-cur" "N/A")" \
            "$(get_key "data.versions.terminal.cur" "N/A")" \
            "$(get_key "data.health.binary_version" "N/A")" \
            "$(compose_version_from_keys "data.versions.terminal.on" "data.versions.terminal.nb")" \
            "$(get_key "data.versions.terminal.on" "N/A")"
        ;;
    terminal_on)
        first_non_na \
            "$(compose_version_with_build "$(get_key "data.online_info.releases.terminal.nightly_version" "N/A")" "")" \
            "$(compose_version_from_keys "system-meta.terminal-on" "system-meta.terminal-nb")" \
            "$(compose_version_from_keys "data.versions.terminal.on" "data.versions.terminal.nb")" \
            "$(get_key "system-meta.terminal-on" "N/A")" \
            "$(get_key "data.versions.terminal.on" "N/A")"
        ;;
    terminal_nb)
        first_non_na \
            "$(get_build_meta_value "terminal" "build_number")" \
            "$(get_key "system-meta.terminal-nb" "N/A")" \
            "$(get_key "data.versions.terminal.nb" "N/A")"
        ;;
    desktop_cur)
        first_non_na \
            "$(get_build_meta_value "desktop" "nightly_version")" \
            "$(compose_version_from_keys "system-meta.desktop-cur" "system-meta.desktop-nb")" \
            "$(compose_version_from_keys "data.versions.desktop.cur" "data.versions.desktop.nb")" \
            "$(get_build_meta_value "desktop" "version")" \
            "$(get_key "system-meta.desktop-cur" "N/A")" \
            "$(get_key "data.versions.desktop.cur" "N/A")" \
            "$(get_key "data.health.binary_version" "N/A")" \
            "$(compose_version_from_keys "data.versions.desktop.on" "data.versions.desktop.nb")" \
            "$(get_key "data.versions.desktop.on" "N/A")"
        ;;
    desktop_on)
        first_non_na \
            "$(compose_version_with_build "$(get_key "data.online_info.releases.desktop.nightly_version" "N/A")" "")" \
            "$(compose_version_from_keys "system-meta.desktop-on" "system-meta.desktop-nb")" \
            "$(compose_version_from_keys "data.versions.desktop.on" "data.versions.desktop.nb")" \
            "$(get_key "system-meta.desktop-on" "N/A")" \
            "$(get_key "data.versions.desktop.on" "N/A")"
        ;;
    desktop_nb)
        first_non_na \
            "$(get_build_meta_value "desktop" "build_number")" \
            "$(get_key "system-meta.desktop-nb" "N/A")" \
            "$(get_key "data.versions.desktop.nb" "N/A")"
        ;;
    *)
        echo "N/A"
        ;;
esac
