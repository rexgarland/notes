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
'

NOTES_DIR=${NOTES_DIR:-~/.note-store}

name_to_file() {
	local name=$1
	echo $NOTES_DIR/$name.md
}

check_for_init() {
	if [[ ! -d $NOTES_DIR ]]; then
		echo "Notes not initialized yet. Please run init first."
		exit 1
	fi
	local gpgfile=$NOTES_DIR/.gpg-id
	if [[ ! -f $gpgfile ]]; then
		echo "Could not find gpg id. Please rerun initialization."
		exit 1;
	fi
}

delete_note() {
	local name=$1
	local file=$(name_to_file $name)
	local gpgfile=$file.gpg
	rm $gpgfile
}

check_note_exists() {
	local name=$1
	local file=$(name_to_file $name)
	local gpgfile=$file.gpg

	if [[ ! -f $gpgfile ]]; then
		echo "Could not find note."
		exit 1
	fi
}

get_gpg_id() {
	local gpgfile=$NOTES_DIR/.gpg-id
	cat $gpgfile | tr -d "\n"
}

encrypt() {
	local file=$1
	local gpgid=$(get_gpg_id)
	if ! gpg --recipient "$gpgid" --encrypt $file
	then
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

edit_note() {
	local name=$1
	local file=$(name_to_file $name)
	local gpgfile=$file.gpg
	
	if ! decrypt $gpgfile >$file
	then
		if [[ -f $file ]]; then
			rm $file
		fi
		echo "Could not decrypt note."
		exit 1
	fi

	if ! $EDITOR $file
	then
		if [[ -f $file ]]; then
			rm $file
		fi
		echo "Editor errored out. Ignored changes to note."
		exit 1
	fi

	cp $gpgfile $gpgfile.backup
	rm $gpgfile
	if ! encrypt $file
	then
		cp $gpgfile.backup $gpgfile
		echo "Could not encrypt note. Reverted to previous version."
	fi
	rm $gpgfile.backup

	rm $file
}

add_note() {
	local name=$1
	local file=$(name_to_file $name)
	local folder=$(dirname $file)

	mkdir -p $folder
	echo -n "" > $file
	if ! encrypt $file
	then
		rm $file
		exit 1
	fi
	
	edit_note $name
}

list_notes() {
	tree -C --noreport $NOTES_DIR | tail -n +2 | sed 's#.md.gpg##' | cat <(echo "Notes store:") -
}

check_valid_name() {
	local name=$1
	if [[ -z $name ]]; then
		echo "Please specify the note's name."
		exit 1
	fi
}

print_note() {
	local name=$1
	local file=$(name_to_file $name)
	local gpgfile=$file.gpg
	decrypt $gpgfile
}

check_note_does_not_exist() {
	local name=$1
	local file=$(name_to_file $name)
	local gpgfile=$file.gpg

	if [[ -f $gpgfile ]]; then
		echo "Note already exists"
		exit 1
	fi
}

init_with_gpg_id() {
	local gpgid=$1
	mkdir -p $NOTES_DIR
	echo $gpgid > $NOTES_DIR/.gpg-id
}

main() {
	local cmd=$1

	case $cmd in
		-h)
			echo "$HELP_DOC"
			;;

		init)
			local gpgid=$2
			init_with_gpg_id $gpgid
			;;

		show|print)
			check_for_init
			local name=$2
			check_valid_name $name
			check_note_exists $name
			print_note $name
			;;

		add|insert|new)
			check_for_init
			local name=$2
			check_note_does_not_exist $name
			add_note $name
			;;

		edit)
			check_for_init
			local name=$2
			check_note_exists $name
			edit_note $name
			;;

		delete)
			check_for_init
			local name=$2
			check_valid_name $name
			check_note_exists $name
			delete_note $name
			;;

		list)
			check_for_init
			list_notes
			;;

		*)
			if [[ -z $cmd ]]; then
				check_for_init
				list_notes
			else
				echo "Unknown command."
				exit 1
			fi
			;;
	esac
}

main "$@"