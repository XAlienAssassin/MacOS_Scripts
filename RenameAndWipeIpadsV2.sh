#!/bin/bash
# ── Configuration ────────────────────────────────────────────────────────────
jssURL="https://macapps.saintandrews.net:8443"
apiuser="orion.medina@saintandrews.net"
apipass=""
csvFile=""
logDir="${HOME}/Downloads"
BATCH_SIZE=12
RENAME_VERIFY_WAIT_SECONDS=60
MAX_RENAME_ATTEMPTS=3
POST_WIPE_WAIT_SECONDS=420
MAX_RETRIES=3
RETRY_DELAY_SECONDS=5
# ─────────────────────────────────────────────────────────────────────────────
#
# CSV format (with header row):
#   SerialNumber,NewName
#   DMPXXXXXXX1,LSKA
#   DMPXXXXXXX2,LSKB
#
# Flow, in batches of $BATCH_SIZE iPads at a time:
#   1. Send the rename (MDM Settings -> deviceName) command to every iPad in
#      the batch.
#   2. Wait $RENAME_VERIFY_WAIT_SECONDS, then check Jamf inventory to confirm
#      the name actually landed on each device (not just that Jamf accepted
#      the command). Any device still showing the wrong name gets the rename
#      command re-sent and another verify cycle — up to $MAX_RENAME_ATTEMPTS
#      attempts total. A device that never confirms is skipped from the wipe
#      entirely and recorded in the end-of-run summary — it never gets erased
#      with a name that was never actually applied.
#   3. Erase every device in the batch that DID confirm, with Return to
#      Service (re-enrolls + re-downloads apps automatically).
#   4. Wait $POST_WIPE_WAIT_SECONDS before starting the next batch (bandwidth
#      throttling — each iPad re-downloading its apps at once saturates the
#      connection).
#
# Re-running against the same CSV skips any serial that was already renamed
# AND wiped successfully in a prior run (tracked in a .completed file next to
# the log directory), so this is safe to re-run over partial/interrupted runs
# across the school year without re-wiping devices that already succeeded.
#
# Requires a Return to Service configuration already set up and scoped in
# Jamf Pro — the erase call will fail with "RTS not supported for this
# device" for hardware/OS combinations that don't support it; those are
# reported in the summary too and need a manual wipe.

# Re-exec under caffeinate so the Mac can't sleep mid-run (this script sleeps
# repeatedly between steps and can take a long time end to end).
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

# Tracks serials that have already been renamed AND successfully erased for
# this CSV, so re-running the script after a failure or interruption doesn't
# re-wipe devices that already completed successfully.
completedFile="${logDir}/$(basename "$csvFile").completed"
touch "$completedFile"

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
    # Refresh proactively if older than 25 minutes. This is just a first
    # line of defense — every API call below also retries once on a live 401
    # regardless of this timer, so an inaccurate assumption about the real
    # token lifetime can't silently break a run.
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

