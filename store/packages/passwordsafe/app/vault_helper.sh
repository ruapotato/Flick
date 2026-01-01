#!/bin/bash
# Password Safe Helper - Wraps keepassxc-cli for QML
# Usage: vault_helper.sh <action> <result_file> [args...]
#
# Actions:
#   unlock <vault> <password>     - Test unlock, returns "OK" or "ERROR: ..."
#   list <vault> <password>       - List entries as JSON array
#   show <vault> <password> <entry> - Show entry as JSON
#   add <vault> <password> <title> <user> <pass> [url] [notes]
#   delete <vault> <password> <entry>
#   generate [length]             - Generate password (no vault needed)
#   create <vault> <password>     - Create new vault

ACTION="$1"
RESULT_FILE="$2"
shift 2

write_result() {
    echo "$1" > "$RESULT_FILE"
}

write_json() {
    echo "$1" > "$RESULT_FILE"
}

case "$ACTION" in
    unlock)
        VAULT="$1"
        PASSWORD="$2"
        OUTPUT=$(echo "$PASSWORD" | keepassxc-cli ls "$VAULT" 2>&1)
        if echo "$OUTPUT" | grep -q "Invalid credentials"; then
            write_result "ERROR:Wrong password"
        elif echo "$OUTPUT" | grep -q "Error"; then
            write_result "ERROR:$OUTPUT"
        else
            write_result "OK"
        fi
        ;;

    list)
        VAULT="$1"
        PASSWORD="$2"
        GROUP="${3:-/}"

        OUTPUT=$(echo "$PASSWORD" | keepassxc-cli ls "$VAULT" "$GROUP" 2>&1)

        if echo "$OUTPUT" | grep -qi "error\|invalid"; then
            write_result "ERROR:$OUTPUT"
            exit 1
        fi

        # Parse output into JSON
        JSON="["
        FIRST=true
        while IFS= read -r line; do
            # Skip empty lines and password prompt
            [ -z "$line" ] && continue
            echo "$line" | grep -qi "enter password" && continue

            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                JSON="$JSON,"
            fi

            if echo "$line" | grep -q '/$'; then
                # It's a group/folder
                NAME=$(echo "$line" | sed 's/\/$//')
                JSON="$JSON{\"type\":\"group\",\"name\":\"$NAME\"}"
            else
                # It's an entry
                JSON="$JSON{\"type\":\"entry\",\"title\":\"$line\"}"
            fi
        done <<< "$OUTPUT"
        JSON="$JSON]"

        write_json "$JSON"
        ;;

    show)
        VAULT="$1"
        PASSWORD="$2"
        ENTRY="$3"

        OUTPUT=$(echo "$PASSWORD" | keepassxc-cli show -s "$VAULT" "$ENTRY" 2>&1)

        if echo "$OUTPUT" | grep -qi "error\|invalid\|not find"; then
            write_result "ERROR:$OUTPUT"
            exit 1
        fi

        # Parse key: value output into JSON
        TITLE=""
        USERNAME=""
        PASSWORD_VAL=""
        URL=""
        NOTES=""
        UUID=""

        while IFS= read -r line; do
            case "$line" in
                Title:*) TITLE="${line#Title: }" ;;
                UserName:*) USERNAME="${line#UserName: }" ;;
                Password:*) PASSWORD_VAL="${line#Password: }" ;;
                URL:*) URL="${line#URL: }" ;;
                Notes:*) NOTES="${line#Notes: }" ;;
                Uuid:*) UUID="${line#Uuid: }" ;;
            esac
        done <<< "$OUTPUT"

        # Escape JSON strings
        escape_json() {
            echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr -d '\n'
        }

        JSON="{\"title\":\"$(escape_json "$TITLE")\","
        JSON="$JSON\"username\":\"$(escape_json "$USERNAME")\","
        JSON="$JSON\"password\":\"$(escape_json "$PASSWORD_VAL")\","
        JSON="$JSON\"url\":\"$(escape_json "$URL")\","
        JSON="$JSON\"notes\":\"$(escape_json "$NOTES")\","
        JSON="$JSON\"uuid\":\"$(escape_json "$UUID")\"}"

        write_json "$JSON"
        ;;

    add)
        VAULT="$1"
        PASSWORD="$2"
        TITLE="$3"
        USERNAME="$4"
        ENTRYPASS="$5"
        URL="${6:-}"
        NOTES="${7:-}"

        # keepassxc-cli add needs password twice (master + entry password)
        INPUT="$PASSWORD
