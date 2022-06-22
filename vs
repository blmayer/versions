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
  vs init mydomain.com/projectx

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
	mkdir -p .vs/commits
	mkdir .vs/cur
	echo "remote=${1%/*}:${1#*/}" > .vs/config
}

status() {
	[ -f "$vsdir/stage" ] && echo "Staged files:" | cat - "$vsdir/stage" 

	for f in "$(find $vsdir/cur/* -type f)"
	do
		rf="$(realpath $f --relative-to $vsdir/cur)"
		debug "checking $rf"
		diff -q "$f" "$rf" > /dev/null || echo "Changed file: $rf"
	done

	# TODO: improve output
	diff --brief --recursive "$vsdir/cur/" "$rootdir" --exclude ".vs"
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
	lastcommit="$(ls -1 "$vsdir/commits/*" | tail -n 1)"
	curcommit="$((lastcommit + 1))"
	mkdir -p "$vsdir/commits/$curcommit/"
	debug "creating commit $curcommit"

	echo "Commit message:"
	read -r msg
	echo "$msg" > "$vsdir/commits/$curcommit/message"
	debug "message: $msg"

	while read -r s
	do
		rs="$(realpath $s --relative-to $vsdir)"
		echo "$s"
		diff -uNd "$s" "$vsdir/cur/$rs" >> "$vsdir/commits/$curcommit/diff"
		[ -d "$(dirname $vsdir/cur/$s)" ] || mkdir "$(dirname $vsdir/cur/$s)"
		cp "$s" "$vsdir/cur/$s"
	done < "$vsdir/stage"
	rm "$vsdir/stage"
}

reset() {
	cp -R "$vsdir/cur/*" $rootdir
}

[ $1 = "init" ] && init "$2" && exit 0

findvs
rootdir="${vsdir%/.vs}"
debug "vsdir=$vsdir rootdir=$rootdir"
case "$1" in
	"add") shift && add "$*" ;;
	"commit") commit ;;
	"reset") reset ;; 
	"") status ;; 
	"help"|*) usage ;; 
esac

