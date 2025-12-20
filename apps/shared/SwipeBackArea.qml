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
    property int swipeThreshold: 80

    // Edge margin - swipes starting within this margin from left edge are ignored
    // (those are for system gestures like quick settings)
    property int edgeMargin: 30

    // Visual feedback
    property bool showIndicator: true
    property color indicatorColor: "#e94560"

    // Internal state
    property real startX: 0
    property real startY: 0
    property real currentX: 0
    property bool tracking: false
    property bool validSwipe: false

    // Content goes here
    default property alias content: contentContainer.data

    // Content container
    Item {
        id: contentContainer
        anchors.fill: parent

        // Slide effect during swipe
        transform: Translate {
            x: swipeBack.tracking && swipeBack.validSwipe ?
               Math.max(0, Math.min(swipeBack.currentX - swipeBack.startX, 100)) : 0

            Behavior on x {
                enabled: !swipeBack.tracking
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
        }
    }

    // Back indicator arrow
    Rectangle {
        id: backIndicator
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 50
        height: 100
        radius: 8
        color: indicatorColor
        opacity: 0
        visible: showIndicator

        // Arrow icon
        Text {
            anchors.centerIn: parent
            text: "‹"
            font.pixelSize: 48
            font.weight: Font.Light
            color: "#ffffff"
        }

        states: State {
            name: "visible"
            when: swipeBack.tracking && swipeBack.validSwipe &&
                  (swipeBack.currentX - swipeBack.startX) > swipeBack.swipeThreshold * 0.5
            PropertyChanges {
                target: backIndicator
                opacity: Math.min(0.9, (swipeBack.currentX - swipeBack.startX - swipeBack.swipeThreshold * 0.5) / swipeBack.swipeThreshold)
                x: Math.min(10, (swipeBack.currentX - swipeBack.startX - swipeBack.swipeThreshold * 0.5) / 4)
            }
        }

        Behavior on opacity { NumberAnimation { duration: 100 } }
        Behavior on x { NumberAnimation { duration: 100 } }
    }

    // Gesture detection
    MouseArea {
        id: gestureArea
        anchors.fill: parent

        // Pass through clicks to content below
        propagateComposedEvents: true

        onPressed: function(mouse) {
            // Ignore swipes from the left edge (system gesture area)
            if (mouse.x < swipeBack.edgeMargin) {
                mouse.accepted = false
                return
            }

            swipeBack.startX = mouse.x
            swipeBack.startY = mouse.y
            swipeBack.currentX = mouse.x
            swipeBack.tracking = true
            swipeBack.validSwipe = false

            // Don't consume the event yet - let content handle it
            mouse.accepted = false
        }

        onPositionChanged: function(mouse) {
            if (!swipeBack.tracking) return

            swipeBack.currentX = mouse.x

            var deltaX = mouse.x - swipeBack.startX
            var deltaY = Math.abs(mouse.y - swipeBack.startY)

            // Check if this is a valid horizontal swipe (more horizontal than vertical)
            if (deltaX > 20 && deltaX > deltaY * 1.5) {
                swipeBack.validSwipe = true
                mouse.accepted = true  // Now consume the event
            }
        }

        onReleased: function(mouse) {
            if (swipeBack.tracking && swipeBack.validSwipe) {
                var deltaX = mouse.x - swipeBack.startX

                if (deltaX >= swipeBack.swipeThreshold) {
                    // Trigger back action
                    swipeBack.back()
                }
            }

            swipeBack.tracking = false
            swipeBack.validSwipe = false
        }

        onCanceled: {
            swipeBack.tracking = false
            swipeBack.validSwipe = false
        }
    }
}
