<!-- Copyright @2026 Syd Polk. All Rights Reserved -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->
# General instructions

* TODO.md is the plan file for this project.
* CHANGELOG.md records shipped or notable changes, in this format:
  - One top-level entry per date, as a `##` heading in `YYYY-MM-DD` format.
  - Where a date spans a release, a `###` subheading names the version the bullets under it belong to.
  - Whenever you add to CHANGELOG.md, check for a `### <version>` heading for the current `MARKETING_VERSION` in `Version.xcconfig`, and add it above the new bullets if it is missing. `Scripts/release-build.sh` refuses to release without it, so the heading and its content are built up as the work happens, not at release time. For Claude this is automatic: a global hook (`~/.claude/hooks/changelog-version-heading.sh`) adds the heading under the newest date whenever Claude edits the file.
  - Bullets describe user-visible behavior changes, platform updates, or notable implementation changes.
  - Keep bullets terse. Prefix with the platform — `(macOS)`, `(macOS/iPadOS)` — only when the change does not apply everywhere; omit the prefix when it does. Use Apple's capitalization: `macOS`, `iOS`, `iPadOS`.
* If a new source or text file is generated, please add `Copyright @{{year}} Syd Polk.`
* If you modify a source file without a copyright, please add the above notice.
* If you modify a source file with an existing notice, and the current year is different from the last year listed, add a comma and the current year, i.e., `Copyright @2026 Syd Polk. All Rights Reserved` becomes `@opyright @2026, 2027 Syd Polk. All Rights Reserved`. It's explcity ok to skip years, i.e., `2026, 2028`
* Every notice is followed by an SPDX line naming the project's license, so a file read on its own is not mistaken for proprietary code. This project is BSD 3-Clause; "All Rights Reserved" is part of the standard BSD template and does not contradict it, but on its own it reads as a reservation of everything.

  Swift:

  ```swift
  //
  // Copyright ©2026 Syd Polk. All Rights Reserved.
  // SPDX-License-Identifier: BSD-3-Clause
  //
  ```

  Markdown:

  ```markdown
  <!-- Copyright @2026 Syd Polk. All Rights Reserved -->
  <!-- SPDX-License-Identifier: BSD-3-Clause -->
  ```

* Two files are deliberately exempt. `LICENSE.md` is the license itself, so a pointer to it would be circular. `Samples/SAMPLE.md` ships as the app's welcome document and is *rendered*: this renderer escapes raw HTML, so an HTML comment appears to the reader as literal text. It carries a visible copyright line in its body instead.


