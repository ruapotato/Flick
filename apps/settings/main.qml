import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../shared"

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Settings"
    color: "#0a0a0f"

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: mainPage

        // Swipe-back gesture overlay for sub-pages
        SwipeBackArea {
            anchors.fill: parent
            visible: stackView.depth > 1
            z: 1000  // Above content

            onBack: {
                if (stackView.depth > 1) {
                    stackView.pop()
                }
            }
        }
    }

    Component {
        id: mainPage
        SettingsMain {
            onPageRequested: stackView.push(page)

            // Main page swipe-back quits the app
            SwipeBackArea {
                anchors.fill: parent
                z: 1000
                onBack: Qt.quit()
            }
        }
    }
}
