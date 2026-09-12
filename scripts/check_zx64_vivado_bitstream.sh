#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${ZX64_VIVADO_BITSTREAM_BUILD_DIR:-$repo_dir/build/vivado_hw_rv64}"
skip_build="${ZX64_VIVADO_BITSTREAM_SKIP_BUILD:-0}"

bit="$build_dir/zynq_cpu_hw.runs/impl_1/zynq_cpu_system_wrapper.bit"
xsa="$build_dir/zynq_cpu_system_wrapper.xsa"
timing="$build_dir/reports/zynq_cpu_system_timing_summary.rpt"
util="$build_dir/reports/zynq_cpu_system_utilization.rpt"
opt_hier_util="$build_dir/reports/zynq_cpu_system_utilization_opt_hier.rpt"
impl_dir="$build_dir/zynq_cpu_hw.runs/impl_1"
impl_log="$impl_dir/runme.log"
impl_drc="$impl_dir/zynq_cpu_system_wrapper_drc_opted.rpt"

fail() {
    echo "ZX64 Vivado bitstream check failed: $*" >&2
    exit 1
}

is_resource_overutilization() {
    grep -qiE 'UTLZ-|over-utili[sz]ed|Resource utilization' \
        "$impl_log" "$impl_drc" 2>/dev/null
}

print_lut_summary_from_report() {
    local report="$1"
    [[ -s "$report" ]] || return 1

    awk -F'|' '
        function trim(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            return s
        }
        function clean(s) {
            s = trim(s)
            gsub(/,/, "", s)
            return s
        }
        function pct(s) {
            s = clean(s)
            if (s != "" && s !~ /%$/) {
                s = s "%"
            }
            return s
        }
        function emit(label, used, avail, util) {
            printf "  %-14s used=%s", label ":", used
            if (avail != "") {
                printf " available=%s", avail
            }
            if (util != "") {
                printf " util=%s", pct(util)
            }
            printf "\n"
        }
        {
            name = trim($2)
            gsub(/\*/, "", name)
            name = trim(name)
            if ((name == "Slice LUTs" || name == "LUT as Logic" || name == "LUT as Memory") && !(name in seen)) {
                seen[name] = 1
                emit(name, clean($3), clean($6), clean($7))
            }
        }
        END {
            if (!seen["Slice LUTs"] && !seen["LUT as Logic"] && !seen["LUT as Memory"]) {
                exit 1
            }
        }
    ' "$report"
}

select_largest_synth_util_report() {
    local report
    local used
    local best_report=""
    local best_used=-1
    local reports=()

    shopt -s nullglob
    reports=("$build_dir"/zynq_cpu_hw.runs/*/*utilization*_synth.rpt)
    shopt -u nullglob

    for report in "${reports[@]}"; do
        [[ -s "$report" ]] || continue
        used="$(
            awk -F'|' '
                function trim(s) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
                    return s
                }
                {
                    name = trim($2)
                    gsub(/\*/, "", name)
                    name = trim(name)
                    if (name == "Slice LUTs") {
                        used = trim($3)
                        gsub(/,/, "", used)
                        print used
                        exit
                    }
                }
            ' "$report"
        )"
        [[ "$used" =~ ^[0-9]+$ ]] || continue
        if (( used > best_used )); then
            best_used="$used"
            best_report="$report"
        fi
    done

    [[ -n "$best_report" ]] || return 1
    printf '%s\n' "$best_report"
}

