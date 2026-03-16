# CloudKit → Convex Migration Plan
**Status:** iOS Migration Complete — Awaiting Xcode project settings cleanup
**Last Updated:** 2026-03-17
**Engineer:** Staff-level migration guide

---

## Overview

This document is the living plan for migrating MonkeyHub_v02 from CloudKit (public database, subscriptions, CKAsset) to Convex (TypeScript backend, real-time queries, file storage). Every section has a completion checkbox. Update this file as work progresses.

### Architecture Delta

| Concern | Before (CloudKit) | After (Convex) |
|---|---|---|
| Auth | iCloud Sign-In / CKContainer.userRecordID() | Username + password hash (Convex mutations) |
| Database | CloudKit Public Database | Convex reactive database |
| Real-time | CloudKit subscriptions + APNs silent push | Convex WebSocket subscriptions (ConvexMobile) |
| File storage | CKAsset | Convex file storage API |
| Push notifications | CloudKit subscription triggers APNs automatically | Convex HTTP action → APNs |
| User identity | iCloud account ID (opaque string) | Convex `Id<"users">` |
| Queries | CKQuery + CKQueryOperation cursors | Convex queries with indexes |
| Batch operations | 400-record chunks via CloudKitBatchOperations | Convex transactions (no hard limit) |

---

## Phase 1 — Backend: Complete Convex Schema & Functions
**Goal:** Make the Convex backend feature-complete to replace every CloudKit operation.

### 1.1 Schema Updates (`backend/convex/schema.ts`)

**Status:** [ ] Not started

Gaps between current schema and what the app needs:

**`users` table — add fields:**
- `name: v.string()` — display name (was separate from username)
- `email: v.optional(v.string())`
- `avatarStorageId: v.optional(v.id("_storage"))` — replaces CKAsset avatar
- `deviceTokens: v.optional(v.array(v.string()))` — APNs tokens for push

**`rooms` table — add fields:**
- `lastMessage: v.optional(v.string())` — preview text
- `lastMessageTime: v.optional(v.number())` — for sorting
- `type: v.optional(v.string())` — "regular" | "secret" (Chamber of Secrets)
- `messageLifetime: v.optional(v.number())` — auto-expiry in seconds
- `avatarStorageId: v.optional(v.id("_storage"))` — room icon

**`messages` table — add fields:**
- `type: v.string()` — "text" | "image" | "video" | "audio" | "url" | "system"
- `mediaStorageId: v.optional(v.id("_storage"))` — replaces CKAsset
- `senderName: v.string()` — denormalized for display without extra query

**New `reactions` table:**
```typescript
reactions: defineTable({
  messageId: v.id("messages"),
  userId: v.id("users"),
  emoji: v.string(),
  createdAt: v.number(),
})
  .index("by_message", ["messageId"])
  .index("by_message_user", ["messageId", "userId"])
```

**New `typingIndicators` table:**
```typescript
typingIndicators: defineTable({
  roomId: v.id("rooms"),
  userId: v.id("users"),
  updatedAt: v.number(), // TTL: ignore if older than 5s
})
  .index("by_room", ["roomId"])
  .index("by_room_user", ["roomId", "userId"])
```

---

### 1.2 Backend Functions

**Status:** [ ] Not started

#### `backend/convex/users.ts` — new file
- [ ] `updateProfile(userId, name, email?, bio?)` — mutation
- [ ] `uploadAvatar(userId, storageId)` — mutation
- [ ] `getProfile(userId)` — query
- [ ] `registerDeviceToken(userId, token)` — mutation (upsert token in array)
- [ ] `removeDeviceToken(userId, token)` — mutation
- [ ] `searchUsers(query, currentUserId)` — query (already in friends.ts, consolidate)

#### `backend/convex/messages.ts` — update existing
- [ ] `send(roomId, userId, content, type, mediaStorageId?, senderName)` — update signature
- [ ] `deleteMessage(messageId, userId)` — mutation (owner or room owner only)
- [ ] `listBefore(roomId, beforeTimestamp, limit)` — for pagination (load older)
- [ ] After sending, update room's `lastMessage` + `lastMessageTime`

#### `backend/convex/reactions.ts` — new file
- [ ] `addReaction(messageId, userId, emoji)` — mutation (idempotent: upsert per user+emoji+message)
- [ ] `removeReaction(messageId, userId, emoji)` — mutation
- [ ] `getReactions(messageId)` — query
- [ ] `getReactionsForMessages(messageIds)` — query (bulk fetch for room)

