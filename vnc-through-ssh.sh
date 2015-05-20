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
    cat <<'EOF'
Documentation below is just rough notes.  Please ask me directly
if you have any questions.

-----------------------

If only one qemu process is running on some remote host, then using
that hostname as the only parameter will connect a local vncviewer to
that qemu's console.

Basic functionality is:
 (1) discovery of remote vnc port(s)
 (2) oneshot forwarding of temporary local port to vnc port(s)
 (3) connection of vncviewer(s) to the local port(s)

The are two positional parameters.  The first is required and is a
bash expression that can open up a shell either locally or remotely.
If the expression consists of only one token, it is assumed to be an
ssh target, and "ssh" is automatically prepended.  Therefore, if bash
is used as the expression (e.g., to search for vnc ports on the local
machine), then it must be artificially made into more than one token,
e.g. "bash -e", or "eval bash" will keep ssh from being prepended.

The second positional parameter is optional and is a regular
expression that is used to filter the listing of qemu processes to
only those whose parameter list matches the regular expression.

These extra options are possible:
  --just-list    Skip steps 2 and 3, and just output all qemu processes that match regex
  --all          When the regular expression selects more than one KVM process, connect
                 a separate vncviewer to each of them.

-----------------------

Documentation above is just rough notes.  Please ask me directly
if you have any questions.

EOF
    exit 255
}

parse-parameters()
{
    doall=false
    justlist=false
    while [ "$#" -gt 0 ]; do
	case "$1" in
	    --help)
		usage
	    ;;
	    -a | --all | --do-all)
		doall=true
	    ;;
	    -l | --ls | --jl | --just-list)
		justlist=true
	    ;;
	    *)
		if [ "$eval_for_shell" == "" ]; then
		    eval_for_shell="$1"
		    read token1 moretokens <<<"$eval_for_shell"
		    # If only one token, assume it is an ssh target
		    # possibly setup by ssh config.
		    [ "$moretokens" == "" ] && eval_for_shell="ssh $eval_for_shell"
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
    (echo "nc $localhost_ref $(( $vncport + 5900 ))" ; nc -l 5996) <&44 | eval "$eval_for_shell"  >&22 &
    sleep 1  # sleep long enough for nc to open the listening port
    vncviewer :96 &
}

search-for-vnc-ports()
{
    r1="$(echo 'ps aux | grep qemu' | eval "$eval_for_shell")"

    if [ "$regex" != "" ]; then
	r2="$(echo "$r1" | grep "$regex")"
    else
	r2="$r1"
    fi

    if $justlist; then
	echo "$r2"
	exit 0
    fi
    
    if [ "$r2" == "" ]; then
	echo "$(echo "$vncs" | wc -l) QEMUs, but no matches"
    fi
    
    vncs="$(echo "$r2" | grep -o -e 'vnc....[^ ]*')"
    
    echo "Matches:"
    echo "$vncs"
    
    count="$(echo "$vncs" | wc -l)"
    if [ "$count" -ne 1 ] && ! $doall ; then
	echo 'More than one match.  Use -a option to open all.'
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
