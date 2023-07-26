#!/bin/bash

# Check if Google Chrome is installed
chromePath="/Applications/Google Chrome.app"
if [ ! -d "$chromePath" ]; then
    echo "Google Chrome is not installed. Please install Google Chrome and try again."
    exit 1
fi

# Set Google Chrome as the default browser
defaultBrowser=$(defaults read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers | grep -o -m 1 "com.google.Chrome")
if [ "$defaultBrowser" != "com.google.Chrome" ]; then
    /usr/bin/defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add '{LSHandlerURLScheme="http";LSHandlerRoleAll="com.google.Chrome";}'

    # Restart Finder to apply the changes
    killall Finder

    # Sleep for a moment to allow the Finder to restart
    sleep 1

    # Open Chrome to prompt recognition of default browser change
    open -a "Google Chrome"

    # Confirm that Google Chrome is now the default browser
    updatedDefaultBrowser=$(defaults read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers | grep -o -m 1 "com.google.Chrome")
    if [ "$updatedDefaultBrowser" == "com.google.Chrome" ]; then
        echo "Google Chrome is now set as the default browser."
    else
        echo "Failed to set Google Chrome as the default browser. Please try again or set it manually in the System Preferences."
        exit 1
    fi
else
    echo "Google Chrome is already set as the default browser."
fi

exit 0
