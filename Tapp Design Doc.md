# Tapp Design Doc

## Overview

Tapp is a social tally app for iPhone. You make tallies — for the times you used the restroom, the times you swore, the times you thought about the Roman Empire — and you share them with friends. It is colorful, and there is a fireworks animation. Tapp is for people who enjoy keeping track of things, alone or together. It is a fun app; it does not send notifications.

There is no search anywhere in the app. If you have a lot of friends or tallies, you can find them on your own.

### Platform and stack

- **Platform:** iOS 26.1+, iPhone only, portrait orientation.
- **Language / UI:** Swift 5, SwiftUI.
- **Backend:** Firebase (Auth + Firestore). Realtime sync via Firestore snapshot listeners.
- **Offline:** Firestore's default offline cache. Writes made offline are queued and flushed on reconnect.

### Out of scope (deliberately)

- **No push or in-app notifications.**
- **No search.** Not for friends, tallies, or anything else.
- **No concurrency safeguard for simultaneous updates.** Increments are atomic (they sum), but for non-count fields (name, schedule, fireworks toggle, permissions) the last write wins. If two friends update the tally at the same time, it happens; the app does not surface conflicts.
- **No share-by-link / Universal Links.** Sharing happens exclusively by friending plus per-tally permissions.

## Data Model

Stored in Firestore. Fields use the casing already present in the codebase.

### `users/{uid}`

- `Name` : String — display name shown next to the user in friends and tally owner rows.
- `Username` : String — unique, lowercase, `[a-z0-9_]{3,20}`. Claimed at signup. Used by friends to add you. Unique across all users.
- `Email` : String — synthetic `username@tapp.users` at signup; may be changed later in Settings to a real address.
- `Joined` : Timestamp — server time at signup.
- `Tallies` : Array<Reference> — refs to documents in `tallies`. Includes tallies the user owns and tallies shared with them.
- `Friends` : Array<Reference> — refs to other `users` documents.
- `NumberType` : String — one of `arabic` | `roman` | `stick`. Default: `arabic`. Account-wide; applies to every tally this user sees.
- `Theme` : String — one of `system` | `light` | `dark`. Default: `system`.
- `AvatarColor` : String — hex color used as the background of the user's monogram avatar. Assigned at signup from a fixed palette; not user-editable.

### `tallies/{tallyId}`

- `Name` : String — tally name. ≤ 40 characters.
- `Count` : Int64 — current count. Can be negative.
- `Owner` : Reference — ref to the user who created the tally.
- `Shared With` : Array<Reference> — refs to users the tally is shared with (does not include the owner). (Firestore field name includes a space.)
- `Permissions` : Map<String, String> — `uid` → `"view"` | `"edit"`. Owner is implicit and not present in the map. A user in `SharedWith` must have an entry here.
- `Created` : Timestamp — server time at creation.
- `LastUpdated` : Timestamp — server time of the most recent write to any field on this tally.
- `LastUpdatedBy` : Reference — ref to the user who made the most recent write.
- `FireworksEnabled` : Bool — when true, increments fire the fireworks animation for every user who has this tally. Default: false.
- `ResetSchedule` : String — one of `off` | `daily` | `monthly` | `yearly`. Default: `off`.
- `NextResetAt` : Timestamp? — server-computed next scheduled reset; null when `ResetSchedule == off`.

### Stored only on the device (UserDefaults)

- `tapp.tallyColorIndex.<tallyId>` : Int — palette swatch index for this tally on this device (`nil`/absent = Default accent). Not synced.
- `tapp.sortEnabled.<userId>` : Bool — when true, home list sorts by `LastUpdated` (desc); when false, by `Created` (desc).
- `tapp.lastSeenTallyUpdates.<userId>.<tallyId>` : Timestamp — last `LastUpdated` the user saw; drives the landing updater-avatar flash.

## Permissions

Three roles per tally. Owner is the user in `Owner`; edit and view come from `Permissions`.

| Action                                | View | Edit | Owner |
|---------------------------------------|:----:|:----:|:-----:|
| See tally on home page                |  ✓   |  ✓   |   ✓   |
| Tap to increment count                |      |  ✓   |   ✓   |
| Long-press to edit count              |      |  ✓   |   ✓   |
| Rename                                |      |  ✓   |   ✓   |
| Pick local color                      |  ✓   |  ✓   |   ✓   |
| Edit per-tally permissions table      |      |      |   ✓   |
| Set reset schedule / reset now        |      |      |   ✓   |
| Toggle fireworks                      |      |      |   ✓   |
| Delete tally for everyone             |      |      |   ✓   |
| Remove tally from own list            |  ✓   |  ✓   |       |

