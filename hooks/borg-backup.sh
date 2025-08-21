#!/usr/bin/env bash

[[ -z $TMUX && -x "$HOME/.local/bin/borg-backup-passphrase" ]] && "$HOME/.local/bin/borg-backup-passphrase" cache

