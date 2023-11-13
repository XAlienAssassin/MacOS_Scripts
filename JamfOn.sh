#!/bin/bash

# Define the code section you want to search for
search_pattern='<dict>
\s*<key>\$classes<\/key>
\s*<array>
\s*<string>NSMutableDictionary<\/string>
\s*<string>NSDictionary<\/string>
\s*<string>NSObject<\/string>
\s*<\/array>
\s*<key>\$classname<\/key>
\s*<string>NSMutableDictionary<\/string>
\s*<\/dict>'

# Define the file path
file_path="/Library/Preferences/com.apple.networkextension.plist"

# Use grep to search for the pattern in the file and store the result in a variable
result=$(grep -zo "$search_pattern" "$file_path")

if [ -n "$result" ]; then
  echo "<result>Found in the file.</result>"
else
  echo "<result>Not Found in the file.</result>"
fi
