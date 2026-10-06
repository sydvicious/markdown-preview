<!-- Copyright @2026 Syd Polk. All Rights Reserved -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# Introduction

I worked on a Mac App called Klink. It was analogous to Dropbox or Box or other services
that would sync files to the cloud.

Like other clients, there was a folder that automatically synced, the Klink folder. What
made Klink different was that, as long as it was in your home directory, you could
add anything to your sync set, not just files in your Klink folder.

This presented challenges. Users could move those folders or files around, or rename them,
and we were expected to track that.

# Solution

- I added an extended attribute to any Klinked-files or folders, com.klink.klinkapp.fileID, 
which was simply the value of the fileId/inode number of the file.
- When we detected that the file had changed or disappeared (that mechanism is not important),
I would do a spotlight search for the value of the fileId.
- I would process the results of that search as follows:
-- If the search returned no files, then the file/folder disappeared and I would remove
it from the synced set.
-- I would then iterate all of the returned results, and find the one whose fileId matched
the extended attribute. This is the orignal file. I would then note the new path name and file
name the asset was, and update the syncing for it. I would remove the extended attirbutes
of assets that did not match.

This caught the following cases:
- File disappeared for real
- The asset was moved around in the file system.
- The asset was renamed.
- The asset was duplicated.

# MarkdownPreview

I want the same tracking for files that we are tracking in MarkdownPreview. When the app
opens, when it comes to the front, and on its timers (every second for the file showing,
every ten seconds for the rest of the list), if we can find the file, we update where we
think it is, and update the list to reflect it. If not, we remove it from the list.

MarkdownPreview does this with bookmarks, not with an extended attribute. Each file in the
list is held by a security-scoped bookmark, which the app keeps in its own saved list. A
bookmark records the file's full path and its fileId, and finds the file by its fileId when
nothing is at the path. That catches the same cases as above, and:

- Nothing is written to the files.
- It does not depend on Spotlight.
- In the sandbox, the bookmark is also what lets the app read the file where it is now. A
path found by a Spotlight search carries no such permission. (Not tested.)
- It works on iOS.

What bookmarks do not do, and the extended attribute could with a looser match: follow a
file that was copied to another volume, or one that was moved and then rewritten under a
new fileId before the app looked.

A bookmark looks at the full path first. If a file is there, it is the file. Editors that
save atomically write a new file and rename it over the old one, so the fileId changes
while the full path stays the same, and the bookmark still finds it.

So the path wins whenever a file is there when the app looks. After
`mv foo.md foo-old.md; cat > foo.md`, the new `foo.md` is the tracked file. If the app
looks between the two commands, nothing is at the path, so it follows the file to
`foo-old.md`, and the new `foo.md` is a file of its own.

Caveats:

- If the file that is showing is moved to the Trash, put up the alert, and then remove it
from the list. If another file in the list is moved to the Trash, remove it from the list
silently.
- If the file was on a removable drive and is no longer available, we should go ahead
and remove it from the list.

Open question(s):

- Don't know if we should do this for iOS. I don't think we should. The tracking is in
code both platforms share, so iOS does it today.
