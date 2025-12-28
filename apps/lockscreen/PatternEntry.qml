import QtQuick 2.15

Item {
    id: patternEntry
    width: 450
    height: 450

    property var selectedNodes: []
    property bool isDrawing: false
    property string errorMessage: ""
    property color accentColor: "#4a9eff"  // Can be set from parent

    // Grid sizing - larger dots, bigger spacing
    property real cellSize: 150
    property real dotSize: 70
    property real hitRadius: 60  // Generous hit detection

    signal patternComplete(var pattern)
    signal cancelled()

    // 3x3 grid of dots
    Repeater {
        model: 9

        Rectangle {
            id: dot
            property int nodeIndex: index
            property int row: Math.floor(index / 3)
            property int col: index % 3
            property bool selected: selectedNodes.indexOf(nodeIndex) !== -1

            x: col * cellSize + (cellSize - dotSize) / 2
            y: row * cellSize + (cellSize - dotSize) / 2
            width: dotSize
            height: dotSize
            radius: dotSize / 2
            color: selected ? accentColor : "#444455"
            border.color: selected ? Qt.lighter(accentColor, 1.2) : "#555566"
            border.width: 4

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 150 } }

            scale: selected ? 1.15 : 1.0
        }
    }

    // Lines connecting selected nodes
    Canvas {
        id: lineCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            if (selectedNodes.length < 2 && !isDrawing) return;

            ctx.strokeStyle = accentColor.toString();
            ctx.lineWidth = 8;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.beginPath();

            for (var i = 0; i < selectedNodes.length; i++) {
                var node = selectedNodes[i];
                var row = Math.floor(node / 3);
                var col = node % 3;
                var x = col * cellSize + cellSize / 2;
                var y = row * cellSize + cellSize / 2;

                if (i === 0) {
                    ctx.moveTo(x, y);
                } else {
                    ctx.lineTo(x, y);
                }
            }

            // Draw line to current touch position if drawing
            if (isDrawing && touchArea.lastX > 0) {
                ctx.lineTo(touchArea.lastX, touchArea.lastY);
            }

            ctx.stroke();
        }
    }

    MouseArea {
        id: touchArea
        anchors.fill: parent

        property real lastX: 0
        property real lastY: 0
        property real prevX: 0
        property real prevY: 0

        onPressed: {
            isDrawing = true;
            selectedNodes = [];
            errorMessage = "";
            lastX = mouse.x;
            lastY = mouse.y;
            prevX = mouse.x;
            prevY = mouse.y;
            checkNodeHit(mouse.x, mouse.y);
        }

        onPositionChanged: {
            if (!isDrawing) return;
            prevX = lastX;
            prevY = lastY;
            lastX = mouse.x;
            lastY = mouse.y;
            // Check line from prev to current position for intersections
            checkLineForNodes(prevX, prevY, lastX, lastY);
            lineCanvas.requestPaint();
        }

        onReleased: {
            isDrawing = false;
            lastX = 0;
            lastY = 0;
            lineCanvas.requestPaint();

            if (selectedNodes.length >= 4) {
                patternComplete(selectedNodes);
            } else if (selectedNodes.length > 0) {
                errorMessage = "Pattern too short (min 4 dots)";
                shakeAnimation.start();
            }
        }

        // Check if a point is near a node
        function checkNodeHit(x, y) {
            for (var i = 0; i < 9; i++) {
                var row = Math.floor(i / 3);
                var col = i % 3;
                var centerX = col * cellSize + cellSize / 2;
                var centerY = row * cellSize + cellSize / 2;
                var dist = Math.sqrt(Math.pow(x - centerX, 2) + Math.pow(y - centerY, 2));

                if (dist < hitRadius && selectedNodes.indexOf(i) === -1) {
                    selectedNodes.push(i);
                    selectedNodes = selectedNodes.slice(); // Trigger binding update
                    lineCanvas.requestPaint();
                }
            }
        }

        // Check a line segment for node intersections (fixes fast swipe skipping)
        function checkLineForNodes(x1, y1, x2, y2) {
            // Sample points along the line to catch fast swipes
            var dx = x2 - x1;
            var dy = y2 - y1;
            var dist = Math.sqrt(dx * dx + dy * dy);
            var steps = Math.max(1, Math.ceil(dist / 20)); // Check every 20 pixels

            for (var s = 0; s <= steps; s++) {
                var t = s / steps;
                var x = x1 + dx * t;
                var y = y1 + dy * t;
                checkNodeHit(x, y);
            }
        }
    }

    // Error message
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 20
        text: errorMessage
        font.pixelSize: 16
        color: accentColor
        visible: errorMessage !== ""
    }

    // Shake animation for wrong pattern
    SequentialAnimation {
        id: shakeAnimation
        PropertyAnimation { target: patternEntry; property: "x"; to: patternEntry.x - 20; duration: 50 }
        PropertyAnimation { target: patternEntry; property: "x"; to: patternEntry.x + 20; duration: 50 }
        PropertyAnimation { target: patternEntry; property: "x"; to: patternEntry.x - 15; duration: 50 }
        PropertyAnimation { target: patternEntry; property: "x"; to: patternEntry.x + 15; duration: 50 }
        PropertyAnimation { target: patternEntry; property: "x"; to: patternEntry.x; duration: 50 }
        ScriptAction { script: { selectedNodes = []; lineCanvas.requestPaint(); } }
    }

    // Clear pattern on error
    function showError(msg) {
        errorMessage = msg;
        shakeAnimation.start();
    }

    function clear() {
        selectedNodes = [];
        errorMessage = "";
        lineCanvas.requestPaint();
    }
}
