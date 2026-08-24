#!/bin/bash
# ── Configuration ────────────────────────────────────────────────────────────
jssURL=""
apiuser=""
apipass=""
csvFile=""
logDir="${HOME}/Downloads"
BATCH_SIZE="${BATCH_SIZE:-5}"
WAIT_SECONDS="${WAIT_SECONDS:-600}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-5}"
# ─────────────────────────────────────────────────────────────────────────────
#
# CSV format (with header row):
#   SerialNumber,NewName
#   DMPXXXXXXX1,LSKA
#   DMPXXXXXXX2,LSKB
#
# Flow, in batches of $BATCH_SIZE iPads at a time:
#   1. Rename each iPad (MDM Settings command -> deviceName)
#   2. Wait $WAIT_SECONDS so the rename lands before the wipe is queued
#   3. Erase each iPad with Return to Service enabled (re-enrolls + re-downloads
#      apps automatically instead of needing someone at the device)
#   4. Wait $WAIT_SECONDS before starting the next batch (bandwidth throttling —
#      each iPad re-downloading its apps at once saturates the connection)
#
# Requires a Return to Service configuration already set up and scoped in
# Jamf Pro — the erase call will fail with "Return to service requirements
# not met" otherwise.

# Re-exec under caffeinate so the Mac can't sleep mid-run (this script sleeps
# for $WAIT_SECONDS between steps and can take a long time end to end).
if [[ "$(uname)" == "Darwin" ]] && command -v caffeinate >/dev/null 2>&1 && [[ -z "$CAFFEINATED" ]]; then
    export CAFFEINATED=1
    exec caffeinate -i bash "$0" "$@"
fi

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
logFile="${logDir}/Rename_And_Wipe_iPads_$(date +%Y%m%d_%H%M%S).log"
touch "$logFile"

exec 3>&1 4>&2
exec 1>>"$logFile" 2>&1
exec 5>>"$logFile"

# log() writes to a dedicated fd (5) pointed at the log file, not fd 1 — so it's
# still safe to call from inside a curl_retry that's itself nested in a
# $(...) capture (which redirects fd 1 to the capture, not the log file).
log() {
    echo "$@" >&5
    echo "$@" >&3
}

log "Log file created at: $logFile"

# ── Retry wrapper for transient network failures ──────────────────────────────
# Retries only on curl's own network-level failures (timeout, connection
# refused, DNS failure, etc — non-zero exit code). An HTTP error response
# (4xx/5xx) still exits 0 since we don't pass --fail, so those are NOT
# retried here — only genuine "the internet blipped" cases are.
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
token_obtained_at=0

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
    token_obtained_at=$(date +%s)
    log "Bearer token obtained successfully"
    return 0
}

refresh_token_if_needed() {
    local now elapsed
    now=$(date +%s)
    elapsed=$(( now - token_obtained_at ))
    # Refresh if older than 25 minutes to stay within the 30-minute expiry
    if [[ $elapsed -ge 1500 ]]; then
        log "Refreshing bearer token (${elapsed}s elapsed)..."
        get_bearer_token
    fi
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

    # Skip a header row only if it actually looks like one (e.g. "SerialNumber,NewName") —
    # don't blindly drop line 1, since CSVs without a header are also valid input here.
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

batches=$(( (total + BATCH_SIZE - 1) / BATCH_SIZE ))

log ""
log "The following $total iPad(s) will be renamed, then wiped with Return to Service:"
for (( i = 0; i < total; i++ )); do
    log "$(printf '  %2d. %-20s -> %s' "$(( i + 1 ))" "${serials[$i]}" "${newnames[$i]}")"
done
log ""
log "That's $total iPad(s) from $csvFile, in $batches batch(es) of up to $BATCH_SIZE."

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
    local response
    response=$(curl_retry -s --connect-timeout 10 --max-time 30 -G "${jssURL}/api/v2/mobile-devices/detail" \
        -H "Authorization: Bearer $bearer_token" \
        -H "Accept: application/json" \
        --data-urlencode "filter=serialNumber==\"${serial}\"" \
        --data-urlencode "section=GENERAL")

    echo "$response" | python3 -c '
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

# ── Erase a device with Return to Service ─────────────────────────────────────
erase_device() {
    local mobile_device_id="$1"
    curl_retry -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X POST "${jssURL}/api/v2/mobile-devices/${mobile_device_id}/erase" \
        -H "Authorization: Bearer $bearer_token" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d '{"returnToService": true}'
}

# ── Process batches ────────────────────────────────────────────────────────────
batch_num=0
index=0
while [[ $index -lt $total ]]; do
    batch_num=$(( batch_num + 1 ))
    log ""
    log "── Batch ${batch_num}/${batches} ──────────────────────────────────────"

    batch_start=$index
    batch_end=$(( index + BATCH_SIZE - 1 ))
    [[ $batch_end -ge $total ]] && batch_end=$(( total - 1 ))

    batch_mobile_ids=()
    batch_serials=()

    refresh_token_if_needed

    # Step 1: rename each iPad in this batch
    for (( i = batch_start; i <= batch_end; i++ )); do
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

        if [[ "$rename_http_code" =~ ^2[0-9][0-9]$ ]]; then
            log "Rename command queued: $serial -> $newname (iPad ID $mobile_device_id)"
            batch_mobile_ids+=("$mobile_device_id")
            batch_serials+=("$serial")
        else
            log "Error: Failed to queue rename for serial $serial (HTTP $rename_http_code)"
            log "Response: $rename_body"
        fi
    done

    if [[ ${#batch_mobile_ids[@]} -eq 0 ]]; then
        log "No iPads in this batch were successfully renamed — skipping wipe for this batch."
        index=$(( batch_end + 1 ))
        continue
    fi

    log "Waiting ${WAIT_SECONDS}s for renames to land before wiping this batch..."
    sleep "$WAIT_SECONDS"

    refresh_token_if_needed

    # Step 2: erase each renamed iPad in this batch with Return to Service
    for (( i = 0; i < ${#batch_mobile_ids[@]}; i++ )); do
        mobile_device_id="${batch_mobile_ids[$i]}"
        serial="${batch_serials[$i]}"

        log "Erasing iPad ID $mobile_device_id (serial $serial) with Return to Service..."
        erase_response=$(erase_device "$mobile_device_id")
        erase_http_code=$(echo "$erase_response" | tail -n1)
        erase_body=$(echo "$erase_response" | sed '$d')

        if [[ "$erase_http_code" =~ ^2[0-9][0-9]$ ]]; then
            log "Erase command queued for serial $serial (iPad ID $mobile_device_id)"
        else
            log "Error: Failed to queue erase for serial $serial (iPad ID $mobile_device_id) (HTTP $erase_http_code)"
            log "Response: $erase_body"
        fi
    done

    index=$(( batch_end + 1 ))

    if [[ $index -lt $total ]]; then
        log "Waiting ${WAIT_SECONDS}s before starting the next batch..."
        sleep "$WAIT_SECONDS"
    fi
done

log ""
log "Rename + Return to Service wipe process completed."
