import QtQuick 2.15

Item {
    id: patternEntry
    width: 300
    height: 300

    property var selectedNodes: []
    property bool isDrawing: false
    property string errorMessage: ""

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

            x: col * 100 + 25
            y: row * 100 + 25
            width: 50
            height: 50
            radius: 25
            color: selected ? "#4a9eff" : "#444455"
            border.color: selected ? "#6ab0ff" : "#555566"
            border.width: 3

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 150 } }

            scale: selected ? 1.2 : 1.0
        }
    }

    // Lines connecting selected nodes
    Canvas {
        id: lineCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            if (selectedNodes.length < 2) return;

            ctx.strokeStyle = "#4a9eff";
            ctx.lineWidth = 6;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.beginPath();

            for (var i = 0; i < selectedNodes.length; i++) {
                var node = selectedNodes[i];
                var row = Math.floor(node / 3);
                var col = node % 3;
                var x = col * 100 + 50;
                var y = row * 100 + 50;

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

        onPressed: {
            isDrawing = true;
            selectedNodes = [];
            errorMessage = "";
            lastX = mouse.x;
            lastY = mouse.y;
            checkNodeHit(mouse.x, mouse.y);
        }

        onPositionChanged: {
            if (!isDrawing) return;
            lastX = mouse.x;
            lastY = mouse.y;
            checkNodeHit(mouse.x, mouse.y);
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

        function checkNodeHit(x, y) {
            for (var i = 0; i < 9; i++) {
                var row = Math.floor(i / 3);
                var col = i % 3;
                var centerX = col * 100 + 50;
                var centerY = row * 100 + 50;
                var dist = Math.sqrt(Math.pow(x - centerX, 2) + Math.pow(y - centerY, 2));

                if (dist < 50 && selectedNodes.indexOf(i) === -1) {
                    selectedNodes.push(i);
                    selectedNodes = selectedNodes.slice(); // Trigger binding update
                    lineCanvas.requestPaint();
                    break;
                }
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
        color: "#e94560"
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
