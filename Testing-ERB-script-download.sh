#!/bin/sh

# -------------------------------------------------------------------------------------
#
# Universal App Installer Script
#
# -------------------------------------------------------------------------------------
#
# DESCRIPTION
#
# Automatically download and install nearly any app from a direct download link
# App can be packaged as .dmg, .pkg, or .zip, and have either the .app or a .pkg inside
#
# -------------------------------------------------------------------------------------
#
# HISTORY
#
# Created by Ella Hansen on 10/30/2018
#
# v2.0 - 08/31/2022 - Scott Leonard
# Created script based on Caine Hörr's script for Google Chrome:
# https://www.jamf.com/jamf-nation/discussions/20894
#
# -------------------------------------------------------------------------------------

# ADD THE DIRECT DOWNLOAD LINK FOR YOUR APP HERE INCLUDING THE CURL COMMAND, WITH OPTIONS IN THE PARAMETER 4 LOCATION IN THE JAMF POLICY:
# Example: curl --location https://dl.google.com/chrome/mac/stable/googlechrome.dmg --output Chrome.dmg
DownloadURL="curl --location https://github.com/XAlienAssassin/MacOS_Scripts/raw/main/ERBSecureBrowser_13.3.0.88.zip --output ERBSecureBrowser_13.3.0.88.zip"

# -------------------------------------------------------------------------------------
# LEAVE THIS CODE ALONE:

# Create directory /tmp/jamf, continue if directory already exists
mkdir /tmp/jamf || :

# Change directory to /tmp/jamf
cd /tmp/jamf

#Download installer container into /tmp/jamf
$DownloadURL

# Make directory to move and copy .app from
mkdir /tmp/jamf/mount

# Unzip installer container and place contents into /tmp/jamf/mount, continue on error
find /tmp/jamf -name "*.zip" -exec unzip {} -d /tmp/jamf/mount \; ||

# Uncompress or Extract Tar file
find /tmp/jamf -name "*.bz2" -exec tar -xf {} -C /tmp/jamf/mount \; || :

# If container is a .dmg:
# Mount installer container
# -nobrowse to hide the mounted .dmg
# -noverify to skip .dmg verification
# -mountpoint to specify mount point
find /tmp/jamf -name "*.dmg" -exec sh -c "yes | hdiutil attach {} -nobrowse -noverify -mountpoint /tmp/jamf/mount" \; || :

# Copy the .app file from the installer container to /Applications
# Preserve all file attributes and ACLs
cp -a /tmp/jamf/mount/*.app /Applications || :

# If container is a .pkg
# Run installer package with the boot drive as the destination
find /tmp/jamf -name "*.pkg" -exec installer -pkg {} -target / \; || :

# Unmount the secondary installation folder, continue on error
hdiutil detach /tmp/jamf/mount || :

# Delete the main installation folder
rm -r /tmp/jamf