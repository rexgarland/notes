#!/usr/bin/env bash

HELP_DOC='Usage:

notes [command] [args]

commands:
- init: initialize the database if needed
- git init: initialize a git repo to automatically track changes
- list|"": list all notes in the database (default command)
- add|insert|new <name>: create a new note and start editing it
- edit <name>: edit a note, creating it first if needed
- show|print <name>: print decrypted note to stdout
- delete|remove <name>: remove a note
- clean: remove any plaintext files in the notes store

git commands:
- git init: initialize a git repo in NOTES_DIR to track all changes going forward
- git <anything>: run any other git command from within NOTES_DIR

args:
- note: the name of a note, without filename extension (can include a folder prefix); e.g. "hello", "work/tasks", etc

environment variables:
- EDITOR: the editor to use (e.g. vim)
- NOTES_DIR (optional): defaults to $HOME/.note-store

CAVEATS:
- If your editor creates swap files to store temporary changes (e.g. for auto-backup), this will leak sensitive note data outside of the protection of this tool. Make sure to disable swap files for your $EDITOR.
'

NOTES_DIR=${NOTES_DIR:-$HOME/.note-store}

###################### utils ######################

name_to_file() {
	local name=$1
	echo $NOTES_DIR/$name.md
}

get_gpg_id() {
	local gpgfile=$NOTES_DIR/.gpg-id
	cat $gpgfile | tr -d "\n"
}

is_store_initialized() {
	if [[ ! -d $NOTES_DIR ]]; then
		return 1
	fi
	local gpgfile=$NOTES_DIR/.gpg-id
	if [[ ! -f $gpgfile ]]; then
		return 1
	fi
	return 0
}

is_git_initialized() {
	if [[ ! -d $NOTES_DIR/.git ]]; then
		return 1
	fi

	if [[ ! -f $NOTES_DIR/.gitattributes ]]; then
		return 1
	fi

	return 0
}

note_exists() {
	local name=$1
	local file=$(name_to_file $name)
	local gpgfile=$file.gpg

	if [[ ! -f $gpgfile ]]; then
		return 1
	else
		return 0
	fi
}

#################### assertions #####################

ensure_editor_is_set() {
	if [[ -z $EDITOR ]]; then
		echo "Please set your EDITOR before using notes."
		exit 1
	fi
}

ensure_store_initialized() {
	if ! is_store_initialized; then
		echo "Notes not initialized. Please run 'notes init <gpg-id>' first."
		exit 1
	fi
}

ensure_git_initialized() {
	if ! is_git_initialized; then
		echo "Git repo not initialized for notes. Run 'notes git init' first."
		exit 1
	fi
}

ensure_valid_name() {
	local name=$1
	if [[ -z $name ]]; then
		echo "Please specify the note's name."
		exit 1
	fi
}

ensure_note_exists() {
	local name=$1
	if ! note_exists $name; then
		echo "Could not find note."
		exit 1
	fi
}

ensure_note_does_not_exist() {
	local name=$1
	if note_exists $name; then
		echo "Note already exists"
		exit 1
	fi
}

################### encryption ####################

encrypt() {
	local file=$1
	local gpgid=$(get_gpg_id)
	if ! gpg --recipient "$gpgid" --encrypt $file; then
		if [[ -f $file.gpg ]]; then
			rm $file.gpg
		fi
		echo "Could not encrypt note. This could be an issue with your gpg-id."
		return 1
	fi
}

decrypt() {
	local file=$1
	gpg --decrypt --quiet $file
}

##################### actions #####################

init_with_gpg_id() {
	local gpgid=$1
	mkdir -p $NOTES_DIR
	echo $gpgid >$NOTES_DIR/.gpg-id
}

initialize_git() {
	if is_git_initialized; then
		echo "Notes repo already initialized."
		exit 1
	fi

	cd $NOTES_DIR
	git init
	echo "*.gpg diff=gpg" >>.gitattributes
	echo "**/*.md" >>.gitignore
	cd - >/dev/null
}

list_notes() {
	echo "Notes store:"
	# Elide .md.gpg, highlight plaintext files in red
	tree -C --noreport $NOTES_DIR | tail -n +2 | sed 's#.md.gpg##' | sed -r 's#([A-z]*.md)#\x1b[1;91\1\x1b[0m#'
	# See https://git.zx2c4.com/password-store/tree/src/password-store.sh (around line 405, search "tree") for another example
}

