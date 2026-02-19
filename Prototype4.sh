#!/bin/sh
printf '\033c\033]0;%s\a' fpp4
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Prototype4.x86_64" "$@"
