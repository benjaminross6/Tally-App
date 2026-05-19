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

```text
Tapp/
├── Tapp/
│   ├── TappApp.swift              # @main + FirebaseApp.configure() + RootView auth gate + .onOpenURL
│   ├── AuthStore.swift            # @Observable email-link auth, profile load, change-name/username/email, delete account
│   ├── EmailLinkHandler.swift     # Action-code URL + UserDefaults for "pending signup / login email"
│   ├── UserProfile.swift          # Codable model for users/{uid}
│   ├── UsernameClaim.swift        # Transactional claim/release/rename on usernames/{name}
│   ├── UserDirectory.swift        # @Observable uid -> (name, username) cache
│   ├── FriendsStore.swift         # @Observable friends array + add/remove (mutual)
│   ├── Tally.swift                # Codable model + TallyRole permissions helpers
│   ├── TallyStore.swift           # @Observable; live-syncs tallies + add/increment/setCount/rename/setPermissions/delete/removeFromMyList
│   ├── LocalTallyColors.swift     # Per-device color storage (UserDefaults)
│   ├── ColorPickerSheet.swift     # 12-swatch palette + Default
│   ├── PermissionsSheet.swift     # 3-column friends-permissions table + AvatarBadge
│   ├── ShakeModifier.swift        # Horizontal-shake GeometryEffect (view-only tap feedback)
│   ├── SignupView.swift           # Name + Username + Email → email-link send
│   ├── LoginView.swift            # Returning-user email-link request
│   ├── AwaitingLinkView.swift     # "Check your email" interstitial
│   ├── TalliesView.swift          # Home page: list, owner badge, lock, long-press → FullScreenTallyView
│   ├── FullScreenTallyView.swift  # Per-tally screen: name/count editors + bottom button row
│   ├── SettingsView.swift         # Account/Friends/Preferences + Log Out + Delete Account
│   ├── GoogleService-Info.plist   # gitignored — provide your own (see Getting Started)
│   └── Assets.xcassets/           # AppIcon, AccentColor
├── TappTests/                     # Stock unit-test scaffold
├── TappUITests/                   # Stock UI-test scaffold
└── Tapp.xcodeproj/
```

## Current Status

What's done:

- Xcode project set up (SwiftUI, iOS 26.1)
- Firebase SDK installed (FirebaseCore, FirebaseAuth, FirebaseFirestore)
- `FirebaseApp.configure()` wired up in `TappApp.init()`
- **Email-Link (passwordless) auth.** Signup collects Name + Username + Email, sends a sign-in link; `TappApp.onOpenURL` completes the sign-in and creates the `users/{uid}` doc on first open. `LoginView` lets returning users on a fresh install request a new link.
- **Username claim.** Unique lowercase `[a-z0-9_]{3,20}` handles, enforced via the `usernames/{name}` collection in a Firestore transaction. Used by the Add Friend lookup.
- `AuthStore` tracks `.loading` / `.signedOut` / `.awaitingEmailLink(email, isSignup)` / `.signedIn(profile)`. Exposes `changeName`, `changeUsername`, `changeEmail`, `signOut`, and `deleteAccount` (full cascade).
- **Home page.** Gear (top-right) → Settings; full-width Add Tally (+) modal with a 3-column friend/permission table; tally rows show owner avatar + username + lock icon for view-only users + local color tint. Tap to increment, long-press (400ms with light haptic) to push the Full Screen Tally.
- **Full Screen Tally.** Back chevron + swipe-down dismiss; long-press name / count to edit; tap anywhere above the bottom button row to increment; bottom row buttons for Color, Friends & Permissions (owner-only), and Delete (label switches between "Delete tally" for owners and "Remove from my list" for non-owners).
- **Color picker.** 12-swatch palette + Default; stored in UserDefaults under `tapp.tallyColorIndex.<tallyId>`. Local only; never written to Firestore.
- **Friends.** `FriendsStore` keeps the user's `Friends` array live; Add Friend looks the username up via `usernames/{name}` and mutually arrayUnion's both users; Remove Friend mutually arrayRemove's and cascades the removed user out of every tally they shared with the current user (in either direction).
- **Settings.** Inline editors for Username (uniqueness checked via transaction), Name, and Email (Firebase `sendEmailVerification(beforeUpdatingEmail:)`); Friends list with swipe-to-remove + Add Friend; Log Out (confirm); Delete Account (red, double-confirm, full cascade).
- `TallyStore`: snapshot listener on the user doc → per-tally snapshot listeners → live-updating array sorted by `LastUpdated` (then `Created`). Writes maintain `LastUpdated` / `LastUpdatedBy`. Increment uses `FieldValue.increment` atomically.
- `UserDirectory`: app-wide cache of uid → (Name, Username) used to render owner badges and friend rows without re-fetching.

