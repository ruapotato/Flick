import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root
    width: 400
    height: 800
    visible: true
    title: "Orbital Home Test"
    color: "#1a1a2e"

    // Configuration
    property real iconSize: 72
    property real firstRadius: 120
    property real ringSpacing: 100
    property real arcSpacing: 95

    // Handedness: false = left-handed (anchor bottom-left), true = right-handed (anchor bottom-right)
    property bool rightHanded: true

    // Anchor point based on handedness
    property real anchorX: rightHanded ? width : 0
    property real anchorY: height

    // Margin from edge for first column of icons
    property real edgeMargin: iconSize/2 + 10

    // Ring colors
    property var ringColors: [
        {h: 0.85, s: 0.7, l: 0.5},
        {h: 0.75, s: 0.7, l: 0.5},
        {h: 0.65, s: 0.7, l: 0.5},
        {h: 0.55, s: 0.7, l: 0.5},
        {h: 0.45, s: 0.7, l: 0.5},
        {h: 0.35, s: 0.7, l: 0.5},
        {h: 0.25, s: 0.7, l: 0.5},
        {h: 0.15, s: 0.7, l: 0.5},
        {h: 0.08, s: 0.7, l: 0.5},
        {h: 0.0,  s: 0.7, l: 0.5}
    ]

    function hslToRgb(h, s, l) {
        var r, g, b;
        if (s === 0) {
            r = g = b = l;
        } else {
            function hue2rgb(p, q, t) {
                if (t < 0) t += 1;
                if (t > 1) t -= 1;
                if (t < 1/6) return p + (q - p) * 6 * t;
                if (t < 1/2) return q;
                if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
                return p;
            }
            var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
            var p = 2 * l - q;
            r = hue2rgb(p, q, h + 1/3);
            g = hue2rgb(p, q, h);
            b = hue2rgb(p, q, h - 1/3);
        }
        return Qt.rgba(r, g, b, 1);
    }

    function getRingColor(ringIndex) {
        var idx = ringIndex % ringColors.length;
        var c = ringColors[idx];
        return hslToRgb(c.h, c.s, c.l);
    }

    // Sample apps
    property var apps: [
        {name: "Phone"}, {name: "Messages"}, {name: "Camera"}, {name: "Browser"},
        {name: "Settings"}, {name: "Music"}, {name: "Maps"}, {name: "Photos"},
        {name: "Calendar"}, {name: "Notes"}, {name: "Mail"}, {name: "Files"},
        {name: "Clock"}, {name: "Weather"}, {name: "Store"}, {name: "Videos"},
        {name: "Contacts"}, {name: "Calc"}, {name: "Record"}, {name: "Radio"},
        {name: "News"}, {name: "Books"}, {name: "Podcast"}, {name: "Health"},
        {name: "Wallet"}, {name: "Games"}, {name: "Social"}, {name: "Shop"}
    ]

    // Visible slots for a ring (how many fit in 90 degree arc)
    function visibleSlots(radius) {
        var arcLength = (Math.PI / 2) * radius;
        var count = Math.floor(arcLength / arcSpacing);
        return Math.max(2, Math.min(count, 12));
    }

    // Generate ring data
    function generateRings() {
        var rings = [];
        var appIndex = 0;
        var maxRings = 8;

        for (var ringIndex = 0; ringIndex < maxRings; ringIndex++) {
            var radius = firstRadius + (ringIndex * ringSpacing);
            var visSlots = visibleSlots(radius);
            var angleStep = 90 / visSlots;

            // Collect apps for this ring
            var ringApps = [];
            while (appIndex < apps.length && ringApps.length < visSlots) {
                ringApps.push(apps[appIndex]);
                appIndex++;
            }

            // Total slots = max of visible slots or actual apps (for looping)
            // If fewer apps than visible, we loop apps+blanks
            // If more apps than visible, we loop all apps
            var totalSlots = Math.max(visSlots, ringApps.length);

            var slots = [];
            for (var i = 0; i < totalSlots; i++) {
                slots.push({
                    slotIndex: i,
                    app: i < ringApps.length ? ringApps[i] : null
                });
            }

            rings.push({
                ringIndex: ringIndex,
                radius: radius,
                visibleSlots: visSlots,
                totalSlots: totalSlots,
                angleStep: angleStep,
                slots: slots
            });
        }
        return rings;
    }

    property var rings: generateRings()

    // Physics timer with gentle snap-to-grid
    Timer {
        id: physicsTimer
        interval: 16
        repeat: true
        running: true
        onTriggered: {
            for (var i = 0; i < ringRepeater.count; i++) {
                var ring = ringRepeater.itemAt(i);
                if (!ring) continue;

                if (!ring.isDragging) {
                    var angleStep = ring.ringData.angleStep;
                    var currentOffset = ((ring.ringRotation % angleStep) + angleStep) % angleStep;
                    var distToSnap = Math.min(currentOffset, angleStep - currentOffset);
                    var isAtGrid = distToSnap < 0.3;

                    if (Math.abs(ring.velocity) > 0.01) {
                        // Apply friction
                        ring.velocity *= 0.96;

                        // Minimum speed until we hit grid
                        var minSpeed = 0.15;
                        if (!isAtGrid && Math.abs(ring.velocity) < minSpeed) {
                            ring.velocity = ring.velocity > 0 ? minSpeed : -minSpeed;
                        }

                        ring.ringRotation += ring.velocity;

                        // If at grid and slow enough, stop and snap exactly
                        if (isAtGrid && Math.abs(ring.velocity) < 0.4) {
                            ring.velocity = 0;
                        }
                    } else {
                        // When stopped, always snap exactly to nearest grid
                        if (distToSnap > 0.001) {
                            var snapTarget;
                            if (currentOffset < angleStep / 2) {
                                snapTarget = ring.ringRotation - currentOffset;
                            } else {
                                snapTarget = ring.ringRotation + (angleStep - currentOffset);
                            }
                            // Round to eliminate floating point errors
                            ring.ringRotation = Math.round(snapTarget * 1000) / 1000;
                        }
                    }

                }
            }
        }
    }

    // Draw colored arc backgrounds
    Canvas {
        id: arcCanvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();

            // Canvas angles: 0 = right, -π/2 = up, π = left, π/2 = down
            // Right-handed (bottom-right): arc from up (-π/2) to left (-π)
            // Left-handed (bottom-left): arc from right (0) to up (-π/2)
            var startAngle, endAngle;
            if (rightHanded) {
                startAngle = -Math.PI;      // left
                endAngle = -Math.PI / 2;    // up
            } else {
                startAngle = -Math.PI / 2;  // up
                endAngle = 0;               // right
            }

            for (var i = 0; i < rings.length; i++) {
                var innerR = (i === 0) ? 0 : (firstRadius + (i - 1) * ringSpacing + ringSpacing/2);
                var outerR = firstRadius + i * ringSpacing + ringSpacing/2;
                var color = getRingColor(i);

                ctx.beginPath();
                // Draw outer arc
                ctx.arc(anchorX, anchorY, outerR, startAngle, endAngle, false);
                // Draw inner arc in reverse
                ctx.arc(anchorX, anchorY, innerR, endAngle, startAngle, true);
                ctx.closePath();

                ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.4);
                ctx.fill();
            }
        }
        Component.onCompleted: requestPaint()

        Connections {
            target: root
            function onRightHandedChanged() { arcCanvas.requestPaint() }
        }

        // Handle swipes anywhere in the arc area
        MouseArea {
            anchors.fill: parent
            property int activeRing: -1
            property real startAngle: 0
            property real startRotation: 0
            property real lastAngle: 0
            property real lastTime: 0

            function getRingAt(mx, my) {
                var dx = mx - anchorX;
                var dy = anchorY - my;
                var dist = Math.sqrt(dx*dx + dy*dy);
                // Find which ring this distance falls into
                for (var i = 0; i < rings.length; i++) {
                    var innerR = (i === 0) ? 0 : (firstRadius + (i - 1) * ringSpacing + ringSpacing/2);
                    var outerR = firstRadius + i * ringSpacing + ringSpacing/2;
                    if (dist >= innerR && dist < outerR) {
                        return i;
                    }
                }
                return -1;
            }

            function getAngle(mx, my) {
                var dx = mx - anchorX;
                var dy = anchorY - my;
                var angle = Math.atan2(dx, dy) * 180 / Math.PI;
                if (rightHanded) angle = -angle;
                return angle;
            }

            onPressed: {
                activeRing = getRingAt(mouse.x, mouse.y);
                if (activeRing >= 0 && activeRing < ringRepeater.count) {
                    var ring = ringRepeater.itemAt(activeRing);
                    if (ring) {
                        startAngle = getAngle(mouse.x, mouse.y);
                        lastAngle = startAngle;
                        startRotation = ring.ringRotation;
                        lastTime = Date.now();
                        ring.isDragging = true;
                        ring.velocity = 0;
                    }
                }
            }

            onPositionChanged: {
                if (activeRing >= 0 && activeRing < ringRepeater.count) {
                    var ring = ringRepeater.itemAt(activeRing);
                    if (ring) {
                        var currentAngle = getAngle(mouse.x, mouse.y);
                        var now = Date.now();
                        var dt = Math.max(1, now - lastTime);
                        ring.velocity = (currentAngle - lastAngle) / dt * 16;
                        ring.ringRotation = startRotation + (currentAngle - startAngle);
                        lastAngle = currentAngle;
                        lastTime = now;
                    }
                }
            }

            onReleased: {
                if (activeRing >= 0 && activeRing < ringRepeater.count) {
                    var ring = ringRepeater.itemAt(activeRing);
                    if (ring) {
                        ring.isDragging = false;
                    }
                }
                activeRing = -1;
            }
        }
    }

    // Draw rings of icons
    Repeater {
        id: ringRepeater
        model: rings

        Item {
            id: ringItem
            property var ringData: modelData
            property real ringRotation: 0
            property real velocity: 0
            property bool isDragging: false

            // Draw ALL slots, with wrapping
            Repeater {
                model: ringItem.ringData.totalSlots

                Rectangle {
                    id: slotRect
                    property int slotIndex: index
                    property var slotData: ringItem.ringData.slots[index]
                    property real ringRadius: ringItem.ringData.radius
                    property real angleStep: ringItem.ringData.angleStep
                    property int totalSlots: ringItem.ringData.totalSlots

                    // Calculate start angle so first icon is at edgeMargin from screen edge
                    // sin(startAngle) * radius = edgeMargin
                    property real startAngleForRing: Math.asin(Math.min(1, edgeMargin / ringRadius)) * 180 / Math.PI

                    // Calculate base angle for this slot
                    property real slotBaseAngle: slotIndex * angleStep + startAngleForRing

                    // Calculate display angle with wrapping
                    property real rawAngle: slotBaseAngle + ringItem.ringRotation
                    // Total orbit for wrapping
                    property real totalOrbit: totalSlots * angleStep

                    // Calculate angular size of icon at this radius (for proper off-screen buffer)
                    property real iconAngularSize: (iconSize / ringRadius) * 180 / Math.PI * 0.5
                    property real buffer: Math.min(15, iconAngularSize + 5)

                    // Effective orbit must be a multiple of angleStep for proper grid alignment
                    // Minimum slots needed to have space for exit and entry
                    property int minSlots: Math.ceil((90 + buffer * 2) / angleStep)
                    property int effectiveSlots: Math.max(totalSlots, minSlots)
                    property real effectiveOrbit: effectiveSlots * angleStep

                    // Wrap angle into visible range with smooth transitions
                    property real displayAngle: {
                        // Normalize to 0..effectiveOrbit range
                        var a = ((rawAngle % effectiveOrbit) + effectiveOrbit) % effectiveOrbit;

                        // Visible window is 0-90, with buffer on each side for fade
                        var exitAngle = 90 + buffer;
                        var entryAngle = buffer;

                        // Show if exiting (0 to exitAngle)
                        if (a <= exitAngle) {
                            return a;
                        }
                        // Show if entering (effectiveOrbit - entryAngle to effectiveOrbit)
                        if (a >= effectiveOrbit - entryAngle) {
                            return a - effectiveOrbit;
                        }
                        // Hidden - traveling through the back
                        return -999;
                    }

                    property real angleRad: displayAngle * Math.PI / 180

                    visible: displayAngle >= -buffer && displayAngle <= 90 + buffer
                    opacity: {
                        if (displayAngle < 0) return Math.max(0, (displayAngle + buffer) / buffer);
                        if (displayAngle > 90) return Math.max(0, (90 + buffer - displayAngle) / buffer);
                        return 1;
                    }

                    // Pure orbital positioning
                    x: rightHanded
                        ? anchorX - Math.sin(angleRad) * ringRadius - width/2
                        : anchorX + Math.sin(angleRad) * ringRadius - width/2
                    y: anchorY - Math.cos(angleRad) * ringRadius - height/2

                    width: iconSize
                    height: iconSize
                    radius: 16
                    color: slotData.app ? "#2a2a3e" : "transparent"
                    border.color: slotData.app ? "#4a4a5e" : "#2a2a3e"
                    border.width: 1

                    Text {
                        visible: slotData.app !== null
                        anchors.centerIn: parent
                        text: slotData.app ? slotData.app.name.substring(0, 2) : ""
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                    }



                    MouseArea {
                        anchors.fill: parent
                        property real startAngle: 0
                        property real startRotation: 0
                        property real lastAngle: 0
                        property real lastTime: 0
                        property bool moved: false

                        function getAngle(mx, my) {
                            // Get position relative to anchor
                            var px = mx + slotRect.x + slotRect.width/2;
                            var py = my + slotRect.y + slotRect.height/2;
                            var dx = px - anchorX;
                            var dy = anchorY - py;
                            // For both modes, angle 0 = straight up, positive = toward edge of screen
                            // atan2(dx, dy) gives angle from vertical
                            var angle = Math.atan2(dx, dy) * 180 / Math.PI;
                            // For right-handed, dx is negative, so angle is negative - negate to make positive rotation go "up"
                            if (rightHanded) angle = -angle;
                            return angle;
                        }

                        onPressed: {
                            startAngle = getAngle(mouseX, mouseY);
                            lastAngle = startAngle;
                            startRotation = ringItem.ringRotation;
                            lastTime = Date.now();
                            moved = false;
                            ringItem.isDragging = true;
                            ringItem.velocity = 0;
                        }

                        onPositionChanged: {
                            var currentAngle = getAngle(mouseX, mouseY);
                            var now = Date.now();
                            var dt = Math.max(1, now - lastTime);

                            ringItem.velocity = (currentAngle - lastAngle) / dt * 16;
                            ringItem.ringRotation = startRotation + (currentAngle - startAngle);
                            lastAngle = currentAngle;
                            lastTime = now;

                            if (Math.abs(currentAngle - startAngle) > 3) {
                                moved = true;
                            }
                        }

                        onReleased: {
                            ringItem.isDragging = false;
                            if (!moved && slotData.app) {
                                console.log("Tapped: " + slotData.app.name);
                            }
                        }
                    }
                }
            }
        }
    }

    // Toggle handedness button
    Rectangle {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.margins: 20
        width: 200
        height: 40
        radius: 20
        color: "#3a3a4e"

        Text {
            anchors.centerIn: parent
            text: rightHanded ? "Right-handed (tap to switch)" : "Left-handed (tap to switch)"
            color: "white"
            font.pixelSize: 12
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                rightHanded = !rightHanded
                arcCanvas.requestPaint()
            }
        }
    }
}
