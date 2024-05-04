# Notes

Local notes, gpg-encrypted. Simple interface (similar to `pass`). Single-file installation.

![screenshot](screenshot.png)

If you already use GNU `pass`, you will know how to use this tool.
It's basically the same thing, but for multiline notes instead.

## Storage

Notes are stored in `$NOTES_DIR`, which you can override.
It defaults to `$HOME/.note-store`.

Each note is stored as a file.
The contents of each note are never stored in plain text, only the filenames themselves.

## Git

You can optionally initialize a git repo within the notes directory, in which case every change to the store will be automatically tracked with a new commit.
After that, you can run any git command from within that directory by running

```
notes git <normal git commands + args>
```
