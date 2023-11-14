#!/bin/bash

# Define the word you want to search for
search_word="com.sophos.endpoint.network"

# Define the file path
file_path="/Library/Preferences/com.apple.networkextension.plist"

# Use grep to search for the word in the file and store the result in a variable
result=$(grep -i "$search_word" "$file_path")

if [ -n "$result" ]; then
  echo "<result>Found in the plist file.</result>"
else
  echo "<result>Not Found in the plist file.</result>"
fi