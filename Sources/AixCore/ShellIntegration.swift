/// What `aix init zsh` prints: Ctrl-G turns the text on the prompt into a command, `aix fix`
/// gets the last command (without exporting it), and an `aix` function puts edited commands on
/// the prompt line and the commands aix runs into shell history.
public enum ShellIntegration {
    public static let zsh = #"""
    # aix shell integration: eval "$(aix init zsh)"
    _aix_widget() {
      [[ -z $BUFFER ]] && return
      zle -M "Generating..."
      zle -R
      local notes=${TMPDIR:-/tmp}/aix-notes.$$
      local out
      out=$(command aix --print -- "$BUFFER" </dev/null 2>"$notes")
      if [[ $? -eq 0 && -n $out ]]; then
        BUFFER=$out
        CURSOR=${#BUFFER}
      fi
      zle -M "$(<"$notes")"
      rm -f "$notes"
    }
    zle -N _aix_widget
    bindkey '^G' _aix_widget

    # Remember the last command without exporting it; only aix gets it, for `aix fix`.
    _aix_precmd() {
      _aix_last_status=$?
      _aix_last_command=$(fc -ln -1 2>/dev/null)
    }
    precmd_functions=(_aix_precmd ${precmd_functions[@]})
    aix() {
      local handoff=${TMPDIR:-/tmp}/aix-handoff.$$
      AIX_HANDOFF=$handoff AIX_LAST_STATUS=$_aix_last_status AIX_LAST_COMMAND=$_aix_last_command command aix "$@"
      local rc=$?
      if [[ -s $handoff ]]; then
        local lines=("${(@f)$(<$handoff)}")
        if [[ $lines[1] == edit ]]; then print -z -- "${(F)lines[2,-1]}"; else print -s -- "${(F)lines[2,-1]}"; fi
      fi
      rm -f $handoff
      return $rc
    }
    """#
}
