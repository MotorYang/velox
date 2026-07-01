# Changelog

## 1.4.0

### New
- Added a Server Manager entry to the terminal context menu, so saved servers can be managed directly from the default terminal right-click menu.
- Added drag-and-drop ordering for server profiles in Server Manager.
- Added nested folders in Server Manager, including creating subfolders from the folder context menu.
- Added drag-and-drop movement for servers and folders, including moving servers into any folder and moving folders into other folders.

### Fixed
- Fixed Helix (`hx`) and other mouse-aware terminal apps entering unwanted mouse-move selection mode in Velox terminals.

### Changed
- Server profile order is now preserved manually instead of being forced into alphabetical order.
- Server folder data now supports nested folder paths while remaining compatible with existing saved profiles.