#### `backend/convex/typing.ts` — new file
- [ ] `setTyping(roomId, userId)` — mutation (upsert with current timestamp)
- [ ] `clearTyping(roomId, userId)` — mutation (delete indicator)
- [ ] `getTypingUsers(roomId)` — query (return users with updatedAt within 5s)

#### `backend/convex/files.ts` — new file
- [ ] `generateUploadUrl()` — action (returns Convex storage upload URL)
- [ ] `getFileUrl(storageId)` — query (returns serving URL)
- [ ] `deleteFile(storageId)` — mutation

#### `backend/convex/notifications.ts` — new file
- [ ] `sendPushNotification(userIds, title, body, data)` — internal action
  - Reads `deviceTokens` for each userId
  - Calls APNs API (HTTP/2)
  - Called from `messages.send` and `reactions.addReaction`
- [ ] APNs credentials stored as Convex environment variables

#### `backend/convex/rooms.ts` — update existing
- [ ] `create(...)` — add `type`, `messageLifetime` params
- [ ] `deleteRoom(...)` — also delete all reactions for room's messages
- [ ] `updateRoomAvatar(roomId, userId, storageId)` — mutation

---

## Phase 2 — iOS: New Convex Service Layer
**Goal:** Build a clean Swift abstraction over ConvexMobile SDK that mirrors the existing CloudKit API surface, so we can do a clean swap.

**Status:** [ ] Not started

### 2.1 `ConvexService.swift` — core singleton
- Wraps `ConvexClient` from ConvexMobile SDK
- Manages WebSocket connection lifecycle (connect on login, disconnect on logout)
- Exposes `subscribe<T>()` for real-time queries
- Exposes `mutation()` and `query()` wrappers with async/await
- Handles auth token injection (userId stored in Keychain, not UserDefaults)
- File: `chatTest.20241220/Services/ConvexService.swift`

### 2.2 `ConvexAuthService.swift`
- `signup(username:password:name:email:)` → calls `auth:signup`
- `login(username:password:)` → calls `auth:login`, stores userId in Keychain
- `logout()` → calls `auth:logout`, clears Keychain
- `currentUserId` — computed from Keychain
- Replaces: iCloud auth in `LoginViewModel`
- File: `chatTest.20241220/Services/ConvexAuthService.swift`

### 2.3 Update Swift Data Models
Remove all CloudKit serialization. Keep the same struct shapes, just remove:
- `init(record: CKRecord)` initializers
- `toRecord() -> CKRecord` methods
- `CKRecord.ID` references
- Add `Convex` ID fields (`_id` as String, decoded from Convex JSON)

Files to update:
- [ ] `Models/ChatMessage.swift`
- [ ] `Models/ChatRoom.swift`
- [ ] `Models/ChatUser.swift`
- [ ] `Models/MessageReaction.swift`
- [ ] `Models/TypingIndicator.swift`

Add `Codable` conformance with Convex JSON field names (camelCase, `_id`).

---

## Phase 3 — iOS: Replace CloudKitManager
**Goal:** Replace `CloudKitManager.swift` with a Convex-backed equivalent that has the same interface consumed by `ChatRepository`.

**Status:** [ ] Not started

### 3.1 Create `ConvexChatAPI.swift`
New file implementing the same protocol/interface surface that `ChatRepository` uses.
Replace every CloudKit operation:

| CloudKit Operation | Convex Replacement |
|---|---|
| `fetchMessages(roomId:after:)` | query `messages:listSince` |
| `fetchMessages(roomId:before:limit:)` | query `messages:listBefore` |
| `sendMessage(message:)` | mutation `messages:send` |
| `deleteMessage(id:roomId:)` | mutation `messages:deleteMessage` |
| `fetchRooms(for:)` | query `rooms:listUserRooms` |
| `createRoom(room:)` | mutation `rooms:create` |
| `joinRoom(roomId:userId:)` | mutation `rooms:join` |
| `leaveRoom(roomId:userId:)` | mutation `rooms:leave` |
| `deleteRoom(roomId:userId:)` | mutation `rooms:deleteRoom` |
| `fetchUser(id:)` | query `users:getProfile` |
| `updateUser(user:)` | mutation `users:updateProfile` |
| `uploadAsset(data:)` | action `files:generateUploadUrl` + HTTP PUT |
| `deleteAsset(id:)` | mutation `files:deleteFile` |

