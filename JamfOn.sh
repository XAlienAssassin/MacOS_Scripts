#!/bin/bash

# Define the path to the plist file
PLIST_PATH='/Library/Preferences/com.apple.networkextension.plist'

# Specify the snippet of text you want to check for
SEARCH_TEXT_1=' Enabled = 1;
            OnDemandRules'

SEARCH_TEXT_2='        "*.jamf.com",
        "*.jamfcloud.com",.'


# Read the contents of the plist file
PLIST_CONTENTS=$(defaults read "$PLIST_PATH")

# Check if both snippets of text are present in the plist content
if [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_1"* && "$PLIST_CONTENTS" == *"$SEARCH_TEXT_2"* ]]; then
  echo "<result>Enabled</result>"
else
  echo "<result>Not Enabled</result>"
fi
