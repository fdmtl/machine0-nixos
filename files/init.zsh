
#
# History
#
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

#
# Completions
#
autoload -Uz compinit && compinit

#
# Plugins
# Tries Homebrew paths first, then common Linux package manager paths
#
source_if_exists() {
  [[ -f "$1" ]] && source "$1"
}

# zsh-autosuggestions
source_if_exists "${HOMEBREW_PREFIX:-/usr/local}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ||
  source_if_exists /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ||
  source_if_exists /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# Accept autosuggestion with Right arrow (Tab is used for path completion)
bindkey '^[[C' autosuggest-accept

# zsh-syntax-highlighting (must be last plugin sourced)
source_if_exists "${HOMEBREW_PREFIX:-/usr/local}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ||
  source_if_exists /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ||
  source_if_exists /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

#
# Terminal
#
export TERM=xterm-256color

# Keybindings for word navigation (Ctrl+Left/Right)
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word

# History search with Up/Down (matches prefix of current input)
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

#
# Aliases - General
#
alias json='python -m json.tool'
alias cd='z'
alias l='eza -l --icons'
alias ll='ls -lGh'
alias reload='source ~/.zshrc'
alias myip='curl http://jsonip.com/ | cut -d\" -f4'
alias key='cat ~/.ssh/id_rsa.pub'
alias webserver='python3 -m http.server'
alias docker-ps='docker ps -a --format "table {{.ID}}\t{{.Status}}\t{{.Names}}"'
alias gen-passwd='openssl rand -base64 12 | tr -d "/+=" | head -c 16 && echo'

#
# git
#
alias gpl='git pull'
alias gpu='git push'
alias gs='git status'
alias ga='git add'
alias gb='git switch -c'
alias gco='git checkout'
alias gm='git checkout main'

#
# MCP
#
alias mcp-inspector='npx @modelcontextprotocol/inspector'

#
# Utilities - General
#
killport() { lsof -ti tcp:$1 | xargs kill; }
listport() { lsof -i :$1; }

alias decompress="tar -xzf"
compress() { tar -czf "${1%/}.tar.gz" "${1%/}"; }

gc() { git commit -a -m "$1"; }

spc() {
  for i in {1..30}; do
    echo
  done
}

#
# Tools
#
command -v mise &>/dev/null && eval "$(mise activate zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# Eza completion (use ls completion for eza and aliases)
compdef eza=ls 2>/dev/null
compdef l=ls 2>/dev/null

#
# Prompt (Starship)
#
export STARSHIP_CONFIG=~/.config/starship/starship.toml
command -v starship &>/dev/null && eval "$(starship init zsh)"
