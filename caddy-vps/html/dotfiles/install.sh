#!/usr/bin/env bash

set -e

if [ -e ~/.dotfiles ]; then
	echo "Dotfiles aready installed."
	exit
fi

echo "Installing dotfiles..."
git clone https://github.com/collinvandyck/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install-all

