# Tapp

The Tally App, or "Tapp," is a SwiftUI iOS app where users can store, share, and update tallies — for example, counting the number of times you used the restroom, the number of swears you let slip, or how often you thought about the Roman Empire. What sets Tapp apart from other tally apps is sharing: add a friend by username and your tallies sync between you.

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
│   ├── TappApp.swift              # @main, Firebase configure, RootView auth gate, theme
│   ├── AuthStore.swift            # Username/password auth, profile, account mutations
│   ├── UserProfile.swift          # Codable model for users/{uid}
│   ├── UsernameClaim.swift        # usernames/{name} uniqueness ledger
│   ├── UserDirectory.swift        # uid → (name, username, avatar color) cache
│   ├── FriendsStore.swift         # Friends array + add/remove (mutual)
│   ├── Tally.swift                # Codable model + TallyRole helpers
│   ├── TallyStore.swift           # Live-sync tallies + writes + scheduled resets
│   ├── TallyListPreferences.swift # Per-user sort toggle (UserDefaults)
│   ├── TallyLastSeenStore.swift   # Landing avatar flash state
│   ├── LocalTallyColors.swift     # Per-device tally colors (UserDefaults)
│   ├── ColorPickerSheet.swift     # 12-swatch palette + Default
│   ├── PermissionsSheet.swift     # Friends/permissions table + AvatarBadge
│   ├── CountFormatter.swift       # Arabic / Roman number rendering
│   ├── StickTallyView.swift       # Custom tally-mark groups (stick number type)
│   ├── FireworksOverlay.swift     # Increment + landing fireworks (Reduce Motion aware)
│   ├── TallyResetSheet.swift      # Off / now / daily / monthly / yearly resets
│   ├── TallyResetDates.swift      # Local-midnight reset scheduling helpers
│   ├── UserPreferences.swift      # NumberType + Theme cycling
│   ├── TappDesignMetrics.swift    # Visual spec constants
│   ├── TallyAccessibility.swift   # VoiceOver labels + row custom actions
│   ├── ColorContrast.swift        # WCAG AA palette validation
│   ├── ShakeModifier.swift        # View-only tap feedback
│   ├── SignupView.swift           # Name + Username + Password signup
│   ├── LoginView.swift            # Username + Password login
│   ├── TalliesView.swift          # Home: list, sort, landing effects, fireworks
│   ├── FullScreenTallyView.swift  # Full-screen tally + per-tally settings
│   ├── SettingsView.swift         # Account, friends, numbers, theme, log out
│   ├── AvatarColorAssignment.swift
│   ├── GoogleService-Info.plist   # gitignored — provide your own
│   └── Assets.xcassets/
├── TappTests/
├── TappUITests/
└── Tapp.xcodeproj/
```

## Current Status

Implemented:

- **Username + password auth.** Signup: Name, Username, Password (Firebase uses a synthetic email `username@tapp.users` under the hood; users never type an email at signup). Login sheet for returning users. `AuthStore` exposes `changeName`, `changeUsername`, `changeEmail`, `changePassword`, `signOut`, `deleteAccount`.
- **Username claim** via `usernames/{name}` (transactional).
- **Home page.** Settings gear; sort toggle (**Last updated** vs **Created**, persisted per user); Add Tally modal with permissions table; tally rows with owner avatar, lock for view-only, local color tint, tap to increment, long-press for full screen. Landing: updater avatar flash + optional fireworks (max 3 concurrent).
- **Full Screen Tally.** Increment area; long-press name/count to edit; bottom row: Color, Friends & Permissions, Resets, Fireworks, Delete (owner vs non-owner labels).
- **Resets.** Off / reset now / daily / monthly / yearly; client applies overdue resets on the next tally write.
- **Fireworks.** Per-tally toggle; plays on increment (row + full screen) and on landing when enabled; Reduce Motion → sparkle fade.
- **Numbers & theme.** Settings cycles Arabic → Roman → Stick and System → Light → Dark; applies app-wide (`.preferredColorScheme` for theme; `CountFormatter` / `StickTallyView` for counts).
- **Friends.** Add by username (instant mutual); remove cascades shared tallies.
- **Accessibility.** VoiceOver labels on icon buttons; custom actions for Increment, Open Full Screen Tally, Edit Name, Edit Count; Dynamic Type on full-screen count; WCAG AA contrast on palette tints.
- **Visual spec.** Row height 88pt, 36pt circular controls, 56pt add button, etc. (`TappDesignMetrics`).

### Auth approach

The app uses **Firebase Email/Password** with a **synthetic email** derived from the username (`username@tapp.users`). Users only see username + password in the UI. Changing username updates the synthetic email in Firebase Auth. Settings still exposes **Email** for users who want to attach a real address via Firebase `updateEmail`.

## Getting Started

This project does not ship with a `GoogleService-Info.plist` — you need your own Firebase project.

### 1. Clone

```bash
git clone https://github.com/benjaminross6/Tally-App.git
cd Tally-App
```

### 2. Create a Firebase project

1. Go to <https://console.firebase.google.com> and create a project.
2. Add an iOS app with your bundle ID (e.g. `com.yourname.tapp`).
3. Download `GoogleService-Info.plist`.

### 3. Add the plist

Place `GoogleService-Info.plist` in the `Tapp/` folder next to `TappApp.swift` (file-system synchronized groups pick it up automatically). The file is gitignored.

### 4. Bundle ID and signing

Open `Tapp.xcodeproj`, set the **Tapp** target bundle ID to match Firebase, pick your development team, and repeat for test targets if needed.

### 5. Configure Firebase

1. **Authentication → Sign-in method** → enable **Email/Password** (email link / passwordless is **not** required).
2. **Firestore** → create database → publish rules (below).

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /users/{userId} {
      allow read: if request.auth != null;
      allow create, delete: if request.auth != null && request.auth.uid == userId;
      allow update: if request.auth != null && (
        request.auth.uid == userId ||
        request.resource.data.diff(resource.data).affectedKeys().hasOnly(['Friends', 'Tallies'])
      );
    }

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

### 6. Build and run

1. Open the project in Xcode, select a simulator or device, ⌘R.
2. **Create Account** with name, username, and password — or **Log in** if you already have an account.

## Backend Schema

Firestore field names match Swift `CodingKeys` (some use spaces).

### `users/{uid}`

- `Name`, `Username`, `Email` (synthetic or user-updated)
- `Joined`, `Tallies[]`, `Friends[]`
- `NumberType` (`arabic` | `roman` | `stick`)
- `Theme` (`system` | `light` | `dark`)
- `AvatarColor` (hex, assigned at signup)

### `tallies/{id}`

- `Name`, `Count`, `Owner`, `Shared With[]`, `Permissions` map
- `Created`, `LastUpdated`, `LastUpdatedBy`
- `FireworksEnabled`, `ResetSchedule`, `NextResetAt`

### `usernames/{username}`

- `uid`

### Device-only (UserDefaults)

- `tapp.tallyColorIndex.<tallyId>` — local row tint
- `tapp.sortEnabled.<userId>` — home sort: last updated vs created
- `tapp.lastSeenTallyUpdates.<userId>.<tallyId>` — landing updater avatar

## Roadmap

Possible future work:

- Forgot-password / account recovery flow on the login screen
- Server-side reset scheduler (today resets are best-effort on client write)
- Broader UI test coverage

## Contributing

Issues and pull requests welcome. For non-trivial changes, open an issue first.

## License

[MIT](./LICENSE) © Ben Ross
