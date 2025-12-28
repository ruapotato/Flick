import QtQuick 2.15
import QtQuick.Window 2.15
import QtMultimedia 5.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Distract"
    color: "#0a0a0f"

    property int currentEffect: 0
    property int exitTapCount: 0
    property var exitTimer: null
    property real globalTime: 0

    // Effect types - now with 25 effects including life/growth
    readonly property var effectTypes: [
        "fireworks",
        "bubbles",
        "rainbow",
        "sparkles",
        "paint",
        "balls",
        "confetti",
        "kaleidoscope",
        "lightning",
        "flowers",
        "snow",
        "neon",
        "shapes",
        "galaxy",
        "rain",
        "life",           // cellular automata that grows
        "tree",           // growing tree/branches
        "spiral",         // hypnotic spiral
        "waves",          // wave interference
        "hearts",         // floating hearts
        "stars",          // twinkling stars
        "lava",           // lava lamp blobs
        "matrix",         // falling code
        "disco",          // disco ball reflections
        "aurora"          // northern lights
    ]

    // Global time for animations
    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: globalTime += 0.016
    }

    // Random effect selection
    function getRandomEffect() {
        return Math.floor(Math.random() * effectTypes.length)
    }

    // Sound generator using Audio element with tone generation
    // This creates a simple beep sound at different frequencies
    Audio {
        id: tonePlayer
        source: ""
        volume: 0.5
    }

    // Play a generated tone based on position
    function playTone(x, y) {
        // Use haptic as primary feedback
        Haptic.tap()

        // Create visual "sound wave" effect
        var normX = x / root.width
        var normY = y / root.height

        // Create multiple concentric rings for sound visualization
        var numRings = 3 + Math.floor((1 - normY) * 4)
        var baseHue = normX

        for (var i = 0; i < numRings; i++) {
            var ring = soundWaveComponent.createObject(root, {
                centerX: x,
                centerY: y,
                ringIndex: i,
                totalRings: numRings,
                hue: baseHue,
                intensity: 1 - normY
            })
        }
    }

    // Sound wave visualization component
    Component {
        id: soundWaveComponent
        Rectangle {
            id: soundWave
            property real centerX: 0
            property real centerY: 0
            property int ringIndex: 0
            property int totalRings: 3
            property real hue: 0.5
            property real intensity: 0.5

            x: centerX - width/2
            y: centerY - height/2
            width: 50
            height: 50
            radius: width/2
            color: "transparent"
            border.width: 3 + intensity * 3
            border.color: Qt.hsla(hue, 0.8, 0.6, 0.9)
            scale: 0.2
            opacity: 0
            z: 40

            SequentialAnimation {
                running: true
                PauseAnimation { duration: ringIndex * 60 }
                ParallelAnimation {
                    NumberAnimation {
                        target: soundWave
                        property: "scale"
                        to: 2 + intensity * 2
                        duration: 400 + intensity * 200
                        easing.type: Easing.OutQuad
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: soundWave
                            property: "opacity"
                            to: 0.8
                            duration: 80
                        }
                        NumberAnimation {
                            target: soundWave
                            property: "opacity"
                            to: 0
                            duration: 320 + intensity * 200
                        }
                    }
                }
                ScriptAction { script: soundWave.destroy() }
            }
        }
    }

    // Triple-tap exit mechanism for top-left corner
    MouseArea {
        id: exitArea
        x: 0
        y: 0
        width: 150
        height: 150
        z: 100

        onClicked: {
            if (exitTimer) {
                exitTimer.stop()
            }
            exitTapCount++

            if (exitTapCount >= 3) {
                Qt.quit()
            }

            exitTimer = Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 1000; running: true; onTriggered: exitTapCount = 0 }', root)
        }
    }

    // Main tap area
    MouseArea {
        anchors.fill: parent
        z: 1

        onPressed: {
            var x = mouse.x
            var y = mouse.y

            // Play sound/haptic with visual feedback
            playTone(x, y)

            // Cycle to random effect (but not the same as current)
            var newEffect = currentEffect
            while (newEffect === currentEffect && effectTypes.length > 1) {
                newEffect = getRandomEffect()
            }
            currentEffect = newEffect

            // Trigger the current effect
            triggerEffect(x, y)
        }
    }

    function triggerEffect(x, y) {
        var effect = effectTypes[currentEffect]

        switch(effect) {
            case "fireworks": createFireworks(x, y); break
            case "bubbles": createBubbles(x, y); break
            case "rainbow": createRainbow(x, y); break
            case "sparkles": createSparkles(x, y); break
            case "paint": createPaint(x, y); break
            case "balls": createBalls(x, y); break
            case "confetti": createConfetti(x, y); break
            case "kaleidoscope": createKaleidoscope(x, y); break
            case "lightning": createLightning(x, y); break
            case "flowers": createFlowers(x, y); break
            case "snow": createSnow(x, y); break
            case "neon": createNeon(x, y); break
            case "shapes": createShapes(x, y); break
            case "galaxy": createGalaxy(x, y); break
            case "rain": createRain(x, y); break
            case "life": createLife(x, y); break
            case "tree": createTree(x, y); break
            case "spiral": createSpiral(x, y); break
            case "waves": createWaves(x, y); break
            case "hearts": createHearts(x, y); break
            case "stars": createStars(x, y); break
            case "lava": createLava(x, y); break
            case "matrix": createMatrix(x, y); break
            case "disco": createDisco(x, y); break
            case "aurora": createAurora(x, y); break
        }
    }

    // ==================== ORIGINAL EFFECTS ====================

    // Fireworks effect
    function createFireworks(x, y) {
        var colors = ["#ff3355", "#ffaa33", "#33ff77", "#3388ff", "#ff33ff", "#ffff33"]
        for (var i = 0; i < 30; i++) {
            var angle = (Math.PI * 2 * i) / 30
            var speed = 200 + Math.random() * 200
            var particle = particleComponent.createObject(root, {
                x: x, y: y,
                vx: Math.cos(angle) * speed,
                vy: Math.sin(angle) * speed,
                color: colors[Math.floor(Math.random() * colors.length)],
                size: 8 + Math.random() * 8,
                lifetime: 1500 + Math.random() * 500
            })
        }
    }

    // Bubbles effect
    function createBubbles(x, y) {
        for (var i = 0; i < 15; i++) {
            var bubble = bubbleComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 200,
                y: y + (Math.random() - 0.5) * 200,
                size: 40 + Math.random() * 80,
                lifetime: 2000 + Math.random() * 2000
            })
        }
    }

    // Rainbow ripples effect
    function createRainbow(x, y) {
        var colors = ["#ff0000", "#ff7700", "#ffff00", "#00ff00", "#0088ff", "#4400ff", "#8800ff"]
        for (var i = 0; i < 7; i++) {
            var ripple = rippleComponent.createObject(root, {
                x: x, y: y,
                color: colors[i],
                delay: i * 100
            })
        }
    }

    // Sparkles effect
    function createSparkles(x, y) {
        for (var i = 0; i < 50; i++) {
            var angle = Math.random() * Math.PI * 2
            var distance = Math.random() * 300
            var sparkle = sparkleComponent.createObject(root, {
                x: x + Math.cos(angle) * distance,
                y: y + Math.sin(angle) * distance,
                size: 4 + Math.random() * 8,
                lifetime: 1000 + Math.random() * 1000
            })
        }
    }

    // Paint splatter effect
    function createPaint(x, y) {
        var colors = ["#ff3355", "#33ff88", "#3388ff", "#ffaa33", "#ff33ff", "#ffff33"]
        for (var i = 0; i < 20; i++) {
            var angle = Math.random() * Math.PI * 2
            var speed = 100 + Math.random() * 300
            var splat = splatComponent.createObject(root, {
                x: x, y: y,
                vx: Math.cos(angle) * speed,
                vy: Math.sin(angle) * speed,
                color: colors[Math.floor(Math.random() * colors.length)],
                size: 20 + Math.random() * 40,
                lifetime: 2000
            })
        }
    }

    // Bouncing balls effect
    function createBalls(x, y) {
        var colors = ["#ff3355", "#33ff88", "#3388ff", "#ffaa33"]
        for (var i = 0; i < 5; i++) {
            var ball = bouncingBallComponent.createObject(root, {
                x: x, y: y,
                vx: (Math.random() - 0.5) * 400,
                vy: -200 - Math.random() * 200,
                color: colors[Math.floor(Math.random() * colors.length)],
                size: 40 + Math.random() * 40
            })
        }
    }

    // Confetti effect
    function createConfetti(x, y) {
        var colors = ["#ff3355", "#33ff88", "#3388ff", "#ffaa33", "#ff33ff", "#ffff33"]
        for (var i = 0; i < 40; i++) {
            var confetto = confettiComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 100,
                y: y - Math.random() * 100,
                vx: (Math.random() - 0.5) * 200,
                vy: -100 - Math.random() * 200,
                color: colors[Math.floor(Math.random() * colors.length)],
                rotation: Math.random() * 360,
                lifetime: 3000 + Math.random() * 1000
            })
        }
    }

    // Kaleidoscope effect
    function createKaleidoscope(x, y) {
        var colors = ["#ff3355", "#33ff88", "#3388ff", "#ffaa33", "#ff33ff"]
        var segments = 12
        for (var i = 0; i < segments; i++) {
            var angle = (Math.PI * 2 * i) / segments
            var kaleido = kaleidoComponent.createObject(root, {
                centerX: x, centerY: y,
                angle: angle,
                color: colors[i % colors.length],
                lifetime: 1500
            })
        }
    }

    // Lightning effect
    function createLightning(x, y) {
        var lightning = lightningComponent.createObject(root, {
            startX: x,
            startY: 0,
            endX: x + (Math.random() - 0.5) * 200,
            endY: y,
            lifetime: 400
        })
    }

    // Flower bloom effect
    function createFlowers(x, y) {
        var colors = ["#ff3388", "#ff88cc", "#ffaadd", "#ff5599"]
        for (var i = 0; i < 8; i++) {
            var angle = (Math.PI * 2 * i) / 8
            var petal = petalComponent.createObject(root, {
                centerX: x, centerY: y,
                angle: angle,
                color: colors[Math.floor(Math.random() * colors.length)],
                lifetime: 1500
            })
        }
        // Center
        var center = Qt.createQmlObject('import QtQuick 2.15; Rectangle { color: "#ffff44"; width: 30; height: 30; radius: 15; z: 10 }', root)
        center.x = x - 15
        center.y = y - 15
        Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 1500; running: true; onTriggered: parent.destroy() }', center)
    }

    // Snow effect
    function createSnow(x, y) {
        for (var i = 0; i < 30; i++) {
            var snowflake = snowComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 400,
                y: y - 200,
                size: 8 + Math.random() * 16,
                lifetime: 3000 + Math.random() * 2000
            })
        }
    }

    // Neon trail effect
    function createNeon(x, y) {
        var colors = ["#ff00ff", "#00ffff", "#ff0088", "#00ff88"]
        for (var i = 0; i < 20; i++) {
            var angle = Math.random() * Math.PI * 2
            var distance = Math.random() * 250
            var neon = neonComponent.createObject(root, {
                x: x, y: y,
                targetX: x + Math.cos(angle) * distance,
                targetY: y + Math.sin(angle) * distance,
                color: colors[Math.floor(Math.random() * colors.length)],
                lifetime: 800
            })
        }
    }

    // Morphing shapes effect
    function createShapes(x, y) {
        var shape = shapeComponent.createObject(root, {
            x: x - 60,
            y: y - 60,
            lifetime: 2000
        })
    }

    // Galaxy swirl effect
    function createGalaxy(x, y) {
        for (var i = 0; i < 50; i++) {
            var angle = (Math.random() * Math.PI * 2)
            var distance = Math.random() * 250
            var star = starComponent.createObject(root, {
                centerX: x, centerY: y,
                angle: angle,
                distance: distance,
                color: i % 3 === 0 ? "#ffffff" : (i % 3 === 1 ? "#aaccff" : "#ffaacc"),
                lifetime: 2500
            })
        }
    }

    // Rain effect
    function createRain(x, y) {
        for (var i = 0; i < 25; i++) {
            var drop = rainComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 300,
                y: y - 400 - Math.random() * 200,
                targetY: y,
                lifetime: 1500
            })
        }
    }

    // ==================== NEW EFFECTS ====================

    // Life - cellular automata that grows
    function createLife(x, y) {
        var life = lifeComponent.createObject(root, {
            centerX: x,
            centerY: y
        })
    }

    // Growing tree/branches
    function createTree(x, y) {
        createBranch(x, y, -Math.PI/2, 100, 5, 0)
    }

    function createBranch(x, y, angle, length, thickness, depth) {
        if (depth > 6 || length < 10) return

        var branch = branchComponent.createObject(root, {
            startX: x,
            startY: y,
            angle: angle,
            length: length,
            thickness: thickness,
            depth: depth
        })
    }

    // Hypnotic spiral
    function createSpiral(x, y) {
        var spiral = spiralComponent.createObject(root, {
            centerX: x,
            centerY: y
        })
    }

    // Wave interference pattern
    function createWaves(x, y) {
        var wave = waveComponent.createObject(root, {
            centerX: x,
            centerY: y
        })
    }

    // Floating hearts
    function createHearts(x, y) {
        var colors = ["#ff3366", "#ff6699", "#ff99cc", "#ffccee"]
        for (var i = 0; i < 15; i++) {
            var heart = heartComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 200,
                y: y,
                size: 20 + Math.random() * 40,
                color: colors[Math.floor(Math.random() * colors.length)]
            })
        }
    }

    // Twinkling stars
    function createStars(x, y) {
        for (var i = 0; i < 30; i++) {
            var twinkle = twinkleComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 400,
                y: y + (Math.random() - 0.5) * 400,
                size: 10 + Math.random() * 20
            })
        }
    }

    // Lava lamp blobs
    function createLava(x, y) {
        var colors = ["#ff3300", "#ff6600", "#ff9900", "#ffcc00"]
        for (var i = 0; i < 8; i++) {
            var blob = lavaComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 200,
                y: y,
                size: 60 + Math.random() * 80,
                color: colors[Math.floor(Math.random() * colors.length)]
            })
        }
    }

    // Matrix falling code
    function createMatrix(x, y) {
        for (var i = 0; i < 20; i++) {
            var column = matrixComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 400,
                startY: y - 200
            })
        }
    }

    // Disco ball reflections
    function createDisco(x, y) {
        for (var i = 0; i < 25; i++) {
            var angle = Math.random() * Math.PI * 2
            var light = discoComponent.createObject(root, {
                centerX: x,
                centerY: y,
                angle: angle
            })
        }
    }

    // Aurora borealis
    function createAurora(x, y) {
        var aurora = auroraComponent.createObject(root, {
            centerX: x,
            centerY: y
        })
    }

    // ==================== COMPONENTS ====================

    // Particle component
    Component {
        id: particleComponent
        Rectangle {
            id: particle
            property real vx: 0
            property real vy: 0
            property int lifetime: 1000
            property real gravity: 400
            property real size: 8

            width: size
            height: size
            radius: size / 2
            z: 5
            opacity: 1.0

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: {
                    particle.x += particle.vx * 0.016
                    particle.y += particle.vy * 0.016
                    particle.vy += particle.gravity * 0.016
                }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: particle.destroy()
            }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.7 }
                NumberAnimation { to: 0; duration: lifetime * 0.3 }
            }
        }
    }

    // Bubble component
    Component {
        id: bubbleComponent
        Rectangle {
            id: bubble
            property int lifetime: 2000
            property real size: 60
            property real vy: -100

            width: size
            height: size
            radius: size / 2
            color: "transparent"
            border.color: Qt.rgba(Math.random(), Math.random(), Math.random(), 0.7)
            border.width: 3
            z: 5
            scale: 0.1

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: {
                    bubble.y += bubble.vy * 0.016
                    bubble.x += Math.sin(bubble.y * 0.05) * 2
                }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: bubble.destroy()
            }

            NumberAnimation on scale { to: 1.0; duration: 300; easing.type: Easing.OutBack }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.8 }
                NumberAnimation { to: 0; duration: lifetime * 0.2 }
            }
        }
    }

    // Ripple component
    Component {
        id: rippleComponent
        Rectangle {
            id: ripple
            property int delay: 0
            property int lifetime: 1500

            width: 20
            height: 20
            radius: 10
            color: "transparent"
            border.width: 4
            opacity: 0.8
            z: 5

            Timer {
                interval: delay
                running: true
                onTriggered: { scaleAnim.start(); fadeAnim.start() }
            }

            NumberAnimation { id: scaleAnim; target: ripple; property: "scale"; from: 1; to: 30; duration: lifetime; easing.type: Easing.OutQuad }
            NumberAnimation { id: fadeAnim; target: ripple; property: "opacity"; from: 0.8; to: 0; duration: lifetime }

            Timer { interval: lifetime + delay; running: true; onTriggered: ripple.destroy() }
        }
    }

    // Sparkle component
    Component {
        id: sparkleComponent
        Rectangle {
            id: sparkle
            property int lifetime: 1000
            property real size: 6

            width: size
            height: size
            radius: size / 2
            color: "#ffffff"
            z: 5
            scale: 0

            SequentialAnimation on scale {
                NumberAnimation { to: 1.5; duration: lifetime * 0.3; easing.type: Easing.OutBack }
                NumberAnimation { to: 0; duration: lifetime * 0.7; easing.type: Easing.InQuad }
            }

            Timer { interval: lifetime; running: true; onTriggered: sparkle.destroy() }
        }
    }

    // Splat component
    Component {
        id: splatComponent
        Rectangle {
            id: splat
            property real vx: 0
            property real vy: 0
            property int lifetime: 2000
            property real size: 30
            property real friction: 0.95

            width: size
            height: size
            radius: size / 2
            z: 5
            scale: 0.5

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: {
                    splat.x += splat.vx * 0.016
                    splat.y += splat.vy * 0.016
                    splat.vx *= splat.friction
                    splat.vy *= splat.friction
                }
            }

            NumberAnimation on scale { to: 1.0; duration: 200; easing.type: Easing.OutBack }
            Timer { interval: lifetime; running: true; onTriggered: splat.destroy() }
        }
    }

    // Bouncing ball component
    Component {
        id: bouncingBallComponent
        Rectangle {
            id: ball
            property real vx: 0
            property real vy: 0
            property real gravity: 800
            property real bounce: 0.7
            property int lifetime: 4000
            property real size: 50

            width: size
            height: size
            radius: size / 2
            z: 5

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: {
                    ball.x += ball.vx * 0.016
                    ball.y += ball.vy * 0.016
                    ball.vy += ball.gravity * 0.016
                    if (ball.y > root.height - ball.size) { ball.y = root.height - ball.size; ball.vy *= -ball.bounce }
                    if (ball.x < 0) { ball.x = 0; ball.vx *= -ball.bounce }
                    if (ball.x > root.width - ball.size) { ball.x = root.width - ball.size; ball.vx *= -ball.bounce }
                }
            }

            Timer { interval: lifetime; running: true; onTriggered: ball.destroy() }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.8 }
                NumberAnimation { to: 0; duration: lifetime * 0.2 }
            }
        }
    }

    // Confetti component
    Component {
        id: confettiComponent
        Rectangle {
            id: confetto
            property real vx: 0
            property real vy: 0
            property real gravity: 500
            property int lifetime: 3000
            property real rotationSpeed: (Math.random() - 0.5) * 720

            width: 12
            height: 20
            radius: 2
            z: 5

            transform: Rotation { id: rot; angle: 0; origin.x: 6; origin.y: 10 }

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: {
                    confetto.x += confetto.vx * 0.016
                    confetto.y += confetto.vy * 0.016
                    confetto.vy += confetto.gravity * 0.016
                    rot.angle += confetto.rotationSpeed * 0.016
                }
            }

            Timer { interval: lifetime; running: true; onTriggered: confetto.destroy() }
        }
    }

    // Kaleidoscope component
    Component {
        id: kaleidoComponent
        Rectangle {
            id: kaleido
            property real centerX: 0
            property real centerY: 0
            property real angle: 0
            property int lifetime: 1500
            property real distance: 0

            width: 60
            height: 60
            radius: 30
            z: 5

            x: centerX + Math.cos(angle) * distance - 30
            y: centerY + Math.sin(angle) * distance - 30

            NumberAnimation on distance { from: 0; to: 200; duration: lifetime; easing.type: Easing.OutQuad }
            NumberAnimation on rotation { from: 0; to: 360; duration: lifetime }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.6 }
                NumberAnimation { to: 0; duration: lifetime * 0.4 }
            }

            Timer { interval: lifetime; running: true; onTriggered: kaleido.destroy() }
        }
    }

    // Lightning component
    Component {
        id: lightningComponent
        Canvas {
            id: lightning
            property real startX: 0
            property real startY: 0
            property real endX: 0
            property real endY: 0
            property int lifetime: 400

            width: root.width
            height: root.height
            z: 20

            onPaint: {
                var ctx = getContext("2d")
                ctx.strokeStyle = "#88ccff"
                ctx.lineWidth = 4
                ctx.lineCap = "round"
                ctx.beginPath()
                var segments = 8
                var currentX = startX
                var currentY = startY
                ctx.moveTo(currentX, currentY)
                for (var i = 0; i < segments; i++) {
                    var progress = (i + 1) / segments
                    var nextX = startX + (endX - startX) * progress + (Math.random() - 0.5) * 50
                    var nextY = startY + (endY - startY) * progress
                    ctx.lineTo(nextX, nextY)
                }
                ctx.stroke()
            }

            Component.onCompleted: requestPaint()

            SequentialAnimation on opacity {
                NumberAnimation { to: 0; duration: 100 }
                NumberAnimation { to: 1; duration: 50 }
                NumberAnimation { to: 0; duration: 100 }
                NumberAnimation { to: 0.7; duration: 50 }
                NumberAnimation { to: 0; duration: 100 }
            }

            Timer { interval: lifetime; running: true; onTriggered: lightning.destroy() }
        }
    }

    // Petal component
    Component {
        id: petalComponent
        Rectangle {
            id: petal
            property real centerX: 0
            property real centerY: 0
            property real angle: 0
            property int lifetime: 1500
            property real distance: 0

            width: 40
            height: 60
            radius: 20
            z: 5
            scale: 0

            x: centerX + Math.cos(angle) * distance - 20
            y: centerY + Math.sin(angle) * distance - 30

            SequentialAnimation on scale {
                NumberAnimation { to: 1.0; duration: lifetime * 0.3; easing.type: Easing.OutBack }
                PauseAnimation { duration: lifetime * 0.4 }
                NumberAnimation { to: 0; duration: lifetime * 0.3 }
            }

            NumberAnimation on distance { from: 0; to: 80; duration: lifetime * 0.3; easing.type: Easing.OutQuad }

            Timer { interval: lifetime; running: true; onTriggered: petal.destroy() }
        }
    }

    // Snow component
    Component {
        id: snowComponent
        Rectangle {
            id: snow
            property int lifetime: 3000
            property real size: 12

            width: size
            height: size
            radius: size / 2
            color: "#ffffff"
            z: 5

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: {
                    snow.y += (100 + Math.random() * 100) * 0.016
                    snow.x += Math.sin(snow.y * 0.02) * 1
                }
            }

            Timer { interval: lifetime; running: true; onTriggered: snow.destroy() }
        }
    }

    // Neon component
    Component {
        id: neonComponent
        Rectangle {
            id: neon
            property real targetX: 0
            property real targetY: 0
            property int lifetime: 800

            width: 8
            height: 8
            radius: 4
            z: 5

            NumberAnimation on x { to: targetX; duration: lifetime; easing.type: Easing.OutQuad }
            NumberAnimation on y { to: targetY; duration: lifetime; easing.type: Easing.OutQuad }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.5 }
                NumberAnimation { to: 0; duration: lifetime * 0.5 }
            }

            Timer { interval: lifetime; running: true; onTriggered: neon.destroy() }
        }
    }

    // Shape component
    Component {
        id: shapeComponent
        Rectangle {
            id: shape
            property int lifetime: 2000

            width: 120
            height: 120
            color: Qt.rgba(Math.random(), Math.random(), Math.random(), 0.8)
            z: 5
            scale: 0

            SequentialAnimation on scale {
                NumberAnimation { to: 1.5; duration: lifetime * 0.5; easing.type: Easing.OutBack }
                NumberAnimation { to: 0; duration: lifetime * 0.5; easing.type: Easing.InBack }
            }

            NumberAnimation on rotation { from: 0; to: 360; duration: lifetime }

            SequentialAnimation on radius {
                NumberAnimation { to: 60; duration: lifetime * 0.33 }
                NumberAnimation { to: 0; duration: lifetime * 0.33 }
                NumberAnimation { to: 30; duration: lifetime * 0.34 }
            }

            Timer { interval: lifetime; running: true; onTriggered: shape.destroy() }
        }
    }

    // Star component (galaxy)
    Component {
        id: starComponent
        Rectangle {
            id: star
            property real centerX: 0
            property real centerY: 0
            property real angle: 0
            property real distance: 100
            property int lifetime: 2500
            property real currentAngle: angle

            width: 6
            height: 6
            radius: 3
            z: 5

            x: centerX + Math.cos(currentAngle) * distance - 3
            y: centerY + Math.sin(currentAngle) * distance - 3

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: star.currentAngle += 0.05
            }

            NumberAnimation on distance { from: distance; to: 10; duration: lifetime; easing.type: Easing.InQuad }

            Timer { interval: lifetime; running: true; onTriggered: star.destroy() }
        }
    }

    // Rain component
    Component {
        id: rainComponent
        Rectangle {
            id: drop
            property real targetY: 0
            property int lifetime: 1500

            width: 4
            height: 20
            radius: 2
            color: "#4488ff"
            z: 5

            NumberAnimation on y { to: targetY; duration: lifetime * 0.7; easing.type: Easing.InQuad }

            Timer { interval: lifetime; running: true; onTriggered: drop.destroy() }
        }
    }

    // ==================== NEW EFFECT COMPONENTS ====================

    // Life component - cellular automata
    Component {
        id: lifeComponent
        Item {
            id: life
            property real centerX: 0
            property real centerY: 0
            property var cells: []
            property int gridSize: 20
            property int cellSize: 16
            property int generation: 0

            width: gridSize * cellSize
            height: gridSize * cellSize
            x: centerX - width/2
            y: centerY - height/2
            z: 5

            Component.onCompleted: {
                // Initialize with random pattern
                cells = []
                for (var i = 0; i < gridSize * gridSize; i++) {
                    cells.push(Math.random() < 0.3)
                }
                updateCanvas()
            }

            Canvas {
                id: lifeCanvas
                anchors.fill: parent

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    var colors = ["#00ff88", "#00ffaa", "#00ffcc", "#00ffee"]

                    for (var i = 0; i < life.cells.length; i++) {
                        if (life.cells[i]) {
                            var x = (i % life.gridSize) * life.cellSize
                            var y = Math.floor(i / life.gridSize) * life.cellSize
                            ctx.fillStyle = colors[Math.floor(Math.random() * colors.length)]
                            ctx.fillRect(x + 1, y + 1, life.cellSize - 2, life.cellSize - 2)
                        }
                    }
                }
            }

            function updateCanvas() {
                lifeCanvas.requestPaint()
            }

            function getCell(x, y) {
                if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return false
                return cells[y * gridSize + x]
            }

            function countNeighbors(x, y) {
                var count = 0
                for (var dy = -1; dy <= 1; dy++) {
                    for (var dx = -1; dx <= 1; dx++) {
                        if (dx === 0 && dy === 0) continue
                        if (getCell(x + dx, y + dy)) count++
                    }
                }
                return count
            }

            Timer {
                interval: 150
                running: true
                repeat: true
                onTriggered: {
                    life.generation++
                    if (life.generation > 30) {
                        life.destroy()
                        return
                    }

                    var newCells = []
                    for (var i = 0; i < life.gridSize * life.gridSize; i++) {
                        var x = i % life.gridSize
                        var y = Math.floor(i / life.gridSize)
                        var neighbors = life.countNeighbors(x, y)
                        var alive = life.cells[i]

                        if (alive) {
                            newCells.push(neighbors === 2 || neighbors === 3)
                        } else {
                            newCells.push(neighbors === 3)
                        }
                    }
                    life.cells = newCells
                    life.updateCanvas()
                }
            }

            NumberAnimation on opacity { from: 1; to: 0; duration: 4500; easing.type: Easing.InQuad }
        }
    }

    // Branch component for tree
    Component {
        id: branchComponent
        Canvas {
            id: branch
            property real startX: 0
            property real startY: 0
            property real angle: 0
            property real length: 100
            property real thickness: 5
            property int depth: 0
            property real growProgress: 0

            width: root.width
            height: root.height
            z: 5

            onPaint: {
                var ctx = getContext("2d")
                ctx.strokeStyle = depth < 3 ? "#8B4513" : "#228B22"
                ctx.lineWidth = thickness
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.moveTo(startX, startY)
                var endX = startX + Math.cos(angle) * length * growProgress
                var endY = startY + Math.sin(angle) * length * growProgress
                ctx.lineTo(endX, endY)
                ctx.stroke()
            }

            NumberAnimation on growProgress {
                from: 0
                to: 1
                duration: 300
                easing.type: Easing.OutQuad
                onFinished: {
                    // Spawn child branches
                    if (depth < 6 && length > 15) {
                        var endX = startX + Math.cos(angle) * length
                        var endY = startY + Math.sin(angle) * length
                        var newLength = length * 0.7
                        var newThickness = thickness * 0.7

                        createBranch(endX, endY, angle - 0.4 - Math.random() * 0.3, newLength, newThickness, depth + 1)
                        createBranch(endX, endY, angle + 0.4 + Math.random() * 0.3, newLength, newThickness, depth + 1)
                    }
                }
            }

            onGrowProgressChanged: requestPaint()

            Timer { interval: 5000; running: true; onTriggered: branch.destroy() }

            SequentialAnimation on opacity {
                PauseAnimation { duration: 4000 }
                NumberAnimation { to: 0; duration: 1000 }
            }
        }
    }

    // Spiral component
    Component {
        id: spiralComponent
        Canvas {
            id: spiral
            property real centerX: 0
            property real centerY: 0
            property real rotation: 0

            width: root.width
            height: root.height
            z: 5

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var arms = 6
                for (var arm = 0; arm < arms; arm++) {
                    var armAngle = (Math.PI * 2 * arm) / arms + rotation
                    ctx.beginPath()
                    ctx.strokeStyle = Qt.hsla(arm / arms, 0.8, 0.5, 0.8)
                    ctx.lineWidth = 4

                    for (var t = 0; t < 300; t += 5) {
                        var angle = armAngle + t * 0.05
                        var radius = t * 0.8
                        var x = centerX + Math.cos(angle) * radius
                        var y = centerY + Math.sin(angle) * radius
                        if (t === 0) ctx.moveTo(x, y)
                        else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
            }

            NumberAnimation on rotation {
                from: 0
                to: Math.PI * 2
                duration: 3000
                loops: 1
            }

            onRotationChanged: requestPaint()

            Timer { interval: 3000; running: true; onTriggered: spiral.destroy() }

            NumberAnimation on opacity { from: 1; to: 0; duration: 3000 }
        }
    }

    // Wave component
    Component {
        id: waveComponent
        Canvas {
            id: wave
            property real centerX: 0
            property real centerY: 0
            property real time: 0

            width: root.width
            height: root.height
            z: 5

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: {
                    wave.time += 0.1
                    wave.requestPaint()
                }
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                for (var r = 20; r < 300; r += 20) {
                    ctx.beginPath()
                    ctx.strokeStyle = Qt.hsla((r / 300), 0.7, 0.5, 0.6)
                    ctx.lineWidth = 3

                    for (var a = 0; a < Math.PI * 2; a += 0.1) {
                        var wobble = Math.sin(a * 8 + time) * 10
                        var x = centerX + Math.cos(a) * (r + wobble)
                        var y = centerY + Math.sin(a) * (r + wobble)
                        if (a === 0) ctx.moveTo(x, y)
                        else ctx.lineTo(x, y)
                    }
                    ctx.closePath()
                    ctx.stroke()
                }
            }

            Timer { interval: 2500; running: true; onTriggered: wave.destroy() }

            NumberAnimation on opacity { from: 1; to: 0; duration: 2500 }
        }
    }

    // Heart component
    Component {
        id: heartComponent
        Text {
            id: heart
            property real size: 30

            text: "❤"
            font.pixelSize: size
            z: 5

            NumberAnimation on y {
                from: y
                to: y - 300
                duration: 2000
                easing.type: Easing.OutQuad
            }

            SequentialAnimation on scale {
                NumberAnimation { from: 0; to: 1.2; duration: 200; easing.type: Easing.OutBack }
                NumberAnimation { to: 1; duration: 100 }
            }

            NumberAnimation on opacity { from: 1; to: 0; duration: 2000 }

            Timer { interval: 2000; running: true; onTriggered: heart.destroy() }
        }
    }

    // Twinkle component
    Component {
        id: twinkleComponent
        Rectangle {
            id: twinkle
            property real size: 15

            width: size
            height: size
            radius: size / 2
            color: "#ffffff"
            z: 5

            SequentialAnimation on scale {
                loops: 3
                NumberAnimation { from: 0; to: 1; duration: 300; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0.3; duration: 200 }
                NumberAnimation { to: 1.2; duration: 300; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0; duration: 400 }
            }

            Timer { interval: 2400; running: true; onTriggered: twinkle.destroy() }
        }
    }

    // Lava component
    Component {
        id: lavaComponent
        Rectangle {
            id: lava
            property real size: 80

            width: size
            height: size
            radius: size / 2
            z: 5

            NumberAnimation on y {
                from: y
                to: y - 400
                duration: 3000
                easing.type: Easing.InOutSine
            }

            SequentialAnimation on scale {
                NumberAnimation { from: 0.5; to: 1.3; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.8; duration: 1500; easing.type: Easing.InOutSine }
            }

            NumberAnimation on opacity { from: 0.8; to: 0; duration: 3000 }

            Timer { interval: 3000; running: true; onTriggered: lava.destroy() }
        }
    }

    // Matrix component
    Component {
        id: matrixComponent
        Text {
            id: matrix
            property real startY: 0

            text: {
                var chars = "ｱｲｳｴｵｶｷｸｹｺ0123456789"
                var result = ""
                for (var i = 0; i < 15; i++) {
                    result += chars[Math.floor(Math.random() * chars.length)] + "\n"
                }
                return result
            }
            font.pixelSize: 16
            font.family: "monospace"
            color: "#00ff00"
            y: startY
            z: 5

            NumberAnimation on y {
                from: startY
                to: root.height
                duration: 2000
                easing.type: Easing.Linear
            }

            NumberAnimation on opacity { from: 1; to: 0; duration: 2000 }

            Timer { interval: 2000; running: true; onTriggered: matrix.destroy() }
        }
    }

    // Disco component
    Component {
        id: discoComponent
        Rectangle {
            id: disco
            property real centerX: 0
            property real centerY: 0
            property real angle: 0
            property real distance: 0

            width: 20
            height: 300
            color: Qt.hsla(Math.random(), 0.8, 0.6, 0.7)
            z: 5

            x: centerX + Math.cos(angle) * distance - 10
            y: centerY + Math.sin(angle) * distance

            rotation: angle * 180 / Math.PI + 90

            NumberAnimation on distance {
                from: 0
                to: 400
                duration: 1500
                easing.type: Easing.OutQuad
            }

            NumberAnimation on opacity { from: 0.8; to: 0; duration: 1500 }

            Timer { interval: 1500; running: true; onTriggered: disco.destroy() }
        }
    }

    // Aurora component
    Component {
        id: auroraComponent
        Canvas {
            id: aurora
            property real centerX: 0
            property real centerY: 0
            property real time: 0

            width: root.width
            height: root.height
            z: 5

            Timer {
                interval: 32
                running: true
                repeat: true
                onTriggered: {
                    aurora.time += 0.05
                    aurora.requestPaint()
                }
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var colors = ["#00ff88", "#00ffcc", "#88ff00", "#00ccff"]

                for (var i = 0; i < 5; i++) {
                    ctx.beginPath()
                    var grad = ctx.createLinearGradient(0, centerY - 200, 0, centerY + 200)
                    grad.addColorStop(0, "transparent")
                    grad.addColorStop(0.5, colors[i % colors.length])
                    grad.addColorStop(1, "transparent")
                    ctx.fillStyle = grad

                    ctx.moveTo(centerX - 300, centerY + 200)
                    for (var x = -300; x <= 300; x += 20) {
                        var wave = Math.sin(x * 0.02 + time + i) * 50
                        var wave2 = Math.sin(x * 0.01 + time * 0.5) * 30
                        ctx.lineTo(centerX + x, centerY + wave + wave2 - i * 30)
                    }
                    ctx.lineTo(centerX + 300, centerY + 200)
                    ctx.closePath()
                    ctx.globalAlpha = 0.3
                    ctx.fill()
                }
                ctx.globalAlpha = 1
            }

            Timer { interval: 3000; running: true; onTriggered: aurora.destroy() }

            NumberAnimation on opacity { from: 1; to: 0; duration: 3000 }
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
        z: 99
    }
}
