# CloudKit Environment Switching Guide

## Problem Overview

When developing with CloudKit, you may encounter issues when switching between Development and Production environments, especially when:

1. **Sign in with Apple (SIWA)** is already authorized for your Apple ID
2. **Local cached data** exists from one environment but you're now using another
3. **User records** exist in one environment but not the other
4. The app tries to create a user that already exists or login when no user exists

## Solution Components

This guide explains the robust solution implemented to handle environment switching seamlessly.

---

## 1. Environment Detection (`CloudKitManager`)

### Features Added

**New Environment Enum:**
```swift
enum CloudKitEnvironment: String {
    case development = "Development"
    case production = "Production"
    case unknown = "Unknown"
}
```

**Automatic Detection:**
- Uses `#if DEBUG` to detect development builds
- Stores user preference in UserDefaults
- Allows manual switching via Settings

**New Methods:**
```swift
func detectEnvironment() async
func setEnvironment(_ environment: CloudKitEnvironment)
func getEnvironmentInfo() -> String
```

### Location
- `CloudKitManager.swift` lines 94-154

---

## 2. Improved User Creation (`LoginViewModel`)

### Enhanced Error Handling

The `createUser()` method now handles scenarios where:
- User already exists (e.g., when switching from dev to prod)
- CloudKit returns server record conflicts
- SIWA is authorized but user doesn't exist in current environment

**Key Improvement:**
```swift
if ckError.code == .serverRecordChanged || ckError.code == .batchRequestFailed {
    Logger.info("User might already exist in different environment, attempting login...")
    try await loginUser(with: credential)
    return
}
```

### Location
- `LoginViewModel.swift` lines 78-126

---

## 3. Data Migration Manager

### Purpose
Allows developers to export cached data from one environment and import it to another.

### Core Features

#### Export Functionality
```swift
func exportDataToDisk() async throws -> URL
```
- Exports all cached rooms and messages to a JSON file
- Includes metadata: userId, export date, app version
- Saves to Documents directory with timestamp

#### Import Functionality
```swift
func importDataToCloudKit(fromFile url: URL) async throws
```
- Reads exported JSON file
- Uploads rooms and messages to CloudKit
- Checks for duplicates (skips existing records)
- Shows progress during upload

#### Data Management
```swift
func clearAllLocalData() throws
func getDiskUsageStats() -> (rooms: Int, messages: Int, totalSize: String)
```

### Export File Format
```json
{
  "userId": "string",
  "rooms": [...],
  "messages": {
    "roomId": [...]
  },
  "exportDate": "ISO8601",
  "appVersion": "1.0"
}
```

### Location
- `DataMigrationManager.swift`

---

## 4. Developer Tools UI (Settings)

### New Settings Section: "DEVELOPER TOOLS"

#### 1. Environment Display & Switch
- Shows current CloudKit environment
- Button to switch between Development/Production
- Persists selection in UserDefaults

#### 2. Data Migration
- Opens comprehensive migration sheet
- Shows statistics: room count, message count, storage size
- Export button with progress tracking
- Import button (enabled after export)

#### 3. Clear Local Data
- Removes all cached files
- Clears UserDefaults
- Shows confirmation alert
- Cannot be undone

#### 4. Force Re-login
- Clears all local data
- Resets authentication state
- Resets environment preference
- Forces user back to login screen

### Migration Sheet UI
- **Stats Cards**: Visual display of cached data
- **Export Section**: One-tap export with progress bar
- **Import Section**: Shows ready-to-import file and upload progress
- **Real-time Status**: Updates during long operations

### Location
- `SettingsView.swift` lines 43-118 (Developer Section)
- `SettingsView.swift` lines 854-1055 (Migration Sheet)

---

## How to Use

### Scenario 1: Developer Switching from Development to Production

1. **In Development Build:**
   - Open Settings → Developer Tools
   - Tap "Data Migration"
   - Tap "Export to File" (saves JSON to Documents)
   - Note the exported file name

2. **Switch to Production:**
   - In Settings → Developer Tools
   - Tap environment switcher
   - Select "Production"

