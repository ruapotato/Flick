import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Flick Home"
    color: "#1a1a2e"
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint

    // Search/filter state
    property string searchText: ""
    property bool searchActive: searchText.length > 0

    // State directory - read from state_dir.txt written by run_home.sh
    property string stateDir: "/home/furios/.local/state/flick"

    // Base unit for proportional sizing (based on smaller screen dimension)
    // Use a reasonable default (480) until window is properly sized
    property real baseUnit: Math.max(480, Math.min(width, height))

    // Configuration - all sizes are proportional to screen size
    // This ensures the layout looks good at any resolution/scale factor
    property real iconSize: baseUnit * 0.18          // ~18% of screen width
    property real firstRadius: baseUnit * 0.30      // First ring distance from corner
    property real ringSpacing: baseUnit * 0.25      // Distance between ring centers
    property real arcSpacing: baseUnit * 0.38       // Arc distance between icons

    // Font sizes proportional to screen
    property real labelFontSize: baseUnit * 0.022   // App label font size
    property real searchFontSize: baseUnit * 0.05  // Search box font size
    property real searchIconSize: baseUnit * 0.055  // Search icon size

    // UI element sizes
    property real searchBoxHeight: baseUnit * 0.09  // Search box height
    property real searchBoxMargin: baseUnit * 0.06  // Top margin for search box
    property real arcDotSize: Math.max(2, baseUnit * 0.006)  // Arc separator dots

    // Handedness: false = left-handed (anchor bottom-left), true = right-handed (anchor bottom-right)
    property bool rightHanded: true

    // Anchor point based on handedness
    property real anchorX: rightHanded ? width : 0
    property real anchorY: height

    // Margin from edge for first column of icons
    property real edgeMargin: iconSize/2 + baseUnit * 0.03

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

    // Trigger haptic feedback (tap, click, or heavy)
    function haptic(type) {
        console.log("FLICK_HAPTIC:" + type);
    }

    // Check if an app matches the search text
    function appMatchesSearch(app) {
        if (!searchActive) return true;
        if (!app) return false;
        var search = searchText.toLowerCase();
        var name = app.name ? app.name.toLowerCase() : "";
        var id = app.id ? app.id.toLowerCase() : "";
        return name.indexOf(search) >= 0 || id.indexOf(search) >= 0;
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

    // Regenerate rings when screen size changes
    onWidthChanged: if (width > 0 && height > 0) rings = generateRings()
    onHeightChanged: if (width > 0 && height > 0) rings = generateRings()

    // Physics timer with gentle snap-to-grid and haptic feedback
    Timer {
        id: physicsTimer
        interval: 16
        repeat: true
        running: true
        onTriggered: {
            for (var i = 0; i < ringRepeater.count; i++) {
                var ring = ringRepeater.itemAt(i);
                if (!ring) continue;

                var angleStep = ring.ringData.angleStep;

                // Calculate current grid index for haptic feedback
                var gridIndex = Math.floor(ring.ringRotation / angleStep);
                if (gridIndex !== ring.lastGridIndex) {
                    // Ring crossed a grid boundary - trigger haptic
                    if (ring.isDragging || Math.abs(ring.velocity) > 0.5) {
                        haptic("tap");
                    }
                    ring.lastGridIndex = gridIndex;
                }

                if (!ring.isDragging) {
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

    // Draw separator arcs using Repeater with QML items
    // Uses the same positioning formula as icons for perfect alignment
    Repeater {
        id: arcRepeater
        model: rings.length

        Item {
            id: arcItem
            property real ringRadius: rings[index].radius

            // Draw arc as series of small dots
            Repeater {
                model: 45  // 45 dots for 90 degree arc

                Rectangle {
                    property real dotAngle: index * 2  // 0 to 90 degrees
                    property real angleRad: dotAngle * Math.PI / 180

                    x: rightHanded
                        ? anchorX - Math.sin(angleRad) * arcItem.ringRadius - arcDotSize/2
                        : anchorX + Math.sin(angleRad) * arcItem.ringRadius - arcDotSize/2
                    y: anchorY - Math.cos(angleRad) * arcItem.ringRadius - arcDotSize/2

                    width: arcDotSize
                    height: arcDotSize
                    radius: arcDotSize/2
                    color: "#4dffffff"
                    z: -1
                }
            }
        }
    }

    // Background touch handler for swipes between icons
    MouseArea {
        anchors.fill: parent
        z: -2  // Behind everything
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
            console.log("Background pressed at " + mouse.x + "," + mouse.y + " -> ring " + activeRing);
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
            property int lastGridIndex: 0  // Track grid position for haptic feedback

            Repeater {
                model: ringItem.ringData.totalSlots

                // Container for each slot - holds both primary and wrapped copies
                Item {
                    id: slotContainer
                    property int slotIndex: index
                    property var slotData: ringItem.ringData.slots[index]
                    property real ringRadius: ringItem.ringData.radius
                    property real angleStep: ringItem.ringData.angleStep
                    property int totalSlots: ringItem.ringData.totalSlots

                    // Small offset from edge so icons don't clip at 0 degrees
                    property real startAngleForRing: Math.asin(Math.min(1, edgeMargin / ringRadius)) * 180 / Math.PI
                    property real slotBaseAngle: slotIndex * angleStep + startAngleForRing

                    property real rawAngle: slotBaseAngle + ringItem.ringRotation

                    // Calculate the visible angle range for THIS ring based on screen size
                    // At angle A: y = height - cos(A)*radius, x = width - sin(A)*radius (right-handed)
                    // Icon visible when: y > -iconSize/2 and x > -iconSize/2
                    property real minVisibleAngle: {
                        // Min angle where icon y > -iconSize/2
                        // height - cos(A)*radius > -iconSize/2
                        // cos(A) < (height + iconSize/2) / radius
                        var cosLimit = (root.height + iconSize/2) / ringRadius;
                        if (cosLimit >= 1) return 0;
                        if (cosLimit <= -1) return 90; // Can't see this ring at all at low angles
                        return Math.acos(Math.min(1, cosLimit)) * 180 / Math.PI;
                    }
                    property real maxVisibleAngle: {
                        // Max angle where icon x > -iconSize/2 (right-handed)
                        // width - sin(A)*radius > -iconSize/2
                        // sin(A) < (width + iconSize/2) / radius
                        var sinLimit = (root.width + iconSize/2) / ringRadius;
                        if (sinLimit >= 1) return 90;
                        if (sinLimit <= 0) return 0; // Can't see this ring at high angles
                        return Math.asin(Math.min(1, sinLimit)) * 180 / Math.PI;
                    }
                    property real visibleRange: Math.max(1, maxVisibleAngle - minVisibleAngle)

                    // Count apps in this ring
                    property int appsInRing: {
                        var count = 0;
                        for (var i = 0; i < ringItem.ringData.slots.length; i++) {
                            if (ringItem.ringData.slots[i].app) count++;
                        }
                        return count;
                    }

                    // Wrap angle based on ring type:
                    // - Single icon rings: wrap to visible range (always visible)
                    // - Multi icon rings: wrap to 90°, allow off-screen
                    property real displayAngle: {
                        if (appsInRing <= 1) {
                            // Single icon: always keep visible
                            var a = rawAngle - minVisibleAngle;
                            a = ((a % visibleRange) + visibleRange) % visibleRange;
                            return a + minVisibleAngle;
                        } else {
                            // Multiple icons: use full 90° range
                            var a = ((rawAngle % 90) + 90) % 90;
                            return a;
                        }
                    }
                    property real angleRad: displayAngle * Math.PI / 180

                    // Calculate pixel position
                    property real iconX: rightHanded
                        ? anchorX - Math.sin(angleRad) * ringRadius - iconSize/2
                        : anchorX + Math.sin(angleRad) * ringRadius - iconSize/2
                    property real iconY: anchorY - Math.cos(angleRad) * ringRadius - iconSize/2

                    // Is icon on screen?
                    property bool onScreen: iconX > -iconSize && iconX < root.width && iconY > -iconSize && iconY < root.height

                    // Edge wrapping: show copy when near edge
                    // For single-icon rings: use visible range edges
                    // For multi-icon rings: use 0° and 90° edges
                    property real edgeBuffer: 15
                    property real effectiveMinEdge: appsInRing <= 1 ? minVisibleAngle : 0
                    property real effectiveMaxEdge: appsInRing <= 1 ? maxVisibleAngle : 90
                    property bool nearMinEdge: displayAngle < effectiveMinEdge + edgeBuffer
                    property bool nearMaxEdge: displayAngle > effectiveMaxEdge - edgeBuffer

                    // Wrapped positions for edge copies
                    // Use 90° for multi-icon rings, visibleRange for single-icon rings
                    property real wrapOffset: appsInRing <= 1 ? visibleRange : 90
                    property real wrapMinAngle: displayAngle + wrapOffset  // Copy at max edge when near min
                    property real wrapMaxAngle: displayAngle - wrapOffset  // Copy at min edge when near max

                    // Render primary and edge wrap copies
                    Repeater {
                        model: slotContainer.slotData.app ? 3 : 0  // Primary + 2 edge copies

                        Rectangle {
                            id: iconRect
                            property bool isPrimary: index === 0
                            property bool isMinEdgeCopy: index === 1  // Shows at max when primary near min
                            property bool isMaxEdgeCopy: index === 2  // Shows at min when primary near max

                            // Calculate position for each copy
                            property real myAngle: isPrimary ? slotContainer.displayAngle :
                                                   isMinEdgeCopy ? slotContainer.wrapMinAngle :
                                                   slotContainer.wrapMaxAngle
                            property real myRad: myAngle * Math.PI / 180
                            property real myX: rightHanded
                                ? anchorX - Math.sin(myRad) * slotContainer.ringRadius - iconSize/2
                                : anchorX + Math.sin(myRad) * slotContainer.ringRadius - iconSize/2
                            property real myY: anchorY - Math.cos(myRad) * slotContainer.ringRadius - iconSize/2

                            x: myX
                            y: myY

                            // Visibility logic - includes search filtering
                            property bool myOnScreen: myX > -iconSize && myX < root.width && myY > -iconSize && myY < root.height
                            property bool matchesSearch: appMatchesSearch(slotContainer.slotData.app)
                            visible: matchesSearch && (
                                     (isPrimary && myOnScreen) ||
                                     (isMinEdgeCopy && slotContainer.nearMinEdge && myOnScreen) ||
                                     (isMaxEdgeCopy && slotContainer.nearMaxEdge && myOnScreen)
                            )

                            opacity: 1

                            width: iconSize
                            height: iconSize
                            radius: iconSize * 0.15
                            color: "#2a2a3e"
                            border.color: "#4a4a5e"
                            border.width: Math.max(1, baseUnit * 0.004)

                            // App icon
                            Image {
                                id: appIcon
                                anchors.centerIn: parent
                                width: parent.width * 0.75
                                height: parent.height * 0.75
                                source: slotContainer.slotData.app && slotContainer.slotData.app.icon ? "file://" + slotContainer.slotData.app.icon : ""
                                fillMode: Image.PreserveAspectFit
                                sourceSize.width: width * 2
                                sourceSize.height: height * 2
                                asynchronous: true
                            }

                            // Fallback text
                            Text {
                                anchors.centerIn: parent
                                visible: appIcon.status !== Image.Ready
                                text: slotContainer.slotData.app ? slotContainer.slotData.app.name.substring(0, 2).toUpperCase() : ""
                                color: "white"
                                font.pixelSize: iconSize * 0.35
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                preventStealing: true
                                enabled: parent.visible

                                property real startGlobalX: 0
                                property real startGlobalY: 0
                                property real startRotation: 0
                                property real lastGlobalX: 0
                                property real lastGlobalY: 0
                                property real lastTime: 0
                                property bool moved: false

                                function angleFromAnchor(gx, gy) {
                                    var ax = anchorX;
                                    var ay = anchorY;
                                    var angle = Math.atan2(gx - ax, ay - gy) * 180 / Math.PI;
                                    return rightHanded ? -angle : angle;
                                }

                                onPressed: {
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
                                }

                                onPositionChanged: {
                                    var global = mapToItem(null, mouse.x, mouse.y);
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
                                    ringItem.isDragging = false;
                                    if (!moved && slotContainer.slotData.app) {
                                        launchApp(slotContainer.slotData.app.id, slotContainer.slotData.app.exec);
                                    }
                                }
                            }

                            // App name label below icon
                            Text {
                                anchors.top: parent.bottom
                                anchors.topMargin: baseUnit * 0.008
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: slotContainer.slotData.app ? slotContainer.slotData.app.name : ""
                                color: "white"
                                font.pixelSize: labelFontSize
                                width: iconSize + baseUnit * 0.02
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                opacity: 0.9
                            }
                        }
                    }
                }
            }
        }
    }

    // Search box at top of screen
    Rectangle {
        id: searchBox
        anchors.top: parent.top
        anchors.topMargin: searchBoxMargin
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.92
        height: searchBoxHeight
        radius: searchBoxHeight / 2
        color: searchInput.activeFocus ? "#3a3a4e" : "#2a2a3e"
        border.color: searchInput.activeFocus ? "#6a6aff" : "#4a4a5e"
        border.width: Math.max(2, baseUnit * 0.005)
        opacity: searchInput.activeFocus || searchActive ? 1.0 : 0.7

        // Search icon
        Text {
            anchors.left: parent.left
            anchors.leftMargin: baseUnit * 0.04
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{1F50D}" // magnifying glass emoji
            font.pixelSize: searchIconSize
            color: "#888"
        }

        // Text input
        TextInput {
            id: searchInput
            anchors.left: parent.left
            anchors.leftMargin: baseUnit * 0.12
            anchors.right: clearButton.left
            anchors.rightMargin: baseUnit * 0.025
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: searchFontSize
            clip: true
            onTextChanged: {
                root.searchText = text;
            }
            onActiveFocusChanged: {
                // Request keyboard show/hide from compositor
                console.log("Search focus changed:", activeFocus);
                if (activeFocus) {
                    console.log("FLICK_KEYBOARD:show");
                    haptic("tap");
                } else {
                    console.log("FLICK_KEYBOARD:hide");
                }
            }

            // Placeholder text
            Text {
                anchors.fill: parent
                anchors.verticalCenter: parent.verticalCenter
                text: "Search apps..."
                color: "#666"
                font.pixelSize: searchFontSize
                visible: !searchInput.text && !searchInput.activeFocus
            }
        }

        // Clear button
        Rectangle {
            id: clearButton
            property real buttonSize: searchBoxHeight * 0.6
            anchors.right: parent.right
            anchors.rightMargin: baseUnit * 0.03
            anchors.verticalCenter: parent.verticalCenter
            width: buttonSize
            height: buttonSize
            radius: buttonSize / 2
            color: clearMouseArea.pressed ? "#4a4a5e" : "transparent"
            visible: searchActive
            z: 10  // Above the search box mouse area

            Text {
                anchors.centerIn: parent
                text: "\u{2715}" // X symbol
                color: "#888"
                font.pixelSize: searchFontSize * 0.9
            }

            MouseArea {
                id: clearMouseArea
                anchors.fill: parent
                onClicked: {
                    searchInput.text = "";
                    searchInput.focus = false;
                    console.log("FLICK_KEYBOARD:hide");
                }
            }
        }

        // Make entire search box tappable to focus input
        MouseArea {
            anchors.fill: parent
            z: -1  // Behind text input
            onClicked: {
                console.log("Search box tapped - focusing input");
                searchInput.forceActiveFocus();
                console.log("FLICK_KEYBOARD:show");
                haptic("tap");
            }
        }
    }
}
