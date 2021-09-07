#!/bin/bash
# This code is part of Qiskit.
#
# (C) Copyright IBM 2021.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

# Runs 'asv' for a single domain and push results to repo

# Script parameters
BASENAME=$0
GIT_OWNER=$1
GIT_USERID=$2
GIT_PERSONAL_TOKEN=$3
DOMAIN=$4

# main lock file with this file name and containing the pid
MAIN_LOCKFILE="/tmp/$DOMAIN.lock"

if [ -f $MAIN_LOCKFILE ]; then
  if ps -p `cat $MAIN_LOCKFILE` > /dev/null 2>&1; then
      echo "Script $BASENAME for $DOMAIN is still running."
      exit 0
  fi
fi
echo $$ > $MAIN_LOCKFILE

echo "Start script $BASENAME for $DOMAIN."

# Removes the file if:
# EXIT - normal termination
# SIGHUP - termination of the controlling process
# SIGKILL - immediate program termination
# SIGINT - program interrupt INTR character
# SIGQUIT - program interrupt QUIT character
# SIGTERM - program termination by kill
trap 'rm -f "$MAIN_LOCKFILE" >/dev/null 2>&1' EXIT HUP KILL INT QUIT TERM

# find if asv is installed
ASV_CMD="asv"
if command -v $ASV_CMD > /dev/null 2>&1; then
  echo "asv command is available in known paths."
else
  ASV_CMD="/usr/local/bin/asv"
  if command -v $ASV_CMD > /dev/null 2>&1; then
    echo "asv command is available at $ASV_CMD."
  else
    echo "asv command not found in any known path."
    exit 1
  fi
fi

source /opt/benchmark/bin/activate

set -e

RUN_ASV=false
ASV_RESULT=1
pushd $DOMAIN
if [ -n "$(find benchmarks/* -not -name '__*' | head -1)" ]; then
  date
  ASV_RESULT=0
  if [ -z "$ASV_QUICK" ]; then
    echo "Run Benchmarks for domain $DOMAIN."
    $ASV_CMD run --show-stderr --launch-method spawn --record-samples NEW && ASV_RESULT=$? || ASV_RESULT=$?
  else
    echo "Run Quick Benchmarks for domain $DOMAIN."
    $ASV_CMD run --quick --show-stderr && ASV_RESULT=$? || ASV_RESULT=$?
  fi
  date
  echo "asv command returned $ASV_RESULT for domain $DOMAIN."
  if [ $ASV_RESULT == 0 ]; then
    echo "Publish Benchmark for domain $DOMAIN."
    $ASV_CMD publish
  fi
  RUN_ASV=true
else
  echo "No Benchmark files found for domain $DOMAIN, run skipped."
fi
popd

# github lock file with this file name and containing the pid
GITHUB_LOCKFILE="/tmp/github_benchmarks.lock"

while :
do
  if [ -f $GITHUB_LOCKFILE ]; then
    if ps -p `cat $GITHUB_LOCKFILE` > /dev/null 2>&1; then
        echo "Benchmarks Github process is still running."
        sleep 15
    else
      break
    fi
  else
    break
  fi
done
echo "Start Github script for domain $DOMAIN."
echo $$ > $GITHUB_LOCKFILE

rm -rf /tmp/$DOMAIN
mkdir -p /tmp/$DOMAIN

echo "echo $GIT_PERSONAL_TOKEN" > /tmp/$DOMAIN/.git-askpass
chmod +x /tmp/$DOMAIN/.git-askpass
export GIT_ASKPASS=/tmp/$DOMAIN/.git-askpass

git clone https://$GIT_USERID@github.com/$GIT_OWNER/qiskit-app-benchmarks.git /tmp/$DOMAIN/qiskit-app-benchmarks

echo 'Copy main docs'

pushd /tmp/$DOMAIN/qiskit-app-benchmarks
git config user.name "Qiskit Application Benchmarks Autodeploy"
git config user.email "qiskit@qiskit.org"
git checkout gh-pages
GLOBIGNORE=.git:finance:machine_learning:nature:optimization
rm -rf * .*
unset GLOBIGNORE
popd

# copy base html to benchmarks gh-pages branch
rm -rf /tmp/$DOMAIN/qiskit-app-benchmarks-html
mkdir /tmp/$DOMAIN/qiskit-app-benchmarks-html
cp -r docs/_build/html/. /tmp/$DOMAIN/qiskit-app-benchmarks-html

# Remove domain base html folders
declare -a TARGETS=("finance" "machine_learning" "nature" "optimization")
for target in "${TARGETS[@]}"
do
  rm -rf /tmp/$DOMAIN/qiskit-app-benchmarks-html/$target
done
# copy only base folders excluding domains
cp -r /tmp/$DOMAIN/qiskit-app-benchmarks-html/. /tmp/$DOMAIN/qiskit-app-benchmarks


pushd /tmp/$DOMAIN/qiskit-app-benchmarks
git add .
# push only if there are changes
if git diff-index --quiet HEAD --; then
  echo 'Nothing to commit for the base doc template.'
else
  git commit -m "[Benchmarks] Base documentation update"
fi
popd

pushd $DOMAIN
if [ "$RUN_ASV" = true ]; then
  date
  if [ $ASV_RESULT == 0 ]; then
    echo "copy asv published html results for domain $DOMAIN."
    rm -rf /tmp/$DOMAIN/qiskit-app-benchmarks/$DOMAIN/*
    cp -r .asv/html/. /tmp/$DOMAIN/qiskit-app-benchmarks/$DOMAIN
  fi
else
  echo "No benchmarks for domain $DOMAIN, remove old html results."
  rm -rf /tmp/$DOMAIN/qiskit-app-benchmarks/$DOMAIN/*
  cp -r ../docs/_build/html/$DOMAIN/. /tmp/$DOMAIN/qiskit-app-benchmarks/$DOMAIN
fi
popd
pushd /tmp/$DOMAIN/qiskit-app-benchmarks
git add .
# push only if there are changes
if git diff-index --quiet HEAD --; then
  echo "Nothing to push for $DOMAIN."
else
  echo "Push benchmark for $DOMAIN."
  git commit -m "[Benchmarks $DOMAIN] Automated documentation update"
  git push origin gh-pages
fi
popd

echo "Final Cleanup for $DOMAIN."
unset GIT_ASKPASS
rm -rf /tmp/$DOMAIN
rm $GITHUB_LOCKFILE
date
echo "End of script $BASENAME for $DOMAIN."
