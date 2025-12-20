import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: aboutPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 140
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "About"
            font.pixelSize: 48
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.bottomMargin: 120
        contentHeight: content.height + 60
        clip: true

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 32
            spacing: 32

            // Logo and name
            Column {
                Layout.fillWidth: true
                Layout.topMargin: 32
                spacing: 28

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 160
                    height: 160
                    radius: 32
                    color: "#1a1a2e"

                    Text {
                        anchors.centerIn: parent
                        text: "⚡"
                        font.pixelSize: 80
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Flick"
                    font.pixelSize: 56
                    font.weight: Font.Medium
                    color: "#ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Mobile Shell for Linux"
                    font.pixelSize: 28
                    color: "#666677"
                }
            }

            // Version info
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 32
                height: infoColumn.height + 48
                color: "#12121a"
                radius: 16

                Column {
                    id: infoColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 24
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
                            height: 80

                            RowLayout {
                                anchors.fill: parent

                                Text {
                                    text: model.label
                                    font.pixelSize: 26
                                    color: "#888899"
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: model.value
                                    font.pixelSize: 26
                                    color: "#ffffff"
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 2
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
                font.pixelSize: 24
                color: "#666677"
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 32
            }

            Text {
                text: "github.com/ruapotato/Flick"
                font.pixelSize: 24
                color: "#e94560"
                Layout.alignment: Qt.AlignHCenter

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally("https://github.com/ruapotato/Flick")
                }
            }

            Item { height: 60 }
        }
    }

    // Back button - bottom right
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 32
        anchors.bottomMargin: 32
        width: 80
        height: 80
        radius: 40
        color: backButtonMouse.pressed ? "#333344" : "#1a1a2e"
        border.color: "#444455"
        border.width: 3

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 36
            color: "#ffffff"
        }

        MouseArea {
            id: backButtonMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }
}
