import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: aboutPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 100
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "About"
            font.pixelSize: 36
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.bottomMargin: 100
        contentHeight: content.height + 40
        clip: true

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: 24

            // Logo and name
            Column {
                Layout.fillWidth: true
                Layout.topMargin: 24
                spacing: 20

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 120
                    height: 120
                    radius: 24
                    color: "#1a1a2e"

                    Text {
                        anchors.centerIn: parent
                        text: "⚡"
                        font.pixelSize: 60
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Flick"
                    font.pixelSize: 40
                    font.weight: Font.Medium
                    color: "#ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Mobile Shell for Linux"
                    font.pixelSize: 20
                    color: "#666677"
                }
            }

            // Version info
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 24
                height: infoColumn.height + 40
                color: "#12121a"
                radius: 12

                Column {
                    id: infoColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 0

                    // Info rows
                    Repeater {
                        model: ListModel {
                            ListElement { label: "Version"; value: "0.1.0" }
                            ListElement { label: "Build"; value: "2024.12.20" }
                            ListElement { label: "Compositor"; value: "Smithay + Slint" }
                            ListElement { label: "Apps"; value: "Qt5/QML" }
                            ListElement { label: "License"; value: "GPL-3.0" }
                        }

                        delegate: Item {
                            width: parent.width
                            height: 60

                            RowLayout {
                                anchors.fill: parent

                                Text {
                                    text: model.label
                                    font.pixelSize: 20
                                    color: "#888899"
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: model.value
                                    font.pixelSize: 20
                                    color: "#ffffff"
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: "#1a1a2e"
                                visible: index < 4
                            }
                        }
                    }
                }
            }

            // Credits
            Text {
                text: "Created by David Hamner"
                font.pixelSize: 18
                color: "#666677"
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 24
            }

            Text {
                text: "github.com/ruapotato/Flick"
                font.pixelSize: 18
                color: "#e94560"
                Layout.alignment: Qt.AlignHCenter

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally("https://github.com/ruapotato/Flick")
                }
            }

            Item { height: 40 }
        }
    }

    // Back button - bottom right (Flick design spec)
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        width: 64
        height: 64
        radius: 32
        color: backButtonMouse.pressed ? "#333344" : "#1a1a2e"
        border.color: "#444455"
        border.width: 2

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 28
            color: "#ffffff"
        }

        MouseArea {
            id: backButtonMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }
}
