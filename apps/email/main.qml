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
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)

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
    readonly property string stateDir: Theme.stateDir + "/email"
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
        var configPath = Theme.stateDir + "/display_config.json"
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
                font.pixelSize: 22
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Loading..."
                color: "#888888"
                font.pixelSize: 20 * textScale
            }
        }
    }

    // ==================== Setup View (Add Account with App Password) ====================
    Rectangle {
        id: setupView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "setup"

        // Setup state
        property string setupStep: "provider"  // "provider", "instructions", "form"
        property string selectedProvider: ""
        property string setupEmail: ""
        property string setupPassword: ""
        property string setupName: ""
        property string setupImapServer: ""
        property int setupImapPort: 993
        property string setupSmtpServer: ""
        property int setupSmtpPort: 587
        property bool showAdvanced: false

        // Provider configurations
        readonly property var providers: ({
            "gmail": {
                "name": "Gmail",
                "color": "#4285f4",
                "icon": "G",
                "imap": "imap.gmail.com",
                "smtp": "smtp.gmail.com",
                "appPasswordUrl": "https://myaccount.google.com/apppasswords",
                "instructions": [
                    "1. Tap 'Get App Password' below",
                    "2. Sign in to your Google Account",
                    "3. You may need to enable 2-Step Verification first",
                    "4. Select 'Mail' and your device",
                    "5. Copy the 16-character password",
                    "6. Paste it in this app"
                ]
            },
            "outlook": {
                "name": "Outlook / Hotmail",
                "color": "#0078d4",
                "icon": "O",
                "imap": "outlook.office365.com",
                "smtp": "smtp.office365.com",
                "appPasswordUrl": "https://account.live.com/proofs/AppPassword",
                "instructions": [
                    "1. Tap 'Get App Password' below",
                    "2. Sign in to your Microsoft Account",
                    "3. Go to Security > Advanced security",
                    "4. Enable Two-step verification if needed",
                    "5. Create a new App password",
                    "6. Copy and paste it here"
                ]
            },
            "yahoo": {
                "name": "Yahoo Mail",
                "color": "#6001d2",
                "icon": "Y!",
                "imap": "imap.mail.yahoo.com",
                "smtp": "smtp.mail.yahoo.com",
                "appPasswordUrl": "https://login.yahoo.com/account/security/app-passwords",
                "instructions": [
                    "1. Tap 'Get App Password' below",
                    "2. Sign in to Yahoo",
                    "3. Generate a new app password",
                    "4. Select 'Other App' and name it 'Flick'",
                    "5. Copy the generated password",
                    "6. Paste it in this app"
                ]
            },
            "icloud": {
                "name": "iCloud Mail",
                "color": "#999999",
                "icon": "☁",
                "imap": "imap.mail.me.com",
                "smtp": "smtp.mail.me.com",
                "appPasswordUrl": "https://appleid.apple.com/account/manage",
                "instructions": [
                    "1. Tap 'Get App Password' below",
                    "2. Sign in to Apple ID",
                    "3. Go to Sign-In and Security",
                    "4. Select App-Specific Passwords",
                    "5. Generate a password for 'Flick Email'",
                    "6. Copy and paste it here"
                ]
            },
            "other": {
                "name": "Other (IMAP)",
                "color": "#888888",
                "icon": "@",
                "imap": "",
                "smtp": "",
                "appPasswordUrl": "",
                "instructions": [
                    "Enter your email server details manually.",
                    "You'll need your IMAP and SMTP server addresses.",
                    "Check your email provider's help pages for these settings."
                ]
            }
        })

        function selectProvider(provider) {
            selectedProvider = provider
            var config = providers[provider]
            setupImapServer = config.imap
            setupSmtpServer = config.smtp
            setupImapPort = 993
            setupSmtpPort = 587
            setupStep = provider === "other" ? "form" : "instructions"
        }

        function resetSetup() {
            setupStep = "provider"
            selectedProvider = ""
            setupEmail = ""
            setupPassword = ""
            setupName = ""
            showAdvanced = false
            errorMessage = ""
        }

        function submitAccount() {
            if (!setupEmail || !setupPassword) {
                errorMessage = "Please enter your email and app password"
                return
            }
            if (!setupImapServer || !setupSmtpServer) {
                errorMessage = "Please enter server addresses"
                return
            }

            errorMessage = ""
            loading = true

            addAccount({
                email: setupEmail,
                name: setupName || setupEmail.split('@')[0],
                username: setupEmail,
                password: setupPassword,
                imap_server: setupImapServer,
                imap_port: setupImapPort,
                smtp_server: setupSmtpServer,
                smtp_port: setupSmtpPort,
                use_ssl: true
            })
        }

        Flickable {
            anchors.fill: parent
            anchors.bottomMargin: 100
            contentHeight: setupContent.height + 32
            clip: true

            Column {
                id: setupContent
                width: parent.width
                padding: 16
                spacing: 20

                // ===== Step 1: Provider Selection =====
                Column {
                    width: parent.width - 48
                    spacing: 16
                    visible: setupView.setupStep === "provider"

                    Text {
                        text: "Add Email Account"
                        color: "#ffffff"
                        font.pixelSize: 20 * textScale
                        font.weight: Font.Bold
                    }

                    Text {
                        width: parent.width
                        text: "Select your email provider"
                        color: "#888888"
                        font.pixelSize: 16 * textScale
                        wrapMode: Text.Wrap
                    }

                    Item { height: 8; width: 1 }

                    // Provider buttons
                    Repeater {
                        model: ["gmail", "outlook", "yahoo", "icloud", "other"]

                        Rectangle {
                            width: parent.width
                            height: 44
                            radius: 16
                            color: providerMouse.pressed ? "#2a2a4e" : "#1a1a2e"
                            border.width: 2
                            border.color: setupView.providers[modelData].color

                            Row {
                                anchors.centerIn: parent
                                spacing: 16

                                Rectangle {
                                    width: 40
                                    height: 40
                                    radius: 20
                                    color: setupView.providers[modelData].color + "33"

                                    Text {
                                        anchors.centerIn: parent
                                        text: setupView.providers[modelData].icon
                                        font.pixelSize: modelData === "icloud" ? 24 : 18
                                        font.weight: Font.Bold
                                        color: setupView.providers[modelData].color
                                    }
                                }

                                Text {
                                    text: setupView.providers[modelData].name
                                    color: "#ffffff"
                                    font.pixelSize: 18 * textScale
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: providerMouse
                                anchors.fill: parent
                                onClicked: {
                                    Haptic.click()
                                    setupView.selectProvider(modelData)
                                }
                            }
                        }
                    }
                }

                // ===== Step 2: Instructions =====
                Column {
                    width: parent.width - 48
                    spacing: 16
                    visible: setupView.setupStep === "instructions"

                    // Back button
                    Rectangle {
                        width: 54
                        height: 40
                        radius: 20
                        color: "transparent"

                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            Text { text: "←"; color: "#888888"; font.pixelSize: 20 }
                            Text { text: "Back"; color: "#888888"; font.pixelSize: 14 * textScale }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: { Haptic.tap(); setupView.resetSetup() }
                        }
                    }

                    // Provider header
                    Row {
                        spacing: 16

                        Rectangle {
                            width: 56
                            height: 56
                            radius: 28
                            color: setupView.providers[setupView.selectedProvider] ?
                                   setupView.providers[setupView.selectedProvider].color + "33" : "#333"

                            Text {
                                anchors.centerIn: parent
                                text: setupView.providers[setupView.selectedProvider] ?
                                      setupView.providers[setupView.selectedProvider].icon : "?"
                                font.pixelSize: 24
                                font.weight: Font.Bold
                                color: setupView.providers[setupView.selectedProvider] ?
                                       setupView.providers[setupView.selectedProvider].color : "#888"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: setupView.providers[setupView.selectedProvider] ?
                                      setupView.providers[setupView.selectedProvider].name : ""
                                color: "#ffffff"
                                font.pixelSize: 22 * textScale
                                font.weight: Font.Bold
                            }
                            Text {
                                text: "App Password Required"
                                color: accentColor
                                font.pixelSize: 14 * textScale
                            }
                        }
                    }

                    Item { height: 8; width: 1 }

                    // Instructions box
                    Rectangle {
                        width: parent.width
                        height: instructionsCol.height + 32
                        radius: 16
                        color: "#1a1a2e"

                        Column {
                            id: instructionsCol
                            width: parent.width - 32
                            x: 16
                            y: 16
                            spacing: 12

                            Text {
                                text: "How to get your App Password:"
                                color: "#ffffff"
                                font.pixelSize: 16 * textScale
                                font.weight: Font.Bold
                            }

                            Repeater {
                                model: setupView.providers[setupView.selectedProvider] ?
                                       setupView.providers[setupView.selectedProvider].instructions : []

                                Text {
                                    width: parent.width
                                    text: modelData
                                    color: "#cccccc"
                                    font.pixelSize: 14 * textScale
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.3
                                }
                            }
                        }
                    }

                    Item { height: 8; width: 1 }

                    // Open browser button
                    Rectangle {
                        width: parent.width
                        height: 44
                        radius: 32
                        color: setupView.providers[setupView.selectedProvider] ?
                               setupView.providers[setupView.selectedProvider].color : accentColor

                        Row {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                text: "↗"
                                color: "#ffffff"
                                font.pixelSize: 24
                            }

                            Text {
                                text: "Get App Password"
                                color: "#ffffff"
                                font.pixelSize: 18 * textScale
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Haptic.click()
                                var url = setupView.providers[setupView.selectedProvider].appPasswordUrl
                                if (url) {
                                    // Launch Flick browser via backend
                                    console.log("Opening browser: " + url)
                                    sendCommand({ action: "open_url", url: url })
                                }
                            }
                        }
                    }

                    // Continue button
                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 28
                        color: "transparent"
                        border.width: 2
                        border.color: "#444466"

                        Text {
                            anchors.centerIn: parent
                            text: "I have my App Password →"
                            color: "#ffffff"
                            font.pixelSize: 16 * textScale
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Haptic.click()
                                setupView.setupStep = "form"
                            }
                        }
                    }
                }

                // ===== Step 3: Account Form =====
                Column {
                    width: parent.width - 48
                    spacing: 16
                    visible: setupView.setupStep === "form"

                    // Back button
                    Rectangle {
                        width: 54
                        height: 40
                        radius: 20
                        color: "transparent"

                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            Text { text: "←"; color: "#888888"; font.pixelSize: 20 }
                            Text { text: "Back"; color: "#888888"; font.pixelSize: 14 * textScale }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                if (setupView.selectedProvider === "other") {
                                    setupView.resetSetup()
                                } else {
                                    setupView.setupStep = "instructions"
                                }
                            }
                        }
                    }

                    Text {
                        text: "Enter Account Details"
                        color: "#ffffff"
                        font.pixelSize: 24 * textScale
                        font.weight: Font.Bold
                    }

                    // Email field
                    Text { text: "Email Address"; color: "#888888"; font.pixelSize: 14 * textScale }
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
                            onTextChanged: setupView.setupEmail = text

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

                    // App Password field
                    Text { text: "App Password"; color: "#888888"; font.pixelSize: 14 * textScale }
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
                                text: "Paste your app password here"
                                color: "#555555"
                                font.pixelSize: 16 * textScale
                                visible: !parent.text && !parent.focus
                            }
                        }
                    }

                    // Display Name field
                    Text { text: "Your Name (optional)"; color: "#888888"; font.pixelSize: 14 * textScale }
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

                    // Advanced settings toggle (for "other" or manual config)
                    Rectangle {
                        width: parent.width
                        height: 48
                        color: "transparent"
                        visible: setupView.selectedProvider === "other" || setupView.showAdvanced

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                text: "Server Settings"
                                color: accentColor
                                font.pixelSize: 14 * textScale
                            }
                            Text {
                                text: setupView.showAdvanced ? "▲" : "▼"
                                color: accentColor
                                font.pixelSize: 12
                            }
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
                        spacing: 12
                        visible: setupView.showAdvanced || setupView.selectedProvider === "other"

                        Text { text: "IMAP Server"; color: "#888888"; font.pixelSize: 14 * textScale }
                        Row {
                            width: parent.width
                            spacing: 8
                            Rectangle {
                                width: parent.width - 88
                                height: 48
                                radius: 12
                                color: "#1a1a2e"
                                TextInput {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    color: "#ffffff"
                                    font.pixelSize: 14 * textScale
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: setupView.setupImapServer
                                    onTextChanged: setupView.setupImapServer = text
                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "imap.example.com"
                                        color: "#555555"
                                        font.pixelSize: 14 * textScale
                                        visible: !parent.text && !parent.focus
                                    }
                                }
                            }
                            Rectangle {
                                width: 54
                                height: 48
                                radius: 12
                                color: "#1a1a2e"
                                TextInput {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    color: "#ffffff"
                                    font.pixelSize: 14 * textScale
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    text: setupView.setupImapPort.toString()
                                    onTextChanged: setupView.setupImapPort = parseInt(text) || 993
                                }
                            }
                        }

                        Text { text: "SMTP Server"; color: "#888888"; font.pixelSize: 14 * textScale }
                        Row {
                            width: parent.width
                            spacing: 8
                            Rectangle {
                                width: parent.width - 88
                                height: 48
                                radius: 12
                                color: "#1a1a2e"
                                TextInput {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    color: "#ffffff"
                                    font.pixelSize: 14 * textScale
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: setupView.setupSmtpServer
                                    onTextChanged: setupView.setupSmtpServer = text
                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "smtp.example.com"
                                        color: "#555555"
                                        font.pixelSize: 14 * textScale
                                        visible: !parent.text && !parent.focus
                                    }
                                }
                            }
                            Rectangle {
                                width: 54
                                height: 48
                                radius: 12
                                color: "#1a1a2e"
                                TextInput {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    color: "#ffffff"
                                    font.pixelSize: 14 * textScale
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    text: setupView.setupSmtpPort.toString()
                                    onTextChanged: setupView.setupSmtpPort = parseInt(text) || 587
                                }
                            }
                        }
                    }

                    Item { height: 8; width: 1 }

                    // Error message
                    Text {
                        width: parent.width
                        text: errorMessage
                        color: accentColor
                        font.pixelSize: 14 * textScale
                        wrapMode: Text.Wrap
                        visible: errorMessage.length > 0
                    }

                    // Add Account button
                    Rectangle {
                        width: parent.width
                        height: 44
                        radius: 32
                        color: loading ? "#555555" : accentColor

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
                                Haptic.click()
                                setupView.submitAccount()
                            }
                        }
                    }
                }
            }
        }

        // Back button (only if we have accounts)
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 48
            height: 48
            radius: 36
            color: "#2a2a3e"
            visible: accounts.length > 0

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 22
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
                height: 54
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
                            text: {
                                if (accounts.length === 0) return ""
                                var acc = accounts.find(function(a) { return a.id === currentAccountId })
                                return acc ? acc.email : ""
                            }
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
                        color: accentColor

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
                color: loading ? accentColor : "transparent"

                Rectangle {
                    width: loading ? parent.width * 0.3 : 0
                    height: parent.height
                    color: accentColor
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
                                color: modelData.read ? "transparent" : accentColor
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
                        color: accentColor
                        visible: emailDelegate.swipeX < 0

                        Text {
                            anchors.centerIn: parent
                            text: "🗑"
                            font.pixelSize: 20
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
                height: 54
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
                            color: accentColor
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
                        color: deleteBtnMouse.pressed ? accentColor : "transparent"

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
                                color: accentColor

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
                height: 54
                color: "#1a1a2e"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Cancel button
                    Rectangle {
                        width: 54
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
                        width: 54
                        height: 44
                        radius: 22
                        color: loading ? "#555555" : accentColor

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
                height: 54
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
                height: 48
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
                        color: modelData.id === currentAccountId ? accentColor : "#2a2a3e"

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
                    height: 44
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
                            color: modelData.name === currentFolder ? accentColor : "#ffffff"
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
            width: 48
            height: 48
            radius: 36
            color: accentColor

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 22
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
                height: 54
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
                            height: 48
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
                                    color: accentColor

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
                                    color: removeAccMouse.pressed ? accentColor : "transparent"

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
                                color: accentColor
                                font.pixelSize: 24
                            }

                            Text {
                                text: "Add Account"
                                color: accentColor
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
                        height: 54
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
            width: 48
            height: 48
            radius: 36
            color: accentColor

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 22
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
