# Notely

A calm Markdown notes app for macOS, written in SwiftUI and AppKit. Your notes are plain `.md` files in a folder on your Mac — open the same folder in Obsidian or any editor.

The product name and icon letter are placeholders until the app is named.

## Features

- **Live preview editing.** Markdown renders as you type; the syntax of the line you're editing is revealed, Obsidian style — headings, lists, quotes, callouts, code, tables, math, images, local videos and YAML frontmatter.
- **Plain files.** A notes library is just a folder; subfolders show as a tree in the sidebar. Works with an existing Obsidian vault as it is.
- **Quick search.** ⇧⌘F searches file names, titles, folders, tags (`#tag`) and note text.
- **Typography.** Fixed line height, spacing between Chinese and Latin text, and a composite font that pairs a Latin family with Songti or PingFang.
- **Settings** for accent color, font, size, line spacing and text width, with a live preview.

## Requirements

- macOS 14 or later
- Xcode 26 or later (the macOS 26 SDK) to build

## Build and run

```bash
xcodebuild -project Notely.xcodeproj -scheme Notely -configuration Debug -derivedDataPath build/dd build
open build/dd/Build/Products/Debug/Notely.app
```

Or open `Notely.xcodeproj` in Xcode and run the Notely scheme.

## Tests

There is no Xcode test target. Each file in `Tests/` is a standalone runner; the `swiftc` command that builds it is in the comment at its top. Run from the repository root, for example:

```bash
swiftc Notely/Views/Editor/CursorMapping.swift Tests/CursorMappingTests.swift -o /tmp/cursormap-tests && /tmp/cursormap-tests
```

## Project structure

```
.
├── Notely/
│   ├── App/          # Window shell, app model, window behavior
│   ├── Models/       # Notes and settings
│   ├── Services/     # File store, search, frontmatter, titles, tags
│   ├── Utils/        # Colors, fonts, icons
│   ├── Views/
│   │   ├── Editor/   # Live-preview engine, text view, attachments
│   │   ├── Sidebar/  # Notes tree, search panel
│   │   ├── Settings/
│   │   └── FolderOpenView.swift   # Welcome page (first launch)
│   └── Resources/    # Asset catalog, app icon
├── Notely.xcodeproj
├── Tests/            # Standalone test runners
└── Tools/            # make_app_icon.swift — regenerates the app icon
```
