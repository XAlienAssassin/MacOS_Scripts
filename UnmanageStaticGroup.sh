#!/bin/bash
# ── Configuration ────────────────────────────────────────────────────────────
jssURL=""
apiuser=""
apipass=""
staticGroupID=""
logDir="/Users/orion.medina/Downloads"
MAX_PARALLEL=5
# ─────────────────────────────────────────────────────────────────────────────

if [[ -z "$jssURL" ]]; then
    read -p "Please enter your Jamf Pro server URL : " jssURL
fi

if [[ -z "$apiuser" ]]; then
    read -p "Please enter your Jamf Pro user account : " apiuser
fi

if [[ -z "$apipass" ]]; then
    read -p "Please enter the password for the $apiuser account : " -s apipass
    echo
fi

if [[ -z "$staticGroupID" ]]; then
    read -p "Please enter the Static Computer Group ID : " staticGroupID
fi

if [[ -z "$jssURL" || -z "$apiuser" || -z "$apipass" || -z "$staticGroupID" ]]; then
    echo "ERROR: All fields are required." >&2
    exit 1
fi

jssURL="${jssURL%/}"
mkdir -p "$logDir"
logFile="${logDir}/Unmanage_Static_Group_$(date +%Y%m%d_%H%M%S).log"
touch "$logFile"

# Save original stdout/stderr, then redirect output to log file
exec 3>&1 4>&2
exec 1>>"$logFile" 2>&1

log() {
    echo "$@" >&1
    echo "$@" >&3
}

alias echo="log"

echo "Log file created at: $logFile"

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

# Get static computer group members
echo "Fetching computers from static group ID: $staticGroupID"
group_results=$(curl -s -H "Accept: text/xml" -H "Authorization: Bearer $bearer_token" "${jssURL}/JSSResource/computergroups/id/${staticGroupID}")

# Verify the group exists and is a static group
is_smart=$(echo "$group_results" | xmllint --xpath '//computer_group/is_smart/text()' - 2>/dev/null)
group_name=$(echo "$group_results" | xmllint --xpath '//computer_group/name/text()' - 2>/dev/null)

if [[ -z "$group_name" ]]; then
    echo "Error: Could not find a computer group with ID $staticGroupID" >&3
    echo "Error: Could not find a computer group with ID $staticGroupID"
    exit 1
fi

if [[ "$is_smart" == "true" ]]; then
    echo "Error: Group '$group_name' is a smart group. This script only supports static groups." >&3
    echo "Error: Group '$group_name' is a smart group. This script only supports static groups."
    exit 1
fi

echo "Group found: $group_name"

# Extract all computer IDs from the group
echo "Extracting computer IDs from group..."

computer_ids=()
echo "$group_results" | xmllint --xpath '//computer_group/computers/computer/id/text()' - 2>/dev/null > /tmp/computer_ids.txt
while read -r id; do
    if [[ ! -z "$id" ]]; then
        computer_ids+=("$id")
        echo "Found computer ID: $id"
    fi
done < /tmp/computer_ids.txt
rm /tmp/computer_ids.txt

echo "Found ${#computer_ids[@]} computers in the static group"

if [[ ${#computer_ids[@]} -eq 0 ]]; then
    echo "No computers found in group. Exiting." >&3
    echo "No computers found in group. Exiting."
    exit 0
fi

# Ask the user if they want to continue
echo ""
echo "Computer IDs queued for unmanagement: ${computer_ids[*]}"
echo ""
printf "Do you want to continue with unmanaging all %d computers in '%s'? (yes/no): " "${#computer_ids[@]}" "$group_name" >&3
read confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Unmanage process aborted by user."
    exit 0
fi

# Temp directory to track per-computer results from parallel subshells
tmp_dir=$(mktemp -d)

# Loop through all computer IDs and unmanage in parallel
echo "Starting to unmanage all computers (${MAX_PARALLEL} at a time)..."

job_count=0
for id in "${computer_ids[@]}"; do
    (
        echo "Unmanaging Computer ID: $id"

        response=$(curl -s -w "\n%{http_code}" -X POST "${jssURL}/api/v1/computer-inventory/${id}/remove-mdm-profile" \
            -H "Authorization: Bearer $bearer_token")

        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')

        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            echo "Unmanaged successfully: computer $id"
            echo "Response: $body"
            touch "${tmp_dir}/success_${id}"
        else
            echo "Error: Failed to unmanage computer $id (HTTP $http_code)"
            echo "Response: $body"
            touch "${tmp_dir}/failed_${id}"
        fi
    ) &

    job_count=$((job_count + 1))
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

echo "Unmanage process completed."
echo "Successful: ${#successful_computers[@]} computers"
echo "Failed: ${#failed_computers[@]} computers"

if [[ ${#failed_computers[@]} -gt 0 ]]; then
    echo "Failed computer IDs: ${failed_computers[*]}"
fi

if [[ ${#successful_computers[@]} -gt 0 ]]; then
    echo "Successful computer IDs: ${successful_computers[*]}"
fi