print_resource_error_summary() {
    local line=""
    local resource="LUT resources"
    local required=""
    local available=""
    local over_by=""

    line="$(grep -h -m1 -E 'over-utili[sz]ed.*requires [0-9]+|requires [0-9]+.*available|UTLZ-.*requires' \
        "$impl_log" "$impl_drc" 2>/dev/null || true)"
    if [[ -z "$line" ]]; then
        line="$(grep -h -m1 -E 'UTLZ-|over-utili[sz]ed|Resource utilization' \
            "$impl_log" "$impl_drc" 2>/dev/null || true)"
    fi

    if [[ "$line" =~ ([[:alnum:]][[:alnum:][:space:]_-]*)[[:space:]]+over-utili[sz]ed ]]; then
        resource="${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ requires[[:space:]]+([0-9]+)[[:space:]]+of[[:space:]]+such[[:space:]]+cell[[:space:]]+types[[:space:]]+but[[:space:]]+only[[:space:]]+([0-9]+) ]]; then
        required="${BASH_REMATCH[1]}"
        available="${BASH_REMATCH[2]}"
        over_by=$((required - available))
    fi

    if [[ -n "$required" && -n "$available" ]]; then
        echo "  Vivado DRC: $resource required=$required available=$available over_by=$over_by" >&2
    elif [[ -n "$line" ]]; then
        echo "  Vivado DRC: $line" >&2
    fi
}

print_vivado_failure_context() {
    local report=""

    is_resource_overutilization || return 0

    echo "Vivado resource over-utilization summary:" >&2
    print_resource_error_summary

    if [[ -s "$opt_hier_util" ]]; then
        report="$opt_hier_util"
    elif [[ -s "$util" && ( ! -e "$impl_log" || "$util" -nt "$impl_log" ) ]]; then
        report="$util"
    else
        report="$(select_largest_synth_util_report || true)"
        [[ -n "$report" ]] || report="$util"
    fi

    if [[ -n "$report" && -s "$report" ]]; then
        echo "  utilization report: $report" >&2
        print_lut_summary_from_report "$report" >&2 || true
    fi
    [[ -s "$impl_drc" ]] && echo "  DRC report: $impl_drc" >&2
    [[ -s "$impl_log" ]] && echo "  implementation log: $impl_log" >&2
}

if [[ "$skip_build" != "1" ]]; then
    mkdir -p "$build_dir"
    if ! (
        cd "$repo_dir"
        ZYNQ_CPU_SOC=rv64 \
        ZYNQ_CPU_VIVADO_BUILD_DIR="$build_dir" \
            ./scripts/run_vivado.sh -mode batch -source vivado/build_hw_bringup.tcl
    ); then
        print_vivado_failure_context
        fail "Vivado build failed; see $impl_log"
    fi
fi

if is_resource_overutilization &&
    [[ ! -s "$bit" ||
        ( -e "$impl_log" && "$impl_log" -nt "$bit" ) ||
        ( -e "$impl_drc" && "$impl_drc" -nt "$bit" ) ]]; then
    print_vivado_failure_context
    fail "implementation resource over-utilization; see $impl_log"
fi

[[ -s "$bit" ]] || { print_vivado_failure_context; fail "missing bitstream: $bit"; }
[[ -s "$xsa" ]] || fail "missing XSA: $xsa"
[[ -s "$timing" ]] || fail "missing timing report: $timing"
[[ -s "$util" ]] || fail "missing utilization report: $util"

setup_line="$(grep -m1 -E '^Setup[[:space:]]*:' "$timing" || true)"
[[ -n "$setup_line" ]] || fail "timing report has no setup summary"

setup_failing="$(sed -E 's/^Setup[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]+Failing Endpoints.*/\1/' <<<"$setup_line")"
wns="$(sed -E 's/.*Worst Slack[[:space:]]+([-0-9.]+)ns.*/\1/' <<<"$setup_line")"

[[ "$setup_failing" =~ ^[0-9]+$ ]] || fail "cannot parse setup failing endpoints from: $setup_line"
[[ "$wns" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || fail "cannot parse WNS from: $setup_line"

(( setup_failing == 0 )) || fail "setup timing has $setup_failing failing endpoints"
awk -v wns="$wns" 'BEGIN { exit !(wns >= 0.0) }' || fail "setup WNS is negative: ${wns}ns"

echo "ZX64 Vivado bitstream: PASS"
echo "  build:  $build_dir"
echo "  bit:    $bit ($(stat -c '%s' "$bit") bytes)"
echo "  xsa:    $xsa ($(stat -c '%s' "$xsa") bytes)"
echo "  timing: setup_failing=$setup_failing WNS=${wns}ns"
