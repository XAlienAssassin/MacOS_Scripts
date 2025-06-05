#!/bin/bash
# Create a timestamped log file name
timestamp=$(date +"%Y%m%d_%H%M%S")
logFile="/Library/Logs/Wipe_Computers_${timestamp}.log"

# Set up logging to both file and terminal
# Create the log file
touch "$logFile"

# Set up logging to both file and terminal without using tee
# Save original stdout and stderr
exec 3>&1 4>&2

# Redirect stdout and stderr to the log file
exec 1>>"$logFile" 2>&1

# Define a function to echo to both log file and original stdout
log() {
    echo "$@" >&1
    echo "$@" >&3
}

# Use log function instead of echo for all subsequent output
alias echo="log"

echo "Log file created at: $logFile"

# Prompt for API credentials
echo "Enter your Jamf API username: "
read -u 3 apiuser
echo "Enter your Jamf API password: "
read -s -u 3 apipass
echo "Enter the Advanced Computer Search ID: "
read -u 3 advancedSearchID
echo

# URL (https://yourjamfserver.jamfcloud.com)
jssURL="https://macapps.saintandrews.net:8443"

# Get the Bearer Token
echo "Authenticating with Jamf API..."
token_response=$(curl -s -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token")
bearer_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')

# Get advanced computer search results
echo "Fetching computers from advanced search ID: $advancedSearchID"
search_results=$(curl -s -H "Accept: text/xml" -H "Authorization: Bearer $bearer_token" "${jssURL}/JSSResource/advancedcomputersearches/id/${advancedSearchID}")

# Extract all computer IDs from the search results
echo "Extracting computer IDs from search results..."

computer_ids=()
# Save the results to a temporary file
echo "$search_results" | xmllint --xpath '//computer/id/text()' - 2>/dev/null > /tmp/computer_ids.txt
while read -r id; do
    if [[ ! -z "$id" ]]; then
        computer_ids+=("$id")
        echo "Found computer ID: $id"
    fi
done < /tmp/computer_ids.txt
rm /tmp/computer_ids.txt

# Count the number of computers found
echo "Found ${#computer_ids[@]} computers in the advanced search"

# Ask the user if they want to continue
echo -n "Do you want to continue with the wipe process? (yes/no): "
read -u 3 confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Wipe process aborted by user."
    exit 0
fi

# Loop through all computer IDs and wipe computers
echo "Starting to wipe all computers..."
for id in "${computer_ids[@]}"; do
    echo "Wiping Computer: $id"
    remove_result=$(curl -s -X POST "${jssURL}/api/v1/computer-inventory/${id}/erase" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $bearer_token")
    
    echo "$remove_result"
    
    # Add a small delay to avoid overwhelming the server
    sleep 1
done

echo "Wipe process completed."