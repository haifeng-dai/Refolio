# Refolio

Refolio is a native macOS literature manager with an integrated PDF reader. Version `0.0.1` is the first test release.

## Features

- Manage literature records, folders, attachments, and the Recycle Bin.
- Import metadata from a DOI through Crossref and update an existing item with a field by field comparison.
- Open PDF attachments in the app with multiple reader tabs.
- Save and restore the reading position for each attachment.
- Add text highlights, border only rectangle marks, comments, and Zotero style annotation colors.
- Keep notes shared between the library detail view and the PDF reader.
- Translate selected PDF text through a configurable translation engine registry.

## Data behavior

PDF files are kept as attachments and are not rewritten when annotations are added. Highlights, rectangle marks, comments, notes, metadata, and reading positions are stored in the local SwiftData library.

The current translation providers include Bing, Google, CNKI, Baidu, Youdao Zhiyun, and NiuTrans. Providers that need credentials read them from macOS Keychain; the selected provider is stored locally.

## Requirements

- macOS 27 or later
- Xcode 26.3 or later for building from source

## Build and run

```bash
xcodebuild -project Refolio.xcodeproj -scheme Refolio -configuration Debug \
  -sdk macosx -derivedDataPath /private/tmp/refolio-build \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build

open -n /private/tmp/refolio-build/Build/Products/Debug/Refolio.app
```

The Debug build seeds sample records only when the local library is empty. Existing library data is not replaced by the sample data.

## Current limitations

- The AI reader panel is a placeholder.
- Text highlight geometry depends on the text layer supplied by the PDF. Scanned pages without a text layer are not OCR processed.
- This is a test release. PDF annotation persistence, translation providers, and file access should be validated with the user's real library before relying on them.

See [ARCHITECTURE.md](ARCHITECTURE.md) for module ownership, data relationships, workflows, and extension boundaries.
