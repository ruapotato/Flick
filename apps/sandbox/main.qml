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
    property int gridWidth: 108
    property int gridHeight: 192
    property int cellSize: 10

    // Particle types encoded as colors for shader
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
    property int brushSize: 3
    property bool isDrawing: false
    property int lastDrawX: -1
    property int lastDrawY: -1

    property var grid: []
    property var velX: []
    property var velY: []
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
        grid = new Array(size)
        velX = new Array(size)
        velY = new Array(size)
        life = new Array(size)
        for (var i = 0; i < size; i++) {
            grid[i] = tEmpty
            velX[i] = 0
            velY[i] = 0
            life[i] = 0
        }
    }

    function idx(x, y) { return y * gridWidth + x }
    function inBounds(x, y) { return x >= 0 && x < gridWidth && y >= 0 && y < gridHeight }
    function getCell(x, y) { return inBounds(x, y) ? grid[idx(x, y)] : tStone }

    function setCell(x, y, type, vx, vy, l) {
        if (!inBounds(x, y)) return
        var i = idx(x, y)
        grid[i] = type
        velX[i] = vx || 0
        velY[i] = vy || 0
        life[i] = l || 0
    }

    function swapCells(x1, y1, x2, y2) {
        if (!inBounds(x1, y1) || !inBounds(x2, y2)) return
        var i1 = idx(x1, y1), i2 = idx(x2, y2)
        if (grid[i1] === grid[i2]) return

        var t = grid[i1]; grid[i1] = grid[i2]; grid[i2] = t
        t = velX[i1]; velX[i1] = velX[i2]; velX[i2] = t
        t = velY[i1]; velY[i1] = velY[i2]; velY[i2] = t
        t = life[i1]; life[i1] = life[i2]; life[i2] = t
    }

    function clearGrid() {
        for (var i = 0; i < grid.length; i++) {
            grid[i] = tEmpty
            velX[i] = 0
            velY[i] = 0
            life[i] = 0
        }
    }

    function drawBrush(cx, cy, type) {
        for (var dy = -brushSize; dy <= brushSize; dy++) {
            for (var dx = -brushSize; dx <= brushSize; dx++) {
                if (dx*dx + dy*dy <= brushSize*brushSize) {
                    var x = cx + dx, y = cy + dy
                    if (inBounds(x, y) && (type === tEmpty || getCell(x, y) === tEmpty)) {
                        var l = 255
                        if (type === tFire) l = 100 + Math.random() * 50
                        if (type === tSteam || type === tSmoke) l = 100 + Math.random() * 50
                        setCell(x, y, type, (Math.random() - 0.5) * 0.5, 0, l)
                    }
                }
            }
        }
    }

    function getDensity(type) {
        var densities = [0, 7, 5, 10, 3, 4, 8, 1, 4, 5, 5, 2, 4, 7, 6]
        return densities[type] || 5
    }

    function isLiquid(t) { return t === tWater || t === tOil || t === tLava || t === tAcid }
    function isGas(t) { return t === tSteam || t === tSmoke || t === tFire }
    function isSolid(t) { return t === tStone || t === tWood || t === tIce || t === tPlant }

    function updateParticles() {
        frameCount++
        var startX = Math.random() < 0.5 ? 0 : gridWidth - 1
        var stepX = startX === 0 ? 1 : -1
        var endX = startX === 0 ? gridWidth : -1

        for (var y = gridHeight - 1; y >= 0; y--) {
            for (var x = startX; x !== endX; x += stepX) {
                var i = idx(x, y)
                var type = grid[i]
                if (type === tEmpty || type === tStone) continue

                var below = getCell(x, y + 1)
                var cellLife = life[i]

                if (type === tSand || type === tGunpowder || type === tSalt) {
                    if (below === tEmpty) { swapCells(x, y, x, y + 1) }
                    else if (isLiquid(below) && getDensity(type) > getDensity(below)) { swapCells(x, y, x, y + 1) }
                    else if (type === tSalt && below === tWater && Math.random() < 0.1) { setCell(x, y, tEmpty, 0, 0, 0) }
                    else {
                        var lb = getCell(x-1, y+1), rb = getCell(x+1, y+1)
                        var cl = lb === tEmpty, cr = rb === tEmpty
                        if (cl && cr) swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y + 1)
                        else if (cl) swapCells(x, y, x - 1, y + 1)
                        else if (cr) swapCells(x, y, x + 1, y + 1)
                    }
                }
                else if (type === tWater || type === tOil || type === tAcid) {
                    if (below === tEmpty) { swapCells(x, y, x, y + 1) }
                    else if (type === tWater && below === tFire) { setCell(x, y+1, tSteam, 0, -1, 80); setCell(x, y, tEmpty, 0, 0, 0) }
                    else if (type === tWater && below === tLava) { setCell(x, y+1, tStone, 0, 0, 0); setCell(x, y, tSteam, 0, -1, 80) }
                    else if (type === tWater && below === tOil) { swapCells(x, y, x, y + 1) }
                    else if (type === tOil && (getCell(x-1,y) === tFire || getCell(x+1,y) === tFire || getCell(x,y-1) === tFire || below === tFire || getCell(x-1,y) === tLava || getCell(x+1,y) === tLava) && Math.random() < 0.3) { setCell(x, y, tFire, 0, 0, 120) }
                    else if (type === tAcid) {
                        for (var dy = -1; dy <= 1; dy++) {
                            for (var dx = -1; dx <= 1; dx++) {
                                var n = getCell(x+dx, y+dy)
                                if (n !== tEmpty && n !== tStone && n !== tAcid && n !== tLava && Math.random() < 0.03) {
                                    setCell(x+dx, y+dy, tEmpty, 0, 0, 0)
                                    if (Math.random() < 0.2) { setCell(x, y, tSmoke, 0, -0.5, 40); break }
                                }
                            }
                        }
                    }
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
                    for (var dy = -1; dy <= 1; dy++) {
                        for (var dx = -1; dx <= 1; dx++) {
                            var n = getCell(x+dx, y+dy)
                            if ((n === tWood || n === tPlant || n === tOil) && Math.random() < 0.08) setCell(x+dx, y+dy, tFire, 0, 0, 100)
                            if (n === tIce) setCell(x+dx, y+dy, tWater, 0, 0, 0)
                            if (n === tWater) { setCell(x+dx, y+dy, tSteam, 0, -1, 80); if (Math.random() < 0.2) { setCell(x, y, tStone, 0, 0, 0); break } }
                            if (n === tGunpowder && Math.random() < 0.4) explode(x+dx, y+dy, 5)
                        }
                    }
                    if (below === tEmpty && Math.random() < 0.6) swapCells(x, y, x, y + 1)
                    else if (Math.random() < 0.2) {
                        var l = getCell(x-1, y), r = getCell(x+1, y)
                        if (l === tEmpty && r === tEmpty) swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y)
                        else if (l === tEmpty) swapCells(x, y, x - 1, y)
                        else if (r === tEmpty) swapCells(x, y, x + 1, y)
                    }
                }
                else if (type === tFire) {
                    life[i]--
                    if (life[i] <= 0) { setCell(x, y, Math.random() < 0.3 ? tSmoke : tEmpty, 0, -0.5, 60) }
                    else {
                        for (var dy = -1; dy <= 1; dy++) {
                            for (var dx = -1; dx <= 1; dx++) {
                                var n = getCell(x+dx, y+dy)
                                if (n === tWood && Math.random() < 0.015) setCell(x+dx, y+dy, tFire, 0, 0, 180)
                                if (n === tPlant && Math.random() < 0.04) setCell(x+dx, y+dy, tFire, 0, 0, 60)
                                if (n === tOil && Math.random() < 0.15) setCell(x+dx, y+dy, tFire, 0, 0, 120)
                                if (n === tGunpowder && Math.random() < 0.25) explode(x+dx, y+dy, 5)
                                if (n === tIce) setCell(x+dx, y+dy, tWater, 0, 0, 0)
                            }
                        }
                        var above = getCell(x, y - 1)
                        if (above === tEmpty && Math.random() < 0.5) swapCells(x, y, x, y - 1)
                        else if (Math.random() < 0.3) {
                            var dir = Math.random() < 0.5 ? -1 : 1
                            if (getCell(x + dir, y - 1) === tEmpty) swapCells(x, y, x + dir, y - 1)
                        }
                    }
                }
                else if (type === tSteam || type === tSmoke) {
                    life[i]--
                    if (life[i] <= 0) { setCell(x, y, type === tSteam && Math.random() < 0.4 ? tWater : tEmpty, 0, 0, 0) }
                    else {
                        var above = getCell(x, y - 1)
                        if (above === tEmpty && Math.random() < 0.6) swapCells(x, y, x, y - 1)
                        else {
                            var dir = Math.random() < 0.5 ? -1 : 1
                            if (getCell(x + dir, y) === tEmpty) swapCells(x, y, x + dir, y)
                        }
                    }
                }
                else if (type === tIce) {
                    for (var dy = -1; dy <= 1; dy++) {
                        for (var dx = -1; dx <= 1; dx++) {
                            var n = getCell(x+dx, y+dy)
                            if (n === tWater && Math.random() < 0.008) setCell(x+dx, y+dy, tIce, 0, 0, 0)
                            if ((n === tFire || n === tLava) && Math.random() < 0.08) { setCell(x, y, tWater, 0, 0, 0); break }
                        }
                    }
                }
                else if (type === tWood) {
                    for (var dy = -1; dy <= 1; dy++) {
                        for (var dx = -1; dx <= 1; dx++) {
                            var n = getCell(x+dx, y+dy)
                            if ((n === tFire || n === tLava) && Math.random() < 0.01) { setCell(x, y, tFire, 0, 0, 200); break }
                        }
                    }
                }
                else if (type === tPlant) {
                    for (var dy = -1; dy <= 1; dy++) {
                        for (var dx = -1; dx <= 1; dx++) {
                            var n = getCell(x+dx, y+dy)
                            if (n === tWater && Math.random() < 0.015) setCell(x+dx, y+dy, tPlant, 0, 0, 0)
                            if (n === tFire && Math.random() < 0.08) { setCell(x, y, tFire, 0, 0, 50); break }
                        }
                    }
                    if (Math.random() < 0.0008 && getCell(x, y-1) === tEmpty) setCell(x, y-1, tPlant, 0, 0, 0)
                }
            }
        }
        dataCanvas.requestPaint()
    }

    function explode(cx, cy, radius) {
        Haptic.click()
        for (var dy = -radius; dy <= radius; dy++) {
            for (var dx = -radius; dx <= radius; dx++) {
                var dist = Math.sqrt(dx*dx + dy*dy)
                if (dist <= radius && inBounds(cx+dx, cy+dy) && getCell(cx+dx, cy+dy) !== tStone) {
                    if (dist < radius * 0.5) setCell(cx+dx, cy+dy, tFire, (Math.random()-0.5)*2, (Math.random()-0.5)*2, 60)
                    else if (Math.random() < 0.4) setCell(cx+dx, cy+dy, tSmoke, (Math.random()-0.5), -1, 40)
                    else setCell(cx+dx, cy+dy, tEmpty, 0, 0, 0)
                }
            }
        }
    }

    // Offscreen canvas for particle data (1 pixel per cell)
    Canvas {
        id: dataCanvas
        width: gridWidth
        height: gridHeight
        visible: false
        renderStrategy: Canvas.Immediate

        onPaint: {
            var ctx = getContext("2d")
            var imgData = ctx.createImageData(gridWidth, gridHeight)
            var data = imgData.data

            for (var y = 0; y < gridHeight; y++) {
                for (var x = 0; x < gridWidth; x++) {
                    var i = (y * gridWidth + x) * 4
                    var type = grid[y * gridWidth + x]
                    // Encode type and life/variation in RGBA
                    var r = 0, g = 0, b = 0, a = 255
                    var noise = ((x * 17 + y * 31 + frameCount) % 30) / 100

                    switch (type) {
                        case tEmpty: a = 0; break
                        case tSand: r = 212 + noise*40; g = 165 + noise*40; b = 118; break
                        case tWater: r = 50; g = 130 + noise*30; b = 230; a = 230; break
                        case tStone: r = 100 + noise*20; g = 100 + noise*20; b = 105 + noise*20; break
                        case tFire: r = 255; g = 80 + Math.random()*100; b = 20; break
                        case tOil: r = 40 + noise*10; g = 25 + noise*10; b = 15; break
                        case tLava: r = 255; g = 50 + Math.random()*60; b = 0; break
                        case tSteam: r = 200; g = 210; b = 220; a = 140; break
                        case tWood: r = 100 + noise*20; g = 65 + noise*15; b = 30; break
                        case tIce: r = 180; g = 220 + noise*20; b = 255; a = 230; break
                        case tAcid: r = 80; g = 230 + noise*20; b = 50; a = 230; break
                        case tSmoke: r = 80; g = 80; b = 90; a = 160; break
                        case tPlant: r = 50; g = 160 + noise*40; b = 40; break
                        case tGunpowder: r = 70 + noise*15; g = 70; b = 70; break
                        case tSalt: r = 245; g = 245; b = 235 + noise*15; break
                    }
                    data[i] = r
                    data[i + 1] = g
                    data[i + 2] = b
                    data[i + 3] = a
                }
            }
            ctx.putImageData(imgData, 0, 0)
        }
    }

    // Shader-rendered display
    ShaderEffect {
        id: display
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: toolbar.top

        property variant src: ShaderEffectSource {
            sourceItem: dataCanvas
            smooth: false
            live: true
        }

        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform sampler2D src;
            uniform lowp float qt_Opacity;

            void main() {
                lowp vec4 tex = texture2D(src, qt_TexCoord0);
                gl_FragColor = tex * qt_Opacity;
            }
        "

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
            }

            onPositionChanged: {
                if (isDrawing) {
                    var gridX = Math.floor(mouse.x / cellSize)
                    var gridY = Math.floor(mouse.y / cellSize)
                    var dx = gridX - lastDrawX
                    var dy = gridY - lastDrawY
                    var steps = Math.max(Math.abs(dx), Math.abs(dy))
                    for (var i = 0; i <= steps; i++) {
                        var t = steps > 0 ? i / steps : 0
                        drawBrush(Math.round(lastDrawX + dx * t), Math.round(lastDrawY + dy * t), selectedType)
                    }
                    lastDrawX = gridX
                    lastDrawY = gridY
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
        height: 280
        color: "#15151f"

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Row {
                width: parent.width
                spacing: 12

                Text {
                    text: "Brush"
                    font.pixelSize: 12 * textScale
                    color: "#888899"
                    anchors.verticalCenter: parent.verticalCenter
                }

                Slider {
                    id: brushSlider
                    width: parent.width - 180
                    from: 1
                    to: 8
                    value: brushSize
                    onValueChanged: brushSize = Math.round(value)

                    background: Rectangle {
                        x: brushSlider.leftPadding
                        y: brushSlider.topPadding + brushSlider.availableHeight / 2 - height / 2
                        width: brushSlider.availableWidth
                        height: 8
                        radius: 4
                        color: "#333344"
                        Rectangle {
                            width: brushSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 4
                            color: "#e94560"
                        }
                    }

                    handle: Rectangle {
                        x: brushSlider.leftPadding + brushSlider.visualPosition * (brushSlider.availableWidth - width)
                        y: brushSlider.topPadding + brushSlider.availableHeight / 2 - height / 2
                        width: 28
                        height: 28
                        radius: 14
                        color: "#e94560"
                    }
                }

                Rectangle {
                    width: 60
                    height: 40
                    radius: 8
                    color: "#222233"
                    Text {
                        anchors.centerIn: parent
                        text: brushSize
                        font.pixelSize: 14 * textScale
                        color: "#ffffff"
                    }
                }
            }

            Row {
                spacing: 6
                Repeater {
                    model: [
                        { type: tSand, name: "Sand", color: "#d4a574" },
                        { type: tWater, name: "Water", color: "#4a90e2" },
                        { type: tStone, name: "Stone", color: "#666666" },
                        { type: tFire, name: "Fire", color: "#ff6b35" },
                        { type: tOil, name: "Oil", color: "#2a1a0a" },
                        { type: tLava, name: "Lava", color: "#ff4400" }
                    ]
                    Rectangle {
                        width: 105; height: 60; radius: 10
                        color: selectedType === modelData.type ? "#e94560" : "#222233"
                        border.color: selectedType === modelData.type ? "#fff" : "transparent"
                        border.width: 2
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Rectangle { width: 24; height: 24; radius: 12; color: modelData.color; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.name; font.pixelSize: 10 * textScale; color: "#ffffff"; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { selectedType = modelData.type; Haptic.tap() } }
                    }
                }
            }

            Row {
                spacing: 6
                Repeater {
                    model: [
                        { type: tSteam, name: "Steam", color: "#ccddee" },
                        { type: tWood, name: "Wood", color: "#664422" },
                        { type: tIce, name: "Ice", color: "#aaddff" },
                        { type: tAcid, name: "Acid", color: "#44ee33" },
                        { type: tPlant, name: "Plant", color: "#33aa22" },
                        { type: tGunpowder, name: "Powder", color: "#444444" }
                    ]
                    Rectangle {
                        width: 105; height: 60; radius: 10
                        color: selectedType === modelData.type ? "#e94560" : "#222233"
                        border.color: selectedType === modelData.type ? "#fff" : "transparent"
                        border.width: 2
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Rectangle { width: 24; height: 24; radius: 12; color: modelData.color; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.name; font.pixelSize: 10 * textScale; color: "#ffffff"; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { selectedType = modelData.type; Haptic.tap() } }
                    }
                }
            }

            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    width: 105; height: 50; radius: 10
                    color: selectedType === tSalt ? "#e94560" : "#222233"
                    border.color: selectedType === tSalt ? "#fff" : "transparent"
                    border.width: 2
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle { width: 20; height: 20; radius: 10; color: "#f5f5ee" }
                        Text { text: "Salt"; font.pixelSize: 11 * textScale; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { selectedType = tSalt; Haptic.tap() } }
                }

                Rectangle {
                    width: 105; height: 50; radius: 10
                    color: selectedType === tEmpty ? "#e94560" : "#222233"
                    border.color: selectedType === tEmpty ? "#fff" : "transparent"
                    border.width: 2
                    Text { anchors.centerIn: parent; text: "Eraser"; font.pixelSize: 12 * textScale; color: "#ffffff" }
                    MouseArea { anchors.fill: parent; onClicked: { selectedType = tEmpty; Haptic.tap() } }
                }

                Rectangle {
                    width: 105; height: 50; radius: 10
                    color: clearMouse.pressed ? "#aa3344" : "#222233"
                    Text { anchors.centerIn: parent; text: "Clear"; font.pixelSize: 12 * textScale; color: "#ff6666" }
                    MouseArea { id: clearMouse; anchors.fill: parent; onClicked: { clearGrid(); Haptic.click() } }
                }
            }
        }
    }

    Timer {
        interval: 33
        running: true
        repeat: true
        onTriggered: updateParticles()
    }

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: toolbar.top
        anchors.leftMargin: 16
        anchors.bottomMargin: 16
        width: 56; height: 56; radius: 28
        color: backMouse.pressed ? "#c23a50" : "#e94560"
        z: 10
        Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 28; color: "#ffffff" }
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
