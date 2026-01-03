import "../../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: dateTimePage

    property string currentTime: "12:00"
    property string currentDate: "2024-12-21"
    property string currentDay: "Saturday"
    property string timezone: "UTC"
    property bool ntpEnabled: true

    // Location properties
    property string locationName: "Not set"
    property real latitude: 0
    property real longitude: 0
    property string weatherConfigFile: Theme.stateDir + "/weather_config.json"

    Component.onCompleted: {
        loadDateTimeInfo()
        loadLocationConfig()
        // Request timezone list to be generated
        console.warn("DATETIME_CMD:list-timezones")
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: loadDateTimeInfo()
    }

    function loadDateTimeInfo() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-datetime.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                currentTime = data.time || "00:00"
                currentDate = data.date || "2024-01-01"
                currentDay = data.day || "Monday"
                timezone = data.timezone || "UTC"
                ntpEnabled = data.ntp_enabled || false
            }
        } catch (e) {
            // Use JavaScript date as fallback
            var now = new Date()
            currentTime = now.toTimeString().substring(0, 5)
            currentDate = now.toISOString().substring(0, 10)
            currentDay = now.toLocaleDateString('en-US', { weekday: 'long' })
        }
    }

    function toggleNtp() {
        ntpEnabled = !ntpEnabled
        console.warn("DATETIME_CMD:ntp:" + (ntpEnabled ? "on" : "off"))
    }

    function loadLocationConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + weatherConfigFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.locationName) locationName = config.locationName
                if (config.latitude) latitude = config.latitude
                if (config.longitude) longitude = config.longitude
            }
        } catch (e) {
            // No config yet
        }
    }

    function saveLocationConfig() {
        var config = {
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        }
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + weatherConfigFile, false)
        try {
            xhr.send(JSON.stringify(config, null, 2))
        } catch (e) {}
    }

    function searchLocation(query) {
        if (query.length < 2) {
            locationSearchModel.clear()
            return
        }
        var url = "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(query) + "&count=5&language=en&format=json"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                locationSearchModel.clear()
                try {
                    var data = JSON.parse(xhr.responseText)
                    if (data.results) {
                        for (var i = 0; i < data.results.length; i++) {
                            var r = data.results[i]
                            locationSearchModel.append({
                                name: r.name,
                                country: r.country || "",
                                admin1: r.admin1 || "",
                                lat: r.latitude,
                                lon: r.longitude
                            })
                        }
                    }
                } catch (e) {}
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function selectLocation(name, country, admin1, lat, lon) {
        var displayName = name
        if (admin1) displayName += ", " + admin1
        if (country) displayName += ", " + country
        locationName = displayName
        latitude = lat
        longitude = lon
        saveLocationConfig()
        locationSearchModel.clear()
        locationSearchInput.text = ""
        locationSearchVisible = false
    }

    property bool locationSearchVisible: false
    property bool timezonePickerVisible: false
    property var filteredTimezones: []

    // Common timezones for quick access
    property var commonTimezones: [
        {name: "America/New_York", display: "New York (Eastern)"},
        {name: "America/Chicago", display: "Chicago (Central)"},
        {name: "America/Denver", display: "Denver (Mountain)"},
        {name: "America/Los_Angeles", display: "Los Angeles (Pacific)"},
        {name: "America/Anchorage", display: "Anchorage (Alaska)"},
        {name: "Pacific/Honolulu", display: "Honolulu (Hawaii)"},
        {name: "Europe/London", display: "London (GMT)"},
        {name: "Europe/Paris", display: "Paris (CET)"},
        {name: "Europe/Berlin", display: "Berlin (CET)"},
        {name: "Europe/Moscow", display: "Moscow"},
        {name: "Asia/Tokyo", display: "Tokyo (JST)"},
        {name: "Asia/Shanghai", display: "Shanghai (CST)"},
        {name: "Asia/Singapore", display: "Singapore"},
        {name: "Asia/Dubai", display: "Dubai"},
        {name: "Asia/Kolkata", display: "India (IST)"},
        {name: "Australia/Sydney", display: "Sydney (AEST)"},
        {name: "Pacific/Auckland", display: "Auckland (NZST)"},
        {name: "UTC", display: "UTC"}
    ]

    // All available timezones (loaded from system)
    property var allTimezones: []

    function loadAllTimezones() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-timezones.txt", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var lines = xhr.responseText.trim().split("\n")
                allTimezones = lines.filter(function(tz) { return tz.length > 0 })
            }
        } catch (e) {}
    }

    function filterTimezones(query) {
        if (query.length < 2) {
            filteredTimezones = []
            return
        }
        var q = query.toLowerCase()
        var results = []
        for (var i = 0; i < allTimezones.length && results.length < 10; i++) {
            if (allTimezones[i].toLowerCase().indexOf(q) !== -1) {
                results.push(allTimezones[i])
            }
        }
        filteredTimezones = results
    }

    function setTimezone(tz) {
        console.warn("DATETIME_CMD:timezone:" + tz)
        timezonePickerVisible = false
        timezoneSearchInput.text = ""
        filteredTimezones = []
    }

    ListModel { id: locationSearchModel }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with large clock
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 320
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 280
            radius: 175
            color: Theme.accentColor
            opacity: 0.1
        }

        Column {
            anchors.centerIn: parent
            spacing: 12

            // Large time display
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentTime
                font.pixelSize: 80
                font.weight: Font.Light
                font.letterSpacing: 4
                color: "#ffffff"

                // Colon blink animation
                Timer {
                    property bool colonVisible: true
                    interval: 500
                    running: true
                    repeat: true
                    onTriggered: colonVisible = !colonVisible
                }
            }

            // Date display
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentDay
                font.pixelSize: 28
                font.weight: Font.Medium
                color: Theme.accentColor
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentDate
                font.pixelSize: 18
                color: "#666677"
            }
        }
    }

    // Settings
    Flickable {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: settingsColumn.height
        clip: true

        Column {
            id: settingsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            Text {
                text: "TIME SETTINGS"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Auto time sync toggle
            Rectangle {
                width: settingsColumn.width
                height: 90
                radius: 24
                color: ntpMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: ntpEnabled ? Theme.accentColor : "#1a1a2e"
                border.width: ntpEnabled ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 14
                        color: ntpEnabled ? "#1a1a3a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🌐"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Automatic date & time"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Use network time (NTP)"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: ntpEnabled ? Theme.accentColor : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: ntpEnabled ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"

                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        }
                    }
                }

                MouseArea {
                    id: ntpMouse
                    anchors.fill: parent
                    onClicked: toggleNtp()
                }
            }

            // Timezone
            Rectangle {
                width: settingsColumn.width
                height: 90
                radius: 24
                color: tzMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: timezonePickerVisible ? Theme.accentColor : "#1a1a2e"
                border.width: timezonePickerVisible ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 14
                        color: timezonePickerVisible ? Qt.darker(Theme.accentColor, 2) : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🌍"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Time Zone"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: timezone
                            font.pixelSize: 13
                            color: Theme.accentColor
                        }
                    }

                    Text {
                        text: timezonePickerVisible ? "×" : "→"
                        font.pixelSize: 24
                        color: "#444455"
                    }
                }

                MouseArea {
                    id: tzMouse
                    anchors.fill: parent
                    onClicked: {
                        timezonePickerVisible = !timezonePickerVisible
                        if (timezonePickerVisible && allTimezones.length === 0) {
                            // Load timezones on first open
                            loadAllTimezones()
                        }
                    }
                }
            }

            // Timezone picker (expandable)
            Rectangle {
                width: settingsColumn.width
                height: timezonePickerVisible ? tzPickerCol.height + 32 : 0
                radius: 16
                color: "#15151f"
                clip: true
                visible: height > 0

                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Column {
                    id: tzPickerCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 12

                    // Search input
                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 12
                        color: "#1a1a28"
                        border.color: timezoneSearchInput.activeFocus ? Theme.accentColor : "#2a2a3e"
                        border.width: timezoneSearchInput.activeFocus ? 2 : 1

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Text {
                                text: "🔍"
                                font.pixelSize: 20
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            TextInput {
                                id: timezoneSearchInput
                                width: parent.width - 44
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 18
                                color: "#ffffff"
                                clip: true

                                property string placeholderText: "Search timezone..."
                                Text {
                                    anchors.fill: parent
                                    text: parent.placeholderText
                                    color: "#555566"
                                    font.pixelSize: 18
                                    visible: !parent.text && !parent.activeFocus
                                }

                                onTextChanged: {
                                    tzSearchDebounce.restart()
                                }

                                Timer {
                                    id: tzSearchDebounce
                                    interval: 200
                                    onTriggered: filterTimezones(timezoneSearchInput.text)
                                }
                            }
                        }
                    }

                    // Common timezones (when no search)
                    Column {
                        width: parent.width
                        spacing: 4
                        visible: filteredTimezones.length === 0 && timezoneSearchInput.text.length < 2

                        Text {
                            text: "Common Timezones"
                            font.pixelSize: 13
                            color: "#555566"
                            leftPadding: 4
                        }

                        Repeater {
                            model: commonTimezones

                            Rectangle {
                                width: tzPickerCol.width
                                height: 52
                                radius: 10
                                color: commonTzMouse.pressed ? "#2a2a3e" : (timezone === modelData.name ? Qt.darker(Theme.accentColor, 2) : "#1a1a28")
                                border.color: timezone === modelData.name ? Theme.accentColor : "transparent"
                                border.width: timezone === modelData.name ? 1 : 0

                                Row {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: 12
                                    spacing: 8

                                    Text {
                                        text: timezone === modelData.name ? "✓" : ""
                                        font.pixelSize: 16
                                        color: Theme.accentColor
                                        width: 20
                                    }

                                    Column {
                                        spacing: 2

                                        Text {
                                            text: modelData.display
                                            font.pixelSize: 15
                                            color: "#ffffff"
                                        }

                                        Text {
                                            text: modelData.name
                                            font.pixelSize: 11
                                            color: "#666677"
                                        }
                                    }
                                }

                                MouseArea {
                                    id: commonTzMouse
                                    anchors.fill: parent
                                    onClicked: setTimezone(modelData.name)
                                }
                            }
                        }
                    }

                    // Search results
                    Column {
                        width: parent.width
                        spacing: 4
                        visible: filteredTimezones.length > 0

                        Text {
                            text: "Search Results"
                            font.pixelSize: 13
                            color: "#555566"
                            leftPadding: 4
                        }

                        Repeater {
                            model: filteredTimezones

                            Rectangle {
                                width: tzPickerCol.width
                                height: 52
                                radius: 10
                                color: searchTzMouse.pressed ? "#2a2a3e" : (timezone === modelData ? Qt.darker(Theme.accentColor, 2) : "#1a1a28")
                                border.color: timezone === modelData ? Theme.accentColor : "transparent"
                                border.width: timezone === modelData ? 1 : 0

                                Row {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: 12
                                    spacing: 8

                                    Text {
                                        text: timezone === modelData ? "✓" : ""
                                        font.pixelSize: 16
                                        color: Theme.accentColor
                                        width: 20
                                    }

                                    Text {
                                        text: modelData
                                        font.pixelSize: 15
                                        color: "#ffffff"
                                    }
                                }

                                MouseArea {
                                    id: searchTzMouse
                                    anchors.fill: parent
                                    onClicked: setTimezone(modelData)
                                }
                            }
                        }
                    }

                    // Tip text
                    Text {
                        text: filteredTimezones.length === 0 && timezoneSearchInput.text.length >= 2 ? "No timezones found" : ""
                        font.pixelSize: 13
                        color: "#555566"
                        visible: text !== ""
                    }
                }
            }

            Item { height: 8 }

            Text {
                text: "FORMAT"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // 24-hour time
            Rectangle {
                width: settingsColumn.width
                height: 80
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "⏰"
                        font.pixelSize: 24
                    }

                    Text {
                        text: "24-hour format"
                        font.pixelSize: 18
                        color: "#ffffff"
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Theme.accentColor

                        Rectangle {
                            x: parent.width - width - 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"
                        }
                    }
                }
            }

            Item { height: 16 }

            Text {
                text: "LOCATION"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Current location display
            Rectangle {
                width: settingsColumn.width
                height: 90
                radius: 24
                color: locationMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: locationName !== "Not set" ? Theme.accentColor : "#1a1a2e"
                border.width: locationName !== "Not set" ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 14
                        color: locationName !== "Not set" ? Qt.darker(Theme.accentColor, 2) : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "📍"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Weather Location"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: locationName
                            font.pixelSize: 13
                            color: locationName !== "Not set" ? Theme.accentColor : "#666677"
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Text {
                        text: locationSearchVisible ? "×" : "→"
                        font.pixelSize: 24
                        color: "#444455"
                    }
                }

                MouseArea {
                    id: locationMouse
                    anchors.fill: parent
                    onClicked: locationSearchVisible = !locationSearchVisible
                }
            }

            // Location search (expandable)
            Rectangle {
                width: settingsColumn.width
                height: locationSearchVisible ? searchCol.height + 32 : 0
                radius: 16
                color: "#15151f"
                clip: true
                visible: height > 0

                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Column {
                    id: searchCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 12

                    // Search input
                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 12
                        color: "#1a1a28"
                        border.color: locationSearchInput.activeFocus ? Theme.accentColor : "#2a2a3e"
                        border.width: locationSearchInput.activeFocus ? 2 : 1

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Text {
                                text: "🔍"
                                font.pixelSize: 20
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            TextInput {
                                id: locationSearchInput
                                width: parent.width - 44
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 18
                                color: "#ffffff"
                                clip: true

                                property string placeholderText: "Search city..."
                                Text {
                                    anchors.fill: parent
                                    text: parent.placeholderText
                                    color: "#555566"
                                    font.pixelSize: 18
                                    visible: !parent.text && !parent.activeFocus
                                }

                                onTextChanged: {
                                    searchDebounce.restart()
                                }

                                Timer {
                                    id: searchDebounce
                                    interval: 300
                                    onTriggered: searchLocation(locationSearchInput.text)
                                }
                            }
                        }
                    }

                    // Search results
                    Column {
                        width: parent.width
                        spacing: 4
                        visible: locationSearchModel.count > 0

                        Repeater {
                            model: locationSearchModel

                            Rectangle {
                                width: searchCol.width
                                height: 60
                                radius: 10
                                color: resultMouse.pressed ? "#2a2a3e" : "#1a1a28"

                                Column {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: 12
                                    spacing: 2

                                    Text {
                                        text: model.name
                                        font.pixelSize: 16
                                        color: "#ffffff"
                                    }

                                    Text {
                                        text: (model.admin1 ? model.admin1 + ", " : "") + model.country
                                        font.pixelSize: 12
                                        color: "#888899"
                                    }
                                }

                                MouseArea {
                                    id: resultMouse
                                    anchors.fill: parent
                                    onClicked: selectLocation(model.name, model.country, model.admin1, model.lat, model.lon)
                                }
                            }
                        }
                    }

                    // Tip text
                    Text {
                        text: locationSearchModel.count === 0 ? "Type a city name to search" : ""
                        font.pixelSize: 13
                        color: "#555566"
                        visible: locationSearchModel.count === 0 && locationSearchInput.text.length < 2
                    }
                }
            }

            Item { height: 20 }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? Qt.darker(Theme.accentColor, 1.2) : Theme.accentColor

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            font.weight: Font.Medium
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: stackView.pop()
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
    }
}
