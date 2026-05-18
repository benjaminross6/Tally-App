# Tapp

The Tally App, or "Tapp," is a SwiftUI iOS app where users can store, share, and update tallies — for example, counting the number of times you used the restroom, the number of swears you let slip, or how often you thought about the Roman Empire. What sets Tapp apart from other tally apps is sharing: send a link to a friend and your tally syncs between you.

Join the Tapp Party Today!

## Tech Stack

- **Platform:** iOS 26.1+
- **Language:** Swift 5.0
- **UI:** SwiftUI (SwiftUI App lifecycle, `@main` in `TappApp.swift`)
- **IDE:** Xcode 26.1.1+
- **Backend:** Firebase (FirebaseCore, FirebaseAuth, FirebaseFirestore via SPM 12.x)

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
│   ├── GoogleService-Info.plist  # gitignored — provide your own (see Getting Started)
│   └── Assets.xcassets/       # AppIcon, AccentColor
├── TappTests/                 # Stock unit-test scaffold
├── TappUITests/               # Stock UI-test scaffold
└── Tapp.xcodeproj/
```

## Current Status

What's done:

- Xcode project set up (SwiftUI, iOS 26.1)
- Signup UI: name + email fields, regex email validation, disabled-until-valid submit button, inline error messages, loading spinner during submit
- Firebase SDK installed (FirebaseCore, FirebaseAuth, FirebaseFirestore)
- `FirebaseApp.configure()` wired up in `TappApp.init()`
- `AuthStore` (`@Observable`) tracking `.loading` / `.signedOut` / `.signedIn(profile)`, listening to Firebase auth state
- Signup creates a Firebase anonymous user and writes `users/{uid}` with `Name`, `Email`, `Joined` (serverTimestamp), and an empty `Tallies` array
- Returning-user auto-login: `RootView` switches on `AuthStore.state`; existing anonymous credential is rehydrated from the keychain and the profile doc is fetched
- `TalliesView`: full-width tally rows (name + count), tap-to-increment, `+` toolbar button opens a name-prompt alert, sign-out in the leading toolbar slot
- `TallyStore`: snapshot listener on the user doc → per-tally snapshot listeners → live-updating sorted array (newest first). Tally creation writes `tallies/{id}` and appends the ref to the user's `Tallies` via `arrayUnion`. Increment uses `FieldValue.increment` atomically.

Still to do:

- Delete tallies (swipe-to-delete; also remove ref from user's `Tallies`)
- Sharing via link (Universal Links + Associated Domains)
- Settings screen and themes
- Tighten Firestore rules (tallies are currently readable/updatable by any authenticated user)
- Decide what the `Change` field means and wire it up (schema reserves it; the app currently writes `0` and never updates it)
- Migrate from anonymous auth to email-link or password auth so accounts survive reinstall / multi-device

### Auth approach (interim)

The current sign-up flow uses **Firebase Anonymous Auth** to mint a stable `uid`, then writes the profile at `users/{uid}`. This required zero UI changes (no password field) and gives free auto-login on the same device, but the account is tied to that device. Swapping in email-link or password auth later does not change the Firestore data model.

## Getting Started

This project does not ship with a `GoogleService-Info.plist` — you need your own Firebase project to run it.

### 1. Clone

```bash
git clone https://github.com/benjaminross6/Tally-App.git
cd Tally-App
```

### 2. Create a Firebase project

1. Go to <https://console.firebase.google.com> and click **Add project**. Analytics is optional.
2. Once created, click the iOS+ icon ("Add app").
3. Choose any bundle ID you like (reverse-DNS, e.g. `com.yourname.tapp`). You'll use this same value in Xcode.
4. Download the generated `GoogleService-Info.plist`.

### 3. Add the plist to the Xcode project

1. Drop `GoogleService-Info.plist` into the `Tapp/` folder (next to `TappApp.swift`).
2. The Xcode project uses file-system synchronized groups, so the file is picked up automatically — no drag-into-Xcode step required.
3. The file is gitignored, so it stays local to you.

### 4. Match the bundle ID in Xcode

1. Open `Tapp.xcodeproj`.
2. Select the **Tapp** target → **Signing & Capabilities** → set **Bundle Identifier** to the value you used in Firebase.
3. Repeat the rename for `TappTests` (e.g. `<your-bundle-id>Tests`) and `TappUITests` (e.g. `<your-bundle-id>UITests`).
4. Under **Signing**, pick your own development team. Automatic signing is on.

### 5. Configure Firebase services

In the [Firebase console](https://console.firebase.google.com) for your project:

1. **Authentication → Sign-in method** → enable **Anonymous**.
2. **Firestore Database → Create database** (any region; production mode is fine — you set rules below).
3. **Firestore → Rules** → paste and **Publish**:

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

### 6. Build and run

1. Pick an iOS 26.1+ simulator (or a real device).
2. Build & run (⌘R).
3. First launch lands on the signup screen. Enter a name + email → Sign Up → you're on the tally list. Tap **+** to create a tally; tap a row to increment.

## Backend Schema

All users and tallies live in Firestore:

- `users` — collection of user documents (id = Firebase Auth `uid`):
  - `Name` : String — display name.
  - `Email` : String — user-entered email.
  - `Joined` : Timestamp — server time at signup.
  - `Tallies` : Array[reference] — refs to documents in `tallies`. Includes tallies the user owns and tallies shared with them.
- `tallies` — collection of tally documents:
  - `Name` : String — tally name.
  - `Count` : Number — current count.
  - `Owner` : Reference — ref to the user who created the tally.
  - `Shared With` : Array[reference] — refs to users the tally is shared with (does not include the owner).
  - `Created` : Timestamp — server time at creation.
  - `Change` : Number — reserved for future use (see roadmap).

Sharing flow (planned): an owner generates a link, the recipient opens it on a device with Tapp installed, the app appends the tally ref to the recipient's `Tallies` and adds the recipient's ref to the tally's `Shared With`.

## Roadmap

A reasonable order to extend this:

1. **Delete tallies.** Swipe-to-delete on the row; on delete, remove the tally doc and `arrayRemove` the ref from the user's `Tallies`. If the tally has `Shared With` users, also remove the ref from each of their `Tallies` arrays (consider a Cloud Function for fan-out).
2. **Sharing.** Generate a Universal Link like `https://tapp.app/t/{tallyId}`. Needs Apple Associated Domains entitlement + an `apple-app-site-association` file hosted on a public domain. On open, append the tally ref to the receiving user's `Tallies` and add their ref to the tally's `Shared With`.
3. **Settings + themes.** Persist theme choice (UserDefaults to start) and apply via an environment value. Move the sign-out button into Settings.
4. **Tighten Firestore rules.** Restrict tally `read` and `update` to the owner + members of `Shared With`; restrict `delete` to the owner.
5. **Upgrade auth.** Swap anonymous auth for email-link or password auth so accounts survive reinstall / multi-device. The Firestore data model does not change; only `AuthStore.signUp` and the Firebase console settings do.

## Contributing

Issues and pull requests welcome. Please keep changes focused — for anything non-trivial, open an issue first to discuss the approach.

## License

[MIT](./LICENSE) © Ben Ross
