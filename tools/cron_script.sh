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

# A virtual env names benchmark has been created
# and has all the qiskit-app-benchmarks requirements-dev.txt
# dependencies installed

# Script parameters
BASENAME=$0
GIT_OWNER=$1
GIT_USERID=$2
GIT_PERSONAL_TOKEN=$3

# lock file with this file name and containing the pid
LOCKFILE=/tmp/`basename $BASENAME`.lock

if [ -f $LOCKFILE ]; then
  if ps -p `cat $LOCKFILE` > /dev/null 2>&1; then
      echo "Script $BASENAME is still running."
      exit 0
  fi
fi
echo $$ > $LOCKFILE
echo "Start script $BASENAME."

# Removes the file if:
# EXIT - normal termination
# SIGHUP - termination of the controlling process
# SIGKILL - immediate program termination
# SIGINT - program interrupt INTR character
# SIGQUIT - program interrupt QUIT character
# SIGTERM - program termination by kill
trap 'rm -f "$LOCKFILE" >/dev/null 2>&1' EXIT HUP KILL INT QUIT TERM

source /opt/benchmark/bin/activate

set -e

# qiskit-app-benchmarks was already cloned in opt and is checkout to main branch
# qiskit-app-benchmarks has a gh-pages branch with the html contents in it
# Build base html

git pull
make clean_sphinx
make html SPHINXOPTS=-W

declare -a DOMAINS=("finance" "machine_learning" "nature" "optimization")

echo 'Run Benchmarks for domains'
DATE=`date +%Y%m%d%H%M%S%Z`
for DOMAIN in "${DOMAINS[@]}"
do
  LOG_FILE="/tmp/${DOMAIN}_${DATE}.log"
  stdbuf --output=L tools/asv_domain.sh $GIT_OWNER $GIT_USERID $GIT_PERSONAL_TOKEN $DOMAIN &> $LOG_FILE &
done

echo 'Domain scripts are running, wait for all processes to end'
date
wait
date
echo 'All domain processes ended'

echo 'Final Cleanup'
echo "End of script $BASENAME."
