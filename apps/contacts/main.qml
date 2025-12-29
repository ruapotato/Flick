import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Contacts"
    color: "#0a0a0f"

    property real textScale: 2.0
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property string contactsFile: "/home/droidian/.local/state/flick/contacts.json"
    property string currentView: "list"  // list, detail, edit, add, menu
    property int selectedContactIndex: -1
    property string searchText: ""
    property string exportPath: "/home/droidian/Documents/contacts.vcf"
    property string importPath: "/home/droidian/Documents/contacts.vcf"

    ListModel { id: contactsModel }

    Component.onCompleted: {
        loadConfig()
        loadContacts()
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///home/droidian/.local/state/flick/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale) textScale = config.text_scale
            }
        } catch (e) {}
    }

    function loadContacts() {
        contactsModel.clear()
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + contactsFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                for (var i = 0; i < data.contacts.length; i++) {
                    contactsModel.append(data.contacts[i])
                }
            }
        } catch (e) {
            console.log("No contacts file yet")
        }
        sortContacts()
    }

    function saveContacts() {
        var contacts = []
        for (var i = 0; i < contactsModel.count; i++) {
            var c = contactsModel.get(i)
            // Explicitly copy properties to avoid Qt model serialization issues
            contacts.push({
                name: c.name || "",
                phone: c.phone || "",
                email: c.email || "",
                initials: c.initials || ""
            })
        }
        var data = JSON.stringify({contacts: contacts}, null, 2)
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + contactsFile, false)
        try {
            xhr.send(data)
        } catch (e) {
            console.log("Error saving contacts: " + e)
        }
    }

    function sortContacts() {
        var contacts = []
        for (var i = 0; i < contactsModel.count; i++) {
            var c = contactsModel.get(i)
            // Skip invalid contacts (no name)
            if (!c.name || c.name.trim() === "") continue
            contacts.push({
                name: c.name || "",
                phone: c.phone || "",
                email: c.email || "",
                initials: c.initials || ""
            })
        }
        contacts.sort(function(a, b) {
            return a.name.localeCompare(b.name)
        })
        contactsModel.clear()
        for (var j = 0; j < contacts.length; j++) {
            contactsModel.append(contacts[j])
        }
    }

    function addContact(name, phone, email) {
        contactsModel.append({
            name: name,
            phone: phone,
            email: email,
            initials: getInitials(name)
        })
        sortContacts()
        saveContacts()
    }

    function updateContact(index, name, phone, email) {
        contactsModel.set(index, {
            name: name,
            phone: phone,
            email: email,
            initials: getInitials(name)
        })
        sortContacts()
        saveContacts()
    }

    function deleteContact(index) {
        contactsModel.remove(index)
        saveContacts()
    }

    function getInitials(name) {
        var parts = name.trim().split(" ")
        if (parts.length >= 2) {
            return (parts[0][0] + parts[parts.length-1][0]).toUpperCase()
        }
        return name.substring(0, 2).toUpperCase()
    }

    function getColor(name) {
        var colors = [accentColor, "#4a9eff", "#50c878", "#ff8c42", "#9b59b6", "#1abc9c"]
        var hash = 0
        for (var i = 0; i < name.length; i++) {
            hash = name.charCodeAt(i) + ((hash << 5) - hash)
        }
        return colors[Math.abs(hash) % colors.length]
    }

    function callContact(phone) {
        Haptic.click()
        console.log("CALL:" + phone)
    }

    function messageContact(phone) {
        Haptic.click()
        // Write hint file for messages app to open this conversation
        var hintPath = "/home/droidian/.local/state/flick/open_conversation.json"
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + hintPath, false)
        try {
            xhr.send(JSON.stringify({phone_number: phone}))
        } catch (e) {}
        // Launch messages app
        console.log("LAUNCH:/home/droidian/Flick/apps/messages/run_messages.sh")
    }

    function filteredContacts() {
        var result = []
        var search = searchText.toLowerCase()
        for (var i = 0; i < contactsModel.count; i++) {
            var c = contactsModel.get(i)
            if (search === "" || c.name.toLowerCase().indexOf(search) >= 0 ||
                c.phone.indexOf(search) >= 0) {
                result.push({index: i, contact: c})
            }
        }
        return result
    }

    function exportContacts() {
        var vcf = ""
        for (var i = 0; i < contactsModel.count; i++) {
            var c = contactsModel.get(i)
            vcf += "BEGIN:VCARD\n"
            vcf += "VERSION:3.0\n"
            vcf += "FN:" + c.name + "\n"
            // Split name into parts for N field
            var parts = c.name.trim().split(" ")
            if (parts.length >= 2) {
                vcf += "N:" + parts.slice(1).join(" ") + ";" + parts[0] + ";;;\n"
            } else {
                vcf += "N:" + c.name + ";;;;\n"
            }
            if (c.phone) vcf += "TEL;TYPE=CELL:" + c.phone + "\n"
            if (c.email) vcf += "EMAIL:" + c.email + "\n"
            vcf += "END:VCARD\n"
        }

        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + exportPath, false)
        try {
            xhr.send(vcf)
            console.log("Exported " + contactsModel.count + " contacts to " + exportPath)
            return true
        } catch (e) {
            console.log("Export error: " + e)
            return false
        }
    }

    function importContacts() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + importPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var vcf = xhr.responseText
                var imported = 0
                var cards = vcf.split("END:VCARD")

                for (var i = 0; i < cards.length; i++) {
                    var card = cards[i]
                    if (card.indexOf("BEGIN:VCARD") < 0) continue

                    var name = "", phone = "", email = ""
                    var lines = card.split("\n")

                    for (var j = 0; j < lines.length; j++) {
                        var line = lines[j].trim()
                        if (line.indexOf("FN:") === 0) {
                            name = line.substring(3)
                        } else if (line.indexOf("TEL") === 0) {
                            var colonIdx = line.indexOf(":")
                            if (colonIdx > 0) phone = line.substring(colonIdx + 1)
                        } else if (line.indexOf("EMAIL") === 0) {
                            var emailIdx = line.indexOf(":")
                            if (emailIdx > 0) email = line.substring(emailIdx + 1)
                        }
                    }

                    if (name) {
                        // Check for duplicates by name
                        var exists = false
                        for (var k = 0; k < contactsModel.count; k++) {
                            if (contactsModel.get(k).name === name) {
                                exists = true
                                break
                            }
                        }
                        if (!exists) {
                            contactsModel.append({
                                name: name,
                                phone: phone,
                                email: email,
                                initials: getInitials(name)
                            })
                            imported++
                        }
                    }
                }

                if (imported > 0) {
                    sortContacts()
                    saveContacts()
                }
                console.log("Imported " + imported + " contacts from " + importPath)
                return imported
            }
        } catch (e) {
            console.log("Import error: " + e)
        }
        return 0
    }

    // Main list view
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "list"

        // Header
        Rectangle {
            id: listHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 160
            color: "transparent"

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Contacts"
                    font.pixelSize: 48 * textScale
                    font.weight: Font.ExtraLight
                    font.letterSpacing: 6
                    color: "#ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: contactsModel.count + " CONTACTS"
                    font.pixelSize: 12 * textScale
                    font.weight: Font.Medium
                    font.letterSpacing: 3
                    color: "#555566"
                }
            }

            // Menu button
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 20
                anchors.topMargin: 60
                width: 56
                height: 56
                radius: 28
                color: menuMouse.pressed ? "#333344" : "#222233"

                Text {
                    anchors.centerIn: parent
                    text: "⋮"
                    font.pixelSize: 28
                    color: "#ffffff"
                }

                MouseArea {
                    id: menuMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        currentView = "menu"
                    }
                }
            }

            // Add button
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 20
                anchors.topMargin: 60
                width: 56
                height: 56
                radius: 28
                color: addMouse.pressed ? accentPressed : accentColor

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: 32
                    color: "#ffffff"
                }

                MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.click()
                        nameInput.text = ""
                        phoneInput.text = ""
                        emailInput.text = ""
                        selectedContactIndex = -1
                        currentView = "edit"
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.2; color: accentColor }
                    GradientStop { position: 0.8; color: accentColor }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                opacity: 0.3
            }
        }

        // Search bar
        Rectangle {
            id: searchBar
            anchors.top: listHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16
            height: 56
            radius: 28
            color: "#1a1a2e"

            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Text {
                    text: "🔍"
                    font.pixelSize: 20
                    anchors.verticalCenter: parent.verticalCenter
                }

                TextInput {
                    id: searchInput
                    width: parent.width - 50
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 18 * textScale
                    color: "#ffffff"
                    onTextChanged: searchText = text

                    Text {
                        anchors.fill: parent
                        text: "Search contacts..."
                        font.pixelSize: 18 * textScale
                        color: "#555566"
                        visible: parent.text === ""
                    }
                }
            }
        }

        ListView {
            id: contactsList
            anchors.top: searchBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            anchors.topMargin: 8
            anchors.bottomMargin: 100
            spacing: 8
            clip: true

            model: contactsModel

            delegate: Rectangle {
                width: contactsList.width
                height: visible ? 80 : 0
                radius: 12
                color: itemMouse.pressed ? "#1a1a2e" : "#15151f"
                visible: searchText === "" ||
                         model.name.toLowerCase().indexOf(searchText.toLowerCase()) >= 0 ||
                         model.phone.indexOf(searchText) >= 0

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 16

                    // Avatar
                    Rectangle {
                        width: 56
                        height: 56
                        radius: 28
                        color: getColor(model.name)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: model.initials || getInitials(model.name)
                            font.pixelSize: 20
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 160
                        spacing: 4

                        Text {
                            text: model.name
                            font.pixelSize: 18 * textScale
                            font.weight: Font.Medium
                            color: "#ffffff"
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: model.phone
                            font.pixelSize: 14 * textScale
                            color: "#888899"
                        }
                    }

                    // Call button
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: callMouse.pressed ? "#1a7a3a" : "#228B22"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: model.phone !== ""

                        Text {
                            anchors.centerIn: parent
                            text: "📞"
                            font.pixelSize: 20
                        }

                        MouseArea {
                            id: callMouse
                            anchors.fill: parent
                            onClicked: callContact(model.phone)
                        }
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    anchors.rightMargin: 60
                    onClicked: {
                        Haptic.tap()
                        selectedContactIndex = index
                        currentView = "detail"
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: "No contacts yet\n\nTap + to add a contact"
                font.pixelSize: 18
                color: "#555566"
                horizontalAlignment: Text.AlignHCenter
                visible: contactsModel.count === 0
            }
        }
    }

    // Contact detail view
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "detail" && selectedContactIndex >= 0

        property var contact: selectedContactIndex >= 0 && selectedContactIndex < contactsModel.count ?
                              contactsModel.get(selectedContactIndex) : null

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 32

            // Back button
            Rectangle {
                width: 56
                height: 56
                radius: 28
                color: backDetailMouse.pressed ? "#333344" : "#222233"

                Text {
                    anchors.centerIn: parent
                    text: "←"
                    font.pixelSize: 28
                    color: "#ffffff"
                }

                MouseArea {
                    id: backDetailMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        currentView = "list"
                    }
                }
            }

            // Avatar
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120
                radius: 60
                color: parent.parent.contact ? getColor(parent.parent.contact.name) : "#333344"

                Text {
                    anchors.centerIn: parent
                    text: parent.parent.parent.contact ? parent.parent.parent.contact.initials || getInitials(parent.parent.parent.contact.name) : ""
                    font.pixelSize: 48
                    font.weight: Font.Medium
                    color: "#ffffff"
                }
            }

            // Name
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.parent.contact ? parent.parent.contact.name : ""
                font.pixelSize: 32 * textScale
                font.weight: Font.Medium
                color: "#ffffff"
            }

            // Action buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 40

                Column {
                    spacing: 8

                    Rectangle {
                        width: 72
                        height: 72
                        radius: 36
                        color: callDetailMouse.pressed ? "#1a7a3a" : "#228B22"

                        Text {
                            anchors.centerIn: parent
                            text: "📞"
                            font.pixelSize: 28
                        }

                        MouseArea {
                            id: callDetailMouse
                            anchors.fill: parent
                            onClicked: if (selectedContactIndex >= 0) callContact(contactsModel.get(selectedContactIndex).phone)
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Call"
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }
                }

                Column {
                    spacing: 8

                    Rectangle {
                        width: 72
                        height: 72
                        radius: 36
                        color: msgDetailMouse.pressed ? "#3a7ac2" : "#4a9eff"

                        Text {
                            anchors.centerIn: parent
                            text: "💬"
                            font.pixelSize: 28
                        }

                        MouseArea {
                            id: msgDetailMouse
                            anchors.fill: parent
                            onClicked: if (selectedContactIndex >= 0) messageContact(contactsModel.get(selectedContactIndex).phone)
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Message"
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }
                }

                Column {
                    spacing: 8

                    Rectangle {
                        width: 72
                        height: 72
                        radius: 36
                        color: editDetailMouse.pressed ? "#333344" : "#222233"

                        Text {
                            anchors.centerIn: parent
                            text: "✏️"
                            font.pixelSize: 28
                        }

                        MouseArea {
                            id: editDetailMouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                if (selectedContactIndex >= 0) {
                                    var c = contactsModel.get(selectedContactIndex)
                                    nameInput.text = c.name
                                    phoneInput.text = c.phone
                                    emailInput.text = c.email || ""
                                    currentView = "edit"
                                }
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Edit"
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }
                }
            }

            // Contact info
            Rectangle {
                width: parent.width
                height: infoCol.height + 32
                radius: 16
                color: "#15151f"

                Column {
                    id: infoCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 16

                    Row {
                        spacing: 16
                        Text { text: "📱"; font.pixelSize: 24 }
                        Column {
                            Text {
                                text: "Phone"
                                font.pixelSize: 12 * textScale
                                color: "#888899"
                            }
                            Text {
                                text: selectedContactIndex >= 0 && selectedContactIndex < contactsModel.count ?
                                      contactsModel.get(selectedContactIndex).phone : ""
                                font.pixelSize: 18 * textScale
                                color: "#ffffff"
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: "#333344" }

                    Row {
                        spacing: 16
                        visible: selectedContactIndex >= 0 && selectedContactIndex < contactsModel.count &&
                                 contactsModel.get(selectedContactIndex).email
                        Text { text: "✉️"; font.pixelSize: 24 }
                        Column {
                            Text {
                                text: "Email"
                                font.pixelSize: 12 * textScale
                                color: "#888899"
                            }
                            Text {
                                text: selectedContactIndex >= 0 && selectedContactIndex < contactsModel.count ?
                                      (contactsModel.get(selectedContactIndex).email || "") : ""
                                font.pixelSize: 18 * textScale
                                color: "#ffffff"
                            }
                        }
                    }
                }
            }

            // Delete button
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 200
                height: 56
                radius: 28
                color: deleteMouse.pressed ? accentPressed : "#3a3a4e"

                Text {
                    anchors.centerIn: parent
                    text: "Delete Contact"
                    font.pixelSize: 16 * textScale
                    color: "#ff6666"
                }

                MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.heavy()
                        deleteContact(selectedContactIndex)
                        currentView = "list"
                    }
                }
            }
        }
    }

    // Edit/Add view
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "edit"

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 24

            // Header
            Row {
                width: parent.width
                spacing: 16

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: cancelMouse.pressed ? "#333344" : "#222233"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            currentView = selectedContactIndex >= 0 ? "detail" : "list"
                        }
                    }
                }

                Text {
                    text: selectedContactIndex >= 0 ? "Edit Contact" : "New Contact"
                    font.pixelSize: 24 * textScale
                    font.weight: Font.Medium
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item { width: parent.width - 300; height: 1 }

                Rectangle {
                    width: 80
                    height: 56
                    radius: 28
                    color: saveMouse.pressed ? "#1a7a3a" : "#228B22"

                    Text {
                        anchors.centerIn: parent
                        text: "Save"
                        font.pixelSize: 16 * textScale
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.click()
                            if (nameInput.text.trim() !== "") {
                                if (selectedContactIndex >= 0) {
                                    updateContact(selectedContactIndex, nameInput.text.trim(),
                                                  phoneInput.text.trim(), emailInput.text.trim())
                                } else {
                                    addContact(nameInput.text.trim(), phoneInput.text.trim(),
                                              emailInput.text.trim())
                                }
                                currentView = "list"
                            }
                        }
                    }
                }
            }

            // Form fields
            Column {
                width: parent.width
                spacing: 16

                Text {
                    text: "Name"
                    font.pixelSize: 14 * textScale
                    color: "#888899"
                }

                Rectangle {
                    width: parent.width
                    height: 60
                    radius: 12
                    color: "#1a1a2e"

                    TextInput {
                        id: nameInput
                        anchors.fill: parent
                        anchors.margins: 16
                        font.pixelSize: 20 * textScale
                        color: "#ffffff"
                        verticalAlignment: TextInput.AlignVCenter
                    }
                }

                Text {
                    text: "Phone"
                    font.pixelSize: 14 * textScale
                    color: "#888899"
                }

                Rectangle {
                    width: parent.width
                    height: 60
                    radius: 12
                    color: "#1a1a2e"

                    TextInput {
                        id: phoneInput
                        anchors.fill: parent
                        anchors.margins: 16
                        font.pixelSize: 20 * textScale
                        color: "#ffffff"
                        verticalAlignment: TextInput.AlignVCenter
                        inputMethodHints: Qt.ImhDialableCharactersOnly
                    }
                }

                Text {
                    text: "Email"
                    font.pixelSize: 14 * textScale
                    color: "#888899"
                }

                Rectangle {
                    width: parent.width
                    height: 60
                    radius: 12
                    color: "#1a1a2e"

                    TextInput {
                        id: emailInput
                        anchors.fill: parent
                        anchors.margins: 16
                        font.pixelSize: 20 * textScale
                        color: "#ffffff"
                        verticalAlignment: TextInput.AlignVCenter
                        inputMethodHints: Qt.ImhEmailCharactersOnly
                    }
                }
            }
        }
    }

    // Menu view
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "menu"

        property string statusMessage: ""

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 24

            // Header
            Row {
                width: parent.width
                spacing: 16

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: backMenuMouse.pressed ? "#333344" : "#222233"

                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        font.pixelSize: 28
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: backMenuMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            currentView = "list"
                        }
                    }
                }

                Text {
                    text: "Options"
                    font.pixelSize: 24 * textScale
                    font.weight: Font.Medium
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Import/Export buttons
            Column {
                width: parent.width
                spacing: 16

                // Import button
                Rectangle {
                    width: parent.width
                    height: 80
                    radius: 16
                    color: importMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 20

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 24
                            color: "#4a9eff"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "↓"
                                font.pixelSize: 24
                                color: "#ffffff"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: "Import Contacts"
                                font.pixelSize: 18 * textScale
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }

                            Text {
                                text: "From ~/Documents/contacts.vcf"
                                font.pixelSize: 12 * textScale
                                color: "#888899"
                            }
                        }
                    }

                    MouseArea {
                        id: importMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.click()
                            var count = importContacts()
                            if (count > 0) {
                                parent.parent.parent.statusMessage = "Imported " + count + " contacts"
                            } else {
                                parent.parent.parent.statusMessage = "No new contacts found"
                            }
                        }
                    }
                }

                // Export button
                Rectangle {
                    width: parent.width
                    height: 80
                    radius: 16
                    color: exportMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 20

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 24
                            color: "#50c878"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "↑"
                                font.pixelSize: 24
                                color: "#ffffff"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: "Export Contacts"
                                font.pixelSize: 18 * textScale
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }

                            Text {
                                text: "To ~/Documents/contacts.vcf"
                                font.pixelSize: 12 * textScale
                                color: "#888899"
                            }
                        }
                    }

                    MouseArea {
                        id: exportMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.click()
                            if (exportContacts()) {
                                parent.parent.parent.statusMessage = "Exported " + contactsModel.count + " contacts"
                            } else {
                                parent.parent.parent.statusMessage = "Export failed"
                            }
                        }
                    }
                }

                // Status message
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.parent.statusMessage
                    font.pixelSize: 16 * textScale
                    color: accentColor
                    visible: parent.parent.statusMessage !== ""
                }
            }

            // Info
            Text {
                width: parent.width
                text: "vCard (.vcf) format is compatible with most contact apps including Google Contacts, iOS Contacts, and Outlook."
                font.pixelSize: 14 * textScale
                color: "#666677"
                wrapMode: Text.WordWrap
            }
        }
    }

    // Back button (list view)
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 100
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? accentPressed : accentColor
        visible: currentView === "list"
        z: 10

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: { Haptic.tap(); Qt.quit() }
        }
    }

    // Home indicator
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 120
        height: 4
        radius: 2
        color: "#333344"
        visible: currentView === "list"
    }
}
