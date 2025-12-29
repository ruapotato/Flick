#!/bin/bash
# Extract text content from an EPUB file
# Usage: extract_epub.sh <epub_file>

EPUB_FILE="$1"
TEMP_DIR=$(mktemp -d)
OUTPUT_FILE="${EPUB_FILE%.epub}.txt"

# Extract epub (it's a zip file)
unzip -q -o "$EPUB_FILE" -d "$TEMP_DIR" 2>/dev/null

# Find and extract text from HTML/XHTML files in reading order
# First try to parse content.opf for proper order
CONTENT_OPF=$(find "$TEMP_DIR" -name "content.opf" -o -name "*.opf" 2>/dev/null | head -1)

if [ -n "$CONTENT_OPF" ]; then
    OPF_DIR=$(dirname "$CONTENT_OPF")

    # Extract spine items (reading order) from OPF
    # Get itemref idrefs from spine, then map to href in manifest
    SPINE_ITEMS=$(grep -oP 'itemref[^>]*idref="\K[^"]+' "$CONTENT_OPF" 2>/dev/null)

    TEXT=""
    for IDREF in $SPINE_ITEMS; do
        # Find the href for this id in manifest
        HREF=$(grep -oP "item[^>]*id=\"$IDREF\"[^>]*href=\"\K[^\"]+|item[^>]*href=\"([^\"]+)\"[^>]*id=\"$IDREF\"" "$CONTENT_OPF" 2>/dev/null | head -1)
        if [ -n "$HREF" ]; then
            CHAPTER_FILE="$OPF_DIR/$HREF"
            if [ -f "$CHAPTER_FILE" ]; then
                # Extract text, remove HTML tags, decode entities
                CHAPTER_TEXT=$(cat "$CHAPTER_FILE" | \
                    sed 's/<style[^>]*>.*<\/style>//g' | \
                    sed 's/<script[^>]*>.*<\/script>//g' | \
                    sed 's/<[^>]*>//g' | \
                    sed 's/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#[0-9]*;//g' | \
                    sed '/^[[:space:]]*$/d' | \
                    tr '\n' ' ' | sed 's/  */ /g')
                TEXT="$TEXT

$CHAPTER_TEXT"
            fi
        fi
    done

    if [ -n "$TEXT" ]; then
        echo "$TEXT" > "$OUTPUT_FILE"
        rm -rf "$TEMP_DIR"
        echo "$OUTPUT_FILE"
        exit 0
    fi
fi

# Fallback: just find all html/xhtml files and extract text
find "$TEMP_DIR" -type f \( -name "*.html" -o -name "*.xhtml" -o -name "*.htm" \) | sort | while read -r HTML_FILE; do
    cat "$HTML_FILE" | \
        sed 's/<style[^>]*>.*<\/style>//g' | \
        sed 's/<script[^>]*>.*<\/script>//g' | \
        sed 's/<[^>]*>//g' | \
        sed 's/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#[0-9]*;//g' | \
        sed '/^[[:space:]]*$/d'
    echo ""
    echo ""
done > "$OUTPUT_FILE"

rm -rf "$TEMP_DIR"
echo "$OUTPUT_FILE"