print_note() {
	local name=$1
	local file=$(name_to_file $name)
	local gpgfile=$file.gpg
	decrypt $gpgfile
}

add_note() {
	local name=$1
	local file=$(name_to_file $name)
	local folder=$(dirname $file)

	mkdir -p $folder
	echo -n "" >$file
	if ! encrypt $file; then
		rm $file
		exit 1
	fi
}

remove_all_plaintext() {
	cd $NOTES_DIR
	# delete files not matching the "*.md.gpg" format, ignoring protected files
	# https://unix.stackexchange.com/questions/96432/find-files-not-matching-list-of-filename-patterns
	# https://stackoverflow.com/questions/4210042/how-do-i-exclude-a-directory-when-using-find
	files_PLAINTEXT="$(find . -type f \! \( -path "./*.md.gpg" -o -path "./.git/*" -o -name ".gitignore" -o -name ".gitattributes" -o -name ".gpg-id" \))"
	echo "$files_PLAINTEXT" | xargs -n1 rm
	cd - >/dev/null
}

edit_note() {
	local name=$1
	local file_PLAINTEXT=$(name_to_file $name)
	local gpgfile=$file_PLAINTEXT.gpg

	# decrypt note to temporary plaintext file

	if ! decrypt $gpgfile >$file_PLAINTEXT; then
		if [[ -f $file_PLAINTEXT ]]; then
			rm $file_PLAINTEXT # always remove plaintext
		fi
		echo "Could not decrypt note."
		exit 1
	fi

	# edit plaintext

	if ! $EDITOR $file_PLAINTEXT; then
		if [[ -f $file_PLAINTEXT ]]; then
			rm $file_PLAINTEXT # always remove plaintext
		fi
		echo "Editor bailed. Ignored changes to note."
		exit 1
	fi

	# encrypt back

	cp $gpgfile $gpgfile.backup
	rm $gpgfile
	if ! encrypt $file_PLAINTEXT; then
		cp $gpgfile.backup $gpgfile
		echo "Could not encrypt note. Reverted to previous version."
	fi
	rm $gpgfile.backup

	# remove temp plaintext file

	rm $file_PLAINTEXT
}

delete_note() {
	local name=$1
	local file=$(name_to_file $name)
	local gpgfile=$file.gpg
	rm $gpgfile
}

run_git_command() {
	cd $NOTES_DIR
	git $@
	cd - >/dev/null
}

commit() {
	if is_git_initialized; then
		run_git_command add .
		run_git_command commit -m "save"
	fi
}

main_git() {
	local cmd=$1
	if [[ "$cmd" = "init" ]]; then
		initialize_git
	else
		ensure_git_initialized
		run_git_command $@
	fi
}

###################### main #######################

main() {
	ensure_editor_is_set

	local cmd=$1

	case $cmd in
	-h)
		echo "$HELP_DOC"
		;;

	init)
		local gpgid=${2:?Please specify a gpg id.}
		init_with_gpg_id $gpgid
		commit
		;;

	show | print | cat)
		ensure_store_initialized
		local name=$2
		ensure_valid_name $name
		ensure_note_exists $name
		print_note $name
		;;

	add | insert | new)
		ensure_store_initialized
		local name=$2
		ensure_note_does_not_exist $name
		add_note $name
		edit_note $name
		commit
		;;

	edit)
		ensure_store_initialized
		local name=$2
		if ! note_exists $name; then
			add_note $name
		fi
		edit_note $name
		commit
		;;

	delete | remove)
		ensure_store_initialized
		local name=$2
		ensure_valid_name $name
		ensure_note_exists $name
		delete_note $name
		commit
		;;

	list | ls)
		ensure_store_initialized
		list_notes
		;;

	git)
		ensure_store_initialized
		shift
		local args="$@"
		main_git $args
		;;

	clean)
		ensure_store_initialized
		remove_all_plaintext
		;;

	*)
		ensure_store_initialized
		if [[ -z $cmd ]]; then
			list_notes
		else
			local name=$1
			if note_exists $name; then
				print_note $name
			else
				printf "Unknown command '%s'. Run 'notes -h' for help." $cmd
				exit 1
			fi
		fi
		;;
	esac
}

main "$@"
