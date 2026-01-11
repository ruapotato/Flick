import "../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: iconManagerPage

    property string stateDir: Theme.stateDir.replace("/flick", "/flick-phosh")
    property string userAppsDir: Theme.homeDir + "/.local/share/applications"
    property string systemAppsDir: "/usr/share/applications"

    // Apps excluded from Other Apps folder (shown on main phosh grid)
    property var excludedApps: []

    // All discovered system apps
    property var allApps: []

    // Default excluded apps (core apps that stay on main screen)
    property var defaultExcluded: [
        "furios-camera",
        "org.gnome.Calls",
        "firefox",
        "sm.puri.Chatty"
    ]

    Component.onCompleted: {
        loadExcludedApps()
        scanAllApps()
    }

    function loadExcludedApps() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + stateDir + "/excluded_apps.json", false)
        try {
            xhr.send()
            if ((xhr.status === 200 || xhr.status === 0) && xhr.responseText && xhr.responseText.trim().length > 2) {
                excludedApps = JSON.parse(xhr.responseText)
            } else {
                // First run - use defaults (don't save yet, will save on first toggle)
                excludedApps = defaultExcluded.slice()
            }
        } catch (e) {
            // First run - use defaults
            excludedApps = defaultExcluded.slice()
        }
    }

    function saveExcludedApps() {
        // Output to console for shell script to capture and save
        console.log("SAVE_EXCLUDED:" + JSON.stringify(excludedApps))

        // Also update the curated_other_apps.json (inverse of excluded)
        updateOtherApps()
    }

    function updateOtherApps() {
        // Other Apps = all apps that are NOT excluded
        var otherApps = []
        for (var i = 0; i < allApps.length; i++) {
            var appId = allApps[i].id
            if (excludedApps.indexOf(appId) < 0) {
                otherApps.push(appId)
            }
        }

        // Output to console for shell script to capture and save
        console.log("SAVE_OTHER_APPS:" + JSON.stringify(otherApps))
    }

    function scanAllApps() {
        allApps = []

        // Load from pre-generated discovered_apps.json (created by scan-apps script)
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + stateDir + "/discovered_apps.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var discovered = JSON.parse(xhr.responseText)
                for (var i = 0; i < discovered.length; i++) {
                    var app = discovered[i]
                    // Skip Flick apps - they're managed separately
                    if (app.id.indexOf("flick-") !== 0) {
                        allApps.push({
                            id: app.id,
                            name: app.name,
                            icon: app.icon
                        })
                    }
                }
            }
        } catch (e) {
            console.log("Could not load discovered apps: " + e)
        }

        updateModel()
    }

    function updateModel() {
        appsModel.clear()
        for (var i = 0; i < allApps.length; i++) {
            var app = allApps[i]
            var isExcluded = excludedApps.indexOf(app.id) >= 0
            appsModel.append({
                appId: app.id,
                name: app.name,
                icon: app.icon,
                excluded: isExcluded  // true = stays on main screen, false = goes to Other Apps
            })
        }
    }

    function toggleApp(appId) {
        var idx = excludedApps.indexOf(appId)
        if (idx >= 0) {
            // Remove from excluded = goes to Other Apps folder
            excludedApps.splice(idx, 1)
        } else {
            // Add to excluded = stays on main screen
            excludedApps.push(appId)
        }
        saveExcludedApps()
        updateModel()
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Header
    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 140
        color: "transparent"

        Column {
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "App Manager"
                font.pixelSize: 32
                font.weight: Font.ExtraLight
                font.letterSpacing: 3
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "OTHER APPS FOLDER"
                font.pixelSize: 11
                font.letterSpacing: 3
                color: "#555566"
            }
        }
    }

    ListModel {
        id: appsModel
    }

    // Tabs
    Row {
        id: tabs
        anchors.top: header.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 16

        Repeater {
            model: ["Main Screen", "Other Apps"]

            Rectangle {
                width: 110
                height: 36
                radius: 18
                color: tabIndex === index ? Theme.accentColor : "#1a1a28"

                property int tabIndex: index

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: 12
                    color: tabIndex === tabsRow.currentTab ? "#ffffff" : "#888899"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: tabsRow.currentTab = index
                }
            }
        }

        property int currentTab: 0
    }

    property alias tabsRow: tabs

    // Content
    Flickable {
        anchors.top: tabs.bottom
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: contentCol.height
        clip: true

        Column {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            // Tab description
            Rectangle {
                width: contentCol.width
                height: descText.height + 24
                radius: 12
                color: "#14141e"
                border.color: "#1a1a2e"

                Text {
                    id: descText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    text: tabs.currentTab === 0
                        ? "Apps shown here stay on the main phosh grid. Toggle OFF to move them to the Other Apps folder."
                        : "Apps shown here appear in the Other Apps folder. Toggle ON to move them to the main screen."
                    font.pixelSize: 12
                    color: "#666677"
                    wrapMode: Text.WordWrap
                }
            }

            Item { height: 8 }

            // Show apps based on tab
            Repeater {
                model: appsModel

                Rectangle {
                    width: contentCol.width
                    height: 64
                    radius: 16
                    color: model.excluded ? "#1a2a1a" : "#14141e"
                    border.color: model.excluded ? "#2a4a2a" : "#1a1a2e"
                    // Tab 0 = Main Screen (excluded apps), Tab 1 = Other Apps (non-excluded)
                    visible: (tabs.currentTab === 0 && model.excluded) || (tabs.currentTab === 1 && !model.excluded)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // Icon placeholder
                        Rectangle {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            radius: 10
                            color: "#2a2a3e"

                            Text {
                                anchors.centerIn: parent
                                text: model.name.charAt(0)
                                font.pixelSize: 18
                                font.bold: true
                                color: "#888899"
                            }
                        }

                        // Name
                        Column {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: model.name
                                font.pixelSize: 15
                                color: "#ffffff"
                            }

                            Text {
                                text: model.appId
                                font.pixelSize: 11
                                color: "#555566"
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Toggle
                        Rectangle {
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 28
                            radius: 14
                            color: model.excluded ? "#4CAF50" : "#2a2a3e"

                            Rectangle {
                                x: model.excluded ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                radius: 11
                                color: "#ffffff"

                                Behavior on x { NumberAnimation { duration: 150 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: toggleApp(model.appId)
                            }
                        }
                    }
                }
            }

            // Empty state
            Text {
                visible: {
                    var count = 0
                    for (var i = 0; i < appsModel.count; i++) {
                        var item = appsModel.get(i)
                        if ((tabs.currentTab === 0 && item.excluded) || (tabs.currentTab === 1 && !item.excluded)) {
                            count++
                        }
                    }
                    return count === 0
                }
                text: tabs.currentTab === 0
                    ? "No apps on main screen.\nSwitch to 'Other Apps' and toggle some ON."
                    : "All apps are on main screen.\nToggle some OFF to move here."
                color: "#555566"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Item { height: 20 }

            // Info
            Rectangle {
                width: contentCol.width
                height: infoCol.height + 24
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"

                Column {
                    id: infoCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    Row {
                        spacing: 8
                        Text { text: "ℹ"; font.pixelSize: 14; color: "#4a9eff" }
                        Text { text: "How it works"; font.pixelSize: 13; color: "#888899" }
                    }

                    Text {
                        width: parent.width
                        text: "Toggle ON = App stays on main phosh screen\nToggle OFF = App goes to 'Other Apps' folder\n\nFlick apps are always on the main screen."
                        font.pixelSize: 12
                        color: "#666677"
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Item { height: 40 }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 44
        height: 44
        radius: 32
        color: backMouse.pressed ? Qt.darker(Theme.accentColor, 1.2) : Theme.accentColor

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 20
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }
}
