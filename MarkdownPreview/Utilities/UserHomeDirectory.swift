//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

/// The user's real home directory, for abbreviating displayed paths to `~`.
///
/// `NSHomeDirectory()` and `FileManager.homeDirectoryForCurrentUser` both return
/// the *container* in a sandboxed app, so a document at `~/Documents/note.md`
/// stops matching and is displayed as its full absolute path. Finder and the rest
/// of the system still call that folder `~`, so the app should too.
///
/// `getpwuid` reads the account's directory service record rather than the
/// process environment, which the sandbox does not rewrite. On iOS the container
/// *is* the home directory and `NSHomeDirectory()` is already correct.
enum UserHomeDirectory {

    /// Fixed for the life of the process, so it is resolved once.
    static let path: String = {
        #if os(macOS)
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            let path = String(cString: directory)
            if !path.isEmpty {
                return path
            }
        }
        // Falling back leaves paths unabbreviated rather than wrong, which is the
        // better failure for something purely cosmetic.
        return NSHomeDirectory()
        #else
        return NSHomeDirectory()
        #endif
    }()
}
