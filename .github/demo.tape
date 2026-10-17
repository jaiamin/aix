# The README demo. Re-record with `vhs .github/demo.tape` (needs vhs, aix on PATH and Apple Intelligence).

Output .github/demo.gif
Require aix

Set Shell zsh
Set FontFamily "Menlo"
Set FontSize 20
Set Width 1300
Set Height 600
Set Padding 30
Set Margin 40
Set MarginFill "#6C63FF"
Set WindowBar Colorful
Set WindowBarSize 44
Set BorderRadius 12
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms
Set CursorBlink false
Set Framerate 24

# A clean shell in a throwaway demo project, with the shell integration loaded.
Hide
Type "exec zsh -f" Enter
Type `PROMPT='%F{#89b4fa}~/site%f %F{#cba6f7}❯%f '; cd "$(mktemp -d)"; mkdir -p photos video src` Enter
Type "head -c 24000000 /dev/zero > video/intro.mov; head -c 8000000 /dev/urandom > photos/beach.jpg; head -c 5000000 /dev/urandom > photos/team.png; touch README.md package.json src/app.js" Enter
Type `eval "$(aix init zsh)"; clear` Enter
Sleep 500ms
Show

# A request: the command streams in, then y runs it.
Sleep 700ms
Type "aix find the 3 biggest files here"
Sleep 600ms
Enter
Sleep 4.5s
Type "y"
Sleep 2.5s

# A question gets an answer.
Type "aix what does chmod 755 mean"
Sleep 500ms
Enter
Sleep 4s

# Ctrl-G turns plain English on the prompt into the command.
Hide
Type "clear" Enter
Sleep 300ms
Show
Sleep 500ms
Type "zip the photos folder"
Sleep 900ms
Ctrl+G
Sleep 4s
Enter
Sleep 3s
