#!/bin/bash

/usr/bin/osascript << EOF
	try
		do shell script "sudo killall DesktopNotifier" with administrator privileges
	on error message number errorNumber
		if errorNumber = -128 then
			-- `Cancel` button is likely used or privileges don't exist, allow the uninstall to abort now and continue to run the app binary unchanged
			display dialog "Uninstallation cannot be completed without administrative privileges."
			return
		else if errorNumber = 1 then
			-- The process is already stopped or not running, just ignore the error for now and continue with uninstallation
			log "Unable to stop existing process (uninstallation will continue) message: " & message & " errorNumber: " & errorNumber
		else
			-- Fatal script error, this shouldn't happen unless some kind of OS change occurs in the future
			error "An uncategorized error occurred stopping the application. The uninstall process is unable to continue due to: " & message number errorNumber
		end if
	end try
	
	-- not all dock applications have 'bundle-identifier', but ours should so scrub the list
	tell application "System Events"
		set prefsHome to (path to preferences folder from user domain as text)
		set filePath to "com.apple.dock.plist"
		set dockPlist to property list file (prefsHome & filePath)
		set dockApps to (value of property list item "persistent-apps" of dockPlist)
		repeat with i from (count items of dockApps) to 1 by -1
			try
				-- With the array of persistent-apps, search for this app using the bundle identifier
				set dockApp to item i of dockApps
				set tileDataRec to |tile-data| of dockApp
				set bundleId to |bundle-identifier| of tileDataRec
				if bundleId = "com.singlewire.DesktopNotifier" then
					set appRemoved to true
					set sourceFile to POSIX path of dockPlist
					do shell script "/usr/libexec/PlistBuddy -c 'Delete persistent-apps:'" & (i - 1) & " '" & sourceFile & "'"
					exit repeat
				end if
			on error
				-- continue search even if lookups in the property list fail
			end try
		end repeat
	end tell
	
	-- it will be restarted automatically
	if appRemoved then
		tell application "Dock" to quit
	end if
	
	-- remove the application
	do shell script "sudo rm -rf /Applications/DesktopNotifier.app" with administrator privileges
	-- stop the current launchctl agents
	do shell script "launchctl unload /Library/LaunchAgents/com.singlewire.DesktopNotifierTrashMonitor.plist"
	do shell script "launchctl unload /Library/LaunchAgents/com.singlewire.DesktopNotifierAgent.plist"
	-- remove all launch agents (assumes a prefix)
	do shell script "sudo rm -rf /Library/LaunchAgents/com.singlewire.DesktopNotifier*.plist" with administrator privileges
	-- remove the Application Support folder
	do shell script "sudo rm -rf \"/Library/Application Support/Singlewire\"" with administrator privileges
	
EOF

