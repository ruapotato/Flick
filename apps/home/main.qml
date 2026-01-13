import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Flick Home"
    color: "#1a1a2e"
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint

    // State directory - read from state_dir.txt written by run_home.sh
    property string stateDir: "/home/furios/.local/state/flick"

    // Configuration - sizes scaled for phone display
    // Icons should be large and easy to tap
    property real iconSize: 180
    property real firstRadius: 200
    property real ringSpacing: 200
    property real arcSpacing: 180

    // Handedness: false = left-handed (anchor bottom-left), true = right-handed (anchor bottom-right)
    property bool rightHanded: true

    // Anchor point based on handedness
    property real anchorX: rightHanded ? width : 0
    property real anchorY: height

    // Margin from edge for first column of icons
    property real edgeMargin: iconSize/2 + 20

    // Ring colors - vibrant rainbow from purple to red
    property var ringColors: [
        {h: 0.83, s: 0.85, l: 0.45},  // Purple
        {h: 0.70, s: 0.85, l: 0.45},  // Blue
        {h: 0.55, s: 0.85, l: 0.45},  // Cyan
        {h: 0.40, s: 0.85, l: 0.45},  // Green
        {h: 0.30, s: 0.85, l: 0.45},  // Yellow-green
        {h: 0.18, s: 0.85, l: 0.45},  // Orange
        {h: 0.08, s: 0.85, l: 0.45},  // Red-orange
        {h: 0.0,  s: 0.85, l: 0.45}   // Red
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

    // Apps loaded from JSON
    property var apps: []

    Component.onCompleted: {
        console.log("Home screen started, stateDir:", stateDir);
        loadApps();
        loadConfig();
    }

    // Reload config when window becomes active (e.g., when swiping back to home)
    onActiveChanged: {
        if (active) {
            console.log("Window became active, reloading config");
            loadConfig();
        }
    }

    // Poll config frequently for responsive handedness switching
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    // Load apps from JSON file provided by compositor
    function loadApps() {
        var xhr = new XMLHttpRequest();
        var url = "file://" + stateDir + "/apps.json";
        xhr.open("GET", url, false);
        try {
            xhr.send();
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText);
                // apps.json is a direct array, not {apps: [...]}
                apps = Array.isArray(data) ? data : (data.apps || []);
                console.log("Loaded", apps.length, "apps");
                rings = generateRings();
                arcCanvas.requestPaint();
            }
        } catch (e) {
            console.log("Could not load apps.json:", e);
            // Use placeholder apps for testing
            apps = [
                {id: "phone", name: "Phone", icon: "phone", exec: ""},
                {id: "messages", name: "Messages", icon: "messages", exec: ""},
                {id: "settings", name: "Settings", icon: "settings", exec: ""},
                {id: "calendar", name: "Calendar", icon: "calendar", exec: ""},
                {id: "clock", name: "Clock", icon: "clock", exec: ""},
                {id: "photos", name: "Photos", icon: "photos", exec: ""},
                {id: "music", name: "Music", icon: "music", exec: ""},
                {id: "files", name: "Files", icon: "files", exec: ""},
                {id: "web", name: "Browser", icon: "web", exec: ""},
                {id: "email", name: "Email", icon: "email", exec: ""},
                {id: "contacts", name: "Contacts", icon: "contacts", exec: ""},
                {id: "notes", name: "Notes", icon: "notes", exec: ""},
                {id: "weather", name: "Weather", icon: "weather", exec: ""},
                {id: "maps", name: "Maps", icon: "maps", exec: ""},
                {id: "calculator", name: "Calculator", icon: "calculator", exec: ""},
                {id: "terminal", name: "Terminal", icon: "terminal", exec: ""}
            ];
            rings = generateRings();
        }
    }

    // Load config (handedness, etc.)
    function loadConfig() {
        var xhr = new XMLHttpRequest();
        var url = "file://" + stateDir + "/home_config.json";
        xhr.open("GET", url, false);
        try {
            xhr.send();
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText);
                if (config.rightHanded !== undefined) rightHanded = config.rightHanded;
                arcCanvas.requestPaint();
            }
        } catch (e) {
            // Use defaults
        }
    }

    // Launch an app by writing to signal file
    function launchApp(appId, execCmd) {
        console.log("Launching app:", appId);
        var signalPath = stateDir + "/launch_app";
        var data = JSON.stringify({id: appId, exec: execCmd});

        // Write using console output that wrapper script can capture
        console.log("FLICK_LAUNCH_APP:" + signalPath + ":" + data);

        // Also try direct file write
        var xhr = new XMLHttpRequest();
        xhr.open("PUT", "file://" + signalPath, false);
        try {
            xhr.send(data);
        } catch (e) {
            console.log("Could not write launch signal");
        }
    }

    // Visible slots for a ring (how many fit in 90 degree arc)
    function visibleSlots(radius) {
        var arcLength = (Math.PI / 2) * radius;
        var count = Math.floor(arcLength / arcSpacing);
        return Math.max(2, Math.min(count, 12));
    }

    // Generate ring data
    function generateRings() {
        var result = [];
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

            var totalSlots = Math.max(visSlots, ringApps.length);

            var slots = [];
            for (var i = 0; i < totalSlots; i++) {
                slots.push({
                    slotIndex: i,
                    app: i < ringApps.length ? ringApps[i] : null
                });
            }

            result.push({
                ringIndex: ringIndex,
                radius: radius,
                visibleSlots: visSlots,
                totalSlots: totalSlots,
                angleStep: angleStep,
                slots: slots
            });
        }
        return result;
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
                        ring.velocity *= 0.96;

                        var minSpeed = 0.15;
                        if (!isAtGrid && Math.abs(ring.velocity) < minSpeed) {
                            ring.velocity = ring.velocity > 0 ? minSpeed : -minSpeed;
                        }

                        ring.ringRotation += ring.velocity;

                        if (isAtGrid && Math.abs(ring.velocity) < 0.4) {
                            ring.velocity = 0;
                        }
                    } else {
                        if (distToSnap > 0.001) {
                            var snapTarget;
                            if (currentOffset < angleStep / 2) {
                                snapTarget = ring.ringRotation - currentOffset;
                            } else {
                                snapTarget = ring.ringRotation + (angleStep - currentOffset);
                            }
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
            ctx.clearRect(0, 0, width, height);

            // Don't draw if window isn't sized yet
            if (width <= 0 || height <= 0) {
                console.log("Canvas not sized yet, skipping paint");
                return;
            }

            var startAngle, endAngle;
            if (rightHanded) {
                // Right-handed: arc from bottom-right corner, spanning up-left quadrant
                startAngle = Math.PI;      // 180 degrees (pointing left)
                endAngle = Math.PI * 1.5;  // 270 degrees (pointing up)
            } else {
                // Left-handed: arc from bottom-left corner, spanning up-right quadrant
                startAngle = Math.PI * 1.5;  // 270 degrees (pointing up)
                endAngle = Math.PI * 2;      // 360 degrees (pointing right)
            }

            // Calculate anchor at corner
            var ax = rightHanded ? width : 0;
            var ay = height;

            console.log("Drawing arcs: canvas=" + width + "x" + height + " anchor=" + ax + "," + ay + " rings=" + rings.length + " rightHanded=" + rightHanded);

            // Draw all rings from outermost to innermost
            for (var i = rings.length - 1; i >= 0; i--) {
                // Ring i has icons at radius: firstRadius + i * ringSpacing
                // Band should be centered on that radius
                var iconRadius = firstRadius + i * ringSpacing;
                var bandHalf = ringSpacing / 2;
                var innerR = (i === 0) ? 0 : (iconRadius - bandHalf);
                var outerR = iconRadius + bandHalf;
                var color = getRingColor(i);

                console.log("Ring " + i + ": iconR=" + iconRadius + " band=" + innerR + "-" + outerR);

                ctx.beginPath();
                ctx.arc(ax, ay, outerR, startAngle, endAngle, false);
                if (innerR > 0) {
                    ctx.arc(ax, ay, innerR, endAngle, startAngle, true);
                } else {
                    ctx.lineTo(ax, ay);
                }
                ctx.closePath();

                ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.5);
                ctx.fill();
            }
        }

        // Repaint after a delay to ensure window is sized
        Timer {
            id: initialPaintTimer
            interval: 100
            running: true
            onTriggered: arcCanvas.requestPaint()
        }

        Connections {
            target: root
            function onRightHandedChanged() { arcCanvas.requestPaint() }
            function onWidthChanged() { arcCanvas.requestPaint() }
            function onHeightChanged() { arcCanvas.requestPaint() }
        }

        // Handle swipes anywhere in the arc area (background swipes)
        // Icons have their own MouseAreas that take priority
        MouseArea {
            anchors.fill: parent
            z: -1  // Behind icons
            property int activeRing: -1
            property real startAngle: 0
            property real startRotation: 0
            property real lastAngle: 0
            property real lastTime: 0

            function getRingAt(mx, my) {
                var ax = rightHanded ? root.width : 0;
                var ay = root.height;
                var dx = mx - ax;
                var dy = ay - my;
                var dist = Math.sqrt(dx*dx + dy*dy);
                for (var i = 0; i < rings.length; i++) {
                    var iconRadius = firstRadius + i * ringSpacing;
                    var bandHalf = ringSpacing / 2;
                    var innerR = (i === 0) ? 0 : (iconRadius - bandHalf);
                    var outerR = iconRadius + bandHalf;
                    if (dist >= innerR && dist < outerR) {
                        return i;
                    }
                }
                return -1;
            }

            function getAngle(mx, my) {
                var ax = rightHanded ? root.width : 0;
                var ay = root.height;
                var dx = mx - ax;
                var dy = ay - my;
                var angle = Math.atan2(dx, dy) * 180 / Math.PI;
                if (rightHanded) angle = -angle;
                return angle;
            }

            onPressed: {
                activeRing = getRingAt(mouse.x, mouse.y);
                console.log("Canvas pressed at " + mouse.x + "," + mouse.y + " -> ring " + activeRing);
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

            Repeater {
                model: ringItem.ringData.totalSlots

                Rectangle {
                    id: slotRect
                    property int slotIndex: index
                    property var slotData: ringItem.ringData.slots[index]
                    property real ringRadius: ringItem.ringData.radius
                    property real angleStep: ringItem.ringData.angleStep
                    property int totalSlots: ringItem.ringData.totalSlots

                    property real startAngleForRing: Math.asin(Math.min(1, edgeMargin / ringRadius)) * 180 / Math.PI
                    property real slotBaseAngle: slotIndex * angleStep + startAngleForRing

                    property real rawAngle: slotBaseAngle + ringItem.ringRotation
                    property real totalOrbit: totalSlots * angleStep

                    property real iconAngularSize: (iconSize / ringRadius) * 180 / Math.PI * 0.5
                    property real buffer: Math.min(15, iconAngularSize + 5)

                    property int minSlots: Math.ceil((90 + buffer * 2) / angleStep)
                    property int effectiveSlots: Math.max(totalSlots, minSlots)
                    property real effectiveOrbit: effectiveSlots * angleStep

                    property real displayAngle: {
                        var a = ((rawAngle % effectiveOrbit) + effectiveOrbit) % effectiveOrbit;
                        var exitAngle = 90 + buffer;
                        var entryAngle = buffer;
                        if (a <= exitAngle) return a;
                        if (a >= effectiveOrbit - entryAngle) return a - effectiveOrbit;
                        return -999;
                    }

                    property real angleRad: displayAngle * Math.PI / 180

                    visible: displayAngle >= -buffer && displayAngle <= 90 + buffer
                    opacity: {
                        if (displayAngle < 0) return Math.max(0, (displayAngle + buffer) / buffer);
                        if (displayAngle > 90) return Math.max(0, (90 + buffer - displayAngle) / buffer);
                        return 1;
                    }

                    x: rightHanded
                        ? anchorX - Math.sin(angleRad) * ringRadius - width/2
                        : anchorX + Math.sin(angleRad) * ringRadius - width/2
                    y: anchorY - Math.cos(angleRad) * ringRadius - height/2

                    width: iconSize
                    height: iconSize
                    radius: iconSize * 0.15
                    color: slotData.app ? "#2a2a3e" : "transparent"
                    border.color: slotData.app ? "#4a4a5e" : "#2a2a3e"
                    border.width: 2

                    // App icon - use full path from apps.json
                    Image {
                        id: appIcon
                        visible: slotData.app !== null
                        anchors.centerIn: parent
                        width: parent.width * 0.75
                        height: parent.height * 0.75
                        // Icon path is full path from apps.json (e.g., /home/user/Flick/icons/app.svg)
                        source: slotData.app && slotData.app.icon ? "file://" + slotData.app.icon : ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        asynchronous: true
                    }

                    // Fallback text if no icon or icon failed to load
                    Text {
                        anchors.centerIn: parent
                        visible: slotData.app && appIcon.status !== Image.Ready
                        text: slotData.app ? slotData.app.name.substring(0, 2).toUpperCase() : ""
                        color: "white"
                        font.pixelSize: iconSize * 0.35
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
                            // Convert local mouse coords to global screen coords
                            var globalPos = mapToItem(root, mx, my);
                            var ax = rightHanded ? root.width : 0;
                            var ay = root.height;
                            var dx = globalPos.x - ax;
                            var dy = ay - globalPos.y;
                            var angle = Math.atan2(dx, dy) * 180 / Math.PI;
                            if (rightHanded) angle = -angle;
                            return angle;
                        }

                        onPressed: {
                            startAngle = getAngle(mouse.x, mouse.y);
                            lastAngle = startAngle;
                            startRotation = ringItem.ringRotation;
                            lastTime = Date.now();
                            moved = false;
                            ringItem.isDragging = true;
                            ringItem.velocity = 0;
                            console.log("Icon pressed, startAngle=" + startAngle + " rotation=" + startRotation);
                        }

                        onPositionChanged: {
                            var currentAngle = getAngle(mouse.x, mouse.y);
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
                                launchApp(slotData.app.id, slotData.app.exec);
                            }
                        }
                    }
                }
            }
        }
    }
}
