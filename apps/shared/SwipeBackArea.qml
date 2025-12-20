import QtQuick 2.15

// SwipeBackArea - Reusable component for swipe-right-to-go-back gesture
// Usage: Wrap your page content in this component
//
// Example:
//   SwipeBackArea {
//       onBack: stackView.pop()  // or Qt.quit() for main page
//
//       // Your page content here
//       Column { ... }
//   }

Item {
    id: swipeBack

    // Signal emitted when back gesture is triggered
    signal back()

    // Minimum swipe distance to trigger back (in pixels)
    property int swipeThreshold: 100

    // Edge margin - swipes starting within this margin from left edge are ignored
    // (those are for system gestures like quick settings)
    property int edgeMargin: 40

    // Visual feedback
    property bool showIndicator: true
    property color indicatorColor: "#e94560"

    // Internal state
    property real startX: 0
    property real startY: 0
    property bool swiping: false

    // Content goes here
    default property alias content: contentContainer.data

    // Content container
    Item {
        id: contentContainer
        anchors.fill: parent
    }

    // Back indicator arrow - only visible during valid swipe
    Rectangle {
        id: backIndicator
        anchors.left: parent.left
        anchors.leftMargin: -40
        anchors.verticalCenter: parent.verticalCenter
        width: 50
        height: 100
        radius: 8
        color: indicatorColor
        opacity: 0
        visible: showIndicator && swiping

        Text {
            anchors.centerIn: parent
            text: "‹"
            font.pixelSize: 48
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    // Gesture detection - thin strip on left side only
    MouseArea {
        id: gestureArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 60  // Only detect swipes starting from left 60px
        z: 1000

        property real dragDistance: 0

        onPressed: function(mouse) {
            // Ignore if too close to edge (system gesture area)
            if (mouse.x < swipeBack.edgeMargin) {
                mouse.accepted = false
                return
            }

            swipeBack.startX = mouse.x
            swipeBack.startY = mouse.y
            swipeBack.swiping = false
            dragDistance = 0
        }

        onPositionChanged: function(mouse) {
            var deltaX = mouse.x - swipeBack.startX
            var deltaY = Math.abs(mouse.y - swipeBack.startY)

            // Only track horizontal swipes (more horizontal than vertical)
            if (deltaX > 30 && deltaX > deltaY * 2) {
                swipeBack.swiping = true
                dragDistance = deltaX

                // Update indicator
                backIndicator.opacity = Math.min(0.9, deltaX / swipeBack.swipeThreshold)
                backIndicator.anchors.leftMargin = Math.min(10, deltaX / 10) - 40
            }
        }

        onReleased: function(mouse) {
            if (swipeBack.swiping && dragDistance >= swipeBack.swipeThreshold) {
                swipeBack.back()
            }

            swipeBack.swiping = false
            backIndicator.opacity = 0
            backIndicator.anchors.leftMargin = -40
        }

        onCanceled: {
            swipeBack.swiping = false
            backIndicator.opacity = 0
            backIndicator.anchors.leftMargin = -40
        }
    }
}
