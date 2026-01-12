# Migration Sheet State Persistence Fix

## Problem: Export File Lost on Sheet Dismiss

### **What You Observed:**
> "After exporting, I can see import selection for a brief second after sheet dismiss, everything is gone."

### **Root Cause:**
The `selectedExportFile` state was stored **inside the sheet** (`DataMigrationSheet`), which gets destroyed when you dismiss the sheet.

```swift
// BEFORE (BROKEN)
struct DataMigrationSheet: View {
    @State private var selectedExportFile: URL?  // ← Gets destroyed on dismiss!
    ...
}
```

**What Happened:**
1. User taps "Export to File"
2. `selectedExportFile` is set to the export URL
3. Import button appears ✅
4. User dismisses sheet
5. Sheet is destroyed → `selectedExportFile` is lost ❌
6. User reopens sheet → Fresh instance with no memory of export

---

## Solution: Move State to Parent View

### **Architecture Change:**

```swift
// Parent View (SettingsView)
@State private var selectedExportFile: URL?  // ← Persists across sheet dismissals
```

```swift
// Sheet (DataMigrationSheet)
@Binding var selectedExportFile: URL?  // ← Binding to parent's state
```

### **Why This Works:**

| State Location | Lifecycle | Result |
|----------------|-----------|--------|
| Inside Sheet | Dies with sheet | ❌ Lost on dismiss |
| In Parent View | Lives with parent | ✅ Persists |

---

## Files Modified

### **1. SettingsView.swift**

**Added persistent state:**
```swift
@State private var selectedExportFile: URL?  // ← New persistent state
```

**Pass binding to sheet:**
```swift
.sheet(isPresented: $showingMigrationSheet) {
    DataMigrationSheet(
        migrationManager: migrationManager,
        selectedExportFile: $selectedExportFile  // ← Pass as binding
    )
}
```

### **2. DataMigrationSheet (inside SettingsView.swift)**

**Changed from @State to @Binding:**
```swift
// BEFORE
@State private var selectedExportFile: URL?

// AFTER
@Binding var selectedExportFile: URL?
```

---

## How It Works Now

### **Export Flow:**
1. User opens migration sheet
2. Taps "Export to File"
3. Export completes
4. `selectedExportFile` is set in **parent view's state** ✅
5. Import button appears

### **Sheet Dismiss:**
6. User dismisses sheet
7. Sheet is destroyed
8. **Parent view's state persists** ✅

### **Sheet Reopen:**
9. User reopens migration sheet
10. New sheet instance is created
11. Receives binding to **parent's persisted state** ✅
12. Import button still visible with export file ✅

---

## User Experience

### **Before Fix:**
```
Open Sheet → Export → See Import Button → Dismiss Sheet
  ↓
Reopen Sheet → Import Button Gone ❌
```

### **After Fix:**
```
Open Sheet → Export → See Import Button → Dismiss Sheet
  ↓
Reopen Sheet → Import Button Still There ✅
```

---

## Additional Improvements

### **Added Logging to getDiskUsageStatsSync:**

```swift
print("📊 Checking disk usage at: \(documentsPath.path)")
print("✅ Found \(roomCount) rooms in cache")
print("✅ Found \(messageCount) message cache files")
print("💾 Total cache size: \(sizeString)")
```

This helps debug if disk reading fails.

---

## Testing

### **Test 1: Basic Export/Import Flow**
1. Open Settings → Developer Tools → Data Migration
2. Tap "Export to File"
3. Wait for export to complete
4. **Dismiss the sheet** (close it)
5. **Reopen** Data Migration sheet
6. **Verify:** Import button should still be visible ✅
7. Tap "Import to CloudKit"
8. Verify import works

### **Test 2: Check Console Logs**
When you open the migration sheet, you should see:
```
📊 Checking disk usage at: /Users/.../Documents
✅ Found X rooms in cache
✅ Found Y message cache files
💾 Total cache size: Z KB
```

---

## SwiftUI State Management Patterns

### **Rule of Thumb:**

| State Lifetime | Storage Location |
|----------------|------------------|
| **Temporary** (only while view is visible) | `@State` in the view |
| **Persistent** (survives view dismissal) | `@State` in parent view |
| **Shared** (across multiple views) | `@StateObject` or `@EnvironmentObject` |

### **For Sheets Specifically:**

**✅ DO:**
- Store state in parent view
- Pass as `@Binding` to sheet

**❌ DON'T:**
- Store state in sheet itself (unless it's truly temporary)
- Rely on sheet state persisting after dismissal

---

## Summary

| Issue | Before | After |
|-------|--------|-------|
| **Export file state** | Lost on dismiss | Persists ✅ |
| **Import button** | Disappears | Stays visible ✅ |
| **User experience** | Confusing | Smooth ✅ |
| **Architecture** | State in child | State in parent ✅ |

The fix ensures that once you export data, the import button remains available even if you close and reopen the migration sheet. This matches user expectations and follows SwiftUI best practices.
