#!/bin/bash
# Extract EPUB to plain text
# Usage: extract_epub.sh <epub_file>

EPUB_FILE="$1"
if [ ! -f "$EPUB_FILE" ]; then
    exit 1
fi

# Remove .epub or .EPUB extension and add .txt
BASE="${EPUB_FILE%.epub}"
BASE="${BASE%.EPUB}"
TXT_FILE="${BASE}.txt"

# Skip if txt exists and is newer than epub
if [ -f "$TXT_FILE" ] && [ "$TXT_FILE" -nt "$EPUB_FILE" ]; then
    exit 0
fi

TEMP_DIR=$(mktemp -d)
unzip -q -o "$EPUB_FILE" -d "$TEMP_DIR" 2>/dev/null

# Find all HTML/XHTML files and extract text
> "$TXT_FILE"

find "$TEMP_DIR" -type f \( -name "*.html" -o -name "*.xhtml" -o -name "*.htm" \) | sort | while read -r CHAPTER; do
    # Strip HTML tags and decode entities
    sed -e 's/<style[^>]*>.*<\/style>//g' \
        -e 's/<script[^>]*>.*<\/script>//g' \
        -e 's/<br[^>]*>/\n/gi' \
        -e 's/<\/p>/\n\n/gi' \
        -e 's/<\/div>/\n/gi' \
        -e 's/<\/h[1-6]>/\n\n/gi' \
        -e 's/<[^>]*>//g' \
        "$CHAPTER" 2>/dev/null | \
    sed -e 's/&nbsp;/ /g' \
        -e 's/&amp;/\&/g' \
        -e 's/&lt;/</g' \
        -e 's/&gt;/>/g' \
        -e 's/&quot;/"/g' \
        -e "s/&#39;/'/g" \
        -e 's/&#[0-9]*;//g' \
        -e 's/&[a-z]*;//g' | \
    tr -s ' \t' ' ' | \
    sed -e 's/^ *//' >> "$TXT_FILE"
    echo -e "\n\n" >> "$TXT_FILE"
done

rm -rf "$TEMP_DIR"