When a user has view-only access, the tally row shows a lock icon, taps on the row are a no-op with a small horizontal shake animation, and the full-screen tally hides all owner-only buttons.

## Navigation

Three screens; entered top-down.

```
Signup / Login  →  Home  ⇄  Full Screen Tally
                    ↓
                  Settings
```

- **Home → Full Screen Tally:** long-press a tally row (≥ 400 ms).
- **Full Screen Tally → Home:** swipe down from the top, or tap the back chevron in the top-left.
- **Home → Settings:** tap the gear button.
- **Settings → Home:** tap the back chevron in the top-left.
- **Any screen → Signup / Login:** triggered by Log Out or Delete Account from Settings.

## Auth & Onboarding

### Signup

Single screen with **Name**, **Username**, and **Password** (plus confirm password). Firebase Auth uses **Email/Password** with a synthetic email `username@tapp.users` — users never type an email at signup. Submit is disabled until all fields validate:

- Name: 1–40 characters.
- Username: matches `^[a-z0-9_]{3,20}$` and not already claimed.
- Password: at least 6 characters; must match confirmation.

On submit: create the Firebase user, claim `usernames/{username}`, write `users/{uid}` with `Name`, `Username`, synthetic `Email`, `AvatarColor` (from a fixed 12-color palette by uid hash), `Joined = serverTimestamp()`, `Tallies = []`, `Friends = []`, `NumberType = "arabic"`, `Theme = "system"`. Route to Home.

### Returning user

`SignupView` is the signed-out landing screen; **Already have an account? Log in** opens `LoginView` (username + password). If Firebase still has a session, `AuthStore` loads the profile and `RootView` routes straight to Home.

### Log out

From Settings → Log Out. Confirms ("Log out of Tapp?"), then signs out. Lands on `SignupView`. Local UserDefaults (colors, sort, last-seen) are kept.

### Delete account

From Settings → Delete Account. Confirms twice (red button, then a destructive alert). On confirm:

1. For every tally where this user is `Owner`: delete the tally document and `arrayRemove` the ref from each `SharedWith` user's `Tallies`.
2. For every tally where this user appears in `SharedWith`: `arrayRemove` this user's ref from the tally, and remove the corresponding `Permissions` entry.
3. For every user in `Friends`: `arrayRemove` this user from their `Friends` list.
4. Delete `users/{uid}`.
5. Delete the Firebase Auth user.
6. Land on Signup.

There is no grace period and no undo.

## Home Page

### What it does

The home page shows the user's tallies, and is the landing page for the app.

### What it looks like

At the top right of the page is a small circular settings button (gear). Under settings is a two-thirds-screen-width button (+). To its left is a small sort button (three bars). Under the add and sort buttons is a scrollable list of tallies. Each tally displays a name, a number, an owner (avatar + username), and — if the current user does not have edit permission on that tally — a lock.

If the user opens the app and someone has updated a tally on the list, the updater's avatar appears briefly (~2 seconds, fading out) in the upper-right of that tally row. By default the most-recently-updated tallies are at the top, so the avatar is usually visible without scrolling; if there have been more updates than the user has not yet seen, only the most recent updater per tally is shown, and earlier updates are dropped silently. If that tally has `FireworksEnabled`, a fireworks animation also plays once in the tally box upon landing on the home page (capped at three concurrent animations to keep the list responsive).

### Empty state

When the user has no tallies, the list area displays centered text: "No tallies yet. Tap + to make one."

### Buttons

#### Settings

The settings button is a circular gear. Tapping it pushes the Settings screen.

#### Add Tally

The add tally button is the same shape as a tally row but a little less tall. It has a **+** in the middle. Tapping it presents a modal sheet titled **New Tally** containing:

- A **Name** text field (1–40 characters, required).
- A 3-column table titled **Share with**: rows are the current user's friends; columns are **Username**, **View**, **Edit**. Each row has two checkboxes; checking **Edit** auto-checks **View**; unchecking **View** auto-unchecks **Edit**. Defaults: both unchecked.
- A primary **Create** button (disabled until Name is valid) and a **Cancel** button.

