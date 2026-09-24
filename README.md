# Refolio

Refolio is a native macOS literature manager with an integrated PDF reader.

## Project organization

- `Refolio/App` contains app entry points and dependency assembly.
- `Refolio/Features` groups user-facing UI and state by feature.
- `Refolio/Application` contains workflows that coordinate user actions.
- `Refolio/Domain` contains business interfaces and, when useful, storage-independent types.
- `Refolio/Data` contains local persistence and file-storage implementations.
- `Refolio/Integrations` contains DOI and other online metadata clients.
- `Refolio/Resources` contains asset catalogs and localized resources.
- `Refolio/Shared` contains only code genuinely shared across features.

See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership rules and dependency direction. An item is the library record; PDFs and other files are attachments linked to that record. Reading position and notes belong to the item and, where relevant, a specific attachment.

Folders are collection-style groupings. An item can be included in multiple folders without duplicating its record. Items moved to the Recycle Bin remain recoverable.

## Initial product workflow

Create an item manually or from a DOI, attach a PDF, read it, restore the last reading position, and add notes. PDF drag-in parsing and other metadata services can be added as additional ways to create or enrich items later.
