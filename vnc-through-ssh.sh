#!/bin/bash

# This could be done through port forwarding.  The disadvantages of
# port forwarding are (1) it need to find an unused port, and (2) the
# sshd on the target machine must allow it (which is not always the case!)

sshtarget="$1"

openvnc()
{
    tf=/tmp/tmpfifo
    rm -f $tf
    mkfifo $tf
    exec 22> >(cat >$tf)
    exec 44< $tf
    nc -l 5996 <&44 | ssh "$1" nc 127.0.0.1 $(( $2 + 5900 )) >&22 &
    sleep 1  # sleep long enough for nc to open the listening port
    vncviewer :96 &
}

r1="$(ssh "$sshtarget" ps aux | grep qemu)"

if [ "$2" != "" ]; then
    regex="$2"
    r2="$(echo "$r1" | grep "$regex")"
else
    r2="$r1"
fi

if [ "$r2" == "" ]; then
    echo "$(echo "$vncs" | wc -l) QEMUs, but no matches"
fi

vncs="$(echo "$r2" | grep -o -e 'vnc....[^ ]*')"

echo "Matches:"
echo "$vncs"

count="$(echo "$vncs" | wc -l)"
if [ "$count" -ne 1 ] && [[ "$3" != -f* ]] ; then
    echo 'More than one match.  Make 3rd parameter -f to open all.  (Maybe make second parameter ".")'
    exit 255
fi

while read ln; do
    p1="${ln#*:}"
    p2="${p1% *}"
    openvnc "$sshtarget" "$p2"
done <<<"$vncs"
