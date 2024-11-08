#!/bin/bash

SEARCH_TEXT_1='
            "file-label" = Safari;
'

SEARCH_TEXT_2='
            "file-label" = "Self Service";
'

SEARCH_TEXT_3='
            "file-label" = "Google Chrome";
'


# Read the contents of the plist file
PLIST_CONTENTS=$(defaults read com.apple.dock persistent-apps)

# Check if all three snippets of text are present in the plist content
if [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_1"* ]] && \
   [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_2"* ]] && \
   [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_3"* ]]; then
  echo "<result>Enabled</result>"
else
  echo "<result>Not Enabled</result>"
fi