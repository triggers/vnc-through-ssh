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

exec 9>>/tmp/for-vnc-through-ssh-cleanup

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
  --just-list         Skip steps 2 and 3, and just output all qemu processes that match regex
  --all               When the regular expression selects more than one KVM process, connect
                      a separate vncviewer to each of them.
  --remote-port 5911  Skip step 1 and just connect vncviewer to the remote port given

Also, these options are for debugging and execute immediately without starting connections:
  --check             Show processes started by this script
  --cleanup           Kill processes started by this script

-----------------------

Documentation above is just rough notes.  Please ask me directly
if you have any questions.

EOF
    exit 255
}

parse-parameters()
{
    localport=""
    remoteport=""
    doall=false
    justlist=false
    portgoal=vnc  # either vnc or monitor
    while [ "$#" -gt 0 ]; do
	case "$1" in
	    --help)
		usage
	    ;;
	    --check)
		exec 9>&-
		lsof /tmp/for-vnc-through-ssh-cleanup
		exit
	    ;;
	    --cleanup)
		exec 9>&-
		lsof /tmp/for-vnc-through-ssh-cleanup | (
		    read headerline
		    while read a b c ; do
			printf "killing%6d %s\n" $b $a
			kill $b
		    done )
		exit
	    ;;
	    --lp | --local*port)
		localport="$2"
		shift
	    ;;
	    -p | --rp | --remote*port)
		remoteport="$2"
		shift
	    ;;
	    -a | --all | --do-all)
		doall=true
	    ;;
	    -l | --ls | --jl | --just-list)
		justlist=true
	    ;;
	    -m | --monitor)
		portgoal=monitor
	    ;;
	    *)
		if [ "$eval_for_shell" == "" ]; then
		    eval_for_shell="$1"
		    read token1 moretokens <<<"$eval_for_shell"
		    # If only one token, assume it is an ssh target
		    # possibly setup by ssh config.
		    [ "$moretokens" == "" ] && eval_for_shell="ssh -T $eval_for_shell"
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
    ( # subshell is necessary to generate new 22 and 44 file descriptors
	vncport="$1"

	tf=/tmp/tmpfifo
	rm -f $tf
	mkfifo $tf
	exec 22> >(cat >$tf)
	exec 44< $tf

	# Randomize the temporary port because MacOS's nc will queue
	# multiple server requests to the same port, instead of
	# failing as on Linux.  This can make the behavior very
	# confusing when vncviewer launching fails for some reason.
	# It also makes it difficult to test properly for a free port.
	# This random solution still leaves a small chance an inuse
	# port will be chosen.  The code skips the common vnc port
	# choices (5900-5999) to reduce this chance.
	rand=$(( $RANDOM  % 2000 ))
	lport=$(( 5900 + 100 + rand )) 
	[ "$localport" != "" ] && lport="$localport"

	(echo "nc $localhost_ref $vncport" ; nc -l "$lport") <&44 | eval "$eval_for_shell"  >&22 &
	if [ "$localport" == "" ]; then
	    sleep 0.2  # sleep long enough for nc to open the listening port
	    vncviewer ":$lport" &
	fi
    )
}

search-for-vnc-ports()
{
    r1="$(echo 'ps aux | grep qem[u]' | eval "$eval_for_shell")"

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
	exit 255
    fi
    
    vncs="$(echo "$r2" | grep -o -e 'vnc....[^ ]*')"
    
    echo "Matches:"
    # Filter output to only show a few key qemu parameters:
    while read ln; do
	for token in $ln; do
	    echo "$token"
	done | (
	    read theuser
	    read thepid
	    printf "%-10s %8s " "$theuser" "$thepid"
	    
	    while read token2; do
		case "$token2" in
		    -vnc|-name)
			read info
			echo -n "$token2 $info  "
			;;
		    -drive)
			read driveinfo
			echo -n "$token2 ${driveinfo%%,*}  "
			;;
		esac
	    done
	)
	echo
    done <<<"$r2"
    
    count="$(echo "$vncs" | wc -l)"
    if [ "$count" -ne 1 ] && [ "$localport" == "" ] &&  ! $doall ; then
	echo 'More than one match.  Use -a option (and no --lp option) to open all.'
	exit 255
    fi
}

open-port-list()
{
    while read ln; do
	p1="${ln#*:}"
	p2="${p1% *}"
	open-one-vnc $(( p2 + 5900 ))
    done <<<"$vncs"
}

search-for-monitor-ports()
{
    r1="$(echo 'ps aux | grep qem[u]' | eval "$eval_for_shell")"

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
	exit 255
    fi
    
    monitors="$(echo "$r2" | grep -o -e '-monitor....[^ ]*')"

    echo "Matches:"
    # Filter output to only show a few key qemu parameters:
    while read ln; do
	for token in $ln; do
	    echo "$token"
	done | (
	    read theuser
	    read thepid
	    printf "%-10s %8s " "$theuser" "$thepid"
	    
	    while read token2; do
		case "$token2" in
		    -vnc|-name|-monitor)
			read info
			echo -n "$token2 $info  "
			;;
		    -drive)
			read driveinfo
			echo -n "$token2 ${driveinfo%%,*}  "
			;;
		esac
	    done
	)
	echo
    done <<<"$r2"

    if $doall; then
	echo "-do-all option not supported for connecting to KVM monitors yet"
	exit 255
    fi

    count="$(echo "$monitors" | wc -l)"
    if [ "$count" -ne 1 ] && [ "$localport" == "" ] &&  ! $doall ; then
	echo 'More than one match.  Use -a option (and no --lp option) to open all.'
	exit 255
    fi
}

parse-parameters "$@"
# There seem to be so many subtle differences between connecting
# to vnc and connecting to the monitor, that code reuse will
# probably be difficult.  Therefore the first draft of this
# will be done by copy/paste/edit.
if [ "$portgoal" == "vnc" ]; then
    if [[ "$remoteport" == "" ]]; then
	search-for-vnc-ports "$@"
	open-port-list "$@"
    else
	open-one-vnc "$remoteport"
    fi
else
    if [[ "$remoteport" == "" ]]; then
	search-for-monitor-ports "$@"
#	open-port-list-for-monitor "$@"
    else
	:
#	open-one-monitor "$remoteport"
    fi
fi
