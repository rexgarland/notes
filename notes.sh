#!/usr/bin/env bash

HELP_DOC='Usage:

notes [command] [args]

commands:
- init: initialize the database if needed
- add|insert|new [note]: create a new note and start editing it
- edit [note]
- show|print [note]
- delete [note]
- list: list all notes in the database

args:
- note: the name of a note, without filename extension (can include a folder prefix); e.g. "hello", "work/tasks", etc

environment variables:
- EDITOR: the editor to use (e.g. vim)
- NOTES_DIR (optional): defaults to ~/.note-store

CAVEATS:
- If your editor creates swap files to store temporary changes (e.g. for auto-backup), this will leak sensitive note data outside of the protection of this tool. Make sure to disable swap files for your $EDITOR.
'

NOTES_DIR=${NOTES_DIR:-~/.note-store}

###################### utils ######################

name_to_file() {
	local name=$1
	echo $NOTES_DIR/$name.md
}

get_gpg_id() {
	local gpgfile=$NOTES_DIR/.gpg-id
	cat $gpgfile | tr -d "\n"
}

#################### checkers #####################

check_for_editor() {
	if [[ -z $EDITOR ]]; then
		echo "Please set your EDITOR before using notes."
		exit 1
	fi
}

initialized() {
	if [[ ! -d $NOTES_DIR ]]; then
		return 1
	fi
	local gpgfile=$NOTES_DIR/.gpg-id
	if [[ ! -f $gpgfile ]]; then
		return 1
	fi
	return 0
}

check_for_init() {
	if ! initialized; then
		echo "Notes not initialized. Please run 'notes init <gpg-id>' first."
		exit 1
	fi
}

git_initialized() {
	if [[ ! -d $NOTES_DIR/.git ]]; then
		return 1
	fi

	if [[ ! -f $NOTES_DIR/.gitattributes ]]; then
		return 1
	fi

	return 0
}

check_for_git_init() {
	if ! git_initialized; then
		echo "Git repo not initialized for notes. Run 'notes git init' first."
		exit 1
	fi
}

check_valid_name() {
	local name=$1
	if [[ -z $name ]]; then
		echo "Please specify the note's name."
		exit 1
	fi
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

check_note_exists() {
	local name=$1
	if ! note_exists $name; then
		echo "Could not find note."
		exit 1
	fi
}

check_note_does_not_exist() {
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
	if git_initialized; then
		echo "Notes repo already initialized."
		exit 1
	fi

	cd $NOTES_DIR
	git init
	echo "*.gpg diff=gpg" >>.gitattributes
	cd - >/dev/null
}

list_notes() {
	tree -C --noreport $NOTES_DIR | tail -n +2 | sed 's#.md.gpg##' | cat <(echo "Notes store:") -
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

	edit_note $name
}

edit_note() {
	local name=$1
	local file=$(name_to_file $name)
	local gpgfile=$file.gpg

	if ! decrypt $gpgfile >$file; then
		if [[ -f $file ]]; then
			rm $file
		fi
		echo "Could not decrypt note."
		exit 1
	fi

	if ! $EDITOR $file; then
		if [[ -f $file ]]; then
			rm $file
		fi
		echo "Editor errored out. Ignored changes to note."
		exit 1
	fi

	cp $gpgfile $gpgfile.backup
	rm $gpgfile
	if ! encrypt $file; then
		cp $gpgfile.backup $gpgfile
		echo "Could not encrypt note. Reverted to previous version."
	fi
	rm $gpgfile.backup

	rm $file
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
	if git_initialized; then
		run_git_command add .
		run_git_command commit -m "save"
	fi
}

main_git() {
	local cmd=$1
	if [[ "$cmd" = "init" ]]; then
		initialize_git
	else
		check_for_git_init
		run_git_command $@
	fi
}

###################### main #######################

main() {
	check_for_editor

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

	show | print)
		check_for_init
		local name=$2
		check_valid_name $name
		check_note_exists $name
		print_note $name
		;;

	add | insert | new)
		check_for_init
		local name=$2
		check_note_does_not_exist $name
		add_note $name
		commit
		;;

	edit)
		check_for_init
		local name=$2
		check_note_exists $name
		edit_note $name
		commit
		;;

	delete)
		check_for_init
		local name=$2
		check_valid_name $name
		check_note_exists $name
		delete_note $name
		commit
		;;

	list)
		check_for_init
		list_notes
		;;

	git)
		check_for_init
		shift
		local args="$@"
		main_git $args
		;;

	*)
		check_for_init
		if [[ -z $cmd ]]; then
			list_notes
		else
			local name=$1
			if note_exists $name; then
				print_note $name
			else
				echo "Unknown command. Run 'notes -h' for help."
				exit 1
			fi
		fi
		;;
	esac
}

main "$@"
