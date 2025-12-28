import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Sandbox"
    color: "#0a0a0f"

    property real textScale: 2.0
    property int gridWidth: 135  // 1080 / 8 = 135 cells wide
    property int gridHeight: 270  // 2160 / 8 = 270 cells high (leaving room for UI)
    property int cellSize: 8

    // Particle types
    readonly property int EMPTY: 0
    readonly property int SAND: 1
    readonly property int WATER: 2
    readonly property int STONE: 3
    readonly property int FIRE: 4

    property int selectedType: SAND
    property bool isDrawing: false
    property int lastDrawX: -1
    property int lastDrawY: -1

    // Grid of particles (stored as flat array for performance)
    property var grid: []
    property var nextGrid: []

    Component.onCompleted: {
        loadConfig()
        initGrid()
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

    function initGrid() {
        grid = []
        nextGrid = []
        for (var i = 0; i < gridWidth * gridHeight; i++) {
            grid.push(EMPTY)
            nextGrid.push(EMPTY)
        }
    }

    function getCell(x, y) {
        if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return STONE
        return grid[y * gridWidth + x]
    }

    function setCell(x, y, type) {
        if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return
        grid[y * gridWidth + x] = type
    }

    function setNextCell(x, y, type) {
        if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return
        nextGrid[y * gridWidth + x] = type
    }

    function clearGrid() {
        for (var i = 0; i < grid.length; i++) {
            grid[i] = EMPTY
            nextGrid[i] = EMPTY
        }
        canvas.requestPaint()
    }

    function drawLine(x1, y1, x2, y2, type) {
        // Bresenham's line algorithm
        var dx = Math.abs(x2 - x1)
        var dy = Math.abs(y2 - y1)
        var sx = x1 < x2 ? 1 : -1
        var sy = y1 < y2 ? 1 : -1
        var err = dx - dy

        while (true) {
            setCell(x1, y1, type)

            if (x1 === x2 && y1 === y2) break

            var e2 = 2 * err
            if (e2 > -dy) {
                err -= dy
                x1 += sx
            }
            if (e2 < dx) {
                err += dx
                y1 += sy
            }
        }
    }

    function updateParticles() {
        // Copy current grid to next grid
        for (var i = 0; i < grid.length; i++) {
            nextGrid[i] = grid[i]
        }

        // Process particles from bottom to top, randomizing left/right
        for (var y = gridHeight - 2; y >= 0; y--) {
            var xStart = Math.random() < 0.5 ? 0 : gridWidth - 1
            var xEnd = xStart === 0 ? gridWidth : -1
            var xStep = xStart === 0 ? 1 : -1

            for (var x = xStart; x !== xEnd; x += xStep) {
                var current = getCell(x, y)
                if (current === EMPTY || current === STONE) continue

                if (current === SAND) {
                    // Sand falls down, slides diagonally
                    var below = getCell(x, y + 1)
                    if (below === EMPTY) {
                        setNextCell(x, y + 1, SAND)
                        setNextCell(x, y, EMPTY)
                    } else if (below === WATER) {
                        // Sand sinks in water
                        setNextCell(x, y + 1, SAND)
                        setNextCell(x, y, WATER)
                    } else {
                        // Try diagonal fall
                        var left = getCell(x - 1, y + 1)
                        var right = getCell(x + 1, y + 1)
                        if (left === EMPTY && right === EMPTY) {
                            var dir = Math.random() < 0.5 ? -1 : 1
                            setNextCell(x + dir, y + 1, SAND)
                            setNextCell(x, y, EMPTY)
                        } else if (left === EMPTY) {
                            setNextCell(x - 1, y + 1, SAND)
                            setNextCell(x, y, EMPTY)
                        } else if (right === EMPTY) {
                            setNextCell(x + 1, y + 1, SAND)
                            setNextCell(x, y, EMPTY)
                        }
                    }
                } else if (current === WATER) {
                    // Water flows down and spreads
                    var below = getCell(x, y + 1)
                    if (below === EMPTY) {
                        setNextCell(x, y + 1, WATER)
                        setNextCell(x, y, EMPTY)
                    } else if (below === FIRE) {
                        // Water extinguishes fire
                        setNextCell(x, y + 1, EMPTY)
                        setNextCell(x, y, EMPTY)
                    } else {
                        // Try to spread horizontally
                        var left = getCell(x - 1, y)
                        var right = getCell(x + 1, y)
                        var leftBelow = getCell(x - 1, y + 1)
                        var rightBelow = getCell(x + 1, y + 1)

                        // Prefer flowing down diagonally
                        if (leftBelow === EMPTY && rightBelow === EMPTY) {
                            var dir = Math.random() < 0.5 ? -1 : 1
                            setNextCell(x + dir, y + 1, WATER)
                            setNextCell(x, y, EMPTY)
                        } else if (leftBelow === EMPTY) {
                            setNextCell(x - 1, y + 1, WATER)
                            setNextCell(x, y, EMPTY)
                        } else if (rightBelow === EMPTY) {
                            setNextCell(x + 1, y + 1, WATER)
                            setNextCell(x, y, EMPTY)
                        } else if (left === EMPTY && right === EMPTY) {
                            var dir = Math.random() < 0.5 ? -1 : 1
                            setNextCell(x + dir, y, WATER)
                            setNextCell(x, y, EMPTY)
                        } else if (left === EMPTY) {
                            setNextCell(x - 1, y, WATER)
                            setNextCell(x, y, EMPTY)
                        } else if (right === EMPTY) {
                            setNextCell(x + 1, y, WATER)
                            setNextCell(x, y, EMPTY)
                        }
                    }
                } else if (current === FIRE) {
                    // Fire rises and spreads
                    var lifetime = Math.random()
                    if (lifetime < 0.05) {
                        // Fire dies out randomly
                        setNextCell(x, y, EMPTY)
                    } else {
                        var above = getCell(x, y - 1)
                        if (above === EMPTY && Math.random() < 0.7) {
                            setNextCell(x, y - 1, FIRE)
                            if (Math.random() < 0.3) {
                                setNextCell(x, y, EMPTY)
                            }
                        } else {
                            // Spread horizontally
                            var spreadDir = Math.random() < 0.5 ? -1 : 1
                            var target = getCell(x + spreadDir, y)
                            if (target === EMPTY && Math.random() < 0.2) {
                                setNextCell(x + spreadDir, y, FIRE)
                            } else if (target === SAND && Math.random() < 0.1) {
                                setNextCell(x + spreadDir, y, FIRE)
                            }
                        }
                    }
                }
            }
        }

        // Swap grids
        var temp = grid
        grid = nextGrid
        nextGrid = temp

        canvas.requestPaint()
    }

    function getParticleColor(type) {
        switch (type) {
            case SAND: return "#d4a574"
            case WATER: return "#4a90e2"
            case STONE: return "#666666"
            case FIRE: return Math.random() < 0.5 ? "#ff6b35" : "#f7931e"
            default: return "#0a0a0f"
        }
    }

    // Main simulation canvas
    Canvas {
        id: canvas
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: controls.top

        onPaint: {
            var ctx = getContext("2d")
            ctx.fillStyle = "#0a0a0f"
            ctx.fillRect(0, 0, width, height)

            // Draw particles
            for (var y = 0; y < gridHeight; y++) {
                for (var x = 0; x < gridWidth; x++) {
                    var cell = getCell(x, y)
                    if (cell !== EMPTY) {
                        ctx.fillStyle = getParticleColor(cell)
                        ctx.fillRect(x * cellSize, y * cellSize, cellSize, cellSize)
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent

            onPressed: {
                isDrawing = true
                var gridX = Math.floor(mouse.x / cellSize)
                var gridY = Math.floor(mouse.y / cellSize)
                setCell(gridX, gridY, selectedType)
                lastDrawX = gridX
                lastDrawY = gridY
                canvas.requestPaint()
                Haptic.tap()
            }

            onPositionChanged: {
                if (isDrawing) {
                    var gridX = Math.floor(mouse.x / cellSize)
                    var gridY = Math.floor(mouse.y / cellSize)
                    if (gridX !== lastDrawX || gridY !== lastDrawY) {
                        drawLine(lastDrawX, lastDrawY, gridX, gridY, selectedType)
                        lastDrawX = gridX
                        lastDrawY = gridY
                        canvas.requestPaint()
                    }
                }
            }

            onReleased: {
                isDrawing = false
            }
        }
    }

    // Control panel at bottom
    Rectangle {
        id: controls
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: 100
        height: 180
        color: "#15151f"

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "Particle Type"
                font.pixelSize: 14 * textScale
                color: "#888899"
            }

            Row {
                spacing: 12

                Rectangle {
                    width: 120
                    height: 80
                    radius: 12
                    color: selectedType === SAND ? "#e94560" : "#222233"
                    border.color: selectedType === SAND ? "#ffffff" : "transparent"
                    border.width: 2

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: "#d4a574"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Sand"
                            font.pixelSize: 12 * textScale
                            color: "#ffffff"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            selectedType = SAND
                            Haptic.tap()
                        }
                    }
                }

                Rectangle {
                    width: 120
                    height: 80
                    radius: 12
                    color: selectedType === WATER ? "#e94560" : "#222233"
                    border.color: selectedType === WATER ? "#ffffff" : "transparent"
                    border.width: 2

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: "#4a90e2"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Water"
                            font.pixelSize: 12 * textScale
                            color: "#ffffff"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            selectedType = WATER
                            Haptic.tap()
                        }
                    }
                }

                Rectangle {
                    width: 120
                    height: 80
                    radius: 12
                    color: selectedType === STONE ? "#e94560" : "#222233"
                    border.color: selectedType === STONE ? "#ffffff" : "transparent"
                    border.width: 2

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: "#666666"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Stone"
                            font.pixelSize: 12 * textScale
                            color: "#ffffff"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            selectedType = STONE
                            Haptic.tap()
                        }
                    }
                }

                Rectangle {
                    width: 120
                    height: 80
                    radius: 12
                    color: selectedType === FIRE ? "#e94560" : "#222233"
                    border.color: selectedType === FIRE ? "#ffffff" : "transparent"
                    border.width: 2

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#ff6b35" }
                                GradientStop { position: 1.0; color: "#f7931e" }
                            }
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Fire"
                            font.pixelSize: 12 * textScale
                            color: "#ffffff"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            selectedType = FIRE
                            Haptic.tap()
                        }
                    }
                }

                Rectangle {
                    width: 120
                    height: 80
                    radius: 12
                    color: clearMouse.pressed ? "#333344" : "#222233"

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "Clear"
                            font.pixelSize: 16 * textScale
                            font.weight: Font.Medium
                            color: "#ffffff"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        onClicked: {
                            clearGrid()
                            Haptic.tap()
                        }
                    }
                }
            }
        }
    }

    // Simulation timer (60fps)
    Timer {
        interval: 16  // ~60 FPS
        running: true
        repeat: true
        onTriggered: updateParticles()
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 300
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? "#c23a50" : "#e94560"
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
}
