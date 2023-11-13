#!/bin/bash

# Define the target XML snippet
TARGET_CODE='
    <dict>
\\nskdsdknsdknsdfsdlkfnsdlkfnkl
'

# Define the path to the plist file
PLIST_PATH='/Library/Preferences/com.apple.networkextension.plist'

# Check if the target code is present in the plist
if grep -n -qF "$TARGET_CODE" "$PLIST_PATH"; then
    echo "Target code found in the plist!"
    grep -n -F "$TARGET_CODE" "$PLIST_PATH"
else
    echo "Target code not found in the plist."
fi

