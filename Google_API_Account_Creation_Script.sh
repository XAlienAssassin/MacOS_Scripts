#!/bin/bash

# Variables
API_KEY="${AIzaSyCi8ZADJekNT5-aZY4r_xaJKzUcoIpxGBE}"  # Use an environment variable for the API key
SHEET_ID="1DeLwFWUjC8sG5DYi8a1T65M2VUw9bZ34sLKYaAG52CM"
RANGE="Sheet1!A2:B"

# Google Sheets API URLx
URL="https://sheets.googleapis.com/v4/spreadsheets/$SHEET_ID/values/$RANGE?key=$API_KEY"

# Fetch data
response=$(curl -s "$URL")

# Assume the JSON is flat and values are in double quotes, parse using grep and cut
echo "$response" | grep -op '"values": \[\[\K[^\]]+' | tr -d '[]" ' | tr ',' '\n' | while read -r name; do
  if ! read -r username; then
    break
  fi

  # Check if user already exists
  if id "$username" &>/dev/null; then
    echo "Account for $username already exists, skipping..."
  else
    # Create the user account
    sudo dscl . -create /Users/"$username"
    sudo dscl . -create /Users/"$username" UserShell /bin/bash
    sudo dscl . -create /Users/"$username" RealName "$name"
    sudo dscl . -create /Users/"$username" UniqueID "$(id -u "$username" 2>/dev/null || echo $((6000 + RANDOM%1000)))"
    sudo dscl . -create /Users/"$username" PrimaryGroupID 20
    sudo dscl . -create /Users/"$username" NFSHomeDirectory /Users/"$username"
    sudo createhomedir -c -u "$username"

    echo "User $username created successfully with full name $name."
    # Update the Google Sheet to mark the user as processed
    # (not implemented in this snippet)
  fi
done

echo "Script execution completed."
