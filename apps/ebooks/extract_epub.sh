#!/bin/bash
# Extract EPUB to plain text
# Usage: extract_epub.sh <epub_file>

EPUB_FILE="$1"
if [ ! -f "$EPUB_FILE" ]; then
    exit 1
fi

TXT_FILE="${EPUB_FILE%.epub}.txt"
TXT_FILE="${TXT_FILE%.EPUB}.txt"

# Skip if txt exists and is newer than epub
if [ -f "$TXT_FILE" ] && [ "$TXT_FILE" -nt "$EPUB_FILE" ]; then
    exit 0
fi

TEMP_DIR=$(mktemp -d)
unzip -q -o "$EPUB_FILE" -d "$TEMP_DIR" 2>/dev/null

# Find OPF file
OPF=$(find "$TEMP_DIR" -name "*.opf" 2>/dev/null | head -1)
if [ -z "$OPF" ]; then
    rm -rf "$TEMP_DIR"
    exit 1
fi

OPF_DIR=$(dirname "$OPF")

# Get spine order
SPINE_IDS=$(grep -oP '<itemref[^>]*idref="\K[^"]+' "$OPF" 2>/dev/null)

# Extract text in order
> "$TXT_FILE"

for IDREF in $SPINE_IDS; do
    HREF=$(grep -oP "<item[^>]*id=\"$IDREF\"[^>]*href=\"\K[^\"]+|<item[^>]*href=\"([^\"]+)\"[^>]*id=\"$IDREF\"" "$OPF" 2>/dev/null | head -1)
    if [ -n "$HREF" ]; then
        CHAPTER="$OPF_DIR/$HREF"
        if [ -f "$CHAPTER" ]; then
            # Strip HTML tags, decode entities, clean up
            sed -e 's/<style[^>]*>.*<\/style>//g' \
                -e 's/<script[^>]*>.*<\/script>//g' \
                -e 's/<br[^>]*>/\n/gi' \
                -e 's/<\/p>/\n\n/gi' \
                -e 's/<\/div>/\n/gi' \
                -e 's/<\/h[1-6]>/\n\n/gi' \
                -e 's/<[^>]*>//g' \
                "$CHAPTER" | \
            sed -e 's/&nbsp;/ /g' \
                -e 's/&amp;/\&/g' \
                -e 's/&lt;/</g' \
                -e 's/&gt;/>/g' \
                -e 's/&quot;/"/g' \
                -e "s/&#39;/'/g" \
                -e 's/&#[0-9]*;//g' | \
            tr -s ' \t' ' ' | \
            sed -e 's/^ *//' -e '/^$/d' >> "$TXT_FILE"
            echo -e "\n\n" >> "$TXT_FILE"
        fi
    fi
done

rm -rf "$TEMP_DIR"
