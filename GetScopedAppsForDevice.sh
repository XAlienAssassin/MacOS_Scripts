#!/bin/bash
# Finds all mobile device apps that have a specific device in scope,
# then exports the app name, version, and scope reason to a CSV.

# ── Configuration ────────────────────────────────────────────────────────────
jamfUrl=""
jamfUser=""
jamfPass=""
deviceID=""
PARALLEL=50   # concurrent API requests
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

if [[ -z "$deviceID" ]]; then
    read -p "Please enter the device ID : " deviceID
fi

if [[ -z "$jamfUrl" || -z "$jamfUser" || -z "$jamfPass" || -z "$deviceID" ]]; then
    echo "ERROR: All fields are required." >&2
    exit 1
fi

jamfUrl="${jamfUrl%/}"
tmpDir=$(mktemp -d)
trap 'rm -rf "$tmpDir"' EXIT

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

# ── Look up the device by ID ──────────────────────────────────────────────────
echo "Looking up device ID: $deviceID..."

deviceXML=$(classicGet "mobiledevices/id/${deviceID}")
if [[ -z "$deviceXML" ]]; then
    echo "ERROR: Device ID '$deviceID' not found in Jamf Pro." >&2
    invalidateToken
    exit 1
fi

deviceName=$(echo "$deviceXML" | xmllint --xpath "//mobile_device/general/name/text()" - 2>/dev/null)
echo "  Device Name: $deviceName"

outputCSV="/Users/orion.medina/Downloads/ScopedApps_$(echo "$deviceName" | tr ' ' '_')_$(date +%Y%m%d_%H%M%S).csv"

deviceDept=$(echo "$deviceXML" | xmllint --xpath "//mobile_device/location/department/text()" - 2>/dev/null)
deviceBldg=$(echo "$deviceXML" | xmllint --xpath "//mobile_device/location/building/text()" - 2>/dev/null)

# Fetch group membership via subset
deviceGroupsXML=$(classicGet "mobiledevices/id/${deviceID}/subset/MobileDeviceGroups")
deviceGroupIDs=$(echo "$deviceGroupsXML" | xmllint --xpath "//mobile_device_group/id" - 2>/dev/null \
    | grep -Eo "<id[^<]*" | grep -Eo "[0-9]+")

groupCount=$(echo "$deviceGroupIDs" | grep -c "[0-9]" 2>/dev/null || echo 0)
echo "  Device belongs to $groupCount group(s)."
echo "$deviceGroupsXML" | xmllint --xpath "//mobile_device_group/name" - 2>/dev/null \
    | grep -Eo "<name>[^<]*" | sed 's/<name>//' | while IFS= read -r g; do
    echo "    - $g"
done

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
echo "  Found $total apps to check (running $PARALLEL at a time)."

