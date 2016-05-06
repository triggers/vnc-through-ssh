#!/bin/bash

# ssh dyn-user@IP-pattern-flags
# ssh dyn--p24-19999-r

abspath="$(readlink -f "$0")"

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
