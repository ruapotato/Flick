import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../shared"

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Email"
    color: "#0a0a0f"

    // Display config
    property real textScale: 1.0

    // State
    property string currentView: "loading" // loading, setup, inbox, email, compose, folders, settings
    property var accounts: []
    property string currentAccountId: ""
    property string currentFolder: "INBOX"
    property var emails: []
    property var currentEmail: null
    property var folders: []
    property bool loading: false
    property string errorMessage: ""

    // Command/response paths
    readonly property string stateDir: "/home/droidian/.local/state/flick/email"
    readonly property string commandsFile: stateDir + "/commands.json"
    readonly property string responseFile: stateDir + "/response.json"

    // Compose state
    property string composeTo: ""
    property string composeCc: ""
    property string composeSubject: ""
    property string composeBody: ""
    property string composeReplyTo: ""

    Component.onCompleted: {
        loadConfig()
        ensureStateDir()
        loadAccounts()
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
        } catch (e) {}
    }

    function ensureStateDir() {
        // State dir is created by backend
    }

    function sendCommand(cmd) {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + commandsFile, false)
        try {
            xhr.send(JSON.stringify(cmd))
            return true
        } catch (e) {
            console.log("Failed to send command: " + e)
            return false
        }
    }

    function readResponse() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + responseFile + "?t=" + Date.now(), false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                return JSON.parse(xhr.responseText)
            }
        } catch (e) {
            console.log("Failed to read response: " + e)
        }
        return null
    }

    function loadAccounts() {
        loading = true
        sendCommand({ action: "get_accounts" })

        // Poll for response
        responseTimer.responseHandler = function(resp) {
            loading = false
            if (resp && resp.accounts) {
                accounts = resp.accounts
                if (accounts.length === 0) {
                    currentView = "setup"
                } else {
                    currentAccountId = accounts[0].id
                    loadFolders()
                    loadEmails()
                    currentView = "inbox"
                }
            } else {
                currentView = "setup"
            }
        }
        responseTimer.start()
    }

    function loadFolders() {
        if (!currentAccountId) return
        sendCommand({ action: "get_folders", account_id: currentAccountId })

        responseTimer.responseHandler = function(resp) {
            if (resp && resp.folders) {
                folders = resp.folders
            }
        }
        responseTimer.start()
    }

    function loadEmails() {
        if (!currentAccountId) return
        loading = true
        sendCommand({
            action: "get_emails",
            account_id: currentAccountId,
            folder: currentFolder,
            limit: 50,
            offset: 0
        })

        responseTimer.responseHandler = function(resp) {
            loading = false
            if (resp && resp.emails) {
                emails = resp.emails
            } else if (resp && resp.error) {
                errorMessage = resp.error
            }
        }
        responseTimer.start()
    }

    function loadEmail(msgId) {
        loading = true
        sendCommand({
            action: "get_email",
            account_id: currentAccountId,
            folder: currentFolder,
            msg_id: msgId
        })

        responseTimer.responseHandler = function(resp) {
            loading = false
            if (resp && resp.email) {
                currentEmail = resp.email
                currentView = "email"
                // Mark as read
                markEmailRead(msgId, true)
            } else if (resp && resp.error) {
                errorMessage = resp.error
            }
        }
        responseTimer.start()
    }

    function markEmailRead(msgId, read) {
        sendCommand({
            action: "mark_read",
            account_id: currentAccountId,
            folder: currentFolder,
            msg_id: msgId,
            read: read
        })
    }

    function deleteEmail(msgId) {
        sendCommand({
            action: "delete_email",
            account_id: currentAccountId,
            folder: currentFolder,
            msg_id: msgId
        })

        // Remove from local list
        var newEmails = []
        for (var i = 0; i < emails.length; i++) {
            if (emails[i].id !== msgId) {
                newEmails.push(emails[i])
            }
        }
        emails = newEmails
    }

    function sendEmail() {
        if (!composeTo.trim()) {
            errorMessage = "Please enter a recipient"
            return
        }

        loading = true
        var toList = composeTo.split(',').map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
        var ccList = composeCc.split(',').map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })

        sendCommand({
            action: "send_email",
            account_id: currentAccountId,
            to: toList,
            cc: ccList,
            bcc: [],
            subject: composeSubject,
            body: composeBody
        })

        responseTimer.responseHandler = function(resp) {
            loading = false
            if (resp && resp.success) {
                // Clear compose and go back
                composeTo = ""
                composeCc = ""
                composeSubject = ""
                composeBody = ""
                composeReplyTo = ""
                currentView = "inbox"
                Haptic.click()
            } else {
                errorMessage = resp ? (resp.error || "Failed to send email") : "Failed to send email"
            }
        }
        responseTimer.start()
    }

    function addAccount(data) {
        loading = true
        sendCommand({
            action: "add_account",
            account: data
        })

        responseTimer.responseHandler = function(resp) {
            loading = false
            if (resp && resp.success) {
                loadAccounts()
            } else {
                errorMessage = resp ? (resp.error || "Failed to add account") : "Failed to add account"
            }
        }
        responseTimer.start()
    }

    function removeAccount(accountId) {
        sendCommand({
            action: "remove_account",
            account_id: accountId
        })

        responseTimer.responseHandler = function(resp) {
            loadAccounts()
        }
        responseTimer.start()
    }

    function getFolderDisplayName(folderName) {
        var names = {
            "INBOX": "Inbox",
            "Sent": "Sent",
            "[Gmail]/Sent Mail": "Sent",
            "Drafts": "Drafts",
            "[Gmail]/Drafts": "Drafts",
            "Trash": "Trash",
            "[Gmail]/Trash": "Trash",
            "Spam": "Spam",
            "[Gmail]/Spam": "Spam",
            "Archive": "Archive",
            "[Gmail]/All Mail": "All Mail"
        }
        return names[folderName] || folderName
    }

    function getFolderIcon(folderName) {
        var icons = {
            "INBOX": "📥",
            "Sent": "📤",
            "[Gmail]/Sent Mail": "📤",
            "Drafts": "📝",
            "[Gmail]/Drafts": "📝",
            "Trash": "🗑",
            "[Gmail]/Trash": "🗑",
            "Spam": "⚠",
            "[Gmail]/Spam": "⚠",
            "Archive": "📦",
            "[Gmail]/All Mail": "📬"
        }
        return icons[folderName] || "📁"
    }

    Timer {
        id: responseTimer
        interval: 100
        repeat: true
        property int attempts: 0
        property var responseHandler: null
        property real lastMtime: 0

        onTriggered: {
            attempts++
            if (attempts > 100) { // 10 second timeout
                stop()
                loading = false
                return
            }

            var resp = readResponse()
            if (resp) {
                stop()
                if (responseHandler) {
                    responseHandler(resp)
                }
            }
        }

        function start() {
            attempts = 0
            running = true
        }
    }

    // ==================== Loading View ====================
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "loading"

        Column {
            anchors.centerIn: parent
            spacing: 24

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "✉"
                font.pixelSize: 80
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Loading..."
                color: "#888888"
                font.pixelSize: 20 * textScale
            }
        }
    }

    // ==================== Setup View (Add Account) ====================
    Rectangle {
        id: setupView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "setup"

        property string setupEmail: ""
        property string setupPassword: ""
        property string setupName: ""
        property string setupImapServer: ""
        property int setupImapPort: 993
        property string setupSmtpServer: ""
        property int setupSmtpPort: 587
        property bool showAdvanced: false

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            anchors.bottomMargin: 120
            contentHeight: setupColumn.height
            clip: true

            Column {
                id: setupColumn
                width: parent.width
                spacing: 16

                // Header
                Text {
                    text: "Add Email Account"
                    color: "#ffffff"
                    font.pixelSize: 28 * textScale
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: "Enter your email credentials to get started"
                    color: "#888888"
                    font.pixelSize: 14 * textScale
                    wrapMode: Text.Wrap
                }

                Item { height: 16; width: 1 }

                // Name field
                Text {
                    text: "Your Name"
                    color: "#888888"
                    font.pixelSize: 14 * textScale
                }

                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: "#1a1a2e"

                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 16
                        color: "#ffffff"
                        font.pixelSize: 16 * textScale
                        verticalAlignment: TextInput.AlignVCenter
                        text: setupView.setupName
                        onTextChanged: setupView.setupName = text

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "John Doe"
                            color: "#555555"
                            font.pixelSize: 16 * textScale
                            visible: !parent.text && !parent.focus
                        }
                    }
                }

                // Email field
                Text {
                    text: "Email Address"
                    color: "#888888"
                    font.pixelSize: 14 * textScale
                }

                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: "#1a1a2e"

                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 16
                        color: "#ffffff"
                        font.pixelSize: 16 * textScale
                        verticalAlignment: TextInput.AlignVCenter
                        inputMethodHints: Qt.ImhEmailCharactersOnly
                        text: setupView.setupEmail
                        onTextChanged: {
                            setupView.setupEmail = text
                            autoDetectServers(text)
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "you@example.com"
                            color: "#555555"
                            font.pixelSize: 16 * textScale
                            visible: !parent.text && !parent.focus
                        }
                    }
                }

                // Password field
                Text {
                    text: "Password"
                    color: "#888888"
                    font.pixelSize: 14 * textScale
                }

                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: "#1a1a2e"

                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 16
                        color: "#ffffff"
                        font.pixelSize: 16 * textScale
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        text: setupView.setupPassword
                        onTextChanged: setupView.setupPassword = text

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Password or App Password"
                            color: "#555555"
                            font.pixelSize: 16 * textScale
                            visible: !parent.text && !parent.focus
                        }
                    }
                }

                // Advanced settings toggle
                Rectangle {
                    width: parent.width
                    height: 48
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        spacing: 8

                        Text {
                            text: "Advanced Settings"
                            color: "#e94560"
                            font.pixelSize: 14 * textScale
                        }

                        Text {
                            text: setupView.showAdvanced ? "▲" : "▼"
                            color: "#e94560"
                            font.pixelSize: 12
                        }

                        Item { Layout.fillWidth: true }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            setupView.showAdvanced = !setupView.showAdvanced
                            Haptic.tap()
                        }
                    }
                }

                // Advanced settings
                Column {
                    width: parent.width
                    spacing: 16
                    visible: setupView.showAdvanced

                    // IMAP Server
                    Text {
                        text: "IMAP Server"
                        color: "#888888"
                        font.pixelSize: 14 * textScale
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            height: 56
                            radius: 12
                            color: "#1a1a2e"

                            TextInput {
                                anchors.fill: parent
                                anchors.margins: 16
                                color: "#ffffff"
                                font.pixelSize: 16 * textScale
                                verticalAlignment: TextInput.AlignVCenter
                                text: setupView.setupImapServer
                                onTextChanged: setupView.setupImapServer = text

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "imap.example.com"
                                    color: "#555555"
                                    font.pixelSize: 16 * textScale
                                    visible: !parent.text && !parent.focus
                                }
                            }
                        }

                        Rectangle {
                            width: 80
                            height: 56
                            radius: 12
                            color: "#1a1a2e"

                            TextInput {
                                anchors.fill: parent
                                anchors.margins: 16
                                color: "#ffffff"
                                font.pixelSize: 16 * textScale
                                verticalAlignment: TextInput.AlignVCenter
                                horizontalAlignment: TextInput.AlignHCenter
                                inputMethodHints: Qt.ImhDigitsOnly
                                text: setupView.setupImapPort.toString()
                                onTextChanged: setupView.setupImapPort = parseInt(text) || 993
                            }
                        }
                    }

                    // SMTP Server
                    Text {
                        text: "SMTP Server"
                        color: "#888888"
                        font.pixelSize: 14 * textScale
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            height: 56
                            radius: 12
                            color: "#1a1a2e"

                            TextInput {
                                anchors.fill: parent
                                anchors.margins: 16
                                color: "#ffffff"
                                font.pixelSize: 16 * textScale
                                verticalAlignment: TextInput.AlignVCenter
                                text: setupView.setupSmtpServer
                                onTextChanged: setupView.setupSmtpServer = text

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "smtp.example.com"
                                    color: "#555555"
                                    font.pixelSize: 16 * textScale
                                    visible: !parent.text && !parent.focus
                                }
                            }
                        }

                        Rectangle {
                            width: 80
                            height: 56
                            radius: 12
                            color: "#1a1a2e"

                            TextInput {
                                anchors.fill: parent
                                anchors.margins: 16
                                color: "#ffffff"
                                font.pixelSize: 16 * textScale
                                verticalAlignment: TextInput.AlignVCenter
                                horizontalAlignment: TextInput.AlignHCenter
                                inputMethodHints: Qt.ImhDigitsOnly
                                text: setupView.setupSmtpPort.toString()
                                onTextChanged: setupView.setupSmtpPort = parseInt(text) || 587
                            }
                        }
                    }
                }

                Item { height: 24; width: 1 }

                // Error message
                Text {
                    width: parent.width
                    text: errorMessage
                    color: "#e94560"
                    font.pixelSize: 14 * textScale
                    wrapMode: Text.Wrap
                    visible: errorMessage.length > 0
                }

                // Add Account button
                Rectangle {
                    width: parent.width
                    height: 64
                    radius: 32
                    color: loading ? "#555555" : "#e94560"

                    Text {
                        anchors.centerIn: parent
                        text: loading ? "Connecting..." : "Add Account"
                        color: "#ffffff"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !loading
                        onClicked: {
                            if (!setupView.setupEmail || !setupView.setupPassword) {
                                errorMessage = "Please enter email and password"
                                return
                            }

                            errorMessage = ""
                            addAccount({
                                email: setupView.setupEmail,
                                name: setupView.setupName || setupView.setupEmail.split('@')[0],
                                username: setupView.setupEmail,
                                password: setupView.setupPassword,
                                imap_server: setupView.setupImapServer,
                                imap_port: setupView.setupImapPort,
                                smtp_server: setupView.setupSmtpServer,
                                smtp_port: setupView.setupSmtpPort,
                                use_ssl: true
                            })
                            Haptic.click()
                        }
                    }
                }

                // Provider hints
                Item { height: 16; width: 1 }

                Text {
                    width: parent.width
                    text: "For Gmail, use an App Password from your Google Account security settings."
                    color: "#666666"
                    font.pixelSize: 12 * textScale
                    wrapMode: Text.Wrap
                }
            }
        }

        function autoDetectServers(email) {
            var domain = email.split('@')[1] || ""
            domain = domain.toLowerCase()

            if (domain === "gmail.com") {
                setupImapServer = "imap.gmail.com"
                setupSmtpServer = "smtp.gmail.com"
                setupImapPort = 993
                setupSmtpPort = 587
            } else if (domain === "outlook.com" || domain === "hotmail.com" || domain === "live.com") {
                setupImapServer = "outlook.office365.com"
                setupSmtpServer = "smtp.office365.com"
                setupImapPort = 993
                setupSmtpPort = 587
            } else if (domain === "yahoo.com") {
                setupImapServer = "imap.mail.yahoo.com"
                setupSmtpServer = "smtp.mail.yahoo.com"
                setupImapPort = 993
                setupSmtpPort = 587
            } else if (domain === "icloud.com" || domain === "me.com" || domain === "mac.com") {
                setupImapServer = "imap.mail.me.com"
                setupSmtpServer = "smtp.mail.me.com"
                setupImapPort = 993
                setupSmtpPort = 587
            } else if (domain) {
                setupImapServer = "imap." + domain
                setupSmtpServer = "smtp." + domain
            }
        }

        // Back button (only if we have accounts)
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 72
            height: 72
            radius: 36
            color: "#2a2a3e"
            visible: accounts.length > 0

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 32
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    currentView = "inbox"
                    Haptic.tap()
                }
            }
        }
    }

    // ==================== Inbox View ====================
    Rectangle {
        id: inboxView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "inbox"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Folder button
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: folderBtnMouse.pressed ? "#3a3a4e" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "☰"
                            color: "#ffffff"
                            font.pixelSize: 24
                        }

                        MouseArea {
                            id: folderBtnMouse
                            anchors.fill: parent
                            onClicked: {
                                currentView = "folders"
                                Haptic.tap()
                            }
                        }
                    }

                    Column {
                        Layout.fillWidth: true

                        Text {
                            text: getFolderDisplayName(currentFolder)
                            color: "#ffffff"
                            font.pixelSize: 22 * textScale
                            font.weight: Font.Bold
                        }

                        Text {
                            text: accounts.length > 0 ? accounts.find(function(a) { return a.id === currentAccountId })?.email || "" : ""
                            color: "#888888"
                            font.pixelSize: 12 * textScale
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    // Compose button
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: "#e94560"

                        Text {
                            anchors.centerIn: parent
                            text: "✏"
                            color: "#ffffff"
                            font.pixelSize: 22
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                composeTo = ""
                                composeCc = ""
                                composeSubject = ""
                                composeBody = ""
                                composeReplyTo = ""
                                currentView = "compose"
                                Haptic.tap()
                            }
                        }
                    }
                }
            }

            // Loading indicator
            Rectangle {
                width: parent.width
                height: 4
                color: loading ? "#e94560" : "transparent"

                Rectangle {
                    width: loading ? parent.width * 0.3 : 0
                    height: parent.height
                    color: "#e94560"
                    x: loadingAnim.running ? (parent.width - width) * loadingAnim.progress : 0

                    NumberAnimation on x {
                        id: loadingAnim
                        property real progress: 0
                        running: loading
                        loops: Animation.Infinite
                        from: 0
                        to: 1
                        duration: 1000
                    }
                }
            }

            // Email list
            ListView {
                id: emailListView
                width: parent.width
                height: parent.height - 180
                model: emails
                clip: true
                spacing: 2

                delegate: Rectangle {
                    id: emailDelegate
                    width: emailListView.width
                    height: 88
                    color: !modelData.read ? "#1a1a2e" : "#0f0f1a"

                    property real swipeX: 0

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: emailDelegate.swipeX
                        color: parent.color

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            // Unread indicator
                            Rectangle {
                                width: 12
                                height: 12
                                radius: 6
                                color: modelData.read ? "transparent" : "#e94560"
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    width: parent.width
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.from_name || modelData.from_email
                                        color: modelData.read ? "#aaaaaa" : "#ffffff"
                                        font.pixelSize: 16 * textScale
                                        font.weight: modelData.read ? Font.Normal : Font.Bold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: formatDate(modelData.date)
                                        color: "#888888"
                                        font.pixelSize: 12 * textScale
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.subject || "(No Subject)"
                                    color: modelData.read ? "#888888" : "#cccccc"
                                    font.pixelSize: 14 * textScale
                                    elide: Text.ElideRight
                                }
                            }

                            // Flag indicator
                            Text {
                                text: modelData.flagged ? "⭐" : ""
                                font.pixelSize: 18
                                visible: modelData.flagged
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                loadEmail(modelData.id)
                                Haptic.tap()
                            }
                            onPressAndHold: {
                                // TODO: Show context menu
                                Haptic.click()
                            }
                        }
                    }

                    // Swipe delete background
                    Rectangle {
                        anchors.right: parent.right
                        width: -emailDelegate.swipeX
                        height: parent.height
                        color: "#e94560"
                        visible: emailDelegate.swipeX < 0

                        Text {
                            anchors.centerIn: parent
                            text: "🗑"
                            font.pixelSize: 28
                            visible: parent.width > 60
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    text: emails.length === 0 && !loading ? "No emails" : ""
                    color: "#666666"
                    font.pixelSize: 18 * textScale
                }

                // Pull to refresh
                onContentYChanged: {
                    if (contentY < -80 && !loading) {
                        loadEmails()
                        Haptic.click()
                    }
                }
            }
        }

        function formatDate(dateStr) {
            if (!dateStr) return ""
            // Just show time for today, date otherwise
            var parts = dateStr.split(' ')
            if (parts.length >= 2) {
                return parts[1] || parts[0]
            }
            return dateStr
        }

        // Home indicator
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 8
            width: 200
            height: 6
            radius: 3
            color: "#444466"
        }
    }

    // ==================== Email Detail View ====================
    Rectangle {
        id: emailView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "email"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Back button
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: backBtnMouse.pressed ? "#3a3a4e" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "←"
                            color: "#ffffff"
                            font.pixelSize: 24
                        }

                        MouseArea {
                            id: backBtnMouse
                            anchors.fill: parent
                            onClicked: {
                                currentView = "inbox"
                                Haptic.tap()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Reply button
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: replyBtnMouse.pressed ? "#3a3a4e" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "↩"
                            color: "#e94560"
                            font.pixelSize: 24
                        }

                        MouseArea {
                            id: replyBtnMouse
                            anchors.fill: parent
                            onClicked: {
                                if (currentEmail) {
                                    composeTo = currentEmail.from_email
                                    composeSubject = "Re: " + currentEmail.subject
                                    composeBody = "\n\n--- Original Message ---\n" + (currentEmail.plain_body || "")
                                    currentView = "compose"
                                    Haptic.tap()
                                }
                            }
                        }
                    }

                    // Delete button
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: deleteBtnMouse.pressed ? "#e94560" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "🗑"
                            font.pixelSize: 22
                        }

                        MouseArea {
                            id: deleteBtnMouse
                            anchors.fill: parent
                            onClicked: {
                                if (currentEmail) {
                                    deleteEmail(currentEmail.id)
                                    currentView = "inbox"
                                    Haptic.click()
                                }
                            }
                        }
                    }
                }
            }

            // Email content
            Flickable {
                width: parent.width
                height: parent.height - 120
                contentHeight: emailContent.height
                clip: true

                Column {
                    id: emailContent
                    width: parent.width
                    padding: 16
                    spacing: 16

                    // Subject
                    Text {
                        width: parent.width - 32
                        text: currentEmail ? currentEmail.subject : ""
                        color: "#ffffff"
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                    }

                    // From
                    Rectangle {
                        width: parent.width - 32
                        height: 56
                        color: "#1a1a2e"
                        radius: 8

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Rectangle {
                                width: 40
                                height: 40
                                radius: 20
                                color: "#e94560"

                                Text {
                                    anchors.centerIn: parent
                                    text: currentEmail ? (currentEmail.from_name || "?").charAt(0).toUpperCase() : ""
                                    color: "#ffffff"
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                }
                            }

                            Column {
                                Layout.fillWidth: true

                                Text {
                                    text: currentEmail ? currentEmail.from_name : ""
                                    color: "#ffffff"
                                    font.pixelSize: 14 * textScale
                                    font.weight: Font.Medium
                                }

                                Text {
                                    text: currentEmail ? currentEmail.from_email : ""
                                    color: "#888888"
                                    font.pixelSize: 12 * textScale
                                }
                            }
                        }
                    }

                    // Date
                    Text {
                        text: currentEmail ? currentEmail.date : ""
                        color: "#888888"
                        font.pixelSize: 12 * textScale
                    }

                    // To
                    Text {
                        width: parent.width - 32
                        text: "To: " + (currentEmail && currentEmail.to ? currentEmail.to.map(function(t) { return t.email }).join(", ") : "")
                        color: "#666666"
                        font.pixelSize: 12 * textScale
                        wrapMode: Text.Wrap
                    }

                    // CC
                    Text {
                        width: parent.width - 32
                        text: "Cc: " + (currentEmail && currentEmail.cc && currentEmail.cc.length > 0 ? currentEmail.cc.map(function(t) { return t.email }).join(", ") : "")
                        color: "#666666"
                        font.pixelSize: 12 * textScale
                        wrapMode: Text.Wrap
                        visible: currentEmail && currentEmail.cc && currentEmail.cc.length > 0
                    }

                    Rectangle {
                        width: parent.width - 32
                        height: 1
                        color: "#2a2a3e"
                    }

                    // Attachments
                    Column {
                        width: parent.width - 32
                        spacing: 8
                        visible: currentEmail && currentEmail.attachments && currentEmail.attachments.length > 0

                        Text {
                            text: "Attachments"
                            color: "#888888"
                            font.pixelSize: 12 * textScale
                            font.weight: Font.Medium
                        }

                        Repeater {
                            model: currentEmail ? currentEmail.attachments : []

                            Rectangle {
                                width: parent.width
                                height: 48
                                radius: 8
                                color: "#1a1a2e"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8

                                    Text {
                                        text: "📎"
                                        font.pixelSize: 18
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.filename
                                        color: "#ffffff"
                                        font.pixelSize: 14 * textScale
                                        elide: Text.ElideMiddle
                                    }

                                    Text {
                                        text: formatSize(modelData.size)
                                        color: "#888888"
                                        font.pixelSize: 12 * textScale
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: "#2a2a3e"
                        }
                    }

                    // Body
                    Text {
                        width: parent.width - 32
                        text: currentEmail ? (currentEmail.plain_body || "(No content)") : ""
                        color: "#cccccc"
                        font.pixelSize: 15 * textScale
                        wrapMode: Text.Wrap
                        lineHeight: 1.4
                    }
                }
            }
        }

        function formatSize(bytes) {
            if (bytes < 1024) return bytes + " B"
            if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + " KB"
            return (bytes / (1024 * 1024)).toFixed(1) + " MB"
        }
    }

    // ==================== Compose View ====================
    Rectangle {
        id: composeView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "compose"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Cancel button
                    Rectangle {
                        width: 80
                        height: 44
                        radius: 22
                        color: cancelMouse.pressed ? "#3a3a4e" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: "#888888"
                            font.pixelSize: 14 * textScale
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            onClicked: {
                                currentView = "inbox"
                                Haptic.tap()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "New Message"
                        color: "#ffffff"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Send button
                    Rectangle {
                        width: 80
                        height: 44
                        radius: 22
                        color: loading ? "#555555" : "#e94560"

                        Text {
                            anchors.centerIn: parent
                            text: loading ? "..." : "Send"
                            color: "#ffffff"
                            font.pixelSize: 14 * textScale
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !loading
                            onClicked: {
                                sendEmail()
                                Haptic.click()
                            }
                        }
                    }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 120
                contentHeight: composeContent.height
                clip: true

                Column {
                    id: composeContent
                    width: parent.width
                    spacing: 0

                    // To field
                    Rectangle {
                        width: parent.width
                        height: 56
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

                            Text {
                                text: "To:"
                                color: "#888888"
                                font.pixelSize: 14 * textScale
                                Layout.preferredWidth: 50
                            }

                            TextInput {
                                Layout.fillWidth: true
                                color: "#ffffff"
                                font.pixelSize: 16 * textScale
                                text: composeTo
                                onTextChanged: composeTo = text
                                inputMethodHints: Qt.ImhEmailCharactersOnly
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: "#2a2a3e"
                        }
                    }

                    // Cc field
                    Rectangle {
                        width: parent.width
                        height: 56
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

                            Text {
                                text: "Cc:"
                                color: "#888888"
                                font.pixelSize: 14 * textScale
                                Layout.preferredWidth: 50
                            }

                            TextInput {
                                Layout.fillWidth: true
                                color: "#ffffff"
                                font.pixelSize: 16 * textScale
                                text: composeCc
                                onTextChanged: composeCc = text
                                inputMethodHints: Qt.ImhEmailCharactersOnly
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: "#2a2a3e"
                        }
                    }

                    // Subject field
                    Rectangle {
                        width: parent.width
                        height: 56
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

                            Text {
                                text: "Subject:"
                                color: "#888888"
                                font.pixelSize: 14 * textScale
                                Layout.preferredWidth: 70
                            }

                            TextInput {
                                Layout.fillWidth: true
                                color: "#ffffff"
                                font.pixelSize: 16 * textScale
                                text: composeSubject
                                onTextChanged: composeSubject = text
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: "#2a2a3e"
                        }
                    }

                    // Body
                    Rectangle {
                        width: parent.width
                        height: Math.max(400, root.height - 400)
                        color: "transparent"

                        TextEdit {
                            anchors.fill: parent
                            anchors.margins: 16
                            color: "#ffffff"
                            font.pixelSize: 16 * textScale
                            wrapMode: TextEdit.Wrap
                            text: composeBody
                            onTextChanged: composeBody = text

                            Text {
                                anchors.fill: parent
                                text: "Compose your message..."
                                color: "#555555"
                                font.pixelSize: 16 * textScale
                                visible: !parent.text && !parent.focus
                            }
                        }
                    }
                }
            }
        }
    }

    // ==================== Folders View ====================
    Rectangle {
        id: foldersView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "folders"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    Text {
                        Layout.fillWidth: true
                        text: "Folders"
                        color: "#ffffff"
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Bold
                    }

                    // Settings button
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: settingsBtnMouse.pressed ? "#3a3a4e" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "⚙"
                            color: "#888888"
                            font.pixelSize: 22
                        }

                        MouseArea {
                            id: settingsBtnMouse
                            anchors.fill: parent
                            onClicked: {
                                currentView = "settings"
                                Haptic.tap()
                            }
                        }
                    }
                }
            }

            // Account selector
            Rectangle {
                width: parent.width
                height: 72
                color: "#1a1a2e"
                visible: accounts.length > 1

                ListView {
                    anchors.fill: parent
                    anchors.margins: 8
                    orientation: ListView.Horizontal
                    model: accounts
                    spacing: 8

                    delegate: Rectangle {
                        width: 150
                        height: 56
                        radius: 28
                        color: modelData.id === currentAccountId ? "#e94560" : "#2a2a3e"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.email.split('@')[0]
                            color: "#ffffff"
                            font.pixelSize: 14 * textScale
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                currentAccountId = modelData.id
                                currentFolder = "INBOX"
                                loadFolders()
                                loadEmails()
                                currentView = "inbox"
                                Haptic.tap()
                            }
                        }
                    }
                }
            }

            // Folder list
            ListView {
                width: parent.width
                height: parent.height - 200
                model: folders
                clip: true
                spacing: 2

                delegate: Rectangle {
                    width: parent.width
                    height: 64
                    color: modelData.name === currentFolder ? "#2a2a3e" : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        Text {
                            text: getFolderIcon(modelData.name)
                            font.pixelSize: 22
                        }

                        Text {
                            Layout.fillWidth: true
                            text: getFolderDisplayName(modelData.name)
                            color: modelData.name === currentFolder ? "#e94560" : "#ffffff"
                            font.pixelSize: 16 * textScale
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            currentFolder = modelData.name
                            loadEmails()
                            currentView = "inbox"
                            Haptic.tap()
                        }
                    }
                }
            }
        }

        // Back button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 72
            height: 72
            radius: 36
            color: "#e94560"

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 32
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    currentView = "inbox"
                    Haptic.tap()
                }
            }
        }
    }

    // ==================== Settings View ====================
    Rectangle {
        id: settingsView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "settings"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                Text {
                    anchors.centerIn: parent
                    text: "Settings"
                    color: "#ffffff"
                    font.pixelSize: 22 * textScale
                    font.weight: Font.Bold
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 180
                contentHeight: settingsContent.height
                clip: true

                Column {
                    id: settingsContent
                    width: parent.width
                    padding: 16
                    spacing: 16

                    // Accounts section
                    Text {
                        text: "ACCOUNTS"
                        color: "#888888"
                        font.pixelSize: 12 * textScale
                        font.weight: Font.Medium
                    }

                    Repeater {
                        model: accounts

                        Rectangle {
                            width: parent.width - 32
                            height: 72
                            radius: 12
                            color: "#1a1a2e"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 12

                                Rectangle {
                                    width: 44
                                    height: 44
                                    radius: 22
                                    color: "#e94560"

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                                        color: "#ffffff"
                                        font.pixelSize: 18
                                        font.weight: Font.Bold
                                    }
                                }

                                Column {
                                    Layout.fillWidth: true

                                    Text {
                                        text: modelData.name || modelData.email
                                        color: "#ffffff"
                                        font.pixelSize: 16 * textScale
                                    }

                                    Text {
                                        text: modelData.email
                                        color: "#888888"
                                        font.pixelSize: 12 * textScale
                                    }
                                }

                                Rectangle {
                                    width: 44
                                    height: 44
                                    radius: 22
                                    color: removeAccMouse.pressed ? "#e94560" : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: "#888888"
                                        font.pixelSize: 18
                                    }

                                    MouseArea {
                                        id: removeAccMouse
                                        anchors.fill: parent
                                        onClicked: {
                                            removeAccount(modelData.id)
                                            Haptic.click()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Add account button
                    Rectangle {
                        width: parent.width - 32
                        height: 56
                        radius: 28
                        color: "#2a2a3e"

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "+"
                                color: "#e94560"
                                font.pixelSize: 24
                            }

                            Text {
                                text: "Add Account"
                                color: "#e94560"
                                font.pixelSize: 16 * textScale
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                currentView = "setup"
                                Haptic.tap()
                            }
                        }
                    }

                    Item { height: 24; width: 1 }

                    // About section
                    Text {
                        text: "ABOUT"
                        color: "#888888"
                        font.pixelSize: 12 * textScale
                        font.weight: Font.Medium
                    }

                    Rectangle {
                        width: parent.width - 32
                        height: 80
                        radius: 12
                        color: "#1a1a2e"

                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Flick Email"
                                color: "#ffffff"
                                font.pixelSize: 18 * textScale
                                font.weight: Font.Bold
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Version 1.0"
                                color: "#888888"
                                font.pixelSize: 14 * textScale
                            }
                        }
                    }
                }
            }
        }

        // Back button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 72
            height: 72
            radius: 36
            color: "#e94560"

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 32
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    currentView = "folders"
                    Haptic.tap()
                }
            }
        }
    }

    // Home indicator
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 8
        width: 200
        height: 6
        radius: 3
        color: "#444466"
        z: 100
    }
}
