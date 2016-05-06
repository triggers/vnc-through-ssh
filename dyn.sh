#!/bin/bash

# ssh dyn-hostname-pattern-flags
# ssh dyn-p24-host   # will log into p24
# ssh dyn-p24-19999  # will log into a KVM on p24 with 19999 somewhere in its command line

# Normally hostname should be set up in .ssh/config, but it is
# possible to specify user and IP explicitly.  But the @ character
# messes up the parsing along the way, so it is necessary to
# substitute _ for @.  For example:

# ssh dyn-myid_192.168.1.9-19999 # will log into a 192.168.1.9 as myid
                                 # and find a KVM 19999 somewhere in
                                 # its command line

# Note: so far, loging into KVM only works with machines started with kvmsteps, because
# vnc-through-ssh.sh only knows how to find a matching user and private key for those
# machines.  Will generalize this later....

# ((-flags is currently not used))

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

# e.g.:     dyn    p24     host
IFS=- read prefix user_ip pattern flags <<<"$1"

if [ "$pattern" = "host" ]; then
    # go directly to the hostname
    ssh "${user_ip/_/@}" <&2 >&2 2>>/tmp/dyn.log
else
    # find and connect to a KVM inside the host
    "${abspath%/*}/vnc-through-ssh.sh" "${user_ip/_/@}" "$pattern" -s <&2 >&2 2>>/tmp/dyn.log
fi
