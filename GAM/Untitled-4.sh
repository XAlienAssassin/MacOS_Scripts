#!/bin/bash



curl -fs "https://helpx.adobe.com/creative-cloud/release-note/cc-release-notes.html" | grep "mandatory" | head -1 | grep -o "Version *.* released" | cut -d " " -f2



curl -fs "https://web.archive.org/web/20241112141623/https://helpx.adobe.com/creative-cloud/release-note/cc-release-notes.html" | grep "mandatory" | head -1 | grep -oE "Version[  ]*[0-9\.]+" | grep -oE "[0-9\.]+"