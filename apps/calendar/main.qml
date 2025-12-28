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

    property var currentDate: new Date()
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property int currentMonth: currentDate.getMonth()
    property int currentYear: currentDate.getFullYear()
    property int selectedDay: -1
    property var events: ({})
    property string viewMode: "month"  // "month" or "week"
    property int currentWeekStart: 0  // Day of month for week view start

    Component.onCompleted: {
        loadEvents()
        updateCurrentWeek()
    }

    function loadEvents() {
        var eventsPath = "/home/droidian/.local/state/flick/calendar.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + eventsPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                events = JSON.parse(xhr.responseText)
                console.log("Loaded events: " + JSON.stringify(events))
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
            console.log("Saved events")
        } catch (e) {
            console.log("Failed to save events: " + e)
        }
    }

    function updateCurrentWeek() {
        var today = new Date()
        var dayOfWeek = today.getDay()
        currentWeekStart = today.getDate() - dayOfWeek
        if (currentWeekStart < 1) currentWeekStart = 1
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
        var result = events[key] && events[key].length > 0
        return result
    }

    function getEventsForDay(day) {
        var key = getDateKey(day)
        return events[key] || []
    }

    function getEventCount(day) {
        var key = getDateKey(day)
        return events[key] ? events[key].length : 0
    }

    function previousMonth() {
        Haptic.tap()
        if (currentMonth === 0) {
            currentMonth = 11
            currentYear--
        } else {
            currentMonth--
        }
    }

    function nextMonth() {
        Haptic.tap()
        if (currentMonth === 11) {
            currentMonth = 0
            currentYear++
        } else {
            currentMonth++
        }
    }

    function previousWeek() {
        Haptic.tap()
        currentWeekStart -= 7
        if (currentWeekStart < 1) {
            previousMonth()
            currentWeekStart = getDaysInMonth(currentMonth, currentYear) + currentWeekStart
        }
    }

    function nextWeek() {
        Haptic.tap()
        currentWeekStart += 7
        var daysInMonth = getDaysInMonth(currentMonth, currentYear)
        if (currentWeekStart > daysInMonth) {
            currentWeekStart = currentWeekStart - daysInMonth
            nextMonth()
        }
    }

    // Header
    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 160
        color: "transparent"

        Column {
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: getMonthName(currentMonth) + " " + currentYear
                font.pixelSize: 36
                font.weight: Font.Light
                color: "#ffffff"
            }

            // View mode toggle
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Rectangle {
                    width: 100
                    height: 36
                    radius: 18
                    color: viewMode === "month" ? accentColor : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "Month"
                        font.pixelSize: 14
                        color: "#ffffff"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            viewMode = "month"
                        }
                    }
                }

                Rectangle {
                    width: 100
                    height: 36
                    radius: 18
                    color: viewMode === "week" ? accentColor : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "Week"
                        font.pixelSize: 14
                        color: "#ffffff"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            viewMode = "week"
                            updateCurrentWeek()
                        }
                    }
                }
            }
        }
    }

    // Main content
    Item {
        id: mainContent
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100

        // Month View
        Item {
            id: monthView
            anchors.fill: parent
            visible: selectedDay === -1 && viewMode === "month"

            // Day names
            Row {
                id: dayNames
                anchors.top: parent.top
                width: parent.width
                height: 40

                Repeater {
                    model: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    Text {
                        width: parent.width / 7
                        text: modelData
                        font.pixelSize: 14
                        color: "#777788"
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // Calendar grid
            Grid {
                id: calendarGrid
                anchors.top: dayNames.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.height - 140
                columns: 7

                property int firstDay: getFirstDayOfMonth(currentMonth, currentYear)
                property int daysInMonth: getDaysInMonth(currentMonth, currentYear)
                property real cellW: width / 7
                property real cellH: height / 6

                Repeater {
                    model: 42

                    Item {
                        width: calendarGrid.cellW
                        height: calendarGrid.cellH

                        property int dayNum: index - calendarGrid.firstDay + 1
                        property bool isValid: dayNum > 0 && dayNum <= calendarGrid.daysInMonth
                        property bool hasEvt: isValid && hasEvents(dayNum)

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 12
                            color: {
                                if (!isValid) return "transparent"
                                if (isToday(dayNum)) return accentColor
                                if (hasEvt) return "#2a2a3e"
                                return "transparent"
                            }
                            opacity: isValid ? (isToday(dayNum) ? 0.8 : 1.0) : 0
                            border.color: hasEvt ? accentColor : "transparent"
                            border.width: hasEvt ? 2 : 0

                            Column {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: isValid ? dayNum : ""
                                    font.pixelSize: 18
                                    font.weight: isToday(dayNum) ? Font.Bold : Font.Normal
                                    color: "#ffffff"
                                }

                                // Event dot
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: accentColor
                                    visible: hasEvt && !isToday(dayNum)
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: isValid
                                onClicked: {
                                    Haptic.tap()
                                    selectedDay = dayNum
                                    updateEventsList()
                                }
                            }
                        }
                    }
                }
            }

            // Navigation
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                spacing: 40

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "◀"
                        font.pixelSize: 20
                        color: "#ffffff"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: previousMonth()
                    }
                }

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        font.pixelSize: 20
                        color: "#ffffff"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: nextMonth()
                    }
                }
            }
        }

        // Week View
        Item {
            id: weekView
            anchors.fill: parent
            visible: selectedDay === -1 && viewMode === "week"

            Column {
                anchors.fill: parent
                spacing: 8

                // Week days
                Repeater {
                    model: 7

                    Rectangle {
                        width: parent.width
                        height: (weekView.height - 120) / 7
                        radius: 12
                        color: {
                            var day = currentWeekStart + index
                            if (day > getDaysInMonth(currentMonth, currentYear)) return "#1a1a2e"
                            if (day < 1) return "#1a1a2e"
                            if (isToday(day)) return "#2a2a3e"
                            return "#1a1a2e"
                        }
                        border.color: {
                            var day = currentWeekStart + index
                            if (day > 0 && day <= getDaysInMonth(currentMonth, currentYear) && hasEvents(day)) {
                                return accentColor
                            }
                            return "transparent"
                        }
                        border.width: 2

                        property int dayNum: {
                            var d = currentWeekStart + index
                            var max = getDaysInMonth(currentMonth, currentYear)
                            if (d < 1 || d > max) return -1
                            return d
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 16

                            // Day info
                            Column {
                                width: 80
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    text: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][index]
                                    font.pixelSize: 14
                                    color: "#777788"
                                }
                                Text {
                                    text: dayNum > 0 ? dayNum : ""
                                    font.pixelSize: 28
                                    font.weight: Font.Bold
                                    color: dayNum > 0 && isToday(dayNum) ? accentColor : "#ffffff"
                                }
                            }

                            // Events preview
                            Column {
                                width: parent.width - 96
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Repeater {
                                    model: dayNum > 0 ? getEventsForDay(dayNum).slice(0, 2) : []

                                    Text {
                                        text: (modelData.time || "All day") + " - " + modelData.title
                                        font.pixelSize: 14
                                        color: "#ccccdd"
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }

                                Text {
                                    visible: dayNum > 0 && getEventCount(dayNum) > 2
                                    text: "+" + (getEventCount(dayNum) - 2) + " more"
                                    font.pixelSize: 12
                                    color: accentColor
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: dayNum > 0
                            onClicked: {
                                Haptic.tap()
                                selectedDay = dayNum
                                updateEventsList()
                            }
                        }
                    }
                }

                // Week navigation
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 40

                    Rectangle {
                        width: 56
                        height: 56
                        radius: 28
                        color: "#2a2a3e"

                        Text {
                            anchors.centerIn: parent
                            text: "◀"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: previousWeek()
                        }
                    }

                    Rectangle {
                        width: 56
                        height: 56
                        radius: 28
                        color: "#2a2a3e"

                        Text {
                            anchors.centerIn: parent
                            text: "▶"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: nextWeek()
                        }
                    }
                }
            }
        }

        // Day Detail View
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
                    height: 70
                    radius: 16
                    color: "#1a1a2e"

                    Text {
                        anchors.centerIn: parent
                        text: getMonthName(currentMonth) + " " + selectedDay + ", " + currentYear
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }
                }

                // Events list
                ListView {
                    id: eventsList
                    width: parent.width
                    height: parent.height - 160
                    clip: true
                    spacing: 12

                    model: ListModel { id: eventsModel }

                    delegate: Rectangle {
                        width: eventsList.width
                        height: 80
                        radius: 16
                        color: "#1a1a2e"
                        border.color: accentColor
                        border.width: 1

                        Row {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 16

                            Column {
                                width: parent.width - 60
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    text: model.title
                                    font.pixelSize: 18
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                Text {
                                    text: model.time || "All day"
                                    font.pixelSize: 14
                                    color: accentColor
                                }
                            }

                            Rectangle {
                                width: 44
                                height: 44
                                radius: 22
                                color: delMouse.pressed ? accentColor : "#2a2a3e"
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    font.pixelSize: 24
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    onClicked: {
                                        Haptic.tap()
                                        deleteEvent(model.index)
                                    }
                                }
                            }
                        }
                    }

                    // Empty state
                    Text {
                        anchors.centerIn: parent
                        text: "No events"
                        font.pixelSize: 18
                        color: "#555566"
                        visible: eventsModel.count === 0
                    }
                }

                // Add event button
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 16
                    color: addMouse.pressed ? accentPressed : accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "+ Add Event"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            eventPopup.open()
                        }
                    }
                }
            }
        }
    }

    function updateEventsList() {
        eventsModel.clear()
        if (selectedDay > 0) {
            var dayEvents = getEventsForDay(selectedDay)
            for (var i = 0; i < dayEvents.length; i++) {
                eventsModel.append({
                    title: dayEvents[i].title || "Untitled",
                    time: dayEvents[i].time || "",
                    index: i
                })
            }
        }
    }

    function deleteEvent(idx) {
        var key = getDateKey(selectedDay)
        var eventList = events[key] || []
        eventList.splice(idx, 1)
        if (eventList.length === 0) {
            delete events[key]
        } else {
            events[key] = eventList
        }
        saveEvents()
        updateEventsList()
    }

    function addEvent(title, hour, minute) {
        var key = getDateKey(selectedDay)
        if (!events[key]) {
            events[key] = []
        }
        var timeStr = ""
        if (hour >= 0) {
            var h = hour % 12
            if (h === 0) h = 12
            var ampm = hour < 12 ? "AM" : "PM"
            timeStr = h + ":" + String(minute).padStart(2, '0') + " " + ampm
        }
        events[key].push({
            title: title,
            time: timeStr,
            date: key
        })
        saveEvents()
        updateEventsList()
    }

    // Event Popup
    Rectangle {
        id: eventPopup
        anchors.fill: parent
        color: "#000000ee"
        visible: false
        z: 100

        function open() {
            titleInput.text = ""
            selectedHour = -1
            selectedMinute = 0
            visible = true
            titleInput.forceActiveFocus()
        }

        function close() {
            visible = false
        }

        property int selectedHour: -1
        property int selectedMinute: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {} // Block clicks
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 60
            height: 520
            radius: 24
            color: "#1a1a2e"
            border.color: accentColor
            border.width: 2

            Column {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16

                Text {
                    text: "New Event"
                    font.pixelSize: 24
                    font.weight: Font.Bold
                    color: "#ffffff"
                }

                // Title input
                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Title"
                        font.pixelSize: 14
                        color: "#888899"
                    }

                    Rectangle {
                        width: parent.width
                        height: 50
                        radius: 12
                        color: "#0a0a0f"
                        border.color: titleInput.activeFocus ? accentColor : "#333344"

                        TextInput {
                            id: titleInput
                            anchors.fill: parent
                            anchors.margins: 12
                            font.pixelSize: 18
                            color: "#ffffff"
                            verticalAlignment: TextInput.AlignVCenter
                        }
                    }
                }

                // Time picker
                Column {
                    width: parent.width
                    spacing: 8

                    Row {
                        spacing: 12

                        Text {
                            text: "Time"
                            font.pixelSize: 14
                            color: "#888899"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 100
                            height: 32
                            radius: 16
                            color: eventPopup.selectedHour === -1 ? accentColor : "#2a2a3e"

                            Text {
                                anchors.centerIn: parent
                                text: "All Day"
                                font.pixelSize: 14
                                color: "#ffffff"
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Haptic.tap()
                                    eventPopup.selectedHour = -1
                                }
                            }
                        }
                    }

                    // Hour picker
                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Hour:"
                            font.pixelSize: 14
                            color: "#666677"
                            width: 50
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Flow {
                            width: parent.width - 58
                            spacing: 6

                            Repeater {
                                model: 12

                                Rectangle {
                                    width: 44
                                    height: 36
                                    radius: 8
                                    color: {
                                        if (eventPopup.selectedHour === index || eventPopup.selectedHour === index + 12)
                                            return accentColor
                                        return "#2a2a3e"
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: index === 0 ? "12" : index
                                        font.pixelSize: 14
                                        color: "#ffffff"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            Haptic.tap()
                                            // Keep AM/PM, just change hour
                                            var isPM = eventPopup.selectedHour >= 12
                                            eventPopup.selectedHour = isPM ? index + 12 : index
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // AM/PM and Minute
                    Row {
                        width: parent.width
                        spacing: 16

                        // AM/PM toggle
                        Row {
                            spacing: 8

                            Rectangle {
                                width: 60
                                height: 36
                                radius: 8
                                color: eventPopup.selectedHour >= 0 && eventPopup.selectedHour < 12 ? accentColor : "#2a2a3e"

                                Text {
                                    anchors.centerIn: parent
                                    text: "AM"
                                    font.pixelSize: 14
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        Haptic.tap()
                                        if (eventPopup.selectedHour < 0) eventPopup.selectedHour = 9
                                        else if (eventPopup.selectedHour >= 12) eventPopup.selectedHour -= 12
                                    }
                                }
                            }

                            Rectangle {
                                width: 60
                                height: 36
                                radius: 8
                                color: eventPopup.selectedHour >= 12 ? accentColor : "#2a2a3e"

                                Text {
                                    anchors.centerIn: parent
                                    text: "PM"
                                    font.pixelSize: 14
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        Haptic.tap()
                                        if (eventPopup.selectedHour < 0) eventPopup.selectedHour = 12
                                        else if (eventPopup.selectedHour < 12) eventPopup.selectedHour += 12
                                    }
                                }
                            }
                        }

                        // Minute picker
                        Row {
                            spacing: 8

                            Text {
                                text: ":"
                                font.pixelSize: 18
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Repeater {
                                model: [0, 15, 30, 45]

                                Rectangle {
                                    width: 50
                                    height: 36
                                    radius: 8
                                    color: eventPopup.selectedMinute === modelData ? accentColor : "#2a2a3e"

                                    Text {
                                        anchors.centerIn: parent
                                        text: String(modelData).padStart(2, '0')
                                        font.pixelSize: 14
                                        color: "#ffffff"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            Haptic.tap()
                                            eventPopup.selectedMinute = modelData
                                            if (eventPopup.selectedHour < 0) eventPopup.selectedHour = 9
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Buttons
                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 50
                        radius: 12
                        color: "#2a2a3e"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                eventPopup.close()
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 50
                        radius: 12
                        color: accentColor

                        Text {
                            anchors.centerIn: parent
                            text: "Save"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (titleInput.text.trim() !== "") {
                                    Haptic.click()
                                    addEvent(titleInput.text.trim(), eventPopup.selectedHour, eventPopup.selectedMinute)
                                    eventPopup.close()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? accentPressed : accentColor
        z: 50

        Text {
            anchors.centerIn: parent
            text: selectedDay !== -1 ? "←" : "✕"
            font.pixelSize: 32
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: {
                Haptic.tap()
                if (selectedDay !== -1) {
                    selectedDay = -1
                } else {
                    Qt.quit()
                }
            }
        }
    }

    // Home indicator
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 8
        width: 120
        height: 4
        radius: 2
        color: "#333344"
    }
}
