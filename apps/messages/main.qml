import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Messages"
    color: "#0a0a0f"

    property real textScale: 2.0
    property color accentColor: "#e94560"
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property string currentView: "list"  // "list" or "conversation"
    property string currentConversation: ""  // Phone number of current conversation
    property string currentContactName: ""
    property string messageInput: ""
    property string lastMessageText: ""  // Track last message for smart scrolling
    property bool userScrolledUp: false  // Track if user scrolled away from bottom
    property string newMessagePhone: ""  // Phone number for new message
    property string newMessageSearch: "" // Search filter for contacts
    property string saveContactPhone: "" // Phone number when saving new contact
    property string saveContactName: ""  // Name input for new contact

    // Models
    ListModel {
        id: conversationsModel
    }

    ListModel {
        id: messagesModel
    }

    ListModel {
        id: contactsModel
    }

    Component.onCompleted: {
        loadConfig()
        loadContacts()
        loadConversations()
        checkOpenConversationHint()
    }

    function checkOpenConversationHint() {
        var hintPath = "/home/droidian/.local/state/flick/open_conversation.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + hintPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                if (data.phone_number) {
                    // Clear the hint file
                    var clearXhr = new XMLHttpRequest()
                    clearXhr.open("PUT", "file://" + hintPath, false)
                    clearXhr.send("{}")
                    // Open the conversation
                    openConversation(data.phone_number, "")
                }
            }
        } catch (e) {
            // No hint file or invalid
        }
    }

    function loadConfig() {
        var configPath = "/home/droidian/.local/state/flick/display_config.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale !== undefined) {
                    textScale = config.text_scale
                }
            }
        } catch (e) {
            console.log("Using default text scale: " + textScale)
        }
    }

    function loadContacts() {
        var contactsPath = "/home/droidian/.local/state/flick/contacts.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + contactsPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                contactsModel.clear()
                for (var i = 0; i < data.contacts.length; i++) {
                    contactsModel.append(data.contacts[i])
                }
            }
        } catch (e) {
            console.log("No contacts found")
        }
    }

    function getContactName(phoneNumber) {
        // Normalize phone number for comparison (remove spaces, dashes)
        var normalizedInput = phoneNumber.replace(/[\s\-\(\)]/g, "")
        for (var i = 0; i < contactsModel.count; i++) {
            var contact = contactsModel.get(i)
            var normalizedContact = contact.phone.replace(/[\s\-\(\)]/g, "")
            if (normalizedInput === normalizedContact ||
                normalizedInput.endsWith(normalizedContact) ||
                normalizedContact.endsWith(normalizedInput)) {
                return contact.name
            }
        }
        return ""
    }

    function saveNewContact(name, phone) {
        // Load existing contacts
        var contactsPath = "/home/droidian/.local/state/flick/contacts.json"
        var contacts = []
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + contactsPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                contacts = data.contacts || []
            }
        } catch (e) {}

        // Get initials
        var parts = name.trim().split(" ")
        var initials = ""
        if (parts.length >= 2) {
            initials = (parts[0][0] + parts[parts.length-1][0]).toUpperCase()
        } else {
            initials = name.substring(0, 2).toUpperCase()
        }

        // Add new contact
        contacts.push({
            name: name,
            phone: phone,
            email: "",
            initials: initials
        })

        // Sort by name
        contacts.sort(function(a, b) {
            return a.name.localeCompare(b.name)
        })

        // Save back
        var saveXhr = new XMLHttpRequest()
        saveXhr.open("PUT", "file://" + contactsPath, false)
        try {
            saveXhr.send(JSON.stringify({contacts: contacts}, null, 2))
        } catch (e) {
            console.log("Error saving contact: " + e)
        }

        // Reload contacts
        loadContacts()
    }

    function loadConversations() {
        var messagesPath = "/home/droidian/.local/state/flick/messages.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + messagesPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                conversationsModel.clear()

                // Group messages by phone number
                for (var i = 0; i < data.conversations.length && i < 100; i++) {
                    conversationsModel.append(data.conversations[i])
                }
            }
        } catch (e) {
            console.log("No messages found")
        }
    }

    function loadMessages(phoneNumber) {
        var messagesPath = "/home/droidian/.local/state/flick/messages.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + messagesPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)

                // Find conversation for this phone number
                var newMessages = []
                for (var i = 0; i < data.conversations.length; i++) {
                    if (data.conversations[i].phone_number === phoneNumber) {
                        newMessages = data.conversations[i].messages || []
                        break
                    }
                }

                // Check if we have new messages
                var hasNewMessages = false
                if (newMessages.length > 0) {
                    var newestMsg = newMessages[newMessages.length - 1]
                    if (newestMsg.text !== lastMessageText) {
                        hasNewMessages = true
                        lastMessageText = newestMsg.text
                    }
                }

                // Update model
                messagesModel.clear()
                for (var j = 0; j < newMessages.length; j++) {
                    messagesModel.append(newMessages[j])
                }

                // Only auto-scroll if user hasn't scrolled up and we have new messages
                if (hasNewMessages && !userScrolledUp && messagesModel.count > 0) {
                    // Use a small delay to ensure layout is complete
                    scrollAfterLoadTimer.restart()
                }
            }
        } catch (e) {
            console.log("Failed to load messages for " + phoneNumber)
        }
    }

    function writeCommand(action, data) {
        // Write command to file for daemon to process
        var cmd = JSON.stringify({action: action, data: data})
        console.log("CMD:" + cmd)
    }

    function sendMessage() {
        if (messageInput.length > 0 && currentConversation.length > 0) {
            writeCommand("send", {
                phone_number: currentConversation,
                message: messageInput
            })

            // Add to UI immediately for responsiveness
            messagesModel.append({
                text: messageInput,
                direction: "outgoing",
                timestamp: new Date().toISOString(),
                status: "sending"
            })

            lastMessageText = messageInput
            messageInput = ""
            userScrolledUp = false
            messagesList.positionViewAtEnd()
        }
    }

    function formatTimestamp(isoString) {
        try {
            var date = new Date(isoString)
            var now = new Date()
            var isToday = date.toDateString() === now.toDateString()

            var yesterday = new Date(now)
            yesterday.setDate(yesterday.getDate() - 1)
            var isYesterday = date.toDateString() === yesterday.toDateString()

            if (isToday) {
                return date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})
            } else if (isYesterday) {
                return "Yesterday"
            } else {
                return date.toLocaleDateString([], {month: 'short', day: 'numeric'})
            }
        } catch (e) {
            return ""
        }
    }

    function formatMessageTime(isoString) {
        try {
            var date = new Date(isoString)
            return date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})
        } catch (e) {
            return ""
        }
    }

    function openConversation(phoneNumber, contactName) {
        currentConversation = phoneNumber
        // Try to get contact name from contacts if not provided
        var name = contactName || getContactName(phoneNumber)
        currentContactName = name || phoneNumber
        currentView = "conversation"
        lastMessageText = ""
        userScrolledUp = false
        loadMessages(phoneNumber)
        // Clear unread count for this conversation
        markConversationRead(phoneNumber)
        // Initial load always scrolls to bottom
        if (messagesModel.count > 0) {
            messagesList.positionViewAtEnd()
        }
    }

    function markConversationRead(phoneNumber) {
        var messagesPath = "/home/droidian/.local/state/flick/messages.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + messagesPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                var normalizedInput = phoneNumber.replace(/[\s\-\(\)\+]/g, "")
                if (normalizedInput.length === 11 && normalizedInput.charAt(0) === '1') {
                    normalizedInput = normalizedInput.substring(1)
                }

                // Find and update conversation
                for (var i = 0; i < data.conversations.length; i++) {
                    var conv = data.conversations[i]
                    var normalizedConv = conv.phone_number.replace(/[\s\-\(\)\+]/g, "")
                    if (normalizedConv.length === 11 && normalizedConv.charAt(0) === '1') {
                        normalizedConv = normalizedConv.substring(1)
                    }
                    if (normalizedInput === normalizedConv) {
                        conv.unread_count = 0
                        break
                    }
                }

                // Save back
                var saveXhr = new XMLHttpRequest()
                saveXhr.open("PUT", "file://" + messagesPath, false)
                saveXhr.send(JSON.stringify(data, null, 2))
            }
        } catch (e) {
            console.log("Failed to mark conversation read: " + e)
        }
    }

    function backToList() {
        currentView = "list"
        currentConversation = ""
        messageInput = ""
        loadConversations()
    }

    // Refresh timer
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (currentView === "list") {
                loadConversations()
            } else if (currentView === "conversation" && currentConversation.length > 0) {
                loadMessages(currentConversation)
            }
        }
    }

    // Timer for scrolling after new messages load
    Timer {
        id: scrollAfterLoadTimer
        interval: 100
        onTriggered: {
            if (!userScrolledUp && messagesModel.count > 0) {
                messagesList.positionViewAtEnd()
            }
        }
    }

    // ===== CONVERSATION LIST VIEW =====
    Item {
        id: conversationListView
        anchors.fill: parent
        anchors.bottomMargin: 24 * textScale
        visible: currentView === "list"

        // Header
        Rectangle {
            id: listHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36 * textScale
            color: "#0a0a0f"
            z: 10

            Text {
                anchors.centerIn: parent
                text: "Messages"
                color: accentColor
                font.pixelSize: 14 * textScale
                font.weight: Font.Bold
            }

            // Separator line
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#2a2a4e"
            }
        }

        // Conversations list
        ListView {
            id: conversationsList
            anchors.top: listHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: 2 * textScale
            model: conversationsModel
            clip: true
            spacing: 1 * textScale

            delegate: Rectangle {
                width: conversationsList.width
                height: 44 * textScale
                color: conversationArea.pressed ? "#2a2a4e" : "#1a1a2e"
                radius: 0

                Row {
                    anchors.fill: parent
                    anchors.margins: 8 * textScale
                    spacing: 8 * textScale

                    // Avatar circle
                    Rectangle {
                        width: 28 * textScale
                        height: 28 * textScale
                        radius: 14 * textScale
                        anchors.verticalCenter: parent.verticalCenter
                        color: accentColor

                        Text {
                            anchors.centerIn: parent
                            text: {
                                var contactName = getContactName(model.phone_number)
                                var name = contactName || model.contact_name || model.phone_number
                                return name.charAt(0).toUpperCase()
                            }
                            color: "white"
                            font.pixelSize: 12 * textScale
                            font.weight: Font.Bold
                        }
                    }

                    // Message info
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 44 * textScale
                        spacing: 2 * textScale

                        Row {
                            width: parent.width
                            spacing: 4 * textScale

                            Text {
                                text: {
                                    var contactName = getContactName(model.phone_number)
                                    return contactName || model.contact_name || model.phone_number
                                }
                                color: "white"
                                font.pixelSize: 10 * textScale
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                width: parent.width - 48 * textScale
                            }

                            Text {
                                text: formatTimestamp(model.last_message_time)
                                color: "#888899"
                                font.pixelSize: 8 * textScale
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            spacing: 4 * textScale
                            width: parent.width

                            Text {
                                text: model.last_message
                                color: "#aaaacc"
                                font.pixelSize: 9 * textScale
                                elide: Text.ElideRight
                                width: parent.width - (model.unread_count > 0 ? 22 * textScale : 0)
                                maximumLineCount: 1
                            }

                            // Unread badge
                            Rectangle {
                                width: 17 * textScale
                                height: 17 * textScale
                                radius: 8.5 * textScale
                                color: accentColor
                                visible: model.unread_count > 0

                                Text {
                                    anchors.centerIn: parent
                                    text: model.unread_count
                                    color: "white"
                                    font.pixelSize: 8 * textScale
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }
                }

                // Bottom separator
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 44 * textScale
                    height: 1
                    color: "#2a2a4e"
                }

                MouseArea {
                    id: conversationArea
                    anchors.fill: parent
                    onClicked: openConversation(model.phone_number, model.contact_name)
                }
            }

            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: 10 * textScale
                visible: conversationsModel.count === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "💬"
                    font.pixelSize: 38 * textScale
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No messages yet"
                    color: "#666688"
                    font.pixelSize: 11 * textScale
                }
            }
        }
    }

    // ===== CONVERSATION DETAIL VIEW =====
    Item {
        id: conversationDetailView
        anchors.fill: parent
        anchors.bottomMargin: 24 * textScale
        visible: currentView === "conversation"

        // Header
        Rectangle {
            id: detailHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 34 * textScale
            color: "#0f0f14"
            z: 10

            Row {
                anchors.fill: parent
                anchors.margins: 8 * textScale
                spacing: 8 * textScale

                // Contact info
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1 * textScale
                    width: parent.width - 40 * textScale

                    Text {
                        text: currentContactName
                        color: "white"
                        font.pixelSize: 11 * textScale
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: currentConversation !== currentContactName ? currentConversation : ""
                        color: "#888899"
                        font.pixelSize: 8 * textScale
                        visible: currentConversation !== currentContactName
                    }
                }

                // Save contact button (only for unknown numbers)
                Rectangle {
                    width: 24 * textScale
                    height: 24 * textScale
                    radius: 12 * textScale
                    anchors.verticalCenter: parent.verticalCenter
                    color: saveContactArea.pressed ? "#2a6a2a" : "#228B22"
                    visible: currentContactName === currentConversation

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: "white"
                        font.pixelSize: 14 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: saveContactArea
                        anchors.fill: parent
                        onClicked: {
                            saveContactPhone = currentConversation
                            saveContactName = ""
                            currentView = "saveContact"
                        }
                    }
                }
            }

            // Separator line
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#2a2a4e"
            }
        }

        // Messages list
        ListView {
            id: messagesList
            anchors.top: detailHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footerArea.top
            anchors.margins: 8 * textScale
            anchors.bottomMargin: 4 * textScale
            model: messagesModel
            clip: true
            spacing: 5 * textScale
            verticalLayoutDirection: ListView.TopToBottom

            // Track when user manually scrolls away from bottom
            onContentYChanged: {
                if (contentHeight > height) {
                    var atBottom = (contentY + height) >= (contentHeight - 50)
                    userScrolledUp = !atBottom
                }
            }

            delegate: Item {
                width: messagesList.width
                height: messageBubble.height + 4 * textScale

                Rectangle {
                    id: messageBubble
                    anchors.left: model.direction === "incoming" ? parent.left : undefined
                    anchors.right: model.direction === "outgoing" ? parent.right : undefined
                    width: Math.min(messageText.implicitWidth + 14 * textScale, parent.width * 0.85)
                    height: messageColumn.height + 10 * textScale
                    radius: 10 * textScale
                    color: model.direction === "outgoing" ? accentColor : "#1a1a2e"

                    Column {
                        id: messageColumn
                        anchors.centerIn: parent
                        width: parent.width - 10 * textScale
                        spacing: 2 * textScale

                        Text {
                            id: messageText
                            text: model.text
                            color: "white"
                            font.pixelSize: 10 * textScale
                            wrapMode: Text.Wrap
                            width: parent.width
                        }

                        Row {
                            anchors.right: parent.right
                            spacing: 4 * textScale

                            Text {
                                text: formatMessageTime(model.timestamp)
                                color: model.direction === "outgoing" ? "#ffffff99" : "#88889999"
                                font.pixelSize: 7 * textScale
                            }

                            Text {
                                text: {
                                    if (model.direction === "outgoing") {
                                        if (model.status === "sending") return "..."
                                        if (model.status === "sent") return "✓"
                                        if (model.status === "delivered") return "✓✓"
                                    }
                                    return ""
                                }
                                color: "#ffffff99"
                                font.pixelSize: 7 * textScale
                                visible: model.direction === "outgoing"
                            }
                        }
                    }
                }
            }

            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: 10 * textScale
                visible: messagesModel.count === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "💬"
                    font.pixelSize: 29 * textScale
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No messages yet"
                    color: "#666688"
                    font.pixelSize: 10 * textScale
                }
            }
        }

        // Input area
        Rectangle {
            id: inputArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8 * textScale
            height: 31 * textScale
            color: "#1a1a2e"
            radius: 15.5 * textScale
            border.color: "#2a2a4e"
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.margins: 5 * textScale
                spacing: 5 * textScale

                // Text input
                Rectangle {
                    width: parent.width - 31 * textScale
                    height: parent.height
                    color: "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    TextInput {
                        id: messageInputField
                        anchors.fill: parent
                        anchors.leftMargin: 5 * textScale
                        text: messageInput
                        onTextChanged: messageInput = text
                        color: "white"
                        font.pixelSize: 10 * textScale
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true

                        Keys.onReturnPressed: sendMessage()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            text: "Type a message..."
                            color: "#666688"
                            font.pixelSize: 10 * textScale
                            visible: messageInput.length === 0
                        }
                    }
                }

                // Send button
                Rectangle {
                    width: 24 * textScale
                    height: 24 * textScale
                    radius: 12 * textScale
                    anchors.verticalCenter: parent.verticalCenter
                    color: messageInput.length > 0 ? (sendArea.pressed ? "#d93550" : accentColor) : "#3a3a4e"

                    Text {
                        anchors.centerIn: parent
                        text: "→"
                        color: messageInput.length > 0 ? "white" : "#666"
                        font.pixelSize: 11 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: sendArea
                        anchors.fill: parent
                        enabled: messageInput.length > 0
                        onClicked: sendMessage()
                    }
                }
            }
        }

        // Footer area for back button (prevents messages from rendering behind it)
        Rectangle {
            id: footerArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: inputArea.top
            height: 110
            color: "transparent"
            z: 50
        }

        // Back button - bottom right, above input (matches other apps)
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: inputArea.top
            anchors.rightMargin: 24
            anchors.bottomMargin: 8
            width: 96
            height: 96
            radius: 48
            color: backArea.pressed ? accentPressed : accentColor
            z: 100

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 40
                font.weight: Font.Medium
                color: "#ffffff"
            }

            MouseArea {
                id: backArea
                anchors.fill: parent
                onClicked: backToList()
            }
        }
    }

    // ===== NEW MESSAGE VIEW =====
    Item {
        id: newMessageView
        anchors.fill: parent
        anchors.bottomMargin: 24 * textScale
        visible: currentView === "newMessage"

        // Header
        Rectangle {
            id: newMsgHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36 * textScale
            color: "#0f0f14"
            z: 10

            Row {
                anchors.fill: parent
                anchors.margins: 8 * textScale
                spacing: 8 * textScale

                // Back button
                Rectangle {
                    width: 24 * textScale
                    height: 24 * textScale
                    radius: 12 * textScale
                    anchors.verticalCenter: parent.verticalCenter
                    color: newMsgBackArea.pressed ? "#3a3a4e" : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        color: accentColor
                        font.pixelSize: 12 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: newMsgBackArea
                        anchors.fill: parent
                        onClicked: {
                            currentView = "list"
                        }
                    }
                }

                Text {
                    text: "New Message"
                    color: "white"
                    font.pixelSize: 11 * textScale
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Separator line
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#2a2a4e"
            }
        }

        // Phone number input
        Rectangle {
            id: phoneInputRow
            anchors.top: newMsgHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8 * textScale
            anchors.topMargin: 8 * textScale
            height: 28 * textScale
            color: "#1a1a2e"
            radius: 14 * textScale
            border.color: "#2a2a4e"
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.margins: 5 * textScale
                spacing: 5 * textScale

                Text {
                    text: "To:"
                    color: "#888899"
                    font.pixelSize: 10 * textScale
                    anchors.verticalCenter: parent.verticalCenter
                }

                TextInput {
                    id: phoneInputField
                    width: parent.width - 80 * textScale
                    height: parent.height
                    text: newMessagePhone
                    onTextChanged: {
                        newMessagePhone = text
                        newMessageSearch = text
                    }
                    color: "white"
                    font.pixelSize: 10 * textScale
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    inputMethodHints: Qt.ImhDialableCharactersOnly

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Phone number or name..."
                        color: "#666688"
                        font.pixelSize: 10 * textScale
                        visible: newMessagePhone.length === 0
                    }
                }

                // Start conversation button
                Rectangle {
                    width: 50 * textScale
                    height: 18 * textScale
                    radius: 9 * textScale
                    anchors.verticalCenter: parent.verticalCenter
                    color: newMessagePhone.length > 0 ? (startChatArea.pressed ? "#d93550" : accentColor) : "#3a3a4e"

                    Text {
                        anchors.centerIn: parent
                        text: "Start"
                        color: newMessagePhone.length > 0 ? "white" : "#666"
                        font.pixelSize: 8 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: startChatArea
                        anchors.fill: parent
                        enabled: newMessagePhone.length > 0
                        onClicked: {
                            openConversation(newMessagePhone, "")
                        }
                    }
                }
            }
        }

        // Contacts list
        ListView {
            id: contactsListView
            anchors.top: phoneInputRow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8 * textScale
            anchors.topMargin: 4 * textScale
            model: contactsModel
            clip: true
            spacing: 2 * textScale

            delegate: Rectangle {
                width: contactsListView.width
                height: visible ? 36 * textScale : 0
                visible: {
                    if (newMessageSearch.length === 0) return true
                    var search = newMessageSearch.toLowerCase()
                    return model.name.toLowerCase().indexOf(search) >= 0 ||
                           model.phone.indexOf(search) >= 0
                }
                color: contactItemArea.pressed ? "#2a2a4e" : "#1a1a2e"
                radius: 8 * textScale

                Row {
                    anchors.fill: parent
                    anchors.margins: 6 * textScale
                    spacing: 8 * textScale

                    // Avatar circle
                    Rectangle {
                        width: 24 * textScale
                        height: 24 * textScale
                        radius: 12 * textScale
                        anchors.verticalCenter: parent.verticalCenter
                        color: {
                            var colors = [accentColor, "#4a9eff", "#50c878", "#ff8c42", "#9b59b6", "#1abc9c"]
                            var hash = 0
                            var name = model.name
                            for (var i = 0; i < name.length; i++) {
                                hash = name.charCodeAt(i) + ((hash << 5) - hash)
                            }
                            return colors[Math.abs(hash) % colors.length]
                        }

                        Text {
                            anchors.centerIn: parent
                            text: {
                                var parts = model.name.trim().split(" ")
                                if (parts.length >= 2) {
                                    return (parts[0][0] + parts[parts.length-1][0]).toUpperCase()
                                }
                                return model.name.substring(0, 2).toUpperCase()
                            }
                            color: "white"
                            font.pixelSize: 9 * textScale
                            font.weight: Font.Bold
                        }
                    }

                    // Contact info
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1 * textScale

                        Text {
                            text: model.name
                            color: "white"
                            font.pixelSize: 10 * textScale
                            font.weight: Font.Bold
                        }

                        Text {
                            text: model.phone
                            color: "#888899"
                            font.pixelSize: 8 * textScale
                        }
                    }
                }

                MouseArea {
                    id: contactItemArea
                    anchors.fill: parent
                    onClicked: {
                        openConversation(model.phone, model.name)
                    }
                }
            }

            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: 10 * textScale
                visible: contactsModel.count === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "📱"
                    font.pixelSize: 29 * textScale
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No contacts yet"
                    color: "#666688"
                    font.pixelSize: 10 * textScale
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Type a phone number above"
                    color: "#555577"
                    font.pixelSize: 9 * textScale
                }
            }
        }
    }

    // ===== SAVE CONTACT VIEW =====
    Item {
        id: saveContactView
        anchors.fill: parent
        anchors.bottomMargin: 24 * textScale
        visible: currentView === "saveContact"

        // Header
        Rectangle {
            id: saveContactHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36 * textScale
            color: "#0f0f14"
            z: 10

            Row {
                anchors.fill: parent
                anchors.margins: 8 * textScale
                spacing: 8 * textScale

                // Back button
                Rectangle {
                    width: 24 * textScale
                    height: 24 * textScale
                    radius: 12 * textScale
                    anchors.verticalCenter: parent.verticalCenter
                    color: saveBackArea.pressed ? "#3a3a4e" : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        color: accentColor
                        font.pixelSize: 12 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: saveBackArea
                        anchors.fill: parent
                        onClicked: {
                            currentView = "conversation"
                        }
                    }
                }

                Text {
                    text: "Save Contact"
                    color: "white"
                    font.pixelSize: 11 * textScale
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Separator line
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#2a2a4e"
            }
        }

        // Form
        Column {
            anchors.top: saveContactHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16 * textScale
            anchors.topMargin: 24 * textScale
            spacing: 16 * textScale

            // Phone number display
            Column {
                width: parent.width
                spacing: 4 * textScale

                Text {
                    text: "Phone Number"
                    color: "#888899"
                    font.pixelSize: 9 * textScale
                }

                Rectangle {
                    width: parent.width
                    height: 28 * textScale
                    color: "#1a1a2e"
                    radius: 8 * textScale

                    Text {
                        anchors.fill: parent
                        anchors.margins: 8 * textScale
                        text: saveContactPhone
                        color: "#aaaacc"
                        font.pixelSize: 10 * textScale
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // Name input
            Column {
                width: parent.width
                spacing: 4 * textScale

                Text {
                    text: "Name"
                    color: "#888899"
                    font.pixelSize: 9 * textScale
                }

                Rectangle {
                    width: parent.width
                    height: 28 * textScale
                    color: "#1a1a2e"
                    radius: 8 * textScale
                    border.color: "#2a2a4e"
                    border.width: 1

                    TextInput {
                        id: saveContactNameInput
                        anchors.fill: parent
                        anchors.margins: 8 * textScale
                        text: saveContactName
                        onTextChanged: saveContactName = text
                        color: "white"
                        font.pixelSize: 10 * textScale
                        verticalAlignment: TextInput.AlignVCenter

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Enter name..."
                            color: "#666688"
                            font.pixelSize: 10 * textScale
                            visible: saveContactName.length === 0
                        }
                    }
                }
            }

            // Save button
            Rectangle {
                width: parent.width
                height: 32 * textScale
                radius: 16 * textScale
                color: saveContactName.length > 0 ? (doSaveArea.pressed ? "#1a6a1a" : "#228B22") : "#3a3a4e"

                Text {
                    anchors.centerIn: parent
                    text: "Save Contact"
                    color: saveContactName.length > 0 ? "white" : "#666"
                    font.pixelSize: 10 * textScale
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: doSaveArea
                    anchors.fill: parent
                    enabled: saveContactName.length > 0
                    onClicked: {
                        saveNewContact(saveContactName, saveContactPhone)
                        // Update current contact name
                        currentContactName = saveContactName
                        currentView = "conversation"
                    }
                }
            }
        }
    }

    // New message FAB (only on list view)
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: backBtn.top
        anchors.rightMargin: 24
        anchors.bottomMargin: 16
        width: 96
        height: 96
        radius: 48
        color: newMsgArea.pressed ? Qt.darker("#4a9eff", 1.2) : "#4a9eff"
        visible: currentView === "list"
        z: 100

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "+"
            font.pixelSize: 48
            font.weight: Font.Medium
            color: "#ffffff"
        }

        MouseArea {
            id: newMsgArea
            anchors.fill: parent
            onClicked: {
                currentView = "newMessage"
                newMessagePhone = ""
                newMessageSearch = ""
            }
        }
    }

    // Back button (only on list view) - matches other apps
    Rectangle {
        id: backBtn
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 96
        height: 96
        radius: 48
        color: backBtnArea.pressed ? accentPressed : accentColor
        visible: currentView === "list"
        z: 100

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 40
            font.weight: Font.Medium
            color: "#ffffff"
        }

        MouseArea {
            id: backBtnArea
            anchors.fill: parent
            onClicked: Qt.quit()
        }
    }

    // Home indicator
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 8
        width: 120
        height: 4
        radius: 2
        color: "#333344"
    }
}
