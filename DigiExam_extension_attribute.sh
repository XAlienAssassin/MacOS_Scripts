#!/bin/bash

# Function to compare two version numbers
version_compare() {
    local IFS=.
    local i version1=($1) version2=($2)
    for ((i=0; i<${#version1[@]}; i++)); do
        if [[ -z ${version2[i]} ]]; then
            # If version2 has fewer components, assume missing components are zeros
            version2[i]=0
        fi
        if ((10#${version1[i]} > 10#${version2[i]})); then
            echo ">"
            return
        elif ((10#${version1[i]} < 10#${version2[i]})); then
            echo "<"
            return
        fi
    done
    echo "="
}

# Path to DigiExam Info.plist file (modify as needed)
info_plist="/Applications/DigiExam.app/Contents/Info.plist"

# Check if Info.plist file exists
if [ -e "$info_plist" ]; then
    # Extract the version information from the plist using PlistBuddy
    digiexam_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$info_plist")

    # Extract the latest version using the specified curl command
    latest_version=$(curl -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15" -fs https://support.digiexam.se/hc/en-us/articles/7119593625628-Client-updates | perl -ne 'print if /Version(?!.*Only(?!.*Mac))(?=.*Mac)?/' | head -1 | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')


    # Check if the latest version is empty (curl command failed)
    if [ -z "$latest_version" ]; then
        echo "<result>Curl command failed. Unable to retrieve the latest version.</result>"
    else
        # Compare installed version with the latest version
        comparison_result=$(version_compare "$digiexam_version" "$latest_version")
        if [ "$comparison_result" = "=" ]; then
            echo "<result>The installed version is up to date.</result>"
        elif [ "$comparison_result" = ">" ]; then
            echo "<result>The installed version: $digiexam_version is higher than the latest version: $latest_version.</result>"
        else
            echo "<result>A newer version of $digiexam_version is available. Latest version: $latest_version.</result>"
        fi
    fi
else
    echo "<result>Info.plist file not found. DigiExam not installed</result>"
fi
