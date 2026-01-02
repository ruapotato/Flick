# Flick Store

QML app for browsing and installing apps from Flick Forge (255.one).

## Architecture

```
Store QML → localhost:7654 → flick-pkg → 255.one API
    ↓              ↓              ↓
  (UI)      (install_server)  (CLI tool)
```

QML can't execute shell commands directly, so the Store POSTs install/uninstall
requests to a local HTTP server, which calls `flick-pkg` to do the actual work.

## Components

- `main.qml` - Store UI
- `install_server.py` - Local HTTP bridge (runs on port 7654)
- `flick-pkg` - CLI package manager (in repo root)

## Running the Install Server

The install server must be running for Store installations to work:

```bash
python3 ~/Flick/apps/store/install_server.py &
```

Or check if it's running:
```bash
curl http://localhost:7654/status
```

## API Endpoints

The local server provides:

- `GET /status` - Server health check
- `GET /installed` - List installed apps
- `POST /install` - Install an app (`{"app": "slug"}`)
- `POST /uninstall` - Uninstall an app (`{"app": "slug"}`)

## Package Sources

1. **Remote** (255.one) - Packages from Flick Forge
2. **Local** (`store/packages/`) - Bundled .flick packages

The CLI tool checks 255.one first, falls back to local packages.
