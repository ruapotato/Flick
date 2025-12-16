import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.15

Item {
    id: lockScreen

    property string correctPin: "1234"
    property string stateDir: ""
    property bool showingPin: false

    signal unlocked()

    // Background gradient
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0a0a0f" }
            GradientStop { position: 0.5; color: "#12121a" }
            GradientStop { position: 1.0; color: "#1a1a2e" }
        }
    }

    // Subtle animated particles in background
    Repeater {
        model: 20
        Rectangle {
            id: particle
            property real startX: Math.random() * lockScreen.width
            property real startY: Math.random() * lockScreen.height
            property real animDuration: 8000 + Math.random() * 12000

            x: startX
            y: startY
            width: 2 + Math.random() * 3
            height: width
            radius: width / 2
            color: "#ffffff"
            opacity: 0.03 + Math.random() * 0.05

            SequentialAnimation on y {
                loops: Animation.Infinite
                PropertyAnimation {
                    to: -20
                    duration: particle.animDuration
                    easing.type: Easing.Linear
                }
                PropertyAnimation {
                    to: lockScreen.height + 20
                    duration: 0
                }
            }
        }
    }

    // Main content container - slides up when PIN is shown
    Item {
        id: mainContent
        anchors.fill: parent
        y: showingPin ? -height * 0.3 : 0

        Behavior on y {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }

        // Time display
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -80
            spacing: 8

            Text {
                id: timeText
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 96
                font.weight: Font.Light
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
                font.weight: Font.Normal
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
    }

    // Swipe up hint
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 60
        spacing: 12
        opacity: showingPin ? 0 : 1

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        // Animated chevron
        Item {
            width: 40
            height: 20
            anchors.horizontalCenter: parent.horizontalCenter

            Canvas {
                id: chevron
                anchors.fill: parent
                property real animOffset: 0

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#666677"
                    ctx.lineWidth = 2
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.moveTo(5, 15 - animOffset)
                    ctx.lineTo(20, 5 - animOffset)
                    ctx.lineTo(35, 15 - animOffset)
                    ctx.stroke()
                }

                SequentialAnimation on animOffset {
                    loops: Animation.Infinite
                    NumberAnimation { to: 5; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 800; easing.type: Easing.InOutSine }
                    onRunningChanged: chevron.requestPaint()
                }

                Connections {
                    target: chevron
                    function onAnimOffsetChanged() { chevron.requestPaint() }
                }
            }
        }

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
        color: "transparent"
        opacity: showingPin ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }

        // Semi-transparent background
        Rectangle {
            anchors.fill: parent
            color: "#0a0a0f"
            opacity: 0.95
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
                // Write unlock signal and quit
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
    // This uses console.log with a special marker that the shell can detect
    // The shell's QML launcher wrapper will create the signal file
    function writeUnlockSignal() {
        var signalPath = stateDir + "/unlock_signal"
        // Special marker that shell can detect in stdout
        console.log("FLICK_UNLOCK_SIGNAL:" + signalPath)
    }
}
