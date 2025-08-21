#!/usr/bin/env bash
set -e


REQUIRED_PACKAGES=(pass gnupg2 borgbackup cifs-utils)

CONFIG_FOLDER="/home/$USER/.config/borg-backup"
GPG_KEY_NAME="$USER@borg-backup"

export PASSWORD_STORE_DIR="$CONFIG_FOLDER/.password-store"


# ────────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────────
check_dependencies() {
   declare \
     missing_packages=() \
     package

  for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -l "$package" &>/dev/null; then
      missing_packages+=("$package")
    fi
  done

  if [[ ${#missing_packages[@]} -ne 0 ]]; then
    echo "Error: The following required packages are not installed:" >&2
    printf "  - %s\n" "${missing_packages[@]}" >&2
    echo "Install them first with: sudo apt update && sudo apt install -y ${missing_packages[@]}" >&2
    return 1
  fi

  return
}

init_password_store() {
  mkdir -p "$CONFIG_FOLDER"

  if gpg --list-secret-keys "$GPG_KEY_NAME" &> /dev/null; then
    echo "GPG key:[$GPG_KEY_NAME] already exists. Skipping key generation."
  else
    printf "\nGenerating new GPG key:[$GPG_KEY_NAME]\n\nYou will be prompted for a passphrase..."
    sleep 5
    gpg --batch --generate-key <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: borg-backup
Name-Email: $GPG_KEY_NAME
Expire-Date: 0
%ask-passphrase
%commit
EOF
  fi

  pass init "$GPG_KEY_NAME"

  return
}

configure_smb() {
  declare \
    success=false \
    pass_store="smb" \
    pass_key="data" \
    server share username

  printf "\nSpecify the remote SMB server\nServer: "
  read server

  printf "\nSpecify the name of the SMB share on the remote server:[$server]\nShare: "
  read share

  printf "\nSpecify the username for the remote server:[$server]\nUsername: "
  read username

  mkdir -p "$PASSWORD_STORE_DIR/$pass_store"

  if ! pass insert "$pass_store/$username"; then
    echo "Error: Failed to read password"
    return 1
  fi
  echo

  printf "%s\n%s\n%s\n%s" \
    "$server" "$share" "$username" "$(pass show "$pass_store/$username" )" \
    | pass insert -mf "$pass_store/$pass_key" 1>/dev/null \
    && success=true \
    || success=false

  pass rm -f "$pass_store/$username" 1>/dev/null

  if ! $success; then
    echo "Failed to store SMB data securely"
    return 1
  fi

  return
}

configure_repo() {
  declare \
    success=false \
    pass_store="repo" \
    pass_key="data" \
    repo smb

  printf "\nSpecify a location for the borg repository\nMount Point: "
  read repo

  mkdir -p "$PASSWORD_STORE_DIR/$pass_store"

  if ! pass insert "$pass_store/passphrase"; then
    echo "Error: Failed to read password"
    return 1
  fi
  echo

  printf "%s\n%s" "$repo" "$(pass show "$pass_store/passphrase" )" \
    | pass insert -mf "$pass_store/$pass_key" 1>/dev/null \
    && success=true \
    || success=false

  pass rm -f "$pass_store/passphrase" 1>/dev/null

  if ! $success; then
    echo "Failed to store repo data securely"
    return 1
  fi

  sudo mkdir -p "$repo"
  sudo chown $USER:$USER "$repo"
  chmod 700 "$repo"

  if ! grep -q "$repo" /etc/fstab; then
    mount_options=(
      "credentials=$HOME/.cache/borg-backup/smb-credentials"
      "user"
      "noauto"
      "rw"
      "vers=3.0"
      "iocharset=utf8"
      "uid=$(id -u)"
      "gid=$(id -g)"
      "file_mode=0600"
      "dir_mode=0700"
    )

    smb=( $(pass show smb/data) )
    ( \
      IFS=,; printf '\n//%s/%s %s cifs %s 0 0\n' "${smb[0]}" "${smb[1]}" "$repo" "${mount_options[*]}" \
      | sudo tee -a /etc/fstab > /dev/null \
    )
    unset smb

    sudo systemctl daemon-reload
  fi

  return
}

init_config() {
  declare \
    config="$CONFIG_FOLDER/borg-backup.conf" \
    includes excludes

  printf "\nSpecify folders to include (comma-separated)\nIncludes: "
  read includes
  echo

  includes=( ${includes//,/ } )
  echo "There will be (${#includes[@]}) folders included in the backup"

  printf "\nSpecify folders to exclude (comma-separated)\nExcludes: "
  read excludes
  echo

  excludes=( ${excludes//,/ } )
  echo "There will be (${#excludes[@]}) folders excluded from the backup"
  echo

  (IFS=,; printf 'INCLUDES=%s\nEXCLUDES=%s\n' "${includes[*]}" "${excludes[*]}" > $config)

  return
}

install_files() {
  mkdir -p $HOME/.local/bin
  install -m 0755 bin/* $HOME/.local/bin/

  mkdir -p $HOME/.config/systemd/user
  install -m 0644 systemd/* $HOME/.config/systemd/user

  sudo install -m 0644 hooks/* /etc/profile.d/

  return
}

enable_services() {
  systemctl --user daemon-reload
  systemctl --user enable --now borg-backup-passphrase@$USER.service
  systemctl --user enable --now borg-backup@$USER.timer

  return
}


# ────────────────────────────────────────────────────────────────────────────────
# Install
# ────────────────────────────────────────────────────────────────────────────────
printf "
This script will prompt you for your password because it needs administrator (root) access for several important setup steps:

Creating and configuring the backup repository folder:
  The script sets up the backup location and ensures you have the correct permissions to access it. This may involve creating or modifying folders that require administrator privileges.

Modifying system mount configuration:
  The script updates the system's mount settings by adding an entry to 'etc/fstab'. This allows the backup volume to be mounted without requiring root privileges or a sudoers workaround, which requires administrator access to change system-wide configuration files.

Reloading system services:
  After updating mount settings, the script reloads system services to apply these changes.

Installing system-wide profile hooks:
  The script places a file in 'etc/profile.d', which affects all users' shell environments. Administrator access is required to modify this location.

You will be prompted for your password when these steps are performed. This is necessary to securely and correctly integrate the backup system into your operating system.

"
read -p 'Press any key to continue ...'
echo


check_dependencies
init_password_store
configure_smb
configure_repo
init_config
install_files
enable_services


$HOME/.local/bin/borg-backup-passphrase cache


exit
