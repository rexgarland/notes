# Notes

Local notes, gpg-encrypted.

Simple CLI (similar to [pass](https://www.passwordstore.org)).
Single-file installation, < 400 lines of code.

![screenshot](screenshot.png)

Run `notes -h` for a full description of available commands.

## Usage

Basic usage

```shell
# Move notes.sh somewhere your shell can run it (aliased "notes" below)

# Initialize the notes dir and encryption
notes init <gpg-id>

# Make a note, edit it with your $EDITOR (e.g. named "hello")
notes add hello
notes edit hello # requires gpg signin

notes show hello # print it (requires logged in gpg, same as above)
notes remove hello # delete it
```

Using git

```shell
notes git init # init repo within $NOTES_DIR (default ~/.note-store)
# Now any changes to $NOTES_DIR are automatically committed.
# Plaintext files are excluded from git (search .gitignore in the code)

notes git push # optionally, push to a remote (it's encrypted, after all)
notes git <any other git command, run from within $NOTES_DIR>
```

Plaintext versions of the files are never committed to git or stored more than during duration of editing.
This is not 100% foolproof, see security notes below.

## Dependencies

- gpg
- git (optional)
- sed
- tree
- find

## Notes store

Notes are stored in `$NOTES_DIR`, which defaults to `$HOME/.note-store` if it is unset.

Each note is stored as a file, with filename formatted as `<name>.md.gpg`.
The contents of each note are never stored in plain text, only the filenames themselves.

When running `note edit <note name>`, the associated note is decrypted using your default gpg key, then opened using your `$EDITOR`.

## Known security issues

When a note is opened for editing, it is first decrypted to plaintext using your GPG credentials.
When you exit the editor, this plaintext file is usually deleted.
However, there are situations when it will _not_ be deleted.

For example, if your computer crashes while you are editing a note, the plaintext version of the note will be left on your disk (this actually happened to me once).

In order to reduce the risk of leaving plaintext lying around, a few precautions are taken:

1. The `notes list` command (alias `notes`) will highlight any plaintext note files in RED.
2. Plaintext note files are automatically ignored in `.gitignore` with `**/*.md`, so they will not be tracked by git.
3. The command `notes clean` will automatically clean up any plaintext files.
4. Any variables exposing plaintext within the code are suffixed with `_PLAINTEXT` for clarity.