On Create, write a `tallies/{id}` document with `Owner = current user`, `Count = 0`, `FireworksEnabled = false`, `ResetSchedule = "off"`, `SharedWith` built from the checked rows, `Permissions` populated from the same, `Created = serverTimestamp()`, `LastUpdated = serverTimestamp()`, `LastUpdatedBy = current user`, and `arrayUnion` the new ref into the current user's `Tallies` and every shared-with user's `Tallies`.

#### Sort

The sort button is a small circular control with three bars, to the left of the add tally button. Tapping it **toggles** between two orderings (persisted per user in `tapp.sortEnabled.<userId>`):

1. **Last updated** (`sortEnabled == true`) — descending by `LastUpdated`, then `Created`.
2. **Created** (`sortEnabled == false`) — descending by `Created`.

When active, the button uses the accent fill. After each tap, a small label ("Last updated" or "Created") fades in for 1.5 seconds under the button, then fades out. The list reorders once on toggle; live snapshot updates do not reshuffle rows (only count/name data updates in place).

#### Tally (row)

There may be many tallies on the home page (that's the point of the app). Each tally is a box spanning almost the entire width of the screen. Each tally displays its name (left), its count (right, rendered in the user's chosen `NumberType`), and its owner (bottom-left, 24 pt avatar + username), plus a lock in the bottom-right when the current user has view-only access.

- **Tap anywhere** on the row → increment `Count` by 1 via Firestore's atomic `FieldValue.increment(1)`. If the current user has only view access, taps are a no-op with a small horizontal shake animation.
- **Long-press (≥ 400 ms)** anywhere on the row → push the Full Screen Tally for that tally. While the press is held, the row scales to 0.98 to acknowledge the gesture; on threshold crossing, a single light haptic fires.

There is no safeguard for two friends incrementing at the same time. Atomic increments make the count itself correct (both taps add up). For non-count fields, the last write wins; the app does not surface conflicts.

Local color (see Full Screen Tally → Color) tints the row's background. Default color is the app accent color.

## Full Screen Tally

### What it does

Long-pressing a tally row opens that tally as its own screen. This screen has two purposes: (1) giving the user a much bigger hitbox to tap-to-increment, and (2) housing the per-tally settings (name, color, friends/permissions, resets, fireworks, delete).

### What it looks like

A back chevron sits in the top-left. The tally's **name** is centered at the top. Below it, in very large font, is the **count**. The entire area above the bottom button row is the increment hitbox.

Arranged in a single row across the bottom of the screen are six small circular setting buttons: **Color**, **Friends and Permissions**, **One-time or scheduled resets**, **Fireworks**, **Delete**. Owner-only buttons (Friends and Permissions, resets, Fireworks, Delete) are hidden for non-owners.

Swiping down from the top, or tapping the back chevron, returns to the home page.

### Increment behavior

Tapping anywhere on the screen above the bottom button row increments the count, exactly like tapping a row on the home page. View-only users get the shake animation.

### Buttons

#### Change Name

The name at the top of the screen is itself the button. Tapping it does nothing. Long-pressing it (≥ 400 ms) puts the name into an editable text field with the keyboard up; pressing Return commits, tapping outside cancels. Requires edit permission; for view-only users the long-press is a no-op.

#### Change Number

The count is itself the button. Tapping it increments by 1 (see above). Long-pressing it (≥ 400 ms) opens an inline numeric editor that accepts any signed 64-bit integer; Return commits, tap-outside cancels. The committed value overwrites `Count` directly (this counts as a normal write, so it updates `LastUpdated` / `LastUpdatedBy` and, if fireworks are enabled, fires the animation once). Requires edit permission.

#### Color

A small circular button rendered as a color wheel / gradient. Tapping it shows a popover with a fixed 12-color palette plus a "Default (Accent)" swatch. The choice writes to UserDefaults under `tapp.tallyColorIndex.<tallyId>`. **This color is local:** only this user, and only on this device, sees it. It is not synced.

#### Friends and Permissions

A small circular button rendered as two people. Tapping it presents a modal sheet identical in layout to the Add Tally sheet's 3-column table, populated with the current user's friends. Checking / unchecking a row immediately updates the tally's `SharedWith` and `Permissions`, and `arrayUnion`s or `arrayRemove`s the tally ref on that friend's `Tallies`. Owner-only.

#### One-time or scheduled resets