Still to do (next phase):

- Sort cycle button (newest / oldest / last-updated / my tallies only) and persisted choice
- "Recent updater" avatar flash on launch
- Reset schedules (off / now / daily / monthly / yearly) + best-effort client-side reset on next touch
- Fireworks toggle + animation in the row and full screen, with Reduce Motion fallback
- Number-type cycle (Arabic / Roman / Stick) using a render helper applied everywhere a count is shown
- Theme cycle (System / Light / Dark) wired to `.preferredColorScheme`
- Full VoiceOver custom actions for the long-press gestures
- AvatarColor persisted on the user doc (today it's derived from the uid hash on the client)

### Auth approach

The app uses **Firebase Email-Link (passwordless) auth**. Signup sends a one-time sign-in link to the user's email; tapping it opens the app, completes auth, and writes the `users/{uid}` doc on first sign-in. Returning users on a fresh install do the same via `LoginView`. See "Email-Link Auth Setup" in [Getting Started](#5-configure-firebase-services).

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

1. **Authentication → Sign-in method** → enable **Email/Password**, then turn on **Email link (passwordless sign-in)** in the same provider's settings.
2. **Firestore Database → Create database** (any region; production mode is fine — you set rules below).
3. **Firestore → Rules** → paste and **Publish**:

   ```js
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {

       // users/{uid}
       //   readable by any signed-in user (needed for owner badges + friend rows)
       //   fully writable only by the owner
       //   anyone signed-in may update only `Friends` or `Tallies` so mutual
       //     arrayUnion/arrayRemove from Add Friend / Add Tally works
       match /users/{userId} {
         allow read: if request.auth != null;
         allow create, delete: if request.auth != null && request.auth.uid == userId;
         allow update: if request.auth != null && (
           request.auth.uid == userId ||
           request.resource.data.diff(resource.data).affectedKeys().hasOnly(['Friends', 'Tallies'])
         );
       }

       // usernames/{name} — uniqueness ledger
       //   readable by any signed-in user (Add Friend lookup)
       //   writable only by the user who owns the claim
       match /usernames/{name} {
         allow read: if request.auth != null;
         allow create: if request.auth != null
           && request.resource.data.uid == request.auth.uid;
         allow update: if request.auth != null
           && request.resource.data.uid == request.auth.uid
           && (resource == null || resource.data.uid == request.auth.uid);
         allow delete: if request.auth != null
           && resource.data.uid == request.auth.uid;
       }

       // tallies/{id}
       //   readable by Owner + anyone in Shared With
       //   updatable by Owner + anyone in Shared With (the UI gates view-only writes)
       //   deletable only by Owner
       match /tallies/{tallyId} {
         function isOwner() {
           return request.auth != null
             && resource.data.Owner == /databases/$(database)/documents/users/$(request.auth.uid);
         }
         function isShared() {
           return request.auth != null
             && resource.data['Shared With'].hasAny([
                  /databases/$(database)/documents/users/$(request.auth.uid)
                ]);
         }
         allow create: if request.auth != null
           && request.resource.data.Owner == /databases/$(database)/documents/users/$(request.auth.uid);
         allow read, update: if isOwner() || isShared();
         allow delete: if isOwner();
       }
     }
   }
   ```

### 5b. Email-Link Auth Setup

Email-link auth uses Firebase's action URL (`EmailLinkConfig.actionURL` in [Tapp/EmailLinkHandler.swift](Tapp/EmailLinkHandler.swift)). For this project that's already set to `https://tapp-97904.firebaseapp.com/__/auth/action`.

1. **Firebase console → Authentication → Sign-in method** → enable **Email/Password**, then turn on **Email link (passwordless sign-in)**.
2. **Authentication → Settings → Authorized domains** — the default domains (`tapp-97904.firebaseapp.com`, `tapp-97904.web.app`) should already be listed.

**Free Apple Personal Team (no $99 developer account):**

Personal teams **cannot** use Associated Domains / Universal Links. The app supports this with a **paste-link fallback** on the "Check your email" screen:

1. Build & run on your physical iPhone (select it in Xcode's device menu, then ⌘R).
2. Sign up or log in and tap **Send Sign-Up Link** / **Send Sign-In Link**.
3. Open the email on the same phone.
4. **Long-press the sign-in button or link → Copy Link** (don't just tap it — that opens Safari).
5. Switch back to Tapp, paste into **Sign-in link**, tap **Continue**.

**Paid Apple Developer Program (tap link opens app directly):**

1. Add **Associated Domains** to the Tapp target: `applinks:tapp-97904.firebaseapp.com` (via Signing & Capabilities or a `Tapp.entitlements` file).
2. Build to a physical device. Tapping the link in Mail should open Tapp automatically.

### 6. Build and run

1. Connect your iPhone, select it in Xcode's toolbar device menu (not a simulator).
2. Build & run (⌘R). If prompted, trust the developer certificate on the phone under **Settings → General → VPN & Device Management**.
3. Sign up with name + username + email → **Send Sign-Up Link** → copy the link from Mail → paste on the **Check your email** screen → **Continue** → you're on the tally list.

## Backend Schema

All users and tallies live in Firestore. Field names use the casing in the documents (some have spaces; that's preserved by the Swift model's `CodingKeys`).

- `users` — collection of user documents (id = Firebase Auth `uid`):
  - `Name` : String — display name (1-40 chars).
  - `Username` : String — unique, lowercase `[a-z0-9_]{3,20}`. Mirrored from `usernames/{username}.uid`.
  - `Email` : String — user-entered email.
  - `Joined` : Timestamp — server time at signup.
  - `Tallies` : Array[reference] — refs to documents in `tallies`. Includes tallies the user owns and tallies shared with them.
  - `Friends` : Array[reference] — mutual refs to other `users` documents.
- `tallies` — collection of tally documents:
  - `Name` : String — tally name (≤ 40 chars).
  - `Count` : Number — current count, signed.
  - `Owner` : Reference — ref to the user who created the tally.
  - `Shared With` : Array[reference] — refs to users the tally is shared with (does not include the owner).
  - `Permissions` : Map<String, String> — `uid -> "view" | "edit"`. Owner is implicit and is not present in this map.
  - `Created` : Timestamp — server time at creation.
  - `LastUpdated` : Timestamp — server time of the most recent write to any field on this tally.
  - `LastUpdatedBy` : Reference — ref to the user who made the most recent write.
- `usernames` — uniqueness ledger keyed by `Username`:
  - `uid` : String — Firebase Auth uid that owns this username.

Per-device, never written to Firestore:

- `tapp.tallyColorIndex.<tallyId>` (UserDefaults Int) — selected palette index for that tally on this device. Absent = "Default" (`Color.accentColor`).
- `tapp.pendingSignup` / `tapp.pendingLoginEmail` (UserDefaults) — handoff between **Send link** and **Open link**.

## Roadmap

A reasonable order to extend this beyond the current state:

1. **Sort cycle and "recent updater" avatars** on the home page (newest / oldest / last-updated / my tallies only; transient avatar flash on cold launch driven by `LastUpdated > lastSeenTallyUpdates[id]`).
2. **Reset schedules.** UI sheet (off / now / daily / monthly / yearly) + best-effort client-side reset when `NextResetAt` has passed on next tally write.
3. **Fireworks.** `FireworksEnabled` toggle on the tally; fire the animation on every increment in both Full Screen Tally and the home row. Honor Reduce Motion.
4. **Number-type cycle.** Render `Count` via Arabic / Roman / Stick selectable in Settings.
5. **Theme cycle.** System / Light / Dark wired to `.preferredColorScheme`.
6. **VoiceOver custom actions** for every long-press gesture.

## Contributing

Issues and pull requests welcome. Please keep changes focused — for anything non-trivial, open an issue first to discuss the approach.

## License

[MIT](./LICENSE) © Ben Ross
