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

Needs Apple silicon, macOS 26+ and Apple Intelligence. Run `aix` alone to type a request without quoting; `-n` shows the command without running it. The model is small, so read the command before pressing `y`.

To improve it, add examples to [`Examples.swift`](Sources/AixCore/Examples.swift) and run `make test`. MIT License.
