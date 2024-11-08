#!/bin/bash

SEARCH_TEXT_1='
                "_CFURLString" = "file:///Applications/Self%20Service.app/";
'

SEARCH_TEXT_2='
                "_CFURLString" = "file:///System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/";
'

SEARCH_TEXT_3='
                "_CFURLString" = "file:///Applications/Google%20Chrome.app";
'


# Read the contents of the plist file
PLIST_CONTENTS=$(defaults read com.apple.dock persistent-apps)

# Check if all snippets of text are present in the plist content
if [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_1"* ]] && \
   [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_2"* ]] && \
   [[ "$PLIST_CONTENTS" == *"$SEARCH_TEXT_3"* ]]; then
  echo "<result>Enabled</result>"
else
  echo "<result>Not Enabled</result>"
fi