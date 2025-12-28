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

    // Effect types
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
        "rain"
    ]

    // Random effect selection
    function getRandomEffect() {
        return Math.floor(Math.random() * effectTypes.length)
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

            // Trigger haptic feedback
            Haptic.tap()

            // Cycle to random effect (but not the same as current)
            var newEffect = currentEffect
            while (newEffect === currentEffect) {
                newEffect = getRandomEffect()
            }
            currentEffect = newEffect

            // Trigger the current effect
            triggerEffect(x, y)

            // Play position-based sound feedback
            playPositionalSound(x, y)
        }
    }

    // Generate position-based audio-visual feedback
    // X position = pitch/hue (left=low/red, right=high/blue)
    // Y position = volume/size (top=loud/big, bottom=soft/small)
    function playPositionalSound(x, y) {
        // Normalize positions to 0-1
        var normX = x / root.width
        var normY = y / root.height

        // Create pitch ring - size varies with Y (top=big, bottom=small)
        var ringSize = 100 + (1 - normY) * 300  // 100-400 based on Y

        // Color based on X position (rainbow left to right)
        var hue = normX  // 0-1 for hue

        // Create multiple expanding rings for richer feedback
        for (var i = 0; i < 3; i++) {
            var ring = soundRingComponent.createObject(root, {
                centerX: x,
                centerY: y,
                baseSize: ringSize * (1 - i * 0.2),
                hue: hue,
                delay: i * 80,
                speed: 300 + normY * 400  // faster at bottom
            })
        }

        // Create pitch indicator particles
        var numParticles = Math.floor(5 + (1 - normY) * 10)  // more particles = louder
        for (var j = 0; j < numParticles; j++) {
            var particle = pitchParticleComponent.createObject(root, {
                startX: x,
                startY: y,
                hue: hue + (Math.random() - 0.5) * 0.1,
                size: 4 + (1 - normY) * 8
            })
        }
    }

    // Sound ring component - expands outward like a sound wave
    Component {
        id: soundRingComponent
        Rectangle {
            id: soundRing
            property real centerX: 0
            property real centerY: 0
            property real baseSize: 200
            property real hue: 0.5
            property int delay: 0
            property int speed: 500

            x: centerX - width/2
            y: centerY - height/2
            width: baseSize
            height: baseSize
            radius: width/2
            color: "transparent"
            border.width: 4 + (1 - hue) * 4  // thicker on left
            border.color: Qt.hsla(hue, 0.8, 0.6, 0.8)
            scale: 0.3
            opacity: 0
            z: 30

            Timer {
                interval: delay
                running: true
                onTriggered: {
                    expandAnim.start()
                    fadeAnim.start()
                }
            }

            NumberAnimation {
                id: expandAnim
                target: soundRing
                property: "scale"
                from: 0.3
                to: 2.5
                duration: speed
                easing.type: Easing.OutQuad
            }

            SequentialAnimation {
                id: fadeAnim
                NumberAnimation {
                    target: soundRing
                    property: "opacity"
                    from: 0
                    to: 0.9
                    duration: 100
                }
                NumberAnimation {
                    target: soundRing
                    property: "opacity"
                    to: 0
                    duration: speed - 100
                }
            }

            Timer {
                interval: speed + delay + 50
                running: true
                onTriggered: soundRing.destroy()
            }
        }
    }

    // Pitch particle component - represents sound "notes"
    Component {
        id: pitchParticleComponent
        Rectangle {
            id: pitchParticle
            property real startX: 0
            property real startY: 0
            property real hue: 0.5
            property real size: 8

            x: startX - size/2
            y: startY - size/2
            width: size
            height: size
            radius: size/2
            color: Qt.hsla(hue, 0.9, 0.7, 1)
            z: 35
            scale: 0

            property real angle: Math.random() * Math.PI * 2
            property real speed: 50 + Math.random() * 100
            property real vx: Math.cos(angle) * speed
            property real vy: Math.sin(angle) * speed - 50  // slight upward bias

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: {
                    pitchParticle.x += pitchParticle.vx * 0.016
                    pitchParticle.y += pitchParticle.vy * 0.016
                    pitchParticle.vy += 100 * 0.016  // gentle gravity
                }
            }

            SequentialAnimation on scale {
                NumberAnimation { to: 1.5; duration: 150; easing.type: Easing.OutBack }
                NumberAnimation { to: 0; duration: 350; easing.type: Easing.InQuad }
            }

            Timer {
                interval: 500
                running: true
                onTriggered: pitchParticle.destroy()
            }
        }
    }

    // Keep original visual indicator as backup
    Rectangle {
        id: soundIndicator
        anchors.centerIn: parent
        width: 300
        height: 300
        radius: 150
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.1)
        border.width: 4
        opacity: 0
        scale: 0.5
        z: 50

        property var animTimer: Timer {
            id: soundAnim
            interval: 300
            onTriggered: soundIndicator.opacity = 0
        }

        function restart() {
            soundAnim.restart()
        }

        Behavior on opacity {
            NumberAnimation { duration: 300 }
        }

        Behavior on scale {
            NumberAnimation { duration: 300 }
        }

        onOpacityChanged: {
            if (opacity > 0) scale = 1.2
            else scale = 0.5
        }
    }

    // Container for all particle effects
    Item {
        anchors.fill: parent

        // Effect trigger function
        function triggerEffect(x, y) {
            var effect = effectTypes[currentEffect]

            switch(effect) {
                case "fireworks":
                    createFireworks(x, y)
                    break
                case "bubbles":
                    createBubbles(x, y)
                    break
                case "rainbow":
                    createRainbow(x, y)
                    break
                case "sparkles":
                    createSparkles(x, y)
                    break
                case "paint":
                    createPaint(x, y)
                    break
                case "balls":
                    createBalls(x, y)
                    break
                case "confetti":
                    createConfetti(x, y)
                    break
                case "kaleidoscope":
                    createKaleidoscope(x, y)
                    break
                case "lightning":
                    createLightning(x, y)
                    break
                case "flowers":
                    createFlowers(x, y)
                    break
                case "snow":
                    createSnow(x, y)
                    break
                case "neon":
                    createNeon(x, y)
                    break
                case "shapes":
                    createShapes(x, y)
                    break
                case "galaxy":
                    createGalaxy(x, y)
                    break
                case "rain":
                    createRain(x, y)
                    break
            }
        }
    }

    function triggerEffect(x, y) {
        var effect = effectTypes[currentEffect]

        switch(effect) {
            case "fireworks":
                createFireworks(x, y)
                break
            case "bubbles":
                createBubbles(x, y)
                break
            case "rainbow":
                createRainbow(x, y)
                break
            case "sparkles":
                createSparkles(x, y)
                break
            case "paint":
                createPaint(x, y)
                break
            case "balls":
                createBalls(x, y)
                break
            case "confetti":
                createConfetti(x, y)
                break
            case "kaleidoscope":
                createKaleidoscope(x, y)
                break
            case "lightning":
                createLightning(x, y)
                break
            case "flowers":
                createFlowers(x, y)
                break
            case "snow":
                createSnow(x, y)
                break
            case "neon":
                createNeon(x, y)
                break
            case "shapes":
                createShapes(x, y)
                break
            case "galaxy":
                createGalaxy(x, y)
                break
            case "rain":
                createRain(x, y)
                break
        }
    }

    // Fireworks effect
    function createFireworks(x, y) {
        var colors = ["#ff3355", "#ffaa33", "#33ff77", "#3388ff", "#ff33ff", "#ffff33"]
        for (var i = 0; i < 30; i++) {
            var angle = (Math.PI * 2 * i) / 30
            var speed = 200 + Math.random() * 200
            var particle = particleComponent.createObject(root, {
                x: x,
                y: y,
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
                x: x,
                y: y,
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
                x: x,
                y: y,
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
                x: x,
                y: y,
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
                x: x,
                y: y,
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
                x: x,
                y: y,
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

    // Snow/particles falling effect
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
                x: x,
                y: y,
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
                centerX: x,
                centerY: y,
                angle: angle,
                distance: distance,
                color: i % 3 === 0 ? "#ffffff" : (i % 3 === 1 ? "#aaccff" : "#ffaacc"),
                lifetime: 2500
            })
        }
    }

    // Rain with splashes effect
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

    // Particle component (for fireworks, sparkles, etc)
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

            NumberAnimation on scale {
                to: 1.0
                duration: 300
                easing.type: Easing.OutBack
            }

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
                onTriggered: {
                    scaleAnim.start()
                    fadeAnim.start()
                }
            }

            NumberAnimation {
                id: scaleAnim
                target: ripple
                property: "scale"
                from: 1
                to: 30
                duration: lifetime
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                id: fadeAnim
                target: ripple
                property: "opacity"
                from: 0.8
                to: 0
                duration: lifetime
            }

            Timer {
                interval: lifetime + delay
                running: true
                onTriggered: ripple.destroy()
            }
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

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.5 }
                NumberAnimation { to: 0; duration: lifetime * 0.5 }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: sparkle.destroy()
            }
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

            NumberAnimation on scale {
                to: 1.0
                duration: 200
                easing.type: Easing.OutBack
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: splat.destroy()
            }
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

                    // Bounce on bottom
                    if (ball.y > root.height - ball.size) {
                        ball.y = root.height - ball.size
                        ball.vy *= -ball.bounce
                    }

                    // Bounce on sides
                    if (ball.x < 0) {
                        ball.x = 0
                        ball.vx *= -ball.bounce
                    }
                    if (ball.x > root.width - ball.size) {
                        ball.x = root.width - ball.size
                        ball.vx *= -ball.bounce
                    }
                }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: ball.destroy()
            }

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

            transform: Rotation {
                id: rot
                angle: 0
                origin.x: 6
                origin.y: 10
            }

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

            Timer {
                interval: lifetime
                running: true
                onTriggered: confetto.destroy()
            }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.8 }
                NumberAnimation { to: 0; duration: lifetime * 0.2 }
            }
        }
    }

    // Kaleidoscope component
    Component {
        id: kaleidoComponent
        Rectangle {
            id: kaleido
            property real angle: 0
            property int lifetime: 1500
            property real distance: 0

            width: 60
            height: 60
            radius: 30
            z: 5

            x: x + Math.cos(angle) * distance - 30
            y: y + Math.sin(angle) * distance - 30

            NumberAnimation on distance {
                from: 0
                to: 200
                duration: lifetime
                easing.type: Easing.OutQuad
            }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.6 }
                NumberAnimation { to: 0; duration: lifetime * 0.4 }
            }

            NumberAnimation on rotation {
                from: 0
                to: 360
                duration: lifetime
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: kaleido.destroy()
            }
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
            opacity: 1.0

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
                    currentX = nextX
                    currentY = nextY
                }

                ctx.stroke()
            }

            Component.onCompleted: {
                requestPaint()
            }

            SequentialAnimation on opacity {
                NumberAnimation { to: 0; duration: 100 }
                NumberAnimation { to: 1; duration: 50 }
                NumberAnimation { to: 0; duration: 100 }
                NumberAnimation { to: 0.7; duration: 50 }
                NumberAnimation { to: 0; duration: 100 }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: lightning.destroy()
            }
        }
    }

    // Petal component
    Component {
        id: petalComponent
        Rectangle {
            id: petal
            property real angle: 0
            property int lifetime: 1500
            property real distance: 0

            width: 40
            height: 60
            radius: 20
            z: 5
            scale: 0

            x: x + Math.cos(angle) * distance - 20
            y: y + Math.sin(angle) * distance - 30

            SequentialAnimation on scale {
                NumberAnimation { to: 1.0; duration: lifetime * 0.3; easing.type: Easing.OutBack }
                PauseAnimation { duration: lifetime * 0.4 }
                NumberAnimation { to: 0; duration: lifetime * 0.3 }
            }

            NumberAnimation on distance {
                from: 0
                to: 80
                duration: lifetime * 0.3
                easing.type: Easing.OutQuad
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: petal.destroy()
            }
        }
    }

    // Snow component
    Component {
        id: snowComponent
        Rectangle {
            id: snow
            property int lifetime: 3000
            property real size: 12
            property real vx: (Math.random() - 0.5) * 50
            property real vy: 100 + Math.random() * 100

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
                    snow.x += snow.vx * 0.016
                    snow.y += snow.vy * 0.016
                    snow.vx += Math.sin(snow.y * 0.02) * 20 * 0.016
                }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: snow.destroy()
            }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.7 }
                NumberAnimation { to: 0; duration: lifetime * 0.3 }
            }
        }
    }

    // Neon trail component
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

            NumberAnimation on x {
                to: targetX
                duration: lifetime
                easing.type: Easing.OutQuad
            }

            NumberAnimation on y {
                to: targetY
                duration: lifetime
                easing.type: Easing.OutQuad
            }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.5 }
                NumberAnimation { to: 0; duration: lifetime * 0.5 }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: neon.destroy()
            }
        }
    }

    // Morphing shape component
    Component {
        id: shapeComponent
        Rectangle {
            id: shape
            property int lifetime: 2000
            property int corners: 3

            width: 120
            height: 120
            color: Qt.rgba(Math.random(), Math.random(), Math.random(), 0.8)
            z: 5
            scale: 0

            SequentialAnimation on scale {
                NumberAnimation { to: 1.5; duration: lifetime * 0.5; easing.type: Easing.OutBack }
                NumberAnimation { to: 0; duration: lifetime * 0.5; easing.type: Easing.InBack }
            }

            SequentialAnimation on rotation {
                NumberAnimation { to: 180; duration: lifetime * 0.5 }
                NumberAnimation { to: 360; duration: lifetime * 0.5 }
            }

            SequentialAnimation on radius {
                NumberAnimation { to: 60; duration: lifetime * 0.33 }
                NumberAnimation { to: 0; duration: lifetime * 0.33 }
                NumberAnimation { to: 30; duration: lifetime * 0.34 }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: shape.destroy()
            }
        }
    }

    // Star component (for galaxy)
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
                onTriggered: {
                    star.currentAngle += 0.05
                }
            }

            NumberAnimation on distance {
                from: distance
                to: 10
                duration: lifetime
                easing.type: Easing.InQuad
            }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.7 }
                NumberAnimation { to: 0; duration: lifetime * 0.3 }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: star.destroy()
            }
        }
    }

    // Rain drop component
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

            NumberAnimation on y {
                to: targetY
                duration: lifetime * 0.7
                easing.type: Easing.InQuad
            }

            SequentialAnimation on opacity {
                PauseAnimation { duration: lifetime * 0.7 }
                NumberAnimation { to: 0; duration: lifetime * 0.3 }
            }

            // Splash on impact
            Timer {
                interval: lifetime * 0.7
                running: true
                onTriggered: {
                    for (var i = 0; i < 5; i++) {
                        var splash = Qt.createQmlObject(
                            'import QtQuick 2.15; Rectangle { color: "#6688ff"; width: 3; height: 3; radius: 1.5; z: 5; NumberAnimation on y { from: 0; to: 20; duration: 300 } NumberAnimation on opacity { from: 1; to: 0; duration: 300 } Timer { interval: 300; running: true; onTriggered: parent.destroy() } }',
                            root
                        )
                        splash.x = drop.x + (Math.random() - 0.5) * 30
                        splash.y = drop.y
                    }
                }
            }

            Timer {
                interval: lifetime
                running: true
                onTriggered: drop.destroy()
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
        z: 99
    }
}
