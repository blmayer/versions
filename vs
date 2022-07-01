#!/usr/bin/sh

usage() {
	cat << EOF
Usage: vs [COMMAND]... FILES
A very simple version control

Available commands:
  init <path>  initialize a vs repo using path as remote and name
  status       show repo status
  add <glob>   add files to staging area
  del <glob>   remove files from staging area
  diff <glob>  show changes for glob
  commit       commit files in staging area
  reset        discard changes and restore to the last commit
  get          get commits from the server
  send         send commits to the remote server
  help         show this help

Notes:
  - the remote address must be on your ssh config.

Most configuration can be done by directly editing the config file in
the .vs folder, in the root of your initialized repo.

Examples:
To initialize a repo named projectx on mydomain.com use:
  vs init mydomain.com:projectx

EOF
}

debug() {
	[ "$TRACE" ] && echo "$*" >&2
}

findvs() {
	debug "findvs in $(pwd)"
	[ -d .vs ] && vsdir="$(realpath .vs)" && return 0
	[ $PWD = "/" ] && echo "not in a repo" && exit 0
	cd ..
	findvs 
}

init() {
	debug "init with $1"
	[ -d .vs ] && echo "vs already present" && exit -1
	[ -z "$1" ] && echo "missing remote repo path" && exit -2
	mkdir -p .vs/commits .vs/remote .vs/cur
	{
		echo "remote=${1%:*}"
		echo "repo=${1#*:}"
	} >> .vs/config
	echo 0 > .vs/rhead

	echo "initializing remote"
	ssh "$remote" "mkdir -p $repo/files && echo 0 > $repo/head"
}

status() {
	read -r head < "$vsdir/head"
	echo "on commit $head"

	rrhead="$(ssh $remote "cat $repo/head")"
	[ -z "$rrhead" ] || echo "remote is on commit $rrhead"

	[ -f "$vsdir/stage" ] && echo "Staged files:" | cat - "$vsdir/stage" 

	for f in $(find $vsdir/cur/ -type f)
	do
		# TODO: try with $rootdir, looks better
		rf="$(realpath $f --relative-to $vsdir/cur)"
		debug "checking $rf"
		diff -q "$f" "$rf" > /dev/null || echo "Changed file: $rf"
	done

	# TODO: improve output
	diff --brief --recursive "$vsdir/cur/" "$rootdir" --exclude ".vs"
}

dif() {
	for f in $*
	do
		debug "checking $f"
		diff -u "$f" "$vsdir/cur/$f"
	done
}

add() {
	[ -f "$vsdir/stage" ] || touch "$vsdir/stage"
	for f in $*
	do
		rf="$(realpath $f --relative-to $rootdir)"
		debug "adding $rf"
		[ -d "$rf" ] && add "$rf/*"
		grep -q "$rf" "$vsdir/stage" || echo "$rf" >> "$vsdir/stage"
	done
}

del() {
	[ -f "$vsdir/stage" ] || return 0
	for f in $*
	do
		rf="$(realpath $f --relative-to $vsdir/..)"
		debug "removing $rf"
		[ -d "$rf" ] && del "$rf/*"
		grep -v "$rf" "$vsdir/stage" >> "$vsdir/stage.temp"
		mv "$vsdir/stage.temp" "$vsdir/stage"
	done
}

commit() {
	[ ! -z "$*" ] && add "$*"

	echo "commiting:"
	cat "$vsdir/stage"

	read -r head < "$vsdir/head"
	curcommit="$((head + 1))"
	mkdir -p "$vsdir/commits/$curcommit/"
	debug "creating commit $curcommit"

	echo "Commit message:"
	read -r msg
	echo "$msg" > "$vsdir/commits/$curcommit/message"
	debug "message: $msg"

	while read -r s
	do
		diff -uNd "$vsdir/cur/$s" "$s" >> "$vsdir/commits/$curcommit/diff"
	done < "$vsdir/stage"

	rm "$vsdir/stage"
	patch -ud "$vsdir/cur/" < "$vsdir/commits/$curcommit/diff"
	echo "$curcommit" > "$vsdir/head"
}

reset() {
	[ -z "$*" ] && reset ./*
	for f in $*
	do
		cp -R "$vsdir/cur/$f" "$rootdir"
	done
}

get() {
	[ "$1" = "-f" ] && force="1" && debug "forcing"
	for f in $(find $vsdir/cur/ -type f)
	do
		[ -z "$f" ] && continue

		# TODO: try with $rootdir, looks better
		rf="$(realpath $f --relative-to $vsdir/cur)"
		debug "checking $rf with $f"
		
		diff -q "$f" "$rf" > /dev/null
		if [ $? ] && [ ! $force ]
		then	
			echo "you have changes, it can be disastrous, run with -f to force"
			exit 3
		fi
	done

	read -r rhead < "$vsdir/rhead"
	read -r head < "$vsdir/head"
	debug "head=$head rhead=$rhead"
	[ $head -lt $rhead ] && "you have local commits, send first" && exit 4

	rrhead="$(ssh $remote "cat $repo/head")"
	[ -z "$rrhead" ] && echo "head not found in remote" && exit 5
	for c in $(seq $((rhead+1)) $rrhead)
	do
		echo "getting commit $c"
		scp "$remote:$repo/$c/diff" "$vsdir/remote/diff"
		patch -ud "$rootdir/" < "$vsdir/remote/diff"
		rm "$vsdir/remote/diff"
		echo "$c" > "$vsdir/rhead"
	done
}

send() {
	read -r rhead < "$vsdir/rhead"
	rrhead="$(ssh -q $remote "cat $repo/head")"
	debug "rhead=$rhead rrhead=$rrhead"
	[ $rrhead -gt $rhead ] && echo "remote has more commits, get first" && exit 6

	echo "checking commit $rhead"
	scp "$remote:$repo/$rhead/diff" "$vsdir/remote/diff"
	rsum="$(md5sum $_ | cut -d ' ' -f 1)"
	csum="$(md5sum $vsdir/commits/$rhead/diff | cut -d ' ' -f 1)"
	rm "$vsdir/remote/diff"
	[ ! "$rsum" = "$csum" ] && echo "commit $rhead is different on remote" && exit 7

	read -r head < "$vsdir/head"
	for c in $(seq $((rhead+1)) $head)
	do
		echo "sending commit $c"
		scp -r "$vsdir/commits/$c" "$remote:$repo/"
		ssh "$remote" "patch -ud "$repo/files/" < "$repo/$c/diff""

		echo "$c" > "$vsdir/rhead"
		ssh "$remote" "echo $c > $repo/head"
	done
}

[ ! -z $1 ] && [ $1 = "init" ] && init "$2" && exit 0

findvs
rootdir="${vsdir%/.vs}"

# this loads remote and repo from the config file
source "$vsdir/config"
debug "config: vsdir=$vsdir rootdir=$rootdir remote=$remote repo=$repo"
case "$1" in
	""|"status") status ;; 
	"diff") shift && dif "$*" ;;
	"add") shift && add "$*" ;;
	"del") shift && del "$*" ;;
	"get") shift && get "$*" ;;
	"commit") shift && commit "$*" ;;
	"reset") shift && reset "$*" ;; 
	"send") send ;; 
	"help"|*) usage ;; 
esac

