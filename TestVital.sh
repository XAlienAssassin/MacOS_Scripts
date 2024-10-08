downloadURL=$(curl -fsL -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.111 Safari/537.36" "https://support.vitalsource.com/hc/en-us/articles/360014107913-Mac" | grep -i "mac/bookshelf/" | head -1 | grep -o -i -E "https.*" | cut -d '"' -f1)
    # Set the app new version
#appNewVersion=$( echo "${downloadURL}" | sed 's/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*$/\1/' )
appNewVersion=$(echo "${downloadURL}" | sed -E 's/.*VitalSource-Bookshelf_([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.dmg/\1/')

echo $appNewVersion 