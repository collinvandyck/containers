#!/usr/bin/env bash

set -e

if ! [ -e ~/.dotfiles ]; then
	git clone https://github.com/collinvandyck/dotfiles.git ~/.dotfiles
fi

cd ~/.dotfiles
./install-all

