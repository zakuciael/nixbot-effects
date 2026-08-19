registerPutStatePhaseOnFailure() {
  failureHooks=("putStatePhaseOnFailure" "${failureHooks[@]}")
}

getStateFile() {
  local stateName="$1"
  local stateFileName="${2:-$1}"
  local apiToken
  apiToken=$(jq -r '.["hercules-ci"].data.token' "$HERCULES_CI_SECRETS_JSON")

  echo 1>&2 "fetching state file $stateName"
  while true; do
    http_code=$(
      curl \
        -H "Authorization: Bearer $apiToken" \
        --retry-max-time 86400 --retry-connrefused --max-time 1800 \
        --silent --show-error \
        --location \
        "$HERCULES_CI_API_BASE_URL/api/v1/current-task/state/$stateName/data" \
        -o "$stateFileName" \
        -w '%{http_code}'
    )
    case $http_code in
    200 | 204)
      break
      ;;
    408 | 421 | 429 | 5*)
      echo 1>&2 "http status $http_code. Retrying..."
      sleep 60
      continue
      ;;
    404)
      echo 1>&2 "state file does not exist."
      rm -f "$stateFileName"
      break
      ;;
    *)
      echo 1>&2 "request failed with fatal status $http_code"
      exit 1
      ;;
    esac
  done
}

putStateFile() {
  local stateName="$1"
  local stateFileName="${2:-$1}"
  local apiToken
  apiToken=$(jq -r '.["hercules-ci"].data.token' "$HERCULES_CI_SECRETS_JSON")

  echo "pushing state file $stateName..."
  curl \
    -H "Authorization: Bearer $apiToken" \
    --retry-max-time 86400 --retry-connrefused --max-time 1800 \
    --silent --show-error \
    --location --fail \
    -XPUT \
    --upload-file "$stateFileName" \
    "$HERCULES_CI_API_BASE_URL/api/v1/current-task/state/$stateName/data" \
    ;
  echo "pushing state successful."
}

readSecretString() {
  local secretName="$1"
  local dataPath="$2"

  if ! jq -e -r '.[$secretName].data | '"$dataPath" --arg secretName "$secretName" <"$HERCULES_CI_SECRETS_JSON"; then
    echo 1>&2 "Could not find path $dataPath in secret $secretName"
    return 1
  fi
}

readSecretJSON() {
  local secretName="$1"
  local dataPath="$2"

  jq -c '.[$secretName].data | '"$dataPath" --arg secretName "$secretName" <"$HERCULES_CI_SECRETS_JSON"
}

writeAWSSecret() {
  local secretName="${1:-aws}"
  local profileName="${2:-default}"

  mkdir -p ~/.aws
  cat >>~/.aws/credentials <<EOF
[$profileName]
aws_secret_access_key = $(readSecretString "$secretName" .aws_secret_access_key)
aws_access_key_id = $(readSecretString "$secretName" .aws_access_key_id)
EOF
}

writeSSHKey() {
  local secretName="${1:-ssh}"
  local privateName="${2:-$HOME/.ssh/id_rsa}"
  local publicName="${privateName}.pub"

  mkdir -p "$(dirname "$privateName")"
  readSecretString "$secretName" .privateKey >"$privateName"
  chmod 0400 "$privateName"
  test -r "$publicName" ||
    readSecretString "$secretName" .publicKey >"$publicName" ||
    ssh-keygen -y -f "$privateName" >"$publicName" ||
    {
      echo >&2 "warning: could not write ${publicName}. do we need it?"
      rm "$publicName"
    }
}

writeDockerKey() {
  local secretName="${1:-docker}"
  local directory="${2:-$HOME/.docker}"

  mkdir -p "$directory"

  readSecretString "$secretName" .clientKey >"$directory/key.pem"
  readSecretString "$secretName" .clientCertificate >"$directory/cert.pem"
  readSecretString "$secretName" .CACertificate >"$directory/ca.pem"

  # Please permission checks if any
  chmod 0400 "$directory"/{key,cert,ca}.pem
}

useDockerHost() {
  local host="${1}"
  local port="${2:-2376}"
  export DOCKER_HOST=tcp://$host:$port
  export DOCKER_TLS_VERIFY=1
}

gpgFingerprints() {
  gpg --with-colons --import-options show-only --import --fingerprint | awk -F: '$1 == "fpr" {print $10;}'
}

gpgTrust() {
  gpgFingerprints | sed -e 's/$/:6/' | gpg --import-ownertrust
}

writeGPGKey() {
  local secretName="${1:-gpg}"
  readSecretString "$secretName" .privateKey | gpg --import
  readSecretString "$secretName" .privateKey | gpgTrust
}

writeAgeKey() {
  local secretName="${1:-age}"
  local fileName="${2:-$HOME/.config/sops/age/keys.txt}"

  mkdir -p "$(dirname "$fileName")"
  readSecretString "$secretName" .privateKey >"$fileName"
}

setupGit() {
  local commitAuthor="${1:-}"
  local commitEmail="${2:-}"

  if [ -z "$commitAuthor" ]; then
    echo "You need to specify the commitAuthor variable"
    return 1
  fi

  jsonData=$(
    curl \
      --retry-max-time 86400 --retry-connrefused --max-time 1800 \
      --silent --show-error \
      --globoff \
      --location \
      "https://api.github.com/users/$commitAuthor"
  )
  read -r name id type < <(echo "$jsonData" | jq -r '[ .login, .id, .type ] | join(" ")')

  if [ "$type" != "Bot" ] && [ -z "$commitEmail" ]; then
    echo "If your are using a non-bot account you need to specify commitEmail variable"
    return 1
  fi

  if [ "$type" == "Bot" ]; then
    commitAuthor="${name}"
    commitEmail="${id}+${name}@users.noreply.github.com"
  fi

  git config --global user.name "$commitAuthor"
  git config --global user.email "$commitEmail"
  git config --global safe.directory '*'
}
