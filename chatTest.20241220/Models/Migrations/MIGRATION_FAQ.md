# CloudKit Migration System - Frequently Asked Questions

## What happens if the app is deleted and reinstalled?

### Short Answer
**The app works correctly.** Migrations don't re-run because schema version is stored in CloudKit, not on the device.

### Detailed Explanation

#### Device Identifier Changes
- **On Delete:** UserDefaults cleared, device ID lost
- **On Reinstall:** New device ID generated
- **Impact:** Logs show "different device" but this is cosmetic

#### Schema Version Persists
```
1. User deletes app
   ↓
2. Local data cleared (UserDefaults, CoreData, etc.)
   ↓
3. CloudKit data remains (SchemaVersion, ChatRooms, Messages)
   ↓
4. User reinstalls app
   ↓
5. App checks CloudKit: "What's the current schema version?"
   ↓
6. CloudKit responds: "Version 2"
   ↓
7. App checks its code: "I support version 2"
   ↓
8. Result: No migration needed! ✅
```

#### User Data
- **ChatRooms, Messages, Users:** All preserved in CloudKit ✅
- **Local cache:** Cleared, will be re-fetched ✅
- **Preferences:** Cleared (user needs to reconfigure settings)

### Edge Cases

#### Case 1: Mid-Migration Crash + Reinstall
```
Problem: App crashes during migration, lock remains in CloudKit

Solution: Automatic lock timeout (30 minutes)
- Stale locks are automatically removed
- New installation can proceed with migration
```

#### Case 2: Multiple Devices, One Reinstalls
```
Scenario:
- iPhone: Has app at v2
- iPad: Has app at v2
- iPhone: Delete & reinstall

Result:
- iPhone fetches v2 from CloudKit
- iPhone sees local code is v2
- No migration runs
- All devices stay in sync ✅
```

#### Case 3: Force Full Re-Migration
```
If you need to force migrations to re-run (e.g., for testing):

Option 1: Delete CloudKit Data (Drastic)
1. Go to CloudKit Dashboard
2. Delete SchemaVersion record
3. Reinstall app
4. Migrations run from scratch

Option 2: Change Schema Version (Safer)
1. Create new migration (e.g., v2 → v3)
2. Deploy update
3. Migration runs on all devices

Option 3: Testing Only
- Use Development CloudKit container
- Clear data between tests
```

## Device Identifier Strategy

### iOS/tvOS
```swift
UIDevice.current.identifierForVendor
```
- Unique per device per vendor
- Changes if ALL vendor apps are deleted
- Apple's recommended approach

### macOS/visionOS/Fallback
```swift
UserDefaults.standard["com.app.deviceIdentifier"]
```
- Generated once per install
- Persists across app launches
- Cleared on uninstall

### Why Not Use KeyChain?
**We considered it but chose UserDefaults because:**

Pros of Keychain:
- Survives app deletion ✅
- More secure ✅

