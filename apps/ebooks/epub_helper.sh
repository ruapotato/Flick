#!/bin/bash
# EPUB helper - extracts and provides chapter info
# Usage: epub_helper.sh <command> <epub_file> [args]
# Commands:
#   extract <epub_file> - Extract to temp dir, output JSON with chapter list
#   cleanup <extract_dir> - Remove extracted files

COMMAND="$1"
EPUB_FILE="$2"

case "$COMMAND" in
    extract)
        if [ ! -f "$EPUB_FILE" ]; then
            echo '{"error": "File not found"}'
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

        # Get chapters in spine order
        CHAPTERS="["
        FIRST=true

        # Get spine item refs
        while IFS= read -r IDREF; do
            [ -z "$IDREF" ] && continue

            # Find href for this idref in manifest
            HREF=$(grep -oP "id=\"$IDREF\"[^>]*href=\"\K[^\"]+|href=\"([^\"]+)\"[^>]*id=\"$IDREF\"" "$CONTENT_OPF" 2>/dev/null | head -1)

            if [ -n "$HREF" ]; then
                CHAPTER_PATH="$OPF_DIR/$HREF"
                if [ -f "$CHAPTER_PATH" ]; then
                    # Get chapter title from the HTML
                    CHAPTER_TITLE=$(grep -oP '<title>\K[^<]+' "$CHAPTER_PATH" 2>/dev/null | head -1)
                    [ -z "$CHAPTER_TITLE" ] && CHAPTER_TITLE=$(basename "$HREF" | sed 's/\.[^.]*$//')

                    # Escape for JSON
                    CHAPTER_TITLE=$(echo "$CHAPTER_TITLE" | sed 's/"/\\"/g' | sed "s/'/\\'/g")

                    if [ "$FIRST" = true ]; then
                        FIRST=false
                    else
                        CHAPTERS="$CHAPTERS,"
                    fi
                    CHAPTERS="$CHAPTERS{\"title\":\"$CHAPTER_TITLE\",\"path\":\"$CHAPTER_PATH\"}"
                fi
            fi
        done < <(grep -oP 'itemref[^>]*idref="\K[^"]+' "$CONTENT_OPF" 2>/dev/null)

        CHAPTERS="$CHAPTERS]"

        # Escape title for JSON
        TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')

        echo "{\"title\":\"$TITLE\",\"extractDir\":\"$EXTRACT_DIR\",\"opfDir\":\"$OPF_DIR\",\"chapters\":$CHAPTERS}"
        ;;

    cleanup)
        EXTRACT_DIR="$2"
        if [ -d "$EXTRACT_DIR" ] && [[ "$EXTRACT_DIR" == /tmp/flick_epub_* ]]; then
            rm -rf "$EXTRACT_DIR"
            echo '{"status": "cleaned"}'
        fi
        ;;

    *)
        echo '{"error": "Unknown command"}'
        exit 1
        ;;
esac
