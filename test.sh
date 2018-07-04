#!/bin/sh
#
# (C) Copyright 2016 Diomidis Spinellis
#
# This file is part of gi, the Git-based issue management system.
#
# gi is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# gi is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with gi.  If not, see <http://www.gnu.org/licenses/>.
#

# Display a test's result
message()
{
  local okfail

  okfail=$1
  shift
  if [ "$1" ] ; then
    echo "$okfail $ntest - $*"
  else
    echo "$okfail $ntest - $testname"
  fi |
  sed "s/$gi_re/gi/"
}

ok()
{
  message ok $*
}

fail()
{
  failed=1
  message fail $*
}

# Test specified command, which should succeed
try()
{
  ntest=$(expr $ntest + 1)
  $* >/dev/null 2>&1
  cd .issues
  if git status | grep 'not staged' >/dev/null ; then
    fail staging $*
  else
    ok staging $*
  fi
  cd ..
  start
  if [ $? = 0 ] ; then
    ok $*
  else
    fail $*
  fi
}

# Test specified command, which should fail
ntry()
{
  ntest=$(expr $ntest + 1)
  $* >/dev/null 2>&1
  if [ $? != 0 ] ; then
    ok "fail $*"
  else
    fail "fail $*"
  fi
}

# grep for the specified pattern, which should be found
# Does not increment ntest, because it is executed as a separate process
try_grep()
{
  grep "$1" >/dev/null 2>&1
  if [ $? = 0 ] ; then
    ok "grep $1"
  else
    fail "grep $1"
  fi
}

# grep for the specified pattern, which should not be found
# Does not increment ntest, because it is executed as a separate process
try_ngrep()
{
  grep "$1" >/dev/null 2>&1
  if [ $? != 0 ] ; then
    ok "not grep $1"
  else
    fail "not grep $1"
  fi
}

# Start a new test with the specified description
start()
{
  ntest=$(expr $ntest + 1)
  testname="$@"
}

echo 'TAP version 13'
failed=0
ntest=0
gi=$(pwd)/git-issue.sh
gi_re=$(echo $gi | sed 's/[^0-9A-Za-z]/\\&/g')

start
GenFiles="git-issue.sh git-issue.1"
make sync-docs
Status=$(git status --porcelain -- $GenFiles)
if [ -z "$Status" ]; then
    ok "make sync-docs left $GenFiles as committed"
else
    fail "make sync-docs changed $GenFiles"
    git checkout -- $GenFiles
fi

TopDir=$(mktemp -d)
echo "Test artifacts saved in $TopDir"
cd $TopDir

mkdir testdir
cd testdir

try $gi init
try $gi list

start ; $gi list $issue | try_ngrep .

# New
try $gi new -s 'First-issue'
start ; $gi list | try_grep 'First-issue'

# New with editor
export VISUAL='mv ../issue-desc '

# Empty summary/description should fail
touch issue-desc
ntry $gi new

cat <<EOF >issue-desc
Second issue

Line in description
EOF
try $gi new
export VISUAL=

issue=$($gi list | awk '/Second issue/{print $1}')

# Show
start ; $gi show $issue | try_grep 'Second issue'
start ; $gi show $issue | try_grep 'Line in description'
start ; $gi show $issue | try_grep '^Author:'
start ; $gi show $issue | try_grep '^Tags:[ 	]*open'
ntry $gi show xyzzy

# Comment
start
cat <<EOF >comment
Comment first line
comment second line
EOF
export VISUAL='mv ../comment '; try $gi comment $issue
export VISUAL=
start ; $gi show -c $issue | try_grep 'comment second line'

# Assign
try $gi assign $issue joe@example.com
try $gi assign $issue joe@example.com
start ; $gi show $issue | try_grep '^Assigned-to:[ 	]joe@example.com'

# Watchers
try $gi watcher $issue jane@example.com
start ; $gi show $issue | try_grep '^Watchers:[ 	]jane@example.com'
try $gi watcher $issue alice@example.com
ntry $gi watcher $issue alice@example.com
start ; $gi show $issue | try_grep '^Watchers:.*jane@example.com'
start ; $gi show $issue | try_grep '^Watchers:.*alice@example.com'
try $gi watcher -r $issue alice@example.com
start ; $gi show $issue | try_ngrep '^Watchers:.*alice@example.com'
try $gi watcher $issue alice@example.com

# Tags (most also tested through watchers)
try $gi tag $issue feature
start ; $gi show $issue | try_grep '^Tags:.*feature'
ntry $gi tag $issue feature

# List by tag
start ; $gi list feature | try_grep 'Second issue'
start ; $gi list open | try_grep 'First-issue'
start ; $gi list feature | try_ngrep 'First-issue'
try $gi tag -r $issue feature
start ; $gi list feature | try_ngrep 'Second issue'
try $gi tag $issue feature

# close
try $gi close $issue
start ; $gi list | try_ngrep 'Second issue'
start ; $gi list closed | try_grep 'Second issue'

# log
try $gi log
start ; n=$($gi log | tee foo | grep -c gi:)
try test $n -ge 18

# clone
# Required in order to allow a push to a non-bare repo
$gi git config --add receive.denyCurrentBranch ignore
cd ..
rm -rf testdir2
mkdir testdir2
cd testdir2
git clone ../testdir/.issues/ 2>/dev/null
start ; $gi show $issue | try_grep '^Watchers:.*alice@example.com'
start ; $gi show $issue | try_grep '^Tags:.*feature'
start ; $gi show $issue | try_grep '^Assigned-to:[ 	]joe@example.com'
start ; $gi show $issue | try_grep 'Second issue'
start ; $gi show $issue | try_grep 'Line in description'
start ; $gi show $issue | try_grep '^Author:'
start ; $gi show $issue | try_grep '^Tags:.*closed'

# Push and pull
try $gi tag $issue cloned
try $gi push
cd ../testdir
try $gi pull
$gi git reset --hard >/dev/null # Required, because we pushed to a non-bare repo
start ; $gi show $issue | try_grep '^Tags:.*cloned'

if [ $failed -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
