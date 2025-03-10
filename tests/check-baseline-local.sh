#!/bin/bash

if [[ -z $(command -v jq) ]]; then
    >2& echo "jq not found. Please install."
    >2& echo "Exiting"
    exit 1
fi

if [[ -z $(command -v wget) ]]; then
    >2& echo "wget not found. Please install."
    >2& echo "Exiting"
    exit 1
fi

if [[ -z $(command -v realpath) ]]; then
    >2& echo "realpath not found. Please install coreutils."
    >2& echo "Exiting"
    exit 1
fi

OS=$(uname -s)

if [[ "${OS}" != "Linux" && "${OS}" != "Darwin" ]]; then
    >2& echo "This script only supports Linux and MacOS"
    >2& echo "$(uname -s) is not a supported OS"
    >2& echo "Exiting"
    exit 1
fi

SCRIPT="$(realpath $0)"
TOOLS="${SCRIPT%/*}"
SIGMA="${TOOLS%/*}"

declare -A PID2OS

if [[ -n "$1" && -d "$1" && -r "$1" ]]; then
    RULES="$1"
else
    RULES="${SIGMA}"/rules
fi

TMP=$(mktemp -d)
if [[ -z "${TMP}" || ! -d "${TMP}" || ! -w "${TMP}" ]]; then
    >2& echo "Error: Created temporary directory ${TMP} is not writable."
    >2& echo "Exiting"
    exit 1
fi


cd "${TMP}"

echo
echo "Copy rules from ${SIGMA} to ${TMP}"
cp -r "${RULES}"/windows .
echo
echo "Remove deprecated rules"
grep -ERl "^status: deprecated" windows | xargs -r rm -v
echo
echo "Download evtx-sigma-checker"
if [[ "${OS}" == "Linux" ]]; then
    wget --no-verbose --progress=bar --show-progress https://github.com/NextronSystems/evtx-baseline/releases/latest/download/evtx-sigma-checker
elif [[ "${OS}" == "Darwin" ]]; then
    wget --no-verbose --progress=bar --show-progress https://github.com/NextronSystems/evtx-baseline/releases/latest/download/evtx-sigma-checker-darwin -O evtx-sigma-checker
fi
chmod +x evtx-sigma-checker
echo

# Windows 7 32-bit
OS="Windows 7 32-bit"
{
    wget --quiet https://github.com/NextronSystems/evtx-baseline/releases/latest/download/win7-x86.tgz
    tar xzf win7-x86.tgz
    echo "  Checking for Sigma matches in $OS baseline"
    ./evtx-sigma-checker --log-source "${SIGMA}"/tools/config/thor.yml --evtx-path win7_x86/ --rule-path windows/ > findings-win7.json
    echo "  Finished Checking for Sigma matches in $OS baseline"
}&
pids+=($!)
PID2OS[$!]=$OS

# Windows 2022
OS="Windows 2022"
{
    wget --quiet https://github.com/NextronSystems/evtx-baseline/releases/latest/download/win2022-evtx.tgz
    tar xzf win2022-evtx.tgz
    echo "  Checking for Sigma matches in $OS baseline (this takes around 1 minute)"
    ./evtx-sigma-checker --log-source "${SIGMA}"/tools/config/thor.yml --evtx-path win2022-evtx/ --rule-path windows/ > findings-win2022.json
    echo "  Finished Checking for Sigma matches in $OS baseline"
}&
pids+=($!)
PID2OS[$!]=$OS

# Windows 10
OS="Windows 10"
{
    wget --quiet https://github.com/NextronSystems/evtx-baseline/releases/latest/download/win10-client.tgz
    tar xzf win10-client.tgz
    echo "  Checking for Sigma matches in $OS baseline (this takes at least 2 minutes)"
    ./evtx-sigma-checker --log-source "${SIGMA}"/tools/config/thor.yml --evtx-path Logs_Client/ --rule-path windows/ > findings-win10.json
    echo "  Finished Checking for Sigma matches in $OS baseline"
}&
pids+=($!)
PID2OS[$!]=$OS

# Windows 11
OS="Windows 11"
{
    wget --quiet https://github.com/NextronSystems/evtx-baseline/releases/latest/download/win11-client.tgz
    tar xzf win11-client.tgz
    echo "  Checking for Sigma matches in $OS baseline (this takes at least 6 minutes)"
    ./evtx-sigma-checker --log-source "${SIGMA}"/tools/config/thor.yml --evtx-path Logs_Win11/ --rule-path windows/ > findings-win11.json
    echo "  Finished Checking for Sigma matches in $OS baseline"
}&
pids+=($!)
PID2OS[$!]=$OS

# Sync with all background jobs
for pid in ${pids[*]}; do
    echo "===>  Waiting for PID $pid / ${PID2OS[$pid]}"
    wait $pid
done

echo
echo "###############"
echo "##  MATCHES  ##"
echo "###############"
echo
echo "Windows 7 32-bit:"
"${SIGMA}"/.github/workflows/matchgrep.sh findings-win7.json "${SIGMA}"/.github/workflows/known-FPs.csv
echo
echo "Windows 10:"
"${SIGMA}"/.github/workflows/matchgrep.sh findings-win10.json "${SIGMA}"/.github/workflows/known-FPs.csv
echo
echo "Windows 11:"
"${SIGMA}"/.github/workflows/matchgrep.sh findings-win11.json "${SIGMA}"/.github/workflows/known-FPs.csv
echo
echo "Windows 2022:"
"${SIGMA}"/.github/workflows/matchgrep.sh findings-win2022.json "${SIGMA}"/.github/workflows/known-FPs.csv

echo
read -p  "Removing temporary directory ${TMP}. Press Enter to continue." -s
echo
rm -r "${TMP}"
echo "Removed ${TMP}"
echo "Finished"