# Drop any serial already marked complete (renamed + confirmed + erased) in a
# prior run against this same CSV — never re-wipe a device that already
# succeeded.
pendingSerials=()
pendingNewnames=()
skippedCompleted=0
for (( i = 0; i < ${#serials[@]}; i++ )); do
    if grep -Fxq "${serials[$i]}" "$completedFile"; then
        skippedCompleted=$(( skippedCompleted + 1 ))
        continue
    fi
    pendingSerials+=("${serials[$i]}")
    pendingNewnames+=("${newnames[$i]}")
done
serials=("${pendingSerials[@]}")
newnames=("${pendingNewnames[@]}")

if [[ $skippedCompleted -gt 0 ]]; then
    log "Skipping $skippedCompleted iPad(s) already renamed + erased in a previous run against this CSV (see $completedFile)."
fi

total=${#serials[@]}

if [[ $total -eq 0 ]]; then
    if [[ $skippedCompleted -gt 0 ]]; then
        log "All $skippedCompleted serial number / name pair(s) in $csvFile were already completed in a previous run — nothing to do."
    else
        log "No serial number / name pairs found in $csvFile"
    fi
    exit 0
fi

batches=$(( (total + BATCH_SIZE - 1) / BATCH_SIZE ))

log ""
log "The following $total iPad(s) will be renamed (with confirmation + retry), then wiped with Return to Service:"
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

    local response http_code
    response=$(curl_retry -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X POST "${jssURL}/api/v2/mdm/commands" \
        -H "Authorization: Bearer $bearer_token" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$payload")
    http_code=$(echo "$response" | tail -n1)

    if [[ "$http_code" == "401" ]]; then
        log "Bearer token rejected (401) during rename for management ID $management_id — refreshing and retrying..."
        get_bearer_token
        response=$(curl_retry -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X POST "${jssURL}/api/v2/mdm/commands" \
            -H "Authorization: Bearer $bearer_token" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "$payload")
    fi

    echo "$response"
}

# ── Erase a device with Return to Service ─────────────────────────────────────
erase_device() {
    local mobile_device_id="$1"
    local response http_code
    response=$(curl_retry -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X POST "${jssURL}/api/v2/mobile-devices/${mobile_device_id}/erase" \
        -H "Authorization: Bearer $bearer_token" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d '{"returnToService": true}')
    http_code=$(echo "$response" | tail -n1)

    if [[ "$http_code" == "401" ]]; then
        log "Bearer token rejected (401) during erase for iPad ID $mobile_device_id — refreshing and retrying..."
        get_bearer_token
        response=$(curl_retry -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X POST "${jssURL}/api/v2/mobile-devices/${mobile_device_id}/erase" \
            -H "Authorization: Bearer $bearer_token" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d '{"returnToService": true}')
    fi

    echo "$response"
}

# ── End-of-run summary buckets ─────────────────────────────────────────────────
summaryOkSerial=(); summaryOkName=()
summaryNotFoundSerial=()
summaryNameFailSerial=(); summaryNameFailWant=(); summaryNameFailGot=()
summaryEraseFailSerial=(); summaryEraseFailName=(); summaryEraseFailReason=()

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
    index=$(( batch_end + 1 ))

    refresh_token_if_needed

    # Per-batch state, parallel arrays indexed 0..n-1 within this batch.
    bSerial=(); bTarget=(); bMobileId=(); bManagementId=()
    bAttempts=(); bStatus=()   # status: pending | confirmed | failed | notfound

    for (( i = batch_start; i <= batch_end; i++ )); do
        serial="${serials[$i]}"
        newname="${newnames[$i]}"

        log "Looking up serial $serial..."
        lookup_result=$(lookup_device "$serial")

        if [[ -z "$lookup_result" ]]; then
            log "Warning: Could not find an iPad with serial number $serial in Jamf — skipping"
            summaryNotFoundSerial+=("$serial")
            continue
        fi

        IFS='|' read -r mobile_device_id management_id current_name <<< "$lookup_result"
        log "Found iPad ID $mobile_device_id (currently '${current_name}') for serial $serial"

        rename_response=$(rename_device "$management_id" "$newname")
        rename_http_code=$(echo "$rename_response" | tail -n1)
        rename_body=$(echo "$rename_response" | sed '$d')

        if [[ "$rename_http_code" =~ ^2[0-9][0-9]$ ]]; then
            log "Rename command sent (attempt 1/${MAX_RENAME_ATTEMPTS}): $serial -> $newname (iPad ID $mobile_device_id)"
        else
            log "Warning: Rename command attempt 1 for serial $serial returned HTTP $rename_http_code — will retry on the next verify cycle"
            log "Response: $rename_body"
        fi

        bSerial+=("$serial"); bTarget+=("$newname")
        bMobileId+=("$mobile_device_id"); bManagementId+=("$management_id")
        bAttempts+=(1); bStatus+=("pending")
    done

    # ── Verify + retry loop ────────────────────────────────────────────────────
    round=1
    pendingCount=${#bSerial[@]}
    while [[ $pendingCount -gt 0 && $round -le $MAX_RENAME_ATTEMPTS ]]; do
        log "Waiting ${RENAME_VERIFY_WAIT_SECONDS}s to verify rename(s) landed (round ${round}/${MAX_RENAME_ATTEMPTS})..."
        sleep "$RENAME_VERIFY_WAIT_SECONDS"
        refresh_token_if_needed

        pendingCount=0
        for (( i = 0; i < ${#bSerial[@]}; i++ )); do
            [[ "${bStatus[$i]}" != "pending" ]] && continue

            serial="${bSerial[$i]}"
            target="${bTarget[$i]}"

            lookup_result=$(lookup_device "$serial")
            if [[ -z "$lookup_result" ]]; then
                log "Warning: Could not re-look-up serial $serial during verification — will retry next round"
                current_name=""
            else
                IFS='|' read -r _ _ current_name <<< "$lookup_result"
            fi

            if [[ "$current_name" == "$target" ]]; then
                log "Confirmed: $serial is now named '$current_name' (took ${bAttempts[$i]} attempt(s))"
                bStatus[$i]="confirmed"
                continue
            fi

            if [[ ${bAttempts[$i]} -ge $MAX_RENAME_ATTEMPTS ]]; then
                log "FAILED: $serial never picked up new name '$target' after ${MAX_RENAME_ATTEMPTS} attempts (still shows '${current_name}') — will NOT be wiped"
                bStatus[$i]="failed"
                summaryNameFailSerial+=("$serial")
                summaryNameFailWant+=("$target")
                summaryNameFailGot+=("$current_name")
                continue
            fi

            next_attempt=$(( ${bAttempts[$i]} + 1 ))
            log "Not yet applied: $serial still shows '${current_name}' — retrying rename (attempt ${next_attempt}/${MAX_RENAME_ATTEMPTS})..."
            rename_response=$(rename_device "${bManagementId[$i]}" "$target")
            rename_http_code=$(echo "$rename_response" | tail -n1)
            if [[ ! "$rename_http_code" =~ ^2[0-9][0-9]$ ]]; then
                log "Warning: Retry rename command for serial $serial returned HTTP $rename_http_code"
            fi
            bAttempts[$i]=$next_attempt
            pendingCount=$(( pendingCount + 1 ))
        done

        round=$(( round + 1 ))
    done

    # ── Erase every confirmed device in this batch ─────────────────────────────
    anyErased=0
    for (( i = 0; i < ${#bSerial[@]}; i++ )); do
        [[ "${bStatus[$i]}" != "confirmed" ]] && continue

        serial="${bSerial[$i]}"
        newname="${bTarget[$i]}"
        mobile_device_id="${bMobileId[$i]}"

        log "Erasing iPad ID $mobile_device_id (serial $serial) with Return to Service..."
        erase_response=$(erase_device "$mobile_device_id")
        erase_http_code=$(echo "$erase_response" | tail -n1)
        erase_body=$(echo "$erase_response" | sed '$d')

        if [[ "$erase_http_code" =~ ^2[0-9][0-9]$ ]]; then
            log "Erase command queued for serial $serial (iPad ID $mobile_device_id)"
            echo "$serial" >> "$completedFile"
            summaryOkSerial+=("$serial"); summaryOkName+=("$newname")
            anyErased=1
        else
            log "Error: Failed to queue erase for serial $serial (iPad ID $mobile_device_id) (HTTP $erase_http_code)"
            log "Response: $erase_body"
            reason="HTTP ${erase_http_code}"
            reasonDesc=$(echo "$erase_body" | python3 -c 'import sys,json
try:
    d=json.loads(sys.stdin.read())
    errs=d.get("errors") or []
    print(errs[0].get("description","") if errs else "")
except Exception:
    print("")' 2>/dev/null)
            [[ -n "$reasonDesc" ]] && reason="$reason - $reasonDesc"
            summaryEraseFailSerial+=("$serial"); summaryEraseFailName+=("$newname"); summaryEraseFailReason+=("$reason")
        fi
    done

    if [[ $anyErased -eq 0 ]]; then
        log "No iPads in this batch were successfully renamed + confirmed — nothing to wipe in this batch."
    fi

    if [[ $index -lt $total ]]; then
        log "Waiting ${POST_WIPE_WAIT_SECONDS}s before starting the next batch..."
        sleep "$POST_WIPE_WAIT_SECONDS"
    fi
done

# ── Final summary ───────────────────────────────────────────────────────────
log ""
log "══════════════════ SUMMARY ══════════════════"
log ""
log "Renamed + wiped successfully (${#summaryOkSerial[@]}):"
for (( i = 0; i < ${#summaryOkSerial[@]}; i++ )); do
    log "  OK: ${summaryOkSerial[$i]} -> ${summaryOkName[$i]}"
done
log ""
log "Rename never confirmed after ${MAX_RENAME_ATTEMPTS} attempts — NOT wiped (${#summaryNameFailSerial[@]}):"
for (( i = 0; i < ${#summaryNameFailSerial[@]}; i++ )); do
    log "  NAME FAILED: ${summaryNameFailSerial[$i]} (wanted '${summaryNameFailWant[$i]}', still showed '${summaryNameFailGot[$i]}')"
done
log ""
log "Renamed but erase failed (${#summaryEraseFailSerial[@]}):"
for (( i = 0; i < ${#summaryEraseFailSerial[@]}; i++ )); do
    log "  ERASE FAILED: ${summaryEraseFailSerial[$i]} -> ${summaryEraseFailName[$i]} (${summaryEraseFailReason[$i]})"
done
log ""
log "Not found in Jamf (${#summaryNotFoundSerial[@]}):"
for (( i = 0; i < ${#summaryNotFoundSerial[@]}; i++ )); do
    log "  NOT FOUND: ${summaryNotFoundSerial[$i]}"
done
log ""
log "══════════════════════════════════════════════"
log ""
log "Rename + Return to Service wipe process completed."
