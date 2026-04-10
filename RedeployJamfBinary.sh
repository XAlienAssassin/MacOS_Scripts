#!/bin/bash
# Create a timestamped log file name
timestamp=$(date +"%Y%m%d_%H%M%S")
logFile="$HOME/Library/Logs/Redeploy_Jamf_Framework_${timestamp}.log"

# Set up logging to both file and terminal
# Create the log file
touch "$logFile"

# Save original stdout/stderr, then redirect output to log file
exec 3>&1 4>&2
exec 1>>"$logFile" 2>&1

# Define a function to echo to both log file and original stdout
log() {
    echo "$@" >&1
    echo "$@" >&3
}

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

# How many redeployments to run at once
MAX_PARALLEL=10

# Function to get a new bearer token
get_bearer_token() {
    echo "Authenticating with Jamf API..."
    local token_response=$(curl -s -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token")
    local new_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')

    if [[ -z "$new_token" ]]; then
        echo "Error: Failed to obtain bearer token"
        return 1
    fi

    bearer_token="$new_token"
    echo "Bearer token obtained successfully"
    return 0
}

# Get initial Bearer Token
if ! get_bearer_token; then
    echo "Failed to authenticate. Exiting."
    exit 1
fi

# Get advanced computer search results
echo "Fetching computers from advanced search ID: $advancedSearchID"
search_results=$(curl -s -H "Accept: text/xml" -H "Authorization: Bearer $bearer_token" "${jssURL}/JSSResource/advancedcomputersearches/id/${advancedSearchID}")

# Extract all computer IDs from the search results
echo "Extracting computer IDs from search results..."

computer_ids=()
echo "$search_results" | xmllint --xpath '//computer/id/text()' - 2>/dev/null > /tmp/computer_ids.txt
while read -r id; do
    if [[ ! -z "$id" ]]; then
        computer_ids+=("$id")
        echo "Found computer ID: $id"
    fi
done < /tmp/computer_ids.txt
rm /tmp/computer_ids.txt

echo "Found ${#computer_ids[@]} computers in the advanced search"

# Ask the user if they want to continue
echo -n "Do you want to continue with redeploying the Jamf Management Framework? (yes/no): "
read -u 3 confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Redeploy process aborted by user."
    exit 0
fi

# Temp directory to track per-computer results from parallel subshells
tmp_dir=$(mktemp -d)

# Loop through all computer IDs and redeploy in parallel
echo "Starting to redeploy Jamf Management Framework for all computers (${MAX_PARALLEL} at a time)..."

job_count=0
for id in "${computer_ids[@]}"; do
    (
        echo "Redeploying Jamf Management Framework for Computer ID: $id"

        response=$(curl -s -w "\n%{http_code}" -X POST "${jssURL}/api/v1/jamf-management-framework/redeploy/${id}" \
            -H "Authorization: Bearer $bearer_token")

        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')

        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            echo "Redeploy sent successfully for computer $id"
            echo "Response: $body"
            touch "${tmp_dir}/success_${id}"
        else
            echo "Error: Failed to redeploy for computer $id (HTTP $http_code)"
            echo "Response: $body"
            touch "${tmp_dir}/failed_${id}"
        fi
    ) &

    job_count=$((job_count + 1))
    # Wait for the current batch to finish before starting the next one
    if [[ $job_count -ge $MAX_PARALLEL ]]; then
        wait
        job_count=0
    fi
done

# Wait for any remaining background jobs
wait

# Collect results from temp files
successful_computers=($(ls "${tmp_dir}"/success_* 2>/dev/null | sed 's/.*success_//'))
failed_computers=($(ls "${tmp_dir}"/failed_* 2>/dev/null | sed 's/.*failed_//'))
rm -rf "$tmp_dir"

echo "Redeploy process completed."
echo "Successful: ${#successful_computers[@]} computers"
echo "Failed: ${#failed_computers[@]} computers"

if [[ ${#failed_computers[@]} -gt 0 ]]; then
    echo "Failed computer IDs: ${failed_computers[*]}"
fi

if [[ ${#successful_computers[@]} -gt 0 ]]; then
    echo "Successful computer IDs: ${successful_computers[*]}"
fi
