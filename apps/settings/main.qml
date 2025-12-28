import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Settings"
    color: "#0a0a0f"

    // Check for deep link page request
    property string startPage: ""

    Component.onCompleted: {
        // Check for requested page in temp file
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick_settings_page", false)
        try {
            xhr.send()
            if (xhr.status === 200 && xhr.responseText.trim() !== "") {
                startPage = xhr.responseText.trim()
                console.log("Settings deep link to: " + startPage)
            }
        } catch (e) {}

        // Navigate to requested page if specified
        if (startPage !== "") {
            var pagePath = "pages/" + startPage + ".qml"
            var component = Qt.createComponent(pagePath)
            if (component.status === Component.Ready) {
                stackView.push(component)
            }
        }
    }

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: mainPage
    }

    Component {
        id: mainPage
        SettingsMain {
            onPageRequested: stackView.push(page)
        }
    }
}
