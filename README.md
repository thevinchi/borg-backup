
# Borg Backup User Automation

This project provides a user-level backup solution built on BorgBackup, focused on automation for developer workstations. It performs hourly backups only during active user sessions, backing up your data while you work.

It uses GPG for encryption and `pass` for secret management, offering a headless and automated backup system for single-user workstations.

> **Note:** This solution is tailored for single-user workstations and is not intended for server environments.

## Features

- Automated backups using BorgBackup
- GPG-encrypted archives with passphrase management
- Password store integration via `pass`
- Systemd service and timer for scheduled backups
- Automated setup and configuration

## Installation

Run the install script to set up dependencies and configuration:
 ```bash
 ./install.sh
 ```

The install script performs the following steps:
- Checks for required system packages (`pass`, `gnupg2`, `borgbackup`, `cifs-utils`).
- Creates a dedicated password store.
- Generates a new GPG key used for encrypting the password store and backup secrets.
- Prompts for and stores your SMB/CIFS credentials and the Borg repository passphrase in the password store.
- Installs the necessary scripts and systemd user units to automate the backup process.
- Configures `/etc/fstab` to allow mounting the remote backup share without requiring `sudo` at runtime.

## Usage

```bash
borg-backup backup
borg-backup ls [<archive>]
borg-backup rm <archive>
borg-backup restore <archive> <src> <dest>
borg-backup -h|--help
```

## Systemd Integration

- `borg-backup@.service`: Runs the backup for a user.
- `borg-backup@.timer`: Schedules hourly backups.
- `borg-backup-passphrase@.service`: Clears the cached GPG passphrase from the `gpg-agent` on session logout.

The `install.sh` script automatically enables and starts the required services and timers for the current user.

## Configuration

- Config files are stored in `~/.config/borg-backup/`

## Requirements

- pass
- gnupg2
- borgbackup
- cifs-utils

