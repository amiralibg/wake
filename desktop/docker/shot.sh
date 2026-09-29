#!/bin/sh
# Screenshot of the test container's display: desktop/.shots/<name>.png
docker exec wake-test sh -c "DISPLAY=:99 import -window root /wake/desktop/.shots/${1:-shot}.png"
