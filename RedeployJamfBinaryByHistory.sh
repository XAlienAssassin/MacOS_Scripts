#!/bin/bash
# ── Configuration ────────────────────────────────────────────────────────────
jssURL=""
apiuser=""
apipass=""
advancedSearchID=""
logDir="/Users/orion.medina/Downloads"
MAX_PARALLEL=5
DAYS_THRESHOLD=10
MDM_RECENCY_DAYS=30
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

if [[ -z "$advancedSearchID" ]]; then
    read -p "Please enter the Advanced Computer Search ID : " advancedSearchID
fi

if [[ -z "$jssURL" || -z "$apiuser" || -z "$apipass" || -z "$advancedSearchID" ]]; then
    echo "ERROR: All fields are required." >&2
    exit 1
fi

jssURL="${jssURL%/}"
mkdir -p "$logDir"
logFile="${logDir}/Redeploy_Jamf_Framework_ByHistory_$(date +%Y%m%d_%H%M%S).log"
touch "$logFile"

exec 3>&1 4>&2
exec 1>>"$logFile" 2>&1

log() {
    echo "$@" >&1
    echo "$@" >&3
}

alias echo="log"

echo "Log file created at: $logFile"

bearer_token=""
token_obtained_at=0

get_bearer_token() {
    echo "Authenticating with Jamf API..."
    local token_response
    token_response=$(curl -s -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token")
    local new_token
    new_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')

    if [[ -z "$new_token" ]]; then
        echo "Error: Failed to obtain bearer token"
        return 1
    fi

    bearer_token="$new_token"
    token_obtained_at=$(date +%s)
    echo "Bearer token obtained successfully"
    return 0
}

refresh_token_if_needed() {
    local now elapsed
    now=$(date +%s)
    elapsed=$(( now - token_obtained_at ))
    # Refresh if older than 25 minutes to stay within the 30-minute expiry
    if [[ $elapsed -ge 1500 ]]; then
        echo "Refreshing bearer token (${elapsed}s elapsed)..."
        get_bearer_token
    fi
}

if ! get_bearer_token; then
    echo "Failed to authenticate. Exiting."
    exit 1
fi

# ── Fetch computers from Advanced Computer Search ────────────────────────────
# Pulls computer IDs via xmllint (same method as RedeployJamfBinary.sh).
# Also tries to pull Last_Check-in if it is a display field in the search —
# which avoids a per-computer Pro API call later and speeds things up.
echo "Fetching computers from Advanced Computer Search ID: $advancedSearchID"

search_results=$(curl -s \
    -H "Authorization: Bearer $bearer_token" \
    -H "Accept: text/xml" \
    "${jssURL}/JSSResource/advancedcomputersearches/id/${advancedSearchID}")

if [[ -z "$search_results" ]]; then
    echo "Error: Empty response from advanced computer search."
    exit 1
fi

echo "Response received (${#search_results} bytes). Extracting computer IDs..."

ids_tmp=$(mktemp)
printf '%s' "$search_results" | xmllint --xpath '//computer/id/text()' - 2>/dev/null | tr ' ' '\n' > "$ids_tmp"
echo "ID extraction: $(wc -l < "$ids_tmp" | tr -d ' ') line(s) from xmllint"

computer_ids=()
while IFS= read -r id; do
    id="${id//[[:space:]]/}"
    [[ "$id" =~ ^[0-9]+$ ]] && computer_ids+=("$id")
done < "$ids_tmp"
rm -f "$ids_tmp"

if [[ ${#computer_ids[@]} -eq 0 ]]; then
    echo "No computers found in Advanced Computer Search ID $advancedSearchID."
    echo "Verify the search ID is correct and returns results in the Jamf Pro UI."
    exit 0
fi

echo "Found ${#computer_ids[@]} computers in the advanced search"

# Try to pull Last_Check-in from the search XML if it was added as a display field.
# Builds a temp file mapping "id last_checkin" so we can look up values without
# needing bash 4 associative arrays (macOS ships bash 3.2).
lct_tmp=$(mktemp)
echo "$search_results" | python3 -c '
import sys
from xml.etree import ElementTree
try:
    root = ElementTree.fromstring(sys.stdin.read())
except ElementTree.ParseError:
    sys.exit(0)
for computer in root.findall(".//computer"):
    cid_el = computer.find("id")
    if cid_el is None or not (cid_el.text or "").strip():
        continue
    cid = cid_el.text.strip()
    lct = ""
    for tag in ("Last_Check-in", "last_contact_time", "Last_Checkin"):
        el = computer.find(tag)
        if el is not None and (el.text or "").strip():
            lct = el.text.strip()
            break
    print(f"{cid} {lct}")
' 2>/dev/null > "$lct_tmp"

# Build the computer_data array: "id|lastContactTime_or_empty"
computer_data=()
for id in "${computer_ids[@]}"; do
    lct=$(grep "^${id} " "$lct_tmp" 2>/dev/null | head -1 | cut -d' ' -f2-)
    computer_data+=("${id}|${lct}")
done
rm -f "$lct_tmp"

# ── Check management history for each computer ───────────────────────────────
# Qualify a computer when BOTH conditions are true:
#   1. lastContactTime is more than DAYS_THRESHOLD days ago (binary has gone dark)
#   2. A completed MDM command exists with a date AFTER lastContactTime
#      (MDM channel is still alive — e.g. CertificateList, DeviceInformation)
# This means the device is reachable via MDM but the Jamf binary is broken/missing,
# so redeploying the framework via MDM will fix it.
echo "Checking management history for each computer in parallel (${MAX_PARALLEL} at a time)..."

threshold_seconds=$(( DAYS_THRESHOLD * 86400 ))
now_epoch=$(date +%s)

tmp_qualify=$(mktemp -d)

qualify_job_count=0
for entry in "${computer_data[@]}"; do
    (
        IFS='|' read -r comp_id last_contact_str <<< "$entry"

        # If Last Check-in was not a display field in the search, fetch it from the Pro API
        if [[ -z "$last_contact_str" ]]; then
            inv=$(curl -s \
                -H "Authorization: Bearer $bearer_token" \
                -H "Accept: application/json" \
                "${jssURL}/api/v1/computers-inventory/${comp_id}?section=GENERAL")
            last_contact_str=$(echo "$inv" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read(), strict=False)
print((data.get('general') or {}).get('lastContactTime', ''))
" 2>/dev/null)
        fi

        if [[ -z "$last_contact_str" ]]; then
            log "Warning: Could not determine lastContactTime for computer $comp_id — skipping"
            exit 0
        fi

        # Parse the date to epoch — handles both ISO 8601 (Pro API) and "YYYY-MM-DD HH:MM:SS" (Classic API)
        last_contact_epoch=$(python3 -c "
import sys
from datetime import datetime, timezone
s = sys.argv[1]
for fmt in ('%Y-%m-%dT%H:%M:%SZ', '%Y-%m-%dT%H:%M:%S.%fZ',
            '%Y-%m-%dT%H:%M:%S+0000', '%Y-%m-%dT%H:%M:%S.%f+0000',
            '%Y-%m-%dT%H:%M:%S',
            '%Y-%m-%d %H:%M:%S', '%Y-%m-%d'):
    try:
        dt = datetime.strptime(s, fmt)
        print(int(dt.replace(tzinfo=timezone.utc).timestamp()))
        sys.exit(0)
    except ValueError:
        pass
print('')
" "$last_contact_str" 2>/dev/null)

        if [[ -z "$last_contact_epoch" ]]; then
            log "Warning: Could not parse lastContactTime for computer $comp_id: '$last_contact_str' — skipping"
            exit 0
        fi

        # Condition 1: binary hasn't checked in for more than DAYS_THRESHOLD days
        days_since_checkin=$(( (now_epoch - last_contact_epoch) / 86400 ))
        if [[ $(( now_epoch - last_contact_epoch )) -le $threshold_seconds ]]; then
            log "Computer $comp_id skipped: checked in ${days_since_checkin}d ago (within ${DAYS_THRESHOLD}d threshold)"
            exit 0
        fi

        # Condition 2: fetch Classic API management history and look for a completed MDM
        # command dated AFTER lastContactTime — proving the MDM channel is still responsive
        history=$(curl -s \
            -H "Authorization: Bearer $bearer_token" \
            -H "Accept: text/xml" \
            "${jssURL}/JSSResource/computerhistory/id/${comp_id}")

        if [[ -z "$history" ]]; then
            log "Warning: Empty history response for computer $comp_id — skipping"
            exit 0
        fi

        # Parse completed MDM command dates from commands/completed/command.
        # Date fields are completed_epoch (milliseconds) and completed_utc — NOT date_completed_*.
        # The <completed> text element is human-readable ("Today at 4:15 PM") and unparseable.
        most_recent_mdm_epoch=$(echo "$history" | python3 -c '
import sys
from datetime import datetime, timezone
from xml.etree import ElementTree
try:
    root = ElementTree.fromstring(sys.stdin.read())
except ElementTree.ParseError:
    print("")
    sys.exit(0)

most_recent = 0
for cmd in root.findall(".//commands/completed/command"):
    # completed_epoch is milliseconds — most reliable
    el = cmd.find("completed_epoch")
    if el is not None and (el.text or "").strip():
        try:
            epoch = int(el.text.strip()) // 1000
            if epoch > most_recent:
                most_recent = epoch
            continue
        except ValueError:
            pass
    # Fall back to completed_utc ISO string
    el = cmd.find("completed_utc")
    if el is not None and (el.text or "").strip():
        val = el.text.strip()
        for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z",
                    "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ"):
            try:
                dt = datetime.strptime(val, fmt)
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                epoch = int(dt.timestamp())
                if epoch > most_recent:
                    most_recent = epoch
                break
            except ValueError:
                pass

print(most_recent if most_recent > 0 else "")
')

        if [[ -z "$most_recent_mdm_epoch" ]]; then
            log "Computer $comp_id skipped: no completed MDM commands found in history (MDM channel may also be dead)"
            exit 0
        fi

        # MDM command must be recent relative to today (MDM_RECENCY_DAYS) AND after last check-in.
        # Without the recency check, a command sent the same day as the last check-in would qualify
        # even if both were months ago — meaning the MDM channel is also dead.
        days_since_mdm=$(( (now_epoch - most_recent_mdm_epoch) / 86400 ))
        if [[ $days_since_mdm -gt $MDM_RECENCY_DAYS ]]; then
            log "Computer $comp_id skipped: binary dark ${days_since_checkin}d, but last MDM command was ${days_since_mdm}d ago (older than ${MDM_RECENCY_DAYS}d recency threshold)"
            exit 0
        fi

        if [[ $most_recent_mdm_epoch -gt $last_contact_epoch ]]; then
            days_mdm_after=$(( (most_recent_mdm_epoch - last_contact_epoch) / 86400 ))
            log "Computer $comp_id qualifies: binary dark ${days_since_checkin}d, MDM active (last MDM command ${days_mdm_after}d after last check-in)"
            touch "${tmp_qualify}/qualify_${comp_id}"
        else
            log "Computer $comp_id skipped: binary dark ${days_since_checkin}d, but no MDM activity since last check-in (MDM may also be dead)"
        fi
    ) &

    qualify_job_count=$(( qualify_job_count + 1 ))
    if [[ $qualify_job_count -ge $MAX_PARALLEL ]]; then
        wait
        qualify_job_count=0
    fi
done

wait

computers_to_redeploy=($(ls "${tmp_qualify}"/qualify_* 2>/dev/null | sed 's/.*qualify_//'))
rm -rf "$tmp_qualify"

echo ""
echo "History check complete. Found ${#computers_to_redeploy[@]} computer(s) to redeploy."

if [[ ${#computers_to_redeploy[@]} -eq 0 ]]; then
    echo "No computers qualify for redeploy."
    exit 0
fi

echo "Computer IDs queued for redeploy: ${computers_to_redeploy[*]}"
echo ""

# ── Confirm and redeploy ─────────────────────────────────────────────────────
printf "Do you want to continue with redeploying the Jamf Management Framework for %d computer(s)? (yes/no): " "${#computers_to_redeploy[@]}" >&3
read confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Redeploy process aborted by user."
    exit 0
fi

tmp_dir=$(mktemp -d)

echo "Starting redeploy for ${#computers_to_redeploy[@]} computers (${MAX_PARALLEL} at a time)..."

job_count=0
for id in "${computers_to_redeploy[@]}"; do
    (
        log "Redeploying Jamf Management Framework for Computer ID: $id"

        response=$(curl -s -w "\n%{http_code}" -X POST "${jssURL}/api/v1/jamf-management-framework/redeploy/${id}" \
            -H "Authorization: Bearer $bearer_token")

        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')

        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            log "Redeploy sent successfully for computer $id"
            log "Response: $body"
            touch "${tmp_dir}/success_${id}"
        else
            log "Error: Failed to redeploy for computer $id (HTTP $http_code)"
            log "Response: $body"
            touch "${tmp_dir}/failed_${id}"
        fi
    ) &

    job_count=$(( job_count + 1 ))
    if [[ $job_count -ge $MAX_PARALLEL ]]; then
        wait
        job_count=0
    fi
done

wait

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
