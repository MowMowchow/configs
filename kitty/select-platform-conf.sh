#!/bin/sh
# Picked up by kitty's geninclude in jhou.conf. Emits one line of kitty config
# (an `include` directive) selecting the right platform overrides file.
case "$(uname -s)" in
    Darwin) echo "include jhou-macos.conf" ;;
    Linux)  echo "include jhou-linux.conf" ;;
    *)      echo "# unsupported platform: $(uname -s) — no platform overrides loaded" ;;
esac
