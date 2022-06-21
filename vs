#!/usr/bin/sh

usage() {
	cat << EOF
Usage: vs [COMMAND]... FILES
A very simple version control

Available commands:
  init         initialize a vs repo
  status       show repo status
  add <glob>   add files to staging area
  commit       commit files in staging area
  reset        discard changes and restore to the last commit
  get          get commits from the server
  send         send commits to the remote server
  help         show this help

Most configuration can be done by directly editing the config file in
the .vs folder, in the root of your initialized repo.
EOF
}

debug() {
	[ "$TRACE" ] && echo "$*" >&2
}

findvs() {
	debug "findvs in $(pwd)"
	[ -d .vs ] && echo "$(realpath .vs)" && return 0
	cd ..
	findvs 
}

init() {
	[ -d .vs ] && echo "vs already present" && exit -1
	mkdir -p .vs/commits
	mkdir .vs/cur
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
		[ -d "$rf" ] && add "$rf"
		grep -q "$rf" "$vsdir/stage" || echo "$rf" >> "$vsdir/stage"
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

vsdir="$(findvs)"
rootdir="${vsdir%/.vs}"
case "$1" in
	"add") shift && add "$*" ;;
	"init") init ;;
	"commit") commit ;;
	"help") usage ;; 
	"reset") reset ;; 
	"") status ;; 
esac

