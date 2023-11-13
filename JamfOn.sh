#!/bin/bash

# Define the path to the plist file
PLIST_PATH='/Library/Preferences/com.apple.networkextension.plist'

# Specify the snippet of text you want to check for
SEARCH_TEXT_1='
        Index = "<CFKeyedArchiverUID 0x6000012fe4e0 [0x1dc2df810]>{value = 1}";
'

SEARCH_TEXT_2='
        "6JQLCT6DRB.com.radiosilenceapp.app-group",
        "group.com.pvpn.privatevpn.packettunnel",
        "8UNVXQC2DG.group.com.urban-vpn.mac",
        "com.radiosilenceapp.client",
        "com.pvpn.privatevpn",
        "com.urban-vpn.mac",
'


# Read the contents of the plist file
PLIST_CONTENTS=$(defaults read "$PLIST_PATH")

# Check if both snippets of text are present in the plist content
if [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_1"* && "$PLIST_CONTENTS" == *"$SEARCH_TEXT_2"* ]]; then
  echo "Both snippets found in the plist file."
else
  echo "At least one of the snippets not found in the plist file."
fi
