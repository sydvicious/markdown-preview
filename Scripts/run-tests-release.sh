#!/bin/bash
#
# Copyright ©2026 Syd Polk. All Rights Reserved.
# SPDX-License-Identifier: BSD-3-Clause
#
# **Runs every test, on everything the app is released for.** This is the run
# made once before a release:
#
#   scripts      the tests for the preview's scripts in MarkdownPreview/Web,
#                with `npm test`, under Node;
#   arm64        the whole MarkdownPreview scheme on this Mac: the engine's
#                tests, the app's, and the ones that use the window server;
#   x86_64       the same, built for x86_64 and run under Rosetta;
#   simulators   the same again on each simulator: an iPhone and an iPad on
#                iOS 26.0, which is the deployment target, and on iOS 27.
#
# **This does launch MarkdownPreview**, on this Mac and in each simulator, to
# host the tests that use the window server. `Scripts/run-tests-mac.sh` is the
# run made while developing, and launches nothing.
#
# **Everything is built unsigned**, into <output>, so this runs on a Mac that
# has no signing certificate and never touches Xcode's own build folders. What
# it tests is the Debug build, not the archive a release is made from.
#
# **The simulators are named, and have to exist already.** Nothing here makes
# one. Each is started by `xcodebuild` with no window and shut down when its
# tests end, and no clone of it is made. They are run a few at a time, two
# unless told otherwise.
#
# **Every run is made, whatever the one before it did**, so one pass says
# everything that is wrong. The exit status is 0 only if all of them passed.
# The last thing printed is a count for each run of the tests that passed,
# failed, failed as expected, and were expected to fail and passed.
#
# Asks nothing and changes nothing in the repository, so a release script or a
# CI job can call it as it is. Anyone may run it, an agent included.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${MDP_BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/MarkdownPreview-scripts}/release-tests"
SIMULATORS=("Claude iPhone 26" "Claude iPad 26" "Claude iPhone" "Claude iPad")
AT_ONCE=2
RUNS=()
NAMED=()

usage() {
    cat <<'HELPTEXT'
Runs every one of MarkdownPreview's tests, on everything it is released for:
this Mac as arm64 and as x86_64, and an iPhone and an iPad simulator on each
of iOS 26.0 and iOS 27. The run made once before a release.

USAGE
  ./Scripts/run-tests-release.sh [options] [run ...]

RUNS
  scripts      npm test: MarkdownCore/Tests/WebTests, under Node.
  arm64        xcodebuild: the whole MarkdownPreview scheme on this Mac. The
               engine's tests, the app's, and the ones that use the window
               server, which MarkdownPreview is launched to host.
  x86_64       The same, built for x86_64 and run under Rosetta.
  simulators   The same on each simulator, built once for all of them.

  With none named, all four.

OPTIONS
  --simulator <name>   A simulator to test on, by its name or its UDID. Give
                       it once for each. Default: Claude iPhone 26 and Claude
                       iPad 26, on iOS 26.0, and Claude iPhone and Claude
                       iPad, on iOS 27.
  --at-once <n>        How many simulators are tested at the same time.
                       Default: 2.
  --output <dir>       Where things are built and the logs are kept. Default:
                       ~/Library/Developer/Xcode/DerivedData/MarkdownPreview-scripts/release-tests
                       or $MDP_BUILD_ROOT/release-tests. Never the repository.
  -h, --help           This.

NEEDS
  Xcode, for xcodebuild. Rosetta, for the x86_64 run. Node, and `npm install`
  run once in the repository, for the scripts. Each simulator, already made:
  nothing here makes one.

RESULT
  For each run, <output>/<run>.log, and for all but the scripts
  <output>/<run>.xcresult. At the end, for each run and in total, how many
  tests:

    passed
    failed
    failed as expected       a known issue, or for the scripts a todo test
    were expected to fail    and passed. In Swift that fails the run, which is
                             the signal to take the marking off. Node lets it
                             pass.

EXIT STATUS
  0  every run passed
  1  a run failed
  2  it could not start: a bad option, or something it needs is missing
HELPTEXT
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --simulator)
            [[ -n "${2:-}" ]] || { echo "--simulator needs a name or a UDID" >&2; exit 2; }
            NAMED+=("$2"); shift 2 ;;
        --at-once)
            [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || { echo "--at-once needs a number, 1 or more" >&2; exit 2; }
            AT_ONCE="$2"; shift 2 ;;
        --output)
            [[ -n "${2:-}" ]] || { echo "--output needs a directory" >&2; exit 2; }
            OUTPUT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        scripts|arm64|x86_64|simulators) RUNS+=("$1"); shift ;;
        *) echo "unknown option or run: $1" >&2; usage >&2; exit 2 ;;
    esac
