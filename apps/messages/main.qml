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

    // Models
    ListModel {
        id: conversationsModel
    }

    ListModel {
        id: messagesModel
    }

    Component.onCompleted: {
        loadConfig()
        loadConversations()
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
                    messagesList.positionViewAtEnd()
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
        currentContactName = contactName || phoneNumber
        currentView = "conversation"
        lastMessageText = ""
        userScrolledUp = false
        loadMessages(phoneNumber)
        // Initial load always scrolls to bottom
        if (messagesModel.count > 0) {
            messagesList.positionViewAtEnd()
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
                                var name = model.contact_name || model.phone_number
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
                                text: model.contact_name || model.phone_number
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

                // Back button
                Rectangle {
                    width: 24 * textScale
                    height: 24 * textScale
                    radius: 12 * textScale
                    anchors.verticalCenter: parent.verticalCenter
                    color: backArea.pressed ? "#3a3a4e" : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        color: accentColor
                        font.pixelSize: 12 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        onClicked: backToList()
                    }
                }

                // Contact info
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1 * textScale

                    Text {
                        text: currentContactName
                        color: "white"
                        font.pixelSize: 11 * textScale
                        font.weight: Font.Bold
                    }

                    Text {
                        text: currentConversation !== currentContactName ? currentConversation : ""
                        color: "#888899"
                        font.pixelSize: 8 * textScale
                        visible: currentConversation !== currentContactName
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
            anchors.bottom: inputArea.top
            anchors.margins: 8 * textScale
            anchors.bottomMargin: 4 * textScale
            model: messagesModel
            clip: true
            spacing: 5 * textScale
            verticalLayoutDirection: ListView.TopToBottom

            // Track when user scrolls
            onContentYChanged: {
                // If not at bottom, user has scrolled up
                if (contentHeight > height) {
                    var atBottom = (contentY + height) >= (contentHeight - 50)
                    userScrolledUp = !atBottom
                }
            }

            // When content height changes (new messages), scroll to bottom if not user-scrolled
            onContentHeightChanged: {
                if (!userScrolledUp && contentHeight > height) {
                    // Use a timer to ensure layout is complete
                    scrollToBottomTimer.restart()
                }
            }

            Timer {
                id: scrollToBottomTimer
                interval: 50
                onTriggered: {
                    if (!userScrolledUp) {
                        messagesList.positionViewAtEnd()
                    }
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
    }

    // Back button (only on list view) - matches other apps
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: backBtnArea.pressed ? accentPressed : accentColor
        visible: currentView === "list"
        z: 100

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
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
