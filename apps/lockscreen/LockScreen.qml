import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: lockScreen

    property string correctPin: "1234"
    property string stateDir: ""
    property bool showingPin: false

    signal unlocked()

    // Simple dark background
    Rectangle {
        anchors.fill: parent
        color: "#1a1a2e"
    }

    // Time display - simplified
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -80
        spacing: 8

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: 96
            color: "#ffffff"
            text: Qt.formatTime(new Date(), "hh:mm")

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: timeText.text = Qt.formatTime(new Date(), "hh:mm")
            }
        }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: 24
            color: "#888899"
            text: Qt.formatDate(new Date(), "dddd, MMMM d")

            Timer {
                interval: 60000
                running: true
                repeat: true
                onTriggered: dateText.text = Qt.formatDate(new Date(), "dddd, MMMM d")
            }
        }
    }

    // Swipe up hint
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 60
        spacing: 12
        opacity: showingPin ? 0 : 1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Swipe up to unlock"
            font.pixelSize: 16
            color: "#666677"
        }
    }

    // Swipe gesture area
    MouseArea {
        anchors.fill: parent
        property real startY: 0
        property real dragDistance: 0

        onPressed: {
            startY = mouse.y
        }

        onPositionChanged: {
            dragDistance = startY - mouse.y
            if (dragDistance > 100 && !showingPin) {
                showingPin = true
            }
        }

        onReleased: {
            dragDistance = 0
        }
    }

    // PIN Entry overlay
    Rectangle {
        id: pinOverlay
        anchors.fill: parent
        color: "#0a0a0f"
        opacity: showingPin ? 0.95 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }

        PinEntry {
            id: pinEntry
            anchors.centerIn: parent
            correctPin: lockScreen.correctPin

            Component.onCompleted: {
                console.log("PinEntry created, correctPin:", correctPin, "enteredPin:", enteredPin)
            }

            onPinCorrect: {
                console.log("PIN CORRECT triggered!")
                writeUnlockSignal()
                lockScreen.unlocked()
            }

            onPinIncorrect: {
                shakeAnimation.start()
            }

            onCancelled: {
                showingPin = false
            }
        }

        // Shake animation for wrong PIN
        SequentialAnimation {
            id: shakeAnimation
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x - 20; duration: 50 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x + 20; duration: 50 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x - 15; duration: 50 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x + 15; duration: 50 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x; duration: 50 }
        }
    }

    // Write unlock signal file
    function writeUnlockSignal() {
        var signalPath = stateDir + "/unlock_signal"
        console.log("FLICK_UNLOCK_SIGNAL:" + signalPath)
    }
}
