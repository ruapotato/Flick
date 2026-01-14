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
    // Icons are 180px, spacing must be larger to prevent overlap
    property real iconSize: 180
    property real firstRadius: 300  // First ring further from corner
    property real ringSpacing: 250  // Distance between ring centers (spread orbits more)
    property real arcSpacing: 380   // Arc distance between icons (4 icons on outer rings instead of 5)

    // Handedness: false = left-handed (anchor bottom-left), true = right-handed (anchor bottom-right)
    property bool rightHanded: true

    // Anchor point based on handedness
    property real anchorX: rightHanded ? width : 0
    property real anchorY: height

    // Margin from edge for first column of icons
    property real edgeMargin: iconSize/2 + 20

    // Ring colors - bright rainbow starting from magenta (contrasts with dark purple background)
    property var ringColors: [
        {h: 0.92, s: 0.90, l: 0.55},  // Magenta/Pink (ring 0 - innermost)
        {h: 0.83, s: 0.85, l: 0.50},  // Purple
        {h: 0.65, s: 0.85, l: 0.50},  // Blue
        {h: 0.50, s: 0.85, l: 0.50},  // Cyan
        {h: 0.35, s: 0.85, l: 0.50},  // Green
        {h: 0.18, s: 0.90, l: 0.50},  // Orange
        {h: 0.08, s: 0.90, l: 0.50},  // Red-orange
        {h: 0.0,  s: 0.90, l: 0.50}   // Red (ring 7 - outermost)
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

    // Launch an app by writing exec command to signal file
    function launchApp(appId, execCmd) {
        console.log("Launching app:", appId, "exec:", execCmd);
        var signalPath = stateDir + "/launch_app";

        // Write using console output that wrapper script captures and writes to file
        // Format: FLICK_LAUNCH_APP:/path/to/file:exec_command
        console.log("FLICK_LAUNCH_APP:" + signalPath + ":" + execCmd);
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
        z: 100  // Draw on top of everything for debugging
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

            // Use canvas dimensions for anchor (should match root)
            var ax = rightHanded ? width : 0;
            var ay = height;
            console.log("Canvas size: " + width + "x" + height + ", root size: " + root.width + "x" + root.height);

            // Draw separator lines between orbits using same coordinate system as icons
            ctx.lineWidth = 3;

            console.log("Drawing lines, anchor=" + ax + "," + ay + ", rings=" + rings.length);

            // Use different colors to identify each line
            var colors = ["#ff0000", "#ff8800", "#ffff00", "#00ff00", "#00ffff", "#0088ff", "#8800ff", "#ff00ff"];

            // Draw lines AT each ring radius (through the icons) for debugging
            for (var i = 0; i < rings.length; i++) {
                var lineRadius = rings[i].radius;
                console.log("Ring " + i + " line at radius " + lineRadius + " color " + colors[i]);

                ctx.strokeStyle = colors[i];
                // Draw arc using same formula as icon positioning
                ctx.beginPath();
                var numSegments = 45;
                for (var j = 0; j <= numSegments; j++) {
                    var angle = (j / numSegments) * (Math.PI / 2);  // 0 to 90 degrees
                    var px, py;
                    if (rightHanded) {
                        px = ax - Math.sin(angle) * lineRadius;
                    } else {
                        px = ax + Math.sin(angle) * lineRadius;
                    }
                    py = ay - Math.cos(angle) * lineRadius;

                    if (j === 0) {
                        ctx.moveTo(px, py);
                    } else {
                        ctx.lineTo(px, py);
                    }
                }
                ctx.stroke();
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

                    // Normalized angle (wrapped to orbit range)
                    property real normalizedAngle: {
                        var a = ((rawAngle % effectiveOrbit) + effectiveOrbit) % effectiveOrbit;
                        return a;
                    }

                    // Display angle - where icon should render
                    property real displayAngle: {
                        var a = normalizedAngle;
                        var exitAngle = 90 + buffer;
                        var entryAngle = buffer;
                        // Visible range: -buffer to 90+buffer
                        if (a <= exitAngle) return a;
                        if (a >= effectiveOrbit - entryAngle) return a - effectiveOrbit;
                        return -999;  // Hidden zone
                    }

                    // For rendering, clamp hidden zone to edges during drag
                    property real renderAngle: {
                        if (displayAngle !== -999) return displayAngle;
                        if (!ringItem.isDragging) return displayAngle;
                        // During drag in hidden zone, clamp to nearest edge
                        var a = normalizedAngle;
                        var midHidden = (90 + buffer + effectiveOrbit - buffer) / 2;
                        return (a < midHidden) ? (90 + buffer) : (-buffer);
                    }
                    property real angleRad: (renderAngle === -999) ? 0 : (renderAngle * Math.PI / 180)

                    // Keep visible while dragging to prevent losing touch events
                    visible: ringItem.isDragging || (displayAngle >= -buffer && displayAngle <= 90 + buffer)
                    opacity: {
                        // During drag, keep full opacity
                        if (ringItem.isDragging) return 1;
                        // Fade at edges
                        var a = displayAngle;
                        if (a === -999) return 0;
                        if (a < 0) return Math.max(0, (a + buffer) / buffer);
                        if (a > 90) return Math.max(0, (90 + buffer - a) / buffer);
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
                        preventStealing: true  // Don't let parent steal touch events

                        // Store GLOBAL coordinates to avoid instability from icon movement
                        property real startGlobalX: 0
                        property real startGlobalY: 0
                        property real startRotation: 0
                        property real lastGlobalX: 0
                        property real lastGlobalY: 0
                        property real lastTime: 0
                        property bool moved: false

                        // Calculate angle from anchor point to a global position
                        function angleFromAnchor(gx, gy) {
                            var ax = anchorX;
                            var ay = anchorY;
                            var angle = Math.atan2(gx - ax, ay - gy) * 180 / Math.PI;
                            return rightHanded ? -angle : angle;
                        }

                        onPressed: {
                            // Convert to global immediately and store
                            var global = mapToItem(null, mouse.x, mouse.y);
                            startGlobalX = global.x;
                            startGlobalY = global.y;
                            lastGlobalX = global.x;
                            lastGlobalY = global.y;
                            startRotation = ringItem.ringRotation;
                            lastTime = Date.now();
                            moved = false;
                            ringItem.isDragging = true;
                            ringItem.velocity = 0;
                            console.log("TOUCH_DOWN ring=" + ringItem.ringData.ringIndex + " global=" + global.x.toFixed(0) + "," + global.y.toFixed(0));
                        }

                        onPositionChanged: {
                            // Convert current position to global
                            var global = mapToItem(null, mouse.x, mouse.y);

                            // Calculate angles directly from global positions
                            var startAngle = angleFromAnchor(startGlobalX, startGlobalY);
                            var lastAngle = angleFromAnchor(lastGlobalX, lastGlobalY);
                            var currentAngle = angleFromAnchor(global.x, global.y);

                            var delta = currentAngle - lastAngle;
                            var totalDelta = currentAngle - startAngle;

                            var now = Date.now();
                            var dt = Math.max(1, now - lastTime);

                            ringItem.velocity = delta / dt * 16;
                            ringItem.ringRotation = startRotation + totalDelta;

                            lastGlobalX = global.x;
                            lastGlobalY = global.y;
                            lastTime = now;

                            if (Math.abs(totalDelta) > 3) {
                                moved = true;
                            }
                        }

                        onReleased: {
                            console.log("TOUCH_UP ring=" + ringItem.ringData.ringIndex + " moved=" + moved + " app=" + (slotData.app ? slotData.app.id : "none"));
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