File: `chatTest.20241220/Services/ConvexChatAPI.swift`

### 3.2 Update `ChatRepository.swift`
- Replace `CloudKitManager` dependency with `ConvexChatAPI`
- Replace all `cloudKit.*` calls with `convexAPI.*`
- Replace notification-based real-time with Convex subscriptions (see 3.3)
- Keep local disk caching (MessagePersistenceService) as-is — it's CloudKit-independent

### 3.3 Replace `NotificationSubscriptionManager.swift`
- Delete the entire file
- Real-time is now handled by Convex WebSocket subscriptions
- Create `ConvexSubscriptionManager.swift`:
  - `subscribeToRoom(roomId:)` → subscribes to `messages:list` query for that room
  - `subscribeToRooms(userId:)` → subscribes to `rooms:listUserRooms`
  - `subscribeToReactions(roomId:)` → subscribes to `reactions:getReactionsForMessages`
  - `subscribeToTyping(roomId:)` → subscribes to `typing:getTypingUsers`
  - Convex automatically delivers real-time updates via WebSocket — no APNs needed for in-app updates

### 3.4 Update `ReactionService.swift`
- Replace CloudKit CKQuery/save/delete with `ConvexChatAPI` reaction methods

### 3.5 Update `TypingIndicatorManager`
- Replace CloudKit record save/delete with `ConvexChatAPI` typing methods

---

## Phase 4 — iOS: Authentication Migration
**Goal:** Replace iCloud/Sign-in-with-Apple auth with Convex username+password auth.

**Status:** [ ] Not started

### 4.1 Update `LoginViewModel.swift`
- Remove `handleSignInWithApple()` and all ASAuthorization code
- Add `handleLogin(username:password:)` using `ConvexAuthService`
- Add `handleSignUp(username:name:email:password:)` using `ConvexAuthService`
- Remove `CKContainer.userRecordID()` dependency
- Remove iCloud account status check

### 4.2 Update `LoginView.swift`
- Remove Sign in with Apple button
- Add username/password form
- Add sign-up flow
- (Optional) Add "Create account" navigation

### 4.3 Session persistence
- Store `userId` (Convex Id<"users">) in **Keychain**, not UserDefaults
- Store `username` in UserDefaults (non-sensitive)
- On app launch: check Keychain for userId → auto-login if present
- On logout: clear Keychain

---

## Phase 5 — iOS: Push Notifications (Background Updates)
**Goal:** Maintain push notification delivery for messages when app is backgrounded.

**Status:** [ ] Not started

> Note: Convex real-time WebSocket handles in-app updates. Push is only needed when app is killed/backgrounded.

### 5.1 iOS — Device Token Registration
- Keep APNs registration in `AppDelegate.registerForPushNotifications()`
- On successful registration: call `ConvexAuthService.registerDeviceToken(token:)`
- Store token locally in UserDefaults (unchanged)
- On `application(_:didReceiveRemoteNotification:)`: minimal handling — just wake app and trigger Convex subscription refresh

### 5.2 Backend — APNs Push Action (`backend/convex/notifications.ts`)
- Internal Convex action called after `messages:send`
- Reads device tokens for all room members (except sender)
- Sends APNs push via HTTP/2 (use `fetch` in Convex action)
- Payload: `{ roomId, senderName, content, type }`
- APNs credentials: set as Convex env vars (`APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`)

### 5.3 Update `AppDelegate.swift`
- Remove `NotificationRouter` and CloudKit notification routing
- Simplify to just: wake app + route to specific room if user taps notification
- Remove CloudKit-specific `userInfo` parsing (ck_payload, ckNotificationID, etc.)

---

## Phase 6 — iOS: File/Asset Migration
**Goal:** Replace CKAsset with Convex file storage for avatars and media messages.

**Status:** [ ] Not started

### 6.1 Upload Flow
```
iOS app → POST /api/upload-url (Convex action generateUploadUrl)
       → receives { uploadUrl, storageId }
       → HTTP PUT to uploadUrl with file data
       → calls mutation files:getFileUrl(storageId) or stores storageId in record
```

