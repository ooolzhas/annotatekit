#!/bin/zsh
# One frame of the reel: frame.sh <index>; at 30fps that is 2 steps of the scene's 60fps clock per frame.
i=$1
rive "$PROJ" --screenshot="$FRAMES/f$(printf %04d $i).png" --advance=$((i*2)) >/dev/null 2>&1
