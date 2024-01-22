#!/usr/bin/env bash

# Copyright (c) 2024, NVIDIA CORPORATION.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euxo pipefail

################################################################################
# This script generates coverage information from the dcgm test suite.         #
# To generate coverage information,                                            #
#   - build dcgm with `./build.sh --coverage`                                  #
#   - run the test suite in _out/Linux-<arch>-<type>/share/dcgm_tests          #
#   - invoke this script from that same directory                              #
#                                                                              #
# If you would like to generate coverage from a test run on a different        #
# machine, run the test suite and then copy _coverage_int to the local test    #
# directory and invoke this script                                             #
################################################################################

DIR="$(dirname $(realpath $0))"
RELDIR="$(echo $DIR | rev | cut -d'/' -f-4 | rev)"
DCGM_DIR="${DCGM_DIR:-$(realpath $DIR/../../../..)}"
BUILD_NAME="${BUILD_NAME:-$(basename $(realpath $DIR/../../))}"
BUILD_DIR="$(realpath $DCGM_DIR/_out/build/$BUILD_NAME)"
COVERAGE_DIR="$DIR/_coverage"
COVERAGE_CTEST_DIR="$COVERAGE_DIR/ctest"
COVERAGE_PYTHON_DIR="$COVERAGE_DIR/python"
COVERAGE_LCOV_DIR="$COVERAGE_DIR/processed"
COVERAGE_REPORT_DIR="$DIR/coverage_report"
LCOV="lcov --rc lcov_branch_coverage=1 --rc genhtml_hi_limit=70 --rc genhtml_med_limit=70 --gcov-tool /opt/cross/bin/x86_64-linux-gnu-gcov"

if [[ ! -f "$DCGM_DIR/intodocker.sh" ]]; then
    echo "Could not find intodocker.sh. Make sure DCGM_DIR is properly configured" \
        "or that this is running in _out/Linux-<arch>-<type>/share/dcgm_tests"
fi

if [[ "${DCGM_BUILD_INSIDE_DOCKER:-}" = 1 ]]; then
    true # proceed to script below
else
    "$DCGM_DIR/intodocker.sh" -- bash -c "$RELDIR/$0 $*"
    exit $?
fi

rm -rf "$COVERAGE_LCOV_DIR" "$COVERAGE_REPORT_DIR"
mkdir -p "$COVERAGE_LCOV_DIR" "$COVERAGE_CTEST_DIR" "$COVERAGE_PYTHON_DIR"

pushd "$BUILD_DIR"
# copy *gcno files next to their *gcda counterparts so lcov can find them
find . -iname '*.gcno' -exec cp --no-preserve=ownership,mode --parents '{}' "$COVERAGE_PYTHON_DIR" ';'
# copy the ctest files separately so we don't overwrite gcdas generated by the Python tests
find . '(' -iname '*.gcno' -o -iname '*.gcda' ')' -exec cp --no-preserve=ownership,mode --parents '{}' "$COVERAGE_CTEST_DIR" ';'
popd

# Generate coverage for all files. Without this, we don't capture files that were not executed
$LCOV -o "$COVERAGE_LCOV_DIR/base.info" -d "$BUILD_DIR" --capture -i
# Calculate coverage
$LCOV -o "$COVERAGE_LCOV_DIR/ctest.info" -b "$BUILD_DIR" -d "$COVERAGE_CTEST_DIR" --capture
$LCOV -o "$COVERAGE_LCOV_DIR/python.info" -b "$BUILD_DIR" -d "$COVERAGE_PYTHON_DIR" --capture
# lcov cannot handle negative integers that gcov outputs in certain scenarios
# Workaround from https://stackoverflow.com/questions/25585895/lcov-inconsistent-coverage
sed -i -e 's/,-1$/,0/g' "$COVERAGE_LCOV_DIR/ctest.info" "$COVERAGE_LCOV_DIR/python.info"
# Combine coverage with baseline from the first step
$LCOV -o "$COVERAGE_LCOV_DIR/combined.info" -a "$COVERAGE_LCOV_DIR/base.info" \
    -a "$COVERAGE_LCOV_DIR/ctest.info" -a  "$COVERAGE_LCOV_DIR/python.info"
# Get rid of files we don't care about (vendored code)
$LCOV -o "$COVERAGE_LCOV_DIR/pass2.info" -e "$COVERAGE_LCOV_DIR/combined.info" '/workspaces/*'
$LCOV -o "$COVERAGE_LCOV_DIR/pass3.info" -r "$COVERAGE_LCOV_DIR/pass2.info" '*/sdk/*'
$LCOV -o "$COVERAGE_LCOV_DIR/dcgm_coverage.info" -r "$COVERAGE_LCOV_DIR/pass3.info" '*/dcgm_private/PerfWorks/*'

genhtml --rc lcov_branch_coverage=1 --rc genhtml_hi_limit=70 --rc genhtml_med_limit=70 -o "$COVERAGE_REPORT_DIR" "$COVERAGE_LCOV_DIR/dcgm_coverage.info"
