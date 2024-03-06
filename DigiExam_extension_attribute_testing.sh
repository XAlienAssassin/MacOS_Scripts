#!/bin/bash

# Path to DigiExam Info.plist file (modify as needed)
info_plist="/Applications/DigiExam.app/Contents/Info.plist"

# Function to compare version numbers
# Takes two version strings as input and compares them
version_compare() {
    # Split version numbers into arrays based on '.' delimiter
    local IFS="."
    local i version1=($1) version2=($2)
    # Pad the shorter version with zeros to match the length of the longer version
    while [ ${#version1[@]} -lt ${#version2[@]} ]; do
        version1+=("0")
    done
    while [ ${#version2[@]} -lt ${#version1[@]} ]; do
        version2+=("0")
    done
    # Compare each segment of the version numbers
    for ((i=0; i<${#version1[@]}; i++)); do
        # Comparing version numbers as base-10 integers to avoid octal interpretation of leading zeros
        # If a segment of version1 is greater than the corresponding segment of version2, version1 is newer
        if ((10#${version1[i]} > 10#${version2[i]})); then
            echo ">"
            return
        # If a segment of version1 is less than the corresponding segment of version2, version1 is older
        elif ((10#${version1[i]} < 10#${version2[i]})); then
            echo "<"
            return
        fi
    done
    # If all segments are equal, the versions are the same
    echo "="
}

# Check if Info.plist file exists
if [ -e "$info_plist" ]; then
    # Extract the version information from the plist using PlistBuddy
    digiexam_version="15.0.1"

    # Extract the latest version using the specified curl command
    latest_version="15.0.10"
    # Check if the latest version is empty (curl command failed)
    if [ -z "$latest_version" ]; then
        echo "<result>Curl command failed. Unable to retrieve the latest version.</result>"
    else
        # Compare versions using the version_compare function
        # This function returns ">", "<", or "=" based on the comparison
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