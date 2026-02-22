# Changelog

Format:
- One top-level entry per date in `YYYY-MM-DD` format.
- Bullets describe user-visible behavior changes, platform updates, or notable implementation changes.

## 2026-02-22

- Replaced SwiftUI `Grid` table rendering with a `WKWebView`-based table block renderer on macOS, iOS, and iPadOS.
- Added automatic table block height reporting from web content back to SwiftUI.
- Added horizontal scrolling for wide tables in the embedded table renderer.
- Updated table rendering to preserve explicit line breaks in table cells.
- Added inline backtick rendering in table cells and headers (`code` styling).
- Tuned iOS table typography:
  - Reduced inline code font size for better visual balance.
  - Disabled text inflation in the web table renderer so compact and regular presentations match.
- Iterated table width behavior to avoid clipping/truncation artifacts that appeared in the original SwiftUI table approach.


*Copyright ©2026 Syd Polk. All Rights Reserved.*
