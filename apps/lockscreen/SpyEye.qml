import QtQuick 2.15

// Spooky eye effect that appears after inactivity
// Line-drawing style eye that opens, looks around, then closes
Item {
    id: spyEye

    property bool enabled: true
    property int inactivityDelay: 8000  // ms before eye appears
    property int lookDuration: 6000     // ms the eye stays open looking around
    property int cyclePause: 15000      // ms between eye appearances

    property real openAmount: 0         // 0 = closed, 1 = fully open
    property real pupilX: 0             // -1 to 1, horizontal look direction
    property real pupilY: 0             // -1 to 1, vertical look direction

    property string eyeState: "closed"   // closed, opening, looking, closing

    visible: enabled && openAmount > 0.01
    opacity: Math.min(1, openAmount * 2)

    // Inactivity timer - starts the eye opening
    Timer {
        id: inactivityTimer
        interval: spyEye.inactivityDelay
        running: spyEye.enabled && spyEye.eyeState === "closed"
        onTriggered: {
            spyEye.eyeState = "opening"
            openAnimation.start()
        }
    }

    // Animation to open the eye
    SequentialAnimation {
        id: openAnimation

        NumberAnimation {
            target: spyEye
            property: "openAmount"
            from: 0
            to: 1
            duration: 1200
            easing.type: Easing.InOutQuad
        }

        ScriptAction {
            script: {
                spyEye.eyeState = "looking"
                lookTimer.start()
                pupilMoveTimer.start()
            }
        }
    }

    // Timer for how long the eye looks around
    Timer {
        id: lookTimer
        interval: spyEye.lookDuration
        onTriggered: {
            pupilMoveTimer.stop()
            spyEye.eyeState = "closing"
            closeAnimation.start()
        }
    }

    // Timer to move the pupil randomly
    Timer {
        id: pupilMoveTimer
        interval: 800 + Math.random() * 1200
        repeat: true
        onTriggered: {
            // Random look direction
            targetPupilX = (Math.random() - 0.5) * 1.6
            targetPupilY = (Math.random() - 0.5) * 0.8
            pupilMoveAnimation.start()
            interval = 800 + Math.random() * 1200
        }
    }

    property real targetPupilX: 0
    property real targetPupilY: 0

    ParallelAnimation {
        id: pupilMoveAnimation
        NumberAnimation {
            target: spyEye
            property: "pupilX"
            to: spyEye.targetPupilX
            duration: 400
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: spyEye
            property: "pupilY"
            to: spyEye.targetPupilY
            duration: 400
            easing.type: Easing.InOutSine
        }
    }

    // Animation to close the eye
    SequentialAnimation {
        id: closeAnimation

        // First center the pupil
        ParallelAnimation {
            NumberAnimation {
                target: spyEye
                property: "pupilX"
                to: 0
                duration: 300
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: spyEye
                property: "pupilY"
                to: 0
                duration: 300
                easing.type: Easing.InOutSine
            }
        }

        PauseAnimation { duration: 200 }

        NumberAnimation {
            target: spyEye
            property: "openAmount"
            to: 0
            duration: 800
            easing.type: Easing.InOutQuad
        }

        ScriptAction {
            script: {
                spyEye.eyeState = "closed"
                cycleTimer.start()
            }
        }
    }

    // Timer before next eye appearance
    Timer {
        id: cycleTimer
        interval: spyEye.cyclePause
        onTriggered: {
            if (spyEye.enabled) {
                inactivityTimer.restart()
            }
        }
    }

    // Reset on user activity
    function onUserActivity() {
        if (eyeState !== "closed") {
            openAnimation.stop()
            lookTimer.stop()
            pupilMoveTimer.stop()
            closeAnimation.stop()
            cycleTimer.stop()

            // Quick close
            quickCloseAnimation.start()
        } else {
            inactivityTimer.restart()
        }
    }

    SequentialAnimation {
        id: quickCloseAnimation
        NumberAnimation {
            target: spyEye
            property: "openAmount"
            to: 0
            duration: 200
            easing.type: Easing.InQuad
        }
        ScriptAction {
            script: {
                spyEye.eyeState = "closed"
                spyEye.pupilX = 0
                spyEye.pupilY = 0
                inactivityTimer.restart()
            }
        }
    }

    // The actual eye drawing using Canvas
    Canvas {
        id: eyeCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var w = width
            var h = height
            var centerX = w / 2
            var centerY = h / 2

            // Eye dimensions - as big as possible
            var eyeWidth = w * 0.85
            var eyeHeight = h * 0.4 * openAmount

            // Line style
            ctx.strokeStyle = "#ffffff"
            ctx.lineWidth = Math.max(3, w * 0.004)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            // Draw upper eyelid
            ctx.beginPath()
            ctx.moveTo(centerX - eyeWidth/2, centerY)
            ctx.quadraticCurveTo(
                centerX, centerY - eyeHeight,
                centerX + eyeWidth/2, centerY
            )
            ctx.stroke()

            // Draw lower eyelid
            ctx.beginPath()
            ctx.moveTo(centerX - eyeWidth/2, centerY)
            ctx.quadraticCurveTo(
                centerX, centerY + eyeHeight * 0.7,
                centerX + eyeWidth/2, centerY
            )
            ctx.stroke()

            if (openAmount > 0.3) {
                // Iris
                var irisRadius = eyeHeight * 0.6
                var pupilRadius = irisRadius * 0.5

                // Pupil position with limits
                var maxMoveX = eyeWidth * 0.15
                var maxMoveY = eyeHeight * 0.2
                var irisX = centerX + pupilX * maxMoveX
                var irisY = centerY + pupilY * maxMoveY

                // Outer iris circle
                ctx.beginPath()
                ctx.arc(irisX, irisY, irisRadius, 0, Math.PI * 2)
                ctx.stroke()

                // Inner iris detail circles
                ctx.lineWidth = Math.max(2, w * 0.002)
                ctx.beginPath()
                ctx.arc(irisX, irisY, irisRadius * 0.75, 0, Math.PI * 2)
                ctx.stroke()

                // Pupil (filled)
                ctx.fillStyle = "#ffffff"
                ctx.beginPath()
                ctx.arc(irisX, irisY, pupilRadius, 0, Math.PI * 2)
                ctx.fill()

                // Highlight
                ctx.fillStyle = "#000000"
                ctx.beginPath()
                ctx.arc(irisX - pupilRadius * 0.3, irisY - pupilRadius * 0.3, pupilRadius * 0.3, 0, Math.PI * 2)
                ctx.fill()

                // Iris lines (radial)
                ctx.strokeStyle = "rgba(255, 255, 255, 0.4)"
                ctx.lineWidth = 1
                for (var i = 0; i < 16; i++) {
                    var angle = (i / 16) * Math.PI * 2
                    ctx.beginPath()
                    ctx.moveTo(irisX + Math.cos(angle) * pupilRadius * 1.2,
                               irisY + Math.sin(angle) * pupilRadius * 1.2)
                    ctx.lineTo(irisX + Math.cos(angle) * irisRadius * 0.9,
                               irisY + Math.sin(angle) * irisRadius * 0.9)
                    ctx.stroke()
                }
            }

            // Eyelash details on upper lid
            if (openAmount > 0.1) {
                ctx.strokeStyle = "rgba(255, 255, 255, 0.6)"
                ctx.lineWidth = Math.max(2, w * 0.002)

                var lashCount = 7
                for (var j = 0; j < lashCount; j++) {
                    var t = (j + 1) / (lashCount + 1)
                    var lashX = centerX - eyeWidth/2 + eyeWidth * t
                    // Calculate Y on the curve
                    var curveT = t * 2 - 1  // -1 to 1
                    var lashY = centerY - eyeHeight * (1 - curveT * curveT)

                    // Lash pointing outward and up
                    var lashAngle = -Math.PI/2 - (t - 0.5) * 0.5
                    var lashLength = eyeHeight * 0.15

                    ctx.beginPath()
                    ctx.moveTo(lashX, lashY)
                    ctx.lineTo(lashX + Math.cos(lashAngle) * lashLength,
                               lashY + Math.sin(lashAngle) * lashLength)
                    ctx.stroke()
                }
            }
        }
    }

    // Redraw when properties change
    onOpenAmountChanged: eyeCanvas.requestPaint()
    onPupilXChanged: eyeCanvas.requestPaint()
    onPupilYChanged: eyeCanvas.requestPaint()
    onWidthChanged: eyeCanvas.requestPaint()
    onHeightChanged: eyeCanvas.requestPaint()
}
