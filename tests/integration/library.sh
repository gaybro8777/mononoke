#!/bin/bash
# Library routines and initial setup for Mononoke-related tests.

function get_free_socket {

# From https://unix.stackexchange.com/questions/55913/whats-the-easiest-way-to-find-an-unused-local-port
  cat >> "$TESTTMP/get_free_socket.py" <<EOF
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('', 0))
addr = s.getsockname()
print(addr[1])
s.close()
EOF

  python "$TESTTMP/get_free_socket.py"
}

function mononoke {
  export MONONOKE_SOCKET
  MONONOKE_SOCKET=$(get_free_socket)
  "$MONONOKE_SERVER" "$@" --debug --listening-host-port 127.0.0.1:"$MONONOKE_SOCKET" -P "$TESTTMP/mononoke-config-rocks" --configrepo_book local_master >> "$TESTTMP/mononoke.out" 2>&1 &
  echo $! >> "$DAEMON_PIDS"
}

# Wait until a Mononoke server is available for this repo.
function wait_for_mononoke {
  local attempts=150
  for _ in $(seq 1 $attempts); do
    curl 127.0.0.1:"$MONONOKE_SOCKET" 2>&1 | grep -q 'Empty reply' && break
    sleep 0.1
  done

  if ! curl 127.0.0.1:"$MONONOKE_SOCKET" 2>&1 | grep -q 'Empty reply'; then
    echo "Mononoke did not start" >&2
    cat "$TESTTMP/mononoke.out"
    exit 1
  fi
}

function setup_common_config {
    setup_config_repo
  cat >> "$HGRCPATH" <<EOF
[ui]
ssh="$DUMMYSSH"
[extensions]
remotefilelog=
[remotefilelog]
cachepath=$TESTTMP/cachepath
EOF
}

function setup_config_repo {
  hg init mononoke-config
  cd mononoke-config || exit
  cat >> .hg/hgrc <<EOF
[extensions]
treemanifest=
remotefilelog=
[treemanifest]
server=True
[remotefilelog]
server=True
shallowtrees=True
EOF

  mkdir repos
  cat > repos/repo <<CONFIG
path="$TESTTMP/repo"
repotype="blob:rocks"
repoid=0
CONFIG
  hg add -q repos
  hg ci -ma
  hg backfilltree
  hg book local_master
  cd ..

  # We need to have a RocksDb version of config repo
  mkdir mononoke-config-rocks
  $MONONOKE_NEWBLOBIMPORT --repo_id 0 --blobstore rocksdb mononoke-config/.hg mononoke-config-rocks >> "$TESTTMP/mononoke-config-blobimport.out" 2>&1
}

function newblobimport {
  reponame=$2
  mkdir -p "$reponame"
  $MONONOKE_NEWBLOBIMPORT --repo_id 0 --blobstore rocksdb "$@" >> "$TESTTMP/blobimport.out" 2>&1
}

function edenserver {
  $MONONOKE_EDEN_SERVER "$@" >> "$TESTTMP/edenserver.out" 2>&1 &
  echo $! >> "$DAEMON_PIDS"
}

# Run an hg binary configured with the settings required to talk to Mononoke.
function hgmn {
  hg --config ui.ssh="$DUMMYSSH" --config paths.default=ssh://user@dummy/repo --config ui.remotecmd="$MONONOKE_HGCLI" "$@"
}

function hgmn_show {
  echo "LOG $*"
  hgmn log --template 'node:\t{node}\np1node:\t{p1node}\np2node:\t{p2node}\nauthor:\t{author}\ndate:\t{date}\ndesc:\t{desc}\n\n{diff()}' -r "$@"
  hgmn update "$@"
  echo
  echo "CONTENT $*"
  find . -type f -not -path "./.hg/*" -print -exec cat {} \;
}

function hginit_treemanifest() {
  hg init "$@"
  cat >> "$1"/.hg/hgrc <<EOF
[extensions]
treemanifest=
remotefilelog=
smartlog=
[treemanifest]
server=True
sendtrees=True
[remotefilelog]
reponame=$1
cachepath=$TESTTMP/cachepath
server=True
shallowtrees=True
EOF
}

function hgclone_treemanifest() {
  hg clone -q --shallow --config remotefilelog.reponame=master "$@"
  cat >> "$2"/.hg/hgrc <<EOF
[extensions]
treemanifest=
remotefilelog=
fastmanifest=
smartlog=
[treemanifest]
sendtrees=True
treeonly=True
[remotefilelog]
reponame=$2
cachepath=$TESTTMP/cachepath
shallowtrees=True
EOF
}

function enableextension() {
  cat >> .hg/hgrc <<EOF
[extensions]
$1=
EOF
}

function setup_hg_server() {
  cat >> .hg/hgrc <<EOF
[extensions]
treemanifest=
remotefilelog=
[treemanifest]
server=True
[remotefilelog]
server=True
shallowtrees=True
EOF
}

function setup_hg_client() {
  cat >> .hg/hgrc <<EOF
[extensions]
treemanifest=
remotefilelog=
[treemanifest]
server=False
treeonly=True
[remotefilelog]
server=False
reponame=repo
EOF
}
