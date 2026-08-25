#!/bin/bash
# Script to set a specific password for a batch of students listed in a CSV.
# This script uses GAM (Google Apps Manager).
#
# The CSV is expected to have repeating groups of 3 columns:
#   <Class> Student Name, Email, <Class>
# e.g. "3A Student Name,Email,3A ,3B Student Name,Email,3B,..."
# The 3rd column in each group holds that student's new password.
# Columns are matched by POSITION (every group of 3), not by header text,
# since header spacing/labels are inconsistent across class groups.
#
# The password is set WITHOUT forcing a change at next login
# (changepassword false).
#
# Every student is shown (class, name, email, password) and must be
# confirmed individually before GAM is run, so a misaligned column never
# silently sets the wrong password on the wrong account.

# Set the path to GAM executable
GAM_PATH="/Users/orion.medina/bin/gam7/gam"

# Path to the CSV file containing students, emails, and passwords
CSV_FILE="/Users/orion.medina/Downloads/Primary_List_Passwords_26.csv"

# Check if GAM exists
if [ ! -f "$GAM_PATH" ]; then
    echo "ERROR: GAM not found at $GAM_PATH"
    echo "Please check the path and try again."
    exit 1
fi

if [ -z "$CSV_FILE" ]; then
    echo "ERROR: CSV_FILE is not set. Edit this script and set CSV_FILE to the path of your CSV."
    exit 1
fi

if [ ! -f "$CSV_FILE" ]; then
    echo "ERROR: CSV file not found at $CSV_FILE"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to parse the CSV but was not found."
    exit 1
fi

echo "Starting script to change password for students in: $CSV_FILE"
echo "Using GAM at: $GAM_PATH"

# Parse the CSV into "class<TAB>name<TAB>email<TAB>password" rows.
# Groups of 3 columns (Name, Email, Password) are read by position so
# inconsistent/duplicate header text (e.g. "3A" vs "3A ") doesn't matter.
# The class label comes from that group's header (e.g. "3A"), so you can
# cross-check each row against the class it came from in the CSV.
# Rows/groups missing an email or password are skipped.
pairs_file=$(mktemp)
python3 - "$CSV_FILE" > "$pairs_file" <<'PYEOF'
import csv
import sys

path = sys.argv[1]
with open(path, newline="", encoding="utf-8-sig") as f:
    reader = csv.reader(f)
    rows = list(reader)

if not rows:
    sys.exit(0)

header = rows[0]
num_groups = len(header) // 3

for row in rows[1:]:
    for g in range(num_groups):
        start = g * 3
        if start + 2 >= len(row):
            continue
        label = header[start + 2].strip() if start + 2 < len(header) else f"group{g+1}"
        name = row[start].strip()
        email = row[start + 1].strip()
        password = row[start + 2].strip()
        if email and password:
            print(f"{label}\t{name}\t{email}\t{password}")
PYEOF

total=$(wc -l < "$pairs_file" | tr -d ' ')

if [ "$total" -eq 0 ]; then
    echo "No students with both an email and a password were found in $CSV_FILE"
    rm -f "$pairs_file"
    exit 1
fi

echo ""
echo "Found $total student(s) with a password to set:"
echo ""
i=0
while IFS=$'\t' read -r -u 3 label name email password; do
    i=$((i + 1))
    printf "%3d) [%s] %-25s %-35s -> %s\n" "$i" "$label" "$name" "$email" "$password"
done 3< "$pairs_file"
echo ""

read -p "Does the class/name/email/password mapping above look correct? Proceed to per-student confirmation? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted. No passwords were changed."
    rm -f "$pairs_file"
    exit 0
fi

# Confirm and apply one student at a time so a bad row can never be
# applied silently. Options: y = apply this one, n = skip this one,
# a = apply this and all remaining without asking again, q = quit now.
apply_all=false
i=0
while IFS=$'\t' read -r -u 3 label name email password; do
    i=$((i + 1))
    if [ "$apply_all" = false ]; then
        echo ""
        printf "[%d/%d] [%s] %s <%s> -> %s\n" "$i" "$total" "$label" "$name" "$email" "$password"
        read -p "Apply this password? (y=yes / n=skip / a=yes to all remaining / q=quit): " ans
        case "$ans" in
            [Aa]*) apply_all=true ;;
            [Yy]*) ;;
            [Qq]*) echo "Quitting. Remaining students were not processed."; break ;;
            *) echo "Skipped $email"; continue ;;
        esac
    fi

    echo "Processing: $email"
    "$GAM_PATH" update user "$email" password "$password" changepassword false
    echo "-------------"
done 3< "$pairs_file"

rm -f "$pairs_file"

echo "Done."
