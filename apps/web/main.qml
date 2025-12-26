import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtWebEngine 1.10
import "../shared"

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    width: 1080
    height: 2400
    title: "Web"
    color: "#0a0a0f"

    // Display config
    property real textScale: 1.0

    // Browser state
    property string currentView: "browser" // "browser", "tabs", "bookmarks", "history", "downloads", "menu"
    property string homepage: "https://start.duckduckgo.com"
    property string searchEngine: "https://duckduckgo.com/?q="

    // Tab management
    property var tabs: []
    property int currentTabIndex: 0
    property int tabIdCounter: 0

    // Data
    property var bookmarksList: []
    property var historyList: []
    property var downloadsList: []

    // File paths
    property string stateDir: "/home/droidian/.local/state/flick"
    property string bookmarksFile: stateDir + "/browser_bookmarks.json"
    property string historyFile: stateDir + "/browser_history.json"
    property string downloadsFile: stateDir + "/browser_downloads.json"
    property string settingsFile: stateDir + "/browser_settings.json"

    Component.onCompleted: {
        loadConfig()
        loadBookmarks()
        loadHistory()
        loadDownloads()
        loadSettings()
        // Create initial tab
        createTab(homepage)
    }

    // ==================== Data Functions ====================

    function loadConfig() {
        var configPath = stateDir + "/display_config.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale !== undefined) {
                    textScale = config.text_scale
                }
            }
        } catch (e) {
            console.log("Using default text scale")
        }
    }

    function loadSettings() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + settingsFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                homepage = data.homepage || homepage
                searchEngine = data.searchEngine || searchEngine
            }
        } catch (e) {}
    }

    function saveSettings() {
        var data = { homepage: homepage, searchEngine: searchEngine }
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + settingsFile)
        xhr.send(JSON.stringify(data, null, 2))
    }

    function loadBookmarks() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + bookmarksFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                bookmarksList = data.bookmarks || []
            }
        } catch (e) { bookmarksList = [] }
    }

    function saveBookmarks() {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + bookmarksFile)
        xhr.send(JSON.stringify({bookmarks: bookmarksList}, null, 2))
    }

    function addBookmark(title, url) {
        var bookmark = {
            id: Date.now().toString(),
            title: title || url,
            url: url,
            createdAt: Date.now()
        }
        bookmarksList.unshift(bookmark)
        bookmarksListChanged()
        saveBookmarks()
        Haptic.click()
    }

    function removeBookmark(id) {
        for (var i = 0; i < bookmarksList.length; i++) {
            if (bookmarksList[i].id === id) {
                bookmarksList.splice(i, 1)
                bookmarksListChanged()
                saveBookmarks()
                return
            }
        }
    }

    function isBookmarked(url) {
        for (var i = 0; i < bookmarksList.length; i++) {
            if (bookmarksList[i].url === url) return true
        }
        return false
    }

    function loadHistory() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + historyFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                historyList = data.entries || []
            }
        } catch (e) { historyList = [] }
    }

    function saveHistory() {
        // Keep last 500 entries
        if (historyList.length > 500) {
            historyList = historyList.slice(0, 500)
        }
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + historyFile)
        xhr.send(JSON.stringify({entries: historyList}, null, 2))
    }

    function addToHistory(title, url) {
        // Don't add empty or about: urls
        if (!url || url.indexOf("about:") === 0) return

        var entry = {
            id: Date.now().toString(),
            title: title || url,
            url: url,
            visitedAt: Date.now()
        }
        historyList.unshift(entry)
        historyListChanged()
        saveHistory()
    }

    function clearHistory() {
        historyList = []
        historyListChanged()
        saveHistory()
    }

    function loadDownloads() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + downloadsFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                downloadsList = data.downloads || []
            }
        } catch (e) { downloadsList = [] }
    }

    function saveDownloads() {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + downloadsFile)
        xhr.send(JSON.stringify({downloads: downloadsList}, null, 2))
    }

    // ==================== Tab Management ====================

    function createTab(url) {
        var tab = {
            id: tabIdCounter++,
            url: url || homepage,
            title: "New Tab",
            loading: false,
            progress: 0,
            canGoBack: false,
            canGoForward: false
        }
        tabs.push(tab)
        currentTabIndex = tabs.length - 1
        tabsChanged()
    }

    function closeTab(index) {
        if (tabs.length === 1) {
            // Reset the only tab to homepage
            tabs[0].url = homepage
            tabs[0].title = "New Tab"
            tabsChanged()
        } else {
            tabs.splice(index, 1)
            if (currentTabIndex >= tabs.length) {
                currentTabIndex = tabs.length - 1
            }
            tabsChanged()
        }
        Haptic.tap()
    }

    function switchTab(index) {
        if (index >= 0 && index < tabs.length) {
            currentTabIndex = index
            currentView = "browser"
            Haptic.tap()
        }
    }

    function getCurrentTab() {
        if (tabs.length > 0 && currentTabIndex < tabs.length) {
            return tabs[currentTabIndex]
        }
        return null
    }

    function navigateTo(urlOrSearch) {
        var url = urlOrSearch.trim()
        if (!url) return

        // Check if it's a URL or search query
        if (url.indexOf("://") === -1 && url.indexOf(".") === -1) {
            // Treat as search query
            url = searchEngine + encodeURIComponent(url)
        } else if (url.indexOf("://") === -1) {
            // Add https://
            url = "https://" + url
        }

        if (tabs.length > 0 && currentTabIndex < tabs.length) {
            tabs[currentTabIndex].url = url
            tabsChanged()
        }
    }

    // ==================== Config Timer ====================

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    // ==================== WebEngine Profile ====================

    WebEngineProfile {
        id: webProfile
        storageName: "FlickBrowser"
        offTheRecord: false
        httpCacheType: WebEngineProfile.DiskHttpCache
        persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
        httpUserAgent: "Mozilla/5.0 (Linux; Android 11; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

        onDownloadRequested: function(download) {
            var filename = download.downloadFileName
            var downloadPath = "/home/droidian/Downloads/" + filename

            download.downloadDirectory = "/home/droidian/Downloads"
            download.accept()

            var dlEntry = {
                id: Date.now().toString(),
                filename: filename,
                url: download.url.toString(),
                localPath: downloadPath,
                progress: 0,
                status: "downloading",
                startedAt: Date.now()
            }
            downloadsList.unshift(dlEntry)
            downloadsListChanged()
            saveDownloads()

            Haptic.click()
        }
    }

    // ==================== Main Browser View ====================

    Item {
        id: browserView
        anchors.fill: parent
        visible: currentView === "browser"

        // Address Bar
        Rectangle {
            id: addressBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 72
            color: "#1a1a2e"
            z: 10

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                // URL Input
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: "#2a2a3e"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        // Security indicator
                        Text {
                            text: {
                                var tab = getCurrentTab()
                                if (tab && tab.url && tab.url.indexOf("https://") === 0) {
                                    return "🔒"
                                }
                                return "🌐"
                            }
                            font.pixelSize: 20
                            color: "#888888"
                        }

                        TextInput {
                            id: urlInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                            selectByMouse: true
                            clip: true

                            property bool editing: false

                            text: {
                                if (editing) return text
                                var tab = getCurrentTab()
                                return tab ? tab.url : ""
                            }

                            onFocusChanged: {
                                if (focus) {
                                    editing = true
                                    selectAll()
                                } else {
                                    editing = false
                                }
                            }

                            onAccepted: {
                                navigateTo(text)
                                focus = false
                                Haptic.tap()
                            }

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                verticalAlignment: Text.AlignVCenter
                                text: "Search or enter URL"
                                color: "#666666"
                                font.pixelSize: 16 * textScale
                                visible: !parent.text && !parent.focus
                            }
                        }

                        // Clear/Reload button
                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: clearMouse.pressed ? "#3a3a4e" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    var tab = getCurrentTab()
                                    if (urlInput.focus) return "✕"
                                    if (tab && tab.loading) return "✕"
                                    return "↻"
                                }
                                font.pixelSize: 20
                                color: "#aaaaaa"
                            }

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                onClicked: {
                                    Haptic.tap()
                                    if (urlInput.focus) {
                                        urlInput.text = ""
                                    } else {
                                        var tab = getCurrentTab()
                                        if (tab && tab.loading) {
                                            tabStack.currentItem.stop()
                                        } else {
                                            tabStack.currentItem.reload()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Tab Bar
        Rectangle {
            id: tabBar
            anchors.top: addressBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: tabs.length > 1 ? 56 : 0
            color: "#0a0a0f"
            visible: tabs.length > 1
            z: 5

            Behavior on height { NumberAnimation { duration: 200 } }

            ListView {
                id: tabListView
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 56
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                model: tabs.length

                delegate: Rectangle {
                    width: 180
                    height: 48
                    radius: 8
                    color: index === currentTabIndex ? "#2a2a3e" : "#1a1a2e"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: tabs[index] ? tabs[index].title : ""
                            color: "#ffffff"
                            font.pixelSize: 13 * textScale
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: closeTabMouse.pressed ? "#e94560" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: "#888888"
                                font.pixelSize: 14
                            }

                            MouseArea {
                                id: closeTabMouse
                                anchors.fill: parent
                                onClicked: closeTab(index)
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 32
                        onClicked: switchTab(index)
                    }
                }
            }

            // New tab button
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44
                radius: 22
                color: newTabMouse.pressed ? "#3a3a4e" : "#2a2a3e"

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: "#e94560"
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: newTabMouse
                    anchors.fill: parent
                    onClicked: {
                        createTab(homepage)
                        Haptic.tap()
                    }
                }
            }
        }

        // Loading progress bar
        Rectangle {
            anchors.top: tabBar.visible ? tabBar.bottom : addressBar.bottom
            anchors.left: parent.left
            width: {
                var tab = getCurrentTab()
                return parent.width * ((tab ? tab.progress : 0) / 100)
            }
            height: 3
            color: "#e94560"
            visible: {
                var tab = getCurrentTab()
                return tab && tab.loading
            }
            z: 5

            Behavior on width { NumberAnimation { duration: 100 } }
        }

        // Web content area - StackLayout for tabs
        StackLayout {
            id: tabStack
            anchors.top: tabBar.visible ? tabBar.bottom : addressBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: bottomToolbar.top
            currentIndex: currentTabIndex

            Repeater {
                model: tabs.length

                WebEngineView {
                    id: webView
                    profile: webProfile

                    Component.onCompleted: {
                        if (tabs[index]) {
                            url = tabs[index].url
                        }
                    }

                    Connections {
                        target: root
                        function onTabsChanged() {
                            if (tabs[index] && webView.url.toString() !== tabs[index].url) {
                                webView.url = tabs[index].url
                            }
                        }
                    }

                    onUrlChanged: {
                        if (tabs[index]) {
                            tabs[index].url = url.toString()
                        }
                    }

                    onTitleChanged: {
                        if (tabs[index]) {
                            tabs[index].title = title || "Untitled"
                            tabsChanged()
                        }
                    }

                    onLoadingChanged: function(loadRequest) {
                        if (tabs[index]) {
                            tabs[index].loading = loading
                            tabs[index].canGoBack = canGoBack
                            tabs[index].canGoForward = canGoForward
                            tabsChanged()

                            if (loadRequest.status === WebEngineLoadRequest.LoadSucceededStatus) {
                                addToHistory(title, url.toString())
                            }
                        }
                    }

                    onLoadProgressChanged: {
                        if (tabs[index]) {
                            tabs[index].progress = loadProgress
                        }
                    }

                    onNewViewRequested: function(request) {
                        createTab(request.requestedUrl.toString())
                    }

                    settings.pluginsEnabled: false
                    settings.fullScreenSupportEnabled: true
                    settings.autoLoadImages: true
                    settings.javascriptEnabled: true
                    settings.localContentCanAccessRemoteUrls: true
                }
            }
        }

        // Bottom Toolbar
        Rectangle {
            id: bottomToolbar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a1a2e"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 8
                anchors.bottomMargin: 36

                // Back
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    radius: 28
                    color: backMouse.pressed ? "#3a3a4e" : "transparent"
                    opacity: {
                        var tab = getCurrentTab()
                        return (tab && tab.canGoBack) ? 1.0 : 0.4
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        font.pixelSize: 28
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        onClicked: {
                            var tab = getCurrentTab()
                            if (tab && tab.canGoBack) {
                                tabStack.currentItem.goBack()
                                Haptic.tap()
                            }
                        }
                    }
                }

                // Forward
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    radius: 28
                    color: fwdMouse.pressed ? "#3a3a4e" : "transparent"
                    opacity: {
                        var tab = getCurrentTab()
                        return (tab && tab.canGoForward) ? 1.0 : 0.4
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "→"
                        font.pixelSize: 28
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: fwdMouse
                        anchors.fill: parent
                        onClicked: {
                            var tab = getCurrentTab()
                            if (tab && tab.canGoForward) {
                                tabStack.currentItem.goForward()
                                Haptic.tap()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Tabs count
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    radius: 8
                    color: tabsMouse.pressed ? "#3a3a4e" : "#2a2a3e"
                    border.color: "#e94560"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: tabs.length.toString()
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: tabsMouse
                        anchors.fill: parent
                        onClicked: {
                            currentView = "tabs"
                            Haptic.tap()
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Bookmark toggle
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    radius: 28
                    color: bookmarkMouse.pressed ? "#3a3a4e" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: {
                            var tab = getCurrentTab()
                            return isBookmarked(tab ? tab.url : "") ? "★" : "☆"
                        }
                        font.pixelSize: 28
                        color: "#e94560"
                    }

                    MouseArea {
                        id: bookmarkMouse
                        anchors.fill: parent
                        onClicked: {
                            var tab = getCurrentTab()
                            if (tab) {
                                if (isBookmarked(tab.url)) {
                                    // Find and remove
                                    for (var i = 0; i < bookmarksList.length; i++) {
                                        if (bookmarksList[i].url === tab.url) {
                                            removeBookmark(bookmarksList[i].id)
                                            break
                                        }
                                    }
                                } else {
                                    addBookmark(tab.title, tab.url)
                                }
                            }
                        }
                    }
                }

                // Menu
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    radius: 28
                    color: menuMouse.pressed ? "#3a3a4e" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "⋮"
                        font.pixelSize: 28
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: menuMouse
                        anchors.fill: parent
                        onClicked: {
                            currentView = "menu"
                            Haptic.tap()
                        }
                    }
                }
            }

            // Home indicator
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 200
                height: 6
                radius: 3
                color: "#444466"
            }
        }
    }

    // ==================== Tabs View ====================

    Rectangle {
        id: tabsView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "tabs"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                Text {
                    anchors.centerIn: parent
                    text: "Tabs (" + tabs.length + ")"
                    color: "#ffffff"
                    font.pixelSize: 24 * textScale
                    font.weight: Font.Bold
                }
            }

            // Tab grid
            GridView {
                width: parent.width
                height: parent.height - 180
                cellWidth: width / 2
                cellHeight: 200
                model: tabs.length
                clip: true

                delegate: Item {
                    width: parent.width / 2
                    height: 200

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 8
                        color: index === currentTabIndex ? "#2a2a3e" : "#1a1a2e"
                        radius: 12

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Text {
                            width: parent.width
                            text: tabs[index] ? tabs[index].title : ""
                            color: "#ffffff"
                            font.pixelSize: 14 * textScale
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }

                        Text {
                            width: parent.width
                            text: {
                                var tab = tabs[index]
                                if (!tab) return ""
                                try {
                                    var url = new URL(tab.url)
                                    return url.hostname
                                } catch(e) { return tab.url }
                            }
                            color: "#888888"
                            font.pixelSize: 12 * textScale
                            elide: Text.ElideRight
                        }
                    }

                    // Close button
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        width: 32
                        height: 32
                        radius: 16
                        color: "#e94560"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: "#ffffff"
                            font.pixelSize: 16
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: closeTab(index)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: 40
                        onClicked: switchTab(index)
                    }
                    }
                }
            }

            // New tab button
            Rectangle {
                width: parent.width - 32
                height: 56
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 28
                color: "#e94560"

                Text {
                    anchors.centerIn: parent
                    text: "+ New Tab"
                    color: "#ffffff"
                    font.pixelSize: 18 * textScale
                    font.weight: Font.Bold
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        createTab(homepage)
                        currentView = "browser"
                        Haptic.click()
                    }
                }
            }
        }

        // Back button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 72
            height: 72
            radius: 36
            color: "#e94560"

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 32
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    currentView = "browser"
                    Haptic.tap()
                }
            }
        }
    }

    // ==================== Menu View ====================

    Rectangle {
        id: menuView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "menu"

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            // Header
            Rectangle {
                width: parent.width
                height: 64
                color: "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Menu"
                    color: "#ffffff"
                    font.pixelSize: 28 * textScale
                    font.weight: Font.Bold
                }
            }

            // Menu items
            Repeater {
                model: [
                    { icon: "★", label: "Bookmarks", view: "bookmarks" },
                    { icon: "🕐", label: "History", view: "history" },
                    { icon: "↓", label: "Downloads", view: "downloads" },
                    { icon: "🏠", label: "Set as Homepage", action: "setHomepage" },
                    { icon: "🔄", label: "Reload", action: "reload" },
                    { icon: "⊕", label: "Desktop Site", action: "desktop" }
                ]

                Rectangle {
                    width: parent.width
                    height: 64
                    radius: 12
                    color: menuItemMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        Text {
                            text: modelData.icon
                            font.pixelSize: 24
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: "#ffffff"
                            font.pixelSize: 18 * textScale
                        }

                        Text {
                            text: "→"
                            color: "#666666"
                            font.pixelSize: 20
                        }
                    }

                    MouseArea {
                        id: menuItemMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            if (modelData.view) {
                                currentView = modelData.view
                            } else if (modelData.action === "setHomepage") {
                                var tab = getCurrentTab()
                                if (tab) {
                                    homepage = tab.url
                                    saveSettings()
                                }
                                currentView = "browser"
                            } else if (modelData.action === "reload") {
                                tabStack.currentItem.reload()
                                currentView = "browser"
                            }
                        }
                    }
                }
            }

            Item { height: 24; width: 1 }

            // Close browser
            Rectangle {
                width: parent.width
                height: 64
                radius: 12
                color: closeMouse.pressed ? "#c23a50" : "#e94560"

                Text {
                    anchors.centerIn: parent
                    text: "Close Browser"
                    color: "#ffffff"
                    font.pixelSize: 18 * textScale
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.click()
                        Qt.quit()
                    }
                }
            }
        }

        // Back button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 72
            height: 72
            radius: 36
            color: "#2a2a3e"

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 32
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    currentView = "browser"
                    Haptic.tap()
                }
            }
        }
    }

    // ==================== Bookmarks View ====================

    Rectangle {
        id: bookmarksView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "bookmarks"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                Text {
                    anchors.centerIn: parent
                    text: "Bookmarks"
                    color: "#ffffff"
                    font.pixelSize: 24 * textScale
                    font.weight: Font.Bold
                }
            }

            ListView {
                width: parent.width
                height: parent.height - 180
                model: bookmarksList
                clip: true
                spacing: 4

                delegate: Rectangle {
                    width: parent.width - 32
                    height: 80
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 12
                    color: bookmarkItemMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                width: parent.width
                                text: modelData.title
                                color: "#ffffff"
                                font.pixelSize: 16 * textScale
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modelData.url
                                color: "#888888"
                                font.pixelSize: 12 * textScale
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            width: 44
                            height: 44
                            radius: 22
                            color: deleteBookmarkMouse.pressed ? "#e94560" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: "#888888"
                                font.pixelSize: 18
                            }

                            MouseArea {
                                id: deleteBookmarkMouse
                                anchors.fill: parent
                                onClicked: {
                                    removeBookmark(modelData.id)
                                    Haptic.tap()
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: bookmarkItemMouse
                        anchors.fill: parent
                        anchors.rightMargin: 60
                        onClicked: {
                            navigateTo(modelData.url)
                            currentView = "browser"
                            Haptic.tap()
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No bookmarks yet"
                    color: "#666666"
                    font.pixelSize: 18 * textScale
                    visible: bookmarksList.length === 0
                }
            }
        }

        // Back button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 72
            height: 72
            radius: 36
            color: "#e94560"

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 32
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    currentView = "menu"
                    Haptic.tap()
                }
            }
        }
    }

    // ==================== History View ====================

    Rectangle {
        id: historyView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "history"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16

                    Text {
                        text: "History"
                        color: "#ffffff"
                        font.pixelSize: 24 * textScale
                        font.weight: Font.Bold
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 100
                        height: 44
                        radius: 22
                        color: clearHistoryMouse.pressed ? "#c23a50" : "#e94560"
                        visible: historyList.length > 0

                        Text {
                            anchors.centerIn: parent
                            text: "Clear"
                            color: "#ffffff"
                            font.pixelSize: 14 * textScale
                        }

                        MouseArea {
                            id: clearHistoryMouse
                            anchors.fill: parent
                            onClicked: {
                                clearHistory()
                                Haptic.click()
                            }
                        }
                    }
                }
            }

            ListView {
                width: parent.width
                height: parent.height - 180
                model: historyList
                clip: true
                spacing: 4

                delegate: Rectangle {
                    width: parent.width - 32
                    height: 72
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 12
                    color: historyItemMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4

                        Text {
                            width: parent.width
                            text: modelData.title
                            color: "#ffffff"
                            font.pixelSize: 15 * textScale
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: modelData.url
                            color: "#888888"
                            font.pixelSize: 11 * textScale
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: historyItemMouse
                        anchors.fill: parent
                        onClicked: {
                            navigateTo(modelData.url)
                            currentView = "browser"
                            Haptic.tap()
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No history yet"
                    color: "#666666"
                    font.pixelSize: 18 * textScale
                    visible: historyList.length === 0
                }
            }
        }

        // Back button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 72
            height: 72
            radius: 36
            color: "#e94560"

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 32
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    currentView = "menu"
                    Haptic.tap()
                }
            }
        }
    }

    // ==================== Downloads View ====================

    Rectangle {
        id: downloadsView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "downloads"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                Text {
                    anchors.centerIn: parent
                    text: "Downloads"
                    color: "#ffffff"
                    font.pixelSize: 24 * textScale
                    font.weight: Font.Bold
                }
            }

            ListView {
                width: parent.width
                height: parent.height - 180
                model: downloadsList
                clip: true
                spacing: 4

                delegate: Rectangle {
                    width: parent.width - 32
                    height: 80
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 12
                    color: "#1a1a2e"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8

                        Text {
                            width: parent.width
                            text: modelData.filename
                            color: "#ffffff"
                            font.pixelSize: 16 * textScale
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                height: 4
                                radius: 2
                                color: "#2a2a3e"

                                Rectangle {
                                    width: parent.width * (modelData.progress / 100)
                                    height: parent.height
                                    radius: 2
                                    color: modelData.status === "completed" ? "#4caf50" : "#e94560"
                                }
                            }

                            Text {
                                text: modelData.status === "completed" ? "✓" : modelData.progress + "%"
                                color: modelData.status === "completed" ? "#4caf50" : "#888888"
                                font.pixelSize: 12 * textScale
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No downloads yet"
                    color: "#666666"
                    font.pixelSize: 18 * textScale
                    visible: downloadsList.length === 0
                }
            }
        }

        // Back button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 72
            height: 72
            radius: 36
            color: "#e94560"

            Text {
                anchors.centerIn: parent
                text: "←"
                color: "#ffffff"
                font.pixelSize: 32
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    currentView = "menu"
                    Haptic.tap()
                }
            }
        }
    }
}
