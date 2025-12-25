import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: lockScreen

    property string correctPin: "1234"
    property string stateDir: ""
    property bool showingPin: false
    property real swipeProgress: 0  // 0-1 for swipe animation

    signal unlocked()

    // Beautiful gradient background
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0f0f1a" }
            GradientStop { position: 0.4; color: "#1a1a2e" }
            GradientStop { position: 1.0; color: "#16213e" }
        }
    }

    // Subtle animated particles/stars effect
    Repeater {
        model: 20
        Rectangle {
            property real baseX: Math.random() * lockScreen.width
            property real baseY: Math.random() * lockScreen.height * 0.7
            property real animOffset: Math.random() * 2 * Math.PI

            x: baseX + Math.sin(starAnim.elapsed * 0.001 + animOffset) * 3
            y: baseY + Math.cos(starAnim.elapsed * 0.0008 + animOffset) * 2
            width: 2 + Math.random() * 2
            height: width
            radius: width / 2
            color: "#ffffff"
            opacity: 0.1 + Math.random() * 0.15

            NumberAnimation on opacity {
                from: 0.05
                to: 0.25
                duration: 2000 + Math.random() * 3000
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
            }
        }
    }

    Timer {
        id: starAnim
        property real elapsed: 0
        interval: 50
        running: true
        repeat: true
        onTriggered: elapsed += interval
    }

    // Main clock display
    Item {
        id: clockContainer
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -parent.height * 0.12
        width: parent.width
        height: timeText.height + dateText.height + 24
        opacity: 1 - swipeProgress * 1.5
        scale: 1 - swipeProgress * 0.1

        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150 } }

        // Time - large, elegant, thin
        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Math.min(lockScreen.width * 0.28, 180)
            font.weight: Font.Thin
            font.letterSpacing: -4
            color: "#ffffff"
            text: Qt.formatTime(new Date(), "hh:mm")

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: timeText.text = Qt.formatTime(new Date(), "hh:mm")
            }
        }

        // Date - elegant subtitle
        Text {
            id: dateText
            anchors.top: timeText.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Math.min(lockScreen.width * 0.055, 32)
            font.weight: Font.Light
            font.letterSpacing: 2
            color: "#8888aa"
            text: Qt.formatDate(new Date(), "dddd, MMMM d").toUpperCase()

            Timer {
                interval: 60000
                running: true
                repeat: true
                onTriggered: dateText.text = Qt.formatDate(new Date(), "dddd, MMMM d").toUpperCase()
            }
        }
    }

    // Media controls on clock screen
    MediaControls {
        id: clockMediaControls
        anchors.top: clockContainer.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: 1 - swipeProgress * 1.5
        stateDir: lockScreen.stateDir

        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Swipe up hint with animated chevron
    Column {
        id: swipeHint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80
        spacing: 16
        opacity: (1 - swipeProgress * 2) * 0.8

        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Animated chevron
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "^"
            font.pixelSize: 32
            font.weight: Font.Light
            color: "#666688"

            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: -8; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { from: -8; to: 0; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Swipe up to unlock"
            font.pixelSize: Math.min(lockScreen.width * 0.045, 22)
            font.weight: Font.Light
            font.letterSpacing: 1
            color: "#555566"
        }
    }

    // Swipe gesture handler
    MouseArea {
        id: swipeArea
        anchors.fill: parent
        enabled: !showingPin
        property real startY: 0
        property bool isDragging: false

        onPressed: {
            startY = mouse.y
            isDragging = true
        }

        onPositionChanged: {
            if (isDragging) {
                var dragDist = startY - mouse.y
                swipeProgress = Math.max(0, Math.min(1, dragDist / (lockScreen.height * 0.3)))

                if (swipeProgress > 0.7) {
                    isDragging = false
                    showingPin = true
                    swipeProgress = 0
                }
            }
        }

        onReleased: {
            isDragging = false
            if (!showingPin) {
                swipeProgress = 0
            }
        }
    }

    // PIN Entry overlay - slides up from bottom
    Rectangle {
        id: pinOverlay
        anchors.fill: parent
        color: "transparent"
        opacity: showingPin ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
        }

        // Semi-transparent background
        Rectangle {
            anchors.fill: parent
            color: "#0a0a0f"
            opacity: 0.92
        }

        // Container for PIN entry and media controls
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: showingPin ? 0 : 200
            spacing: 24

            Behavior on anchors.verticalCenterOffset {
                NumberAnimation { duration: 400; easing.type: Easing.OutBack }
            }

            PinEntry {
                id: pinEntry
                anchors.horizontalCenter: parent.horizontalCenter
                correctPin: lockScreen.correctPin

                onPinCorrect: {
                    // Success animation
                    successAnim.start()
                }

                onPinIncorrect: {
                    shakeAnimation.start()
                }

                onCancelled: {
                    showingPin = false
                }
            }

            // Media controls below PIN entry
            MediaControls {
                id: pinMediaControls
                anchors.horizontalCenter: parent.horizontalCenter
                stateDir: lockScreen.stateDir
            }
        }

        // Shake animation for wrong PIN
        SequentialAnimation {
            id: shakeAnimation
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x - 25; duration: 40 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x + 25; duration: 40 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x - 20; duration: 40 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x + 20; duration: 40 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x; duration: 40 }
        }

        // Success animation
        SequentialAnimation {
            id: successAnim
            PropertyAnimation { target: pinOverlay; property: "scale"; to: 1.05; duration: 150 }
            PropertyAnimation { target: pinOverlay; property: "opacity"; to: 0; duration: 300 }
            ScriptAction {
                script: {
                    writeUnlockSignal()
                    lockScreen.unlocked()
                }
            }
        }
    }

    // Home indicator at bottom
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        width: 134
        height: 5
        radius: 2.5
        color: "#444455"
        opacity: 0.6
    }

    // Write unlock signal file
    function writeUnlockSignal() {
        var signalPath = stateDir + "/unlock_signal"
        console.log("FLICK_UNLOCK_SIGNAL:" + signalPath)
    }
}