done
(( ${#RUNS[@]} > 0 )) || RUNS=(scripts arm64 x86_64 simulators)
(( ${#NAMED[@]} > 0 )) && SIMULATORS=("${NAMED[@]}")

case "$OUTPUT" in
    "$REPO"|"$REPO"/*) echo "refusing to build inside the repository: $OUTPUT" >&2; exit 2 ;;
esac

wants() { [[ " ${RUNS[*]} " == *" $1 "* ]]; }

# The UDID of every simulator that has this name, or this UDID, and a runtime
# that is installed. One line each.
udids_of() {
    xcrun simctl list devices available | awk -v wanted="$1" '
        match($0, / \([0-9A-F-]+\) \([A-Za-z ]+\) *$/) {
            name = substr($0, 1, RSTART - 1); sub(/^ +/, "", name)
            udid = substr($0, RSTART + 2); sub(/\).*$/, "", udid)
            if (name == wanted || udid == wanted) print udid
        }'
}

# Everything that would stop a run, found before any of them is made.
problems=()
UDIDS=()
[[ "$(uname -s)" == "Darwin" ]] || problems+=("this runs on a Mac; this is $(uname -s)")
if wants scripts; then
    command -v npm >/dev/null || problems+=("no npm on the PATH; install Node")
    [[ -d "$REPO/node_modules/jsdom" ]] || problems+=("jsdom is not installed; run npm install in $REPO")
fi
if wants arm64 || wants x86_64 || wants simulators; then
    command -v xcodebuild >/dev/null || problems+=("no xcodebuild on the PATH; install Xcode")
fi
if wants x86_64; then
    arch -x86_64 /usr/bin/true 2>/dev/null \
        || problems+=("Rosetta is not installed; run softwareupdate --install-rosetta")
fi
if wants simulators && command -v xcrun >/dev/null; then
    for simulator in "${SIMULATORS[@]}"; do
        found="$(udids_of "$simulator")"
        case "$(printf '%s' "$found" | grep -c .)" in
            1) UDIDS+=("$found") ;;
            0) problems+=("no simulator named $simulator, or its runtime is not installed") ;;
            *) problems+=("more than one simulator is named $simulator; give its UDID with --simulator") ;;
        esac
    done
fi
if (( ${#problems[@]} > 0 )); then
    echo "cannot run the tests:" >&2
    printf '  %s\n' "${problems[@]}" >&2
    exit 2
fi

mkdir -p "$OUTPUT" || exit 2

xcode() {
    xcodebuild -project "$REPO/MarkdownPreview.xcodeproj" -scheme MarkdownPreview "$@" \
        CODE_SIGNING_ALLOWED=NO
}

# Every run leaves <output>/<run>.status, its exit status and how long it took,
# for the table at the end. A file, since the simulators' runs are made in the
# background and can hand nothing else back.
record() { echo "$2 $((SECONDS - $3))" > "$OUTPUT/$1.status"; }

# What an earlier pass left for a run is removed before it is made again, so
# that a run that stops early is not counted from the last one's results.
forget() {
    rm -rf "$OUTPUT/$1.xcresult"
    rm -f "$OUTPUT/$1.status" "$OUTPUT/$1.log" "$OUTPUT/$1-build.log" "$OUTPUT/$1-summary.json"
}

# The log that says the most about a run: its tests', or the build's if it got
# no further than that.
log_of() {
    local log
    for log in "$OUTPUT/$1.log" "$OUTPUT/$1-build.log" "$OUTPUT/simulators-build.log"; do
        [[ -f "$log" ]] && { echo "$log"; return; }
    done
}

# build <run> <derived data> <destination> [build settings]
build() {
    local run="$1" derived="$2" destination="$3"
    shift 3
    xcode -quiet -destination "$destination" -derivedDataPath "$derived" \
        build-for-testing "$@" > "$OUTPUT/$run-build.log" 2>&1
}

# check <run> <derived data> <destination> [xcodebuild options]
#
# Built and tested in two steps: built unsigned, `xcodebuild test` stops at the
# test bundle it then cannot sign. The failures' own words are not in what
# xcodebuild prints, so the result bundle's summary is kept beside it. Without
# `-collect-test-diagnostics never`, a failure in a simulator is followed by
# ten minutes of `simctl diagnose`.
check() {
    local run="$1" derived="$2" destination="$3" status=0
    local bundle="$OUTPUT/$run.xcresult"
    shift 3
    xcode -destination "$destination" -derivedDataPath "$derived" -resultBundlePath "$bundle" \
        -collect-test-diagnostics never "$@" test-without-building > "$OUTPUT/$run.log" 2>&1 || status=1
    [[ -d "$bundle" ]] || return 1
    xcrun xcresulttool get test-results summary --path "$bundle" > "$OUTPUT/$run-summary.json"
    return "$status"
}

scripts() {
    local started=$SECONDS status=0
    echo "==> scripts"
    forget scripts
    (cd "$REPO" && npm test) > "$OUTPUT/scripts.log" 2>&1 || status=1
    record scripts "$status" "$started"
}

mac() {
    local arch="$1" started=$SECONDS status=1
    echo "==> Mac, $arch"
    forget "$arch"
    build "$arch" "$OUTPUT/xcode-$arch" "platform=macOS,arch=$arch" \
        && check "$arch" "$OUTPUT/xcode-$arch" "platform=macOS,arch=$arch" \
        && status=0
    record "$arch" "$status" "$started"
}

# Built once, for arm64 alone: no simulator on this Mac runs anything else,
# and what ships for iOS has no x86_64 in it. Then AT_ONCE simulators at a
# time. With parallel testing left on, xcodebuild tests in clones of the
# simulator it is given.
simulators() {
    local derived="$OUTPUT/xcode-simulators" built=0 next=0 batch udid
    echo "==> building for the simulators"
    forget simulators
    for udid in "${UDIDS[@]}"; do forget "$udid"; done
    build simulators "$derived" "generic/platform=iOS Simulator" EXCLUDED_ARCHS=x86_64 && built=1
    while (( next < ${#UDIDS[@]} )); do
        for (( batch = 0; batch < AT_ONCE && next < ${#UDIDS[@]}; batch++, next++ )); do
            echo "==> ${SIMULATORS[next]}"
            (
                started=$SECONDS status=1
                (( built )) \
                    && check "${UDIDS[next]}" "$derived" "platform=iOS Simulator,id=${UDIDS[next]}" \
                        -parallel-testing-enabled NO \
                    && status=0
                record "${UDIDS[next]}" "$status" "$started"
            ) &
        done
        wait
    done
}

# What each run's tests did, as four numbers: passed, failed, failed as
# expected, and expected to fail but passed. A test of the last kind is taken
# out of the failed, so the four add up to the tests that ran.

# From the TAP that Node prints when it is not writing to a terminal. A todo
# test is its expected failure, and one that passes does not fail the run.
count_scripts() {
    awk '
        /^# pass [0-9]+$/ { passed = $3 }
        /^# fail [0-9]+$/ { failed = $3 }
        /^ *not ok .* # TODO/ { expected++ }
        /^ *ok .* # TODO/ { surprised++ }
        END { print passed + 0, failed + 0, expected + 0, surprised + 0 }
    ' "$OUTPUT/scripts.log"
}

# From the result bundle's summary.
count_bundle() {
    local json="$OUTPUT/$1-summary.json" passed failed expected surprised
    [[ -f "$json" ]] || { echo "0 0 0 0"; return; }
    passed="$(plutil -extract passedTests raw -o - "$json")"
    failed="$(plutil -extract failedTests raw -o - "$json")"
    expected="$(plutil -extract expectedFailures raw -o - "$json")"
    surprised="$(grep -cE '"failureText" *: *"(Known issue was not recorded|Expected failure .* but none recorded)' "$json")"
    echo "$passed $((failed - surprised)) $expected $surprised"
}

# The system a run's tests ran on, as the result bundle has it: "iOS 26.0, ".
# Nothing for a run that has no bundle.
system_of() {
    local json="$OUTPUT/$1-summary.json" platform version
    [[ -f "$json" ]] || return
    platform="$(plutil -extract devicesAndConfigurations.0.device.platform raw -o - "$json" 2>/dev/null)" || return
    version="$(plutil -extract devicesAndConfigurations.0.device.osVersion raw -o - "$json" 2>/dev/null)" || return
    echo "${platform% Simulator} $version, "
}

echo "MarkdownPreview $(sed -n 's/^MARKETING_VERSION = //p' "$REPO/Version.xcconfig")" \
    "($(sed -n 's/^CURRENT_PROJECT_VERSION = //p' "$REPO/Version.xcconfig"))," \
    "at $(git -C "$REPO" rev-parse --short HEAD)$([[ -z "$(git -C "$REPO" status --porcelain)" ]] || echo ", with changes not committed")"
echo

# Each run's name in the table, and the name its files go by.
labels=()
files=()
if wants scripts; then scripts; labels+=("scripts"); files+=("scripts"); fi
if wants arm64; then mac arm64; labels+=("Mac, arm64"); files+=("arm64"); fi
if wants x86_64; then mac x86_64; labels+=("Mac, x86_64"); files+=("x86_64"); fi
if wants simulators; then
    simulators
    labels+=("${SIMULATORS[@]}")
    files+=("${UDIDS[@]}")
fi
echo

ROW='%-18s %7s %7s %10s %12s   %s\n'
failed=0
rows=()
totals=(0 0 0 0)
for (( i = 0; i < ${#files[@]}; i++ )); do
    file="${files[i]}"
    read -r status seconds < "$OUTPUT/$file.status"
    if [[ "$file" == scripts ]]; then
        read -r -a counts <<< "$(count_scripts)"
        system=""
    else
        read -r -a counts <<< "$(count_bundle "$file")"
        system="$(system_of "$file")"
    fi
    for n in 0 1 2 3; do totals[n]=$((totals[n] + counts[n])); done
    if (( status == 0 )); then
        note="${system}passed in ${seconds}s"
    else
        note="${system}FAILED in ${seconds}s: $(log_of "$file")"
        failed=1
        # A run that fails with no test failing did not get as far as its tests.
        if (( counts[1] + counts[3] == 0 )); then
            note="$note (it did not run to the end)"
        elif [[ -f "$OUTPUT/$file-summary.json" ]]; then
            echo "==> ${labels[i]} failed"
            cat "$OUTPUT/$file-summary.json"
            echo
        fi
    fi
    rows+=("$(printf "$ROW" "${labels[i]}" "${counts[@]}" "$note")")
done

printf "$ROW" "" "" "" "expected" "expected to" ""
printf "$ROW" "" "passed" "failed" "failures" "fail, passed" ""
printf '%s\n' "${rows[@]}"
printf "$ROW" "total" "${totals[@]}" ""
exit "$failed"
