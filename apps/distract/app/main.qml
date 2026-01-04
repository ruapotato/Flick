import QtQuick 2.15
import QtQuick.Window 2.15
import QtMultimedia 5.15
import "./shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Distract"
    color: "#0a0a0f"

    property int currentEffect: 0
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property int exitTapCount: 0
    property var exitTimer: null
    property real globalTime: 0

    // Effect types - 25 effects
    readonly property var effectTypes: [
        "fireworks", "bubbles", "rainbow", "sparkles", "paint",
        "balls", "confetti", "kaleidoscope", "lightning", "flowers",
        "snow", "neon", "shapes", "galaxy", "rain",
        "life", "tree", "spiral", "waves", "hearts",
        "stars", "lava", "matrix", "disco", "aurora"
    ]

    // Swipe effect types
    readonly property var swipeEffectTypes: [
        "trail", "ribbon", "fire", "ice", "electric", "rainbow", "smoke", "sparkle"
    ]
    property int currentSwipeEffect: 0

    // Global time for animations (reduced frequency for lower CPU usage)
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: globalTime += 0.1
    }

    function getRandomEffect() {
        return Math.floor(Math.random() * effectTypes.length)
    }

    function getRandomSwipeEffect() {
        return Math.floor(Math.random() * swipeEffectTypes.length)
    }

    // ==================== SOUND GENERATION ====================

    // Audio player pool for polyphonic sound playback
    property var audioPool: []
    property int audioPoolSize: 10
    property int currentAudioIndex: 0

    // Available frequencies and waveforms
    property var frequencies: [200, 250, 300, 350, 400, 450, 500, 550, 600, 650, 700, 750, 800]
    property var waveformNames: ["sine", "square", "triangle", "sawtooth"]

    // Initialize audio pool
    Component.onCompleted: {
        for (var i = 0; i < audioPoolSize; i++) {
            var audio = Qt.createQmlObject('
                import QtQuick 2.15
                import QtMultimedia 5.15
                Audio {
                    autoPlay: false
                    volume: 0.5
                }
            ', root)
            audioPool.push(audio)
        }
    }

    // Generate and play a tone
    // Frequency based on X position, volume/timbre based on Y position
    function playSound(x, y, isTap) {
        // Normalize position
        var normX = x / root.width   // 0-1, affects pitch
        var normY = y / root.height  // 0-1, affects volume/character

        // Map X to frequency index (0-12 for 13 frequencies)
        var freqIndex = Math.floor(normX * (frequencies.length - 1))
        var freq = frequencies[freqIndex]

        // Map Y to volume (louder at top)
        var volume = 0.3 + (1 - normY) * 0.5  // 0.3-0.8

        // Map Y to waveform type (different timbre vertically)
        var waveType = Math.floor(normY * 3.99)  // 0-3 based on Y position
        waveType = Math.min(3, Math.max(0, waveType))

        // Play the beep
        playBeep(freq, waveType, volume)

        // Haptic feedback
        Haptic.tap()

        // Create visual feedback (single wave for reduced resource usage)
        var wave = soundWaveComponent.createObject(root, {
            centerX: x,
            centerY: y,
            hue: normX,
            delay: 0,
            waveSize: 50 + volume * 100
        })
    }

    // Play a beep from pre-generated sound files
    function playBeep(freq, waveType, volume) {
        // Get next available audio player from pool
        var audio = audioPool[currentAudioIndex]
        currentAudioIndex = (currentAudioIndex + 1) % audioPoolSize

        // Set audio source and volume
        var soundFile = "sounds/beep_" + freq + "_" + waveType + ".wav"
        audio.source = soundFile
        audio.volume = volume

        // Play the sound
        audio.play()
    }

    // Sound wave visual component
    Component {
        id: soundWaveComponent
        Rectangle {
            id: soundWave
            property real centerX: 540
            property real centerY: 1200
            property real hue: 0.5
            property int delay: 0
            property real waveSize: 100

            x: centerX - width/2
            y: centerY - height/2
            width: 20
            height: 20
            radius: width/2
            color: "transparent"
            border.width: 4
            border.color: Qt.hsla(hue, 0.9, 0.6, 0.8)
            scale: 0.1
            opacity: 0
            z: 50

            SequentialAnimation {
                running: true
                PauseAnimation { duration: delay }
                ParallelAnimation {
                    NumberAnimation { target: soundWave; property: "scale"; to: waveSize / 20; duration: 400; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        NumberAnimation { target: soundWave; property: "opacity"; to: 0.9; duration: 50 }
                        NumberAnimation { target: soundWave; property: "opacity"; to: 0; duration: 350 }
                    }
                }
                ScriptAction { script: soundWave.destroy() }
            }
        }
    }

    // ==================== EXIT AREA ====================

    MouseArea {
        id: exitArea
        x: 0; y: 0; width: 150; height: 150
        z: 100
        onClicked: {
            if (exitTimer) exitTimer.stop()
            exitTapCount++
            if (exitTapCount >= 3) Qt.quit()
            exitTimer = Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 1000; running: true; onTriggered: exitTapCount = 0 }', root)
        }
    }

    // ==================== MAIN TOUCH AREA (MULTI-TOUCH) ====================

    // Track per-touch state for multi-touch support
    property var touchStates: ({})

    function handleTouchStart(touchPoint) {
        var x = touchPoint.x
        var y = touchPoint.y
        var pointId = touchPoint.pointId

        // Initialize touch state for this point
        touchStates[pointId] = {
            isSwiping: false,
            swipeStartX: x,
            swipeStartY: y,
            lastSwipeX: x,
            lastSwipeY: y,
            swipeEffect: getRandomSwipeEffect()
        }

        // Play sound
        playSound(x, y, true)

        // Change to random effect
        var newEffect = currentEffect
        while (newEffect === currentEffect && effectTypes.length > 1) {
            newEffect = getRandomEffect()
        }
        currentEffect = newEffect

        // Trigger tap effect
        triggerEffect(x, y)
    }

    function handleTouchUpdate(touchPoint) {
        var x = touchPoint.x
        var y = touchPoint.y
        var pointId = touchPoint.pointId

        var state = touchStates[pointId]
        if (!state) return

        var dx = x - state.lastSwipeX
        var dy = y - state.lastSwipeY
        var dist = Math.sqrt(dx*dx + dy*dy)

        // Only trigger swipe effects if moved enough
        if (dist > 15) {
            if (!state.isSwiping) {
                state.isSwiping = true
                // Change swipe effect type for this touch
                state.swipeEffect = getRandomSwipeEffect()
            }

            // Temporarily set current swipe effect for this touch
            var prevSwipeEffect = currentSwipeEffect
            currentSwipeEffect = state.swipeEffect

            // Play swipe sound (position-based, reduced frequency for performance)
            if (Math.random() < 0.3) {
                playSound(x, y, false)
            }

            // Create swipe trail effect
            createSwipeEffect(state.lastSwipeX, state.lastSwipeY, x, y, dx, dy)

            // Restore previous swipe effect
            currentSwipeEffect = prevSwipeEffect

            state.lastSwipeX = x
            state.lastSwipeY = y
        }
    }

    function handleTouchEnd(touchPoint) {
        var x = touchPoint.x
        var y = touchPoint.y
        var pointId = touchPoint.pointId

        var state = touchStates[pointId]
        if (!state) return

        if (state.isSwiping) {
            // Calculate swipe velocity
            var dx = x - state.swipeStartX
            var dy = y - state.swipeStartY
            var speed = Math.sqrt(dx*dx + dy*dy)

            // Temporarily set current swipe effect for this touch
            var prevSwipeEffect = currentSwipeEffect
            currentSwipeEffect = state.swipeEffect

            // Big swipe finale effect
            if (speed > 200) {
                createSwipeFinale(x, y, dx, dy, speed)
                // Play a fun high-pitched finale sound
                playSound(x, y, true)
            }

            // Restore previous swipe effect
            currentSwipeEffect = prevSwipeEffect
        }

        // Clean up touch state
        delete touchStates[pointId]
    }

    MultiPointTouchArea {
        anchors.fill: parent
        z: 1
        minimumTouchPoints: 1
        maximumTouchPoints: 10

        touchPoints: [
            TouchPoint { id: touch1 },
            TouchPoint { id: touch2 },
            TouchPoint { id: touch3 },
            TouchPoint { id: touch4 },
            TouchPoint { id: touch5 },
            TouchPoint { id: touch6 },
            TouchPoint { id: touch7 },
            TouchPoint { id: touch8 },
            TouchPoint { id: touch9 },
            TouchPoint { id: touch10 }
        ]

        onPressed: function(touchPoints) {
            for (var i = 0; i < touchPoints.length; i++) {
                handleTouchStart(touchPoints[i])
            }
        }

        onUpdated: function(touchPoints) {
            for (var i = 0; i < touchPoints.length; i++) {
                handleTouchUpdate(touchPoints[i])
            }
        }

        onReleased: function(touchPoints) {
            for (var i = 0; i < touchPoints.length; i++) {
                handleTouchEnd(touchPoints[i])
            }
        }
    }

    // ==================== SWIPE EFFECTS ====================

    function createSwipeEffect(x1, y1, x2, y2, dx, dy) {
        var effect = swipeEffectTypes[currentSwipeEffect]
        var speed = Math.sqrt(dx*dx + dy*dy)
        var angle = Math.atan2(dy, dx)

        switch(effect) {
            case "trail": createTrail(x2, y2, angle, speed); break
            case "ribbon": createRibbon(x1, y1, x2, y2); break
            case "fire": createFireTrail(x2, y2, angle, speed); break
            case "ice": createIceTrail(x2, y2, angle, speed); break
            case "electric": createElectricTrail(x1, y1, x2, y2); break
            case "rainbow": createRainbowTrail(x2, y2, angle); break
            case "smoke": createSmokeTrail(x2, y2); break
            case "sparkle": createSparkleTrail(x2, y2, speed); break
        }
    }

    function createSwipeFinale(x, y, dx, dy, speed) {
        var effect = swipeEffectTypes[currentSwipeEffect]
        var angle = Math.atan2(dy, dx)
        var numParticles = Math.min(20, Math.floor(speed / 20))

        // Burst of particles in swipe direction
        for (var i = 0; i < numParticles; i++) {
            var spreadAngle = angle + (Math.random() - 0.5) * 0.8
            var particleSpeed = speed * (0.5 + Math.random() * 0.5)

            var particle = finaleParticleComponent.createObject(root, {
                x: x,
                y: y,
                vx: Math.cos(spreadAngle) * particleSpeed,
                vy: Math.sin(spreadAngle) * particleSpeed,
                hue: (currentSwipeEffect / swipeEffectTypes.length) + Math.random() * 0.2,
                size: 8 + Math.random() * 16
            })
        }

        // Big haptic
        Haptic.tap()
    }

    // Trail effect
    function createTrail(x, y, angle, speed) {
        var colors = ["#ff3366", "#33ff99", "#3399ff", "#ffcc33", "#ff33cc"]
        var trail = Qt.createQmlObject('
            import QtQuick 2.15
            Rectangle {
                property real fadeTime: ' + (300 + speed * 5) + '
                width: ' + (10 + speed * 0.5) + '
                height: width
                radius: width/2
                color: "' + colors[Math.floor(Math.random() * colors.length)] + '"
                x: ' + (x - width/2) + '
                y: ' + (y - height/2) + '
                z: 10
                opacity: 0.8
                NumberAnimation on opacity { to: 0; duration: fadeTime }
                NumberAnimation on scale { to: 0.3; duration: fadeTime }
                Timer { interval: fadeTime; running: true; onTriggered: parent.destroy() }
            }
        ', root)
    }

    // Ribbon effect
    function createRibbon(x1, y1, x2, y2) {
        var ribbon = Qt.createQmlObject('
            import QtQuick 2.15
            Canvas {
                width: ' + root.width + '
                height: ' + root.height + '
                z: 10
                opacity: 0.7
                onPaint: {
                    var ctx = getContext("2d")
                    var grad = ctx.createLinearGradient(' + x1 + ',' + y1 + ',' + x2 + ',' + y2 + ')
                    grad.addColorStop(0, Qt.hsla(' + (globalTime % 1) + ', 0.8, 0.5, 0.8))
                    grad.addColorStop(1, Qt.hsla(' + ((globalTime + 0.3) % 1) + ', 0.8, 0.5, 0.8))
                    ctx.strokeStyle = grad
                    ctx.lineWidth = 8
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.moveTo(' + x1 + ', ' + y1 + ')
                    ctx.lineTo(' + x2 + ', ' + y2 + ')
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
                NumberAnimation on opacity { to: 0; duration: 500 }
                Timer { interval: 500; running: true; onTriggered: parent.destroy() }
            }
        ', root)
    }

    // Fire trail
    function createFireTrail(x, y, angle, speed) {
        for (var i = 0; i < 3; i++) {
            var fire = Qt.createQmlObject('
                import QtQuick 2.15
                Rectangle {
                    width: ' + (15 + Math.random() * 15) + '
                    height: width
                    radius: width/2
                    x: ' + (x - 10 + Math.random() * 20) + '
                    y: ' + (y - 10 + Math.random() * 20) + '
                    color: Qt.hsla(' + (0.05 + Math.random() * 0.08) + ', 1, 0.5, 0.9)
                    z: 10
                    NumberAnimation on y { to: ' + (y - 50 - Math.random() * 50) + '; duration: 400 }
                    NumberAnimation on opacity { from: 0.9; to: 0; duration: 400 }
                    NumberAnimation on scale { from: 1; to: 0.3; duration: 400 }
                    Timer { interval: 400; running: true; onTriggered: parent.destroy() }
                }
            ', root)
        }
    }

    // Ice trail
    function createIceTrail(x, y, angle, speed) {
        var ice = Qt.createQmlObject('
            import QtQuick 2.15
            Rectangle {
                width: ' + (12 + speed * 0.3) + '
                height: width
                radius: 2
                rotation: ' + (Math.random() * 360) + '
                x: ' + x + '
                y: ' + y + '
                color: Qt.hsla(0.55, 0.6, ' + (0.7 + Math.random() * 0.3) + ', 0.8)
                z: 10
                NumberAnimation on opacity { to: 0; duration: 600 }
                NumberAnimation on rotation { to: ' + (Math.random() * 360) + '; duration: 600 }
                Timer { interval: 600; running: true; onTriggered: parent.destroy() }
            }
        ', root)
    }

    // Electric trail
    function createElectricTrail(x1, y1, x2, y2) {
        var bolt = Qt.createQmlObject('
            import QtQuick 2.15
            Canvas {
                width: ' + root.width + '
                height: ' + root.height + '
                z: 15
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.strokeStyle = "#88ccff"
                    ctx.lineWidth = 2
                    ctx.shadowColor = "#00aaff"
                    ctx.shadowBlur = 10
                    ctx.beginPath()
                    var x = ' + x1 + ', y = ' + y1 + '
                    ctx.moveTo(x, y)
                    var dx = ' + (x2 - x1) + ', dy = ' + (y2 - y1) + '
                    var segments = 5
                    for (var i = 0; i < segments; i++) {
                        x += dx/segments + (Math.random() - 0.5) * 20
                        y += dy/segments + (Math.random() - 0.5) * 20
                        ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
                SequentialAnimation on opacity {
                    NumberAnimation { to: 0; duration: 50 }
                    NumberAnimation { to: 1; duration: 30 }
                    NumberAnimation { to: 0; duration: 100 }
                }
                Timer { interval: 180; running: true; onTriggered: parent.destroy() }
            }
        ', root)
    }

    // Rainbow trail
    function createRainbowTrail(x, y, angle) {
        var colors = ["#ff0000", "#ff7700", "#ffff00", "#00ff00", "#0077ff", "#7700ff"]
        for (var i = 0; i < colors.length; i++) {
            var offset = (i - colors.length/2) * 4
            var rainbow = Qt.createQmlObject('
                import QtQuick 2.15
                Rectangle {
                    width: 12; height: 12; radius: 6
                    x: ' + (x + Math.cos(angle + Math.PI/2) * offset) + '
                    y: ' + (y + Math.sin(angle + Math.PI/2) * offset) + '
                    color: "' + colors[i] + '"
                    z: 10
                    NumberAnimation on opacity { from: 0.8; to: 0; duration: 400 }
                    Timer { interval: 400; running: true; onTriggered: parent.destroy() }
                }
            ', root)
        }
    }

    // Smoke trail
    function createSmokeTrail(x, y) {
        var smoke = Qt.createQmlObject('
            import QtQuick 2.15
            Rectangle {
                width: ' + (30 + Math.random() * 30) + '
                height: width
                radius: width/2
                x: ' + (x - 30) + '
                y: ' + (y - 30) + '
                color: Qt.rgba(0.5, 0.5, 0.5, 0.4)
                z: 8
                NumberAnimation on y { to: ' + (y - 100 - Math.random() * 100) + '; duration: 1500 }
                NumberAnimation on scale { to: 2; duration: 1500 }
                NumberAnimation on opacity { to: 0; duration: 1500 }
                Timer { interval: 1500; running: true; onTriggered: parent.destroy() }
            }
        ', root)
    }

    // Sparkle trail
    function createSparkleTrail(x, y, speed) {
        for (var i = 0; i < 2 + speed/20; i++) {
            var sparkle = Qt.createQmlObject('
                import QtQuick 2.15
                Rectangle {
                    width: ' + (4 + Math.random() * 8) + '
                    height: width
                    radius: width/2
                    x: ' + (x - 10 + Math.random() * 20) + '
                    y: ' + (y - 10 + Math.random() * 20) + '
                    color: "#ffffff"
                    z: 12
                    SequentialAnimation on scale {
                        NumberAnimation { from: 0; to: 1.5; duration: 150 }
                        NumberAnimation { to: 0; duration: 200 }
                    }
                    Timer { interval: 350; running: true; onTriggered: parent.destroy() }
                }
            ', root)
        }
    }

    // Finale particle component
    Component {
        id: finaleParticleComponent
        Rectangle {
            id: fp
            property real vx: 0
            property real vy: 0
            property real hue: 0.5
            property real size: 12
            property real gravity: 300

            width: size
            height: size
            radius: size/2
            color: Qt.hsla(hue, 0.9, 0.6, 1)
            z: 20

            Timer {
                interval: 33
                running: true
                repeat: true
                onTriggered: {
                    fp.x += fp.vx * 0.033
                    fp.y += fp.vy * 0.033
                    fp.vy += fp.gravity * 0.033
                    fp.vx *= 0.96
                }
            }

            NumberAnimation on opacity { from: 1; to: 0; duration: 1500 }
            Timer { interval: 1500; running: true; onTriggered: fp.destroy() }
        }
    }

    // ==================== TAP EFFECTS ====================

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

    // ==================== TAP EFFECT IMPLEMENTATIONS ====================

    function createFireworks(x, y) {
        var colors = ["#ff3355", "#ffaa33", "#33ff77", "#3388ff", "#ff33ff", "#ffff33"]
        for (var i = 0; i < 12; i++) {
            var angle = (Math.PI * 2 * i) / 12
            var speed = 150 + Math.random() * 150
            particleComponent.createObject(root, {
                x: x, y: y,
                vx: Math.cos(angle) * speed,
                vy: Math.sin(angle) * speed,
                particleColor: colors[Math.floor(Math.random() * colors.length)],
                size: 6 + Math.random() * 6
            })
        }
    }

    function createBubbles(x, y) {
        for (var i = 0; i < 6; i++) {
            bubbleComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 150,
                y: y + (Math.random() - 0.5) * 150,
                size: 30 + Math.random() * 60
            })
        }
    }

    function createRainbow(x, y) {
        var colors = ["#ff0000", "#ff7700", "#ffff00", "#00ff00", "#0088ff", "#4400ff", "#8800ff"]
        for (var i = 0; i < 7; i++) {
            rippleComponent.createObject(root, {
                centerX: x, centerY: y,
                rippleColor: colors[i],
                delay: i * 80
            })
        }
    }

    function createSparkles(x, y) {
        for (var i = 0; i < 15; i++) {
            var angle = Math.random() * Math.PI * 2
            var dist = Math.random() * 250
            sparkleComponent.createObject(root, {
                x: x + Math.cos(angle) * dist,
                y: y + Math.sin(angle) * dist,
                size: 4 + Math.random() * 6
            })
        }
    }

    function createPaint(x, y) {
        var colors = ["#ff3355", "#33ff88", "#3388ff", "#ffaa33", "#ff33ff"]
        for (var i = 0; i < 8; i++) {
            var angle = Math.random() * Math.PI * 2
            var speed = 80 + Math.random() * 200
            splatComponent.createObject(root, {
                x: x, y: y,
                vx: Math.cos(angle) * speed,
                vy: Math.sin(angle) * speed,
                splatColor: colors[Math.floor(Math.random() * colors.length)],
                size: 15 + Math.random() * 30
            })
        }
    }

    function createBalls(x, y) {
        var colors = ["#ff3355", "#33ff88", "#3388ff", "#ffaa33"]
        for (var i = 0; i < 4; i++) {
            ballComponent.createObject(root, {
                x: x, y: y,
                vx: (Math.random() - 0.5) * 300,
                vy: -150 - Math.random() * 150,
                ballColor: colors[i],
                size: 35 + Math.random() * 35
            })
        }
    }

    function createConfetti(x, y) {
        var colors = ["#ff3355", "#33ff88", "#3388ff", "#ffaa33", "#ff33ff", "#ffff33"]
        for (var i = 0; i < 12; i++) {
            confettiComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 80,
                y: y - Math.random() * 80,
                vx: (Math.random() - 0.5) * 150,
                vy: -80 - Math.random() * 150,
                confettiColor: colors[Math.floor(Math.random() * colors.length)]
            })
        }
    }

    function createKaleidoscope(x, y) {
        var colors = ["#ff3355", "#33ff88", "#3388ff", "#ffaa33", "#ff33ff"]
        for (var i = 0; i < 10; i++) {
            var angle = (Math.PI * 2 * i) / 10
            kaleidoComponent.createObject(root, {
                centerX: x, centerY: y,
                angle: angle,
                kaleidoColor: colors[i % colors.length]
            })
        }
    }

    function createLightning(x, y) {
        lightningComponent.createObject(root, {
            startX: x,
            startY: 0,
            endX: x + (Math.random() - 0.5) * 150,
            endY: y
        })
    }

    function createFlowers(x, y) {
        var colors = ["#ff3388", "#ff88cc", "#ffaadd", "#ff5599"]
        for (var i = 0; i < 6; i++) {
            var angle = (Math.PI * 2 * i) / 6
            petalComponent.createObject(root, {
                centerX: x, centerY: y,
                angle: angle,
                petalColor: colors[Math.floor(Math.random() * colors.length)]
            })
        }
        var center = Qt.createQmlObject('import QtQuick 2.15; Rectangle { color: "#ffff44"; width: 24; height: 24; radius: 12; z: 11; x:' + (x-12) + '; y:' + (y-12) + '; Timer { interval: 1200; running: true; onTriggered: parent.destroy() } }', root)
    }

    function createSnow(x, y) {
        for (var i = 0; i < 10; i++) {
            snowComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 300,
                y: y - 150,
                size: 6 + Math.random() * 12
            })
        }
    }

    function createNeon(x, y) {
        var colors = ["#ff00ff", "#00ffff", "#ff0088", "#00ff88"]
        for (var i = 0; i < 8; i++) {
            var angle = Math.random() * Math.PI * 2
            var dist = Math.random() * 200
            neonComponent.createObject(root, {
                startX: x, startY: y,
                targetX: x + Math.cos(angle) * dist,
                targetY: y + Math.sin(angle) * dist,
                neonColor: colors[Math.floor(Math.random() * colors.length)]
            })
        }
    }

    function createShapes(x, y) { shapeComponent.createObject(root, { x: x - 50, y: y - 50 }) }
    function createGalaxy(x, y) {
        for (var i = 0; i < 15; i++) {
            galaxyStarComponent.createObject(root, {
                centerX: x, centerY: y,
                angle: Math.random() * Math.PI * 2,
                dist: Math.random() * 200,
                starColor: ["#ffffff", "#aaccff", "#ffaacc"][i % 3]
            })
        }
    }
    function createRain(x, y) {
        for (var i = 0; i < 10; i++) {
            rainComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 250,
                startY: y - 300 - Math.random() * 150,
                targetY: y
            })
        }
    }
    function createLife(x, y) { lifeComponent.createObject(root, { centerX: x, centerY: y }) }
    function createTree(x, y) { createBranch(x, y, -Math.PI/2, 80, 4, 0) }
    function createBranch(x, y, angle, length, thickness, depth) {
        if (depth > 5 || length < 12) return
        branchComponent.createObject(root, { startX: x, startY: y, angle: angle, length: length, thickness: thickness, depth: depth })
    }
    function createSpiral(x, y) { spiralComponent.createObject(root, { centerX: x, centerY: y }) }
    function createWaves(x, y) { waveComponent.createObject(root, { centerX: x, centerY: y }) }
    function createHearts(x, y) {
        var colors = ["#ff3366", "#ff6699", "#ff99cc"]
        for (var i = 0; i < 6; i++) {
            heartComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 150,
                y: y,
                size: 18 + Math.random() * 30,
                heartColor: colors[Math.floor(Math.random() * colors.length)]
            })
        }
    }
    function createStars(x, y) {
        for (var i = 0; i < 10; i++) {
            twinkleComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 300,
                y: y + (Math.random() - 0.5) * 300,
                size: 8 + Math.random() * 15
            })
        }
    }
    function createLava(x, y) {
        var colors = ["#ff3300", "#ff6600", "#ff9900", "#ffcc00"]
        for (var i = 0; i < 6; i++) {
            lavaComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 150,
                y: y,
                size: 50 + Math.random() * 60,
                lavaColor: colors[Math.floor(Math.random() * colors.length)]
            })
        }
    }
    function createMatrix(x, y) {
        for (var i = 0; i < 8; i++) {
            matrixComponent.createObject(root, {
                x: x + (Math.random() - 0.5) * 300,
                startY: y - 150
            })
        }
    }
    function createDisco(x, y) {
        for (var i = 0; i < 10; i++) {
            discoComponent.createObject(root, {
                centerX: x, centerY: y,
                angle: Math.random() * Math.PI * 2
            })
        }
    }
    function createAurora(x, y) { auroraComponent.createObject(root, { centerX: x, centerY: y }) }

    // ==================== PARTICLE COMPONENTS ====================

    Component {
        id: particleComponent
        Rectangle {
            id: p
            property real vx: 0
            property real vy: 0
            property real size: 8
            property string particleColor: "#ff3355"
            property real gravity: 350
            width: size; height: size; radius: size/2
            color: particleColor; z: 5
            Timer { interval: 33; running: true; repeat: true
                onTriggered: { p.x += p.vx * 0.033; p.y += p.vy * 0.033; p.vy += p.gravity * 0.033 }
            }
            NumberAnimation on opacity { from: 1; to: 0; duration: 1200 }
            Timer { interval: 1200; running: true; onTriggered: p.destroy() }
        }
    }

    Component {
        id: bubbleComponent
        Rectangle {
            id: b
            property real size: 50
            property real vy: -80
            width: size; height: size; radius: size/2
            color: "transparent"
            border.color: Qt.rgba(Math.random(), Math.random(), Math.random(), 0.6)
            border.width: 2; z: 5; scale: 0.2
            Timer { interval: 33; running: true; repeat: true
                onTriggered: { b.y += b.vy * 0.033; b.x += Math.sin(b.y * 0.04) * 1.5 }
            }
            NumberAnimation on scale { to: 1; duration: 250; easing.type: Easing.OutBack }
            NumberAnimation on opacity { from: 0.7; to: 0; duration: 1800 }
            Timer { interval: 1800; running: true; onTriggered: b.destroy() }
        }
    }

    Component {
        id: rippleComponent
        Rectangle {
            id: r
            property real centerX: 0
            property real centerY: 0
            property string rippleColor: "#ff0000"
            property int delay: 0
            x: centerX - 10; y: centerY - 10
            width: 20; height: 20; radius: 10
            color: "transparent"; border.color: rippleColor; border.width: 3
            opacity: 0; z: 5
            SequentialAnimation { running: true
                PauseAnimation { duration: r.delay }
                ParallelAnimation {
                    NumberAnimation { target: r; property: "scale"; from: 1; to: 25; duration: 1200; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        NumberAnimation { target: r; property: "opacity"; to: 0.7; duration: 100 }
                        NumberAnimation { target: r; property: "opacity"; to: 0; duration: 1100 }
                    }
                }
                ScriptAction { script: r.destroy() }
            }
        }
    }

    Component {
        id: sparkleComponent
        Rectangle {
            id: sp
            property real size: 5
            width: size; height: size; radius: size/2
            color: "#ffffff"; z: 5; scale: 0
            SequentialAnimation on scale {
                NumberAnimation { to: 1.3; duration: 250; easing.type: Easing.OutBack }
                NumberAnimation { to: 0; duration: 500 }
            }
            Timer { interval: 750; running: true; onTriggered: sp.destroy() }
        }
    }

    Component {
        id: splatComponent
        Rectangle {
            id: sl
            property real vx: 0
            property real vy: 0
            property real size: 25
            property string splatColor: "#ff3355"
            width: size; height: size; radius: size/2
            color: splatColor; z: 5; scale: 0.6
            Timer { interval: 33; running: true; repeat: true
                onTriggered: { sl.x += sl.vx * 0.033; sl.y += sl.vy * 0.033; sl.vx *= 0.92; sl.vy *= 0.92 }
            }
            NumberAnimation on scale { to: 1; duration: 150; easing.type: Easing.OutBack }
            Timer { interval: 1500; running: true; onTriggered: sl.destroy() }
        }
    }

    Component {
        id: ballComponent
        Rectangle {
            id: ball
            property real vx: 0
            property real vy: 0
            property real size: 40
            property string ballColor: "#ff3355"
            property real gravity: 600
            width: size; height: size; radius: size/2
            color: ballColor; z: 5
            Timer { interval: 33; running: true; repeat: true
                onTriggered: {
                    ball.x += ball.vx * 0.033; ball.y += ball.vy * 0.033; ball.vy += ball.gravity * 0.033
                    if (ball.y > root.height - ball.size) { ball.y = root.height - ball.size; ball.vy *= -0.65 }
                    if (ball.x < 0) { ball.x = 0; ball.vx *= -0.65 }
                    if (ball.x > root.width - ball.size) { ball.x = root.width - ball.size; ball.vx *= -0.65 }
                }
            }
            NumberAnimation on opacity { from: 1; to: 0; duration: 3000 }
            Timer { interval: 3000; running: true; onTriggered: ball.destroy() }
        }
    }

    Component {
        id: confettiComponent
        Rectangle {
            id: c
            property real vx: 0
            property real vy: 0
            property string confettiColor: "#ff3355"
            property real gravity: 400
            property real spin: (Math.random() - 0.5) * 600
            width: 10; height: 16; radius: 2
            color: confettiColor; z: 5
            transform: Rotation { id: rot; angle: 0; origin.x: 5; origin.y: 8 }
            Timer { interval: 33; running: true; repeat: true
                onTriggered: { c.x += c.vx * 0.033; c.y += c.vy * 0.033; c.vy += c.gravity * 0.033; rot.angle += c.spin * 0.033 }
            }
            Timer { interval: 2500; running: true; onTriggered: c.destroy() }
        }
    }

    Component {
        id: kaleidoComponent
        Rectangle {
            id: k
            property real centerX: 0
            property real centerY: 0
            property real angle: 0
            property string kaleidoColor: "#ff3355"
            property real dist: 0
            width: 50; height: 50; radius: 25
            color: kaleidoColor; z: 5
            x: centerX + Math.cos(angle) * dist - 25
            y: centerY + Math.sin(angle) * dist - 25
            NumberAnimation on dist { from: 0; to: 160; duration: 1200; easing.type: Easing.OutQuad }
            NumberAnimation on rotation { from: 0; to: 360; duration: 1200 }
            NumberAnimation on opacity { from: 0.8; to: 0; duration: 1200 }
            Timer { interval: 1200; running: true; onTriggered: k.destroy() }
        }
    }

    Component {
        id: lightningComponent
        Canvas {
            id: lt
            property real startX: 0
            property real startY: 0
            property real endX: 0
            property real endY: 0
            width: root.width; height: root.height; z: 20
            onPaint: {
                var ctx = getContext("2d")
                ctx.strokeStyle = "#88ccff"; ctx.lineWidth = 3; ctx.lineCap = "round"
                ctx.beginPath(); ctx.moveTo(startX, startY)
                var segs = 6
                for (var i = 0; i < segs; i++) {
                    var prog = (i + 1) / segs
                    ctx.lineTo(startX + (endX - startX) * prog + (Math.random() - 0.5) * 40,
                               startY + (endY - startY) * prog)
                }
                ctx.stroke()
            }
            Component.onCompleted: requestPaint()
            SequentialAnimation on opacity {
                NumberAnimation { to: 0; duration: 80 }
                NumberAnimation { to: 1; duration: 40 }
                NumberAnimation { to: 0; duration: 80 }
            }
            Timer { interval: 300; running: true; onTriggered: lt.destroy() }
        }
    }

    Component {
        id: petalComponent
        Rectangle {
            id: pt
            property real centerX: 0
            property real centerY: 0
            property real angle: 0
            property string petalColor: "#ff3388"
            property real dist: 0
            width: 32; height: 48; radius: 16
            color: petalColor; z: 5; scale: 0
            x: centerX + Math.cos(angle) * dist - 16
            y: centerY + Math.sin(angle) * dist - 24
            SequentialAnimation on scale {
                NumberAnimation { to: 1; duration: 350; easing.type: Easing.OutBack }
                PauseAnimation { duration: 500 }
                NumberAnimation { to: 0; duration: 350 }
            }
            NumberAnimation on dist { from: 0; to: 65; duration: 350; easing.type: Easing.OutQuad }
            Timer { interval: 1200; running: true; onTriggered: pt.destroy() }
        }
    }

    Component {
        id: snowComponent
        Rectangle {
            id: sn
            property real size: 10
            width: size; height: size; radius: size/2
            color: "#ffffff"; z: 5
            Timer { interval: 33; running: true; repeat: true
                onTriggered: { sn.y += (80 + Math.random() * 60) * 0.033; sn.x += Math.sin(sn.y * 0.015) * 0.8 }
            }
            Timer { interval: 2500; running: true; onTriggered: sn.destroy() }
        }
    }

    Component {
        id: neonComponent
        Rectangle {
            id: ne
            property real startX: 0
            property real startY: 0
            property real targetX: 0
            property real targetY: 0
            property string neonColor: "#ff00ff"
            width: 6; height: 6; radius: 3
            color: neonColor; z: 5
            x: startX; y: startY
            NumberAnimation on x { to: ne.targetX; duration: 600; easing.type: Easing.OutQuad }
            NumberAnimation on y { to: ne.targetY; duration: 600; easing.type: Easing.OutQuad }
            NumberAnimation on opacity { from: 0.9; to: 0; duration: 600 }
            Timer { interval: 600; running: true; onTriggered: ne.destroy() }
        }
    }

    Component {
        id: shapeComponent
        Rectangle {
            id: sh
            width: 100; height: 100
            color: Qt.rgba(Math.random(), Math.random(), Math.random(), 0.75)
            z: 5; scale: 0
            SequentialAnimation on scale {
                NumberAnimation { to: 1.3; duration: 600; easing.type: Easing.OutBack }
                NumberAnimation { to: 0; duration: 600; easing.type: Easing.InBack }
            }
            NumberAnimation on rotation { from: 0; to: 360; duration: 1200 }
            SequentialAnimation on radius {
                NumberAnimation { to: 50; duration: 400 }
                NumberAnimation { to: 0; duration: 400 }
                NumberAnimation { to: 25; duration: 400 }
            }
            Timer { interval: 1200; running: true; onTriggered: sh.destroy() }
        }
    }

    Component {
        id: galaxyStarComponent
        Rectangle {
            id: gs
            property real centerX: 0
            property real centerY: 0
            property real angle: 0
            property real dist: 100
            property string starColor: "#ffffff"
            property real curAngle: angle
            width: 5; height: 5; radius: 2.5
            color: starColor; z: 5
            x: centerX + Math.cos(curAngle) * dist - 2.5
            y: centerY + Math.sin(curAngle) * dist - 2.5
            Timer { interval: 33; running: true; repeat: true; onTriggered: gs.curAngle += 0.08 }
            NumberAnimation on dist { from: dist; to: 8; duration: 2000; easing.type: Easing.InQuad }
            Timer { interval: 2000; running: true; onTriggered: gs.destroy() }
        }
    }

    Component {
        id: rainComponent
        Rectangle {
            id: rd
            property real startY: 0
            property real targetY: 0
            width: 3; height: 16; radius: 1.5
            color: "#4488ff"; z: 5; y: startY
            NumberAnimation on y { to: rd.targetY; duration: 1200; easing.type: Easing.InQuad }
            Timer { interval: 1200; running: true; onTriggered: rd.destroy() }
        }
    }

    Component {
        id: lifeComponent
        Item {
            id: lf
            property real centerX: 0
            property real centerY: 0
            property var cells: []
            property int gridSize: 16
            property int cellSize: 18
            property int gen: 0
            width: gridSize * cellSize; height: gridSize * cellSize
            x: centerX - width/2; y: centerY - height/2; z: 5
            Component.onCompleted: {
                cells = []; for (var i = 0; i < gridSize * gridSize; i++) cells.push(Math.random() < 0.3)
                lfCanvas.requestPaint()
            }
            Canvas { id: lfCanvas; anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    var colors = ["#00ff88", "#00ffaa", "#00ffcc"]
                    for (var i = 0; i < lf.cells.length; i++) {
                        if (lf.cells[i]) {
                            ctx.fillStyle = colors[Math.floor(Math.random() * colors.length)]
                            ctx.fillRect((i % lf.gridSize) * lf.cellSize + 1, Math.floor(i / lf.gridSize) * lf.cellSize + 1, lf.cellSize - 2, lf.cellSize - 2)
                        }
                    }
                }
            }
            function getCell(x, y) { return (x < 0 || x >= gridSize || y < 0 || y >= gridSize) ? false : cells[y * gridSize + x] }
            function countN(x, y) {
                var c = 0
                for (var dy = -1; dy <= 1; dy++) for (var dx = -1; dx <= 1; dx++) if (!(dx === 0 && dy === 0) && getCell(x + dx, y + dy)) c++
                return c
            }
            Timer { interval: 200; running: true; repeat: true
                onTriggered: {
                    lf.gen++; if (lf.gen > 15) { lf.destroy(); return }
                    var nc = []
                    for (var i = 0; i < lf.gridSize * lf.gridSize; i++) {
                        var n = lf.countN(i % lf.gridSize, Math.floor(i / lf.gridSize))
                        nc.push(lf.cells[i] ? (n === 2 || n === 3) : (n === 3))
                    }
                    lf.cells = nc; lfCanvas.requestPaint()
                }
            }
            NumberAnimation on opacity { from: 1; to: 0; duration: 3500; easing.type: Easing.InQuad }
        }
    }

    Component {
        id: branchComponent
        Canvas {
            id: br
            property real startX: 0
            property real startY: 0
            property real angle: 0
            property real length: 80
            property real thickness: 4
            property int depth: 0
            property real gp: 0
            width: root.width; height: root.height; z: 5
            onPaint: {
                var ctx = getContext("2d")
                ctx.strokeStyle = depth < 2 ? "#8B4513" : "#228B22"
                ctx.lineWidth = thickness; ctx.lineCap = "round"
                ctx.beginPath(); ctx.moveTo(startX, startY)
                ctx.lineTo(startX + Math.cos(angle) * length * gp, startY + Math.sin(angle) * length * gp)
                ctx.stroke()
            }
            NumberAnimation on gp { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad
                onFinished: {
                    if (br.depth < 5 && br.length > 12) {
                        var ex = br.startX + Math.cos(br.angle) * br.length
                        var ey = br.startY + Math.sin(br.angle) * br.length
                        createBranch(ex, ey, br.angle - 0.35 - Math.random() * 0.25, br.length * 0.7, br.thickness * 0.7, br.depth + 1)
                        createBranch(ex, ey, br.angle + 0.35 + Math.random() * 0.25, br.length * 0.7, br.thickness * 0.7, br.depth + 1)
                    }
                }
            }
            onGpChanged: requestPaint()
            Timer { interval: 4000; running: true; onTriggered: br.destroy() }
            SequentialAnimation on opacity { PauseAnimation { duration: 3200 } NumberAnimation { to: 0; duration: 800 } }
        }
    }

    Component {
        id: spiralComponent
        Canvas {
            id: spi
            property real centerX: 0
            property real centerY: 0
            property real rot: 0
            width: root.width; height: root.height; z: 5
            onPaint: {
                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                for (var arm = 0; arm < 5; arm++) {
                    var aa = (Math.PI * 2 * arm) / 5 + rot
                    ctx.beginPath(); ctx.strokeStyle = Qt.hsla(arm / 5, 0.8, 0.5, 0.7); ctx.lineWidth = 3
                    for (var t = 0; t < 250; t += 6) {
                        var a = aa + t * 0.04, r = t * 0.7
                        if (t === 0) ctx.moveTo(centerX + Math.cos(a) * r, centerY + Math.sin(a) * r)
                        else ctx.lineTo(centerX + Math.cos(a) * r, centerY + Math.sin(a) * r)
                    }
                    ctx.stroke()
                }
            }
            NumberAnimation on rot { from: 0; to: Math.PI * 2; duration: 2500 }
            onRotChanged: requestPaint()
            Timer { interval: 2500; running: true; onTriggered: spi.destroy() }
            NumberAnimation on opacity { from: 1; to: 0; duration: 2500 }
        }
    }

    Component {
        id: waveComponent
        Canvas {
            id: wv
            property real centerX: 0
            property real centerY: 0
            property real t: 0
            width: root.width; height: root.height; z: 5
            Timer { interval: 50; running: true; repeat: true; onTriggered: { wv.t += 0.2; wv.requestPaint() } }
            onPaint: {
                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                for (var r = 15; r < 250; r += 18) {
                    ctx.beginPath(); ctx.strokeStyle = Qt.hsla(r / 250, 0.65, 0.5, 0.5); ctx.lineWidth = 2
                    for (var a = 0; a < Math.PI * 2; a += 0.08) {
                        var w = Math.sin(a * 7 + t) * 8
                        if (a === 0) ctx.moveTo(centerX + Math.cos(a) * (r + w), centerY + Math.sin(a) * (r + w))
                        else ctx.lineTo(centerX + Math.cos(a) * (r + w), centerY + Math.sin(a) * (r + w))
                    }
                    ctx.closePath(); ctx.stroke()
                }
            }
            Timer { interval: 2000; running: true; onTriggered: wv.destroy() }
            NumberAnimation on opacity { from: 1; to: 0; duration: 2000 }
        }
    }

    Component {
        id: heartComponent
        Text {
            id: ht
            property real size: 28
            property string heartColor: "#ff3366"
            text: "❤"; font.pixelSize: size; color: heartColor; z: 5
            NumberAnimation on y { from: y; to: y - 250; duration: 1600; easing.type: Easing.OutQuad }
            SequentialAnimation on scale {
                NumberAnimation { from: 0; to: 1.15; duration: 180; easing.type: Easing.OutBack }
                NumberAnimation { to: 1; duration: 80 }
            }
            NumberAnimation on opacity { from: 1; to: 0; duration: 1600 }
            Timer { interval: 1600; running: true; onTriggered: ht.destroy() }
        }
    }

    Component {
        id: twinkleComponent
        Rectangle {
            id: tw
            property real size: 12
            width: size; height: size; radius: size/2
            color: "#ffffff"; z: 5
            SequentialAnimation on scale { loops: 2
                NumberAnimation { from: 0; to: 1; duration: 200 }
                NumberAnimation { to: 0.25; duration: 150 }
                NumberAnimation { to: 1.1; duration: 200 }
                NumberAnimation { to: 0; duration: 300 }
            }
            Timer { interval: 1700; running: true; onTriggered: tw.destroy() }
        }
    }

    Component {
        id: lavaComponent
        Rectangle {
            id: lv
            property real size: 65
            property string lavaColor: "#ff6600"
            width: size; height: size; radius: size/2
            color: lavaColor; z: 5
            NumberAnimation on y { from: y; to: y - 300; duration: 2500; easing.type: Easing.InOutSine }
            SequentialAnimation on scale {
                NumberAnimation { from: 0.5; to: 1.2; duration: 1250; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.7; duration: 1250; easing.type: Easing.InOutSine }
            }
            NumberAnimation on opacity { from: 0.75; to: 0; duration: 2500 }
            Timer { interval: 2500; running: true; onTriggered: lv.destroy() }
        }
    }

    Component {
        id: matrixComponent
        Text {
            id: mx
            property real startY: 0
            text: { var c = "ｱｲｳｴｵｶｷ012345"; var r = ""; for (var i = 0; i < 12; i++) r += c[Math.floor(Math.random() * c.length)] + "\n"; return r }
            font.pixelSize: 14; font.family: "monospace"; color: "#00ff00"; y: startY; z: 5
            NumberAnimation on y { from: startY; to: root.height; duration: 1600 }
            NumberAnimation on opacity { from: 1; to: 0; duration: 1600 }
            Timer { interval: 1600; running: true; onTriggered: mx.destroy() }
        }
    }

    Component {
        id: discoComponent
        Rectangle {
            id: ds
            property real centerX: 0
            property real centerY: 0
            property real angle: 0
            property real dist: 0
            width: 16; height: 250
            color: Qt.hsla(Math.random(), 0.8, 0.55, 0.65); z: 5
            x: centerX + Math.cos(angle) * dist - 8
            y: centerY + Math.sin(angle) * dist
            rotation: angle * 180 / Math.PI + 90
            NumberAnimation on dist { from: 0; to: 350; duration: 1200; easing.type: Easing.OutQuad }
            NumberAnimation on opacity { from: 0.7; to: 0; duration: 1200 }
            Timer { interval: 1200; running: true; onTriggered: ds.destroy() }
        }
    }

    Component {
        id: auroraComponent
        Canvas {
            id: au
            property real centerX: 0
            property real centerY: 0
            property real t: 0
            width: root.width; height: root.height; z: 5
            Timer { interval: 50; running: true; repeat: true; onTriggered: { au.t += 0.07; au.requestPaint() } }
            onPaint: {
                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                var colors = ["#00ff88", "#00ffcc", "#88ff00", "#00ccff"]
                for (var i = 0; i < 4; i++) {
                    ctx.beginPath()
                    var grad = ctx.createLinearGradient(0, centerY - 150, 0, centerY + 150)
                    grad.addColorStop(0, "transparent"); grad.addColorStop(0.5, colors[i]); grad.addColorStop(1, "transparent")
                    ctx.fillStyle = grad
                    ctx.moveTo(centerX - 250, centerY + 150)
                    for (var x = -250; x <= 250; x += 18) {
                        var w = Math.sin(x * 0.018 + t + i) * 40 + Math.sin(x * 0.01 + t * 0.4) * 25
                        ctx.lineTo(centerX + x, centerY + w - i * 25)
                    }
                    ctx.lineTo(centerX + 250, centerY + 150); ctx.closePath()
                    ctx.globalAlpha = 0.25; ctx.fill()
                }
                ctx.globalAlpha = 1
            }
            Timer { interval: 2500; running: true; onTriggered: au.destroy() }
            NumberAnimation on opacity { from: 1; to: 0; duration: 2500 }
        }
    }

    // Home indicator
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 120; height: 4; radius: 2
        color: "#333344"; z: 99
    }
}
