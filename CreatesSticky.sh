#!/bin/bash

#DEP First Login script

#Create Sticky
theUser="$(dscl . -read "/Users/$(logname)" RealName)"

theUser="$(dscl . -read "/Users/$(logname)" RealName | sed -n 's/^ //g;2p' | sed 's/ //g')"

#Automation:
gradYear="$(id $lastUser | sed -n 's/.*Class of //p' | cut -f1 -d")")"

#AppleScript

osascript -- - "$gradYear" "$theUser" <<'EOF'
on run(argv)
set gradY to item 1 of argv as string
set userFull to item 2 of argv as string
tell application "Stickies" to activate
tell application "System Events"
	tell application process "Stickies"
		tell window 1
			delay 1
			keystroke "a" using command down
			key code 51
			keystroke "w" using command down
			delay 1
			keystroke "a" using command down
			key code 51
			keystroke "w" using command down
			delay 1
			keystroke "n" using command down
			keystroke "MySA Username: "
			keystroke userFull & gradY
		end tell
	end tell
end tell
end
EOF