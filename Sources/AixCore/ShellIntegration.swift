/// What `aix init zsh` prints: Ctrl-G turns the text on the prompt into a command,
/// and the last command is passed to aix (only) for `aix fix`.
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
      AIX_LAST_STATUS=$_aix_last_status AIX_LAST_COMMAND=$_aix_last_command command aix "$@"
    }
    """#
}
