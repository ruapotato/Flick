import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 720
    height: 1600
    title: "Flick Clock"
    color: "#0a0a0f"

    property real textScale: 2.0
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property string currentTab: "clock"  // clock, alarm, timer, stopwatch
    property string alarmsFile: Theme.stateDir + "/alarms.json"

    // Timer state
    property int timerSeconds: 0
    property int timerSetSeconds: 300  // 5 minutes default
    property bool timerRunning: false

    // Stopwatch state
    property int stopwatchMs: 0
    property bool stopwatchRunning: false

    ListModel { id: alarmsModel }

    Component.onCompleted: {
        loadConfig()
        loadAlarms()
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + Theme.stateDir + "/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale) textScale = config.text_scale
            }
        } catch (e) {}
    }

    function loadAlarms() {
        alarmsModel.clear()
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + alarmsFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                for (var i = 0; i < data.alarms.length; i++) {
                    alarmsModel.append(data.alarms[i])
                }
            }
        } catch (e) {}
    }

    function saveAlarms() {
        var alarms = []
        for (var i = 0; i < alarmsModel.count; i++) {
            alarms.push(alarmsModel.get(i))
        }
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + alarmsFile, false)
        try {
            xhr.send(JSON.stringify({alarms: alarms}, null, 2))
        } catch (e) {}
    }

    function formatTime(date) {
        var h = date.getHours()
        var m = date.getMinutes()
        var ampm = h >= 12 ? "PM" : "AM"
        h = h % 12 || 12
        return h + ":" + (m < 10 ? "0" : "") + m + " " + ampm
    }

    function formatTimerTime(secs) {
        var h = Math.floor(secs / 3600)
        var m = Math.floor((secs % 3600) / 60)
        var s = secs % 60
        if (h > 0) {
            return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
        }
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function formatStopwatchTime(ms) {
        var secs = Math.floor(ms / 1000)
        var mins = Math.floor(secs / 60)
        secs = secs % 60
        var centis = Math.floor((ms % 1000) / 10)
        return (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs + "." + (centis < 10 ? "0" : "") + centis
    }

    // Clock update timer
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: clockText.text = formatTime(new Date())
    }

    // Timer countdown
    Timer {
        interval: 1000
        running: timerRunning && timerSeconds > 0
        repeat: true
        onTriggered: {
            timerSeconds--
            if (timerSeconds <= 0) {
                timerRunning = false
                Haptic.heavy()
                console.log("TIMER_DONE")
            }
        }
    }

    // Stopwatch timer
    Timer {
        interval: 10
        running: stopwatchRunning
        repeat: true
        onTriggered: stopwatchMs += 10
    }

    // Tab bar
    Rectangle {
        id: tabBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 100
        color: "#0a0a0f"
        z: 10

        Row {
            anchors.centerIn: parent
            spacing: 0

            Repeater {
                model: [
                    {id: "clock", label: "Clock"},
                    {id: "alarm", label: "Alarm"},
                    {id: "timer", label: "Timer"},
                    {id: "stopwatch", label: "Stopwatch"}
                ]

                Rectangle {
                    width: 250
                    height: 80
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 16 * textScale
                        font.weight: currentTab === modelData.id ? Font.Medium : Font.Normal
                        color: currentTab === modelData.id ? accentColor : "#888899"
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 40
                        height: 3
                        radius: 1.5
                        color: accentColor
                        visible: currentTab === modelData.id
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            currentTab = modelData.id
                        }
                    }
                }
            }
        }
    }

    // Clock view
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 100
        color: "#0a0a0f"
        visible: currentTab === "clock"

        Column {
            anchors.centerIn: parent
            spacing: 24

            Text {
                id: clockText
                anchors.horizontalCenter: parent.horizontalCenter
                text: formatTime(new Date())
                font.pixelSize: 80 * textScale
                font.weight: Font.ExtraLight
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(new Date(), "dddd, MMMM d")
                font.pixelSize: 20 * textScale
                color: "#888899"
            }
        }
    }

    // Alarm view
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 100
        color: "#0a0a0f"
        visible: currentTab === "alarm"

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            Row {
                width: parent.width

                Text {
                    text: "Alarms"
                    font.pixelSize: 28 * textScale
                    font.weight: Font.Medium
                    color: "#ffffff"
                }

                Item { width: parent.width - 200; height: 1 }

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: addAlarmMouse.pressed ? accentPressed : accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: 32
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: addAlarmMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.click()
                            // Add alarm at next hour
                            var now = new Date()
                            var hour = (now.getHours() + 1) % 24
                            alarmsModel.append({
                                hour: hour,
                                minute: 0,
                                enabled: true,
                                label: "Alarm"
                            })
                            saveAlarms()
                        }
                    }
                }
            }

            ListView {
                width: parent.width
                height: parent.height - 80
                spacing: 12
                clip: true

                model: alarmsModel

                delegate: Rectangle {
                    width: parent.width
                    height: 100
                    radius: 16
                    color: "#15151f"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 20

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: (model.hour % 12 || 12) + ":" + (model.minute < 10 ? "0" : "") + model.minute + " " + (model.hour >= 12 ? "PM" : "AM")
                                font.pixelSize: 32 * textScale
                                font.weight: Font.Light
                                color: model.enabled ? "#ffffff" : "#555566"
                            }

                            Text {
                                text: model.label
                                font.pixelSize: 14 * textScale
                                color: "#888899"
                            }
                        }

                        Item { width: parent.width - 300; height: 1 }

                        // Toggle switch
                        Rectangle {
                            width: 60
                            height: 32
                            radius: 16
                            color: model.enabled ? accentColor : "#333344"
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                x: model.enabled ? parent.width - width - 4 : 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                radius: 12
                                color: "#ffffff"

                                Behavior on x { NumberAnimation { duration: 150 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Haptic.tap()
                                    alarmsModel.set(index, {
                                        hour: model.hour,
                                        minute: model.minute,
                                        enabled: !model.enabled,
                                        label: model.label
                                    })
                                    saveAlarms()
                                }
                            }
                        }

                        // Delete
                        Rectangle {
                            width: 48
                            height: 48
                            radius: 24
                            color: delAlarmMouse.pressed ? accentPressed : "#3a3a4e"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 20
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: delAlarmMouse
                                anchors.fill: parent
                                onClicked: {
                                    Haptic.tap()
                                    alarmsModel.remove(index)
                                    saveAlarms()
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No alarms\n\nTap + to add one"
                    font.pixelSize: 18
                    color: "#555566"
                    horizontalAlignment: Text.AlignHCenter
                    visible: alarmsModel.count === 0
                }
            }
        }
    }

    // Timer view
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 100
        color: "#0a0a0f"
        visible: currentTab === "timer"

        Column {
            anchors.centerIn: parent
            spacing: 48

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: formatTimerTime(timerRunning ? timerSeconds : timerSetSeconds)
                font.pixelSize: 80 * textScale
                font.weight: Font.ExtraLight
                font.family: "monospace"
                color: timerSeconds <= 10 && timerRunning ? accentColor : "#ffffff"
            }

            // Time adjustment (when not running)
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 24
                visible: !timerRunning

                Repeater {
                    model: [1, 5, 10, 15, 30]

                    Rectangle {
                        width: 80
                        height: 48
                        radius: 24
                        color: timerPresetMouse.pressed ? "#333344" : "#1a1a2e"

                        Text {
                            anchors.centerIn: parent
                            text: modelData + "m"
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: timerPresetMouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                timerSetSeconds = modelData * 60
                            }
                        }
                    }
                }
            }

            // Controls
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 32

                // Reset
                Rectangle {
                    width: 72
                    height: 72
                    radius: 36
                    color: resetTimerMouse.pressed ? "#333344" : "#222233"
                    visible: timerRunning || timerSeconds !== timerSetSeconds

                    Text {
                        anchors.centerIn: parent
                        text: "↺"
                        font.pixelSize: 32
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: resetTimerMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            timerRunning = false
                            timerSeconds = timerSetSeconds
                        }
                    }
                }

                // Start/Pause
                Rectangle {
                    width: 100
                    height: 100
                    radius: 50
                    color: startTimerMouse.pressed ? accentPressed : accentColor

                    Text {
                        anchors.centerIn: parent
                        text: timerRunning ? "⏸" : "▶"
                        font.pixelSize: 40
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: startTimerMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.click()
                            if (!timerRunning && timerSeconds === 0) {
                                timerSeconds = timerSetSeconds
                            }
                            timerRunning = !timerRunning
                        }
                    }
                }
            }
        }
    }

    // Stopwatch view
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 100
        color: "#0a0a0f"
        visible: currentTab === "stopwatch"

        Column {
            anchors.centerIn: parent
            spacing: 48

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: formatStopwatchTime(stopwatchMs)
                font.pixelSize: 80 * textScale
                font.weight: Font.ExtraLight
                font.family: "monospace"
                color: "#ffffff"
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 32

                // Reset
                Rectangle {
                    width: 72
                    height: 72
                    radius: 36
                    color: resetSwMouse.pressed ? "#333344" : "#222233"
                    visible: stopwatchMs > 0

                    Text {
                        anchors.centerIn: parent
                        text: "↺"
                        font.pixelSize: 32
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: resetSwMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            stopwatchRunning = false
                            stopwatchMs = 0
                        }
                    }
                }

                // Start/Stop
                Rectangle {
                    width: 100
                    height: 100
                    radius: 50
                    color: startSwMouse.pressed ? (stopwatchRunning ? accentPressed : "#1a7a3a") : (stopwatchRunning ? accentColor : "#228B22")

                    Text {
                        anchors.centerIn: parent
                        text: stopwatchRunning ? "⏸" : "▶"
                        font.pixelSize: 40
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: startSwMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.click()
                            stopwatchRunning = !stopwatchRunning
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
        anchors.rightMargin: 24
        anchors.bottomMargin: 100
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? accentPressed : accentColor
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
    }
}
