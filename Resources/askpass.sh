#!/bin/sh
# SUDO_ASKPASS helper. sudo runs this only when Touch ID is not available or was
# cancelled. It shows a password dialog and prints the answer to sudo; nothing is stored.
exec /usr/bin/osascript \
  -e 'on run argv' \
  -e 'text returned of (display dialog (item 1 of argv) default answer "" with hidden answer with title "OwlEye" with icon caution buttons {"Cancel", "OK"} default button "OK")' \
  -e 'end run' \
  "${1:-Password:}"