### 6.2 Download Flow
```
iOS app → calls query files:getFileUrl(storageId)
       → receives CDN URL (Convex storage URL)
       → downloads directly from CDN URL
       → caches locally (same AssetPersistenceService)
```

### 6.3 Update `AssetPersistenceService.swift`
- Replace CKAsset loading with Convex storage URL download
- Keep local file caching logic (it's CloudKit-independent)
- Asset filenames: use `storageId` as filename key instead of CKAsset URL

---

## Phase 7 — Cleanup
**Goal:** Remove all CloudKit code, entitlements, and dead dependencies.

**Status:** [ ] Not started

### Files to DELETE entirely:
- [ ] `Managers/CloudKitManager.swift`
- [ ] `Managers/NotificationSubscriptionManager.swift`
- [ ] `Managers/NotificationRouter.swift`
- [ ] `Managers/DataMigrationManager.swift`
- [ ] `Managers/MigrationRunner.swift`
- [ ] `Utilities/CloudKitBatchOperations.swift`
- [ ] `Models/Migrations/` (entire directory)

### Files to MODIFY (remove CloudKit imports/code):
- [ ] `AppDelegate.swift` — remove CloudKit notification routing
- [ ] `chatTest_20241220App.swift` — remove CloudKit init
- [ ] All Model files — remove CKRecord serialization
- [ ] `Services/ReactionService.swift` — already replaced in Phase 3
- [ ] `Modules/Login/LoginViewModel.swift` — already replaced in Phase 4

### Xcode Project Settings:
- [ ] Remove `CloudKit` capability from target
- [ ] Remove `iCloud` entitlement (or keep for iCloud Drive if needed — unlikely)
- [ ] Remove `CKContainer` identifier from entitlements
- [ ] Remove CloudKit framework from "Link Binary With Libraries"
- [ ] Verify ConvexMobile package is properly linked

---

## Implementation Order (Dependency Graph)

```
Phase 1 (Backend) ──────────────────────────────────────────────┐
    ├── 1.1 Schema updates                                       │
    ├── 1.2 users.ts, messages.ts, reactions.ts, typing.ts      │
    ├── 1.2 files.ts (storage)                                   │
    └── 1.2 notifications.ts (APNs action)                      │
                                                                  │
Phase 2 (iOS Service Layer) ─────────────────────────── depends on Phase 1
    ├── 2.1 ConvexService.swift                                  │
    ├── 2.2 ConvexAuthService.swift                              │
    └── 2.3 Update Swift models (remove CKRecord)               │
                                                                  │
Phase 3 (Replace CloudKitManager) ──────────────── depends on Phase 2
    ├── 3.1 ConvexChatAPI.swift                                  │
    ├── 3.2 Update ChatRepository.swift                          │
    ├── 3.3 ConvexSubscriptionManager.swift                      │
    ├── 3.4 Update ReactionService.swift                         │
    └── 3.5 Update TypingIndicatorManager                        │
                                                                  │
Phase 4 (Auth) ──────────────────────────────────── depends on Phase 2
    ├── 4.1 Update LoginViewModel.swift                          │
    ├── 4.2 Update LoginView.swift                               │
    └── 4.3 Session persistence (Keychain)                       │
                                                                  │
Phase 5 (Push) ──────────────────────────────────── depends on Phase 3
Phase 6 (Files) ─────────────────────────────────── depends on Phase 3
Phase 7 (Cleanup) ───────────────────────────────── depends on all above
```

---

## Critical Decisions & Non-Obvious Notes

### Auth Transition
There is no automatic migration of existing iCloud users to Convex accounts. This is a **clean start** — users must create new Convex accounts. If data portability matters, a one-time migration job would be needed (fetch CloudKit records by old iCloud ID, insert into Convex).

### Real-Time Model Change
CloudKit used APNs push for real-time delivery (both foreground and background). Convex uses WebSocket subscriptions for foreground and APNs for background. The `ConvexSubscriptionManager` must:
1. Subscribe when app enters foreground
2. Unsubscribe / let WebSocket idle when backgrounded
3. On foreground return: Convex SDK reconnects and delivers missed updates automatically

### No `CKQueryOperation` Cursors
Convex pagination uses `{ isDone, continueCursor }` via `ctx.db.query().paginate()`. The existing cursor-based pagination logic in `ChatRepository` must be adapted.

### Message Deduplication
CloudKit deduplication used a `processedMessageIds` Set because push + query could both deliver the same message. With Convex real-time, the query is the **single source of truth** — no deduplication needed. The Set can be removed.

### `deviceTokens` Array
Convex has no equivalent of "save array of push tokens" — it's just a regular field. The `registerDeviceToken` mutation should append-if-not-present to avoid duplicates. Use `Array.includes` check before push.

### Password Security
The current Convex auth stores `passwordHash` computed on the client (iOS hashes before sending). Ensure the hash function used on iOS (likely SHA-256 or bcrypt) is consistent. **Do not store plaintext passwords.**

### File Storage URLs
Convex storage URLs are time-limited signed URLs (default ~1 hour). The existing `AssetPersistenceService` local caching is important — don't re-fetch file URLs on every render. Cache the downloaded file locally by `storageId`.

---

## Progress Checklist

### Phase 1 — Backend ✅ COMPLETE (2026-03-17)
- [x] 1.1 Update schema.ts (users, rooms, messages, add reactions, typingIndicators)
- [x] 1.2 Create users.ts
- [x] 1.3 Update messages.ts (type, mediaStorageId, senderName, listBefore, deleteMessage)
- [x] 1.4 Create reactions.ts
- [x] 1.5 Create typing.ts
- [x] 1.6 Create files.ts
- [x] 1.7 Create notifications.ts (APNs action)
- [x] 1.8 Update rooms.ts (type, messageLifetime, avatarStorageId, deleteRoom cascade, lastMessage)
- [ ] 1.9 Run `convex dev` against live deployment and verify schema (requires Convex account login)

### Phase 2 — iOS Service Layer ✅ COMPLETE (2026-03-17)
- [x] 2.1 Create ConvexService.swift
- [x] 2.2 Create ConvexAuthService.swift
- [x] 2.3 Update ChatMessage.swift (remove CKRecord, add Codable for Convex)
- [x] 2.4 Update ChatRoom.swift
- [x] 2.5 Update ChatUser.swift
- [x] 2.6 Update MessageReaction.swift
- [x] 2.7 Update TypingIndicator.swift

### Phase 3 — Replace CloudKitManager ✅ COMPLETE (2026-03-17)
- [x] 3.1 Create ConvexChatAPI.swift
- [x] 3.2 Update ChatRepository.swift
- [x] 3.3 Create ConvexSubscriptionManager.swift
- [x] 3.4 Update ReactionService.swift
- [x] 3.5 Update TypingIndicatorManager

### Phase 4 — Authentication ✅ COMPLETE (2026-03-17)
- [x] 4.1 Update LoginViewModel.swift
- [x] 4.2 Update LoginView.swift
- [x] 4.3 Keychain session storage

### Phase 5 — Push Notifications ✅ COMPLETE (2026-03-17)
- [x] 5.1 Update AppDelegate.swift (simplified, routes via NotificationRouter → ChatRepository)
- [x] 5.2 Backend: APNs action in notifications.ts
- [ ] 5.3 Set APNs env vars in Convex dashboard (requires Convex account access)

### Phase 6 — File Storage ✅ COMPLETE (2026-03-17)
- [x] 6.1 Update AssetPersistenceService.swift (Convex storage URLs)
- [x] 6.2 Update upload flow (generateUploadUrl → PUT → storageId)
- [x] 6.3 Update download flow (getFileUrl → URLSession → local cache)

### Phase 7 — Cleanup ✅ COMPLETE (2026-03-17)
- [x] 7.1 Delete CloudKitManager.swift
- [x] 7.2 Delete NotificationSubscriptionManager.swift
- [x] 7.3 NotificationRouter.swift rewritten (not deleted — Convex-backed)
- [x] 7.4 Delete DataMigrationManager.swift + MigrationRunner.swift
- [x] 7.5 Delete CloudKitBatchOperations.swift
- [x] 7.6 Delete Models/Migrations/ directory (all 6 files)
- [x] 7.7 Delete Modules/Login/ICloudErrorView.swift
- [x] 7.8 Delete Modules/Migration/MigrationProgressView.swift
- [x] 7.9 Zero `import CloudKit` or CloudKit symbols in codebase — confirmed by grep
- [x] 7.10 Stale CloudKit UI strings in SettingsView cleaned up
- [x] 7.11 Remove CloudKit/iCloud capability from Xcode project + entitlements — done manually in Xcode
