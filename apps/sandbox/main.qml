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
    property int gridWidth: 36
    property int gridHeight: 64
    property int cellSize: 30

    readonly property int tEmpty: 0
    readonly property int tSand: 1
    readonly property int tWater: 2
    readonly property int tStone: 3
    readonly property int tFire: 4
    readonly property int tOil: 5
    readonly property int tLava: 6
    readonly property int tSteam: 7
    readonly property int tWood: 8
    readonly property int tIce: 9
    readonly property int tAcid: 10
    readonly property int tSmoke: 11
    readonly property int tPlant: 12
    readonly property int tGunpowder: 13
    readonly property int tSalt: 14

    property int selectedType: tSand
    property int brushSize: 2
    property bool isDrawing: false
    property int lastDrawX: -1
    property int lastDrawY: -1

    property var grid: []
    property var life: []
    property int frameCount: 0

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
        var size = gridWidth * gridHeight
        grid = []
        life = []
        for (var i = 0; i < size; i++) {
            grid.push(tEmpty)
            life.push(0)
        }
        gridModel.clear()
        for (var i = 0; i < size; i++) {
            gridModel.append({ cellColor: "transparent" })
        }
    }

    function idx(x, y) { return y * gridWidth + x }
    function inBounds(x, y) { return x >= 0 && x < gridWidth && y >= 0 && y < gridHeight }
    function getCell(x, y) { return inBounds(x, y) ? grid[idx(x, y)] : tStone }

    function setCell(x, y, type, l) {
        if (!inBounds(x, y)) return
        var i = idx(x, y)
        grid[i] = type
        life[i] = l || 0
    }

    function swapCells(x1, y1, x2, y2) {
        if (!inBounds(x1, y1) || !inBounds(x2, y2)) return
        var i1 = idx(x1, y1), i2 = idx(x2, y2)
        if (grid[i1] === grid[i2]) return
        var t = grid[i1]; grid[i1] = grid[i2]; grid[i2] = t
        t = life[i1]; life[i1] = life[i2]; life[i2] = t
    }

    function clearGrid() {
        for (var i = 0; i < grid.length; i++) {
            grid[i] = tEmpty
            life[i] = 0
        }
        syncModel()
    }

    function drawBrush(cx, cy, type) {
        for (var dy = -brushSize; dy <= brushSize; dy++) {
            for (var dx = -brushSize; dx <= brushSize; dx++) {
                if (dx*dx + dy*dy <= brushSize*brushSize) {
                    var x = cx + dx, y = cy + dy
                    if (inBounds(x, y) && (type === tEmpty || getCell(x, y) === tEmpty)) {
                        var l = 80
                        if (type === tFire) l = 60 + Math.random() * 30
                        if (type === tSteam || type === tSmoke) l = 50 + Math.random() * 30
                        setCell(x, y, type, l)
                    }
                }
            }
        }
    }

    function getDensity(type) {
        var d = [0, 7, 5, 10, 3, 4, 8, 1, 4, 5, 5, 2, 4, 7, 6]
        return d[type] || 5
    }

    function isLiquid(t) { return t === tWater || t === tOil || t === tLava || t === tAcid }

    function updateParticles() {
        frameCount++
        var startX = Math.random() < 0.5 ? 0 : gridWidth - 1
        var stepX = startX === 0 ? 1 : -1
        var endX = startX === 0 ? gridWidth : -1

        for (var y = gridHeight - 1; y >= 0; y--) {
            for (var x = startX; x !== endX; x += stepX) {
                var type = grid[idx(x, y)]
                if (type === tEmpty || type === tStone) continue

                var below = getCell(x, y + 1)

                // Powders: sand, gunpowder, salt
                if (type === tSand || type === tGunpowder || type === tSalt) {
                    if (below === tEmpty) swapCells(x, y, x, y + 1)
                    else if (isLiquid(below) && getDensity(type) > getDensity(below)) swapCells(x, y, x, y + 1)
                    else if (type === tSalt && below === tWater && Math.random() < 0.1) setCell(x, y, tEmpty, 0)
                    else {
                        var lb = getCell(x-1, y+1), rb = getCell(x+1, y+1)
                        if (lb === tEmpty && rb === tEmpty) swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y + 1)
                        else if (lb === tEmpty) swapCells(x, y, x - 1, y + 1)
                        else if (rb === tEmpty) swapCells(x, y, x + 1, y + 1)
                    }
                }
                // Liquids
                else if (type === tWater || type === tOil || type === tAcid) {
                    if (below === tEmpty) swapCells(x, y, x, y + 1)
                    else if (type === tWater && below === tFire) { setCell(x, y+1, tSteam, 50); setCell(x, y, tEmpty, 0) }
                    else if (type === tWater && below === tLava) { setCell(x, y+1, tStone, 0); setCell(x, y, tSteam, 50) }
                    else if (type === tWater && below === tOil) swapCells(x, y, x, y + 1)
                    else if (type === tOil) {
                        for (var d = -1; d <= 1; d++) {
                            var n = getCell(x+d, y)
                            if ((n === tFire || n === tLava) && Math.random() < 0.2) { setCell(x, y, tFire, 80); break }
                        }
                    }
                    else if (type === tAcid) {
                        for (var dy2 = -1; dy2 <= 1; dy2++) {
                            for (var dx2 = -1; dx2 <= 1; dx2++) {
                                var n = getCell(x+dx2, y+dy2)
                                if (n !== tEmpty && n !== tStone && n !== tAcid && n !== tLava && Math.random() < 0.02) {
                                    setCell(x+dx2, y+dy2, tEmpty, 0)
                                    if (Math.random() < 0.15) { setCell(x, y, tSmoke, 30); break }
                                }
                            }
                        }
                    }
                    if (grid[idx(x,y)] === type) { // Still liquid
                        var lb = getCell(x-1, y+1), rb = getCell(x+1, y+1)
                        if (lb === tEmpty && rb === tEmpty) swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y + 1)
                        else if (lb === tEmpty) swapCells(x, y, x - 1, y + 1)
                        else if (rb === tEmpty) swapCells(x, y, x + 1, y + 1)
                        else {
                            var l = getCell(x-1, y), r = getCell(x+1, y)
                            if (l === tEmpty && r === tEmpty) swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y)
                            else if (l === tEmpty) swapCells(x, y, x - 1, y)
                            else if (r === tEmpty) swapCells(x, y, x + 1, y)
                        }
                    }
                }
                // Lava
                else if (type === tLava) {
                    for (var dy2 = -1; dy2 <= 1; dy2++) {
                        for (var dx2 = -1; dx2 <= 1; dx2++) {
                            var n = getCell(x+dx2, y+dy2)
                            if ((n === tWood || n === tPlant || n === tOil) && Math.random() < 0.06) setCell(x+dx2, y+dy2, tFire, 70)
                            if (n === tIce) setCell(x+dx2, y+dy2, tWater, 0)
                            if (n === tWater) { setCell(x+dx2, y+dy2, tSteam, 50); if (Math.random() < 0.15) setCell(x, y, tStone, 0) }
                            if (n === tGunpowder && Math.random() < 0.3) explode(x+dx2, y+dy2, 4)
                        }
                    }
                    if (below === tEmpty && Math.random() < 0.5) swapCells(x, y, x, y + 1)
                    else if (Math.random() < 0.15) {
                        var l = getCell(x-1, y), r = getCell(x+1, y)
                        if (l === tEmpty) swapCells(x, y, x - 1, y)
                        else if (r === tEmpty) swapCells(x, y, x + 1, y)
                    }
                }
                // Fire
                else if (type === tFire) {
                    var i = idx(x, y)
                    life[i]--
                    if (life[i] <= 0) setCell(x, y, Math.random() < 0.25 ? tSmoke : tEmpty, 40)
                    else {
                        for (var dy2 = -1; dy2 <= 1; dy2++) {
                            for (var dx2 = -1; dx2 <= 1; dx2++) {
                                var n = getCell(x+dx2, y+dy2)
                                if (n === tWood && Math.random() < 0.01) setCell(x+dx2, y+dy2, tFire, 100)
                                if (n === tPlant && Math.random() < 0.03) setCell(x+dx2, y+dy2, tFire, 40)
                                if (n === tOil && Math.random() < 0.1) setCell(x+dx2, y+dy2, tFire, 80)
                                if (n === tGunpowder && Math.random() < 0.2) explode(x+dx2, y+dy2, 4)
                                if (n === tIce) setCell(x+dx2, y+dy2, tWater, 0)
                            }
                        }
                        var above = getCell(x, y - 1)
                        if (above === tEmpty && Math.random() < 0.4) swapCells(x, y, x, y - 1)
                    }
                }
                // Steam/Smoke
                else if (type === tSteam || type === tSmoke) {
                    var i = idx(x, y)
                    life[i]--
                    if (life[i] <= 0) setCell(x, y, type === tSteam && Math.random() < 0.3 ? tWater : tEmpty, 0)
                    else {
                        var above = getCell(x, y - 1)
                        if (above === tEmpty && Math.random() < 0.5) swapCells(x, y, x, y - 1)
                        else {
                            var dir = Math.random() < 0.5 ? -1 : 1
                            if (getCell(x + dir, y) === tEmpty) swapCells(x, y, x + dir, y)
                        }
                    }
                }
                // Ice
                else if (type === tIce) {
                    for (var dy2 = -1; dy2 <= 1; dy2++) {
                        for (var dx2 = -1; dx2 <= 1; dx2++) {
                            var n = getCell(x+dx2, y+dy2)
                            if (n === tWater && Math.random() < 0.005) setCell(x+dx2, y+dy2, tIce, 0)
                            if ((n === tFire || n === tLava) && Math.random() < 0.06) { setCell(x, y, tWater, 0); break }
                        }
                    }
                }
                // Wood
                else if (type === tWood) {
                    for (var dy2 = -1; dy2 <= 1; dy2++) {
                        for (var dx2 = -1; dx2 <= 1; dx2++) {
                            var n = getCell(x+dx2, y+dy2)
                            if ((n === tFire || n === tLava) && Math.random() < 0.008) { setCell(x, y, tFire, 120); break }
                        }
                    }
                }
                // Plant
                else if (type === tPlant) {
                    for (var dy2 = -1; dy2 <= 1; dy2++) {
                        for (var dx2 = -1; dx2 <= 1; dx2++) {
                            var n = getCell(x+dx2, y+dy2)
                            if (n === tWater && Math.random() < 0.01) setCell(x+dx2, y+dy2, tPlant, 0)
                            if (n === tFire && Math.random() < 0.06) { setCell(x, y, tFire, 35); break }
                        }
                    }
                }
            }
        }
        syncModel()
    }

    function explode(cx, cy, radius) {
        Haptic.click()
        for (var dy = -radius; dy <= radius; dy++) {
            for (var dx = -radius; dx <= radius; dx++) {
                var dist = Math.sqrt(dx*dx + dy*dy)
                if (dist <= radius && inBounds(cx+dx, cy+dy) && getCell(cx+dx, cy+dy) !== tStone) {
                    if (dist < radius * 0.5) setCell(cx+dx, cy+dy, tFire, 45)
                    else if (Math.random() < 0.35) setCell(cx+dx, cy+dy, tSmoke, 30)
                    else setCell(cx+dx, cy+dy, tEmpty, 0)
                }
            }
        }
    }

    function syncModel() {
        for (var i = 0; i < grid.length; i++) {
            gridModel.setProperty(i, "cellColor", getColor(grid[i]))
        }
    }

    function getColor(type) {
        switch (type) {
            case tEmpty: return "transparent"
            case tSand: return "#d4a574"
            case tWater: return "#4a90e2"
            case tStone: return "#666677"
            case tFire: return Math.random() < 0.5 ? "#ff6030" : "#ff9020"
            case tOil: return "#2a1a0a"
            case tLava: return Math.random() < 0.5 ? "#ff4400" : "#ff6600"
            case tSteam: return "#c8d8e8"
            case tWood: return "#664422"
            case tIce: return "#aaddff"
            case tAcid: return "#44ee33"
            case tSmoke: return "#505560"
            case tPlant: return "#33aa22"
            case tGunpowder: return "#444444"
            case tSalt: return "#f0f0e8"
            default: return "transparent"
        }
    }

    ListModel { id: gridModel }

    // Display grid
    Grid {
        id: displayGrid
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        columns: gridWidth
        spacing: 0

        Repeater {
            model: gridModel
            Rectangle {
                width: cellSize
                height: cellSize
                color: model.cellColor
            }
        }

        MouseArea {
            anchors.fill: parent

            onPressed: {
                isDrawing = true
                var gridX = Math.floor(mouse.x / cellSize)
                var gridY = Math.floor(mouse.y / cellSize)
                drawBrush(gridX, gridY, selectedType)
                lastDrawX = gridX
                lastDrawY = gridY
                Haptic.tap()
                syncModel()
            }

            onPositionChanged: {
                if (isDrawing) {
                    var gridX = Math.floor(mouse.x / cellSize)
                    var gridY = Math.floor(mouse.y / cellSize)
                    drawBrush(gridX, gridY, selectedType)
                    lastDrawX = gridX
                    lastDrawY = gridY
                    syncModel()
                }
            }

            onReleased: isDrawing = false
        }
    }

    // Toolbar
    Rectangle {
        id: toolbar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 260
        color: "#15151f"

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            Row {
                spacing: 6
                Repeater {
                    model: [
                        { type: tSand, name: "Sand", color: "#d4a574" },
                        { type: tWater, name: "Water", color: "#4a90e2" },
                        { type: tStone, name: "Stone", color: "#666677" },
                        { type: tFire, name: "Fire", color: "#ff6030" },
                        { type: tOil, name: "Oil", color: "#2a1a0a" },
                        { type: tLava, name: "Lava", color: "#ff4400" }
                    ]
                    Rectangle {
                        width: 105; height: 55; radius: 10
                        color: selectedType === modelData.type ? "#e94560" : "#222233"
                        border.color: selectedType === modelData.type ? "#fff" : "transparent"
                        border.width: 2
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Rectangle { width: 22; height: 22; radius: 11; color: modelData.color; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.name; font.pixelSize: 9 * textScale; color: "#fff"; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { selectedType = modelData.type; Haptic.tap() } }
                    }
                }
            }

            Row {
                spacing: 6
                Repeater {
                    model: [
                        { type: tSteam, name: "Steam", color: "#c8d8e8" },
                        { type: tWood, name: "Wood", color: "#664422" },
                        { type: tIce, name: "Ice", color: "#aaddff" },
                        { type: tAcid, name: "Acid", color: "#44ee33" },
                        { type: tPlant, name: "Plant", color: "#33aa22" },
                        { type: tGunpowder, name: "Powder", color: "#444444" }
                    ]
                    Rectangle {
                        width: 105; height: 55; radius: 10
                        color: selectedType === modelData.type ? "#e94560" : "#222233"
                        border.color: selectedType === modelData.type ? "#fff" : "transparent"
                        border.width: 2
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Rectangle { width: 22; height: 22; radius: 11; color: modelData.color; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.name; font.pixelSize: 9 * textScale; color: "#fff"; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { selectedType = modelData.type; Haptic.tap() } }
                    }
                }
            }

            Row {
                spacing: 8
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    width: 100; height: 48; radius: 10
                    color: selectedType === tSalt ? "#e94560" : "#222233"
                    Row {
                        anchors.centerIn: parent; spacing: 4
                        Rectangle { width: 18; height: 18; radius: 9; color: "#f0f0e8" }
                        Text { text: "Salt"; font.pixelSize: 10 * textScale; color: "#fff"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { selectedType = tSalt; Haptic.tap() } }
                }

                Rectangle {
                    width: 100; height: 48; radius: 10
                    color: selectedType === tEmpty ? "#e94560" : "#222233"
                    Text { anchors.centerIn: parent; text: "Eraser"; font.pixelSize: 11 * textScale; color: "#fff" }
                    MouseArea { anchors.fill: parent; onClicked: { selectedType = tEmpty; Haptic.tap() } }
                }

                Rectangle {
                    width: 100; height: 48; radius: 10
                    color: clearMouse.pressed ? "#aa3344" : "#222233"
                    Text { anchors.centerIn: parent; text: "Clear"; font.pixelSize: 11 * textScale; color: "#ff6666" }
                    MouseArea { id: clearMouse; anchors.fill: parent; onClicked: { clearGrid(); Haptic.click() } }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Text { text: "Brush:"; font.pixelSize: 10 * textScale; color: "#888"; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: [1, 2, 3, 4]
                    Rectangle {
                        width: 48; height: 40; radius: 8
                        color: brushSize === modelData ? "#e94560" : "#222233"
                        Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 12 * textScale; color: "#fff" }
                        MouseArea { anchors.fill: parent; onClicked: { brushSize = modelData; Haptic.tap() } }
                    }
                }
            }
        }
    }

    Timer {
        interval: 80  // ~12 FPS
        running: true
        repeat: true
        onTriggered: updateParticles()
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: displayGrid.bottom
        anchors.leftMargin: 16
        anchors.topMargin: 16
        width: 56; height: 56; radius: 28
        color: backMouse.pressed ? "#c23a50" : "#e94560"
        z: 10
        Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 28; color: "#fff" }
        MouseArea { id: backMouse; anchors.fill: parent; onClicked: { Haptic.tap(); Qt.quit() } }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 120; height: 4; radius: 2
        color: "#333344"
    }
}
