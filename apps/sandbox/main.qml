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
    property int gridWidth: 54    // Optimized for mobile
    property int gridHeight: 96
    property int cellSize: 20

    // Particle types
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

    // Particle data: type, velocity, life
    property var grid: []
    property var velX: []
    property var velY: []
    property var life: []
    property var updated: []  // Track if cell was updated this frame
    property int frameCount: 0
    property bool needsRepaint: false

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
        updated = new Array(size)
        for (var i = 0; i < size; i++) {
            grid[i] = tEmpty
            velX[i] = 0
            velY[i] = 0
            life[i] = 0
            updated[i] = false
        }
    }

    function idx(x, y) {
        return y * gridWidth + x
    }

    function inBounds(x, y) {
        return x >= 0 && x < gridWidth && y >= 0 && y < gridHeight
    }

    function getCell(x, y) {
        if (!inBounds(x, y)) return tStone
        return grid[idx(x, y)]
    }

    function setCell(x, y, type, vx, vy, l) {
        if (!inBounds(x, y)) return
        var i = idx(x, y)
        if (grid[i] !== type) needsRepaint = true
        grid[i] = type
        velX[i] = vx || 0
        velY[i] = vy || 0
        life[i] = l || 0
        updated[i] = true
    }

    function swapCells(x1, y1, x2, y2) {
        if (!inBounds(x1, y1) || !inBounds(x2, y2)) return
        var i1 = idx(x1, y1)
        var i2 = idx(x2, y2)
        if (grid[i1] === grid[i2]) return  // No point swapping same types

        needsRepaint = true

        var tempType = grid[i1]
        var tempVx = velX[i1]
        var tempVy = velY[i1]
        var tempLife = life[i1]

        grid[i1] = grid[i2]
        velX[i1] = velX[i2]
        velY[i1] = velY[i2]
        life[i1] = life[i2]

        grid[i2] = tempType
        velX[i2] = tempVx
        velY[i2] = tempVy
        life[i2] = tempLife

        updated[i1] = true
        updated[i2] = true
    }

    function clearGrid() {
        for (var i = 0; i < grid.length; i++) {
            grid[i] = tEmpty
            velX[i] = 0
            velY[i] = 0
            life[i] = 0
        }
        canvas.requestPaint()
    }

    function drawBrush(cx, cy, type) {
        for (var dy = -brushSize; dy <= brushSize; dy++) {
            for (var dx = -brushSize; dx <= brushSize; dx++) {
                if (dx*dx + dy*dy <= brushSize*brushSize) {
                    var x = cx + dx
                    var y = cy + dy
                    if (inBounds(x, y)) {
                        // Don't overwrite unless erasing
                        if (type === tEmpty || getCell(x, y) === tEmpty) {
                            var vx = (Math.random() - 0.5) * 0.5
                            var vy = 0
                            var l = 255
                            if (type === tFire) l = 100 + Math.random() * 50
                            if (type === tSteam) l = 150 + Math.random() * 50
                            setCell(x, y, type, vx, vy, l)
                        }
                    }
                }
            }
        }
    }

    // Density for sinking/floating
    function getDensity(type) {
        switch(type) {
            case tEmpty: return 0
            case tSteam: return 1
            case tSmoke: return 2
            case tFire: return 3
            case tOil: return 4
            case tWater: return 5
            case tAcid: return 5
            case tSalt: return 6
            case tSand: return 7
            case tGunpowder: return 7
            case tIce: return 5
            case tWood: return 4
            case tPlant: return 4
            case tLava: return 8
            case tStone: return 10
            default: return 5
        }
    }

    function isSolid(type) {
        return type === tStone || type === tWood || type === tIce || type === tPlant
    }

    function isLiquid(type) {
        return type === tWater || type === tOil || type === tLava || type === tAcid
    }

    function isGas(type) {
        return type === tSteam || type === tSmoke || type === tFire
    }

    function isPowder(type) {
        return type === tSand || type === tSalt || type === tGunpowder
    }

    function updateParticles() {
        frameCount++
        needsRepaint = false

        // Reset updated flags
        for (var i = 0; i < updated.length; i++) {
            updated[i] = false
        }

        // Process from bottom to top for falling, randomize horizontal
        var startX = Math.random() < 0.5 ? 0 : gridWidth - 1
        var endX = startX === 0 ? gridWidth : -1
        var stepX = startX === 0 ? 1 : -1

        for (var y = gridHeight - 1; y >= 0; y--) {
            for (var x = startX; x !== endX; x += stepX) {
                var i = idx(x, y)
                if (updated[i]) continue

                var type = grid[i]
                if (type === tEmpty || type === tStone) continue

                var cellLife = life[i]
                var cellVx = velX[i]
                var cellVy = velY[i]

                // Apply gravity to velocity
                if (!isSolid(type) && !isGas(type)) {
                    cellVy = Math.min(cellVy + 0.5, 3)
                }

                // Process by type
                if (type === tSand || type === tGunpowder || type === tSalt) {
                    updatePowder(x, y, type, cellVx, cellVy)
                } else if (type === tWater) {
                    updateWater(x, y, cellVx, cellVy)
                } else if (type === tOil) {
                    updateOil(x, y, cellVx, cellVy)
                } else if (type === tLava) {
                    updateLava(x, y, cellVx, cellVy)
                } else if (type === tAcid) {
                    updateAcid(x, y, cellVx, cellVy)
                } else if (type === tFire) {
                    updateFire(x, y, cellLife)
                } else if (type === tSteam) {
                    updateSteam(x, y, cellLife)
                } else if (type === tSmoke) {
                    updateSmoke(x, y, cellLife)
                } else if (type === tIce) {
                    updateIce(x, y)
                } else if (type === tWood) {
                    updateWood(x, y)
                } else if (type === tPlant) {
                    updatePlant(x, y)
                }
            }
        }

        if (needsRepaint) canvas.requestPaint()
    }

    function updatePowder(x, y, type, vx, vy) {
        var below = getCell(x, y + 1)

        // Fall into empty or lighter liquids
        if (below === tEmpty) {
            swapCells(x, y, x, y + 1)
            velY[idx(x, y + 1)] = vy + 0.5
            return
        }

        // Sink through lighter materials
        if (isLiquid(below) && getDensity(type) > getDensity(below)) {
            swapCells(x, y, x, y + 1)
            return
        }

        // Salt dissolves in water
        if (type === tSalt && below === tWater && Math.random() < 0.1) {
            setCell(x, y, tEmpty, 0, 0, 0)
            return
        }

        // Try diagonal
        var leftBelow = getCell(x - 1, y + 1)
        var rightBelow = getCell(x + 1, y + 1)
        var canLeft = leftBelow === tEmpty || (isLiquid(leftBelow) && getDensity(type) > getDensity(leftBelow))
        var canRight = rightBelow === tEmpty || (isLiquid(rightBelow) && getDensity(type) > getDensity(rightBelow))

        if (canLeft && canRight) {
            var dir = Math.random() < 0.5 ? -1 : 1
            swapCells(x, y, x + dir, y + 1)
        } else if (canLeft) {
            swapCells(x, y, x - 1, y + 1)
        } else if (canRight) {
            swapCells(x, y, x + 1, y + 1)
        } else {
            // Settle - reduce velocity
            velX[idx(x, y)] = vx * 0.8
            velY[idx(x, y)] = 0
        }
    }

    function updateWater(x, y, vx, vy) {
        var below = getCell(x, y + 1)
        var i = idx(x, y)

        // Fall
        if (below === tEmpty) {
            swapCells(x, y, x, y + 1)
            velY[idx(x, y + 1)] = vy + 0.5
            return
        }

        // Extinguish fire
        if (below === tFire) {
            setCell(x, y + 1, tSteam, 0, -1, 100)
            setCell(x, y, tEmpty, 0, 0, 0)
            return
        }

        // Cool lava
        if (below === tLava) {
            setCell(x, y + 1, tStone, 0, 0, 0)
            setCell(x, y, tSteam, 0, -1, 100)
            return
        }

        // Float on oil (water is denser)
        if (below === tOil) {
            swapCells(x, y, x, y + 1)
            return
        }

        // Try diagonal down
        var leftBelow = getCell(x - 1, y + 1)
        var rightBelow = getCell(x + 1, y + 1)

        if (leftBelow === tEmpty && rightBelow === tEmpty) {
            swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y + 1)
            return
        } else if (leftBelow === tEmpty) {
            swapCells(x, y, x - 1, y + 1)
            return
        } else if (rightBelow === tEmpty) {
            swapCells(x, y, x + 1, y + 1)
            return
        }

        // Flow horizontally with momentum
        var spreadDist = 3 + Math.floor(Math.abs(vx))
        var left = getCell(x - 1, y)
        var right = getCell(x + 1, y)

        // Follow momentum
        if (vx < -0.5 && left === tEmpty) {
            swapCells(x, y, x - 1, y)
            velX[idx(x - 1, y)] = vx * 0.95
        } else if (vx > 0.5 && right === tEmpty) {
            swapCells(x, y, x + 1, y)
            velX[idx(x + 1, y)] = vx * 0.95
        } else if (left === tEmpty && right === tEmpty) {
            var dir = Math.random() < 0.5 ? -1 : 1
            swapCells(x, y, x + dir, y)
            velX[idx(x + dir, y)] = dir * 0.5
        } else if (left === tEmpty) {
            swapCells(x, y, x - 1, y)
            velX[idx(x - 1, y)] = -0.5
        } else if (right === tEmpty) {
            swapCells(x, y, x + 1, y)
            velX[idx(x + 1, y)] = 0.5
        }
    }

    function updateOil(x, y, vx, vy) {
        var below = getCell(x, y + 1)

        // Fall
        if (below === tEmpty) {
            swapCells(x, y, x, y + 1)
            return
        }

        // Catch fire from fire/lava nearby
        for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
                var neighbor = getCell(x + dx, y + dy)
                if ((neighbor === tFire || neighbor === tLava) && Math.random() < 0.3) {
                    setCell(x, y, tFire, 0, 0, 150)
                    return
                }
            }
        }

        // Flow (similar to water but slower)
        var leftBelow = getCell(x - 1, y + 1)
        var rightBelow = getCell(x + 1, y + 1)

        if (leftBelow === tEmpty && rightBelow === tEmpty) {
            swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y + 1)
        } else if (leftBelow === tEmpty) {
            swapCells(x, y, x - 1, y + 1)
        } else if (rightBelow === tEmpty) {
            swapCells(x, y, x + 1, y + 1)
        } else {
            var left = getCell(x - 1, y)
            var right = getCell(x + 1, y)
            if (left === tEmpty && right === tEmpty) {
                swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y)
            } else if (left === tEmpty) {
                swapCells(x, y, x - 1, y)
            } else if (right === tEmpty) {
                swapCells(x, y, x + 1, y)
            }
        }
    }

    function updateLava(x, y, vx, vy) {
        var below = getCell(x, y + 1)

        // Set nearby flammables on fire
        for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
                if (dx === 0 && dy === 0) continue
                var nx = x + dx
                var ny = y + dy
                var neighbor = getCell(nx, ny)
                if ((neighbor === tWood || neighbor === tPlant || neighbor === tOil) && Math.random() < 0.1) {
                    setCell(nx, ny, tFire, 0, 0, 120)
                }
                if (neighbor === tIce) {
                    setCell(nx, ny, tWater, 0, 0, 0)
                }
                if (neighbor === tWater) {
                    setCell(nx, ny, tSteam, 0, -1, 100)
                    if (Math.random() < 0.3) {
                        setCell(x, y, tStone, 0, 0, 0)
                        return
                    }
                }
                if (neighbor === tGunpowder && Math.random() < 0.5) {
                    // Explosion!
                    explode(nx, ny, 5)
                }
            }
        }

        // Fall slowly
        if (below === tEmpty && Math.random() < 0.7) {
            swapCells(x, y, x, y + 1)
            return
        }

        // Flow very slowly
        if (Math.random() < 0.3) {
            var left = getCell(x - 1, y)
            var right = getCell(x + 1, y)
            if (left === tEmpty && right === tEmpty) {
                swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y)
            } else if (left === tEmpty) {
                swapCells(x, y, x - 1, y)
            } else if (right === tEmpty) {
                swapCells(x, y, x + 1, y)
            }
        }
    }

    function updateAcid(x, y, vx, vy) {
        var below = getCell(x, y + 1)

        // Dissolve nearby materials
        for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
                if (dx === 0 && dy === 0) continue
                var nx = x + dx
                var ny = y + dy
                var neighbor = getCell(nx, ny)
                // Dissolve most things except stone and other acid
                if (neighbor !== tEmpty && neighbor !== tStone && neighbor !== tAcid &&
                    neighbor !== tLava && Math.random() < 0.05) {
                    setCell(nx, ny, tEmpty, 0, 0, 0)
                    if (Math.random() < 0.3) {
                        setCell(x, y, tSmoke, 0, -0.5, 50)
                        return
                    }
                }
            }
        }

        // Fall
        if (below === tEmpty) {
            swapCells(x, y, x, y + 1)
            return
        }

        // Flow like water
        var leftBelow = getCell(x - 1, y + 1)
        var rightBelow = getCell(x + 1, y + 1)

        if (leftBelow === tEmpty && rightBelow === tEmpty) {
            swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y + 1)
        } else if (leftBelow === tEmpty) {
            swapCells(x, y, x - 1, y + 1)
        } else if (rightBelow === tEmpty) {
            swapCells(x, y, x + 1, y + 1)
        } else {
            var left = getCell(x - 1, y)
            var right = getCell(x + 1, y)
            if (left === tEmpty && right === tEmpty) {
                swapCells(x, y, x + (Math.random() < 0.5 ? -1 : 1), y)
            } else if (left === tEmpty) {
                swapCells(x, y, x - 1, y)
            } else if (right === tEmpty) {
                swapCells(x, y, x + 1, y)
            }
        }
    }

    function updateFire(x, y, cellLife) {
        var i = idx(x, y)
        cellLife--

        if (cellLife <= 0) {
            // Fire dies, maybe creates smoke
            if (Math.random() < 0.3) {
                setCell(x, y, tSmoke, (Math.random() - 0.5), -1, 80)
            } else {
                setCell(x, y, tEmpty, 0, 0, 0)
            }
            return
        }

        life[i] = cellLife

        // Spread to flammables
        for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
                if (dx === 0 && dy === 0) continue
                var nx = x + dx
                var ny = y + dy
                var neighbor = getCell(nx, ny)
                if (neighbor === tWood && Math.random() < 0.02) {
                    setCell(nx, ny, tFire, 0, 0, 200)
                }
                if (neighbor === tPlant && Math.random() < 0.05) {
                    setCell(nx, ny, tFire, 0, 0, 80)
                }
                if (neighbor === tOil && Math.random() < 0.2) {
                    setCell(nx, ny, tFire, 0, 0, 150)
                }
                if (neighbor === tGunpowder && Math.random() < 0.3) {
                    explode(nx, ny, 6)
                }
                if (neighbor === tIce) {
                    setCell(nx, ny, tWater, 0, 0, 0)
                }
            }
        }

        // Rise with some randomness
        var above = getCell(x, y - 1)
        if (above === tEmpty && Math.random() < 0.6) {
            swapCells(x, y, x, y - 1)
        } else {
            var dir = Math.random() < 0.5 ? -1 : 1
            if (getCell(x + dir, y - 1) === tEmpty && Math.random() < 0.3) {
                swapCells(x, y, x + dir, y - 1)
            }
        }
    }

    function updateSteam(x, y, cellLife) {
        var i = idx(x, y)
        cellLife--

        if (cellLife <= 0) {
            // Condense back to water
            if (Math.random() < 0.5) {
                setCell(x, y, tWater, 0, 0, 0)
            } else {
                setCell(x, y, tEmpty, 0, 0, 0)
            }
            return
        }

        life[i] = cellLife

        // Rise
        var above = getCell(x, y - 1)
        if (above === tEmpty) {
            swapCells(x, y, x, y - 1)
        } else {
            var dir = Math.random() < 0.5 ? -1 : 1
            if (getCell(x + dir, y) === tEmpty) {
                swapCells(x, y, x + dir, y)
            } else if (getCell(x + dir, y - 1) === tEmpty) {
                swapCells(x, y, x + dir, y - 1)
            }
        }
    }

    function updateSmoke(x, y, cellLife) {
        var i = idx(x, y)
        cellLife--

        if (cellLife <= 0) {
            setCell(x, y, tEmpty, 0, 0, 0)
            return
        }

        life[i] = cellLife

        // Rise with drift
        var above = getCell(x, y - 1)
        if (above === tEmpty && Math.random() < 0.7) {
            swapCells(x, y, x, y - 1)
        } else {
            var dir = Math.random() < 0.5 ? -1 : 1
            if (getCell(x + dir, y) === tEmpty) {
                swapCells(x, y, x + dir, y)
            }
        }
    }

    function updateIce(x, y) {
        // Freeze nearby water
        for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
                if (dx === 0 && dy === 0) continue
                var neighbor = getCell(x + dx, y + dy)
                if (neighbor === tWater && Math.random() < 0.01) {
                    setCell(x + dx, y + dy, tIce, 0, 0, 0)
                }
                // Melt from fire/lava
                if ((neighbor === tFire || neighbor === tLava) && Math.random() < 0.1) {
                    setCell(x, y, tWater, 0, 0, 0)
                    return
                }
            }
        }
    }

    function updateWood(x, y) {
        // Just check for fire neighbors
        for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
                var neighbor = getCell(x + dx, y + dy)
                if (neighbor === tFire && Math.random() < 0.01) {
                    setCell(x, y, tFire, 0, 0, 250)
                    return
                }
                if (neighbor === tLava && Math.random() < 0.02) {
                    setCell(x, y, tFire, 0, 0, 250)
                    return
                }
            }
        }
    }

    function updatePlant(x, y) {
        // Grow when touching water
        for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
                if (dx === 0 && dy === 0) continue
                var nx = x + dx
                var ny = y + dy
                var neighbor = getCell(nx, ny)

                if (neighbor === tWater && Math.random() < 0.02) {
                    // Consume water and grow
                    setCell(nx, ny, tPlant, 0, 0, 0)
                }

                // Burn easily
                if (neighbor === tFire && Math.random() < 0.1) {
                    setCell(x, y, tFire, 0, 0, 60)
                    return
                }
            }
        }

        // Random growth upward
        if (Math.random() < 0.001) {
            var above = getCell(x, y - 1)
            if (above === tEmpty) {
                setCell(x, y - 1, tPlant, 0, 0, 0)
            }
        }
    }

    function explode(cx, cy, radius) {
        Haptic.click()
        for (var dy = -radius; dy <= radius; dy++) {
            for (var dx = -radius; dx <= radius; dx++) {
                var dist = Math.sqrt(dx*dx + dy*dy)
                if (dist <= radius) {
                    var nx = cx + dx
                    var ny = cy + dy
                    if (inBounds(nx, ny)) {
                        var type = getCell(nx, ny)
                        if (type !== tStone) {
                            if (dist < radius * 0.5) {
                                setCell(nx, ny, tFire, (Math.random()-0.5)*3, (Math.random()-0.5)*3, 80)
                            } else if (Math.random() < 0.5) {
                                setCell(nx, ny, tSmoke, (Math.random()-0.5)*2, -2, 60)
                            } else {
                                setCell(nx, ny, tEmpty, 0, 0, 0)
                            }
                        }
                    }
                }
            }
        }
    }

    function getParticleColor(type, x, y) {
        var noise = ((x * 13 + y * 7) % 20) / 100  // Subtle variation
        switch (type) {
            case tSand:
                return Qt.rgba(0.83 + noise, 0.65 + noise, 0.46, 1)
            case tWater:
                return Qt.rgba(0.2, 0.5 + noise, 0.9 + noise * 0.5, 0.9)
            case tStone:
                return Qt.rgba(0.4 + noise, 0.4 + noise, 0.42 + noise, 1)
            case tFire:
                var flicker = Math.random() * 0.3
                return Qt.rgba(1, 0.3 + flicker, 0.1, 1)
            case tOil:
                return Qt.rgba(0.15 + noise, 0.1 + noise, 0.05, 1)
            case tLava:
                var glow = Math.random() * 0.2
                return Qt.rgba(1, 0.2 + glow, 0, 1)
            case tSteam:
                return Qt.rgba(0.8, 0.85, 0.9, 0.5)
            case tWood:
                return Qt.rgba(0.4 + noise, 0.25 + noise, 0.1, 1)
            case tIce:
                return Qt.rgba(0.7, 0.85 + noise, 1, 0.9)
            case tAcid:
                return Qt.rgba(0.3, 0.9 + noise * 0.5, 0.2, 0.9)
            case tSmoke:
                return Qt.rgba(0.3, 0.3, 0.35, 0.6)
            case tPlant:
                return Qt.rgba(0.2, 0.6 + noise, 0.15, 1)
            case tGunpowder:
                return Qt.rgba(0.25 + noise, 0.25, 0.25, 1)
            case tSalt:
                return Qt.rgba(0.95, 0.95, 0.9 + noise, 1)
            default:
                return "#0a0a0f"
        }
    }

    Canvas {
        id: canvas
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: toolbar.top

        onPaint: {
            var ctx = getContext("2d")
            ctx.fillStyle = "#0a0a0f"
            ctx.fillRect(0, 0, width, height)

            for (var y = 0; y < gridHeight; y++) {
                for (var x = 0; x < gridWidth; x++) {
                    var cell = grid[idx(x, y)]
                    if (cell !== tEmpty) {
                        ctx.fillStyle = getParticleColor(cell, x, y)
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
                drawBrush(gridX, gridY, selectedType)
                lastDrawX = gridX
                lastDrawY = gridY
                Haptic.tap()
            }

            onPositionChanged: {
                if (isDrawing) {
                    var gridX = Math.floor(mouse.x / cellSize)
                    var gridY = Math.floor(mouse.y / cellSize)
                    // Interpolate for smooth drawing
                    var dx = gridX - lastDrawX
                    var dy = gridY - lastDrawY
                    var steps = Math.max(Math.abs(dx), Math.abs(dy))
                    for (var i = 0; i <= steps; i++) {
                        var t = steps > 0 ? i / steps : 0
                        var ix = Math.round(lastDrawX + dx * t)
                        var iy = Math.round(lastDrawY + dy * t)
                        drawBrush(ix, iy, selectedType)
                    }
                    lastDrawX = gridX
                    lastDrawY = gridY
                }
            }

            onReleased: {
                isDrawing = false
            }
        }
    }

    // Particle selector toolbar
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

            // Brush size slider
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
                    to: 10
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

            // Particle grid - row 1
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
                        width: 105
                        height: 60
                        radius: 10
                        color: selectedType === modelData.type ? "#e94560" : "#222233"
                        border.color: selectedType === modelData.type ? "#fff" : "transparent"
                        border.width: 2

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            Rectangle {
                                width: 24
                                height: 24
                                radius: 12
                                color: modelData.color
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: modelData.name
                                font.pixelSize: 10 * textScale
                                color: "#ffffff"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                selectedType = modelData.type
                                Haptic.tap()
                            }
                        }
                    }
                }
            }

            // Particle grid - row 2
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
                        width: 105
                        height: 60
                        radius: 10
                        color: selectedType === modelData.type ? "#e94560" : "#222233"
                        border.color: selectedType === modelData.type ? "#fff" : "transparent"
                        border.width: 2

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            Rectangle {
                                width: 24
                                height: 24
                                radius: 12
                                color: modelData.color
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: modelData.name
                                font.pixelSize: 10 * textScale
                                color: "#ffffff"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                selectedType = modelData.type
                                Haptic.tap()
                            }
                        }
                    }
                }
            }

            // Bottom row: Salt, Eraser, Clear
            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    width: 105
                    height: 50
                    radius: 10
                    color: selectedType === tSalt ? "#e94560" : "#222233"
                    border.color: selectedType === tSalt ? "#fff" : "transparent"
                    border.width: 2

                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            color: "#f5f5ee"
                        }
                        Text {
                            text: "Salt"
                            font.pixelSize: 11 * textScale
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            selectedType = tSalt
                            Haptic.tap()
                        }
                    }
                }

                Rectangle {
                    width: 105
                    height: 50
                    radius: 10
                    color: selectedType === tEmpty ? "#e94560" : "#222233"
                    border.color: selectedType === tEmpty ? "#fff" : "transparent"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: "Eraser"
                        font.pixelSize: 12 * textScale
                        color: "#ffffff"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            selectedType = tEmpty
                            Haptic.tap()
                        }
                    }
                }

                Rectangle {
                    width: 105
                    height: 50
                    radius: 10
                    color: clearMouse.pressed ? "#aa3344" : "#222233"

                    Text {
                        anchors.centerIn: parent
                        text: "Clear All"
                        font.pixelSize: 12 * textScale
                        color: "#ff6666"
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        onClicked: {
                            clearGrid()
                            Haptic.click()
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 50  // 20 FPS for physics (balanced)
        running: true
        repeat: true
        onTriggered: updateParticles()
    }

    // Back button
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: toolbar.top
        anchors.leftMargin: 16
        anchors.bottomMargin: 16
        width: 56
        height: 56
        radius: 28
        color: backMouse.pressed ? "#c23a50" : "#e94560"
        z: 10

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 28
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
