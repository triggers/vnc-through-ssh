#!/bin/bash

# ssh dyn-user@IP-pattern-flags
# ssh dyn--p24-19999-r

# the python code duplicates "readlink -f" functionality, but is portable to OSX.
# from: http://stackoverflow.com/questions/1055671/how-can-i-get-the-behavior-of-gnus-readlink-f-on-a-mac
#   this answer-> http://stackoverflow.com/a/1115074
abspath="$(python -c 'import os,sys;print os.path.realpath(sys.argv[1])' "$0")"

if [[ "$1" == *setup ]]; then
    cat >> ~/.ssh/config <<EOF

host dyn-*
  ProxyCommand "$abspath" "%h" "%p"
EOF
    exit
fi
set -x
IFS=- read prefix user_ip pattern flags <<<"$1"

if [ "$pattern" = "host" ]; then
    ssh "$user_ip" <&2 >&2 2>>/tmp/dyn.log
else
    "${abspath%/*}/vnc-through-ssh.sh" "$user_ip" "$pattern" -s <&2 >&2 2>>/tmp/dyn.log
fi
