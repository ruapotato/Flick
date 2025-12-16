import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: aboutPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 80
        color: "#12121a"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Text {
                text: "‹"
                font.pixelSize: 32
                color: "#e94560"
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: stackView.pop()
                }
            }

            Text {
                text: "About"
                font.pixelSize: 28
                font.weight: Font.Light
                color: "#ffffff"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            Item { width: 32 }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: content.height + 40
        clip: true

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 20

            // Logo and name
            Column {
                Layout.fillWidth: true
                Layout.topMargin: 20
                spacing: 16

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 100
                    height: 100
                    radius: 20
                    color: "#1a1a2e"

                    Text {
                        anchors.centerIn: parent
                        text: "⚡"
                        font.pixelSize: 48
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Flick"
                    font.pixelSize: 32
                    font.weight: Font.Medium
                    color: "#ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Mobile Shell for Linux"
                    font.pixelSize: 16
                    color: "#666677"
                }
            }

            // Version info
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 20
                height: infoColumn.height + 32
                color: "#12121a"
                radius: 10

                Column {
                    id: infoColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 0

                    // Info rows
                    Repeater {
                        model: ListModel {
                            ListElement { label: "Version"; value: "0.1.0" }
                            ListElement { label: "Build"; value: "2024.12.15" }
                            ListElement { label: "Compositor"; value: "Smithay + Slint" }
                            ListElement { label: "Apps"; value: "Qt5/QML" }
                            ListElement { label: "License"; value: "GPL-3.0" }
                        }

                        delegate: Item {
                            width: parent.width
                            height: 50

                            RowLayout {
                                anchors.fill: parent

                                Text {
                                    text: model.label
                                    font.pixelSize: 16
                                    color: "#888899"
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: model.value
                                    font.pixelSize: 16
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
                font.pixelSize: 14
                color: "#666677"
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 20
            }

            Text {
                text: "github.com/ruapotato/Flick"
                font.pixelSize: 14
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
}