A small circular button rendered as a clock. Tapping it presents a modal sheet with four radio-style options: **Off**, **Reset now**, **Reset every day**, **Reset every month**, **Reset every year**. If a recurring schedule is currently set, that option is preselected.

- **Off** clears `ResetSchedule` and `NextResetAt`.
- **Reset now** sets `Count = 0` once; does not change the recurring schedule.
- **Daily / Monthly / Yearly** set `ResetSchedule` accordingly and compute `NextResetAt` as the next local-midnight boundary in the user's current timezone (next day / first of next month / January 1 of next year). When the device next runs a write to the tally, the client checks `NextResetAt`: if it has passed, the client sets `Count = 0` and rolls `NextResetAt` forward. This is best-effort (no server-side scheduler in this version); the reset happens the next time any client touches the tally after the scheduled time.

Owner-only.

#### Fireworks

A small circular button rendered with fireworks. Tapping toggles `FireworksEnabled` on the tally. When enabled, every increment fires a ~1.5 second fireworks animation in both the full-screen tally and the row on the home page for every user who has the tally. No sound. Honors the iOS Reduce Motion accessibility setting (when on, the animation is replaced with a brief sparkle fade). Owner-only.

#### Delete

A small circular button rendered as a trash can.

- **Owner:** label reads "Delete tally." Tapping prompts "Delete this tally for you and everyone you've shared it with?" On confirm: delete the tally doc and `arrayRemove` the ref from every `SharedWith` user's `Tallies` and the owner's own `Tallies`. Return to Home.
- **Non-owner:** label reads "Remove from my list." Tapping prompts "Remove this tally from your list? The owner and other friends keep it." On confirm: `arrayRemove` the ref from this user's `Tallies`, `arrayRemove` this user's ref from `SharedWith`, and remove this user's entry from `Permissions`. Return to Home.

## Settings

### What it does

The settings screen allows the user to view and change their account info, friends, number type, and theme. It is also where you log out or delete the account.

### What it looks like

The settings page is a scrollable list. From top to bottom:

```
Username:  (username)            [Change]
Name:      (name)                [Change]
Email:     (email)               [Change]
Password:  ********              [Change]

Friends                          [Add Friend]
  • (friend 1 avatar)  (friend 1 username)
  • (friend 2 avatar)  (friend 2 username)
  • ...

Numbers:   (Arabic)              [▾]
Theme:     (System)              [▾]

                                 [Log Out]

(Considerable Space)

                                 [Delete Account]
```

The "Considerable Space" before Delete Account is at least 96 pt to prevent accidental taps after scrolling.

### Empty state — Friends

When the user has no friends, the Friends section reads: "No friends yet. Tap **Add Friend** to add one by username."

### Buttons

#### Change Username

Opens an inline editor. Validates `^[a-z0-9_]{3,20}$` and uniqueness. On success, writes `Username` to the user doc. The user's friends and any tallies they share continue to work; only the displayed handle changes.

#### Change Name

Opens an inline editor. 1–40 characters. Writes `Name` to the user doc.

#### Change Email

Opens an inline editor, then routes through Firebase Auth's email update flow. On success, writes `Email` to the user doc.

#### Password (Change)

Tapping opens a sheet for **current password** and **new password** (with confirmation). Reauthenticates via Firebase, then calls `updatePassword`. No "forgot password" link here (future login-screen feature).

#### Friends — row

Swipe left on a friend row for **Remove**. Confirm in the alert. On Remove:

1. `arrayRemove` each user from the other's `Friends`.
2. For every tally currently owned by either user that lists the other in `SharedWith`, `arrayRemove` the other user from `SharedWith` and remove their `Permissions` entry, and `arrayRemove` the tally ref from the other user's `Tallies`.

There is no undo.

#### Add Friend

A box with normal-sized text reading "Add Friend." Tapping it presents a single text field for a username (no search, no autocomplete, no contacts access). On submit:

- If the username does not exist → "Error."
- If the username belongs to the current user → "Error."
- If the username belongs to an existing friend → "Success!" (idempotent).
- Otherwise → `arrayUnion` each user's ref into the other's `Friends`, then "Success!"

Friends are not optional: the added user does not get a request or a chance to refuse. They simply become a friend. Either side can remove the friendship at any time from their own Friends list.

#### Numbers

A tappable value box beside "Numbers:" showing the current type (e.g. "Arabic"). Tapping cycles **Arabic → Roman → Stick → Arabic** and writes `NumberType`.