# ── Scope-check: prints all reasons the device is in scope, or nothing ────────
scopeReason() {
    local appXML="$1"
    local reasons=()

    # Scoped to all mobile devices
    local allDevices
    allDevices=$(echo "$appXML" | xmllint --xpath "//scope/all_mobile_devices/text()" - 2>/dev/null)
    if [[ "$allDevices" == "true" ]]; then
        echo "All Mobile Devices"
        return
    fi

    # Direct device match
    local scopedDeviceIds
    scopedDeviceIds=$(echo "$appXML" | xmllint --xpath "//scope/mobile_devices/mobile_device/id" - 2>/dev/null \
        | grep -Eo "<id[^<]*" | grep -Eo "[0-9]+")
    while IFS= read -r sid; do
        if [[ "$sid" == "$deviceID" ]]; then
            reasons+=("Device: $deviceName")
            break
        fi
    done <<< "$scopedDeviceIds"

    # Group match — collect all matching group names
    local scopedGroupIds
    scopedGroupIds=$(echo "$appXML" | xmllint --xpath "//scope/mobile_device_groups/mobile_device_group/id" - 2>/dev/null \
        | grep -Eo "<id[^<]*" | grep -Eo "[0-9]+")
    while IFS= read -r gid; do
        while IFS= read -r dgid; do
            if [[ -n "$gid" && "$gid" == "$dgid" ]]; then
                local gname
                gname=$(echo "$appXML" | xmllint --xpath \
                    "string(//scope/mobile_device_groups/mobile_device_group[id='${gid}']/name)" - 2>/dev/null)
                reasons+=("Group: $gname")
                break
            fi
        done <<< "$deviceGroupIDs"
    done <<< "$scopedGroupIds"

    # Department match
    if [[ -n "$deviceDept" ]]; then
        local scopedDepts
        scopedDepts=$(echo "$appXML" | xmllint --xpath "//scope/departments/department/name" - 2>/dev/null \
            | grep -Eo "<name>[^<]*" | sed 's/<name>//')
        while IFS= read -r dept; do
            if [[ "$dept" == "$deviceDept" ]]; then
                reasons+=("Department: $deviceDept")
                break
            fi
        done <<< "$scopedDepts"
    fi

    # Building match
    if [[ -n "$deviceBldg" ]]; then
        local scopedBldgs
        scopedBldgs=$(echo "$appXML" | xmllint --xpath "//scope/buildings/building/name" - 2>/dev/null \
            | grep -Eo "<name>[^<]*" | sed 's/<name>//')
        while IFS= read -r bldg; do
            if [[ "$bldg" == "$deviceBldg" ]]; then
                reasons+=("Building: $deviceBldg")
                break
            fi
        done <<< "$scopedBldgs"
    fi

    # Join all reasons with " | "
    local joined=""
    for r in "${reasons[@]}"; do
        [[ -n "$joined" ]] && joined="$joined | "
        joined="${joined}${r}"
    done
    echo "$joined"
}

# Export functions and variables needed by subshells
export -f classicGet scopeReason
export token jamfUrl deviceID deviceName deviceGroupIDs deviceDept deviceBldg

# ── Iterate over every app in parallel ───────────────────────────────────────
echo "App Name,Version,Scoped Via" > "$outputCSV"

jobCount=0
count=0
while IFS= read -r appID; do
    [[ -z "$appID" ]] && continue
    count=$((count + 1))

    (
        appXML=$(classicGet "mobiledeviceapplications/id/${appID}")
        [[ -z "$appXML" ]] && exit 0
        reason=$(scopeReason "$appXML")
        [[ -z "$reason" ]] && exit 0
        appName=$(echo "$appXML" | xmllint --xpath "//general/name/text()" - 2>/dev/null)
        appVersion=$(echo "$appXML" | xmllint --xpath "//general/version/text()" - 2>/dev/null)
        appNameCSV=$(printf '%s' "$appName" | sed 's/"/""/g')
        appVersionCSV=$(printf '%s' "$appVersion" | sed 's/"/""/g')
        reasonCSV=$(printf '%s' "$reason" | sed 's/"/""/g')
        echo "\"${appNameCSV}\",\"${appVersionCSV}\",\"${reasonCSV}\"" > "$tmpDir/$appID"
    ) &

    jobCount=$((jobCount + 1))
    if [[ $jobCount -ge $PARALLEL ]]; then
        wait
        jobCount=0
        printf "\r  Checked ~%d / %d..." "$count" "$total"
        checkTokenExpiration
    fi
done <<< "$appIDs"
wait
printf "\r  Checked %d / %d.   \n" "$total" "$total"

# ── Collect results in original order ────────────────────────────────────────
matched=0
while IFS= read -r appID; do
    [[ -z "$appID" ]] && continue
    if [[ -f "$tmpDir/$appID" ]]; then
        cat "$tmpDir/$appID" >> "$outputCSV"
        matched=$((matched + 1))
    fi
done <<< "$appIDs"

# ── Done ──────────────────────────────────────────────────────────────────────
invalidateToken
echo "Done. Found $matched app(s) scoped to '$deviceName'."
echo "CSV saved to: $outputCSV"
