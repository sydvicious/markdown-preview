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

I want to do this for files that we are tracking in MarkdownPreview. When the app opens,
or we get notification that the filesystem around the file has changed, if we can find
it, we update where we think it is, and update list to reflect it. If not, we remove it
from the list.

Caveats: 

- If the file ends up in the Trash, we should go ahead and remove it from our list.
- If the file was on a removable drive and is no longer available, we should go ahead 
and remove it from the list.

Open question(s):

- Don't know if we should do this for iOS. I don't think we should.

