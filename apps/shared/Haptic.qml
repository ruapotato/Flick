pragma Singleton
import QtQuick 2.15
import FlickBackend 1.0 as Backend

QtObject {
    // Proxy all functions to the backend Haptic singleton
    function tap() { Backend.Haptic.tap() }
    function click() { Backend.Haptic.click() }
    function heavy() { Backend.Haptic.heavy() }
    function vibrate(ms) { Backend.Haptic.vibrate(ms) }
    function pattern(durations) { Backend.Haptic.pattern(durations) }
    function success() { Backend.Haptic.success() }
    function error() { Backend.Haptic.error() }
}
