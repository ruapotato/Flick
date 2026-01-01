import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../shared" as Shared

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    color: "#0a0a0f"

    // Auto-lock when window loses focus
    onActiveChanged: {
        if (!active && isUnlocked) {
            console.log("Window lost focus - locking vault")
            lockVault()
        }
    }

    // State
    property string currentView: "loading"  // loading, vaults, unlock, entries, detail, edit, create, open_existing
    property var vaults: []
    property var entries: []
    property var currentEntry: null
    property string currentVaultPath: ""
    property string currentVaultName: ""
    property string masterPassword: ""
    property bool isUnlocked: false
    property string searchQuery: ""
    property bool isEditing: false
    property string errorMessage: ""
    property string currentGroup: "/"
    property var groupStack: []

    // Paths
    property string stateDir: ""
    property string cmdDir: "/tmp/flick_vault_cmds"

    Component.onCompleted: {
        // Read state dir from temp file
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick_vault_state_dir", false)
        try {
            xhr.send()
            stateDir = xhr.responseText.trim()
        } catch(e) {
            stateDir = "/home/droidian/.local/state/flick/passwordsafe"
        }
        loadVaultList()
    }

    // Load saved vault list
    function loadVaultList() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + stateDir + "/vaults.json?" + Date.now(), false)
        try {
            xhr.send()
            if (xhr.responseText) {
                var data = JSON.parse(xhr.responseText)
                vaults = data.map(function(path) {
                    return {
                        path: path,
                        name: path.split("/").pop().replace(".kdbx", ""),
                        exists: true  // Assume exists
                    }
                })
            }
        } catch(e) {
            vaults = []
        }

        // Check for last vault
        xhr.open("GET", "file://" + stateDir + "/last_vault.json?" + Date.now(), false)
        try {
            xhr.send()
            if (xhr.responseText) {
                var data = JSON.parse(xhr.responseText)
                if (data.path) {
                    currentVaultPath = data.path
                    currentVaultName = data.path.split("/").pop().replace(".kdbx", "")
                    currentView = "unlock"
                    return
                }
            }
        } catch(e) {}

        currentView = "vaults"
    }

    // Save vault list
    function saveVaultList() {
        var paths = vaults.map(function(v) { return v.path })
        runHelper("writefile", [stateDir + "/vaults.json", JSON.stringify(paths)], function(){})
    }

    // Save last vault
    function saveLastVault(path) {
        runHelper("writefile", [stateDir + "/last_vault.json", '{"path":"' + path + '"}'], function(){})
    }

    // Add vault to list
    function addVault(path) {
        for (var i = 0; i < vaults.length; i++) {
            if (vaults[i].path === path) return
        }
        var newVaults = vaults.slice()
        newVaults.push({
            path: path,
            name: path.split("/").pop().replace(".kdbx", ""),
            exists: true
        })
        vaults = newVaults
        saveVaultList()
    }

    // Remove vault from list
    function removeVault(path) {
        vaults = vaults.filter(function(v) { return v.path !== path })
        saveVaultList()
    }

    // Lock vault
    function lockVault() {
        isUnlocked = false
        masterPassword = ""
        entries = []
        currentEntry = null
        currentGroup = "/"
        groupStack = []
        currentView = "vaults"
        loadVaultList()
    }

    // Run helper command via VAULTCMD protocol
    function runHelper(action, args, callback) {
        var cmdId = Date.now() + "_" + Math.floor(Math.random() * 10000)
        var resultFile = cmdDir + "/result_" + cmdId

        // Build command string
        var cmdContent = action
        for (var i = 0; i < args.length; i++) {
            cmdContent += "|" + String(args[i])
        }

        console.log("VAULTCMD:" + cmdId + ":" + cmdContent)

        // Poll for result
        var poller = Qt.createQmlObject('
            import QtQuick 2.15
            Timer {
                property string resultFile: ""
                property var callback: null
                property int attempts: 0
                interval: 50
                repeat: true
                running: true

                onTriggered: {
                    attempts++
                    if (attempts > 200) {
                        running = false
                        if (callback) callback(false, "Timeout")
                        destroy()
                        return
                    }

                    var xhr = new XMLHttpRequest()
                    xhr.open("GET", "file://" + resultFile + "?" + Date.now(), false)
                    try {
                        xhr.send()
                        if (xhr.responseText && xhr.responseText.length > 0) {
                            running = false
                            var result = xhr.responseText.trim()
                            var success = result.indexOf("ERROR:") !== 0
                            if (callback) callback(success, result)
                            destroy()
                        }
                    } catch(e) {}
                }
            }
        ', root, "poller" + cmdId)

        poller.resultFile = resultFile
        poller.callback = callback
    }

    // Unlock vault
    function doUnlock() {
        if (unlockPassword.text.length === 0) return
        unlockBusy.running = true
        errorMessage = ""

        runHelper("unlock", [currentVaultPath, unlockPassword.text], function(success, result) {
            unlockBusy.running = false
            if (success) {
                masterPassword = unlockPassword.text
                unlockPassword.text = ""
                isUnlocked = true
                addVault(currentVaultPath)
                saveLastVault(currentVaultPath)
                currentGroup = "/"
                loadEntries()
                currentView = "entries"
            } else {
                errorMessage = result.replace("ERROR:", "")
            }
        })
    }

    // Generate random password
    function generatePassword(length) {
        if (!length) length = 20
        var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
        var password = ""
        for (var i = 0; i < length; i++) {
            password += chars.charAt(Math.floor(Math.random() * chars.length))
        }
        return password
    }

    // Header
    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 88
        color: "#1a1a2e"
        z: 10

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 88
            spacing: 12

            // Back button
            Rectangle {
                width: 64
                height: 64
                radius: 32
                color: backMouse.pressed ? "#444" : "#2a2a4e"
                visible: currentView !== "vaults" && currentView !== "loading"

                Text {
                    anchors.centerIn: parent
                    text: "<"
                    color: "white"
                    font.pixelSize: 32
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    onClicked: {
                        errorMessage = ""
                        if (currentView === "unlock" || currentView === "create" || currentView === "open_existing") {
                            currentView = "vaults"
                        } else if (currentView === "detail" || currentView === "edit") {
                            currentView = "entries"
                            currentEntry = null
                            isEditing = false
                        } else if (currentView === "entries") {
                            if (currentGroup !== "/" && groupStack.length > 0) {
                                currentGroup = groupStack.pop()
                                loadEntries()
                            } else if (currentGroup !== "/") {
                                currentGroup = "/"
                                loadEntries()
                            } else {
                                lockVault()
                            }
                        }
                    }
                }
            }

            // Title
            Text {
                Layout.fillWidth: true
                text: {
                    if (currentView === "loading") return "Password Safe"
                    if (currentView === "vaults") return "Password Safe"
                    if (currentView === "unlock") return "Unlock Vault"
                    if (currentView === "create") return "New Vault"
                    if (currentView === "open_existing") return "Open Vault"
                    if (currentView === "entries") {
                        if (currentGroup !== "/") return currentGroup.split("/").pop()
                        return currentVaultName || "Entries"
                    }
                    if (currentView === "detail") return currentEntry ? currentEntry.title : "Entry"
                    if (currentView === "edit") return isEditing ? "Edit Entry" : "New Entry"
                    return "Password Safe"
                }
                color: "white"
                font.pixelSize: 20
                font.bold: true
                elide: Text.ElideRight
            }

            // Lock button
            Rectangle {
                width: 64
                height: 64
                radius: 32
                color: lockMouse.pressed ? "#444" : "#2a2a4e"
                visible: isUnlocked && currentView === "entries"

                Text {
                    anchors.centerIn: parent
                    text: "\u{1F513}"
                    font.pixelSize: 30
                }

                MouseArea {
                    id: lockMouse
                    anchors.fill: parent
                    onClicked: lockVault()
                }
            }
        }

        // Add button
        Item {
            width: 80
            height: 88
            anchors.right: parent.right
            anchors.top: parent.top
            visible: currentView === "entries"

            Rectangle {
                width: 64
                height: 64
                radius: 32
                anchors.centerIn: parent
                color: addMouse.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: "white"
                    font.pixelSize: 32
                    font.bold: true
                }
            }

            MouseArea {
                id: addMouse
                anchors.fill: parent
                onClicked: {
                    currentEntry = null
                    isEditing = false
                    currentView = "edit"
                }
            }
        }
    }

    // Content area
    Item {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // Loading view
        Column {
            anchors.centerIn: parent
            spacing: 16
            visible: currentView === "loading"

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: currentView === "loading"
            }

            Text {
                text: "Loading..."
                color: "#888"
                font.pixelSize: 16
            }
        }

        // Vault list view
        ListView {
            id: vaultList
            anchors.fill: parent
            anchors.margins: 16
            visible: currentView === "vaults"
            spacing: 8
            clip: true
            model: vaults

            header: Column {
                width: parent.width
                spacing: 16

                Text {
                    text: "Your Vaults"
                    color: "#888"
                    font.pixelSize: 14
                }
            }

            delegate: Rectangle {
                width: vaultList.width
                height: 80
                radius: 12
                color: vaultMouse.pressed ? "#2a2a4e" : "#1a1a2e"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: "\u{1F512}"
                        font.pixelSize: 28
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: modelData.name
                            color: "white"
                            font.pixelSize: 18
                            font.bold: true
                        }
                        Text {
                            text: modelData.path
                            color: "#888"
                            font.pixelSize: 14
                            elide: Text.ElideMiddle
                            width: parent.width
                        }
                    }
                }

                MouseArea {
                    id: vaultMouse
                    anchors.fill: parent
                    onClicked: {
                        currentVaultPath = modelData.path
                        currentVaultName = modelData.name
                        currentView = "unlock"
                        errorMessage = ""
                    }
                    onPressAndHold: {
                        removeConfirm.vaultPath = modelData.path
                        removeConfirm.vaultName = modelData.name
                        removeConfirm.visible = true
                    }
                }
            }

            footer: Column {
                width: parent.width
                spacing: 12
                topPadding: 24

                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: createMouse.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "+ Create New Vault"
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                    }

                    MouseArea {
                        id: createMouse
                        anchors.fill: parent
                        onClicked: currentView = "create"
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: openMouse.pressed ? "#2a2a4e" : "#1a1a2e"
                    border.color: "#333"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Open Existing Vault"
                        color: "white"
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: openMouse
                        anchors.fill: parent
                        onClicked: currentView = "open_existing"
                    }
                }

                Text {
                    text: "Long press to remove a vault from list"
                    color: "#666"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }
            }
        }

        // Unlock view
        Column {
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 24
            visible: currentView === "unlock"

            Text {
                text: "\u{1F512}"
                font.pixelSize: 64
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Text {
                text: currentVaultName
                color: "white"
                font.pixelSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            TextField {
                id: unlockPassword
                width: parent.width
                height: 56
                placeholderText: "Enter password"
                echoMode: TextInput.Password
                color: "white"
                font.pixelSize: 18

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: unlockPassword.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }

                Keys.onReturnPressed: root.doUnlock()
            }

            Text {
                text: errorMessage
                color: "#f44336"
                font.pixelSize: 14
                visible: errorMessage.length > 0
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 12
                color: unlockBusy.running ? "#444" : (unlockBtn.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor)

                Text {
                    anchors.centerIn: parent
                    text: "Unlock"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    visible: !unlockBusy.running
                }

                BusyIndicator {
                    id: unlockBusy
                    anchors.centerIn: parent
                    running: false
                    width: 32
                    height: 32
                }

                MouseArea {
                    id: unlockBtn
                    anchors.fill: parent
                    enabled: !unlockBusy.running
                    onClicked: root.doUnlock()
                }
            }
        }

        // Create vault view
        Column {
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 24
            visible: currentView === "create"

            Text {
                text: "Create New Vault"
                color: "white"
                font.pixelSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            TextField {
                id: newVaultName
                width: parent.width
                height: 56
                placeholderText: "Vault name"
                color: "white"
                font.pixelSize: 18

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: newVaultName.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }
            }

            TextField {
                id: newVaultPassword
                width: parent.width
                height: 56
                placeholderText: "Password"
                echoMode: TextInput.Password
                color: "white"
                font.pixelSize: 18

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: newVaultPassword.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }
            }

            TextField {
                id: confirmPassword
                width: parent.width
                height: 56
                placeholderText: "Confirm password"
                echoMode: TextInput.Password
                color: "white"
                font.pixelSize: 18

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: confirmPassword.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }
            }

            Text {
                text: errorMessage
                color: "#f44336"
                font.pixelSize: 14
                visible: errorMessage.length > 0
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 12
                color: createBusy.running ? "#444" : (createBtn.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor)

                Text {
                    anchors.centerIn: parent
                    text: "Create Vault"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    visible: !createBusy.running
                }

                BusyIndicator {
                    id: createBusy
                    anchors.centerIn: parent
                    running: false
                    width: 32
                    height: 32
                }

                MouseArea {
                    id: createBtn
                    anchors.fill: parent
                    enabled: !createBusy.running
                    onClicked: {
                        if (newVaultName.text.length === 0) {
                            errorMessage = "Enter a vault name"
                            return
                        }
                        if (newVaultPassword.text.length < 4) {
                            errorMessage = "Password too short (min 4 chars)"
                            return
                        }
                        if (newVaultPassword.text !== confirmPassword.text) {
                            errorMessage = "Passwords don't match"
                            return
                        }

                        createBusy.running = true
                        errorMessage = ""
                        var vaultPath = "/home/droidian/Documents/" + newVaultName.text + ".kdbx"

                        runHelper("create", [vaultPath, newVaultPassword.text], function(success, result) {
                            createBusy.running = false
                            if (success) {
                                currentVaultPath = vaultPath
                                currentVaultName = newVaultName.text
                                masterPassword = newVaultPassword.text
                                isUnlocked = true
                                addVault(vaultPath)
                                saveLastVault(vaultPath)
                                entries = []
                                currentGroup = "/"
                                currentView = "entries"
                                newVaultName.text = ""
                                newVaultPassword.text = ""
                                confirmPassword.text = ""
                            } else {
                                errorMessage = result.replace("ERROR:", "")
                            }
                        })
                    }
                }
            }
        }

        // Open existing vault view
        Column {
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 24
            visible: currentView === "open_existing"

            Text {
                text: "Open Existing Vault"
                color: "white"
                font.pixelSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Text {
                text: "Enter the full path to a .kdbx file"
                color: "#888"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            TextField {
                id: existingVaultPath
                width: parent.width
                height: 56
                placeholderText: "/home/droidian/Documents/vault.kdbx"
                text: "/home/droidian/Documents/"
                color: "white"
                font.pixelSize: 16

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: existingVaultPath.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }
            }

            Text {
                text: errorMessage
                color: "#f44336"
                font.pixelSize: 14
                visible: errorMessage.length > 0
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 12
                color: openExistingBtn.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                Text {
                    anchors.centerIn: parent
                    text: "Open Vault"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }

                MouseArea {
                    id: openExistingBtn
                    anchors.fill: parent
                    onClicked: {
                        var path = existingVaultPath.text.trim()
                        if (path.length === 0) {
                            errorMessage = "Enter a vault path"
                            return
                        }
                        if (!path.endsWith(".kdbx")) {
                            errorMessage = "File must be a .kdbx file"
                            return
                        }
                        errorMessage = ""
                        currentVaultPath = path
                        currentVaultName = path.split("/").pop().replace(".kdbx", "")
                        currentView = "unlock"
                    }
                }
            }
        }

        // Entries list view
        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            visible: currentView === "entries"

            // Folder path indicator
            Rectangle {
                width: parent.width
                height: currentGroup !== "/" ? 44 : 0
                visible: currentGroup !== "/"
                color: "transparent"

                Row {
                    anchors.fill: parent
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{1F4C1} " + currentGroup
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                    }
                }
            }

            // Search field
            TextField {
                id: searchField
                width: parent.width
                height: 48
                placeholderText: "Search..."
                color: "white"
                font.pixelSize: 16

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 24
                    border.color: searchField.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 1
                }

                leftPadding: 20

                onTextChanged: {
                    if (text.length > 0) {
                        searchEntries(text)
                    } else {
                        loadEntries()
                    }
                }
            }

            // Entry count
            Text {
                text: entries.length + " entries"
                color: "#888"
                font.pixelSize: 12
            }

            // Entries list
            ListView {
                id: entriesList
                width: parent.width
                height: parent.height - 120 - (currentGroup !== "/" ? 56 : 0)
                spacing: 8
                clip: true
                model: entries

                delegate: Rectangle {
                    width: entriesList.width
                    height: 80
                    radius: 12
                    color: entryMouse.pressed ? "#2a2a4e" : "#1a1a2e"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Rectangle {
                            width: 52
                            height: 52
                            radius: 26
                            color: modelData.type === "group" ? "#ffa500" : Shared.Theme.accentColor

                            Text {
                                anchors.centerIn: parent
                                text: modelData.type === "group" ? "\u{1F4C1}" : (modelData.title ? modelData.title.charAt(0).toUpperCase() : "?")
                                color: "white"
                                font.pixelSize: modelData.type === "group" ? 24 : 22
                                font.bold: true
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: modelData.title || modelData.name || ""
                                color: "white"
                                font.pixelSize: 18
                                font.bold: true
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: modelData.type === "group" ? "Folder" : (modelData.username || "")
                                color: "#888"
                                font.pixelSize: 15
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Copy button (for entries only)
                        Rectangle {
                            width: 56
                            height: 56
                            radius: 28
                            color: copyMouse.pressed ? "#333" : "transparent"
                            visible: modelData.type !== "group"

                            Text {
                                anchors.centerIn: parent
                                text: "\u{1F4CB}"
                                font.pixelSize: 24
                            }

                            MouseArea {
                                id: copyMouse
                                anchors.fill: parent
                                onClicked: {
                                    runHelper("copy", [currentVaultPath, masterPassword, modelData.title, "password"], function(success) {
                                        if (success) copiedLabel.show()
                                    })
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        anchors.rightMargin: modelData.type !== "group" ? 68 : 0
                        onClicked: {
                            if (modelData.type === "group") {
                                groupStack.push(currentGroup)
                                currentGroup = currentGroup === "/" ? "/" + modelData.name : currentGroup + "/" + modelData.name
                                loadEntries()
                            } else {
                                showEntry(modelData.title)
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: entriesBusy.running ? "" : "No entries yet\nTap + to add one"
                    color: "#666"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    visible: entries.length === 0 && !entriesBusy.running
                }

                BusyIndicator {
                    id: entriesBusy
                    anchors.centerIn: parent
                    running: false
                }
            }
        }

        // Entry detail view
        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: detailColumn.height
            clip: true
            visible: currentView === "detail"

            Column {
                id: detailColumn
                width: parent.width
                spacing: 16

                // Title
                Text {
                    text: currentEntry ? currentEntry.title : ""
                    color: "white"
                    font.pixelSize: 24
                    font.bold: true
                    width: parent.width
                    wrapMode: Text.Wrap
                }

                // Username field
                Rectangle {
                    width: parent.width
                    height: currentEntry && currentEntry.username ? 72 : 0
                    radius: 12
                    color: "#1a1a2e"
                    visible: currentEntry && currentEntry.username

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Text { text: "Username"; color: "#888"; font.pixelSize: 12 }
                        Text {
                            text: currentEntry ? currentEntry.username : ""
                            color: "white"
                            font.pixelSize: 16
                            width: parent.width - 60
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 12
                        width: 56; height: 56; radius: 28
                        color: copyUserMouse.pressed ? "#333" : "transparent"

                        Text { anchors.centerIn: parent; text: "\u{1F4CB}"; font.pixelSize: 24 }

                        MouseArea {
                            id: copyUserMouse
                            anchors.fill: parent
                            onClicked: {
                                runHelper("copy", [currentVaultPath, masterPassword, currentEntry.title, "username"], function(success) {
                                    if (success) copiedLabel.show()
                                })
                            }
                        }
                    }
                }

                // Password field
                Rectangle {
                    width: parent.width
                    height: 72
                    radius: 12
                    color: "#1a1a2e"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Text { text: "Password"; color: "#888"; font.pixelSize: 12 }
                        Text {
                            id: passwordText
                            property bool revealed: false
                            text: revealed ? (currentEntry ? currentEntry.password : "") : "********"
                            color: "white"
                            font.pixelSize: 16
                            font.family: revealed ? "monospace" : ""
                            width: parent.width - 120
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 12
                        spacing: 4

                        Rectangle {
                            width: 48; height: 48; radius: 24
                            color: revealMouse.pressed ? "#333" : "transparent"

                            Text { anchors.centerIn: parent; text: passwordText.revealed ? "\u{1F648}" : "\u{1F441}"; font.pixelSize: 20 }

                            MouseArea {
                                id: revealMouse
                                anchors.fill: parent
                                onClicked: passwordText.revealed = !passwordText.revealed
                            }
                        }

                        Rectangle {
                            width: 48; height: 48; radius: 24
                            color: copyPassMouse.pressed ? "#333" : "transparent"

                            Text { anchors.centerIn: parent; text: "\u{1F4CB}"; font.pixelSize: 24 }

                            MouseArea {
                                id: copyPassMouse
                                anchors.fill: parent
                                onClicked: {
                                    runHelper("copy", [currentVaultPath, masterPassword, currentEntry.title, "password"], function(success) {
                                        if (success) copiedLabel.show()
                                    })
                                }
                            }
                        }
                    }
                }

                // URL field
                Rectangle {
                    width: parent.width
                    height: currentEntry && currentEntry.url ? 72 : 0
                    radius: 12
                    color: "#1a1a2e"
                    visible: currentEntry && currentEntry.url

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Text { text: "URL"; color: "#888"; font.pixelSize: 12 }
                        Text {
                            text: currentEntry ? currentEntry.url : ""
                            color: Shared.Theme.accentColor
                            font.pixelSize: 14
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }
                }

                // Notes field
                Rectangle {
                    width: parent.width
                    height: currentEntry && currentEntry.notes ? Math.max(80, notesText.contentHeight + 40) : 0
                    radius: 12
                    color: "#1a1a2e"
                    visible: currentEntry && currentEntry.notes

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Text { text: "Notes"; color: "#888"; font.pixelSize: 12 }
                        Text {
                            id: notesText
                            text: currentEntry ? currentEntry.notes : ""
                            color: "white"
                            font.pixelSize: 14
                            width: parent.width
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Action buttons
                Row {
                    width: parent.width
                    spacing: 12
                    topPadding: 24

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 56
                        radius: 12
                        color: editMouse.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                        Text {
                            anchors.centerIn: parent
                            text: "Edit"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        MouseArea {
                            id: editMouse
                            anchors.fill: parent
                            onClicked: {
                                isEditing = true
                                currentView = "edit"
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 56
                        radius: 12
                        color: deleteMouse.pressed ? "#c62828" : "#f44336"

                        Text {
                            anchors.centerIn: parent
                            text: "Delete"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        MouseArea {
                            id: deleteMouse
                            anchors.fill: parent
                            onClicked: deleteConfirm.visible = true
                        }
                    }
                }
            }
        }

        // Edit/Add entry view
        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: editColumn.height
            clip: true
            visible: currentView === "edit"

            Column {
                id: editColumn
                width: parent.width
                spacing: 16

                // Title
                Column {
                    width: parent.width
                    spacing: 4

                    Text { text: "Title"; color: "#888"; font.pixelSize: 12 }
                    TextField {
                        id: editTitle
                        width: parent.width
                        height: 56
                        text: isEditing && currentEntry ? currentEntry.title : ""
                        placeholderText: "Entry title"
                        color: "white"
                        font.pixelSize: 16

                        background: Rectangle {
                            color: "#1a1a2e"
                            radius: 12
                            border.color: editTitle.focus ? Shared.Theme.accentColor : "#333"
                            border.width: 1
                        }
                    }
                }

                // Username
                Column {
                    width: parent.width
                    spacing: 4

                    Text { text: "Username"; color: "#888"; font.pixelSize: 12 }
                    TextField {
                        id: editUsername
                        width: parent.width
                        height: 56
                        text: isEditing && currentEntry ? currentEntry.username : ""
                        placeholderText: "Username or email"
                        color: "white"
                        font.pixelSize: 16

                        background: Rectangle {
                            color: "#1a1a2e"
                            radius: 12
                            border.color: editUsername.focus ? Shared.Theme.accentColor : "#333"
                            border.width: 1
                        }
                    }
                }

                // Password
                Column {
                    width: parent.width
                    spacing: 4

                    Text { text: "Password"; color: "#888"; font.pixelSize: 12 }
                    RowLayout {
                        width: parent.width
                        spacing: 8

                        TextField {
                            id: editPassword
                            Layout.fillWidth: true
                            height: 56
                            text: isEditing && currentEntry ? currentEntry.password : ""
                            placeholderText: "Password"
                            echoMode: showEditPassword.checked ? TextInput.Normal : TextInput.Password
                            color: "white"
                            font.pixelSize: 16

                            background: Rectangle {
                                color: "#1a1a2e"
                                radius: 12
                                border.color: editPassword.focus ? Shared.Theme.accentColor : "#333"
                                border.width: 1
                            }
                        }

                        Rectangle {
                            width: 56; height: 56; radius: 12
                            color: showEditPassword.checked ? Shared.Theme.accentColor : "#1a1a2e"

                            Text { anchors.centerIn: parent; text: "\u{1F441}"; font.pixelSize: 20 }

                            MouseArea {
                                id: showEditPassword
                                property bool checked: false
                                anchors.fill: parent
                                onClicked: checked = !checked
                            }
                        }

                        Rectangle {
                            width: 56; height: 56; radius: 12
                            color: generateMouse.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                            Text { anchors.centerIn: parent; text: "\u{1F3B2}"; font.pixelSize: 20 }

                            MouseArea {
                                id: generateMouse
                                anchors.fill: parent
                                onClicked: {
                                    editPassword.text = generatePassword(20)
                                    showEditPassword.checked = true
                                }
                            }
                        }
                    }
                }

                // URL
                Column {
                    width: parent.width
                    spacing: 4

                    Text { text: "URL"; color: "#888"; font.pixelSize: 12 }
                    TextField {
                        id: editUrl
                        width: parent.width
                        height: 56
                        text: isEditing && currentEntry ? currentEntry.url : ""
                        placeholderText: "https://..."
                        color: "white"
                        font.pixelSize: 16
                        inputMethodHints: Qt.ImhUrlCharactersOnly

                        background: Rectangle {
                            color: "#1a1a2e"
                            radius: 12
                            border.color: editUrl.focus ? Shared.Theme.accentColor : "#333"
                            border.width: 1
                        }
                    }
                }

                // Notes
                Column {
                    width: parent.width
                    spacing: 4

                    Text { text: "Notes"; color: "#888"; font.pixelSize: 12 }
                    Rectangle {
                        width: parent.width
                        height: 120
                        color: "#1a1a2e"
                        radius: 12
                        border.color: editNotes.focus ? Shared.Theme.accentColor : "#333"
                        border.width: 1

                        TextArea {
                            id: editNotes
                            anchors.fill: parent
                            anchors.margins: 12
                            text: isEditing && currentEntry ? currentEntry.notes : ""
                            placeholderText: "Additional notes..."
                            color: "white"
                            font.pixelSize: 16
                            wrapMode: Text.Wrap
                            background: null
                        }
                    }
                }

                Text {
                    text: errorMessage
                    color: "#f44336"
                    font.pixelSize: 14
                    visible: errorMessage.length > 0
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: saveBusy.running ? "#444" : (saveMouse.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor)

                    Text {
                        anchors.centerIn: parent
                        text: "Save"
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                        visible: !saveBusy.running
                    }

                    BusyIndicator {
                        id: saveBusy
                        anchors.centerIn: parent
                        running: false
                        width: 32
                        height: 32
                    }

                    MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        enabled: !saveBusy.running
                        onClicked: {
                            if (editTitle.text.length === 0) {
                                errorMessage = "Title is required"
                                return
                            }
                            errorMessage = ""
                            saveBusy.running = true

                            var action = isEditing ? "edit" : "add"
                            var args = [currentVaultPath, masterPassword, editTitle.text, editUsername.text, editPassword.text, editUrl.text]

                            runHelper(action, args, function(success, result) {
                                saveBusy.running = false
                                if (success) {
                                    currentView = "entries"
                                    isEditing = false
                                    currentEntry = null
                                    loadEntries()
                                } else {
                                    errorMessage = result.replace("ERROR:", "")
                                }
                            })
                        }
                    }
                }

                Item { width: parent.width; height: 200 }
            }
        }
    }

    // Helper functions
    function loadEntries() {
        entriesBusy.running = true
        runHelper("list", [currentVaultPath, masterPassword, currentGroup], function(success, result) {
            entriesBusy.running = false
            if (success) {
                try {
                    entries = JSON.parse(result)
                } catch(e) {
                    entries = []
                }
            }
        })
    }

    function searchEntries(query) {
        entriesBusy.running = true
        runHelper("search", [currentVaultPath, masterPassword, query], function(success, result) {
            entriesBusy.running = false
            if (success) {
                try {
                    entries = JSON.parse(result)
                } catch(e) {}
            }
        })
    }

    function showEntry(title) {
        runHelper("show", [currentVaultPath, masterPassword, title], function(success, result) {
            if (success) {
                try {
                    currentEntry = JSON.parse(result)
                    currentView = "detail"
                } catch(e) {}
            }
        })
    }

    // Copied notification
    Rectangle {
        id: copiedLabel
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        anchors.horizontalCenter: parent.horizontalCenter
        width: 150
        height: 44
        radius: 22
        color: "#4caf50"
        opacity: 0
        visible: opacity > 0

        Text {
            anchors.centerIn: parent
            text: "Copied!"
            color: "white"
            font.pixelSize: 16
            font.bold: true
        }

        function show() {
            opacity = 1
            hideTimer.start()
        }

        Timer {
            id: hideTimer
            interval: 1500
            onTriggered: copiedLabel.opacity = 0
        }

        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Delete confirmation
    Rectangle {
        id: deleteConfirm
        anchors.fill: parent
        color: "#000000cc"
        visible: false

        MouseArea { anchors.fill: parent; onClicked: deleteConfirm.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 64
            height: 180
            radius: 16
            color: "#1a1a2e"

            Column {
                anchors.centerIn: parent
                spacing: 20

                Text {
                    text: "Delete this entry?"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                Row {
                    spacing: 12

                    Rectangle {
                        width: 120; height: 48; radius: 24
                        color: cancelDelMouse.pressed ? "#333" : "#2a2a4e"

                        Text { anchors.centerIn: parent; text: "Cancel"; color: "white"; font.pixelSize: 16 }
                        MouseArea { id: cancelDelMouse; anchors.fill: parent; onClicked: deleteConfirm.visible = false }
                    }

                    Rectangle {
                        width: 120; height: 48; radius: 24
                        color: confirmDelMouse.pressed ? "#c62828" : "#f44336"

                        Text { anchors.centerIn: parent; text: "Delete"; color: "white"; font.pixelSize: 16; font.bold: true }
                        MouseArea {
                            id: confirmDelMouse
                            anchors.fill: parent
                            onClicked: {
                                if (currentEntry) {
                                    runHelper("delete", [currentVaultPath, masterPassword, currentEntry.title], function(success) {
                                        if (success) {
                                            currentView = "entries"
                                            currentEntry = null
                                            loadEntries()
                                        }
                                    })
                                }
                                deleteConfirm.visible = false
                            }
                        }
                    }
                }
            }
        }
    }

    // Remove vault confirmation
    Rectangle {
        id: removeConfirm
        anchors.fill: parent
        color: "#000000cc"
        visible: false

        property string vaultPath: ""
        property string vaultName: ""

        MouseArea { anchors.fill: parent; onClicked: removeConfirm.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 64
            height: 200
            radius: 16
            color: "#1a1a2e"

            Column {
                anchors.centerIn: parent
                spacing: 16

                Text {
                    text: "Remove vault from list?"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                Text {
                    text: removeConfirm.vaultName + "\n(File will not be deleted)"
                    color: "#888"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                Row {
                    spacing: 12
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        width: 120; height: 48; radius: 24
                        color: cancelRemMouse.pressed ? "#333" : "#2a2a4e"

                        Text { anchors.centerIn: parent; text: "Cancel"; color: "white"; font.pixelSize: 16 }
                        MouseArea { id: cancelRemMouse; anchors.fill: parent; onClicked: removeConfirm.visible = false }
                    }

                    Rectangle {
                        width: 120; height: 48; radius: 24
                        color: confirmRemMouse.pressed ? "#c62828" : "#f44336"

                        Text { anchors.centerIn: parent; text: "Remove"; color: "white"; font.pixelSize: 16; font.bold: true }
                        MouseArea {
                            id: confirmRemMouse
                            anchors.fill: parent
                            onClicked: {
                                removeVault(removeConfirm.vaultPath)
                                removeConfirm.visible = false
                                loadVaultList()
                            }
                        }
                    }
                }
            }
        }
    }
}
