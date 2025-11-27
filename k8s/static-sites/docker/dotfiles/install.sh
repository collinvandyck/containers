#!/usr/bin/env bash

set -e

function cmd-exists() {
    local cmd="$1"
    command -v "${cmd}" &>/dev/null
}

# add pre-requisites that the dotfiles depends on. 
if [ "$(uname -s)" = "Linux" ]; then
    ok=true
    for cmd in git curl; do
        if ! cmd-exists "$cmd"; then
            ok=false
        fi
    done
    if [ "$ok" = "false" ]; then 
        sudo apt-get update
        sudo apt-get install -y git curl
    fi
fi

if ! [ -e ~/.dotfiles ]; then
	git clone https://github.com/collinvandyck/dotfiles.git ~/.dotfiles
fi

cd ~/.dotfiles
git pull || true
./install-all

