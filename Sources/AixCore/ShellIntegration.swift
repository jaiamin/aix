/// What `aix init zsh` prints: Ctrl-G turns the text on the prompt into a command,
/// and a precmd hook remembers the last command for `aix fix`.
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

    _aix_precmd() {
      export AIX_LAST_STATUS=$? AIX_LAST_COMMAND="$(fc -ln -1 2>/dev/null)"
    }
    precmd_functions=(_aix_precmd ${precmd_functions[@]})
    """#
}
