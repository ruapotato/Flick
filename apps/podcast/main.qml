import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtMultimedia 5.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Podcasts"
    color: "#0a0a0f"

    property real textScale: 2.0
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property string configFile: "/home/droidian/.local/state/flick/podcasts.json"
    property string currentView: "library"  // library, episodes, player, add
    property int selectedPodcast: -1
    property bool isPlaying: false
    property string currentEpisodeTitle: ""
    property string currentPodcastName: ""

    ListModel { id: podcastsModel }
    ListModel { id: episodesModel }

    Component.onCompleted: {
        loadConfig()
        loadPodcasts()
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///home/droidian/.local/state/flick/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale) textScale = config.text_scale
            }
        } catch (e) {}
    }

    function loadPodcasts() {
        podcastsModel.clear()
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                for (var i = 0; i < data.podcasts.length; i++) {
                    podcastsModel.append(data.podcasts[i])
                }
            }
        } catch (e) {}
    }

    function savePodcasts() {
        var podcasts = []
        for (var i = 0; i < podcastsModel.count; i++) {
            podcasts.push(podcastsModel.get(i))
        }
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + configFile, false)
        try {
            xhr.send(JSON.stringify({podcasts: podcasts}, null, 2))
        } catch (e) {}
    }

    function addPodcast(url) {
        if (url.trim() === "") return

        // Fetch RSS feed
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    parseFeed(xhr.responseText, url)
                }
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function parseFeed(xml, feedUrl) {
        // Simple XML parsing for podcast RSS
        var titleMatch = xml.match(/<title>([^<]+)<\/title>/)
        var title = titleMatch ? titleMatch[1] : "Unknown Podcast"

        var descMatch = xml.match(/<description>([^<]+)<\/description>/)
        var desc = descMatch ? descMatch[1] : ""

        var imageMatch = xml.match(/<itunes:image[^>]*href="([^"]+)"/)
        var image = imageMatch ? imageMatch[1] : ""

        podcastsModel.append({
            title: title,
            description: desc.substring(0, 200),
            feedUrl: feedUrl,
            imageUrl: image
        })
        savePodcasts()
        currentView = "library"
    }

    function loadEpisodes(feedUrl, podcastTitle) {
        currentPodcastName = podcastTitle
        episodesModel.clear()

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    parseEpisodes(xhr.responseText)
                }
            }
        }
        xhr.open("GET", feedUrl)
        xhr.send()
    }

    function parseEpisodes(xml) {
        // Parse episodes from RSS
        var items = xml.split("<item>")
        for (var i = 1; i < items.length && i <= 50; i++) {
            var item = items[i]

            var titleMatch = item.match(/<title>([^<]+)<\/title>/)
            var title = titleMatch ? titleMatch[1].replace(/^<!\[CDATA\[|\]\]>$/g, "") : "Episode " + i

            var encMatch = item.match(/<enclosure[^>]*url="([^"]+)"/)
            var audioUrl = encMatch ? encMatch[1] : ""

            var dateMatch = item.match(/<pubDate>([^<]+)<\/pubDate>/)
            var pubDate = dateMatch ? formatPubDate(dateMatch[1]) : ""

            var durMatch = item.match(/<itunes:duration>([^<]+)<\/itunes:duration>/)
            var duration = durMatch ? durMatch[1] : ""

            if (audioUrl !== "") {
                episodesModel.append({
                    title: title,
                    audioUrl: audioUrl,
                    pubDate: pubDate,
                    duration: duration
                })
            }
        }
    }

    function formatPubDate(dateStr) {
        var date = new Date(dateStr)
        return Qt.formatDate(date, "MMM d, yyyy")
    }

    function playEpisode(url, title) {
        Haptic.click()
        currentEpisodeTitle = title
        mediaPlayer.source = url
        mediaPlayer.play()
        isPlaying = true
        currentView = "player"
    }

    function togglePlayPause() {
        Haptic.tap()
        if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
            mediaPlayer.pause()
            isPlaying = false
        } else {
            mediaPlayer.play()
            isPlaying = true
        }
    }

    function formatTime(ms) {
        var secs = Math.floor(ms / 1000)
        var mins = Math.floor(secs / 60)
        var hours = Math.floor(mins / 60)
        secs = secs % 60
        mins = mins % 60
        if (hours > 0) {
            return hours + ":" + (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs
        }
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    MediaPlayer {
        id: mediaPlayer
        onStatusChanged: {
            if (status === MediaPlayer.EndOfMedia) {
                isPlaying = false
            }
        }
    }

    // Library view
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "library"

        Column {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                width: parent.width
                height: 160
                color: "transparent"

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Podcasts"
                        font.pixelSize: 48 * textScale
                        font.weight: Font.ExtraLight
                        font.letterSpacing: 6
                        color: "#ffffff"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: podcastsModel.count + " SUBSCRIPTIONS"
                        font.pixelSize: 12 * textScale
                        font.weight: Font.Medium
                        font.letterSpacing: 3
                        color: "#555566"
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 20
                    anchors.topMargin: 60
                    width: 56
                    height: 56
                    radius: 28
                    color: addMouse.pressed ? accentPressed : accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: 32
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.click()
                            feedInput.text = ""
                            currentView = "add"
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.2; color: accentColor }
                        GradientStop { position: 0.8; color: accentColor }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    opacity: 0.3
                }
            }

            ListView {
                width: parent.width
                height: parent.height - 260
                spacing: 12
                clip: true
                anchors.margins: 16

                model: podcastsModel

                delegate: Rectangle {
                    width: parent.width - 32
                    x: 16
                    height: 120
                    radius: 16
                    color: podItemMouse.pressed ? "#1a1a2e" : "#15151f"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        Rectangle {
                            width: 88
                            height: 88
                            radius: 12
                            color: "#1a1a2e"

                            Text {
                                anchors.centerIn: parent
                                text: "🎙️"
                                font.pixelSize: 40
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 180
                            spacing: 8

                            Text {
                                text: model.title
                                font.pixelSize: 18 * textScale
                                font.weight: Font.Medium
                                color: "#ffffff"
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: model.description
                                font.pixelSize: 13 * textScale
                                color: "#888899"
                                elide: Text.ElideRight
                                width: parent.width
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 24
                            color: delPodMouse.pressed ? accentPressed : "#3a3a4e"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 18
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: delPodMouse
                                anchors.fill: parent
                                onClicked: {
                                    Haptic.tap()
                                    podcastsModel.remove(index)
                                    savePodcasts()
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: podItemMouse
                        anchors.fill: parent
                        anchors.rightMargin: 60
                        onClicked: {
                            Haptic.tap()
                            selectedPodcast = index
                            loadEpisodes(model.feedUrl, model.title)
                            currentView = "episodes"
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No podcasts yet\n\nTap + to add a podcast feed"
                    font.pixelSize: 18
                    color: "#555566"
                    horizontalAlignment: Text.AlignHCenter
                    visible: podcastsModel.count === 0
                }
            }
        }
    }

    // Episodes view
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "episodes"

        Column {
            anchors.fill: parent
            spacing: 16

            // Header
            Rectangle {
                width: parent.width
                height: 100
                color: "transparent"

                Row {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        width: 56
                        height: 56
                        radius: 28
                        color: backEpMouse.pressed ? "#333344" : "#222233"
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "←"
                            font.pixelSize: 28
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: backEpMouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                currentView = "library"
                            }
                        }
                    }

                    Text {
                        text: currentPodcastName
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Medium
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 80
                        elide: Text.ElideRight
                    }
                }
            }

            ListView {
                width: parent.width
                height: parent.height - 200
                spacing: 8
                clip: true

                model: episodesModel

                delegate: Rectangle {
                    width: parent.width - 32
                    x: 16
                    height: 100
                    radius: 12
                    color: epItemMouse.pressed ? "#1a1a2e" : "#15151f"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        Rectangle {
                            width: 56
                            height: 56
                            radius: 28
                            color: accentColor
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "▶"
                                font.pixelSize: 20
                                color: "#ffffff"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 90
                            spacing: 4

                            Text {
                                text: model.title
                                font.pixelSize: 16 * textScale
                                font.weight: Font.Medium
                                color: "#ffffff"
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: model.pubDate + (model.duration ? " • " + model.duration : "")
                                font.pixelSize: 12 * textScale
                                color: "#888899"
                            }
                        }
                    }

                    MouseArea {
                        id: epItemMouse
                        anchors.fill: parent
                        onClicked: playEpisode(model.audioUrl, model.title)
                    }
                }
            }
        }
    }

    // Player view
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "player"

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 32

            // Back button
            Rectangle {
                width: 56
                height: 56
                radius: 28
                color: backPlayerMouse.pressed ? "#333344" : "#222233"

                Text {
                    anchors.centerIn: parent
                    text: "←"
                    font.pixelSize: 28
                    color: "#ffffff"
                }

                MouseArea {
                    id: backPlayerMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        currentView = "episodes"
                    }
                }
            }

            Item { width: 1; height: 60 }

            // Album art placeholder
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300
                height: 300
                radius: 24
                color: "#1a1a2e"

                Text {
                    anchors.centerIn: parent
                    text: "🎙️"
                    font.pixelSize: 120
                }
            }

            // Episode info
            Column {
                width: parent.width
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: currentEpisodeTitle
                    font.pixelSize: 22 * textScale
                    font.weight: Font.Medium
                    color: "#ffffff"
                    width: parent.width
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: currentPodcastName
                    font.pixelSize: 16 * textScale
                    color: "#888899"
                }
            }

            // Progress
            Column {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 8
                    radius: 4
                    color: "#333344"

                    Rectangle {
                        width: mediaPlayer.duration > 0 ? parent.width * (mediaPlayer.position / mediaPlayer.duration) : 0
                        height: parent.height
                        radius: 4
                        color: accentColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -20
                        onClicked: {
                            var pos = mouse.x / parent.width
                            mediaPlayer.seek(pos * mediaPlayer.duration)
                        }
                    }
                }

                Row {
                    width: parent.width

                    Text {
                        text: formatTime(mediaPlayer.position)
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }

                    Item { width: parent.width - 160; height: 1 }

                    Text {
                        text: formatTime(mediaPlayer.duration)
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }
                }
            }

            // Controls
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 40

                Rectangle {
                    width: 64
                    height: 64
                    radius: 32
                    color: rew30Mouse.pressed ? "#333344" : "#222233"

                    Text {
                        anchors.centerIn: parent
                        text: "−30"
                        font.pixelSize: 16
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: rew30Mouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            mediaPlayer.seek(Math.max(0, mediaPlayer.position - 30000))
                        }
                    }
                }

                Rectangle {
                    width: 88
                    height: 88
                    radius: 44
                    color: playBtnMouse.pressed ? accentPressed : accentColor

                    Text {
                        anchors.centerIn: parent
                        text: isPlaying ? "⏸" : "▶"
                        font.pixelSize: 36
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: playBtnMouse
                        anchors.fill: parent
                        onClicked: togglePlayPause()
                    }
                }

                Rectangle {
                    width: 64
                    height: 64
                    radius: 32
                    color: fwd30Mouse.pressed ? "#333344" : "#222233"

                    Text {
                        anchors.centerIn: parent
                        text: "+30"
                        font.pixelSize: 16
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: fwd30Mouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            mediaPlayer.seek(Math.min(mediaPlayer.duration, mediaPlayer.position + 30000))
                        }
                    }
                }
            }
        }
    }

    // Add podcast view
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "add"

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 32

            Row {
                width: parent.width
                spacing: 16

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: cancelAddMouse.pressed ? "#333344" : "#222233"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: cancelAddMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            currentView = "library"
                        }
                    }
                }

                Text {
                    text: "Add Podcast"
                    font.pixelSize: 24 * textScale
                    font.weight: Font.Medium
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                text: "Enter podcast RSS feed URL"
                font.pixelSize: 16 * textScale
                color: "#888899"
            }

            Rectangle {
                width: parent.width
                height: 60
                radius: 12
                color: "#1a1a2e"

                TextInput {
                    id: feedInput
                    anchors.fill: parent
                    anchors.margins: 16
                    font.pixelSize: 18 * textScale
                    color: "#ffffff"
                    verticalAlignment: TextInput.AlignVCenter
                    inputMethodHints: Qt.ImhUrlCharactersOnly

                    Text {
                        anchors.fill: parent
                        text: "https://example.com/feed.xml"
                        font.pixelSize: 18 * textScale
                        color: "#555566"
                        visible: parent.text === ""
                    }
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 200
                height: 56
                radius: 28
                color: addFeedMouse.pressed ? "#1a7a3a" : "#228B22"

                Text {
                    anchors.centerIn: parent
                    text: "Subscribe"
                    font.pixelSize: 18 * textScale
                    color: "#ffffff"
                }

                MouseArea {
                    id: addFeedMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.click()
                        addPodcast(feedInput.text)
                    }
                }
            }
        }
    }

    // Back button (library only)
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 100
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? accentPressed : accentColor
        visible: currentView === "library"
        z: 10

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: { Haptic.tap(); Qt.quit() }
        }
    }

    // Home indicator
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 120
        height: 4
        radius: 2
        color: "#333344"
        visible: currentView === "library"
    }
}
