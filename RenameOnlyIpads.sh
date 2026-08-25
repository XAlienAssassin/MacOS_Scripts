#!/bin/bash
# ── Configuration ────────────────────────────────────────────────────────────
jssURL="https://macapps.saintandrews.net:8443"
apiuser="orion.medina@saintandrews.net"
apipass=""
csvFile="${HOME}/Documents/GitHub/MacOS_Scripts/StragglerIpads.csv"
logDir="${HOME}/Downloads"
MAX_RETRIES=3
RETRY_DELAY_SECONDS=5
VERIFY_WAIT_SECONDS=120
# ─────────────────────────────────────────────────────────────────────────────
#
# Rename-only remediation for iPads that went through RenameAndWipeIpads.sh's
# Return to Service wipe but came back still showing their old/default name —
# the rename MDM command hadn't landed on the device before the wipe fired, so
# the erase overwrote it. No erase here: just send the rename, wait for the
# device to check in, then verify the name actually landed in Jamf.
#
# CSV format (with header row):
#   SerialNumber,NewName
#   DMPXXXXXXX1,LSKA-13

for dep in curl python3; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "ERROR: '$dep' is required but not found on this machine (install it, e.g. via Xcode Command Line Tools or Homebrew, and re-run)." >&2
        exit 1
    fi
done

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

if [[ -z "$csvFile" ]]; then
    read -p "Please enter the path to the CSV file (SerialNumber,NewName) : " csvFile
fi

if [[ -z "$jssURL" || -z "$apiuser" || -z "$apipass" || -z "$csvFile" ]]; then
    echo "ERROR: All fields are required." >&2
    exit 1
fi

if [[ ! -f "$csvFile" ]]; then
    echo "ERROR: CSV file not found: $csvFile" >&2
    exit 1
fi

jssURL="${jssURL%/}"
mkdir -p "$logDir"
logFile="${logDir}/Rename_Only_iPads_$(date +%Y%m%d_%H%M%S).log"
touch "$logFile"

exec 3>&1 4>&2
exec 1>>"$logFile" 2>&1
exec 5>>"$logFile"

log() {
    echo "$@" >&5
    echo "$@" >&3
}

log "Log file created at: $logFile"

curl_retry() {
    local attempt=1
    local output=""
    local rc=0
    while (( attempt <= MAX_RETRIES )); do
        output=$(curl "$@")
        rc=$?
        if [[ $rc -eq 0 ]]; then
            printf '%s' "$output"
            return 0
        fi
        if (( attempt < MAX_RETRIES )); then
            log "Network error (curl exit $rc) on attempt ${attempt}/${MAX_RETRIES} — retrying in ${RETRY_DELAY_SECONDS}s..."
            sleep "$RETRY_DELAY_SECONDS"
        fi
        attempt=$(( attempt + 1 ))
    done
    log "Network error: curl failed after ${MAX_RETRIES} attempts (exit code $rc)"
    printf '%s' "$output"
    return "$rc"
}

bearer_token=""

get_bearer_token() {
    log "Authenticating with Jamf API..."
    local token_response
    token_response=$(curl_retry -s --connect-timeout 10 --max-time 30 -u "${apiuser}:${apipass}" -X POST "${jssURL}/api/v1/auth/token")
    local new_token
    new_token=$(echo "$token_response" | awk -F'"' '/token/{print $4}')

    if [[ -z "$new_token" ]]; then
        log "Error: Failed to obtain bearer token"
        return 1
    fi

    bearer_token="$new_token"
    log "Bearer token obtained successfully"
    return 0
}

if ! get_bearer_token; then
    log "Failed to authenticate. Exiting."
    exit 1
fi

# ── Parse CSV (skip header row) ───────────────────────────────────────────────
serials=()
newnames=()

lineno=0
while IFS=, read -r rawSerial rawName; do
    lineno=$(( lineno + 1 ))

    if [[ $lineno -eq 1 ]]; then
        headerCheck="$(echo -n "$rawSerial" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
        if [[ "$headerCheck" == "serialnumber" || "$headerCheck" == "serial" ]]; then
            continue
        fi
    fi

    serial="${rawSerial//[$'\r\n']/}"
    serial="${serial// /}"
    newname="${rawName//[$'\r\n']/}"
    newname="$(echo -n "$newname" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    [[ -z "$serial" || -z "$newname" ]] && continue

    serials+=("$serial")
    newnames+=("$newname")
done < "$csvFile"

