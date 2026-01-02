import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../shared"

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Flick Store"
    color: "#0a0a0f"

    // Display config
    property real textScale: 1.0
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)

    // Navigation state
    property string currentView: "home" // home, browse, search, detail, wildwest, request, profile, settings
    property var viewStack: ["home"]

    // API configuration
    property string apiBaseUrl: "https://255.one/api"
    property var repositories: ["https://255.one"]

    // App data
    property var featuredApps: []
    property var categories: [
        { id: "games", name: "Games", icon: "controller", color: "#e94560" },
        { id: "utilities", name: "Utilities", icon: "wrench", color: "#4a90d9" },
        { id: "media", name: "Media", icon: "play", color: "#9b59b6" },
        { id: "social", name: "Social", icon: "people", color: "#27ae60" },
        { id: "productivity", name: "Productivity", icon: "briefcase", color: "#f39c12" },
        { id: "education", name: "Education", icon: "book", color: "#1abc9c" },
        { id: "lifestyle", name: "Lifestyle", icon: "heart", color: "#e74c3c" },
        { id: "tools", name: "Tools", icon: "gear", color: "#95a5a6" }
    ]
    property var newApps: []
    property var popularApps: []
    property var searchResults: []
    property var categoryApps: []
    property var wildWestApps: []
    property var appRequests: []
    property var myRequests: []
    property var installedApps: []
    property var myReviews: []

    // Selected states
    property var selectedApp: null
    property string selectedCategory: ""
    property string searchQuery: ""

    // User state
    property bool isLoggedIn: false
    property string username: "Anonymous"
    property string userId: ""

    // Download state
    property bool isDownloading: false
    property real downloadProgress: 0
    property string downloadingApp: ""

    // File paths
    property string stateDir: "/home/droidian/.local/state/flick"
    property string cacheDir: stateDir + "/store_cache"
    property string settingsFile: stateDir + "/store_settings.json"
    property string installedFile: stateDir + "/store_installed.json"
    property string reviewsFile: stateDir + "/store_reviews.json"
    property string requestsFile: stateDir + "/store_requests.json"

    Component.onCompleted: {
        loadConfig()
        loadSettings()
        loadInstalledApps()
        loadMyReviews()
        loadMyRequests()
        loadCategories()
        loadFeaturedApps()
        loadNewApps()
        loadPopularApps()
        getCurrentUser()
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
                apiBaseUrl = data.apiBaseUrl || apiBaseUrl
                repositories = data.repositories || repositories
                isLoggedIn = data.isLoggedIn || false
                username = data.username || "Anonymous"
                userId = data.userId || ""
            }
        } catch (e) {}
    }

    function saveSettings() {
        var data = {
            apiBaseUrl: apiBaseUrl,
            repositories: repositories,
            isLoggedIn: isLoggedIn,
            username: username,
            userId: userId
        }
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + settingsFile)
        xhr.send(JSON.stringify(data, null, 2))
    }

    function loadInstalledApps() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + installedFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                installedApps = data.apps || []
            }
        } catch (e) { installedApps = [] }
    }

    function saveInstalledApps() {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + installedFile)
        xhr.send(JSON.stringify({apps: installedApps}, null, 2))
    }

    function loadMyReviews() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + reviewsFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                myReviews = data.reviews || []
            }
        } catch (e) { myReviews = [] }
    }

    function saveMyReviews() {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + reviewsFile)
        xhr.send(JSON.stringify({reviews: myReviews}, null, 2))
    }

    function loadMyRequests() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + requestsFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var data = JSON.parse(xhr.responseText)
                myRequests = data.requests || []
            }
        } catch (e) { myRequests = [] }
    }

    function saveMyRequests() {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + requestsFile)
        xhr.send(JSON.stringify({requests: myRequests}, null, 2))
    }

    // ==================== API Functions ====================

    // Loading states for API calls
    property bool isLoadingFeatured: false
    property bool isLoadingNew: false
    property bool isLoadingPopular: false
    property bool isLoadingSearch: false
    property bool isLoadingCategory: false
    property bool isLoadingWildWest: false
    property bool isLoadingRequests: false

    // API error state
    property string apiError: ""

    function loadFeaturedApps() {
        if (isLoadingFeatured) return
        isLoadingFeatured = true
        apiError = ""

        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps/featured")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingFeatured = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        featuredApps = data.apps || data || []
                    } catch (e) {
                        console.log("Error parsing featured apps:", e)
                        apiError = "Failed to parse featured apps"
                    }
                } else {
                    console.log("Error loading featured apps:", xhr.status, xhr.statusText)
                    apiError = "Failed to load featured apps"
                }
            }
        }
        xhr.send()
    }

    function loadNewApps() {
        if (isLoadingNew) return
        isLoadingNew = true
        apiError = ""

        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps?sort=newest")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingNew = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        newApps = data.apps || data || []
                    } catch (e) {
                        console.log("Error parsing new apps:", e)
                        apiError = "Failed to parse new apps"
                    }
                } else {
                    console.log("Error loading new apps:", xhr.status, xhr.statusText)
                    apiError = "Failed to load new apps"
                }
            }
        }
        xhr.send()
    }

    function loadPopularApps() {
        if (isLoadingPopular) return
        isLoadingPopular = true
        apiError = ""

        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps?sort=downloads")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingPopular = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        popularApps = data.apps || data || []
                    } catch (e) {
                        console.log("Error parsing popular apps:", e)
                        apiError = "Failed to parse popular apps"
                    }
                } else {
                    console.log("Error loading popular apps:", xhr.status, xhr.statusText)
                    apiError = "Failed to load popular apps"
                }
            }
        }
        xhr.send()
    }

    function searchApps(query) {
        searchQuery = query
        if (query.length < 2) {
            searchResults = []
            return
        }

        if (isLoadingSearch) return
        isLoadingSearch = true
        apiError = ""

        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps/search?q=" + encodeURIComponent(query))
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingSearch = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        searchResults = data.apps || data || []
                    } catch (e) {
                        console.log("Error parsing search results:", e)
                        searchResults = []
                    }
                } else {
                    console.log("Error searching apps:", xhr.status, xhr.statusText)
                    searchResults = []
                }
            }
        }
        xhr.send()
    }

    function loadCategoryApps(categoryId) {
        selectedCategory = categoryId

        if (isLoadingCategory) return
        isLoadingCategory = true
        apiError = ""

        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps?category=" + encodeURIComponent(categoryId))
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingCategory = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        categoryApps = data.apps || data || []
                    } catch (e) {
                        console.log("Error parsing category apps:", e)
                        categoryApps = []
                    }
                } else {
                    console.log("Error loading category apps:", xhr.status, xhr.statusText)
                    categoryApps = []
                }
            }
        }
        xhr.send()
    }

    function loadWildWestApps() {
        if (isLoadingWildWest) return
        isLoadingWildWest = true
        apiError = ""

        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps?status=wild_west")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingWildWest = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        wildWestApps = data.apps || data || []
                    } catch (e) {
                        console.log("Error parsing wild west apps:", e)
                        wildWestApps = []
                    }
                } else {
                    console.log("Error loading wild west apps:", xhr.status, xhr.statusText)
                    wildWestApps = []
                }
            }
        }
        xhr.send()
    }

    function loadAppRequests() {
        if (isLoadingRequests) return
        isLoadingRequests = true
        apiError = ""

        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/requests")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingRequests = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        appRequests = data.requests || data || []
                    } catch (e) {
                        console.log("Error parsing app requests:", e)
                        appRequests = []
                    }
                } else {
                    console.log("Error loading app requests:", xhr.status, xhr.statusText)
                    appRequests = []
                }
            }
        }
        xhr.send()
    }

    function upvoteRequest(requestId) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", apiBaseUrl + "/requests/" + requestId + "/upvote")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    // Reload requests to get updated vote counts
                    loadAppRequests()
                } else {
                    console.log("Error upvoting request:", xhr.status, xhr.statusText)
                }
            }
        }
        xhr.send()
    }

    function loadCategories() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps/categories")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        if (data.categories && data.categories.length > 0) {
                            categories = data.categories
                        }
                    } catch (e) {
                        console.log("Error parsing categories:", e)
                    }
                } else {
                    console.log("Error loading categories:", xhr.status, xhr.statusText)
                }
            }
        }
        xhr.send()
    }

    function loadAppDetails(slug) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps/" + encodeURIComponent(slug))
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        selectedApp = data
                    } catch (e) {
                        console.log("Error parsing app details:", e)
                    }
                } else {
                    console.log("Error loading app details:", xhr.status, xhr.statusText)
                }
            }
        }
        xhr.send()
    }

    function loadAppReviews(slug) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/reviews/app/" + encodeURIComponent(slug))
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        // Store reviews in selectedApp if available
                        if (selectedApp) {
                            selectedApp.reviews = data.reviews || data || []
                            selectedAppChanged()
                        }
                    } catch (e) {
                        console.log("Error parsing reviews:", e)
                    }
                } else {
                    console.log("Error loading reviews:", xhr.status, xhr.statusText)
                }
            }
        }
        xhr.send()
    }

    function submitReview(slug, rating, content) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", apiBaseUrl + "/reviews/app/" + encodeURIComponent(slug))
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 201) {
                    // Reload reviews to show the new one
                    loadAppReviews(slug)
                    Haptic.click()
                } else {
                    console.log("Error submitting review:", xhr.status, xhr.statusText)
                }
            }
        }
        xhr.send(JSON.stringify({ rating: rating, content: content }))
    }

    function submitAppRequest(title, prompt, category) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", apiBaseUrl + "/requests")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 201) {
                    loadAppRequests()
                    Haptic.click()
                } else {
                    console.log("Error submitting request:", xhr.status, xhr.statusText)
                }
            }
        }
        xhr.send(JSON.stringify({ title: title, prompt: prompt, category: category }))
    }

    function loginUser(usernameInput, password) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", apiBaseUrl + "/auth/login")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        isLoggedIn = true
                        username = data.username || usernameInput
                        userId = data.id || data.userId || ""
                        saveSettings()
                        Haptic.click()
                    } catch (e) {
                        console.log("Error parsing login response:", e)
                    }
                } else {
                    console.log("Login failed:", xhr.status, xhr.statusText)
                }
            }
        }
        xhr.send(JSON.stringify({ username: usernameInput, password: password }))
    }

    function registerUser(usernameInput, email, password) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", apiBaseUrl + "/auth/register")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 201) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        isLoggedIn = true
                        username = data.username || usernameInput
                        userId = data.id || data.userId || ""
                        saveSettings()
                        Haptic.click()
                    } catch (e) {
                        console.log("Error parsing register response:", e)
                    }
                } else {
                    console.log("Registration failed:", xhr.status, xhr.statusText)
                }
            }
        }
        xhr.send(JSON.stringify({ username: usernameInput, email: email, password: password }))
    }

    function logoutUser() {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", apiBaseUrl + "/auth/logout")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                // Logout locally regardless of server response
                isLoggedIn = false
                username = "Anonymous"
                userId = ""
                saveSettings()
                Haptic.tap()
            }
        }
        xhr.send()
    }

    function getCurrentUser() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/auth/me")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        isLoggedIn = true
                        username = data.username || username
                        userId = data.id || data.userId || userId
                    } catch (e) {
                        console.log("Error parsing user data:", e)
                    }
                } else {
                    // Not logged in or session expired
                    isLoggedIn = false
                    username = "Anonymous"
                    userId = ""
                }
            }
        }
        xhr.send()
    }

    function isAppInstalled(appId) {
        for (var i = 0; i < installedApps.length; i++) {
            if (installedApps[i].id === appId) return true
        }
        return false
    }

    function installApp(app) {
        if (isDownloading) return
        isDownloading = true
        downloadingApp = app.id
        downloadProgress = 0

        // Simulate download progress
        downloadTimer.start()
    }

    Timer {
        id: downloadTimer
        interval: 100
        repeat: true
        onTriggered: {
            downloadProgress += 0.05
            if (downloadProgress >= 1.0) {
                downloadTimer.stop()
                completeInstallation()
            }
        }
    }

    function completeInstallation() {
        if (selectedApp) {
            installedApps.push({
                id: selectedApp.id,
                name: selectedApp.name,
                icon: selectedApp.icon,
                version: selectedApp.version,
                installedAt: Date.now()
            })
            saveInstalledApps()
        }
        isDownloading = false
        downloadProgress = 0
        downloadingApp = ""
        Haptic.click()
    }

    function uninstallApp(appId) {
        for (var i = 0; i < installedApps.length; i++) {
            if (installedApps[i].id === appId) {
                installedApps.splice(i, 1)
                installedAppsChanged()
                saveInstalledApps()
                Haptic.click()
                return
            }
        }
    }

    // ==================== Navigation ====================

    function navigateTo(view) {
        viewStack.push(view)
        currentView = view
        Haptic.tap()
    }

    function goBack() {
        if (viewStack.length > 1) {
            viewStack.pop()
            currentView = viewStack[viewStack.length - 1]
            Haptic.tap()
        } else {
            Qt.quit()
        }
    }

    function openAppDetail(app) {
        selectedApp = app
        navigateTo("detail")
    }

    // ==================== Config Timer ====================

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    // ==================== Helper Functions ====================

    function getIconForType(iconType) {
        var icons = {
            "camera": "camera.png",
            "note": "note.png",
            "cloud": "cloud.png",
            "music": "music.png",
            "run": "run.png",
            "code": "code.png",
            "chat": "chat.png",
            "folder": "folder.png",
            "game": "game.png",
            "robot": "robot.png",
            "translate": "translate.png",
            "photo": "photo.png",
            "controller": "game.png",
            "wrench": "tool.png",
            "play": "media.png",
            "people": "social.png",
            "briefcase": "work.png",
            "book": "book.png",
            "heart": "heart.png",
            "gear": "settings.png"
        }
        return icons[iconType] || "app.png"
    }

    function getIconEmoji(iconType) {
        var emojis = {
            "camera": "camera",
            "note": "note",
            "cloud": "cloud",
            "music": "music",
            "run": "run",
            "code": "code",
            "chat": "speech",
            "folder": "folder",
            "game": "game",
            "robot": "robot",
            "translate": "globe",
            "photo": "picture",
            "controller": "game",
            "wrench": "tool",
            "play": "play",
            "people": "people",
            "briefcase": "briefcase",
            "book": "book",
            "heart": "heart",
            "gear": "gear"
        }
        return emojis[iconType] || "app"
    }

    function formatNumber(num) {
        if (num >= 1000000) return (num / 1000000).toFixed(1) + "M"
        if (num >= 1000) return (num / 1000).toFixed(1) + "K"
        return num.toString()
    }

    function formatDate(timestamp) {
        var date = new Date(timestamp)
        return date.toLocaleDateString()
    }

    // ==================== HOME VIEW ====================

    Rectangle {
        id: homeView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "home"

        Flickable {
            id: homeFlickable
            anchors.fill: parent
            anchors.bottomMargin: 100
            contentHeight: homeColumn.height + 40
            clip: true
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: homeColumn
                width: parent.width
                spacing: 24

                // Header with search and settings
                Rectangle {
                    width: parent.width
                    height: 180
                    color: "transparent"

                    // Ambient glow
                    Rectangle {
                        anchors.centerIn: parent
                        width: 300
                        height: 200
                        radius: 150
                        color: accentColor
                        opacity: 0.08

                        NumberAnimation on opacity {
                            from: 0.05
                            to: 0.12
                            duration: 3000
                            loops: Animation.Infinite
                            easing.type: Easing.InOutSine
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Store"
                            font.pixelSize: 48 * textScale
                            font.weight: Font.ExtraLight
                            font.letterSpacing: 6
                            color: "#ffffff"
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "FLICK APP STORE"
                            font.pixelSize: 14 * textScale
                            font.weight: Font.Medium
                            font.letterSpacing: 3
                            color: "#555566"
                        }
                    }

                    // Settings button
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 20
                        anchors.topMargin: 60
                        width: 48
                        height: 48
                        radius: 24
                        color: settingsMouse.pressed ? "#333344" : "#222233"

                        Text {
                            anchors.centerIn: parent
                            text: "gear"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#888899"
                        }

                        MouseArea {
                            id: settingsMouse
                            anchors.fill: parent
                            onClicked: navigateTo("settings")
                        }
                    }

                    // Profile button
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 20
                        anchors.topMargin: 60
                        width: 48
                        height: 48
                        radius: 24
                        color: profileMouse.pressed ? "#333344" : "#222233"

                        Text {
                            anchors.centerIn: parent
                            text: "person"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#888899"
                        }

                        MouseArea {
                            id: profileMouse
                            anchors.fill: parent
                            onClicked: navigateTo("profile")
                        }
                    }

                    // Bottom fade line
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
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

                // Search bar
                Rectangle {
                    width: parent.width - 32
                    height: 56
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 28
                    color: "#1a1a2e"
                    border.color: "#2a2a3e"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Text {
                            text: "search"
                            font.family: iconFont.name
                            font.pixelSize: 22
                            color: "#666677"
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Search apps..."
                            font.pixelSize: 16 * textScale
                            color: "#666677"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: navigateTo("search")
                    }
                }

                // Featured apps carousel
                Column {
                    width: parent.width
                    spacing: 12

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Featured"
                        font.pixelSize: 20 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    ListView {
                        id: featuredList
                        width: parent.width
                        height: 200
                        orientation: ListView.Horizontal
                        spacing: 16
                        leftMargin: 16
                        rightMargin: 16
                        clip: true
                        model: featuredApps

                        delegate: Rectangle {
                            width: 280
                            height: 180
                            radius: 20
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#2a2a4e" }
                                GradientStop { position: 1.0; color: "#1a1a2e" }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 16

                                // App icon
                                Rectangle {
                                    width: 80
                                    height: 80
                                    radius: 20
                                    color: accentColor
                                    opacity: 0.3
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        font.family: iconFont.name
                                        font.pixelSize: 36
                                        color: "#ffffff"
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 96
                                    spacing: 8

                                    Text {
                                        text: modelData.name
                                        font.pixelSize: 18 * textScale
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }

                                    Text {
                                        text: modelData.description
                                        font.pixelSize: 15 * textScale
                                        color: "#888899"
                                        elide: Text.ElideRight
                                        width: parent.width
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                    }

                                    Row {
                                        spacing: 8

                                        Text {
                                            text: "star"
                                            font.family: iconFont.name
                                            font.pixelSize: 14
                                            color: "#ffc107"
                                        }

                                        Text {
                                            text: modelData.rating.toFixed(1)
                                            font.pixelSize: 15 * textScale
                                            color: "#888899"
                                        }

                                        Text {
                                            text: "  |  " + formatNumber(modelData.downloads) + " downloads"
                                            font.pixelSize: 15 * textScale
                                            color: "#666677"
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: openAppDetail(modelData)
                            }
                        }
                    }
                }

                // Categories grid
                Column {
                    width: parent.width
                    spacing: 12

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Categories"
                        font.pixelSize: 20 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 4
                        spacing: 12

                        Repeater {
                            model: categories

                            Rectangle {
                                width: (root.width - 64) / 4
                                height: width
                                radius: 16
                                color: catMouse.pressed ? Qt.lighter(modelData.color, 1.2) : modelData.color
                                opacity: 0.8

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon
                                        font.family: iconFont.name
                                        font.pixelSize: 28
                                        color: "#ffffff"
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.name
                                        font.pixelSize: 14 * textScale
                                        font.weight: Font.Medium
                                        color: "#ffffff"
                                    }
                                }

                                MouseArea {
                                    id: catMouse
                                    anchors.fill: parent
                                    onClicked: {
                                        loadCategoryApps(modelData.id)
                                        navigateTo("browse")
                                    }
                                }
                            }
                        }
                    }
                }

                // New Apps section
                Column {
                    width: parent.width
                    spacing: 12

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.right: parent.right
                        anchors.rightMargin: 16

                        Text {
                            text: "New Apps"
                            font.pixelSize: 20 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        Item { width: parent.width - 150; height: 1 }

                        Text {
                            text: "See all >"
                            font.pixelSize: 14 * textScale
                            color: accentColor

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    categoryApps = newApps
                                    selectedCategory = "new"
                                    navigateTo("browse")
                                }
                            }
                        }
                    }

                    ListView {
                        id: newAppsList
                        width: parent.width
                        height: 100
                        orientation: ListView.Horizontal
                        spacing: 12
                        leftMargin: 16
                        rightMargin: 16
                        clip: true
                        model: newApps

                        delegate: Rectangle {
                            width: 220
                            height: 80
                            radius: 16
                            color: newAppMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                            Row {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    width: 56
                                    height: 56
                                    radius: 14
                                    color: accentColor
                                    opacity: 0.3
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        font.family: iconFont.name
                                        font.pixelSize: 24
                                        color: "#ffffff"
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    Text {
                                        text: modelData.name
                                        font.pixelSize: 15 * textScale
                                        font.weight: Font.Medium
                                        color: "#ffffff"
                                    }

                                    Row {
                                        spacing: 4
                                        Text {
                                            text: "star"
                                            font.family: iconFont.name
                                            font.pixelSize: 12
                                            color: "#ffc107"
                                        }
                                        Text {
                                            text: modelData.rating.toFixed(1)
                                            font.pixelSize: 14 * textScale
                                            color: "#888899"
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: newAppMouse
                                anchors.fill: parent
                                onClicked: openAppDetail(modelData)
                            }
                        }
                    }
                }

                // Popular Apps section
                Column {
                    width: parent.width
                    spacing: 12

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.right: parent.right
                        anchors.rightMargin: 16

                        Text {
                            text: "Popular Apps"
                            font.pixelSize: 20 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        Item { width: parent.width - 180; height: 1 }

                        Text {
                            text: "See all >"
                            font.pixelSize: 14 * textScale
                            color: accentColor

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    categoryApps = popularApps
                                    selectedCategory = "popular"
                                    navigateTo("browse")
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width - 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        Repeater {
                            model: popularApps

                            Rectangle {
                                width: parent.width
                                height: 80
                                radius: 16
                                color: popAppMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    // Rank number
                                    Rectangle {
                                        width: 32
                                        height: 32
                                        radius: 16
                                        color: index === 0 ? "#ffc107" : (index === 1 ? "#c0c0c0" : (index === 2 ? "#cd7f32" : "#3a3a4e"))
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: (index + 1).toString()
                                            font.pixelSize: 14 * textScale
                                            font.weight: Font.Bold
                                            color: index < 3 ? "#000000" : "#ffffff"
                                        }
                                    }

                                    Rectangle {
                                        width: 56
                                        height: 56
                                        radius: 14
                                        color: accentColor
                                        opacity: 0.3
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.icon
                                            font.family: iconFont.name
                                            font.pixelSize: 24
                                            color: "#ffffff"
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 120
                                        spacing: 4

                                        Text {
                                            text: modelData.name
                                            font.pixelSize: 15 * textScale
                                            font.weight: Font.Medium
                                            color: "#ffffff"
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }

                                        Text {
                                            text: formatNumber(modelData.downloads) + " downloads"
                                            font.pixelSize: 14 * textScale
                                            color: "#888899"
                                        }
                                    }
                                }

                                MouseArea {
                                    id: popAppMouse
                                    anchors.fill: parent
                                    onClicked: openAppDetail(modelData)
                                }
                            }
                        }
                    }
                }

                // Wild West teaser
                Rectangle {
                    width: parent.width - 32
                    height: 100
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 20
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#4a2a1a" }
                        GradientStop { position: 1.0; color: "#2a1a0a" }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16

                        Text {
                            text: "warning"
                            font.family: iconFont.name
                            font.pixelSize: 40
                            color: "#ff9800"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 60
                            spacing: 4

                            Text {
                                text: "Wild West"
                                font.pixelSize: 18 * textScale
                                font.weight: Font.Bold
                                color: "#ffffff"
                            }

                            Text {
                                text: "Try AI-generated apps and help test them"
                                font.pixelSize: 15 * textScale
                                color: "#ccaa88"
                                width: parent.width
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            loadWildWestApps()
                            navigateTo("wildwest")
                        }
                    }
                }

                // Request apps teaser
                Rectangle {
                    width: parent.width - 32
                    height: 80
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 16
                    color: "#1a2a3a"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        Text {
                            text: "lightbulb"
                            font.family: iconFont.name
                            font.pixelSize: 32
                            color: "#ffc107"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: "Request an App"
                                font.pixelSize: 16 * textScale
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }

                            Text {
                                text: "Submit ideas and vote on requests"
                                font.pixelSize: 14 * textScale
                                color: "#888899"
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            loadAppRequests()
                            navigateTo("request")
                        }
                    }
                }

                // Spacing at bottom
                Item { width: 1; height: 20 }
            }
        }

        // Bottom navigation bar
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a1a2e"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.topMargin: 8
                anchors.bottomMargin: 36

                Repeater {
                    model: [
                        { icon: "home", label: "Home", view: "home" },
                        { icon: "apps", label: "Browse", view: "browse" },
                        { icon: "search", label: "Search", view: "search" },
                        { icon: "person", label: "Profile", view: "profile" }
                    ]

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "transparent"

                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                font.family: iconFont.name
                                font.pixelSize: 24
                                color: currentView === modelData.view ? accentColor : "#666677"
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.pixelSize: 14 * textScale
                                color: currentView === modelData.view ? accentColor : "#666677"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (modelData.view === "browse") {
                                    categoryApps = featuredApps.concat(newApps).concat(popularApps)
                                    selectedCategory = "all"
                                }
                                currentView = modelData.view
                                viewStack = [modelData.view]
                                Haptic.tap()
                            }
                        }
                    }
                }
            }

            // Home indicator
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
            }
        }

        // Back button - prominent floating action button
        Rectangle {
            id: homeBackButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 24
            anchors.bottomMargin: 120
            width: 72
            height: 72
            radius: 36
            color: homeBackMouse.pressed ? accentPressed : accentColor

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
                font.weight: Font.Medium
                color: "#ffffff"
            }

            MouseArea {
                id: homeBackMouse
                anchors.fill: parent
                onClicked: Qt.quit()
            }
        }
    }

    // ==================== BROWSE VIEW ====================

    Rectangle {
        id: browseView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "browse"

        Column {
            anchors.fill: parent

            // Header
            Rectangle {
                width: parent.width
                height: 100
                color: "#1a1a2e"

                Row {
                    anchors.fill: parent
                    anchors.margins: 20
                    anchors.topMargin: 40
                    spacing: 16

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: browseBackMouse.pressed ? "#3a3a4e" : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: browseBackMouse
                            anchors.fill: parent
                            onClicked: goBack()
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (selectedCategory === "all") return "All Apps"
                            if (selectedCategory === "new") return "New Apps"
                            if (selectedCategory === "popular") return "Popular Apps"
                            for (var i = 0; i < categories.length; i++) {
                                if (categories[i].id === selectedCategory) return categories[i].name
                            }
                            return "Browse"
                        }
                        font.pixelSize: 24 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }
                }
            }

            // Filter bar
            Rectangle {
                width: parent.width
                height: 56
                color: "#0a0a0f"

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Rectangle {
                        width: 100
                        height: 32
                        radius: 16
                        color: "#2a2a3e"
                        border.color: accentColor
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "filter Sort"
                            font.family: iconFont.name
                            font.pixelSize: 15 * textScale
                            color: "#ffffff"
                        }
                    }

                    Rectangle {
                        width: 80
                        height: 32
                        radius: 16
                        color: "#1a1a2e"

                        Text {
                            anchors.centerIn: parent
                            text: "Free"
                            font.pixelSize: 15 * textScale
                            color: "#888899"
                        }
                    }

                    Rectangle {
                        width: 80
                        height: 32
                        radius: 16
                        color: "#1a1a2e"

                        Text {
                            anchors.centerIn: parent
                            text: "Rating"
                            font.pixelSize: 15 * textScale
                            color: "#888899"
                        }
                    }
                }
            }

            // App grid
            GridView {
                id: browseGrid
                width: parent.width
                height: parent.height - 256
                cellWidth: width / 2
                cellHeight: 180
                clip: true
                model: categoryApps

                delegate: Item {
                    width: browseGrid.cellWidth
                    height: 180

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 8
                        radius: 20
                        color: browseAppMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Rectangle {
                                width: 64
                                height: 64
                                radius: 16
                                color: accentColor
                                opacity: 0.3
                                anchors.horizontalCenter: parent.horizontalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.family: iconFont.name
                                    font.pixelSize: 28
                                    color: "#ffffff"
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                font.pixelSize: 15 * textScale
                                font.weight: Font.Medium
                                color: "#ffffff"
                                elide: Text.ElideRight
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 4

                                Text {
                                    text: "star"
                                    font.family: iconFont.name
                                    font.pixelSize: 14
                                    color: "#ffc107"
                                }

                                Text {
                                    text: modelData.rating.toFixed(1)
                                    font.pixelSize: 15 * textScale
                                    color: "#888899"
                                }
                            }
                        }

                        MouseArea {
                            id: browseAppMouse
                            anchors.fill: parent
                            onClicked: openAppDetail(modelData)
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No apps in this category"
                    font.pixelSize: 16 * textScale
                    color: "#666677"
                    visible: categoryApps.length === 0
                }
            }
        }

        // Bottom nav
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a1a2e"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
            }
        }
    }

    // ==================== SEARCH VIEW ====================

    Rectangle {
        id: searchView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "search"

        Column {
            anchors.fill: parent
            spacing: 0

            // Search header
            Rectangle {
                width: parent.width
                height: 120
                color: "#1a1a2e"

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 40
                    spacing: 12

                    Row {
                        width: parent.width
                        spacing: 12

                        Rectangle {
                            width: 44
                            height: 44
                            radius: 22
                            color: searchBackMouse.pressed ? "#3a3a4e" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "arrow_back"
                                font.family: iconFont.name
                                font.pixelSize: 24
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: searchBackMouse
                                anchors.fill: parent
                                onClicked: goBack()
                            }
                        }

                        Rectangle {
                            width: parent.width - 56
                            height: 44
                            radius: 22
                            color: "#2a2a3e"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                Text {
                                    text: "search"
                                    font.family: iconFont.name
                                    font.pixelSize: 20
                                    color: "#666677"
                                }

                                TextInput {
                                    id: searchInput
                                    Layout.fillWidth: true
                                    font.pixelSize: 16 * textScale
                                    color: "#ffffff"
                                    clip: true

                                    onTextChanged: searchApps(text)

                                    Text {
                                        anchors.fill: parent
                                        text: "Search apps..."
                                        font.pixelSize: 16 * textScale
                                        color: "#666677"
                                        visible: !parent.text && !parent.focus
                                    }
                                }

                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: clearSearchMouse.pressed ? "#4a4a5e" : "transparent"
                                    visible: searchInput.text.length > 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "close"
                                        font.family: iconFont.name
                                        font.pixelSize: 16
                                        color: "#888899"
                                    }

                                    MouseArea {
                                        id: clearSearchMouse
                                        anchors.fill: parent
                                        onClicked: {
                                            searchInput.text = ""
                                            searchResults = []
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Search results
            ListView {
                id: searchResultsList
                width: parent.width
                height: parent.height - 220
                clip: true
                spacing: 8
                model: searchResults

                delegate: Rectangle {
                    width: parent.width - 32
                    height: 80
                    x: 16
                    radius: 16
                    color: searchResultMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Rectangle {
                            width: 56
                            height: 56
                            radius: 14
                            color: accentColor
                            opacity: 0.3
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.family: iconFont.name
                                font.pixelSize: 24
                                color: "#ffffff"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 80
                            spacing: 4

                            Text {
                                text: modelData.name
                                font.pixelSize: 16 * textScale
                                font.weight: Font.Medium
                                color: "#ffffff"
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: modelData.description
                                font.pixelSize: 15 * textScale
                                color: "#888899"
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Row {
                                spacing: 8
                                Text {
                                    text: "star"
                                    font.family: iconFont.name
                                    font.pixelSize: 12
                                    color: "#ffc107"
                                }
                                Text {
                                    text: modelData.rating.toFixed(1)
                                    font.pixelSize: 14 * textScale
                                    color: "#888899"
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: searchResultMouse
                        anchors.fill: parent
                        onClicked: openAppDetail(modelData)
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 16
                    visible: searchResults.length === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "search"
                        font.family: iconFont.name
                        font.pixelSize: 64
                        color: "#333344"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: searchInput.text.length > 0 ? "No apps found" : "Search for apps"
                        font.pixelSize: 18 * textScale
                        color: "#666677"
                    }
                }
            }
        }

        // Bottom nav
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a1a2e"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
            }
        }
    }

    // ==================== APP DETAIL VIEW ====================

    Rectangle {
        id: detailView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "detail"

        Flickable {
            anchors.fill: parent
            anchors.bottomMargin: 100
            contentHeight: detailColumn.height + 40
            clip: true
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: detailColumn
                width: parent.width
                spacing: 24

                // Header with back button
                Rectangle {
                    width: parent.width
                    height: 80
                    color: "#1a1a2e"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        anchors.topMargin: 30
                        spacing: 16

                        Rectangle {
                            width: 44
                            height: 44
                            radius: 22
                            color: detailBackMouse.pressed ? "#3a3a4e" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "arrow_back"
                                font.family: iconFont.name
                                font.pixelSize: 24
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: detailBackMouse
                                anchors.fill: parent
                                onClicked: goBack()
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "App Details"
                            font.pixelSize: 20 * textScale
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }
                    }
                }

                // App info header
                Rectangle {
                    width: parent.width - 32
                    height: 140
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "transparent"

                    Row {
                        anchors.fill: parent
                        spacing: 20

                        Rectangle {
                            width: 100
                            height: 100
                            radius: 24
                            color: accentColor
                            opacity: 0.3
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: selectedApp ? selectedApp.icon : ""
                                font.family: iconFont.name
                                font.pixelSize: 48
                                color: "#ffffff"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 120
                            spacing: 8

                            Text {
                                text: selectedApp ? selectedApp.name : ""
                                font.pixelSize: 24 * textScale
                                font.weight: Font.Bold
                                color: "#ffffff"
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: selectedApp ? selectedApp.author : ""
                                font.pixelSize: 14 * textScale
                                color: accentColor
                            }

                            Row {
                                spacing: 16

                                Row {
                                    spacing: 4
                                    Text {
                                        text: "star"
                                        font.family: iconFont.name
                                        font.pixelSize: 16
                                        color: "#ffc107"
                                    }
                                    Text {
                                        text: selectedApp ? selectedApp.rating.toFixed(1) : ""
                                        font.pixelSize: 14 * textScale
                                        color: "#ffffff"
                                    }
                                }

                                Text {
                                    text: selectedApp ? formatNumber(selectedApp.downloads) + " downloads" : ""
                                    font.pixelSize: 14 * textScale
                                    color: "#888899"
                                }
                            }

                            Text {
                                text: selectedApp ? "v" + selectedApp.version : ""
                                font.pixelSize: 14 * textScale
                                color: "#666677"
                            }
                        }
                    }
                }

                // Install button
                Rectangle {
                    width: parent.width - 32
                    height: 56
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 28
                    color: {
                        if (isDownloading && downloadingApp === (selectedApp ? selectedApp.id : "")) {
                            return "#333344"
                        }
                        if (isAppInstalled(selectedApp ? selectedApp.id : "")) {
                            return "#2a4a2a"
                        }
                        return installMouse.pressed ? accentPressed : accentColor
                    }

                    // Progress bar overlay
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * downloadProgress
                        radius: 28
                        color: accentColor
                        visible: isDownloading && downloadingApp === (selectedApp ? selectedApp.id : "")
                    }

                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (isDownloading && downloadingApp === (selectedApp ? selectedApp.id : "")) {
                                return "Downloading... " + Math.round(downloadProgress * 100) + "%"
                            }
                            if (isAppInstalled(selectedApp ? selectedApp.id : "")) {
                                return "check Installed"
                            }
                            return "download Install"
                        }
                        font.family: iconFont.name
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: installMouse
                        anchors.fill: parent
                        onClicked: {
                            if (!isDownloading && selectedApp && !isAppInstalled(selectedApp.id)) {
                                installApp(selectedApp)
                                Haptic.click()
                            }
                        }
                    }
                }

                // Screenshots section
                Column {
                    width: parent.width
                    spacing: 12

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Screenshots"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    ListView {
                        width: parent.width
                        height: 200
                        orientation: ListView.Horizontal
                        spacing: 12
                        leftMargin: 16
                        rightMargin: 16
                        clip: true
                        model: 3 // Placeholder screenshots

                        delegate: Rectangle {
                            width: 120
                            height: 200
                            radius: 12
                            color: "#2a2a3e"

                            Column {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "image"
                                    font.family: iconFont.name
                                    font.pixelSize: 48
                                    color: "#444455"
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Screenshot " + (index + 1)
                                    font.pixelSize: 14 * textScale
                                    color: "#666677"
                                }
                            }
                        }
                    }
                }

                // Description
                Column {
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Text {
                        text: "Description"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    Text {
                        text: selectedApp ? selectedApp.description : ""
                        font.pixelSize: 15 * textScale
                        color: "#ccccdd"
                        width: parent.width
                        wrapMode: Text.Wrap
                    }
                }

                // Reviews section
                Column {
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Row {
                        width: parent.width

                        Text {
                            text: "Reviews"
                            font.pixelSize: 18 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        Item { width: parent.width - 180; height: 1 }

                        Rectangle {
                            width: 120
                            height: 36
                            radius: 18
                            color: writeReviewMouse.pressed ? "#3a3a4e" : "#2a2a3e"

                            Text {
                                anchors.centerIn: parent
                                text: "edit Write Review"
                                font.family: iconFont.name
                                font.pixelSize: 15 * textScale
                                color: accentColor
                            }

                            MouseArea {
                                id: writeReviewMouse
                                anchors.fill: parent
                                onClicked: {
                                    Haptic.tap()
                                    // TODO: Open review dialog
                                }
                            }
                        }
                    }

                    // Sample reviews
                    Repeater {
                        model: [
                            { user: "user123", rating: 5, text: "Great app! Works perfectly.", date: Date.now() - 86400000 },
                            { user: "appfan", rating: 4, text: "Good but could use more features.", date: Date.now() - 86400000 * 3 }
                        ]

                        Rectangle {
                            width: parent.width
                            height: 100
                            radius: 12
                            color: "#1a1a2e"

                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 6

                                Row {
                                    width: parent.width
                                    spacing: 8

                                    Text {
                                        text: modelData.user
                                        font.pixelSize: 14 * textScale
                                        font.weight: Font.Medium
                                        color: "#ffffff"
                                    }

                                    Repeater {
                                        model: 5
                                        Text {
                                            text: "star"
                                            font.family: iconFont.name
                                            font.pixelSize: 12
                                            color: index < modelData.rating ? "#ffc107" : "#333344"
                                        }
                                    }

                                    Item { width: parent.width - 200; height: 1 }

                                    Text {
                                        text: formatDate(modelData.date)
                                        font.pixelSize: 14 * textScale
                                        color: "#666677"
                                    }
                                }

                                Text {
                                    text: modelData.text
                                    font.pixelSize: 14 * textScale
                                    color: "#aaaaaa"
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }

                // Report issue button
                Rectangle {
                    width: parent.width - 32
                    height: 48
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 24
                    color: reportMouse.pressed ? "#4a2a2a" : "#3a1a1a"

                    Text {
                        anchors.centerIn: parent
                        text: "flag Report Issue"
                        font.family: iconFont.name
                        font.pixelSize: 14 * textScale
                        color: "#ff6666"
                    }

                    MouseArea {
                        id: reportMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            // TODO: Open report dialog
                        }
                    }
                }

                Item { width: 1; height: 20 }
            }
        }

        // Bottom safe area
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a1a2e"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
            }
        }
    }

    // ==================== WILD WEST VIEW ====================

    Rectangle {
        id: wildWestView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "wildwest"

        Column {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#4a2a1a"

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 30
                    spacing: 16

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: wwBackMouse.pressed ? "#5a3a2a" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: wwBackMouse
                            anchors.fill: parent
                            onClicked: goBack()
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "warning Wild West"
                        font.family: iconFont.name
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Bold
                        color: "#ff9800"
                    }
                }
            }

            // Warning banner
            Rectangle {
                width: parent.width
                height: 80
                color: "#3a2a1a"

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: "info"
                        font.family: iconFont.name
                        font.pixelSize: 24
                        color: "#ff9800"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "These are AI-generated apps in testing.\nUse at your own risk and provide feedback!"
                        font.pixelSize: 15 * textScale
                        color: "#ccaa88"
                        width: parent.width - 50
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Wild west apps list
            ListView {
                id: wwList
                width: parent.width
                height: parent.height - 260
                clip: true
                spacing: 12
                model: wildWestApps

                header: Item { height: 16; width: 1 }

                delegate: Rectangle {
                    width: parent.width - 32
                    height: 120
                    x: 16
                    radius: 16
                    color: wwAppMouse.pressed ? "#3a2a2a" : "#2a1a1a"
                    border.color: "#4a3a2a"
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        Rectangle {
                            width: 64
                            height: 64
                            radius: 16
                            color: "#ff9800"
                            opacity: 0.3
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.family: iconFont.name
                                font.pixelSize: 28
                                color: "#ffffff"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 180
                            spacing: 6

                            Text {
                                text: modelData.name
                                font.pixelSize: 17 * textScale
                                font.weight: Font.Bold
                                color: "#ffffff"
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: modelData.description
                                font.pixelSize: 15 * textScale
                                color: "#aa8866"
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Row {
                                spacing: 16

                                Text {
                                    text: modelData.downloads + " testers"
                                    font.pixelSize: 14 * textScale
                                    color: "#888866"
                                }

                                Text {
                                    text: modelData.feedbackCount + " feedback"
                                    font.pixelSize: 14 * textScale
                                    color: "#888866"
                                }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Rectangle {
                                width: 80
                                height: 36
                                radius: 18
                                color: "#ff9800"

                                Text {
                                    anchors.centerIn: parent
                                    text: "Test"
                                    font.pixelSize: 15 * textScale
                                    font.weight: Font.Bold
                                    color: "#000000"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        selectedApp = modelData
                                        navigateTo("detail")
                                    }
                                }
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 8

                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: "#2a4a2a"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "thumb_up"
                                        font.family: iconFont.name
                                        font.pixelSize: 16
                                        color: "#4caf50"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: Haptic.tap()
                                    }
                                }

                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: "#4a2a2a"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "thumb_down"
                                        font.family: iconFont.name
                                        font.pixelSize: 16
                                        color: "#f44336"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: Haptic.tap()
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: wwAppMouse
                        anchors.fill: parent
                        anchors.rightMargin: 100
                        onClicked: {
                            selectedApp = modelData
                            navigateTo("detail")
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No testing apps available"
                    font.pixelSize: 16 * textScale
                    color: "#666655"
                    visible: wildWestApps.length === 0
                }
            }
        }

        // Bottom nav
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#2a1a1a"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#4a3a2a"
            }
        }
    }

    // ==================== REQUEST VIEW ====================

    Rectangle {
        id: requestView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "request"

        Column {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a2a3a"

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 30
                    spacing: 16

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: reqBackMouse.pressed ? "#2a3a4a" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: reqBackMouse
                            anchors.fill: parent
                            onClicked: goBack()
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "lightbulb App Requests"
                        font.family: iconFont.name
                        font.pixelSize: 20 * textScale
                        font.weight: Font.Bold
                        color: "#ffc107"
                    }
                }
            }

            // New request button
            Rectangle {
                width: parent.width - 32
                height: 56
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 16
                radius: 28
                color: newReqMouse.pressed ? Qt.darker("#ffc107", 1.2) : "#ffc107"

                Text {
                    anchors.centerIn: parent
                    text: "add Submit New Request"
                    font.family: iconFont.name
                    font.pixelSize: 16 * textScale
                    font.weight: Font.Bold
                    color: "#000000"
                }

                MouseArea {
                    id: newReqMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.click()
                        // TODO: Open request form
                    }
                }
            }

            Item { height: 16; width: 1 }

            // Tabs
            Row {
                width: parent.width - 32
                anchors.horizontalCenter: parent.horizontalCenter
                height: 48

                property int selectedTab: 0

                Rectangle {
                    width: parent.width / 2
                    height: parent.height
                    color: parent.selectedTab === 0 ? "#2a2a3e" : "transparent"
                    radius: 12

                    Text {
                        anchors.centerIn: parent
                        text: "Popular Requests"
                        font.pixelSize: 14 * textScale
                        color: parent.parent.selectedTab === 0 ? "#ffffff" : "#888899"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: parent.parent.selectedTab = 0
                    }
                }

                Rectangle {
                    width: parent.width / 2
                    height: parent.height
                    color: parent.selectedTab === 1 ? "#2a2a3e" : "transparent"
                    radius: 12

                    Text {
                        anchors.centerIn: parent
                        text: "My Requests"
                        font.pixelSize: 14 * textScale
                        color: parent.parent.selectedTab === 1 ? "#ffffff" : "#888899"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: parent.parent.selectedTab = 1
                    }
                }
            }

            // Requests list
            ListView {
                id: requestsList
                width: parent.width
                height: parent.height - 300
                clip: true
                spacing: 12
                model: appRequests

                header: Item { height: 16; width: 1 }

                delegate: Rectangle {
                    width: parent.width - 32
                    height: 100
                    x: 16
                    radius: 16
                    color: reqItemMouse.pressed ? "#2a3a4a" : "#1a2a3a"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        // Upvote section
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Rectangle {
                                width: 48
                                height: 48
                                radius: 24
                                color: upvoteMouse.pressed ? "#3a4a5a" : "#2a3a4a"

                                Text {
                                    anchors.centerIn: parent
                                    text: "arrow_upward"
                                    font.family: iconFont.name
                                    font.pixelSize: 24
                                    color: "#4caf50"
                                }

                                MouseArea {
                                    id: upvoteMouse
                                    anchors.fill: parent
                                    onClicked: {
                                        upvoteRequest(modelData.id)
                                        Haptic.tap()
                                    }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.upvotes.toString()
                                font.pixelSize: 14 * textScale
                                font.weight: Font.Bold
                                color: "#4caf50"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 80
                            spacing: 6

                            Text {
                                text: modelData.title
                                font.pixelSize: 17 * textScale
                                font.weight: Font.Bold
                                color: "#ffffff"
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: modelData.description
                                font.pixelSize: 15 * textScale
                                color: "#aabbcc"
                                elide: Text.ElideRight
                                width: parent.width
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }

                            Text {
                                text: "by " + modelData.author + " - " + formatDate(modelData.createdAt)
                                font.pixelSize: 14 * textScale
                                color: "#667788"
                            }
                        }
                    }

                    MouseArea {
                        id: reqItemMouse
                        anchors.fill: parent
                        anchors.leftMargin: 80
                        onClicked: Haptic.tap()
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No requests yet"
                    font.pixelSize: 16 * textScale
                    color: "#666677"
                    visible: appRequests.length === 0
                }
            }
        }

        // Bottom nav
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a2a3a"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#2a3a4a"
            }
        }
    }

    // ==================== PROFILE VIEW ====================

    Rectangle {
        id: profileView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "profile"

        Flickable {
            anchors.fill: parent
            anchors.bottomMargin: 100
            contentHeight: profileColumn.height + 40
            clip: true
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: profileColumn
                width: parent.width
                spacing: 24

                // Header
                Rectangle {
                    width: parent.width
                    height: 200
                    color: "transparent"

                    // Gradient background
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#2a2a4e" }
                            GradientStop { position: 1.0; color: "#0a0a0f" }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 12

                        Rectangle {
                            width: 80
                            height: 80
                            radius: 40
                            color: accentColor
                            anchors.horizontalCenter: parent.horizontalCenter

                            Text {
                                anchors.centerIn: parent
                                text: "person"
                                font.family: iconFont.name
                                font.pixelSize: 40
                                color: "#ffffff"
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: username
                            font.pixelSize: 24 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: isLoggedIn ? "Logged in" : "Not logged in"
                            font.pixelSize: 14 * textScale
                            color: "#888899"
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 16
                        anchors.topMargin: 50
                        width: 44
                        height: 44
                        radius: 22
                        color: profBackMouse.pressed ? "#3a3a4e" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: profBackMouse
                            anchors.fill: parent
                            onClicked: goBack()
                        }
                    }
                }

                // Login/Register buttons (if not logged in)
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16
                    visible: !isLoggedIn

                    Rectangle {
                        width: 140
                        height: 48
                        radius: 24
                        color: loginMouse.pressed ? accentPressed : accentColor

                        Text {
                            anchors.centerIn: parent
                            text: "Login"
                            font.pixelSize: 16 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: loginMouse
                            anchors.fill: parent
                            onClicked: {
                                navigateTo("login")
                                Haptic.tap()
                            }
                        }
                    }

                    Rectangle {
                        width: 140
                        height: 48
                        radius: 24
                        color: registerMouse.pressed ? "#3a3a4e" : "#2a2a3e"

                        Text {
                            anchors.centerIn: parent
                            text: "Register"
                            font.pixelSize: 16 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: registerMouse
                            anchors.fill: parent
                            onClicked: {
                                navigateTo("register")
                                Haptic.tap()
                            }
                        }
                    }
                }

                // Logout button (if logged in)
                Rectangle {
                    width: 200
                    height: 48
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 24
                    color: logoutMouse.pressed ? "#4a2a2a" : "#3a1a1a"
                    visible: isLoggedIn

                    Text {
                        anchors.centerIn: parent
                        text: "Logout"
                        font.pixelSize: 16 * textScale
                        font.weight: Font.Bold
                        color: "#ff6666"
                    }

                    MouseArea {
                        id: logoutMouse
                        anchors.fill: parent
                        onClicked: logoutUser()
                    }
                }

                // Stats row
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 32

                    Column {
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: installedApps.length.toString()
                            font.pixelSize: 28 * textScale
                            font.weight: Font.Bold
                            color: accentColor
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Installed"
                            font.pixelSize: 15 * textScale
                            color: "#888899"
                        }
                    }

                    Column {
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: myReviews.length.toString()
                            font.pixelSize: 28 * textScale
                            font.weight: Font.Bold
                            color: accentColor
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Reviews"
                            font.pixelSize: 15 * textScale
                            color: "#888899"
                        }
                    }

                    Column {
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: myRequests.length.toString()
                            font.pixelSize: 28 * textScale
                            font.weight: Font.Bold
                            color: accentColor
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Requests"
                            font.pixelSize: 15 * textScale
                            color: "#888899"
                        }
                    }
                }

                // Installed apps section
                Column {
                    width: parent.width
                    spacing: 12

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Installed Apps"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    Column {
                        width: parent.width - 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        Repeater {
                            model: installedApps

                            Rectangle {
                                width: parent.width
                                height: 72
                                radius: 16
                                color: "#1a1a2e"

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    Rectangle {
                                        width: 48
                                        height: 48
                                        radius: 12
                                        color: accentColor
                                        opacity: 0.3
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.icon
                                            font.family: iconFont.name
                                            font.pixelSize: 22
                                            color: "#ffffff"
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 140
                                        spacing: 2

                                        Text {
                                            text: modelData.name
                                            font.pixelSize: 15 * textScale
                                            font.weight: Font.Medium
                                            color: "#ffffff"
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }

                                        Text {
                                            text: "v" + modelData.version
                                            font.pixelSize: 14 * textScale
                                            color: "#888899"
                                        }
                                    }

                                    Rectangle {
                                        width: 70
                                        height: 36
                                        radius: 18
                                        color: uninstallMouse.pressed ? "#4a2a2a" : "#3a1a1a"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Remove"
                                            font.pixelSize: 14 * textScale
                                            color: "#ff6666"
                                        }

                                        MouseArea {
                                            id: uninstallMouse
                                            anchors.fill: parent
                                            onClicked: uninstallApp(modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No installed apps"
                            font.pixelSize: 14 * textScale
                            color: "#666677"
                            visible: installedApps.length === 0
                        }
                    }
                }

                // My reviews section
                Column {
                    width: parent.width
                    spacing: 12

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "My Reviews"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No reviews yet"
                        font.pixelSize: 14 * textScale
                        color: "#666677"
                        visible: myReviews.length === 0
                    }
                }

                // Settings link
                Rectangle {
                    width: parent.width - 32
                    height: 56
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 16
                    color: profSettingsMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Text {
                            text: "settings"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#888899"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Store Settings"
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                        }

                        Item { width: parent.width - 200; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "chevron_right"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#666677"
                        }
                    }

                    MouseArea {
                        id: profSettingsMouse
                        anchors.fill: parent
                        onClicked: navigateTo("settings")
                    }
                }

                Item { width: 1; height: 20 }
            }
        }

        // Bottom nav
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a1a2e"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
            }
        }
    }

    // ==================== SETTINGS VIEW ====================

    Rectangle {
        id: settingsView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "settings"

        Column {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 30
                    spacing: 16

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: setBackMouse.pressed ? "#3a3a4e" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: setBackMouse
                            anchors.fill: parent
                            onClicked: goBack()
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Store Settings"
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 180
                contentHeight: settingsColumn.height + 40
                clip: true
                flickableDirection: Flickable.VerticalFlick

                Column {
                    id: settingsColumn
                    width: parent.width
                    spacing: 24
                    topPadding: 24

                    // Repositories section
                    Column {
                        width: parent.width - 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 12

                        Text {
                            text: "Repositories"
                            font.pixelSize: 18 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        Repeater {
                            model: repositories

                            Rectangle {
                                width: parent.width
                                height: 64
                                radius: 16
                                color: "#1a1a2e"

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    Text {
                                        text: "cloud"
                                        font.family: iconFont.name
                                        font.pixelSize: 24
                                        color: accentColor
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData
                                        font.pixelSize: 15 * textScale
                                        color: "#ffffff"
                                        elide: Text.ElideRight
                                        width: parent.width - 100
                                    }

                                    Rectangle {
                                        width: 36
                                        height: 36
                                        radius: 18
                                        color: removeRepoMouse.pressed ? "#4a2a2a" : "transparent"
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: index > 0 // Can't remove default repo

                                        Text {
                                            anchors.centerIn: parent
                                            text: "close"
                                            font.family: iconFont.name
                                            font.pixelSize: 18
                                            color: "#ff6666"
                                        }

                                        MouseArea {
                                            id: removeRepoMouse
                                            anchors.fill: parent
                                            onClicked: {
                                                repositories.splice(index, 1)
                                                repositoriesChanged()
                                                saveSettings()
                                                Haptic.tap()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 56
                            radius: 16
                            color: addRepoMouse.pressed ? "#3a3a4e" : "#2a2a3e"
                            border.color: accentColor
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: "add"
                                    font.family: iconFont.name
                                    font.pixelSize: 20
                                    color: accentColor
                                }

                                Text {
                                    text: "Add Repository"
                                    font.pixelSize: 15 * textScale
                                    color: accentColor
                                }
                            }

                            MouseArea {
                                id: addRepoMouse
                                anchors.fill: parent
                                onClicked: Haptic.tap()
                            }
                        }
                    }

                    // Cache section
                    Column {
                        width: parent.width - 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 12

                        Text {
                            text: "Cache"
                            font.pixelSize: 18 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        Rectangle {
                            width: parent.width
                            height: 56
                            radius: 16
                            color: clearCacheMouse.pressed ? "#4a2a2a" : "#3a1a1a"

                            Row {
                                anchors.centerIn: parent
                                spacing: 12

                                Text {
                                    text: "delete"
                                    font.family: iconFont.name
                                    font.pixelSize: 24
                                    color: "#ff6666"
                                }

                                Text {
                                    text: "Clear App Cache"
                                    font.pixelSize: 16 * textScale
                                    color: "#ff6666"
                                }
                            }

                            MouseArea {
                                id: clearCacheMouse
                                anchors.fill: parent
                                onClicked: {
                                    Haptic.click()
                                    // TODO: Clear cache
                                }
                            }
                        }
                    }

                    // About section
                    Column {
                        width: parent.width - 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 12

                        Text {
                            text: "About"
                            font.pixelSize: 18 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        Rectangle {
                            width: parent.width
                            height: 120
                            radius: 16
                            color: "#1a1a2e"

                            Column {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 8

                                Text {
                                    text: "Flick Store"
                                    font.pixelSize: 20 * textScale
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }

                                Text {
                                    text: "Version 1.0.0"
                                    font.pixelSize: 14 * textScale
                                    color: "#888899"
                                }

                                Text {
                                    text: "The official app store for Flick OS"
                                    font.pixelSize: 14 * textScale
                                    color: "#666677"
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    // Close button
                    Rectangle {
                        width: parent.width - 32
                        height: 56
                        anchors.horizontalCenter: parent.horizontalCenter
                        radius: 28
                        color: closeStoreMouse.pressed ? accentPressed : accentColor

                        Text {
                            anchors.centerIn: parent
                            text: "Close Store"
                            font.pixelSize: 16 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: closeStoreMouse
                            anchors.fill: parent
                            onClicked: Qt.quit()
                        }
                    }
                }
            }
        }

        // Bottom nav
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a1a2e"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
            }
        }
    }

    // ==================== LOGIN VIEW ====================

    Rectangle {
        id: loginView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "login"

        property string loginError: ""

        Column {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 30
                    spacing: 16

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: loginBackMouse.pressed ? "#3a3a4e" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: loginBackMouse
                            anchors.fill: parent
                            onClicked: goBack()
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Login"
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }
                }
            }

            Item { height: 40; width: 1 }

            // Login form
            Column {
                width: parent.width - 32
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20

                // Username field
                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Username"
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }

                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 16
                        color: "#1a1a2e"
                        border.color: loginUsernameInput.focus ? accentColor : "#2a2a3e"
                        border.width: 1

                        TextInput {
                            id: loginUsernameInput
                            anchors.fill: parent
                            anchors.margins: 16
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                            clip: true

                            Text {
                                anchors.fill: parent
                                text: "Enter username"
                                font.pixelSize: 16 * textScale
                                color: "#666677"
                                visible: !parent.text && !parent.focus
                            }
                        }
                    }
                }

                // Password field
                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Password"
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }

                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 16
                        color: "#1a1a2e"
                        border.color: loginPasswordInput.focus ? accentColor : "#2a2a3e"
                        border.width: 1

                        TextInput {
                            id: loginPasswordInput
                            anchors.fill: parent
                            anchors.margins: 16
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                            clip: true
                            echoMode: TextInput.Password

                            Text {
                                anchors.fill: parent
                                text: "Enter password"
                                font.pixelSize: 16 * textScale
                                color: "#666677"
                                visible: !parent.text && !parent.focus
                            }
                        }
                    }
                }

                // Error message
                Text {
                    width: parent.width
                    text: loginView.loginError
                    font.pixelSize: 14 * textScale
                    color: "#ff6666"
                    visible: loginView.loginError !== ""
                    horizontalAlignment: Text.AlignHCenter
                }

                // Login button
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 28
                    color: doLoginMouse.pressed ? accentPressed : accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "Login"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: doLoginMouse
                        anchors.fill: parent
                        onClicked: {
                            if (loginUsernameInput.text.length > 0 && loginPasswordInput.text.length > 0) {
                                loginUser(loginUsernameInput.text, loginPasswordInput.text)
                                loginUsernameInput.text = ""
                                loginPasswordInput.text = ""
                                goBack()
                            } else {
                                loginView.loginError = "Please enter username and password"
                            }
                            Haptic.tap()
                        }
                    }
                }

                // Register link
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Don't have an account? Register"
                    font.pixelSize: 14 * textScale
                    color: accentColor

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            currentView = "register"
                            viewStack[viewStack.length - 1] = "register"
                            Haptic.tap()
                        }
                    }
                }
            }
        }

        // Bottom nav
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a1a2e"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
            }
        }
    }

    // ==================== REGISTER VIEW ====================

    Rectangle {
        id: registerView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "register"

        property string registerError: ""

        Column {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                width: parent.width
                height: 80
                color: "#1a1a2e"

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 30
                    spacing: 16

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: regBackMouse.pressed ? "#3a3a4e" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: regBackMouse
                            anchors.fill: parent
                            onClicked: goBack()
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Register"
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }
                }
            }

            Item { height: 40; width: 1 }

            // Register form
            Column {
                width: parent.width - 32
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20

                // Username field
                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Username"
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }

                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 16
                        color: "#1a1a2e"
                        border.color: regUsernameInput.focus ? accentColor : "#2a2a3e"
                        border.width: 1

                        TextInput {
                            id: regUsernameInput
                            anchors.fill: parent
                            anchors.margins: 16
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                            clip: true

                            Text {
                                anchors.fill: parent
                                text: "Choose a username"
                                font.pixelSize: 16 * textScale
                                color: "#666677"
                                visible: !parent.text && !parent.focus
                            }
                        }
                    }
                }

                // Email field
                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Email"
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }

                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 16
                        color: "#1a1a2e"
                        border.color: regEmailInput.focus ? accentColor : "#2a2a3e"
                        border.width: 1

                        TextInput {
                            id: regEmailInput
                            anchors.fill: parent
                            anchors.margins: 16
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                            clip: true

                            Text {
                                anchors.fill: parent
                                text: "Enter your email"
                                font.pixelSize: 16 * textScale
                                color: "#666677"
                                visible: !parent.text && !parent.focus
                            }
                        }
                    }
                }

                // Password field
                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Password"
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }

                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 16
                        color: "#1a1a2e"
                        border.color: regPasswordInput.focus ? accentColor : "#2a2a3e"
                        border.width: 1

                        TextInput {
                            id: regPasswordInput
                            anchors.fill: parent
                            anchors.margins: 16
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                            clip: true
                            echoMode: TextInput.Password

                            Text {
                                anchors.fill: parent
                                text: "Create a password"
                                font.pixelSize: 16 * textScale
                                color: "#666677"
                                visible: !parent.text && !parent.focus
                            }
                        }
                    }
                }

                // Error message
                Text {
                    width: parent.width
                    text: registerView.registerError
                    font.pixelSize: 14 * textScale
                    color: "#ff6666"
                    visible: registerView.registerError !== ""
                    horizontalAlignment: Text.AlignHCenter
                }

                // Register button
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 28
                    color: doRegisterMouse.pressed ? accentPressed : accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "Create Account"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: doRegisterMouse
                        anchors.fill: parent
                        onClicked: {
                            if (regUsernameInput.text.length > 0 && regEmailInput.text.length > 0 && regPasswordInput.text.length > 0) {
                                registerUser(regUsernameInput.text, regEmailInput.text, regPasswordInput.text)
                                regUsernameInput.text = ""
                                regEmailInput.text = ""
                                regPasswordInput.text = ""
                                goBack()
                            } else {
                                registerView.registerError = "Please fill in all fields"
                            }
                            Haptic.tap()
                        }
                    }
                }

                // Login link
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Already have an account? Login"
                    font.pixelSize: 14 * textScale
                    color: accentColor

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            currentView = "login"
                            viewStack[viewStack.length - 1] = "login"
                            Haptic.tap()
                        }
                    }
                }
            }
        }

        // Bottom nav
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 100
            color: "#1a1a2e"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
            }
        }
    }

    // ==================== Icon Font ====================

    // Note: Using text placeholders for icons since Material Icons font may not be available
    // In production, would use proper icon font
    FontLoader {
        id: iconFont
        source: "qrc:/fonts/MaterialIcons-Regular.ttf"
        onStatusChanged: {
            if (status === FontLoader.Error) {
                console.log("Icon font not available, using text fallbacks")
            }
        }
    }
}