3. **Import Data:**
   - Open Settings → Developer Tools → Data Migration
   - The exported file should appear as "Ready to import"
   - Tap "Import to CloudKit"
   - Wait for upload to complete

4. **Restart App:**
   - Force close and reopen
   - Sign in with Apple
   - Your rooms and messages are now in production

### Scenario 2: Mismatched State (Cached Data + No User)

**Symptoms:**
- App shows rooms and messages (from disk)
- Can't send messages (no CloudKit user)
- "Failed to create new user" error

**Solution:**
1. Open Settings → Developer Tools
2. Tap "Force Re-login"
3. Confirm the action
4. App returns to login screen
5. Sign in again (creates fresh user in current environment)

### Scenario 3: SIWA Already Authorized but Different Environment

**Symptoms:**
- Sign in with Apple succeeds
- "User not found" or "Failed to create user" error

**Solution:**
The app now automatically handles this:
- Tries to create user
- If creation fails due to existing record → attempts login
- If login succeeds → continues normally
- If both fail → shows appropriate error

---

## Technical Details

### CloudKit Helpers Added

```swift
// CloudKitManager.swift
func fetchChatRoom(byId roomId: String) async throws -> ChatRoom?
func fetchMessage(byId messageId: String) async throws -> ChatMessage?
```

These methods check if records already exist before importing, preventing duplicates.

### Error Handling

New error enum for migration operations:
```swift
enum DataMigrationError: LocalizedError {
    case noDataToExport
    case exportFailed(String)
    case importFailed(String)
    case noUserLoggedIn
    case cloudKitNotAvailable
}
```

### Data Persistence

The migration system uses existing persistence infrastructure:
- `MessagePersistenceService` for reading cached data
- `CloudKitManager` for uploading to CloudKit
- Standard JSON encoding/decoding for portability

---

## Best Practices

### For Developers

1. **Always export data before switching environments**
2. **Use Force Re-login if you encounter authentication issues**
3. **Keep export files** (they're timestamped for tracking)
4. **Monitor the progress bars** during import (large datasets take time)

### For Production Users

**Good news:** Production users won't encounter these issues because:
- They only use production environment (no switching)
- They don't have cached development data
- SIWA creates fresh records on first login

### Deployment Considerations

Before deploying to production:
1. Ensure development schema is deployed to production CloudKit
2. Test the migration flow on a clean device
3. Verify all record types exist in both environments

---

## Files Modified

| File | Changes |
|------|---------|
| `CloudKitManager.swift` | Added environment detection, fetch helpers |
| `LoginViewModel.swift` | Enhanced user creation error handling |
| `DataMigrationManager.swift` | New file - complete migration system |
| `SettingsView.swift` | Added developer tools section and migration UI |

---

## Troubleshooting

### "Export failed: No cached data found"
**Cause:** No rooms or messages are cached locally
**Solution:** Join some rooms and send messages first, then export

### "Import failed: No user is currently logged in"
**Cause:** Not signed in when attempting import
**Solution:** Sign in with Apple first, then import

### "CloudKit save failed" during import
**Cause:** Network issues or CloudKit quota exceeded
**Solution:** Check internet connection and iCloud storage

### App still shows old data after Force Re-login
**Cause:** App didn't restart properly
**Solution:** Force close the app completely and reopen

---

## Future Enhancements

Potential improvements for the future:
- Automatic environment detection based on build configuration
- Background sync for large imports
- Selective migration (choose specific rooms)
- Conflict resolution when importing existing data
- Export to iCloud Drive for backup

---

## Summary

This solution provides a robust way to handle CloudKit environment switching during development while ensuring production users have a seamless experience. The key features are:

✅ **Environment awareness** - App knows which environment it's using
✅ **Data portability** - Export/import mechanism for moving data
✅ **Error recovery** - Force re-login to fix mismatched states
✅ **Developer-friendly** - Clear UI for all operations
✅ **Production-safe** - No impact on regular users

The implementation follows SwiftUI best practices and integrates seamlessly with your existing CloudKit infrastructure.
