import QtQuick 2.15
import QtQuick.Controls 2.15
import FlickBackend 1.0
import "shared"

Item {
    id: mediaControls
    width: parent ? parent.width - Theme.sp(48) : 400
    height: MediaController.hasMedia ? Theme.sp(140) : 0
    visible: MediaController.hasMedia

    property color accentColor: Theme.accentColor
    property string stateDir: Theme.stateDir

    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // Background with blur effect
    Rectangle {
        anchors.fill: parent
        radius: Theme.sp(20)
        color: "#1a1a28"
        opacity: 0.9
        border.color: "#333344"
        border.width: 1
    }

    Row {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingLarge

        // Album art / App icon placeholder
        Rectangle {
            width: Theme.sp(54)
            height: Theme.sp(54)
            radius: Theme.sp(12)
            color: MediaController.isAudiobook ? accentColor : "#4a9eff"
            opacity: 0.3
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: MediaController.isAudiobook ? "B" : "M"
                font.pixelSize: Theme.sp(26)
                font.bold: true
                color: "#ffffff"
            }
        }

        // Track info and controls
        Column {
            width: parent.width - Theme.sp(96) - Theme.spacingLarge
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingSmall

            // Title
            Text {
                width: parent.width
                text: MediaController.title
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: "#ffffff"
                elide: Text.ElideRight
            }

            // Artist / Book
            Text {
                width: parent.width
                text: MediaController.artist
                font.pixelSize: Theme.fontNormal
                color: "#888899"
                elide: Text.ElideRight
            }

            // Controls row
            Row {
                width: parent.width
                spacing: Theme.sp(20)

                // Skip back (30s for audiobooks, prev track for music)
                Rectangle {
                    width: Theme.sp(44)
                    height: Theme.sp(44)
                    radius: Theme.sp(22)
                    color: skipBackMouse.pressed ? "#333344" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: MediaController.isMusic ? "<" : "<<"
                        font.pixelSize: Theme.sp(22)
                        color: "#aaaacc"
                    }

                    MouseArea {
                        id: skipBackMouse
                        anchors.fill: parent
                        anchors.margins: -25
                        onClicked: {
                            Haptic.tap()
                            if (MediaController.isMusic) {
                                MediaController.previous()
                            } else {
                                MediaController.seekBackward(30000)
                            }
                        }
                    }
                }

                // Play/Pause
                Rectangle {
                    width: Theme.sp(56)
                    height: Theme.sp(56)
                    radius: Theme.sp(28)
                    color: playPauseMouse.pressed ? Qt.darker(accentColor, 1.2) : accentColor

                    Text {
                        anchors.centerIn: parent
                        text: MediaController.isPlaying ? "||" : ">"
                        font.pixelSize: Theme.sp(24)
                        font.bold: true
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: playPauseMouse
                        anchors.fill: parent
                        anchors.margins: -25
                        onClicked: {
                            Haptic.click()
                            MediaController.togglePlayPause()
                        }
                    }
                }

                // Skip forward (30s for audiobooks, next track for music)
                Rectangle {
                    width: Theme.sp(44)
                    height: Theme.sp(44)
                    radius: Theme.sp(22)
                    color: skipFwdMouse.pressed ? "#333344" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: MediaController.isMusic ? ">" : ">>"
                        font.pixelSize: Theme.sp(22)
                        color: "#aaaacc"
                    }

                    MouseArea {
                        id: skipFwdMouse
                        anchors.fill: parent
                        anchors.margins: -25
                        onClicked: {
                            Haptic.tap()
                            if (MediaController.isMusic) {
                                MediaController.next()
                            } else {
                                MediaController.seekForward(30000)
                            }
                        }
                    }
                }

                // Time display
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: MediaController.positionText + " / " + MediaController.durationText
                    font.pixelSize: Theme.fontSmall
                    color: "#666677"
                }
            }
        }
    }
}
