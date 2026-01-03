import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtLocation 5.15
import QtPositioning 5.15
import "../shared"

Window {
    id: root
    visible: true
    width: 720
    height: 1600
    title: "Flick Maps"
    color: "#0a0a0f"

    property real textScale: 2.0
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property var currentRoute: null
    property bool followGps: true
    property bool searchVisible: false
    property var searchResults: []
    property var favorites: []
    property string favoritesFile: Theme.stateDir + "/map_favorites.json"

    // Navigation state
    property bool navigating: false
    property var routeSteps: []
    property int currentStepIndex: 0
    property real distanceToNextStep: 0
    property string currentInstruction: ""
    property string nextInstruction: ""
    property bool voiceEnabled: true
    property var lastSpokenDistance: -1  // Track what distance we last spoke at

    // GPS state
    property bool hasGpsFix: false
    property bool gpsWaiting: true

    Component.onCompleted: {
        loadConfig()
        loadFavorites()
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + Theme.stateDir + "/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale) textScale = config.text_scale
            }
        } catch (e) {}
    }

    function loadFavorites() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + favoritesFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                favorites = data.favorites || []
            }
        } catch (e) { favorites = [] }
    }

    function saveFavorites() {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + favoritesFile)
        xhr.send(JSON.stringify({favorites: favorites}, null, 2))
    }

    function addFavorite(name, lat, lon) {
        favorites.push({name: name, lat: lat, lon: lon})
        saveFavorites()
    }

    function searchLocation(query) {
        var xhr = new XMLHttpRequest()
        var url = "https://nominatim.openstreetmap.org/search?q=" + encodeURIComponent(query) + "&format=json&limit=10"
        xhr.open("GET", url)
        xhr.setRequestHeader("User-Agent", "FlickMaps/1.0")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                try {
                    searchResults = JSON.parse(xhr.responseText)
                    searchResultsView.model = searchResults
                } catch (e) { searchResults = [] }
            }
        }
        xhr.send()
    }

    function getRoute(fromLat, fromLon, toLat, toLon) {
        var xhr = new XMLHttpRequest()
        var url = "https://router.project-osrm.org/route/v1/driving/" +
                  fromLon + "," + fromLat + ";" + toLon + "," + toLat +
                  "?overview=full&geometries=geojson&steps=true"
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    if (data.routes && data.routes.length > 0) {
                        var route = data.routes[0]
                        currentRoute = route
                        drawRoute(route.geometry.coordinates)
                        showRouteInfo(route)
                    }
                } catch (e) { console.log("Route error:", e) }
            }
        }
        xhr.send()
    }

    function drawRoute(coords) {
        routePath.path = []
        var path = []
        for (var i = 0; i < coords.length; i++) {
            path.push(QtPositioning.coordinate(coords[i][1], coords[i][0]))
        }
        routePath.path = path
    }

    function showRouteInfo(route) {
        var dist = route.distance / 1000
        var dur = Math.round(route.duration / 60)
        routeInfoText.text = dist.toFixed(1) + " km • " + dur + " min"
        routeInfoPanel.visible = true
        // Start voice navigation
        startNavigation(route)
    }

    function formatDistance(meters) {
        if (meters < 1000) return Math.round(meters) + " m"
        return (meters / 1000).toFixed(1) + " km"
    }

    // Voice navigation functions
    property string speakQueueFile: Theme.stateDir + "/speak_queue"

    function speak(text) {
        if (!voiceEnabled || !text) return
        // Write to speak queue file - background process will pick it up
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + speakQueueFile)
        xhr.send(text + "\n")
    }

    function parseOsrmManeuver(step) {
        var maneuver = step.maneuver
        var type = maneuver.type
        var modifier = maneuver.modifier || ""
        var name = step.name || "the road"

        // Build spoken instruction
        var instruction = ""

        switch (type) {
            case "depart":
                instruction = "Start by heading " + (modifier || "forward")
                if (name) instruction += " on " + name
                break
            case "arrive":
                if (modifier === "left") instruction = "Your destination is on the left"
                else if (modifier === "right") instruction = "Your destination is on the right"
                else instruction = "You have arrived at your destination"
                break
            case "turn":
                instruction = "Turn " + modifier
                if (name && name !== "") instruction += " onto " + name
                break
            case "merge":
                instruction = "Merge " + modifier
                if (name) instruction += " onto " + name
                break
            case "on ramp":
            case "off ramp":
                instruction = "Take the ramp " + modifier
                break
            case "fork":
                instruction = "Keep " + modifier + " at the fork"
                break
            case "end of road":
                instruction = "At the end of the road, turn " + modifier
                break
            case "continue":
                instruction = "Continue " + (modifier || "straight")
                if (name && name !== "") instruction += " on " + name
                break
            case "roundabout":
                var exit = maneuver.exit || 1
                instruction = "At the roundabout, take exit " + exit
                break
            case "rotary":
                instruction = "At the rotary, take exit " + (maneuver.exit || 1)
                break
            case "new name":
                instruction = "Continue onto " + name
                break
            case "notification":
                instruction = step.notification || ""
                break
            default:
                if (modifier) {
                    instruction = modifier.charAt(0).toUpperCase() + modifier.slice(1)
                    if (name) instruction += " onto " + name
                } else {
                    instruction = "Continue"
                }
        }

        return instruction
    }

    function getShortInstruction(step) {
        var maneuver = step.maneuver
        var type = maneuver.type
        var modifier = maneuver.modifier || ""

        switch (type) {
            case "turn":
                if (modifier.indexOf("left") >= 0) return "↰ Turn left"
                if (modifier.indexOf("right") >= 0) return "↱ Turn right"
                return "↑ " + modifier
            case "arrive":
                return "🏁 Arrive"
            case "depart":
                return "▶ Start"
            case "merge":
                return "⤭ Merge " + modifier
            case "fork":
                if (modifier.indexOf("left") >= 0) return "⤿ Keep left"
                if (modifier.indexOf("right") >= 0) return "⤾ Keep right"
                return "Fork " + modifier
            case "roundabout":
            case "rotary":
                return "⟳ Roundabout exit " + (maneuver.exit || 1)
            case "continue":
            case "new name":
                return "↑ Continue"
            default:
                if (modifier.indexOf("left") >= 0) return "↰ " + modifier
                if (modifier.indexOf("right") >= 0) return "↱ " + modifier
                return "↑ " + (modifier || type)
        }
    }

    function startNavigation(route) {
        if (!route || !route.legs || route.legs.length === 0) return

        // Extract steps from all legs
        routeSteps = []
        for (var i = 0; i < route.legs.length; i++) {
            var leg = route.legs[i]
            for (var j = 0; j < leg.steps.length; j++) {
                routeSteps.push(leg.steps[j])
            }
        }

        if (routeSteps.length === 0) return

        currentStepIndex = 0
        navigating = true
        followGps = true
        lastSpokenDistance = -1

        updateCurrentStep()

        // Initial announcement
        speak("Starting navigation. " + currentInstruction)
    }

    function updateCurrentStep() {
        if (currentStepIndex >= routeSteps.length) {
            // Navigation complete
            speak("You have arrived at your destination")
            stopNavigation()
            return
        }

        var step = routeSteps[currentStepIndex]
        currentInstruction = parseOsrmManeuver(step)

        if (currentStepIndex + 1 < routeSteps.length) {
            nextInstruction = getShortInstruction(routeSteps[currentStepIndex + 1])
        } else {
            nextInstruction = ""
        }
    }

    function stopNavigation() {
        navigating = false
        routeSteps = []
        currentStepIndex = 0
        currentInstruction = ""
        nextInstruction = ""
        lastSpokenDistance = -1
    }

    function calculateDistanceToStep(pos, stepIndex) {
        if (stepIndex >= routeSteps.length) return 0

        var step = routeSteps[stepIndex]
        var maneuverLat = step.maneuver.location[1]
        var maneuverLon = step.maneuver.location[0]

        // Haversine formula for distance
        var R = 6371000 // Earth radius in meters
        var lat1 = pos.latitude * Math.PI / 180
        var lat2 = maneuverLat * Math.PI / 180
        var dLat = (maneuverLat - pos.latitude) * Math.PI / 180
        var dLon = (maneuverLon - pos.longitude) * Math.PI / 180

        var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(lat1) * Math.cos(lat2) *
                Math.sin(dLon/2) * Math.sin(dLon/2)
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))

        return R * c
    }

    function updateNavigation(pos) {
        if (!navigating || routeSteps.length === 0) return

        // Calculate distance to next maneuver
        distanceToNextStep = calculateDistanceToStep(pos, currentStepIndex)

        // Check if we've passed the current step (within 30m threshold)
        if (distanceToNextStep < 30 && currentStepIndex < routeSteps.length - 1) {
            currentStepIndex++
            updateCurrentStep()
            lastSpokenDistance = -1

            // Announce next step immediately
            if (currentStepIndex < routeSteps.length) {
                speak(currentInstruction)
            }
            return
        }

        // Voice announcements at key distances
        checkVoiceAnnouncement(distanceToNextStep)
    }

    function checkVoiceAnnouncement(distance) {
        // Announce at 500m, 200m, 100m, and 50m before turn
        var thresholds = [500, 200, 100, 50]

        for (var i = 0; i < thresholds.length; i++) {
            var threshold = thresholds[i]
            // Check if we crossed this threshold
            if (distance < threshold && (lastSpokenDistance < 0 || lastSpokenDistance >= threshold)) {
                var prefix = ""
                if (threshold >= 1000) {
                    prefix = "In " + (threshold / 1000).toFixed(1) + " kilometers, "
                } else {
                    prefix = "In " + threshold + " meters, "
                }
                speak(prefix + currentInstruction)
                lastSpokenDistance = distance
                break
            }
        }
    }

    // Position source for GPS
    PositionSource {
        id: positionSource
        updateInterval: 1000  // More frequent updates during navigation
        active: true
        preferredPositioningMethods: PositionSource.AllPositioningMethods

        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                gpsWaiting = false
                gpsMarker.coordinate = position.coordinate

                // Auto-center on first GPS fix
                if (!hasGpsFix) {
                    hasGpsFix = true
                    map.center = position.coordinate
                    map.zoomLevel = 15
                    console.log("GPS fix acquired:", position.coordinate.latitude, position.coordinate.longitude)
                }

                if (followGps && !searchVisible) {
                    map.center = position.coordinate
                }
                // Update navigation if active
                if (navigating) {
                    updateNavigation(position.coordinate)
                }
            }
        }

        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError) {
                console.log("GPS error:", sourceError)
            }
        }

        Component.onCompleted: {
            console.log("PositionSource initialized, valid:", valid, "name:", name)
            if (valid) {
                start()
            }
        }
    }

    // Map plugin - OpenStreetMap
    Plugin {
        id: osmPlugin
        name: "osm"
        PluginParameter { name: "osm.mapping.highdpi_tiles"; value: "true" }
        PluginParameter { name: "osm.useragent"; value: "FlickMaps/1.0 (Linux; Droidian)" }
    }

    // Main map
    Map {
        id: map
        anchors.fill: parent
        plugin: osmPlugin
        center: QtPositioning.coordinate(37.7749, -122.4194) // Default SF
        zoomLevel: 14
        copyrightsVisible: false

        // GPS marker
        MapQuickItem {
            id: gpsMarker
            coordinate: positionSource.position.coordinate
            anchorPoint.x: gpsIcon.width / 2
            anchorPoint.y: gpsIcon.height / 2
            z: 100

            sourceItem: Rectangle {
                id: gpsIcon
                width: 24
                height: 24
                radius: 12
                color: "#4285f4"
                border.color: "#ffffff"
                border.width: 3

                // Accuracy circle pulse
                Rectangle {
                    anchors.centerIn: parent
                    width: 60
                    height: 60
                    radius: 30
                    color: "transparent"
                    border.color: "#4285f4"
                    border.width: 2
                    opacity: 0.4

                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.5; to: 1.2; duration: 1500 }
                        NumberAnimation { from: 1.2; to: 0.5; duration: 1500 }
                    }
                }
            }
        }

        // Route line
        MapPolyline {
            id: routePath
            line.width: 6
            line.color: "#4285f4"
            path: []
        }

        // Destination marker
        MapQuickItem {
            id: destMarker
            visible: routePath.path.length > 0
            coordinate: routePath.path.length > 0 ? routePath.path[routePath.path.length - 1] : QtPositioning.coordinate(0, 0)
            anchorPoint.x: 16
            anchorPoint.y: 40
            z: 99

            sourceItem: Text {
                text: "📍"
                font.pixelSize: 40
            }
        }

        // Search result markers
        MapItemView {
            model: searchVisible ? searchResults : []
            delegate: MapQuickItem {
                coordinate: QtPositioning.coordinate(parseFloat(modelData.lat), parseFloat(modelData.lon))
                anchorPoint.x: 12
                anchorPoint.y: 12

                sourceItem: Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: accentColor
                    border.color: "#ffffff"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: (index + 1).toString()
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }

        // Favorite markers
        MapItemView {
            model: favorites
            delegate: MapQuickItem {
                coordinate: QtPositioning.coordinate(modelData.lat, modelData.lon)
                anchorPoint.x: 16
                anchorPoint.y: 40

                sourceItem: Text {
                    text: "⭐"
                    font.pixelSize: 32
                }
            }
        }

        // Touch handling
        MouseArea {
            anchors.fill: parent
            onPressed: followGps = false
            onDoubleClicked: {
                map.zoomLevel += 1
            }
        }

        // Pinch zoom
        PinchArea {
            anchors.fill: parent
            onPinchUpdated: {
                map.zoomLevel += pinch.scale - pinch.previousScale
                followGps = false
            }
        }
    }

    // Search bar
    Rectangle {
        id: searchBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        anchors.topMargin: 40
        height: 56
        radius: 28
        color: "#1a1a2e"
        border.color: searchInput.focus ? accentColor : "#333344"
        border.width: 2
        z: 100

        Row {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 12

            // Menu/back button
            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: menuMouse.pressed ? "#333344" : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: searchVisible ? "←" : "☰"
                    font.pixelSize: 24
                    color: "#ffffff"
                }

                MouseArea {
                    id: menuMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        if (searchVisible) {
                            searchVisible = false
                            searchInput.text = ""
                            searchResults = []
                        } else {
                            favoritesPanel.visible = !favoritesPanel.visible
                        }
                    }
                }
            }

            // Search input
            TextInput {
                id: searchInput
                width: parent.width - 120
                height: 40
                anchors.verticalCenter: parent.verticalCenter
                color: "#ffffff"
                font.pixelSize: 18
                verticalAlignment: TextInput.AlignVCenter
                clip: true

                Text {
                    anchors.fill: parent
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search places..."
                    color: "#666677"
                    font.pixelSize: 18
                    verticalAlignment: Text.AlignVCenter
                    visible: !searchInput.text && !searchInput.focus
                }

                onTextChanged: {
                    if (text.length > 2) {
                        searchTimer.restart()
                    }
                }

                onFocusChanged: {
                    if (focus) searchVisible = true
                }

                onAccepted: {
                    if (text.length > 0) searchLocation(text)
                }

                Timer {
                    id: searchTimer
                    interval: 500
                    onTriggered: searchLocation(searchInput.text)
                }
            }

            // Search button
            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: searchBtnMouse.pressed ? accentPressed : accentColor
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: "🔍"
                    font.pixelSize: 20
                }

                MouseArea {
                    id: searchBtnMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        if (searchInput.text.length > 0) searchLocation(searchInput.text)
                    }
                }
            }
        }
    }

    // Search results panel
    Rectangle {
        id: searchResultsPanel
        anchors.top: searchBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        anchors.topMargin: 8
        height: Math.min(400, searchResults.length * 72 + 20)
        radius: 16
        color: "#1a1a2e"
        visible: searchVisible && searchResults.length > 0
        z: 99

        ListView {
            id: searchResultsView
            anchors.fill: parent
            anchors.margins: 10
            clip: true
            model: searchResults

            delegate: Rectangle {
                width: searchResultsView.width
                height: 64
                color: resultMouse.pressed ? "#333344" : "transparent"
                radius: 8

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: accentColor
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: (index + 1).toString()
                            color: "#ffffff"
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 100
                        spacing: 4

                        Text {
                            text: modelData.display_name ? modelData.display_name.split(",")[0] : ""
                            color: "#ffffff"
                            font.pixelSize: 16
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: modelData.display_name ? modelData.display_name.split(",").slice(1, 3).join(",") : ""
                            color: "#888899"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }

                MouseArea {
                    id: resultMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        var lat = parseFloat(modelData.lat)
                        var lon = parseFloat(modelData.lon)
                        map.center = QtPositioning.coordinate(lat, lon)
                        map.zoomLevel = 16
                        searchVisible = false
                        followGps = false

                        // Show route option
                        selectedPlace = modelData
                        placePanel.visible = true
                    }
                }
            }
        }
    }

    property var selectedPlace: null

    // Place detail panel
    Rectangle {
        id: placePanel
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 200
        color: "#1a1a2e"
        radius: 24
        visible: false
        z: 100

        // Handle
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            width: 40
            height: 4
            radius: 2
            color: "#333344"
        }

        Column {
            anchors.fill: parent
            anchors.margins: 24
            anchors.topMargin: 32
            spacing: 16

            Text {
                text: selectedPlace ? selectedPlace.display_name.split(",")[0] : ""
                color: "#ffffff"
                font.pixelSize: 22
                font.weight: Font.Medium
                width: parent.width
                elide: Text.ElideRight
            }

            Text {
                text: selectedPlace ? selectedPlace.display_name.split(",").slice(1, 4).join(",") : ""
                color: "#888899"
                font.pixelSize: 14
                width: parent.width
                elide: Text.ElideRight
            }

            Row {
                spacing: 16
                anchors.horizontalCenter: parent.horizontalCenter

                // Directions button
                Rectangle {
                    width: 140
                    height: 48
                    radius: 24
                    color: dirMouse.pressed ? "#3574d4" : "#4285f4"

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Text { text: "🧭"; font.pixelSize: 20 }
                        Text { text: "Directions"; color: "#ffffff"; font.pixelSize: 16 }
                    }

                    MouseArea {
                        id: dirMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            if (positionSource.position.latitudeValid && selectedPlace) {
                                getRoute(
                                    positionSource.position.coordinate.latitude,
                                    positionSource.position.coordinate.longitude,
                                    parseFloat(selectedPlace.lat),
                                    parseFloat(selectedPlace.lon)
                                )
                                placePanel.visible = false
                            }
                        }
                    }
                }

                // Favorite button
                Rectangle {
                    width: 140
                    height: 48
                    radius: 24
                    color: favMouse.pressed ? accentPressed : accentColor

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Text { text: "⭐"; font.pixelSize: 20 }
                        Text { text: "Save"; color: "#ffffff"; font.pixelSize: 16 }
                    }

                    MouseArea {
                        id: favMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            if (selectedPlace) {
                                addFavorite(
                                    selectedPlace.display_name.split(",")[0],
                                    parseFloat(selectedPlace.lat),
                                    parseFloat(selectedPlace.lon)
                                )
                            }
                            placePanel.visible = false
                        }
                    }
                }

                // Close button
                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: closeMouse.pressed ? "#333344" : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: "#ffffff"
                        font.pixelSize: 20
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            placePanel.visible = false
                        }
                    }
                }
            }
        }
    }

    // Route info panel
    Rectangle {
        id: routeInfoPanel
        anchors.bottom: controlsColumn.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 16
        width: routeInfoRow.width + 48
        height: 56
        radius: 28
        color: "#1a1a2e"
        visible: false
        z: 99

        Row {
            id: routeInfoRow
            anchors.centerIn: parent
            spacing: 16

            Text {
                text: "🚗"
                font.pixelSize: 24
            }

            Text {
                id: routeInfoText
                color: "#ffffff"
                font.pixelSize: 18
            }

            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: clearRouteMouse.pressed ? accentPressed : accentColor
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "#ffffff"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: clearRouteMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        routePath.path = []
                        routeInfoPanel.visible = false
                        currentRoute = null
                        stopNavigation()
                    }
                }
            }
        }
    }

    // Navigation instructions panel (shown during active navigation)
    Rectangle {
        id: navPanel
        anchors.top: searchBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        anchors.topMargin: 8
        height: 140
        radius: 16
        color: "#1a1a2e"
        visible: navigating
        z: 100

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            // Distance to next maneuver
            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    text: formatDistance(distanceToNextStep)
                    color: "#4285f4"
                    font.pixelSize: 36
                    font.weight: Font.Bold
                }

                // Voice toggle button
                Rectangle {
                    width: 44
                    height: 44
                    radius: 22
                    color: voiceToggleMouse.pressed ? "#333344" : (voiceEnabled ? "#4285f4" : "#2a2a3e")
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: voiceEnabled ? "🔊" : "🔇"
                        font.pixelSize: 20
                    }

                    MouseArea {
                        id: voiceToggleMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            voiceEnabled = !voiceEnabled
                            if (voiceEnabled) {
                                speak("Voice navigation enabled")
                            }
                        }
                    }
                }
            }

            // Current instruction
            Text {
                text: currentInstruction
                color: "#ffffff"
                font.pixelSize: 18
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 2
            }

            // Next instruction preview
            Text {
                text: nextInstruction ? "Then: " + nextInstruction : ""
                color: "#888899"
                font.pixelSize: 14
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: nextInstruction !== ""
            }
        }
    }

    // Favorites panel
    Rectangle {
        id: favoritesPanel
        anchors.top: searchBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        anchors.topMargin: 8
        height: Math.min(300, favorites.length * 56 + 60)
        radius: 16
        color: "#1a1a2e"
        visible: false
        z: 99

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            Text {
                text: "⭐ Saved Places"
                color: "#ffffff"
                font.pixelSize: 18
                font.weight: Font.Medium
            }

            ListView {
                width: parent.width
                height: parent.height - 40
                clip: true
                model: favorites

                delegate: Rectangle {
                    width: parent ? parent.width : 0
                    height: 48
                    color: favItemMouse.pressed ? "#333344" : "transparent"
                    radius: 8

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: "#ffffff"
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: favItemMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            map.center = QtPositioning.coordinate(modelData.lat, modelData.lon)
                            map.zoomLevel = 16
                            favoritesPanel.visible = false
                            followGps = false
                        }
                    }
                }
            }
        }
    }

    // Map controls
    Column {
        id: controlsColumn
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 100
        spacing: 12
        z: 99

        // Zoom in
        Rectangle {
            width: 56
            height: 56
            radius: 28
            color: zoomInMouse.pressed ? "#333344" : "#1a1a2e"
            border.color: "#333344"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "+"
                font.pixelSize: 28
                color: "#ffffff"
            }

            MouseArea {
                id: zoomInMouse
                anchors.fill: parent
                onClicked: { Haptic.tap(); map.zoomLevel += 1 }
            }
        }

        // Zoom out
        Rectangle {
            width: 56
            height: 56
            radius: 28
            color: zoomOutMouse.pressed ? "#333344" : "#1a1a2e"
            border.color: "#333344"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "−"
                font.pixelSize: 28
                color: "#ffffff"
            }

            MouseArea {
                id: zoomOutMouse
                anchors.fill: parent
                onClicked: { Haptic.tap(); map.zoomLevel -= 1 }
            }
        }

        // GPS center
        Rectangle {
            width: 56
            height: 56
            radius: 28
            color: followGps ? "#4285f4" : (gpsMouse.pressed ? "#333344" : "#1a1a2e")
            border.color: followGps ? "#4285f4" : "#333344"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "◎"
                font.pixelSize: 24
                color: "#ffffff"
            }

            MouseArea {
                id: gpsMouse
                anchors.fill: parent
                onClicked: {
                    Haptic.tap()
                    followGps = true
                    if (positionSource.position.latitudeValid) {
                        map.center = positionSource.position.coordinate
                    }
                }
            }
        }

        // Compass / North
        Rectangle {
            width: 56
            height: 56
            radius: 28
            color: compassMouse.pressed ? "#333344" : "#1a1a2e"
            border.color: "#333344"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "🧭"
                font.pixelSize: 24
                rotation: -map.bearing
            }

            MouseArea {
                id: compassMouse
                anchors.fill: parent
                onClicked: { Haptic.tap(); map.bearing = 0 }
            }
        }
    }

    // Map type toggle (bottom left)
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.bottomMargin: 100
        width: 56
        height: 56
        radius: 28
        color: layerMouse.pressed ? "#333344" : "#1a1a2e"
        border.color: "#333344"
        border.width: 1
        z: 99

        Text {
            anchors.centerIn: parent
            text: "🗺️"
            font.pixelSize: 24
        }

        MouseArea {
            id: layerMouse
            anchors.fill: parent
            onClicked: {
                Haptic.tap()
                // Toggle map type - cycle through available types
                var types = map.supportedMapTypes
                if (types.length > 1) {
                    var currentIdx = 0
                    for (var i = 0; i < types.length; i++) {
                        if (types[i].name === map.activeMapType.name) {
                            currentIdx = i
                            break
                        }
                    }
                    map.activeMapType = types[(currentIdx + 1) % types.length]
                }
            }
        }
    }

    // GPS status indicator (bottom center, above home indicator)
    Rectangle {
        id: gpsStatusBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        width: gpsStatusRow.width + 24
        height: 36
        radius: 18
        color: "#1a1a2e"
        visible: gpsWaiting || !hasGpsFix
        z: 100

        Row {
            id: gpsStatusRow
            anchors.centerIn: parent
            spacing: 8

            // Animated GPS icon
            Text {
                text: "📡"
                font.pixelSize: 18

                SequentialAnimation on opacity {
                    running: gpsWaiting
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.3; duration: 500 }
                    NumberAnimation { from: 0.3; to: 1.0; duration: 500 }
                }
            }

            Text {
                text: gpsWaiting ? "Locating..." : "No GPS signal"
                color: "#ffffff"
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // GPS accuracy indicator (shown when we have a fix)
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 80
        anchors.bottomMargin: 100
        width: gpsInfoRow.width + 16
        height: 32
        radius: 16
        color: "#1a1a2e"
        visible: hasGpsFix && !navigating
        z: 99

        Row {
            id: gpsInfoRow
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: positionSource.position.horizontalAccuracyValid &&
                       positionSource.position.horizontalAccuracy < 50 ? "#4ade80" : "#fbbf24"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: positionSource.position.horizontalAccuracyValid ?
                      "±" + Math.round(positionSource.position.horizontalAccuracy) + "m" : "GPS"
                color: "#ffffff"
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
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
        z: 100
    }
}
