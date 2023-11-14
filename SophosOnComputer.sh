#!/bin/bash

# Define the path to the plist file
PLIST_PATH='/Library/Preferences/com.apple.networkextension.plist'

# Specify the snippet of text you want to check for
SEARCH_TEXT_1='
        "Sophos Network Extension",
        "Sophos Network Extension",
'


# Read the contents of the plist file
PLIST_CONTENTS=$(defaults read "$PLIST_PATH")

# Check if both snippets of text are present in the plist content
if [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_1"* ]]; then
  echo "Enabled"
else
  echo "Not Enabled"
fi