$ENTRYPASS"

        OUTPUT=$(echo "$INPUT" | keepassxc-cli add -u "$USERNAME" -p "$VAULT" "$TITLE" 2>&1)

        if echo "$OUTPUT" | grep -qi "error\|invalid\|exists"; then
            write_result "ERROR:$OUTPUT"
        else
            # If URL or notes provided, edit the entry
            if [ -n "$URL" ]; then
                echo "$PASSWORD" | keepassxc-cli edit -u "$USERNAME" --url "$URL" "$VAULT" "$TITLE" 2>/dev/null
            fi
            write_result "OK"
        fi
        ;;

    edit)
        VAULT="$1"
        PASSWORD="$2"
        TITLE="$3"
        USERNAME="$4"
        ENTRYPASS="$5"
        URL="${6:-}"

        # Edit with new password
        INPUT="$PASSWORD
$ENTRYPASS"

        OUTPUT=$(echo "$INPUT" | keepassxc-cli edit -u "$USERNAME" -p --url "$URL" "$VAULT" "$TITLE" 2>&1)

        if echo "$OUTPUT" | grep -qi "error\|invalid"; then
            write_result "ERROR:$OUTPUT"
        else
            write_result "OK"
        fi
        ;;

    delete)
        VAULT="$1"
        PASSWORD="$2"
        ENTRY="$3"

        OUTPUT=$(echo "$PASSWORD" | keepassxc-cli rm "$VAULT" "$ENTRY" 2>&1)

        if echo "$OUTPUT" | grep -qi "error\|invalid"; then
            write_result "ERROR:$OUTPUT"
        else
            write_result "OK"
        fi
        ;;

    generate)
        LENGTH="${1:-20}"
        PASSWORD=$(keepassxc-cli generate -L "$LENGTH" 2>&1)
        write_result "$PASSWORD"
        ;;

    create)
        VAULT="$1"
        PASSWORD="$2"

        # Create vault - password entered twice
        INPUT="$PASSWORD
$PASSWORD"

        OUTPUT=$(echo "$INPUT" | keepassxc-cli db-create -p "$VAULT" 2>&1)

        if echo "$OUTPUT" | grep -qi "error"; then
            write_result "ERROR:$OUTPUT"
        else
            write_result "OK"
        fi
        ;;

    copy)
        VAULT="$1"
        PASSWORD="$2"
        ENTRY="$3"
        FIELD="${4:-password}"

        echo "$PASSWORD" | keepassxc-cli clip -a "$FIELD" "$VAULT" "$ENTRY" 2>&1
        write_result "OK"
        ;;

    search)
        VAULT="$1"
        PASSWORD="$2"
        QUERY="$3"

        OUTPUT=$(echo "$PASSWORD" | keepassxc-cli search "$VAULT" "$QUERY" 2>&1)

        # Parse into JSON array
        JSON="["
        FIRST=true
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            echo "$line" | grep -qi "enter password" && continue

            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                JSON="$JSON,"
            fi
            JSON="$JSON{\"title\":\"$line\"}"
        done <<< "$OUTPUT"
        JSON="$JSON]"

        write_json "$JSON"
        ;;

    writefile)
        FILEPATH="$1"
        CONTENT="$2"
        echo "$CONTENT" > "$FILEPATH"
        write_result "OK"
        ;;

    *)
        write_result "ERROR:Unknown action: $ACTION"
        exit 1
        ;;
esac
