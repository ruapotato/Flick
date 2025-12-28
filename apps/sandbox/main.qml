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
    property int gridWidth: 54
    property int gridHeight: 96
    property int cellSize: 20

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

    property var grid: []
    property var life: []

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
    }

    function drawBrush(cx, cy, type) {
        for (var dy = -brushSize; dy <= brushSize; dy++) {
            for (var dx = -brushSize; dx <= brushSize; dx++) {
                if (dx*dx + dy*dy <= brushSize*brushSize) {
                    var x = cx + dx, y = cy + dy
                    if (inBounds(x, y) && (type === tEmpty || getCell(x, y) === tEmpty)) {
                        var l = 60
                        if (type === tFire) l = 40 + Math.random() * 20
                        if (type === tSteam || type === tSmoke) l = 40 + Math.random() * 20
                        setCell(x, y, type, l)
                    }
                }
            }
        }
    }

    function isLiquid(t) { return t === tWater || t === tOil || t === tLava || t === tAcid }

    function updatePhysics() {
        var startX = Math.random() < 0.5 ? 0 : gridWidth - 1
        var stepX = startX === 0 ? 1 : -1
        var endX = startX === 0 ? gridWidth : -1

        for (var y = gridHeight - 1; y >= 0; y--) {
            for (var x = startX; x !== endX; x += stepX) {
                var type = grid[idx(x, y)]
                if (type === tEmpty || type === tStone) continue

                var below = getCell(x, y + 1)

                if (type === tSand || type === tGunpowder || type === tSalt) {
                    if (below === tEmpty) swapCells(x, y, x, y + 1)
                    else if (isLiquid(below)) swapCells(x, y, x, y + 1)
                    else {
                        var lb = getCell(x-1, y+1), rb = getCell(x+1, y+1)
                        if (lb === tEmpty && rb === tEmpty) swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y + 1)
                        else if (lb === tEmpty) swapCells(x, y, x - 1, y + 1)
                        else if (rb === tEmpty) swapCells(x, y, x + 1, y + 1)
                    }
                }
                else if (type === tWater || type === tOil || type === tAcid) {
                    if (below === tEmpty) swapCells(x, y, x, y + 1)
                    else if (type === tWater && below === tFire) { setCell(x, y+1, tSteam, 40); setCell(x, y, tEmpty, 0) }
                    else if (type === tWater && below === tLava) { setCell(x, y+1, tStone, 0); setCell(x, y, tSteam, 40) }
                    else if (type === tWater && below === tOil) swapCells(x, y, x, y + 1)
                    else {
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
                else if (type === tLava) {
                    if (below === tEmpty && Math.random() < 0.5) swapCells(x, y, x, y + 1)
                    else if (Math.random() < 0.2) {
                        var l = getCell(x-1, y), r = getCell(x+1, y)
                        if (l === tEmpty) swapCells(x, y, x - 1, y)
                        else if (r === tEmpty) swapCells(x, y, x + 1, y)
                    }
                    // Ignite neighbors
                    for (var d = -1; d <= 1; d++) {
                        var n = getCell(x+d, y-1)
                        if ((n === tWood || n === tPlant || n === tOil) && Math.random() < 0.05) setCell(x+d, y-1, tFire, 50)
                        if (n === tWater) { setCell(x+d, y-1, tSteam, 40); if (Math.random() < 0.1) setCell(x, y, tStone, 0) }
                        if (n === tGunpowder && Math.random() < 0.2) explode(x+d, y-1, 3)
                    }
                }
                else if (type === tFire) {
                    life[idx(x,y)]--
                    if (life[idx(x,y)] <= 0) setCell(x, y, Math.random() < 0.2 ? tSmoke : tEmpty, 30)
                    else {
                        if (getCell(x, y-1) === tEmpty && Math.random() < 0.4) swapCells(x, y, x, y - 1)
                        // Spread
                        for (var d = -1; d <= 1; d++) {
                            var n = getCell(x+d, y)
                            if (n === tWood && Math.random() < 0.01) setCell(x+d, y, tFire, 80)
                            if (n === tPlant && Math.random() < 0.03) setCell(x+d, y, tFire, 30)
                            if (n === tOil && Math.random() < 0.1) setCell(x+d, y, tFire, 60)
                            if (n === tGunpowder && Math.random() < 0.15) explode(x+d, y, 3)
                        }
                    }
                }
                else if (type === tSteam || type === tSmoke) {
                    life[idx(x,y)]--
                    if (life[idx(x,y)] <= 0) setCell(x, y, type === tSteam && Math.random() < 0.3 ? tWater : tEmpty, 0)
                    else if (getCell(x, y-1) === tEmpty && Math.random() < 0.5) swapCells(x, y, x, y - 1)
                    else {
                        var d = Math.random() < 0.5 ? -1 : 1
                        if (getCell(x+d, y) === tEmpty) swapCells(x, y, x+d, y)
                    }
                }
                else if (type === tIce) {
                    for (var d = -1; d <= 1; d++) {
                        if (getCell(x+d, y) === tWater && Math.random() < 0.005) setCell(x+d, y, tIce, 0)
                        if ((getCell(x+d, y) === tFire || getCell(x+d, y) === tLava) && Math.random() < 0.05) { setCell(x, y, tWater, 0); break }
                    }
                }
                else if (type === tWood || type === tPlant) {
                    for (var d = -1; d <= 1; d++) {
                        var n = getCell(x+d, y)
                        if ((n === tFire || n === tLava) && Math.random() < 0.01) { setCell(x, y, tFire, type === tWood ? 80 : 30); break }
                        if (type === tPlant && n === tWater && Math.random() < 0.01) setCell(x+d, y, tPlant, 0)
                    }
                }
            }
        }
        canvas.requestPaint()
    }

    function explode(cx, cy, r) {
        Haptic.click()
        for (var dy = -r; dy <= r; dy++) {
            for (var dx = -r; dx <= r; dx++) {
                if (dx*dx + dy*dy <= r*r && inBounds(cx+dx, cy+dy) && getCell(cx+dx, cy+dy) !== tStone) {
                    setCell(cx+dx, cy+dy, Math.random() < 0.4 ? tFire : tEmpty, 30)
                }
            }
        }
    }

    function getColor(type) {
        switch (type) {
            case tSand: return "#d4a574"
            case tWater: return "#4a90e2"
            case tStone: return "#666677"
            case tFire: return Math.random() < 0.5 ? "#ff6030" : "#ff9020"
            case tOil: return "#2a1a0a"
            case tLava: return "#ff4400"
            case tSteam: return "#c8d8e8"
            case tWood: return "#664422"
            case tIce: return "#aaddff"
            case tAcid: return "#44ee33"
            case tSmoke: return "#505560"
            case tPlant: return "#33aa22"
            case tGunpowder: return "#444444"
            case tSalt: return "#f0f0e8"
            default: return null
        }
    }

    Canvas {
        id: canvas
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: gridWidth * cellSize
        height: gridHeight * cellSize

        renderStrategy: Canvas.Immediate

        onPaint: {
            var ctx = getContext("2d")
            ctx.fillStyle = "#0a0a0f"
            ctx.fillRect(0, 0, width, height)

            for (var y = 0; y < gridHeight; y++) {
                for (var x = 0; x < gridWidth; x++) {
                    var c = getColor(grid[idx(x, y)])
                    if (c) {
                        ctx.fillStyle = c
                        ctx.fillRect(x * cellSize, y * cellSize, cellSize, cellSize)
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onPressed: {
                isDrawing = true
                var gx = Math.floor(mouse.x / cellSize)
                var gy = Math.floor(mouse.y / cellSize)
                drawBrush(gx, gy, selectedType)
                Haptic.tap()
                canvas.requestPaint()
            }
            onPositionChanged: {
                if (isDrawing) {
                    var gx = Math.floor(mouse.x / cellSize)
                    var gy = Math.floor(mouse.y / cellSize)
                    drawBrush(gx, gy, selectedType)
                    canvas.requestPaint()
                }
            }
            onReleased: isDrawing = false
        }
    }

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
                        { t: tSand, n: "Sand", c: "#d4a574" },
                        { t: tWater, n: "Water", c: "#4a90e2" },
                        { t: tStone, n: "Stone", c: "#666677" },
                        { t: tFire, n: "Fire", c: "#ff6030" },
                        { t: tOil, n: "Oil", c: "#2a1a0a" },
                        { t: tLava, n: "Lava", c: "#ff4400" }
                    ]
                    Rectangle {
                        width: 105; height: 55; radius: 10
                        color: selectedType === modelData.t ? "#e94560" : "#222233"
                        border.color: selectedType === modelData.t ? "#fff" : "transparent"
                        border.width: 2
                        Column {
                            anchors.centerIn: parent; spacing: 2
                            Rectangle { width: 22; height: 22; radius: 11; color: modelData.c; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.n; font.pixelSize: 9 * textScale; color: "#fff"; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { selectedType = modelData.t; Haptic.tap() } }
                    }
                }
            }

            Row {
                spacing: 6
                Repeater {
                    model: [
                        { t: tSteam, n: "Steam", c: "#c8d8e8" },
                        { t: tWood, n: "Wood", c: "#664422" },
                        { t: tIce, n: "Ice", c: "#aaddff" },
                        { t: tAcid, n: "Acid", c: "#44ee33" },
                        { t: tPlant, n: "Plant", c: "#33aa22" },
                        { t: tGunpowder, n: "Powder", c: "#444444" }
                    ]
                    Rectangle {
                        width: 105; height: 55; radius: 10
                        color: selectedType === modelData.t ? "#e94560" : "#222233"
                        border.color: selectedType === modelData.t ? "#fff" : "transparent"
                        border.width: 2
                        Column {
                            anchors.centerIn: parent; spacing: 2
                            Rectangle { width: 22; height: 22; radius: 11; color: modelData.c; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.n; font.pixelSize: 9 * textScale; color: "#fff"; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { selectedType = modelData.t; Haptic.tap() } }
                    }
                }
            }

            Row {
                spacing: 8; anchors.horizontalCenter: parent.horizontalCenter
                Rectangle {
                    width: 100; height: 48; radius: 10
                    color: selectedType === tSalt ? "#e94560" : "#222233"
                    Row { anchors.centerIn: parent; spacing: 4
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
                    color: clrM.pressed ? "#aa3344" : "#222233"
                    Text { anchors.centerIn: parent; text: "Clear"; font.pixelSize: 11 * textScale; color: "#ff6666" }
                    MouseArea { id: clrM; anchors.fill: parent; onClicked: { clearGrid(); canvas.requestPaint(); Haptic.click() } }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
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
        interval: 100
        running: true
        repeat: true
        onTriggered: updatePhysics()
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: canvas.bottom
        anchors.leftMargin: 16
        anchors.topMargin: 16
        width: 56; height: 56; radius: 28
        color: bkM.pressed ? "#c23a50" : "#e94560"
        z: 10
        Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 28; color: "#fff" }
        MouseArea { id: bkM; anchors.fill: parent; onClicked: { Haptic.tap(); Qt.quit() } }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 120; height: 4; radius: 2
        color: "#333344"
    }
}