Cons of Keychain:
- Creates unique identifier that survives reinstall
- Privacy concern: could track users across installs
- Overkill for non-sensitive migration tracking
- Complicates debugging (can't easily clear)

### Why This Approach?
1. **Privacy-First:** No persistent tracking across installs
2. **Cloud-Based Truth:** Schema version in CloudKit (shared across devices)
3. **Simple:** Easy to understand and debug
4. **Standard:** Follows Apple's guidelines

## Migration Lock Behavior

### Normal Operation
```
Device A starts migration
  ↓
Creates lock in CloudKit
  ↓
Completes migration (30 seconds)
  ↓
Releases lock
  ↓
Device B can now migrate if needed
```

### Lock Timeout
```
Device A starts migration
  ↓
Creates lock in CloudKit
  ↓
App crashes! Lock remains...
  ↓
30 minutes pass...
  ↓
Device B (or A reinstalled) checks lock
  ↓
Sees lock is >30 min old
  ↓
Removes stale lock
  ↓
Acquires new lock and migrates ✅
```

### Why 30 Minutes?
- Most migrations complete in seconds
- Network issues might add a few minutes
- 30 min provides safe buffer
- Prevents indefinite blocking

## Common Scenarios

### Scenario 1: First Install
```
✨ Fresh install
  ↓
Check CloudKit for SchemaVersion
  ↓
Not found (404)
  ↓
Create SchemaVersion: v2
  ↓
No migrations needed (starting at current version)
```

### Scenario 2: Update from v1 to v2
```
📱 App update released (v1 → v2)
  ↓
User launches updated app
  ↓
Check CloudKit: "SchemaVersion is v1"
  ↓
App code supports v2
  ↓
Run migration v1 → v2
  ↓
Update SchemaVersion: v2
  ↓
Done ✅
```

### Scenario 3: Skip Version
```
⚠️ User has v1, update jumps to v3

Check CloudKit: v1
App code: v3
  ↓
Get migration path: [v1→v2, v2→v3]
  ↓
Run v1→v2
Update to v2
  ↓
Run v2→v3
Update to v3
  ↓
Done ✅
```

### Scenario 4: Two Devices, One Migrates First
```
iPhone (opens app first):
  ↓
Runs migration v1 → v2
Updates CloudKit SchemaVersion: v2
  ↓
iPad (opens app later):
  ↓
Checks CloudKit: v2
App code: v2
No migration needed ✅
```

## Testing Migrations

### Test New Migration
```swift
// 1. Create test migration
class Migration_v2_to_v3_TEST: CloudKitMigration {
    // ... implementation
}

// 2. Register ONLY in test manifest
let testManifest = MigrationManifest()
testManifest.register(Migration_v2_to_v3_TEST())

// 3. Run with mock database
let mockDB = MockCloudKitDatabase()
let runner = MigrationRunner(database: mockDB)
try await runner.migrate(to: 3)

// 4. Verify results
XCTAssertEqual(mockDB.schemaVersion, 3)
```

### Test Rollback
```swift
// Test that rollback correctly undoes changes
let migration = Migration_v2_to_v3_TEST()

// Apply migration
try await migration.migrate(database: mockDB)

// Rollback
try await migration.rollback(database: mockDB)

// Verify state restored
let records = mockDB.fetchRecords(recordType: ChatUser.recordType)
XCTAssertNil(records[0]["newField"])
```

### Integration Testing
```swift
// Test full migration flow
func testFullMigrationFlow() async throws {
    // Setup: Start at v1
    let runner = MigrationRunner(database: database)

    // Execute: Migrate to v3
    try await runner.migrate(to: 3)

    // Verify: Check SchemaVersion
    let version = try await fetchSchemaVersion(from: database)
    XCTAssertEqual(version.version, 3)

    // Verify: Check migration history
    let history = version.parseMigrationHistory()
    XCTAssertEqual(history.count, 2) // v1→v2, v2→v3
}
```

## Troubleshooting

### "Migration Lock Already Held"
**Cause:** Another device is migrating, or stale lock exists

**Solution:**
- Wait a few minutes for active migration to complete
- If >30 minutes, lock auto-clears on next attempt
- Manual: Delete "MigrationLock" record in CloudKit Dashboard

### "Schema Version Mismatch"
**Cause:** App versions out of sync across devices

**Solution:**
- Update all devices to latest app version
- Migrations handle version jumps automatically

### "Migration Failed Partway"
**Cause:** Network error, app crash, etc.

**Solution:**
- Automatic rollback attempted
- On next launch, migration retries
- Check migration history in SchemaVersion record

### "Can't Find Migration"
**Cause:** Missing intermediate migration

**Solution:**
```swift
// If you have v1 and v3, but skipped v2:
// You MUST create v1→v2 AND v2→v3

// DON'T: Create v1→v3 (skipping v2)
// DO: Create v1→v2, then v2→v3
```

## Best Practices

### 1. Always Test Migrations
```swift
// Test with real CloudKit Development container
// Test with varying data sizes
// Test rollback scenarios
```

### 2. Keep Migrations Small
```swift
// ✅ Good: v1→v2 adds one field
// ❌ Bad: v1→v2 restructures entire schema
```

### 3. Document Breaking Changes
```swift
/**
 Migration: v2 → v3

 BREAKING CHANGE: Removes ChatRoom.createdBy field

 Impact: Old app versions will crash
 Mitigation: Ensure 90%+ users on v2+ before releasing v3
 */
```

### 4. Monitor Migration Success
```swift
// Check SchemaVersion.migrationHistory
// Track errors via logging
// Monitor CloudKit dashboard
```

## Summary

✅ **Delete & Reinstall:** Works correctly, no issues
✅ **Multi-Device:** Synchronized via CloudKit
✅ **Lock Timeout:** Prevents indefinite blocking
✅ **Privacy:** Device IDs don't persist across installs
✅ **Testing:** Comprehensive test infrastructure

The migration system is designed to be resilient, debuggable, and privacy-respecting.
