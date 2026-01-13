import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Flick Home"
    color: "#1a1a2e"

    // State directory for communication with compositor
    property string stateDir: {
        var dir = Qt.application.arguments.indexOf("--state-dir");
        if (dir >= 0 && dir + 1 < Qt.application.arguments.length) {
            return Qt.application.arguments[dir + 1];
        }
        // Default to standard location
        var home = "/home/droidian";
        if (!fileExists(home)) home = "/home/user";
        return home + "/.local/state/flick";
    }

    function fileExists(path) {
        var xhr = new XMLHttpRequest();
        xhr.open("HEAD", "file://" + path, false);
        try { xhr.send(); return xhr.status === 200 || xhr.status === 0; }
        catch (e) { return false; }
    }

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

    // Apps loaded from JSON
    property var apps: []

    Component.onCompleted: {
        console.log("Home screen started, stateDir:", stateDir);
        loadApps();
        loadConfig();
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
                apps = data.apps || [];
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

            var startAngle, endAngle;
            if (rightHanded) {
                startAngle = -Math.PI;
                endAngle = -Math.PI / 2;
            } else {
                startAngle = -Math.PI / 2;
                endAngle = 0;
            }

            for (var i = 0; i < rings.length; i++) {
                var innerR = (i === 0) ? 0 : (firstRadius + (i - 1) * ringSpacing + ringSpacing/2);
                var outerR = firstRadius + i * ringSpacing + ringSpacing/2;
                var color = getRingColor(i);

                ctx.beginPath();
                ctx.arc(anchorX, anchorY, outerR, startAngle, endAngle, false);
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
                    radius: 16
                    color: slotData.app ? "#2a2a3e" : "transparent"
                    border.color: slotData.app ? "#4a4a5e" : "#2a2a3e"
                    border.width: 1

                    // App icon
                    Image {
                        visible: slotData.app !== null
                        anchors.centerIn: parent
                        width: parent.width * 0.7
                        height: parent.height * 0.7
                        source: slotData.app ? "file:///home/droidian/Flick/shell/icons/" + slotData.app.icon + ".png" : ""
                        fillMode: Image.PreserveAspectFit

                        // Fallback text if no icon
                        Text {
                            anchors.centerIn: parent
                            visible: parent.status !== Image.Ready
                            text: slotData.app ? slotData.app.name.substring(0, 2).toUpperCase() : ""
                            color: "white"
                            font.pixelSize: 18
                            font.bold: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        property real startAngle: 0
                        property real startRotation: 0
                        property real lastAngle: 0
                        property real lastTime: 0
                        property bool moved: false

                        function getAngle(mx, my) {
                            var px = mx + slotRect.x + slotRect.width/2;
                            var py = my + slotRect.y + slotRect.height/2;
                            var dx = px - anchorX;
                            var dy = anchorY - py;
                            var angle = Math.atan2(dx, dy) * 180 / Math.PI;
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
                                launchApp(slotData.app.id, slotData.app.exec);
                            }
                        }
                    }
                }
            }
        }
    }
}
