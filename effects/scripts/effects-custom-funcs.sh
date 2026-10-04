writeAgeKey() {
  local secretName="${1:-age}"
  local fileName="${2:-$HOME/.config/sops/age/keys.txt}"

  mkdir -p "$(dirname "$fileName")"
  readSecretString "$secretName" .privateKey >"$fileName"
}

setupGit() {
  local secretName="${1:-"git-author"}"

  commitAuthor=$(readSecretString "$secretName" .username)
  commitEmail=$(readSecretString "$secretName" .email)

  git config --global user.name "$commitAuthor"
  git config --global user.email "$commitEmail"
  git config --global safe.directory '*'
}
