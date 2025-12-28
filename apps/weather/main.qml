import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Weather"
    color: "#0a0a0f"

    property real textScale: 2.0
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property string configFile: "/home/droidian/.local/state/flick/weather_config.json"

    // Weather data
    property real currentTemp: 0
    property string currentCondition: "Loading..."
    property string currentIcon: "🌡️"
    property real feelsLike: 0
    property int humidity: 0
    property real windSpeed: 0
    property string locationName: "Loading..."

    // Location (default to a common location, user can change)
    property real latitude: 40.7128
    property real longitude: -74.0060

    ListModel { id: forecastModel }
    ListModel { id: hourlyModel }

    Component.onCompleted: {
        loadConfig()
        loadWeatherConfig()
        fetchWeather()
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///home/droidian/.local/state/flick/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale) textScale = config.text_scale
            }
        } catch (e) {}
    }

    property bool hasLocation: false

    function loadWeatherConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.latitude && config.longitude && config.locationName) {
                    latitude = config.latitude
                    longitude = config.longitude
                    locationName = config.locationName
                    hasLocation = true
                } else {
                    hasLocation = false
                    locationName = "Location not set"
                }
            } else {
                hasLocation = false
                locationName = "Location not set"
            }
        } catch (e) {
            hasLocation = false
            locationName = "Location not set"
        }
    }

    property bool showLocationHelp: false

    function openSettings() {
        // Show help message
        showLocationHelp = true
    }

    function saveWeatherConfig() {
        var config = {
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        }
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + configFile, false)
        try {
            xhr.send(JSON.stringify(config, null, 2))
        } catch (e) {}
    }

    function fetchWeather() {
        if (!hasLocation) {
            currentCondition = "Set your location"
            currentIcon = "📍"
            return
        }
        var url = "https://api.open-meteo.com/v1/forecast?" +
                  "latitude=" + latitude +
                  "&longitude=" + longitude +
                  "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m" +
                  "&hourly=temperature_2m,weather_code" +
                  "&daily=weather_code,temperature_2m_max,temperature_2m_min" +
                  "&temperature_unit=fahrenheit" +
                  "&wind_speed_unit=mph" +
                  "&timezone=auto"

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    parseWeather(JSON.parse(xhr.responseText))
                } else {
                    currentCondition = "Unable to fetch weather"
                }
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function parseWeather(data) {
        // Current weather
        currentTemp = Math.round(data.current.temperature_2m)
        feelsLike = Math.round(data.current.apparent_temperature)
        humidity = data.current.relative_humidity_2m
        windSpeed = Math.round(data.current.wind_speed_10m)

        var code = data.current.weather_code
        var cond = getCondition(code)
        currentCondition = cond.text
        currentIcon = cond.icon

        // Hourly forecast (next 24 hours)
        hourlyModel.clear()
        var now = new Date()
        var currentHour = now.getHours()
        for (var i = currentHour; i < currentHour + 24 && i < data.hourly.time.length; i++) {
            var hourCode = data.hourly.weather_code[i]
            var hourCond = getCondition(hourCode)
            var time = new Date(data.hourly.time[i])
            hourlyModel.append({
                hour: formatHour(time),
                temp: Math.round(data.hourly.temperature_2m[i]),
                icon: hourCond.icon
            })
        }

        // Daily forecast
        forecastModel.clear()
        for (var j = 0; j < data.daily.time.length && j < 7; j++) {
            var dayCode = data.daily.weather_code[j]
            var dayCond = getCondition(dayCode)
            var date = new Date(data.daily.time[j])
            forecastModel.append({
                day: j === 0 ? "Today" : formatDay(date),
                high: Math.round(data.daily.temperature_2m_max[j]),
                low: Math.round(data.daily.temperature_2m_min[j]),
                icon: dayCond.icon,
                condition: dayCond.text
            })
        }
    }

    function getCondition(code) {
        // WMO weather codes
        var conditions = {
            0: {text: "Clear", icon: "☀️"},
            1: {text: "Mostly Clear", icon: "🌤️"},
            2: {text: "Partly Cloudy", icon: "⛅"},
            3: {text: "Overcast", icon: "☁️"},
            45: {text: "Foggy", icon: "🌫️"},
            48: {text: "Icy Fog", icon: "🌫️"},
            51: {text: "Light Drizzle", icon: "🌧️"},
            53: {text: "Drizzle", icon: "🌧️"},
            55: {text: "Heavy Drizzle", icon: "🌧️"},
            61: {text: "Light Rain", icon: "🌧️"},
            63: {text: "Rain", icon: "🌧️"},
            65: {text: "Heavy Rain", icon: "🌧️"},
            71: {text: "Light Snow", icon: "🌨️"},
            73: {text: "Snow", icon: "🌨️"},
            75: {text: "Heavy Snow", icon: "🌨️"},
            77: {text: "Snow Grains", icon: "🌨️"},
            80: {text: "Light Showers", icon: "🌦️"},
            81: {text: "Showers", icon: "🌦️"},
            82: {text: "Heavy Showers", icon: "🌦️"},
            85: {text: "Light Snow Showers", icon: "🌨️"},
            86: {text: "Snow Showers", icon: "🌨️"},
            95: {text: "Thunderstorm", icon: "⛈️"},
            96: {text: "Thunderstorm w/ Hail", icon: "⛈️"},
            99: {text: "Thunderstorm w/ Hail", icon: "⛈️"}
        }
        return conditions[code] || {text: "Unknown", icon: "🌡️"}
    }

    function formatHour(date) {
        var h = date.getHours()
        var ampm = h >= 12 ? "PM" : "AM"
        h = h % 12 || 12
        return h + ampm
    }

    function formatDay(date) {
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days[date.getDay()]
    }

    // Refresh timer
    Timer {
        interval: 1800000  // 30 minutes
        running: true
        repeat: true
        onTriggered: fetchWeather()
    }

    // Main content
    Flickable {
        anchors.fill: parent
        anchors.bottomMargin: 100
        contentHeight: contentCol.height + 40
        clip: true

        Column {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            spacing: 32

            // Header with location
            Row {
                width: parent.width
                height: 80
                spacing: 12

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 140

                    Text {
                        text: locationName
                        font.pixelSize: 28 * textScale
                        font.weight: Font.Medium
                        color: "#ffffff"
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: Qt.formatDateTime(new Date(), "dddd h:mm AP")
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }
                }

                Item { width: 1; height: 1 }  // spacer

                // Settings button
                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: settingsMouse.pressed ? Qt.darker(accentColor, 1.2) : accentColor
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            openSettings()
                        }
                    }
                }

                // Refresh button
                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: refreshMouse.pressed ? "#333344" : "#222233"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: hasLocation

                    Text {
                        anchors.centerIn: parent
                        text: "↻"
                        font.pixelSize: 24
                        color: "#888899"
                    }

                    MouseArea {
                        id: refreshMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            fetchWeather()
                        }
                    }
                }
            }

            // Current weather card
            Rectangle {
                width: parent.width
                height: 280
                radius: 24
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1a1a2e" }
                    GradientStop { position: 1.0; color: "#15151f" }
                }

                // No location prompt
                Column {
                    anchors.centerIn: parent
                    spacing: 16
                    visible: !hasLocation

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "📍"
                        font.pixelSize: 64
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No Location Set"
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Tap the settings button to set your location"
                        font.pixelSize: 14
                        color: "#888899"
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 160
                        height: 48
                        radius: 24
                        color: setLocMouse.pressed ? Qt.darker(accentColor, 1.2) : accentColor

                        Text {
                            anchors.centerIn: parent
                            text: "Set Location"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: setLocMouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                openSettings()
                            }
                        }
                    }
                }

                // Weather display (when location is set)
                Row {
                    anchors.fill: parent
                    anchors.margins: 32
                    visible: hasLocation

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            text: currentIcon
                            font.pixelSize: 80
                        }

                        Text {
                            text: currentCondition
                            font.pixelSize: 18 * textScale
                            color: "#ffffff"
                        }
                    }

                    Item { width: 40; height: 1 }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            text: currentTemp + "°"
                            font.pixelSize: 72 * textScale
                            font.weight: Font.ExtraLight
                            color: "#ffffff"
                        }

                        Text {
                            text: "Feels like " + feelsLike + "°"
                            font.pixelSize: 16 * textScale
                            color: "#888899"
                        }

                        Row {
                            spacing: 24

                            Text {
                                text: "💧 " + humidity + "%"
                                font.pixelSize: 14 * textScale
                                color: "#888899"
                            }

                            Text {
                                text: "💨 " + windSpeed + " mph"
                                font.pixelSize: 14 * textScale
                                color: "#888899"
                            }
                        }
                    }
                }
            }

            // Hourly forecast
            Text {
                text: "Hourly"
                font.pixelSize: 20 * textScale
                font.weight: Font.Medium
                color: "#ffffff"
                visible: hasLocation
            }

            Rectangle {
                width: parent.width
                height: 140
                radius: 16
                color: "#15151f"
                visible: hasLocation

                ListView {
                    anchors.fill: parent
                    anchors.margins: 16
                    orientation: ListView.Horizontal
                    spacing: 24
                    clip: true

                    model: hourlyModel

                    delegate: Column {
                        spacing: 8
                        width: 60

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: model.hour
                            font.pixelSize: 12 * textScale
                            color: "#888899"
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: model.icon
                            font.pixelSize: 28
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: model.temp + "°"
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                        }
                    }
                }
            }

            // Daily forecast
            Text {
                text: "7-Day Forecast"
                font.pixelSize: 20 * textScale
                font.weight: Font.Medium
                color: "#ffffff"
                visible: hasLocation
            }

            Rectangle {
                width: parent.width
                height: forecastCol.height + 32
                radius: 16
                color: "#15151f"
                visible: hasLocation

                Column {
                    id: forecastCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 8

                    Repeater {
                        model: forecastModel

                        Rectangle {
                            width: parent.width
                            height: 56
                            color: "transparent"

                            Row {
                                anchors.fill: parent
                                spacing: 16

                                Text {
                                    width: 80
                                    text: model.day
                                    font.pixelSize: 16 * textScale
                                    color: "#ffffff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: model.icon
                                    font.pixelSize: 28
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    width: 200
                                    text: model.condition
                                    font.pixelSize: 14 * textScale
                                    color: "#888899"
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                }

                                Item { width: parent.width - 480; height: 1 }

                                Text {
                                    text: model.high + "°"
                                    font.pixelSize: 18 * textScale
                                    color: "#ffffff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: model.low + "°"
                                    font.pixelSize: 18 * textScale
                                    color: "#666677"
                                    anchors.verticalCenter: parent.verticalCenter
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
        anchors.bottomMargin: 100
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? accentPressed : accentColor
        z: 10

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: { Haptic.tap(); Qt.quit() }
        }
    }

    // Home indicator
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 120
        height: 4
        radius: 2
        color: "#333344"
    }

    // Location help overlay
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: showLocationHelp ? 0.9 : 0
        visible: opacity > 0
        z: 100

        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: showLocationHelp = false
        }

        Column {
            anchors.centerIn: parent
            spacing: 24
            width: parent.width - 80

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "📍"
                font.pixelSize: 64
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Set Your Location"
                font.pixelSize: 28
                font.weight: Font.Medium
                color: "#ffffff"
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "To set your weather location:\n\n1. Go back to the home screen\n2. Open Settings\n3. Tap 'Time'\n4. Scroll down to 'Location'\n5. Search for your city"
                font.pixelSize: 18
                color: "#ccccdd"
                wrapMode: Text.WordWrap
                lineHeight: 1.4
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 140
                height: 52
                radius: 26
                color: closeMouse.pressed ? Qt.darker(accentColor, 1.2) : accentColor

                Text {
                    anchors.centerIn: parent
                    text: "Got it"
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    color: "#ffffff"
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        showLocationHelp = false
                    }
                }
            }
        }
    }
}
