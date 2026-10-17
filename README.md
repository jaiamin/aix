# aix

Say what you want in plain English, get the shell command, and run it with one key.
aix uses Apple Intelligence's on-device model, so it's free, private and works offline. No API key.

```
$ aix find the 5 largest files here

  Lists the five largest files in this folder and its subfolders.

  $ find . -type f -not -path '*/.git/*' -exec du -k {} + | sort -rn | head -5

Run? y/N · r refine · c copy
```

## Install

```sh
brew install jaiamin/aix/aix
```

Needs an Apple silicon Mac on macOS 26 or later, with Apple Intelligence turned on
(System Settings → Apple Intelligence & Siri).

## Use

```sh
aix show what changed since the last commit
aix                        # asks for the request, so you never need quotes
aix -n kill whatever is on port 3000   # just show the command
```

At the prompt, press one key:

| Key | Does |
|---|---|
| `y` | run it |
| `r` | refine it ("only python files", "include hidden ones") |
| `c` | copy it to the clipboard |
| anything else | cancel |

If a command fails, aix offers to fix it using the error message.

Options: `-n` show only, `-y` run without asking, `-h` help, `-v` version.

**Tip:** zsh treats `?` and `*` specially, so `aix what's my ip?` breaks. Run `aix` on its own and type the request, or add `alias aix='noglob aix'` to `~/.zshrc`.

## What to expect

The on-device model is small (about 3B parameters). It handles everyday one-liners well: finding files, searching text, git, archives, images, and system and network info. It sometimes gets longer pipelines wrong, so **read the command before you press `y`**.

## Safety

- Nothing runs until you press `y` (or pass `-y`).
- aix tells you what a command changes: "⚠ This deletes logs", "moves notes.txt", "overwrites config.json", "pushes to the remote".
- It refuses obvious disasters: `sudo`, deleting your home or system folders, erasing disks, `curl … | sh`, and reading and overwriting the same file.
- This is a safety net, not a sandbox.

## Privacy

The model runs on your Mac. It sees your request, the current folder's file names (two levels deep), your macOS and shell versions, the git branch, and which common tools are installed. Nothing is sent anywhere.

## Build from source

```sh
git clone https://github.com/jaiamin/aix && cd aix
make test
make install      # to ~/.local/bin; PREFIX=/usr/local to change
```

The prompt lives in `Sources/AixCore/Prompt.swift`, and the worked examples in `Sources/AixCore/Examples.swift`. Each request gets the 10 most related examples. Set `AIX_DEBUG=1` to print the prompt.

## License

MIT
