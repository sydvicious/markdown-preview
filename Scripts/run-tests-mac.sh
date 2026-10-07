#!/bin/bash
#
# Copyright ©2026 Syd Polk. All Rights Reserved.
# SPDX-License-Identifier: BSD-3-Clause
#
# **Runs only the tests that do not use the window server**, on this Mac:
#
#   engine    MarkdownCoreTests and MarkdownCoreConformanceTests, with
#             `swift test` in the MarkdownCore package;
#   scripts   the tests for the preview's scripts in MarkdownPreview/Web, with
#             `npm test`, under Node;
#   app       MarkdownPreviewTests, the app's stores, view models and
#             utilities, with `xcodebuild`.
#
# **Nothing here launches MarkdownPreview**, a simulator, or anything with a
# window. The app suite's bundle has no host: it compiles the app's stores,
# view models and utilities into itself, and is run by Xcode's `xctest`.
#
# **MarkdownPreviewWindowServerTests is not run here.** Those are the tests
# that do use it: pages loaded in WebKit, and the pasteboards. The app is
# launched to host them. Run them, with everything above except the scripts
# suite, in Xcode: the MarkdownPreview scheme, Product > Test (Cmd-U). Or from
# the command line:
#
#   xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview \
#       -destination "platform=macOS,arch=arm64"
#
# and for those tests alone, add -only-testing:MarkdownPreviewWindowServerTests.
#
# **The app suite is built unsigned**, so this runs on a Mac that has no
# signing certificate.
#
# **Apple silicon only.** Nothing here is built or run for x86_64: this is the
# run made while developing. The release is still built for both, and its
# tests are run for both, once, before it ships.
#
# **Every suite runs, whatever the one before it did**, so one run says
# everything that is wrong. The exit status is 0 only if all of them passed.
# The last thing printed is a count for each suite of the tests that passed,
# failed, failed as expected, and were expected to fail and passed.
#
# Asks nothing and changes nothing in the repository, so a release script or a
# CI job can call it as it is. Anyone may run it, an agent included.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${MDP_BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/MarkdownPreview-scripts}/tests"
SUITES=()

usage() {
    cat <<'HELPTEXT'
Runs only those of MarkdownPreview's tests that do not use the window server:
the markdown engine's, the preview scripts', and the app's own. Mac only, and
Apple silicon only: nothing is built or run for x86_64.

USAGE
  ./Scripts/run-tests-mac.sh [options] [suite ...]

SUITES
  engine     swift test, in MarkdownCore: MarkdownCoreTests and
             MarkdownCoreConformanceTests.
  scripts    npm test: MarkdownCore/Tests/WebTests, under Node.
  app        xcodebuild: MarkdownPreviewTests, the app's stores, view models
             and utilities. The app is built, unsigned, and not launched.

  With none named, all three.

OPTIONS
  --output <dir>   Where things are built and the logs are kept. Default:
                   ~/Library/Developer/Xcode/DerivedData/MarkdownPreview-scripts/tests
                   or $MDP_BUILD_ROOT/tests. Never the repository.
  -h, --help       This.

NEEDS
  Xcode, for swift and xcodebuild. Node, and `npm install` run once in the
  repository, for the scripts suite.

RESULT
  <output>/engine.log, <output>/scripts.log and <output>/app.log. The app suite
  also leaves <output>/app.xcresult. At the end, for each suite and in total,
  how many tests:

    passed
    failed
    failed as expected       a known issue, or for the scripts a todo test
    were expected to fail    and passed. In Swift that fails the run, which is
                             the signal to take the marking off. Node lets it
                             pass.

NOT RUN HERE
  MarkdownPreviewWindowServerTests: the tests that use the window server or a
  pasteboard, which the app is launched to host. In Xcode, the MarkdownPreview
  scheme and Product > Test (Cmd-U) runs them with the app's and the engine's.
  From the command line:

    xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview \
        -destination "platform=macOS,arch=arm64"

  For those alone, add -only-testing:MarkdownPreviewWindowServerTests.

EXIT STATUS
  0  every suite passed
  1  a suite failed
  2  it could not start: a bad option, or something it needs is missing
HELPTEXT
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ -n "${2:-}" ]] || { echo "--output needs a directory" >&2; exit 2; }
            OUTPUT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        engine|scripts|app) SUITES+=("$1"); shift ;;
        *) echo "unknown option or suite: $1" >&2; usage >&2; exit 2 ;;
    esac
