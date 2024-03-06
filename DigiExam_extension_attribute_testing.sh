#!/bin/bash


# Function to compare version numbers
# Takes two version strings as input and compares them
version_compare() {
    # Set '.' as delimiter to split version strings into arrays
    local IFS="."
    local version1=($1) version2=($2)
    # Pad the shorter version with zeros for equal length comparison
    for ((i=${#version1[@]}; i<${#version2[@]}; i++)); do version1[i]=0; done
    for ((i=${#version2[@]}; i<${#version1[@]}; i++)); do version2[i]=0; done
    # Loop through each segment to compare version numbers
    for ((i=0; i<${#version1[@]}; i++)); do
        # Compare segments as base-10 to prevent octal interpretation
        if ((10#${version1[i]} > 10#${version2[i]})); then echo ">"; return; fi  # version1 is newer
        if ((10#${version1[i]} < 10#${version2[i]})); then echo "<"; return; fi  # version1 is older
    done
    echo "="  # Versions are identical if all segments are equal
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