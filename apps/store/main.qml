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

    // File paths - detect home directory
    property string userHome: {
        var home = Qt.resolvedUrl(".").toString().replace("file://", "")
        // Extract home from path like /home/user/Flick/apps/store/
        var match = home.match(/^(\/home\/[^\/]+)\//)
        return match ? match[1] : "/home/droidian"
    }
    property string flickDir: userHome + "/Flick"
    property string stateDir: userHome + "/.local/state/flick"
    property string cacheDir: stateDir + "/store_cache"
    property string settingsFile: stateDir + "/store_settings.json"
    property string installedFile: stateDir + "/store_installed.json"
    property string reviewsFile: stateDir + "/store_reviews.json"
    property string requestsFile: stateDir + "/store_requests.json"
    property string localPackagesDir: flickDir + "/store/packages"
    property string installScript: flickDir + "/apps/store/install_app.sh"
    property string installRequestFile: "/tmp/flick_install_request"
    property string installStatusFile: "/tmp/flick_install_status"

    // Local packages
    property var localPackages: []

    Component.onCompleted: {
        loadConfig()
        loadSettings()
        loadInstalledApps()
        loadLocalPackages()
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

    function loadLocalPackages() {
        // Known local packages - read their manifests
        var packageIds = ["distract", "audiobooks", "ebooks", "passwordsafe", "podcast", "recorder", "sandbox", "music"]
        var packages = []

        for (var i = 0; i < packageIds.length; i++) {
            var pkgId = packageIds[i]
            var manifestPath = localPackagesDir + "/" + pkgId + "/manifest.json"
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file://" + manifestPath, false)
            try {
                xhr.send()
                if (xhr.status === 200 || xhr.status === 0) {
                    var manifest = JSON.parse(xhr.responseText)
                    packages.push({
                        id: pkgId,
                        name: manifest.name || pkgId,
                        description: manifest.description || "",
                        long_description: manifest.long_description || manifest.description || "",
                        author: manifest.author ? manifest.author.name : "Flick Project",
                        version: manifest.version || "1.0.0",
                        icon: getIconForCategory(manifest.categories ? manifest.categories[0] : "Utilities"),
                        rating: 4.5,
                        downloads: 100,
                        categories: manifest.categories || ["Utilities"],
                        isLocal: true
                    })
                }
            } catch (e) {
                console.log("Could not load manifest for " + pkgId + ": " + e)
            }
        }

        localPackages = packages
        console.log("Loaded " + packages.length + " local packages")

        // Add local packages to featured if not already showing API apps
        if (featuredApps.length === 0) {
            featuredApps = packages.slice(0, 4)
        }
        if (newApps.length === 0) {
            newApps = packages
        }
    }

    function getIconForCategory(category) {
        var icons = {
            "Games": "game",
            "Utilities": "wrench",
            "Media": "play",
            "Audio": "music",
            "Player": "play",
            "Social": "people",
            "Productivity": "briefcase",
            "Education": "book",
            "Lifestyle": "heart",
            "Security": "gear",
            "Entertainment": "game"
        }
        return icons[category] || "app"
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

        // Search Wild West apps locally
        var lowerQuery = query.toLowerCase()
        var wildWestMatches = []
        for (var i = 0; i < wildWestApps.length; i++) {
            var app = wildWestApps[i]
            var name = (app.name || "").toLowerCase()
            var desc = (app.description || "").toLowerCase()
            if (name.indexOf(lowerQuery) >= 0 || desc.indexOf(lowerQuery) >= 0) {
                // Clone the app object and mark as Wild West
                var matchedApp = JSON.parse(JSON.stringify(app))
                matchedApp.isWildWest = true
                wildWestMatches.push(matchedApp)
            }
        }

        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps/search?q=" + encodeURIComponent(query))
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingSearch = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        var apiResults = data.apps || data || []
                        // Combine API results with Wild West matches (Wild West at end)
                        searchResults = apiResults.concat(wildWestMatches)
                    } catch (e) {
                        console.log("Error parsing search results:", e)
                        searchResults = wildWestMatches
                    }
                } else {
                    console.log("Error searching apps:", xhr.status, xhr.statusText)
                    // Still show Wild West matches even if API fails
                    searchResults = wildWestMatches
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

    function loadAllApps() {
        if (isLoadingCategory) return
        isLoadingCategory = true
        apiError = ""

        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBaseUrl + "/apps")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingCategory = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        var apiApps = data.apps || data || []
                        // Also include Wild West apps marked with isWildWest
                        var wwApps = []
                        for (var i = 0; i < wildWestApps.length; i++) {
                            var app = JSON.parse(JSON.stringify(wildWestApps[i]))
                            app.isWildWest = true
                            wwApps.push(app)
                        }
                        categoryApps = apiApps.concat(wwApps)
                    } catch (e) {
                        console.log("Error parsing all apps:", e)
                        categoryApps = []
                    }
                } else {
                    categoryApps = []
                }
            }
        }
        xhr.send()
    }

    function findAppById(appId) {
        // Search in all known app lists
        var lists = [featuredApps, newApps, popularApps, categoryApps, wildWestApps]
        for (var i = 0; i < lists.length; i++) {
            var list = lists[i]
            for (var j = 0; j < list.length; j++) {
                if (list[j].id === appId || list[j].slug === appId) {
                    return list[j]
                }
            }
        }
        return null
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
        // Keep default categories with colors - API categories don't have colors
        // Just use the built-in categories defined at the top
        console.log("Using built-in categories")
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
        // Check the installed apps list
        // The list is synced with actual filesystem by flick-pkg
        for (var i = 0; i < installedApps.length; i++) {
            // Check both id and slug since API uses both
            if (installedApps[i].id === appId || installedApps[i].slug === appId) return true
        }
        return false
    }

    function getAppSlug(app) {
        // Get the slug/id for installation - prefer slug over numeric id
        return app.slug || app.id || ""
    }

    // Local install server URL
    property string installServerUrl: "http://localhost:7654"

    function installApp(app) {
        if (isDownloading) return
        isDownloading = true
        var slug = getAppSlug(app)
        downloadingApp = slug
        downloadProgress = 0

        // POST install request to local server
        var xhr = new XMLHttpRequest()
        xhr.open("POST", installServerUrl + "/install")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var result = JSON.parse(xhr.responseText)
                        if (result.success) {
                            console.log("Install success: " + result.output)
                            // Reload installed apps and complete
                            reloadInstalledApps()
                            downloadProgress = 1.0
                            completeInstallation()
                            return
                        }
                    } catch (e) {}
                }
                console.log("Install request sent, waiting for completion...")
            }
        }
        xhr.send(JSON.stringify({app: slug}))

        // Start progress simulation while install happens
        installTimer.start()
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

    Timer {
        id: installTimer
        interval: 300
        repeat: true
        property int checkCount: 0
        onTriggered: {
            downloadProgress = Math.min(0.9, downloadProgress + 0.1)
            checkCount++

            // Check if installation completed via server
            if (selectedApp) {
                var slug = getAppSlug(selectedApp)
                var xhr = new XMLHttpRequest()
                xhr.open("GET", installServerUrl + "/installed", false)
                try {
                    xhr.send()
                    if (xhr.status === 200) {
                        var data = JSON.parse(xhr.responseText)
                        var apps = data.apps || []
                        for (var i = 0; i < apps.length; i++) {
                            if (apps[i].id === slug || apps[i].slug === slug) {
                                // Found in installed list - installation complete!
                                installedApps = apps
                                installTimer.stop()
                                checkCount = 0
                                downloadProgress = 1.0
                                completeInstallation()
                                return
                            }
                        }
                    }
                } catch (e) {
                    // Server not available, try local file
                    loadInstalledApps()
                }
            }

            // Timeout after 15 seconds
            if (checkCount >= 50) {
                installTimer.stop()
                checkCount = 0
                isDownloading = false
                downloadProgress = 0
                downloadingApp = ""
                console.log("Installation timeout - use: flick-pkg install " + (selectedApp ? getAppSlug(selectedApp) : ""))
            }
        }
    }

    function completeInstallation() {
        if (selectedApp) {
            var slug = getAppSlug(selectedApp)
            // Add to installed list if not already there
            var found = false
            for (var i = 0; i < installedApps.length; i++) {
                if (installedApps[i].id === slug || installedApps[i].slug === slug) {
                    found = true
                    break
                }
            }
            if (!found) {
                installedApps.push({
                    id: slug,
                    slug: slug,
                    name: selectedApp.name,
                    icon: selectedApp.icon || "app",
                    version: selectedApp.version || "1.0.0",
                    installedAt: Date.now()
                })
                saveInstalledApps()
            }
        }
        isDownloading = false
        downloadProgress = 0
        downloadingApp = ""
        Haptic.click()
    }

    function reloadInstalledApps() {
        // Reload installed apps from server
        var xhr = new XMLHttpRequest()
        xhr.open("GET", installServerUrl + "/installed", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                installedApps = data.apps || []
            }
        } catch (e) {
            // Fall back to file if server not available
            loadInstalledApps()
        }
    }

    function uninstallApp(appId) {
        // POST uninstall request to local server
        var xhr = new XMLHttpRequest()
        xhr.open("POST", installServerUrl + "/uninstall")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    reloadInstalledApps()
                }
            }
        }
        xhr.send(JSON.stringify({app: appId}))

        // Remove from installed list
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

    // Debug report dialog state
    property bool showingReportDialog: false
    property string reportText: ""

    function showDebugReportDialog() {
        reportText = ""
        reportStatus = ""
        reportError = ""
        isSubmittingReport = false
        showingReportDialog = true
    }

    function submitDebugReport() {
        if (!selectedApp || reportText.length < 10) return
        if (isSubmittingReport) return

        isSubmittingReport = true
        reportStatus = "Submitting..."
        reportError = ""

        var slug = getAppSlug(selectedApp)
        var xhr = new XMLHttpRequest()
        xhr.open("POST", apiBaseUrl + "/feedback/app/" + slug)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isSubmittingReport = false
                if (xhr.status === 200 || xhr.status === 201) {
                    console.log("Feedback submitted successfully")
                    reportStatus = "Submitted!"
                    // Close dialog after brief delay
                    reportSuccessTimer.start()
                } else {
                    // Parse error message from backend
                    var errorMsg = "Failed to submit (error " + xhr.status + ")"
                    try {
                        var resp = JSON.parse(xhr.responseText)
                        if (resp.error) errorMsg = resp.error
                    } catch (e) {}
                    console.log("Failed to submit feedback:", xhr.status, xhr.responseText)
                    reportError = errorMsg
                    reportStatus = ""
                }
            }
        }
        xhr.onerror = function() {
            isSubmittingReport = false
            reportError = "Network error - check connection"
            reportStatus = ""
        }
        // Backend expects: type (bug/suggestion/rebuild_request), title, content
        var data = JSON.stringify({
            type: "bug",
            title: "Bug Report: " + selectedApp.name,
            content: reportText,
            priority: "medium"
        })
        xhr.send(data)
    }

    property bool isSubmittingReport: false
    property string reportStatus: ""
    property string reportError: ""

    Timer {
        id: reportSuccessTimer
        interval: 1500
        onTriggered: showingReportDialog = false
    }

    // ==================== App Logs ====================

    property string logsAppId: ""
    property string logsAppName: ""
    property var logsContent: []
    property bool isLoadingLogs: false

    function openAppLogs(appId) {
        logsAppId = appId
        logsAppName = selectedApp ? selectedApp.name : appId
        loadAppLogs()
        navigateTo("logs")
    }

    function loadAppLogs() {
        // Read logs from file system via local HTTP server
        isLoadingLogs = true
        logsContent = []

        var xhr = new XMLHttpRequest()
        xhr.open("GET", "http://localhost:7654/logs/" + logsAppId)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isLoadingLogs = false
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        logsContent = data.logs || []
                    } catch (e) {
                        logsContent = [{text: "Error parsing logs: " + e, level: "ERROR"}]
                    }
                } else {
                    logsContent = [{text: "No logs found for this app", level: "INFO"}]
                }
            }
        }
        xhr.onerror = function() {
            isLoadingLogs = false
            logsContent = [{text: "Could not connect to log server", level: "ERROR"}]
        }
        xhr.send()
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
    // Clean tabbed design with Browse, Installed, Wild West

    property string homeTab: "browse"  // browse, installed, wildwest

    Rectangle {
        id: homeView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "home"

        Column {
            anchors.fill: parent
            spacing: 0

            // Header with title and login
            Rectangle {
                width: parent.width
                height: 100
                color: "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "Flick Store"
                    font.pixelSize: 32 * textScale
                    font.weight: Font.Bold
                    color: "#ffffff"
                }

                // Login/Profile button
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 20
                    width: isLoggedIn ? 48 : 100
                    height: 48
                    radius: 24
                    color: loginBtnMouse.pressed ? "#333344" : "#222233"

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: isLoggedIn ? "person" : "login"
                            font.family: iconFont.name
                            font.pixelSize: 20
                            color: accentColor
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            visible: !isLoggedIn
                            text: "Login"
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: loginBtnMouse
                        anchors.fill: parent
                        onClicked: navigateTo(isLoggedIn ? "profile" : "login")
                    }
                }

                // Back button
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 20
                    width: 48
                    height: 48
                    radius: 24
                    color: homeBackBtnMouse.pressed ? "#333344" : "#222233"

                    Text {
                        anchors.centerIn: parent
                        text: "arrow_back"
                        font.family: iconFont.name
                        font.pixelSize: 24
                        color: "#888899"
                    }

                    MouseArea {
                        id: homeBackBtnMouse
                        anchors.fill: parent
                        onClicked: Qt.quit()
                    }
                }
            }

            // Tab bar
            Rectangle {
                width: parent.width
                height: 56
                color: "#111118"

                Row {
                    anchors.centerIn: parent
                    spacing: 0

                    Repeater {
                        model: [
                            { id: "browse", label: "Browse", icon: "apps" },
                            { id: "installed", label: "Installed", icon: "check_circle" },
                            { id: "wildwest", label: "Wild West", icon: "science" }
                        ]

                        Rectangle {
                            width: (root.width - 40) / 3
                            height: 48
                            radius: 12
                            color: homeTab === modelData.id ? accentColor : "transparent"
                            opacity: homeTab === modelData.id ? 1.0 : 0.7

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: modelData.icon
                                    font.family: iconFont.name
                                    font.pixelSize: 18
                                    color: homeTab === modelData.id ? "#ffffff" : "#888899"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: modelData.label
                                    font.pixelSize: 15 * textScale
                                    font.weight: Font.Medium
                                    color: homeTab === modelData.id ? "#ffffff" : "#888899"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    homeTab = modelData.id
                                    if (modelData.id === "wildwest") {
                                        loadWildWestApps()
                                    }
                                    Haptic.click()
                                }
                            }
                        }
                    }
                }
            }

            // Search bar
            Rectangle {
                width: parent.width - 32
                height: 56
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 16
                radius: 28
                color: "#1a1a2e"
                border.color: "#2a2a3e"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    Text {
                        text: "search"
                        font.family: iconFont.name
                        font.pixelSize: 22
                        color: "#666677"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Search apps..."
                        font.pixelSize: 16 * textScale
                        color: "#666677"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: navigateTo("search")
                }
            }

            Item { width: 1; height: 16 }

            // Tab content
            Item {
                width: parent.width
                height: parent.height - 230

                // Browse tab - Categories
                Flickable {
                    anchors.fill: parent
                    visible: homeTab === "browse"
                    contentHeight: browseColumn.height + 40
                    clip: true

                    Column {
                        id: browseColumn
                        width: parent.width
                        spacing: 24
                        topPadding: 8

                        // Categories header
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            text: "Categories"
                            font.pixelSize: 22 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        // Categories grid - big buttons
                        Grid {
                            anchors.horizontalCenter: parent.horizontalCenter
                            columns: 2
                            spacing: 16

                            Repeater {
                                model: categories

                                Rectangle {
                                    property color catColor: modelData.color || "#4a90d9"
                                    width: (root.width - 48) / 2
                                    height: 100
                                    radius: 20
                                    color: catMouseHome.pressed ? Qt.darker(catColor, 1.2) : catColor

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 16

                                        Text {
                                            text: modelData.icon || "apps"
                                            font.family: iconFont.name
                                            font.pixelSize: 36
                                            color: "#ffffff"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: modelData.name || ""
                                            font.pixelSize: 18 * textScale
                                            font.weight: Font.Bold
                                            color: "#ffffff"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: catMouseHome
                                        anchors.fill: parent
                                        onClicked: {
                                            loadCategoryApps(modelData.id)
                                            selectedCategory = modelData.name
                                            navigateTo("browse")
                                            Haptic.click()
                                        }
                                    }
                                }
                            }
                        }

                        // All Apps button
                        Rectangle {
                            width: parent.width - 32
                            height: 64
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: 16
                            color: allAppsMouse.pressed ? "#333344" : "#222233"

                            Row {
                                anchors.centerIn: parent
                                spacing: 12

                                Text {
                                    text: "view_list"
                                    font.family: iconFont.name
                                    font.pixelSize: 24
                                    color: accentColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Browse All Apps"
                                    font.pixelSize: 18 * textScale
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: allAppsMouse
                                anchors.fill: parent
                                onClicked: {
                                    loadAllApps()
                                    selectedCategory = "All Apps"
                                    navigateTo("browse")
                                    Haptic.click()
                                }
                            }
                        }
                    }
                }

                // Installed tab
                Flickable {
                    anchors.fill: parent
                    visible: homeTab === "installed"
                    contentHeight: installedColumn.height + 40
                    clip: true

                    Column {
                        id: installedColumn
                        width: parent.width
                        spacing: 12
                        topPadding: 8

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            text: "Installed Apps (" + installedApps.length + ")"
                            font.pixelSize: 22 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        // Empty state
                        Column {
                            visible: installedApps.length === 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 16
                            topPadding: 60

                            Text {
                                text: "inbox"
                                font.family: iconFont.name
                                font.pixelSize: 64
                                color: "#444455"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: "No apps installed yet"
                                font.pixelSize: 18 * textScale
                                color: "#666677"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        // Installed apps list
                        Repeater {
                            model: installedApps

                            Rectangle {
                                width: parent.width - 32
                                height: 80
                                anchors.horizontalCenter: parent.horizontalCenter
                                radius: 16
                                color: installedItemMouse.pressed ? "#2a2a3e" : "#1a1a2e"

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 16

                                    Rectangle {
                                        width: 48
                                        height: 48
                                        radius: 12
                                        color: accentColor
                                        opacity: 0.3
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "apps"
                                            font.family: iconFont.name
                                            font.pixelSize: 24
                                            color: "#ffffff"
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        width: parent.width - 180

                                        Text {
                                            text: modelData.name || modelData.id
                                            font.pixelSize: 17 * textScale
                                            font.weight: Font.Medium
                                            color: "#ffffff"
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }

                                        Text {
                                            text: "v" + (modelData.version || "1.0.0")
                                            font.pixelSize: 14 * textScale
                                            color: "#666677"
                                        }
                                    }

                                    // Uninstall button
                                    Rectangle {
                                        width: 80
                                        height: 40
                                        radius: 20
                                        color: uninstallBtnMouse.pressed ? "#6b1a1a" : "#4a1a1a"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Remove"
                                            font.pixelSize: 13 * textScale
                                            color: "#ff6666"
                                        }

                                        MouseArea {
                                            id: uninstallBtnMouse
                                            anchors.fill: parent
                                            onClicked: {
                                                uninstallApp(modelData.id || modelData.slug)
                                                Haptic.click()
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: installedItemMouse
                                    anchors.fill: parent
                                    onClicked: {
                                        // Find full app info and open detail
                                        var app = findAppById(modelData.id)
                                        if (app) openAppDetail(app)
                                    }
                                }
                            }
                        }
                    }
                }

                // Wild West tab
                Flickable {
                    anchors.fill: parent
                    visible: homeTab === "wildwest"
                    contentHeight: wildwestColumn.height + 40
                    clip: true

                    Column {
                        id: wildwestColumn
                        width: parent.width
                        spacing: 12
                        topPadding: 8

                        // Header
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            spacing: 12

                            Text {
                                text: "science"
                                font.family: iconFont.name
                                font.pixelSize: 28
                                color: "#ff9800"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                Text {
                                    text: "Wild West"
                                    font.pixelSize: 22 * textScale
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }
                                Text {
                                    text: "AI-generated apps in testing"
                                    font.pixelSize: 14 * textScale
                                    color: "#888899"
                                }
                            }
                        }

                        // Warning banner
                        Rectangle {
                            width: parent.width - 32
                            height: 60
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: 12
                            color: "#2a1a00"
                            border.color: "#ff9800"
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: 12

                                Text {
                                    text: "warning"
                                    font.family: iconFont.name
                                    font.pixelSize: 24
                                    color: "#ff9800"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "These apps are experimental and may have bugs"
                                    font.pixelSize: 14 * textScale
                                    color: "#ffcc80"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Wild west apps list
                        Repeater {
                            model: wildWestApps

                            Rectangle {
                                width: parent.width - 32
                                height: 90
                                anchors.horizontalCenter: parent.horizontalCenter
                                radius: 16
                                color: wwItemMouse.pressed ? "#2a2a3e" : "#1a1a2e"
                                border.color: "#ff9800"
                                border.width: 1

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 16

                                    Rectangle {
                                        width: 56
                                        height: 56
                                        radius: 14
                                        color: "#ff9800"
                                        opacity: 0.3
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "science"
                                            font.family: iconFont.name
                                            font.pixelSize: 28
                                            color: "#ff9800"
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        width: parent.width - 90

                                        Text {
                                            text: modelData.name
                                            font.pixelSize: 17 * textScale
                                            font.weight: Font.Medium
                                            color: "#ffffff"
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }

                                        Text {
                                            text: modelData.description || ""
                                            font.pixelSize: 14 * textScale
                                            color: "#888899"
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }

                                        Text {
                                            text: "v" + (modelData.version || "0.1") + " • AI Generated"
                                            font.pixelSize: 12 * textScale
                                            color: "#ff9800"
                                        }
                                    }
                                }

                                MouseArea {
                                    id: wwItemMouse
                                    anchors.fill: parent
                                    onClicked: openAppDetail(modelData)
                                }
                            }
                        }

                        // Empty state for wild west
                        Column {
                            visible: wildWestApps.length === 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 16
                            topPadding: 40

                            Text {
                                text: "science"
                                font.family: iconFont.name
                                font.pixelSize: 64
                                color: "#444455"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: "No apps in testing"
                                font.pixelSize: 18 * textScale
                                color: "#666677"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }
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
                            text: "←"
                            font.pixelSize: 28
                            font.weight: Font.Medium
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
                    property bool isWildWest: modelData.isWildWest === true
                    width: browseGrid.cellWidth
                    height: 180

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 8
                        radius: 20
                        color: isWildWest
                            ? (browseAppMouse.pressed ? "#3d2a1a" : "#2d1f15")
                            : (browseAppMouse.pressed ? "#2a2a3e" : "#1a1a2e")
                        border.width: isWildWest ? 1 : 0
                        border.color: "#ff9800"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Rectangle {
                                width: 64
                                height: 64
                                radius: 16
                                color: isWildWest ? "#ff9800" : accentColor
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

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 6

                                Text {
                                    text: modelData.name
                                    font.pixelSize: 15 * textScale
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    visible: isWildWest
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: "#ff9800"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
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

                        // Feedback button
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            width: 32
                            height: 32
                            radius: 16
                            color: feedbackBtnMouse.pressed ? "#3a3a4e" : "#2a2a3e"
                            z: 10

                            Text {
                                anchors.centerIn: parent
                                text: "feedback"
                                font.family: iconFont.name
                                font.pixelSize: 16
                                color: isWildWest ? "#ff9800" : accentColor
                            }

                            MouseArea {
                                id: feedbackBtnMouse
                                anchors.fill: parent
                                onClicked: {
                                    selectedApp = modelData
                                    showDebugReportDialog()
                                    Haptic.tap()
                                }
                            }
                        }

                        MouseArea {
                            id: browseAppMouse
                            anchors.fill: parent
                            anchors.rightMargin: 40  // Don't overlap feedback button
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
                                text: "←"
                                font.pixelSize: 28
                                font.weight: Font.Medium
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
                    property bool isWildWest: modelData.isWildWest === true
                    width: parent.width - 32
                    height: 80
                    x: 16
                    radius: 16
                    color: isWildWest
                        ? (searchResultMouse.pressed ? "#3d2a1a" : "#2d1f15")
                        : (searchResultMouse.pressed ? "#2a2a3e" : "#1a1a2e")
                    border.width: isWildWest ? 1 : 0
                    border.color: "#ff9800"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Rectangle {
                            width: 56
                            height: 56
                            radius: 14
                            color: isWildWest ? "#ff9800" : accentColor
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

                            Row {
                                spacing: 8
                                Text {
                                    text: modelData.name
                                    font.pixelSize: 16 * textScale
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: isWildWest
                                    width: wildWestLabel.width + 8
                                    height: 16
                                    radius: 4
                                    color: "#ff9800"
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        id: wildWestLabel
                                        anchors.centerIn: parent
                                        text: "Wild West"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#000000"
                                    }
                                }
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

                    // Feedback button
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 12
                        width: 40
                        height: 40
                        radius: 20
                        color: searchFeedbackMouse.pressed ? "#3a3a4e" : "#2a2a3e"
                        z: 10

                        Text {
                            anchors.centerIn: parent
                            text: "feedback"
                            font.family: iconFont.name
                            font.pixelSize: 18
                            color: isWildWest ? "#ff9800" : accentColor
                        }

                        MouseArea {
                            id: searchFeedbackMouse
                            anchors.fill: parent
                            onClicked: {
                                selectedApp = modelData
                                showDebugReportDialog()
                                Haptic.tap()
                            }
                        }
                    }

                    MouseArea {
                        id: searchResultMouse
                        anchors.fill: parent
                        anchors.rightMargin: 52  // Don't overlap feedback button
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
                                text: "←"
                                font.pixelSize: 28
                                font.weight: Font.Medium
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

                            Text {
                                text: selectedApp && selectedApp.isLocal ? "Local package" : "From 255.one"
                                font.pixelSize: 14 * textScale
                                color: "#888899"
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
                        if (isDownloading && downloadingApp === (selectedApp ? getAppSlug(selectedApp) : "")) {
                            return "#333344"
                        }
                        if (selectedApp && isAppInstalled(getAppSlug(selectedApp))) {
                            return installMouse.pressed ? "#8b2a2a" : "#a33"  // Red for uninstall
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
                        visible: isDownloading && downloadingApp === (selectedApp ? getAppSlug(selectedApp) : "")
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: {
                                if (isDownloading && downloadingApp === (selectedApp ? getAppSlug(selectedApp) : "")) {
                                    return "hourglass_empty"
                                }
                                if (selectedApp && isAppInstalled(getAppSlug(selectedApp))) {
                                    return "delete"
                                }
                                return "download"
                            }
                            font.family: iconFont.name
                            font.pixelSize: 22
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: {
                                if (isDownloading && downloadingApp === (selectedApp ? getAppSlug(selectedApp) : "")) {
                                    return "Installing... " + Math.round(downloadProgress * 100) + "%"
                                }
                                if (selectedApp && isAppInstalled(getAppSlug(selectedApp))) {
                                    return "Remove from device"
                                }
                                return "Install from 255.one"
                            }
                            font.pixelSize: 18 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: installMouse
                        anchors.fill: parent
                        onClicked: {
                            if (isDownloading) return
                            if (!selectedApp) return
                            var slug = getAppSlug(selectedApp)
                            if (isAppInstalled(slug)) {
                                uninstallApp(slug)
                                Haptic.click()
                            } else {
                                installApp(selectedApp)
                                Haptic.click()
                            }
                        }
                    }
                }

                // Wild West warning banner
                Rectangle {
                    visible: selectedApp && (selectedApp.status === "wild_west" || selectedApp.isWildWest)
                    width: parent.width - 32
                    height: wildWestBannerCol.height + 24
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 16
                    color: "#2d1f15"
                    border.width: 1
                    border.color: "#ff9800"

                    Column {
                        id: wildWestBannerCol
                        width: parent.width - 24
                        anchors.centerIn: parent
                        spacing: 12

                        Row {
                            spacing: 8
                            Text {
                                text: "warning"
                                font.family: iconFont.name
                                font.pixelSize: 20
                                color: "#ff9800"
                            }
                            Text {
                                text: "Wild West App"
                                font.pixelSize: 16 * textScale
                                font.weight: Font.Bold
                                color: "#ff9800"
                            }
                        }

                        Text {
                            width: parent.width
                            text: "This app has not been reviewed. It may contain bugs or security issues. Use at your own risk."
                            font.pixelSize: 14 * textScale
                            color: "#cc9966"
                            wrapMode: Text.Wrap
                        }

                        Rectangle {
                            width: parent.width
                            height: 44
                            radius: 22
                            color: debugReportMouse.pressed ? "#4a3020" : "#3d2a1a"
                            border.width: 1
                            border.color: "#ff9800"

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: "bug_report"
                                    font.family: iconFont.name
                                    font.pixelSize: 18
                                    color: "#ff9800"
                                }

                                Text {
                                    text: "Report Issue"
                                    font.pixelSize: 14 * textScale
                                    font.weight: Font.Medium
                                    color: "#ff9800"
                                }
                            }

                            MouseArea {
                                id: debugReportMouse
                                anchors.fill: parent
                                onClicked: {
                                    Haptic.click()
                                    showDebugReportDialog()
                                }
                            }
                        }
                    }
                }

                // View Logs button (for installed apps)
                Rectangle {
                    visible: selectedApp && isAppInstalled(getAppSlug(selectedApp))
                    width: parent.width - 32
                    height: 52
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 26
                    color: viewLogsMouse.pressed ? "#2a3a4a" : "#1a2a3a"
                    border.width: 1
                    border.color: "#4a90d9"

                    Row {
                        anchors.centerIn: parent
                        spacing: 10

                        Text {
                            text: "description"
                            font.family: iconFont.name
                            font.pixelSize: 20
                            color: "#4a90d9"
                        }

                        Text {
                            text: "View Logs"
                            font.pixelSize: 16 * textScale
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }
                    }

                    MouseArea {
                        id: viewLogsMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            openAppLogs(getAppSlug(selectedApp))
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
                            text: "←"
                            font.pixelSize: 28
                            font.weight: Font.Medium
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
                            text: "←"
                            font.pixelSize: 28
                            font.weight: Font.Medium
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
                            text: "←"
                            font.pixelSize: 28
                            font.weight: Font.Medium
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

    // ==================== LOGS VIEW ====================

    Rectangle {
        id: logsView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentView === "logs"

        Column {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                width: parent.width
                height: 100
                color: "#1a2a3a"

                Row {
                    anchors.fill: parent
                    anchors.margins: 20
                    anchors.topMargin: 40
                    spacing: 16

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: logsBackMouse.pressed ? "#2a3a4a" : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "←"
                            font.pixelSize: 28
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: logsBackMouse
                            anchors.fill: parent
                            onClicked: goBack()
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            text: "App Logs"
                            font.pixelSize: 22 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        Text {
                            text: logsAppName
                            font.pixelSize: 14 * textScale
                            color: "#88aacc"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: refreshLogsMouse.pressed ? "#2a3a4a" : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "refresh"
                            font.family: iconFont.name
                            font.pixelSize: 24
                            color: "#4a90d9"
                        }

                        MouseArea {
                            id: refreshLogsMouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                loadAppLogs()
                            }
                        }
                    }
                }
            }

            // Logs content
            Rectangle {
                width: parent.width
                height: parent.height - 200
                color: "#0a0a0f"

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    contentHeight: logsColumn.height
                    clip: true

                    Column {
                        id: logsColumn
                        width: parent.width
                        spacing: 2

                        // Loading indicator
                        Text {
                            visible: isLoadingLogs
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Loading logs..."
                            font.pixelSize: 14 * textScale
                            color: "#666677"
                        }

                        // Empty state
                        Column {
                            visible: !isLoadingLogs && logsContent.length === 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 16
                            topPadding: 60

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "description"
                                font.family: iconFont.name
                                font.pixelSize: 64
                                color: "#333344"
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "No logs available"
                                font.pixelSize: 18 * textScale
                                color: "#666677"
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Logs will appear here when the app runs"
                                font.pixelSize: 14 * textScale
                                color: "#555566"
                            }
                        }

                        // Log entries
                        Repeater {
                            model: logsContent

                            Rectangle {
                                width: parent.width
                                height: logText.height + 8
                                radius: 4
                                color: {
                                    var level = modelData.level || "INFO"
                                    if (level === "ERROR") return "#2d1a1a"
                                    if (level === "WARN") return "#2d2a1a"
                                    return "#1a1a2a"
                                }

                                Text {
                                    id: logText
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: 8
                                    text: modelData.text || modelData
                                    font.pixelSize: 12 * textScale
                                    font.family: "monospace"
                                    color: {
                                        var level = modelData.level || "INFO"
                                        if (level === "ERROR") return "#ff6666"
                                        if (level === "WARN") return "#ffaa44"
                                        return "#aabbcc"
                                    }
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
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
                            text: "←"
                            font.pixelSize: 28
                            font.weight: Font.Medium
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
                            text: "←"
                            font.pixelSize: 28
                            font.weight: Font.Medium
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
                            text: "←"
                            font.pixelSize: 28
                            font.weight: Font.Medium
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

    // ==================== Debug Report Dialog ====================

    Rectangle {
        id: reportDialogOverlay
        anchors.fill: parent
        color: "#000000aa"
        visible: showingReportDialog
        z: 1000

        MouseArea {
            anchors.fill: parent
            onClicked: showingReportDialog = false
        }

        Rectangle {
            width: parent.width - 48
            height: reportDialogColumn.height + 48
            anchors.centerIn: parent
            radius: 24
            color: "#1a1a2e"
            border.width: 1
            border.color: "#ff9800"

            MouseArea {
                anchors.fill: parent
                // Prevent click through
            }

            Column {
                id: reportDialogColumn
                width: parent.width - 48
                anchors.centerIn: parent
                spacing: 16

                Row {
                    spacing: 8
                    Text {
                        text: "bug_report"
                        font.family: iconFont.name
                        font.pixelSize: 24
                        color: "#ff9800"
                    }
                    Text {
                        text: "Report Issue"
                        font.pixelSize: 20 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }
                }

                Text {
                    width: parent.width
                    text: "Describe the issue with " + (selectedApp ? selectedApp.name : "this app") + ":"
                    font.pixelSize: 14 * textScale
                    color: "#aaaaaa"
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    width: parent.width
                    height: 120
                    radius: 12
                    color: "#2a2a3e"
                    border.width: 1
                    border.color: reportTextInput.activeFocus ? accentColor : "#444455"

                    TextEdit {
                        id: reportTextInput
                        anchors.fill: parent
                        anchors.margins: 12
                        font.pixelSize: 14 * textScale
                        color: "#ffffff"
                        wrapMode: TextEdit.Wrap
                        onTextChanged: reportText = text

                        Text {
                            visible: reportTextInput.text.length === 0
                            text: "Crashes, bugs, unexpected behavior..."
                            font.pixelSize: 14 * textScale
                            color: "#666677"
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "Minimum 10 characters required"
                    font.pixelSize: 12 * textScale
                    color: "#666677"
                    visible: reportError === "" && reportStatus === ""
                }

                // Status message (submitting/success)
                Text {
                    width: parent.width
                    text: reportStatus
                    font.pixelSize: 14 * textScale
                    font.weight: Font.Medium
                    color: reportStatus === "Submitted!" ? "#4caf50" : "#ff9800"
                    visible: reportStatus !== ""
                    horizontalAlignment: Text.AlignHCenter
                }

                // Error message
                Rectangle {
                    width: parent.width
                    height: errorText.height + 16
                    radius: 8
                    color: "#3d1a1a"
                    border.width: 1
                    border.color: "#ff4444"
                    visible: reportError !== ""

                    Text {
                        id: errorText
                        anchors.centerIn: parent
                        width: parent.width - 16
                        text: reportError
                        font.pixelSize: 13 * textScale
                        color: "#ff6666"
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 48
                        radius: 24
                        color: cancelReportMouse.pressed ? "#3a3a4e" : "#2a2a3e"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: 16 * textScale
                            color: "#aaaaaa"
                        }

                        MouseArea {
                            id: cancelReportMouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                showingReportDialog = false
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 48
                        radius: 24
                        color: {
                            if (isSubmittingReport) return "#666666"
                            if (reportText.length >= 10) return submitReportMouse.pressed ? "#cc7700" : "#ff9800"
                            return "#444455"
                        }

                        Text {
                            anchors.centerIn: parent
                            text: isSubmittingReport ? "..." : "Submit"
                            font.pixelSize: 16 * textScale
                            font.weight: Font.Bold
                            color: {
                                if (isSubmittingReport) return "#999999"
                                if (reportText.length >= 10) return "#000000"
                                return "#666666"
                            }
                        }

                        MouseArea {
                            id: submitReportMouse
                            anchors.fill: parent
                            enabled: reportText.length >= 10 && !isSubmittingReport
                            onClicked: {
                                Haptic.click()
                                submitDebugReport()
                            }
                        }
                    }
                }
            }
        }
    }
}