- **Arabic:** base-10 digits (`0`, `1`, `42`, `-7`).
- **Roman:** classic numerals; `0` → `N`; above 3999 uses vinculum (overline = ×1000); negatives prefixed with `-`.
- **Stick:** custom-drawn tally groups (`StickTallyView`) — four rounded verticals plus a diagonal on the fifth, matching the app icon geometry. `0` is a dot; negatives prefixed with `-`. Groups wrap in a grid; on tight home rows, only as many groups as fit are shown and the true count appears in small Arabic beside them. VoiceOver always speaks the numeric count.

#### Theme

A tappable value box beside "Theme:" (e.g. "System"). Tapping cycles **System → Light → Dark → System**, writes `Theme`, and applies `.preferredColorScheme` immediately.

#### Log Out

Tapping prompts "Log out of Tapp?" On confirm, signs out and routes to the Signup / Login screen.

#### Delete Account

A bright red box reading "Delete Account." Tapping prompts a confirmation alert. Confirming runs the Delete Account flow described in **Auth & Onboarding → Delete account**.

## Sync, Offline, and Concurrency

- **Sync.** `TallyStore` keeps a snapshot listener on the current user doc, fans out per-tally snapshot listeners, and exposes a live-updating array to the UI. Friends and settings are read on demand and on relevant write callbacks.
- **Increments.** Always use Firestore's atomic `FieldValue.increment(1)`. Two users tapping at the same time both count; no taps are lost.
- **Other writes.** `Name`, `FireworksEnabled`, `ResetSchedule`, `Permissions`, `SharedWith`, direct `Count` overwrites, and friend mutations are plain Firestore writes. Last write wins; the app does not detect or surface conflicts.
- **Offline.** Firestore's offline cache serves reads and queues writes. The UI behaves the same online or offline; queued writes flush automatically on reconnect.
- **Avatars-on-landing.** Uses `tapp.lastSeenTallyUpdates.<userId>.<tallyId>`: on each home appearance (after tallies load), for every tally where `LastUpdated` is newer than last seen and `LastUpdatedBy` is another user, flash that updater's avatar (~2 s fade), then record last seen. If `FireworksEnabled`, also play landing fireworks (max 3 concurrent).

## Accessibility

- Every icon-only button has a VoiceOver label matching its name in this doc (Settings, Add Tally, Sort, Color, Friends and Permissions, Resets, Fireworks, Delete).
- All long-press gestures (≥ 400 ms) are also exposed as VoiceOver custom actions, so VoiceOver users can trigger Edit Name, Edit Count, and Open Full Screen Tally without timed gestures.
- Dynamic Type is supported throughout. The big count on the full-screen tally scales but caps at the screen width.
- The fireworks animation honors **Reduce Motion**: when on, the burst is replaced with a brief sparkle fade.
- All foreground/background color pairs (including every swatch in the color palette and every theme) meet WCAG AA contrast for normal text. The "view-only" state never relies on color alone — the lock icon is always present.

## Limits & Constraints

- **Tally name:** 1–40 characters.
- **Username:** 3–20 characters, `[a-z0-9_]`, unique across all users.
- **Display name:** 1–40 characters.
- **Count:** signed 64-bit integer. May be negative.
- **Friends per user:** no app-imposed limit.
- **Tallies per user:** no app-imposed limit.
- **Shared-with per tally:** no app-imposed limit.
- **Concurrent fireworks on the home page:** capped at 3 simultaneous animations; further bursts are dropped, not queued.

## Visual Spec Defaults

Used wherever the doc says "small," "almost the entire width," or similar.

- **Grid:** 8 pt base. Component sizes snap to multiples of 4.
- **Tally row:** full screen width minus 16 pt left/right margin, 88 pt tall, 16 pt corner radius.
- **Add Tally button:** same width as a tally row, 56 pt tall, 16 pt corner radius. Sits 8 pt under the sort/settings row.
- **Settings, Sort, and all per-tally setting buttons:** 36 pt circles.
- **Owner avatar on tally row:** 24 pt circle.
- **Updater avatar (briefly visible):** 20 pt circle, top-right of the row, 2-second fade.
- **Long-press threshold:** 400 ms everywhere it appears.
- **Default tally color:** app accent color.
- **Color palette:** 12 swatches plus "Default (Accent)."
- **Reduce-Motion fallback for fireworks:** 600 ms sparkle fade.
