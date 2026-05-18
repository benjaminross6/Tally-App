# Tapp

## What is Tapp?

The Tally App, or "Tapp," is a very useful app where users can store, share, and update tallies. E.g., counting the number of times you used the restroom, or number of swears, or the number of times you thought about the Roman Empire. Furthermore there are a multitude of themes to choose from. That way, you can customize your Tapp as much as you please. It doesn't stop there though. What sets Tapp apart from other tally apps is how you can share tallies with your friends!

Join the Tapp Party Today!

## Tech Stack

- **Platform:** iOS 26.1+
- **Language:** Swift 5.0
- **UI:** SwiftUI (SwiftUI App lifecycle, `@main` in `TappApp.swift`)
- **IDE:** Xcode 26.1.1
- **Backend:** Firebase (FirebaseCore, FirebaseAuth, FirebaseFirestore via SPM 12.x)
- **Bundle ID:** `com.iambenross.tapp`

## Project Structure

```
Tapp/
├── Tapp/
│   ├── TappApp.swift          # @main + FirebaseApp.configure() + RootView auth gate
│   ├── AuthStore.swift        # @Observable auth + profile state (anonymous auth + Firestore)
│   ├── UserProfile.swift      # Codable model for the users/{uid} doc
│   ├── Tally.swift            # Codable model for the tallies/{id} doc
│   ├── TallyStore.swift       # @Observable; live-syncs the user's tallies + add/increment
│   ├── SignupView.swift       # Signup form, calls AuthStore.signUp
│   ├── TalliesView.swift      # Tally list + add-tally alert + sign-out
│   ├── ContentView.swift      # Default Xcode boilerplate, unused (safe to delete)
│   ├── GoogleService-Info.plist
│   └── Assets.xcassets/       # AppIcon, AccentColor
├── TappTests/                 # Stock unit-test scaffold
├── TappUITests/               # Stock UI-test scaffold
└── Tapp.xcodeproj/
```

## Current Status

What's done:

- Xcode project set up (SwiftUI, iOS 26.1)
- App branding + tagline on the signup screen
- Signup UI: name + email fields, regex email validation, disabled-until-valid submit button, inline error messages, loading spinner during submit
- Data model designed (see "Backend" below)
- Firebase SDK installed (FirebaseCore, FirebaseAuth, FirebaseFirestore)
- `FirebaseApp.configure()` wired up in `TappApp.init()`
- `AuthStore` (`@Observable`) tracking `.loading` / `.signedOut` / `.signedIn(profile)`, listening to Firebase auth state
- Signup creates a Firebase anonymous user and writes the matching `users/{uid}` document with `Name`, `Email`, `Joined` (serverTimestamp), and an empty `Tallies` array
- Returning-user auto-login: `RootView` switches on `AuthStore.state`; existing anonymous credential is rehydrated from the keychain and the profile doc is fetched
- `TalliesView`: full-width tally rows (name + count), tap-to-increment, `+` toolbar button opens a name-prompt alert, sign-out moved to the leading toolbar slot
- `TallyStore`: snapshot listener on the user doc → per-tally snapshot listeners → live-updating sorted array (newest first). Tally creation writes `tallies/{id}` and appends the ref to the user's `Tallies` array via `arrayUnion`. Increment uses `FieldValue.increment` atomically.

Still to do:

- Delete tallies (swipe-to-delete / long-press; also remove ref from user's `Tallies`)
- Sharing via link (Universal Links + Associated Domains)
- Settings screen and themes
- Tighten Firestore rules (tallies are currently world-readable to any authenticated user)
- Use of the `Change` field on tallies (schema includes it but increment currently only touches `Count`)
- Migrate from anonymous auth to email-link or password auth so accounts survive reinstall / multi-device

### Auth approach (interim)

The current sign-up flow uses **Firebase Anonymous Auth** to mint a stable `uid`, then writes the profile at `users/{uid}`. This required zero UI changes (no password field) and gives free auto-login on the same device, but the account is tied to that device. Swapping in email-link or password auth later does not change the Firestore data model.

### Required Firebase console setup

Before running, in the [Firebase console](https://console.firebase.google.com) for the `tapp-97904` project:

1. **Authentication → Sign-in method** → enable **Anonymous**.
2. **Firestore Database** must exist (any region is fine).
3. **Firestore → Rules** — starter rules that match the current schema:

   ```js
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{userId} {
         allow read: if request.auth != null;
         allow write: if request.auth != null && request.auth.uid == userId;
       }
       match /tallies/{tallyId} {
         allow read: if request.auth != null;
         allow create: if request.auth != null;
         allow update, delete: if request.auth != null; // tighten before shipping
       }
     }
   }
   ```

## Backend

All users and tallies are stored in Firebase. This is the breakdown of the database:

- `users` — A collection of user documents. Each user document has a unique ID.
  - `Name` : String — Name for a user. Names do not have to be unique.
  - `Email` : String — Email for user. Emails must be one-to-one with User IDs.
  - `Joined` : Timestamp — Date and time user was created.
  - `Tallies` : Array[reference] — An array of references to tally documents in collection `tallies`. Includes tallies that the user owns, and tallies that are merely shared with the user.
- `tallies` — A collection of tally documents. Each tally document has a unique ID.
  - `Name` : String — Name for tally. Names do not have to be unique.
  - `Count` : Number — The number the count is at.
  - `Owner` : Reference — Reference to the user document who created and owns the tally.
  - `Shared With` : Array[reference] — An array of references to user documents in collection `users`. Does not include the owner.
  - `Created` : Timestamp — Date and time tally was created.
  - `Change` : Number — The incrementation of the tally without a global update.

Users share their tallies with a link that they send to their friends (e.g. via text or email). The link leads to the app and adds the tally to that user's `Tallies` array.

## Flow

First time users land on a signup page, prompting their name and email. Users with accounts are auto logged in and land on the tally page. At the top of the tally page is a "settings" button, an "add tally" button, and then the list of tallies. Each tally is a widget spanning the width of the screen, displaying its name and count.

## How to Run

1. Open `Tapp.xcodeproj` in Xcode 26.1 or later.
2. Select an iOS 26.1+ simulator (or a device — automatic code signing is enabled, team `HSQJ946X8B`).
3. Build & run (⌘R).

No package dependencies are checked in yet, so a clean clone should build immediately.

## Next Steps (Suggested Roadmap)

A reasonable order to pick this back up:

1. **Delete tallies.** Swipe-to-delete on the row; on delete, remove the tally doc and `arrayRemove` the ref from the user's `Tallies`. If the tally has `Shared With` users, also remove the ref from each of their `Tallies` arrays (consider a Cloud Function for fan-out).
2. **Sharing.** Generate a Universal Link like `https://tapp.app/t/{tallyId}`. Needs Apple Associated Domains entitlement + an `apple-app-site-association` file hosted on a public domain. On open, append the tally ref to the receiving user's `Tallies` and add their ref to the tally's `Shared With`.
3. **Settings + themes.** Persist theme choice (UserDefaults to start) and apply via an environment value. Move the sign-out button into Settings.
4. **Tighten Firestore rules.** Currently any authenticated user can read/update any tally. Restrict `read` and `update` to the owner + members of `Shared With`. Restrict `delete` to the owner.
5. **Upgrade auth.** Swap anonymous auth for email-link or password auth so accounts survive reinstall / multi-device. The Firestore data model does not change; only `AuthStore.signUp` and the Firebase console settings do.
6. **Cleanup.** Delete `ContentView.swift`, replace the stock test files with real coverage, and consider adding a `.gitignore` (at least `xcuserdata/`).

