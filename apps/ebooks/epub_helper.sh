#!/bin/bash
# EPUB helper - extracts and provides chapter info
# Usage: epub_helper.sh extract <epub_file>

COMMAND="$1"
EPUB_FILE="$2"

if [ "$COMMAND" != "extract" ] || [ ! -f "$EPUB_FILE" ]; then
    echo '{"error": "Usage: epub_helper.sh extract <epub_file>"}'
    exit 1
fi

# Create temp directory for this book
BOOK_HASH=$(echo "$EPUB_FILE" | md5sum | cut -d' ' -f1)
EXTRACT_DIR="/tmp/flick_epub_$BOOK_HASH"

# Only extract if not already done
if [ ! -d "$EXTRACT_DIR" ]; then
    mkdir -p "$EXTRACT_DIR"
    unzip -q -o "$EPUB_FILE" -d "$EXTRACT_DIR" 2>/dev/null
fi

# Find content.opf
CONTENT_OPF=$(find "$EXTRACT_DIR" -name "*.opf" 2>/dev/null | head -1)

if [ -z "$CONTENT_OPF" ]; then
    echo '{"error": "Invalid EPUB - no OPF found"}'
    exit 1
fi

OPF_DIR=$(dirname "$CONTENT_OPF")

# Extract title
TITLE=$(grep -oP '<dc:title[^>]*>\K[^<]+' "$CONTENT_OPF" 2>/dev/null | head -1)
[ -z "$TITLE" ] && TITLE=$(basename "$EPUB_FILE" .epub)
# Escape for JSON
TITLE=$(echo "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')

# Build chapters array by reading spine and manifest
CHAPTERS="["
FIRST=true

# Read the OPF file content
OPF_CONTENT=$(cat "$CONTENT_OPF")

# Get spine idrefs
SPINE_IDREFS=$(echo "$OPF_CONTENT" | grep -oP '<itemref[^>]*idref="[^"]+' | sed 's/.*idref="//' | tr '\n' ' ')

for IDREF in $SPINE_IDREFS; do
    # Find the href for this id in manifest - look for id="$IDREF" and extract href
    HREF=$(echo "$OPF_CONTENT" | grep -oP "<item[^>]*id=\"$IDREF\"[^>]*" | grep -oP 'href="[^"]+' | sed 's/href="//')

    if [ -n "$HREF" ]; then
        # Handle relative paths
        if [[ "$HREF" != /* ]]; then
            CHAPTER_PATH="$OPF_DIR/$HREF"
        else
            CHAPTER_PATH="$EXTRACT_DIR$HREF"
        fi

        if [ -f "$CHAPTER_PATH" ]; then
            # Get chapter title from the HTML
            CHAPTER_TITLE=$(grep -oP '<title>\K[^<]+' "$CHAPTER_PATH" 2>/dev/null | head -1)
            [ -z "$CHAPTER_TITLE" ] && CHAPTER_TITLE=$(basename "$HREF" | sed 's/\.[^.]*$//')

            # Escape for JSON
            CHAPTER_TITLE=$(echo "$CHAPTER_TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')
            CHAPTER_PATH_ESC=$(echo "$CHAPTER_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')

            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                CHAPTERS="$CHAPTERS,"
            fi
            CHAPTERS="$CHAPTERS{\"title\":\"$CHAPTER_TITLE\",\"path\":\"$CHAPTER_PATH_ESC\"}"
        fi
    fi
done

CHAPTERS="$CHAPTERS]"

echo "{\"title\":\"$TITLE\",\"extractDir\":\"$EXTRACT_DIR\",\"opfDir\":\"$OPF_DIR\",\"chapters\":$CHAPTERS}"
