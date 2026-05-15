#!/bin/bash
# Finds all mobile device apps scoped to one or more smart/static groups
# and exports the app names to a CSV, organized by group.

# ── Configuration ────────────────────────────────────────────────────────────
jamfUrl=""
jamfUser=""
jamfPass=""
groupIDsInput=""
PARALLEL=10
# ─────────────────────────────────────────────────────────────────────────────

if [[ -z "$jamfUrl" ]]; then
    read -p "Please enter your Jamf Pro server URL : " jamfUrl
fi

if [[ -z "$jamfUser" ]]; then
    read -p "Please enter your Jamf Pro user account : " jamfUser
fi

if [[ -z "$jamfPass" ]]; then
    read -p "Please enter the password for the $jamfUser account : " -s jamfPass
    echo
fi

if [[ -z "$groupIDsInput" ]]; then
    read -p "Please enter smart group ID(s), comma-separated : " groupIDsInput
fi

if [[ -z "$jamfUrl" || -z "$jamfUser" || -z "$jamfPass" || -z "$groupIDsInput" ]]; then
    echo "ERROR: All fields are required." >&2
    exit 1
fi

jamfUrl="${jamfUrl%/}"
outputCSV="/Users/orion.medina/Downloads/GroupApps_$(date +%Y%m%d_%H%M%S).csv"
tmpDir=$(mktemp -d)
trap 'rm -rf "$tmpDir"' EXIT
mkdir -p "$tmpDir/apps"

# Parse comma-separated group IDs, trim whitespace
IFS=',' read -ra rawIDs <<< "$groupIDsInput"
groupIDs_input=()
for g in "${rawIDs[@]}"; do
    trimmed=$(echo "$g" | sed 's/^ *//;s/ *$//')
    [[ -n "$trimmed" ]] && groupIDs_input+=("$trimmed")
done

