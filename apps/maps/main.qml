import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtLocation 5.15
import QtPositioning 5.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Maps"
    color: "#0a0a0f"

    property real textScale: 2.0
    property var currentRoute: null
    property bool followGps: true
    property bool searchVisible: false
    property var searchResults: []
    property var favorites: []
    property string favoritesFile: "/home/droidian/.local/state/flick/map_favorites.json"

    Component.onCompleted: {
        loadConfig()
        loadFavorites()
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
    }

    function formatDistance(meters) {
        if (meters < 1000) return Math.round(meters) + " m"
        return (meters / 1000).toFixed(1) + " km"
    }

    // Position source for GPS
    PositionSource {
        id: positionSource
        updateInterval: 2000
        active: true

        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                gpsMarker.coordinate = position.coordinate
                if (followGps && !searchVisible) {
                    map.center = position.coordinate
                }
            }
        }
    }

    // Map plugin - OpenStreetMap
    Plugin {
        id: osmPlugin
        name: "osm"
        PluginParameter { name: "osm.mapping.custom.host"; value: "https://tile.openstreetmap.org/" }
        PluginParameter { name: "osm.useragent"; value: "FlickMaps/1.0" }
    }

    // Main map
    Map {
        id: map
        anchors.fill: parent
        plugin: osmPlugin
        center: QtPositioning.coordinate(37.7749, -122.4194) // Default SF
        zoomLevel: 14
        copyrightsVisible: false

        // Dark style tint overlay
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.15
            z: -1
        }

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
                    color: "#e94560"
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
        border.color: searchInput.focus ? "#e94560" : "#333344"
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
                color: searchBtnMouse.pressed ? "#c23a50" : "#e94560"
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
                        color: "#e94560"
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
                    color: favMouse.pressed ? "#c23a50" : "#e94560"

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
                color: clearRouteMouse.pressed ? "#c23a50" : "#e94560"
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
                    }
                }
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