done
(( ${#SUITES[@]} > 0 )) || SUITES=(engine scripts app)

case "$OUTPUT" in
    "$REPO"|"$REPO"/*) echo "refusing to build inside the repository: $OUTPUT" >&2; exit 2 ;;
esac

wants() { [[ " ${SUITES[*]} " == *" $1 "* ]]; }

# Everything that would stop a suite, found before any of them is run.
problems=()
[[ "$(uname -s)" == "Darwin" ]] || problems+=("this runs on a Mac; this is $(uname -s)")
if wants engine; then
    command -v swift >/dev/null || problems+=("no swift on the PATH; install Xcode")
fi
if wants scripts; then
    command -v npm >/dev/null || problems+=("no npm on the PATH; install Node")
    [[ -d "$REPO/node_modules/jsdom" ]] || problems+=("jsdom is not installed; run npm install in $REPO")
fi
if wants app; then
    command -v xcodebuild >/dev/null || problems+=("no xcodebuild on the PATH; install Xcode")
fi
if (( ${#problems[@]} > 0 )); then
    echo "cannot run the tests:" >&2
    printf '  %s\n' "${problems[@]}" >&2
    exit 2
fi

mkdir -p "$OUTPUT" || exit 2

# The engine is built under <output>, not in MarkdownCore/.build, so a run here
# and a `swift test` typed by hand never wait on each other's build.
engine() {
    rm -f "$OUTPUT/engine-events.jsonl"
    swift test --package-path "$REPO/MarkdownCore" --scratch-path "$OUTPUT/swiftpm" \
        --event-stream-output-path "$OUTPUT/engine-events.jsonl"
}
# TAP is asked for by name. The counts at the end are read from it, and which
# reporter Node uses when it is not writing to a terminal depends on the Node:
# 22 prints TAP, 26 does not.
scripts() { cd "$REPO" && NODE_OPTIONS="${NODE_OPTIONS:-} --test-reporter=tap" npm test; }

# Built and run in two steps: built unsigned, `xcodebuild test` stops at the
# test bundle it then cannot sign. The failures' own words are not in what
# xcodebuild prints, so they are read out of the result bundle.
app() {
    local bundle="$OUTPUT/app.xcresult"
    local xcode=(xcodebuild -project "$REPO/MarkdownPreview.xcodeproj" -scheme MarkdownPreview
        -destination "platform=macOS,arch=arm64" -derivedDataPath "$OUTPUT/xcode")
    local status=0
    rm -rf "$bundle" "$OUTPUT/app-summary.json"
    "${xcode[@]}" -quiet build-for-testing CODE_SIGNING_ALLOWED=NO || return 1
    "${xcode[@]}" -resultBundlePath "$bundle" -only-testing:MarkdownPreviewTests \
        test-without-building CODE_SIGNING_ALLOWED=NO || status=1
    [[ -d "$bundle" ]] || return 1
    xcrun xcresulttool get test-results summary --path "$bundle" > "$OUTPUT/app-summary.json"
    (( status == 0 )) || cat "$OUTPUT/app-summary.json"
    return "$status"
}

# What each suite's tests did, as four numbers: passed, failed, failed as
# expected, and expected to fail but passed. A test of the last kind is taken
# out of the failed, so the four add up to the tests that ran.

# From the record Swift Testing keeps of the run, a line of JSON for each
# test and each thing that happened to it. Not from what `swift test` prints:
# twice, while this was being written, some of the lines saying a test had
# passed never arrived. Tests written with XCTest are not in the record, and
# the engine has none.
count_engine() {
    [[ -f "$OUTPUT/engine-events.jsonl" ]] || { echo "0 0 0 0"; return; }
    awk '
        function field(line, key) { sub(".*\"" key "\":\"", "", line); sub(/".*$/, "", line); return line }
        /"kind":"test"/ && /"kind":"function"/ { isTest[field($0, "id")] = 1; next }
        /"kind":"testEnded"/ { if (field($0, "testID") in isTest) ran++; next }
        /"kind":"issueRecorded"/ {
            test = field($0, "testID")
            if ($0 ~ /"isKnown":true/) known[test] = 1
            else if ($0 ~ /"text":"Known issue was not recorded"/) surprise[test] = 1
            else if ($0 !~ /"severity":"warning"/) broken[test] = 1
        }
        END {
            for (test in broken) failed++
            for (test in surprise) if (!(test in broken)) surprised++
            for (test in known) if (!(test in broken) && !(test in surprise)) expected++
            print ran - failed - surprised - expected, failed + 0, expected + 0, surprised + 0
        }
    ' "$OUTPUT/engine-events.jsonl"
}

# From the TAP that Node is asked for. A todo
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
count_app() {
    local json="$OUTPUT/app-summary.json" passed failed expected surprised
    [[ -f "$json" ]] || { echo "0 0 0 0"; return; }
    passed="$(plutil -extract passedTests raw -o - "$json")"
    failed="$(plutil -extract failedTests raw -o - "$json")"
    expected="$(plutil -extract expectedFailures raw -o - "$json")"
    surprised="$(grep -cE '"failureText" *: *"(Known issue was not recorded|Expected failure .* but none recorded)' "$json")"
    echo "$passed $((failed - surprised)) $expected $surprised"
}

ROW='%-8s %7s %7s %10s %12s   %s\n'
failed=0
rows=()
totals=(0 0 0 0)
for suite in engine scripts app; do
    wants "$suite" || continue
    log="$OUTPUT/$suite.log"
    started=$SECONDS
    echo "==> $suite"
    if "$suite" 2>&1 | tee "$log"; then
        note="passed in $((SECONDS - started))s"
    else
        note="FAILED in $((SECONDS - started))s: $log"
        failed=1
    fi
    echo
    read -r -a counts <<< "$("count_$suite")"
    for i in 0 1 2 3; do totals[i]=$((totals[i] + counts[i])); done
    # A suite that fails with no test failing did not get as far as its tests.
    [[ "$note" == FAILED* ]] && (( counts[1] + counts[3] == 0 )) && note="$note (it did not run to the end)"
    rows+=("$(printf "$ROW" "$suite" "${counts[@]}" "$note")")
done

printf "$ROW" "" "" "" "expected" "expected to" ""
printf "$ROW" "" "passed" "failed" "failures" "fail, passed" ""
printf '%s\n' "${rows[@]}"
printf "$ROW" "total" "${totals[@]}" ""
exit "$failed"