if [[ ${#groupIDs_input[@]} -eq 0 ]]; then
    echo "ERROR: No group IDs provided." >&2
    exit 1
fi

# ── URL encode (no python) ────────────────────────────────────────────────────
urlencode() {
    local string="$1" encoded="" i c
    for (( i=0; i<${#string}; i++ )); do
        c="${string:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            *) encoded+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    echo "$encoded"
}

# ── Token functions ───────────────────────────────────────────────────────────
getBearerToken() {
    response=$(curl -s -u "$jamfUser:$jamfPass" "$jamfUrl/api/v1/auth/token" -X POST)
    token=$(echo "$response" | plutil -extract token raw -)
}

invalidateToken() {
    curl -s -X POST -H "Authorization: Bearer $token" "$jamfUrl/api/v1/auth/invalidate-token" -o /dev/null
    echo "Token invalidated."
}

checkTokenExpiration() {
    apiCheck=$(curl -w "%{http_code}" -H "Authorization: Bearer $token" "$jamfUrl/api/v1/auth" -s -o /dev/null)
    if [[ "$apiCheck" != "200" ]]; then
        echo "Token expired, fetching new token."
        getBearerToken
        export token
    fi
}

classicGet() {
    curl -sf -H "Authorization: Bearer $token" -H "Accept: application/xml" \
        "$jamfUrl/JSSResource/$1"
}

# ── Authenticate ──────────────────────────────────────────────────────────────
echo "Authenticating with Jamf Pro..."
getBearerToken
if [[ -z "$token" ]]; then
    echo "ERROR: Failed to retrieve bearer token. Check credentials and URL." >&2
    exit 1
fi

# ── Look up all groups by ID ──────────────────────────────────────────────────
echo "Looking up groups..."
declare -A groupNames   # groupID -> groupName
validGroupIDs=()
for gid in "${groupIDs_input[@]}"; do
    groupXML=$(classicGet "mobiledevicegroups/id/${gid}")
    if [[ -z "$groupXML" ]]; then
        echo "  WARNING: Group ID '$gid' not found, skipping." >&2
        continue
    fi
    gname=$(echo "$groupXML" | xmllint --xpath "//mobile_device_group/name/text()" - 2>/dev/null)
    isSmart=$(echo "$groupXML" | xmllint --xpath "//mobile_device_group/is_smart/text()" - 2>/dev/null)
    groupType="Static"
    [[ "$isSmart" == "true" ]] && groupType="Smart"
    groupNames["$gid"]="$gname"
    validGroupIDs+=("$gid")
    echo "  ID $gid → '$gname' ($groupType Group)"
done

if [[ ${#validGroupIDs[@]} -eq 0 ]]; then
    echo "ERROR: No valid groups found." >&2
    invalidateToken
    exit 1
fi

# ── Get all mobile device app IDs ─────────────────────────────────────────────
echo "Fetching list of all mobile device apps..."
checkTokenExpiration
allAppsXML=$(classicGet "mobiledeviceapplications")
if [[ -z "$allAppsXML" ]]; then
    echo "ERROR: Could not retrieve mobile device applications." >&2
    invalidateToken
    exit 1
fi

appIDs=$(echo "$allAppsXML" | xmllint --xpath "//mobile_device_application/id" - 2>/dev/null \
    | grep -Eo "<id[^<]*" | grep -Eo "[0-9]+")
total=$(echo "$appIDs" | grep -c "[0-9]")
echo "  Found $total apps to fetch (running $PARALLEL at a time)."

# Export for subshells
export -f classicGet
export token jamfUrl

# ── Phase 1: Fetch and cache all app XMLs in parallel ────────────────────────
echo "Caching app records..."
jobCount=0
count=0
while IFS= read -r appID; do
    [[ -z "$appID" ]] && continue
    count=$((count + 1))

    (
        appXML=$(classicGet "mobiledeviceapplications/id/${appID}")
        [[ -z "$appXML" ]] && exit 0
        echo "$appXML" > "$tmpDir/apps/$appID"
    ) &

    jobCount=$((jobCount + 1))
    if [[ $jobCount -ge $PARALLEL ]]; then
        wait
        jobCount=0
        printf "\r  Fetched ~%d / %d..." "$count" "$total"
        checkTokenExpiration
    fi
done <<< "$appIDs"
wait
printf "\r  Fetched %d / %d.   \n" "$total" "$total"

# ── Phase 2: Collect each group's apps into separate temp files ───────────────
for groupID in "${validGroupIDs[@]}"; do
    groupName="${groupNames[$groupID]}"
    groupFile="$tmpDir/group_$groupID"

    matched=0
    while IFS= read -r appID; do
        [[ -z "$appID" ]] && continue
        [[ ! -f "$tmpDir/apps/$appID" ]] && continue

        appXML=$(cat "$tmpDir/apps/$appID")

        # Check if scoped to all mobile devices
        allDevices=$(echo "$appXML" | xmllint --xpath "//scope/all_mobile_devices/text()" - 2>/dev/null)
        if [[ "$allDevices" == "true" ]]; then
            appName=$(echo "$appXML" | xmllint --xpath "//general/name/text()" - 2>/dev/null)
            echo "$appName" >> "$groupFile"
            matched=$((matched + 1))
            continue
        fi

        # Check if this group is in the app's scope
        found=0
        scopedGroupIds=$(echo "$appXML" | xmllint --xpath "//scope/mobile_device_groups/mobile_device_group/id" - 2>/dev/null \
            | grep -Eo "<id[^<]*" | grep -Eo "[0-9]+")
        while IFS= read -r gid; do
            if [[ "$gid" == "$groupID" ]]; then
                found=1
                break
            fi
        done <<< "$scopedGroupIds"

        if [[ $found -eq 1 ]]; then
            appName=$(echo "$appXML" | xmllint --xpath "//general/name/text()" - 2>/dev/null)
            echo "$appName" >> "$groupFile"
            matched=$((matched + 1))
        fi
    done <<< "$appIDs"

    echo "  Found $matched app(s) for '$groupName'."
done

# ── Phase 3: Write columnar CSV ───────────────────────────────────────────────
# Header row
headerRow=""
for groupID in "${validGroupIDs[@]}"; do
    groupName="${groupNames[$groupID]}"
    groupNameCSV=$(printf '%s' "$groupName" | sed 's/"/""/g')
    [[ -n "$headerRow" ]] && headerRow="${headerRow},"
    headerRow="${headerRow}\"${groupNameCSV} - Apps\""
done
echo "$headerRow" > "$outputCSV"

# Find the longest app list
maxRows=0
for groupID in "${validGroupIDs[@]}"; do
    groupFile="$tmpDir/group_$groupID"
    count=0
    [[ -f "$groupFile" ]] && count=$(wc -l < "$groupFile" | tr -d ' ')
    [[ $count -gt $maxRows ]] && maxRows=$count
done

# Write one row per app slot, one column per group
for (( row=1; row<=maxRows; row++ )); do
    rowData=""
    for groupID in "${validGroupIDs[@]}"; do
        groupFile="$tmpDir/group_$groupID"
        appName=""
        [[ -f "$groupFile" ]] && appName=$(sed -n "${row}p" "$groupFile")
        appNameCSV=$(printf '%s' "$appName" | sed 's/"/""/g')
        [[ -n "$rowData" ]] && rowData="${rowData},"
        rowData="${rowData}\"${appNameCSV}\""
    done
    echo "$rowData" >> "$outputCSV"
done

# ── Done ──────────────────────────────────────────────────────────────────────
invalidateToken
echo "Done."
echo "CSV saved to: $outputCSV"