total=${#serials[@]}

if [[ $total -eq 0 ]]; then
    log "No serial number / name pairs found in $csvFile"
    exit 0
fi

log ""
log "The following $total iPad(s) will be renamed (no erase):"
for (( i = 0; i < total; i++ )); do
    log "$(printf '  %2d. %-20s -> %s' "$(( i + 1 ))" "${serials[$i]}" "${newnames[$i]}")"
done
log ""

printf "Type the number of iPads listed above (%d) to confirm and proceed: " "$total" >&3
read confirm_count
if [[ "$confirm_count" != "$total" ]]; then
    log "Confirmation did not match (you entered '$confirm_count', expected $total). Aborted."
    exit 0
fi

# ── Look up a device by serial number ─────────────────────────────────────────
# Prints "mobileDeviceId|managementId|currentDisplayName" or nothing if not found.
lookup_device() {
    local serial="$1"
    local attempt response http_code body
    for attempt in 1 2; do
        response=$(curl_retry -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -G "${jssURL}/api/v2/mobile-devices/detail" \
            -H "Authorization: Bearer $bearer_token" \
            -H "Accept: application/json" \
            --data-urlencode "filter=serialNumber==\"${serial}\"" \
            --data-urlencode "section=GENERAL")
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')

        if [[ "$http_code" == "401" && $attempt -eq 1 ]]; then
            log "Bearer token rejected (401) during lookup for serial $serial — refreshing and retrying..."
            get_bearer_token
            continue
        fi

        if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            log "Warning: Lookup for serial $serial failed with HTTP $http_code (not a 'not found' — an API error)"
            log "Response: $body"
            return 0
        fi

        echo "$body" | python3 -c '
import sys, json
try:
    data = json.loads(sys.stdin.read())
except ValueError:
    sys.exit(0)
results = data.get("results") or []
if not results:
    sys.exit(0)
device = results[0]
general = device.get("general") or {}
mobile_device_id = device.get("mobileDeviceId", "")
management_id = general.get("managementId", "")
display_name = general.get("displayName", "")
if mobile_device_id and management_id:
    print(f"{mobile_device_id}|{management_id}|{display_name}")
' 2>/dev/null
        return 0
    done
}

# ── Rename a device via MDM Settings command ──────────────────────────────────
rename_device() {
    local management_id="$1"
    local new_name="$2"
    local payload
    payload=$(python3 -c '
import json, sys
management_id, new_name = sys.argv[1], sys.argv[2]
print(json.dumps({
    "clientData": [{"managementId": management_id}],
    "commandData": {"commandType": "SETTINGS", "deviceName": new_name}
}))
' "$management_id" "$new_name")

    curl_retry -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X POST "${jssURL}/api/v2/mdm/commands" \
        -H "Authorization: Bearer $bearer_token" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$payload"
}

# ── Step 1: rename each iPad ───────────────────────────────────────────────────
renamed_serials=()
renamed_targets=()

for (( i = 0; i < total; i++ )); do
    serial="${serials[$i]}"
    newname="${newnames[$i]}"

    log "Looking up serial $serial..."
    lookup_result=$(lookup_device "$serial")

    if [[ -z "$lookup_result" ]]; then
        log "Warning: Could not find an iPad with serial number $serial in Jamf — skipping"
        continue
    fi

    IFS='|' read -r mobile_device_id management_id current_name <<< "$lookup_result"
    log "Found iPad ID $mobile_device_id (currently '${current_name}') for serial $serial"

    rename_response=$(rename_device "$management_id" "$newname")
    rename_http_code=$(echo "$rename_response" | tail -n1)
    rename_body=$(echo "$rename_response" | sed '$d')

    if [[ "$rename_http_code" == "401" ]]; then
        log "Bearer token rejected (401) during rename for serial $serial — refreshing and retrying..."
        get_bearer_token
        rename_response=$(rename_device "$management_id" "$newname")
        rename_http_code=$(echo "$rename_response" | tail -n1)
        rename_body=$(echo "$rename_response" | sed '$d')
    fi

    if [[ "$rename_http_code" =~ ^2[0-9][0-9]$ ]]; then
        log "Rename command queued: $serial -> $newname (iPad ID $mobile_device_id)"
        renamed_serials+=("$serial")
        renamed_targets+=("$newname")
    else
        log "Error: Failed to queue rename for serial $serial (HTTP $rename_http_code)"
        log "Response: $rename_body"
    fi
done

if [[ ${#renamed_serials[@]} -eq 0 ]]; then
    log "No rename commands were successfully queued — nothing to verify."
    exit 0
fi

# ── Step 2: wait, then verify the name actually landed ────────────────────────
log ""
log "Waiting ${VERIFY_WAIT_SECONDS}s for devices to check in and apply the rename..."
sleep "$VERIFY_WAIT_SECONDS"

log ""
log "── Verification ──────────────────────────────────────"
still_wrong=()
for (( i = 0; i < ${#renamed_serials[@]}; i++ )); do
    serial="${renamed_serials[$i]}"
    target="${renamed_targets[$i]}"

    lookup_result=$(lookup_device "$serial")
    if [[ -z "$lookup_result" ]]; then
        log "Warning: Could not re-look-up serial $serial for verification"
        continue
    fi
    IFS='|' read -r mobile_device_id management_id current_name <<< "$lookup_result"

    if [[ "$current_name" == "$target" ]]; then
        log "OK: $serial is now named '$current_name'"
    else
        log "STILL WRONG: $serial expected '$target' but Jamf shows '$current_name' — did not land in time"
        still_wrong+=("$serial")
    fi
done

log ""
if [[ ${#still_wrong[@]} -eq 0 ]]; then
    log "All renamed devices verified successfully."
else
    log "${#still_wrong[@]} device(s) still did not pick up the new name in time: ${still_wrong[*]}"
    log "These devices may be offline or slow to check in — re-run this script against just those serials once they're back online."
fi

log ""
log "Rename-only process completed."
