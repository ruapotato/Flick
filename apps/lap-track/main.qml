// SPDX-License-Identifier: AGPL-3.0
// Lap Track - A simple lap counter app using volume buttons
import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Lap Track"
    color: "#0a0a0f"

    // Lap counter state
    property int lapCount: 0
    property bool isTracking: true

    // Handle key press events for volume buttons
    Item {
        id: keyHandler
        focus: true
        anchors.fill: parent

        Keys.onPressed: function(event) {
            // Volume Up (Qt.Key_VolumeUp) or Volume Down (Qt.Key_VolumeDown)
            // Both increment the lap counter
            if (event.key === Qt.Key_VolumeUp || event.key === Qt.Key_VolumeDown) {
                if (root.isTracking) {
                    root.lapCount++
                    // Visual feedback animation
                    pulseAnimation.start()
                }
                event.accepted = true
            }
        }
    }

    // Main content
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 60

        // Header
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "LAP TRACK"
            font.pixelSize: 64
            font.weight: Font.Bold
            font.letterSpacing: 8
            color: "#6366f1"
        }

        // Spacer
        Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

        // Lap counter display
        Rectangle {
            id: counterDisplay
            Layout.alignment: Qt.AlignHCenter
            width: 500
            height: 500
            radius: 250
            color: "transparent"
            border.color: "#6366f1"
            border.width: 8

            // Inner glow effect
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 40
                height: parent.height - 40
                radius: width / 2
                color: "#1a1a2e"
                border.color: "#6366f1"
                border.width: 2
                opacity: 0.5
            }

            // Lap count number
            Text {
                id: lapCountText
                anchors.centerIn: parent
                text: root.lapCount
                font.pixelSize: 180
                font.weight: Font.Bold
                color: "#ffffff"

                // Scale animation for visual feedback
                transform: Scale {
                    id: scaleTransform
                    origin.x: lapCountText.width / 2
                    origin.y: lapCountText.height / 2
                    xScale: 1
                    yScale: 1
                }
            }

            // Pulse animation when lap is recorded
            SequentialAnimation {
                id: pulseAnimation
                PropertyAnimation {
                    target: scaleTransform
                    properties: "xScale,yScale"
                    to: 1.15
                    duration: 100
                    easing.type: Easing.OutQuad
                }
                PropertyAnimation {
                    target: scaleTransform
                    properties: "xScale,yScale"
                    to: 1.0
                    duration: 150
                    easing.type: Easing.InOutQuad
                }
            }
        }

        // Label
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "LAPS"
            font.pixelSize: 48
            font.weight: Font.Medium
            font.letterSpacing: 4
            color: "#888888"
        }

        // Spacer
        Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

        // Instructions
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width - 80
            Layout.preferredHeight: instructionColumn.height + 60
            color: "#1a1a2e"
            radius: 24

            ColumnLayout {
                id: instructionColumn
                anchors.centerIn: parent
                width: parent.width - 60
                spacing: 20

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Press Volume Up or Down"
                    font.pixelSize: 36
                    font.weight: Font.Medium
                    color: "#ffffff"
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "to count each lap"
                    font.pixelSize: 32
                    color: "#888888"
                }
            }
        }

        // Spacer
        Item { Layout.preferredHeight: 40 }

        // Control buttons row
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 40

            // Manual increment button (alternative to volume keys)
            Rectangle {
                width: 200
                height: 120
                radius: 24
                color: mouseAreaPlus.pressed ? "#4f46e5" : "#6366f1"

                Text {
                    anchors.centerIn: parent
                    text: "+1"
                    font.pixelSize: 56
                    font.weight: Font.Bold
                    color: "#ffffff"
                }

                MouseArea {
                    id: mouseAreaPlus
                    anchors.fill: parent
                    onClicked: {
                        if (root.isTracking) {
                            root.lapCount++
                            pulseAnimation.start()
                        }
                    }
                }
            }

            // Reset button
            Rectangle {
                width: 200
                height: 120
                radius: 24
                color: mouseAreaReset.pressed ? "#dc2626" : "#ef4444"

                Text {
                    anchors.centerIn: parent
                    text: "RESET"
                    font.pixelSize: 36
                    font.weight: Font.Bold
                    color: "#ffffff"
                }

                MouseArea {
                    id: mouseAreaReset
                    anchors.fill: parent
                    onClicked: {
                        root.lapCount = 0
                    }
                }
            }
        }

        // Spacer at bottom for safe area
        Item { Layout.preferredHeight: 80 }
    }

    // Ensure key handler has focus
    Component.onCompleted: {
        keyHandler.forceActiveFocus()
    }
}
