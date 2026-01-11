pragma Singleton
import QtQuick 2.15

QtObject {
    // Trigger a light tap haptic (for key presses, selections)
    function tap() {
        writeHaptic("tap");
    }

    // Trigger a medium click haptic (for confirms, toggles)
    function click() {
        writeHaptic("click");
    }

    // Trigger a heavy haptic (for important actions, errors)
    function heavy() {
        writeHaptic("heavy");
    }

    // Custom duration in milliseconds (max 100ms)
    function vibrate(ms) {
        writeHaptic(String(Math.min(ms, 100)));
    }

    // Internal function to trigger haptic - uses console.log for shell script to capture
    function writeHaptic(cmd) {
        console.log("HAPTIC:" + cmd);
    }
}
