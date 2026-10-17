# aix

Describe what you want, get the shell command, run it with one key. Runs on Apple Intelligence, on your Mac.

```
$ aix find the 5 largest files here
  $ find . -type f -exec du -k {} + | sort -rn | head -5
Run? y/N · r refine · c copy
```

```sh
brew install jaiamin/aix/aix
```

Needs Apple silicon, macOS 26+ and Apple Intelligence.

- `aix <request>`, or `aix` alone to type it without quoting. Questions like `aix what does chmod 755 mean` get a short answer.
- `aix explain <command>` breaks a command down. `aix fix` fixes your last failed command.
- Add `eval "$(aix init zsh)"` to `~/.zshrc`, then type a request at your prompt and press **Ctrl-G** to turn it into the command (needed for `aix fix`).

The model is small, so read the command before pressing `y`. aix learns from commands you approve; they're kept in `~/Library/Application Support/aix/history.json`.

To improve it, add examples to [`Examples.swift`](Sources/AixCore/Examples.swift) and run `make test`. MIT License.
