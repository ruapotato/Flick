import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Calendar"
    color: "#0a0a0f"

    // Calendar uses fixed scaling
    property real textScale: 1.0
    property var currentDate: new Date()
    property int currentMonth: currentDate.getMonth()
    property int currentYear: currentDate.getFullYear()
    property int selectedDay: -1
    property var events: ({})

    Component.onCompleted: {
        loadConfig()
        loadEvents()
    }

    function loadConfig() {
        // Calendar uses fixed scaling - no config needed
    }

    function loadEvents() {
        var eventsPath = "/home/droidian/.local/state/flick/calendar.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + eventsPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                events = JSON.parse(xhr.responseText)
                console.log("Loaded events")
            }
        } catch (e) {
            console.log("No existing events file")
            events = {}
        }
    }

    function saveEvents() {
        var eventsPath = "/home/droidian/.local/state/flick/calendar.json"
        var eventsJson = JSON.stringify(events, null, 2)
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + eventsPath, false)
        try {
            xhr.send(eventsJson)
            console.log("Saved events to " + eventsPath)
        } catch (e) {
            console.log("Failed to save events: " + e)
        }
        // Refresh calendar view to show event indicators
        refreshCalendar()
    }

    function refreshCalendar() {
        // Force grid refresh by resetting model
        var model = calendarGrid.model
        calendarGrid.model = 0
        calendarGrid.model = model
    }

    function getMonthName(month) {
        var months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        return months[month]
    }

    function getDaysInMonth(month, year) {
        return new Date(year, month + 1, 0).getDate()
    }

    function getFirstDayOfMonth(month, year) {
        return new Date(year, month, 1).getDay()
    }

    function isToday(day) {
        var today = new Date()
        return day === today.getDate() &&
               currentMonth === today.getMonth() &&
               currentYear === today.getFullYear()
    }

    function getDateKey(day) {
        return currentYear + "-" +
               String(currentMonth + 1).padStart(2, '0') + "-" +
               String(day).padStart(2, '0')
    }

    function hasEvents(day) {
        var key = getDateKey(day)
        return events[key] && events[key].length > 0
    }

    function previousMonth() {
        Haptic.tap()
        if (currentMonth === 0) {
            currentMonth = 11
            currentYear--
        } else {
            currentMonth--
        }
        calendarGrid.model = null
        calendarGrid.model = getDaysInMonth(currentMonth, currentYear) + getFirstDayOfMonth(currentMonth, currentYear)
    }

    function nextMonth() {
        Haptic.tap()
        if (currentMonth === 11) {
            currentMonth = 0
            currentYear++
        } else {
            currentMonth++
        }
        calendarGrid.model = null
        calendarGrid.model = getDaysInMonth(currentMonth, currentYear) + getFirstDayOfMonth(currentMonth, currentYear)
    }


    // Header
    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 180
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 300
            height: 150
            radius: 150
            color: "#e94560"
            opacity: 0.08

            NumberAnimation on opacity {
                from: 0.05
                to: 0.12
                duration: 3000
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: getMonthName(currentMonth) + " " + currentYear
                font.pixelSize: 42
                font.weight: Font.Light
                font.letterSpacing: 4
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CALENDAR"
                font.pixelSize: 12
                font.weight: Font.Medium
                font.letterSpacing: 3
                color: "#555566"
            }
        }

        // Bottom line
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.2; color: "#e94560" }
                GradientStop { position: 0.8; color: "#e94560" }
                GradientStop { position: 1.0; color: "transparent" }
            }
            opacity: 0.3
        }
    }

    // Main content area
    Item {
        id: mainContent
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100

        // Calendar view
        Item {
            id: calendarView
            anchors.fill: parent
            visible: selectedDay === -1

            // Swipe area for month navigation
            MouseArea {
                anchors.fill: parent
                property real startX: 0

                onPressed: {
                    startX = mouse.x
                }

                onReleased: {
                    var delta = mouse.x - startX
                    if (Math.abs(delta) > 100) {
                        if (delta > 0) {
                            previousMonth()
                        } else {
                            nextMonth()
                        }
                    }
                }
            }

            // Day names header
            Row {
                id: dayNamesRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 40

                Repeater {
                    model: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

                    Rectangle {
                        width: parent.width / 7
                        height: parent.height
                        color: "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: "#777788"
                        }
                    }
                }
            }

            // Calendar grid
            GridView {
                id: calendarGrid
                anchors.top: dayNamesRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.topMargin: 8

                cellWidth: width / 7
                cellHeight: (height - 80) / 6
                interactive: false

                model: getDaysInMonth(currentMonth, currentYear) + getFirstDayOfMonth(currentMonth, currentYear)

                delegate: Item {
                    width: calendarGrid.cellWidth
                    height: calendarGrid.cellHeight

                    property int dayNumber: {
                        var firstDay = getFirstDayOfMonth(currentMonth, currentYear)
                        if (index < firstDay) {
                            return -1
                        }
                        return index - firstDay + 1
                    }

                    property bool isValid: dayNumber > 0 && dayNumber <= getDaysInMonth(currentMonth, currentYear)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 12
                        color: {
                            if (!isValid) return "transparent"
                            if (dayMouse.pressed) return "#e94560"
                            if (isToday(dayNumber)) return "#e94560"
                            if (hasEvents(dayNumber)) return "#1a1a2e"
                            return "transparent"
                        }
                        border.color: isValid && hasEvents(dayNumber) ? "#e94560" : "transparent"
                        border.width: 1
                        opacity: {
                            if (!isValid) return 0
                            if (dayMouse.pressed) return 0.8
                            if (isToday(dayNumber)) return 0.6
                            return 0.4
                        }

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: isValid ? dayNumber : ""
                                font.pixelSize: 20
                                font.weight: isToday(dayNumber) ? Font.Bold : Font.Normal
                                color: isToday(dayNumber) ? "#ffffff" : "#ccccdd"
                            }

                            // Event indicator
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: "#e94560"
                                visible: isValid && hasEvents(dayNumber)
                            }
                        }

                        MouseArea {
                            id: dayMouse
                            anchors.fill: parent
                            enabled: isValid
                            onClicked: {
                                Haptic.tap()
                                selectedDay = dayNumber
                            }
                        }
                    }
                }
            }

            // Month navigation buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                spacing: 40

                Rectangle {
                    width: 60
                    height: 60
                    radius: 30
                    color: prevMouse.pressed ? "#c23a50" : "#e94560"
                    opacity: 0.6

                    Text {
                        anchors.centerIn: parent
                        text: "◀"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        onClicked: previousMonth()
                    }
                }

                Rectangle {
                    width: 60
                    height: 60
                    radius: 30
                    color: nextMouse.pressed ? "#c23a50" : "#e94560"
                    opacity: 0.6

                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        onClicked: nextMonth()
                    }
                }
            }
        }

        // Day detail view
        Item {
            id: dayDetailView
            anchors.fill: parent
            visible: selectedDay !== -1

            Column {
                anchors.fill: parent
                spacing: 16

                // Date header
                Rectangle {
                    width: parent.width
                    height: 80
                    radius: 16
                    color: "#1a1a2e"

                    Text {
                        anchors.centerIn: parent
                        text: selectedDay !== -1 ?
                              getMonthName(currentMonth) + " " + selectedDay + ", " + currentYear : ""
                        font.pixelSize: 28
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }
                }

                // Events list
                ListView {
                    id: eventsList
                    width: parent.width
                    height: parent.height - 240
                    clip: true
                    spacing: 12

                    model: {
                        if (selectedDay === -1) return []
                        var key = getDateKey(selectedDay)
                        return events[key] || []
                    }

                    delegate: Rectangle {
                        width: eventsList.width
                        height: 100
                        radius: 16
                        color: "#1a1a2e"
                        border.color: "#e94560"
                        border.width: 1

                        Column {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

                            Row {
                                width: parent.width
                                spacing: 12

                                Text {
                                    text: modelData.time || "All day"
                                    font.pixelSize: 16
                                    font.weight: Font.Medium
                                    color: "#e94560"
                                }

                                Text {
                                    text: modelData.title || "Untitled"
                                    font.pixelSize: 18
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                }
                            }

                            Rectangle {
                                width: 40
                                height: 30
                                radius: 8
                                color: "#e94560"
                                opacity: 0.3

                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    font.pixelSize: 20
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        var key = getDateKey(selectedDay)
                                        var eventList = events[key] || []
                                        eventList.splice(index, 1)
                                        if (eventList.length === 0) {
                                            delete events[key]
                                        } else {
                                            events[key] = eventList
                                        }
                                        saveEvents()
                                        eventsList.model = events[key] || []
                                    }
                                }
                            }
                        }
                    }
                }

                // Add event button
                Rectangle {
                    width: parent.width
                    height: 60
                    radius: 16
                    color: addMouse.pressed ? "#c23a50" : "#e94560"

                    Text {
                        anchors.centerIn: parent
                        text: "+ Add Event"
                        font.pixelSize: 20
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        onClicked: {
                            newEventPopup.open()
                        }
                    }
                }
            }
        }
    }

    // New event popup
    Rectangle {
        id: newEventPopup
        anchors.fill: parent
        color: "#000000"
        opacity: 0
        visible: opacity > 0
        z: 100

        property bool isOpen: false

        function open() {
            isOpen = true
            titleInput.text = ""
            timeInput.text = ""
            titleInput.forceActiveFocus()
            openAnim.start()
        }

        function close() {
            isOpen = false
            closeAnim.start()
        }

        NumberAnimation {
            id: openAnim
            target: newEventPopup
            property: "opacity"
            to: 0.95
            duration: 200
        }

        NumberAnimation {
            id: closeAnim
            target: newEventPopup
            property: "opacity"
            to: 0
            duration: 200
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {} // Prevent clicks from passing through
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 80
            height: 400
            radius: 24
            color: "#1a1a2e"
            border.color: "#e94560"
            border.width: 2

            Column {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 20

                Text {
                    text: "New Event"
                    font.pixelSize: 28
                    font.weight: Font.Bold
                    color: "#ffffff"
                }

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Title"
                        font.pixelSize: 16
                        color: "#999999"
                    }

                    Rectangle {
                        width: parent.width
                        height: 50
                        radius: 12
                        color: "#0a0a0f"
                        border.color: titleInput.activeFocus ? "#e94560" : "#333344"
                        border.width: titleInput.activeFocus ? 2 : 1

                        TextInput {
                            id: titleInput
                            anchors.fill: parent
                            anchors.margins: 12
                            font.pixelSize: 18
                            color: "#ffffff"
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: titleInput.forceActiveFocus()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Time (optional)"
                        font.pixelSize: 16
                        color: "#999999"
                    }

                    Rectangle {
                        width: parent.width
                        height: 50
                        radius: 12
                        color: "#0a0a0f"
                        border.color: timeInput.activeFocus ? "#e94560" : "#333344"
                        border.width: timeInput.activeFocus ? 2 : 1

                        TextInput {
                            id: timeInput
                            anchors.fill: parent
                            anchors.margins: 12
                            font.pixelSize: 18
                            color: "#ffffff"
                            verticalAlignment: TextInput.AlignVCenter
                            inputMethodHints: Qt.ImhTime
                            clip: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: timeInput.forceActiveFocus()
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 50
                        radius: 12
                        color: cancelMouse.pressed ? "#2a2a3e" : "#1a1a2e"
                        border.color: "#555566"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: 18
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                newEventPopup.close()
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 50
                        radius: 12
                        color: saveMouse.pressed ? "#c23a50" : "#e94560"

                        Text {
                            anchors.centerIn: parent
                            text: "Save"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: saveMouse
                            anchors.fill: parent
                            onClicked: {
                                if (titleInput.text.trim() !== "") {
                                    Haptic.click()
                                    var key = getDateKey(selectedDay)
                                    if (!events[key]) {
                                        events[key] = []
                                    }
                                    events[key].push({
                                        title: titleInput.text.trim(),
                                        time: timeInput.text.trim(),
                                        date: key
                                    })
                                    saveEvents()
                                    eventsList.model = events[key]
                                    newEventPopup.close()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Floating back button
    Rectangle {
        id: backButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? "#c23a50" : "#e94560"
        z: 50

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: selectedDay !== -1 ? "←" : "✕"
            font.pixelSize: 32
            font.weight: Font.Medium
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: {
                Haptic.tap()
                if (selectedDay !== -1) {
                    selectedDay = -1
                    refreshCalendar()
                } else {
                    Qt.quit()
                }
            }
        }
    }

    // Home indicator bar
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 120
        height: 4
        radius: 2
        color: "#333344"
    }
}
