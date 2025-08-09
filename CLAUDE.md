# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Claude Code Switcher is a macOS status bar application for quickly switching between Claude Code API provider configurations. It provides a convenient GUI to manage multiple API providers and automatically syncs configurations to `~/.claude/settings.json`.

### Key Features
- **Quick Provider Switching**: Switch between different API providers directly from the status bar
- **Custom Provider Icons**: Set custom icons for each API provider for easy visual identification
- **Token Usage Statistics**: Track and display API token usage for the last 3 days
- **Configuration Management**: Automatic sync with Claude Code's settings.json
- **Proxy Support**: Configure HTTP/HTTPS proxy settings per provider

## Key Commands

### Building the Project
```bash
# Open in Xcode
open ClaudeCodeSwitcher.xcodeproj

# Build using provided script (handles swiftc compilation)
./build.sh

# Manual Xcode build
xcodebuild -project ClaudeCodeSwitcher.xcodeproj -scheme ClaudeCodeSwitcher -configuration Release build
```

### Testing
```bash
# Run functionality tests
./test.sh
```

### Running
```bash
# Run in Xcode: Cmd+R
# Or run built app
open build/ClaudeCodeSwitcher.app
```

## Architecture Overview

The application follows a clean MVC architecture with SwiftUI for modern UI components:

### Core Architecture Layers
- **App Layer** (`App/`): Application lifecycle, status bar control, window management
- **Models Layer** (`Models/`): Data structures for API providers and Claude configuration
- **Services Layer** (`Services/`): Business logic for configuration management and token statistics
- **Views Layer** (`Views/`): SwiftUI-based settings interface

### Key Components
- **ConfigManager**: Singleton service managing API provider configuration and Claude settings sync
- **StatusBarController**: Handles status bar menu and provider switching
- **APIProvider**: Data model representing API provider configurations (name, URL, key, models, custom icon)
- **ClaudeConfig**: Model matching Claude Code's settings.json structure
- **TokenStatistics**: Service for tracking and displaying API token usage statistics
- **AppIconManager**: Manages custom icons for API providers and handles icon storage

### Configuration Sync Flow
1. User modifies provider settings in UI
2. ConfigManager updates local storage (UserDefaults)
3. ConfigManager automatically syncs to `~/.claude/settings.json`
4. Claude Code reads updated configuration

## Development Notes

### File Structure
- Main executable entry is `main.swift` (not SwiftUI App pattern)
- Status bar app uses `LSUIElement=true` in Info.plist (no dock icon)
- SwiftUI views are embedded in AppKit windows for status bar integration
- Configuration persisted in both UserDefaults and Claude settings file

### Claude Configuration Format
The app generates configuration compatible with Claude Code's expected format:
```json
{
  "env": {
    "ANTHROPIC_API_KEY": "...",
    "ANTHROPIC_BASE_URL": "...",
    "ANTHROPIC_MODEL": "...",
    "ANTHROPIC_SMALL_FAST_MODEL": "...",
    "HTTPS_PROXY": "...",
    "HTTP_PROXY": "..."
  }
}
```

### Dependencies
- Swift 5.0+
- macOS 13.0+ target
- AppKit for status bar integration
- SwiftUI for settings interface
- Combine for reactive programming
- No external package dependencies

### Important Implementation Details
- Uses `NSApplication.shared` with custom AppDelegate (not SwiftUI lifecycle)
- Status bar item managed manually via NSStatusBar
- Configuration changes trigger NotificationCenter events
- Proxy settings support both HTTP and HTTPS with automatic URL formatting
- Preserves existing Claude configuration fields when syncing
- Custom icons stored as base64 in UserDefaults
- Token statistics calculated from Claude Code's conversation history files
- Status bar icon changes based on selected provider's custom icon

### New Features (Recent Updates)
- **Custom Provider Icons**: Each API provider can have a custom icon displayed in the status bar
- **Token Usage Statistics**: View detailed token usage for the last 3 days, broken down by model
- **Enhanced UI**: Improved menu styling with visual separators and better organization
- **Configuration Change Notifications**: System notifications when provider is switched