#!/bin/bash

# This could be done through port forwarding.  The disadvantages of
# port forwarding are (1) it need to find an unused port, and (2) the
# sshd on the target machine must allow it (which is not always the case!)

# Some machines do not have localhost defined, so 127.0.0.1 seems to
# be a safer default choice for making local TCP connections.  Only
# once have I seen localhost work where 127.0.0.1 did not work, but
# did not have time to verify what was going on.  If things are not
# working and no other reason can be found, it may be worth a trying
# uncommenting the second line below.

localhost_ref=127.0.0.1
# localhost_ref=localhost

usage()
{
    echo "ssh target, then regex, bla, bla, bla..." 1>&2
    exit 255
}

parse-parameters()
{
    while [ "$#" -gt 0 ]; do
	case "$1" in
	    *)
		if [ "$sshtarget" == "" ]; then
		    sshtarget="$1"
		elif [ "$regex" == "" ]; then
		    regex="$1"
		else
		    usage
		fi
		;;
	esac
	shift
    done
}

open-one-vnc()
{
    vncport="$1"
    tf=/tmp/tmpfifo
    rm -f $tf
    mkfifo $tf
    exec 22> >(cat >$tf)
    exec 44< $tf
    nc -l 5996 <&44 | ssh "$sshtarget" nc "$localhost_ref" $(( $vncport + 5900 )) >&22 &
    sleep 1  # sleep long enough for nc to open the listening port
    vncviewer :96 &
}

search-for-vnc-ports()
{
    r1="$(echo 'ps aux | grep qemu' | ssh "$sshtarget")"

    if [ "$regex" != "" ]; then
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
}

open-port-list()
{
    while read ln; do
	p1="${ln#*:}"
	p2="${p1% *}"
	open-one-vnc "$p2"
    done <<<"$vncs"
}

parse-parameters "$@"
search-for-vnc-ports "$@"
open-port-list "$@"
