import "../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: iconManagerPage

    property string stateDir: Theme.stateDir.replace("/flick", "/flick-phosh")
    property var curatedApps: []
    property var allApps: []

    Component.onCompleted: {
        loadCuratedApps()
        scanSystemApps()
    }

    function loadCuratedApps() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + stateDir + "/curated_other_apps.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                curatedApps = JSON.parse(xhr.responseText)
            }
        } catch (e) {
            curatedApps = []
        }
        updateModel()
    }

    function saveCuratedApps() {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + stateDir + "/curated_other_apps.json", false)
        try {
            xhr.send(JSON.stringify(curatedApps, null, 2))
        } catch (e) {
            console.error("Failed to save:", e)
        }
    }

    function scanSystemApps() {
        // Common useful apps to show
        var knownApps = [
            {id: "furios-camera", name: "Camera", icon: "camera"},
            {id: "org.gnome.Usage", name: "Usage", icon: "utilities-system-monitor"},
            {id: "org.gnome.clocks", name: "Clocks", icon: "clock"},
            {id: "org.gnome.Calls", name: "Calls", icon: "phone"},
            {id: "sm.puri.Chatty", name: "Chats", icon: "chat"},
            {id: "org.gnome.Contacts", name: "Contacts", icon: "contacts"},
            {id: "org.gnome.Geary", name: "Geary", icon: "mail"},
            {id: "org.gnome.Console", name: "Console", icon: "terminal"},
            {id: "firefox", name: "Firefox", icon: "firefox"},
            {id: "Andromeda", name: "Andromeda", icon: "android"},
            {id: "android.org.fdroid.fdroid", name: "F-Droid", icon: "fdroid"},
            {id: "org.gnome.Nautilus", name: "Files", icon: "folder"},
            {id: "org.gnome.TextEditor", name: "Text Editor", icon: "text-editor"},
            {id: "org.gnome.Calculator", name: "Calculator", icon: "calculator"},
            {id: "org.gnome.Calendar", name: "Calendar", icon: "calendar"},
            {id: "org.gnome.Weather", name: "Weather", icon: "weather"},
            {id: "org.gnome.Maps", name: "Maps", icon: "map"},
            {id: "org.gnome.Music", name: "Music", icon: "music"},
            {id: "org.gnome.Photos", name: "Photos", icon: "photo"},
            {id: "org.gnome.Totem", name: "Videos", icon: "video"},
            {id: "org.sigxcpu.Livi", name: "Livi", icon: "video"},
            {id: "org.gnome.Cheese", name: "Cheese", icon: "camera"},
            {id: "com.github.geigi.cozy", name: "Cozy", icon: "audiobook"},
        ]
        allApps = knownApps
        updateModel()
    }

    function updateModel() {
        appsModel.clear()
        for (var i = 0; i < allApps.length; i++) {
            var app = allApps[i]
            var isCurated = curatedApps.indexOf(app.id) >= 0
            appsModel.append({
                appId: app.id,
                name: app.name,
                icon: app.icon,
                curated: isCurated
            })
        }
    }

    function toggleApp(appId) {
        var idx = curatedApps.indexOf(appId)
        if (idx >= 0) {
            curatedApps.splice(idx, 1)
        } else {
            curatedApps.push(appId)
        }
        saveCuratedApps()
        updateModel()
    }

    function moveApp(from, to) {
        if (from < 0 || to < 0 || from >= curatedApps.length || to >= curatedApps.length) return
        var app = curatedApps.splice(from, 1)[0]
        curatedApps.splice(to, 0, app)
        saveCuratedApps()
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
                text: "PHOSH ICONS"
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
            model: ["Curated", "All Apps"]

            Rectangle {
                width: 100
                height: 36
                radius: 18
                color: tabIndex === index ? Theme.accentColor : "#1a1a28"

                property int tabIndex: index

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: 13
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

            // Show curated or all based on tab
            Repeater {
                model: appsModel

                Rectangle {
                    width: contentCol.width
                    height: 64
                    radius: 16
                    color: model.curated ? "#1a2a1a" : "#14141e"
                    border.color: model.curated ? "#2a4a2a" : "#1a1a2e"
                    visible: tabs.currentTab === 1 || model.curated

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // Drag handle (for curated items)
                        Text {
                            text: "≡"
                            font.pixelSize: 20
                            color: "#444455"
                            visible: model.curated && tabs.currentTab === 0
                            Layout.preferredWidth: visible ? 24 : 0
                        }

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
                            color: model.curated ? "#4CAF50" : "#2a2a3e"

                            Rectangle {
                                x: model.curated ? parent.width - width - 3 : 3
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

            // Empty state for curated tab
            Text {
                visible: tabs.currentTab === 0 && curatedApps.length === 0
                text: "No apps curated.\nSwitch to 'All Apps' to add some."
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
                        Text { text: "ℹ️"; font.pixelSize: 14 }
                        Text { text: "How it works"; font.pixelSize: 13; color: "#888899" }
                    }

                    Text {
                        width: parent.width
                        text: "Curated apps appear in the 'Other Apps' folder on your home screen. Toggle apps on/off to show or hide them."
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
