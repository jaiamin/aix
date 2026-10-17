# aix

Say what you want in plain English. aix writes the shell command, and you run it with one key.
It uses Apple Intelligence on your Mac: free, private, offline, no API key.

![aix demo](.github/demo.gif)

## Install

```sh
brew install jaiamin/aix/aix
```

Needs an Apple silicon Mac on macOS 26 or later, with Apple Intelligence turned on.

## Use

```sh
aix find the 5 largest files here    # get a command, press y to run it
aix what does chmod 755 mean         # ask about the terminal or your Mac
aix explain tar -xzf backup.tgz      # break a command down
aix                                  # type the request, no quoting needed
```

At the prompt: `y` runs, `r` refines, `c` copies, any other key cancels. `-n` shows the command without asking.

## Shell integration

Add this to `~/.zshrc`:

```sh
eval "$(aix init zsh)"
```

- **Ctrl-G** turns the English on your prompt into the command, ready to edit.
- **`e`** at the Run prompt puts the command on your prompt line.
- Commands aix runs go into your shell history.
- **`aix fix`** fixes your last failed command.

## Good to know

- The on-device model is small, so read the command before you press `y`. aix warns when a command deletes, moves or overwrites files, and refuses obvious disasters.
- Nothing leaves your Mac. aix learns from the commands you approve, kept in `~/Library/Application Support/aix/history.json`; delete it to forget them.

## Contributing

The model learns from the worked examples in [`Examples.swift`](Sources/AixCore/Examples.swift), so adding good ones is the easiest way to improve aix. Run `make test` before opening a pull request.

MIT License
