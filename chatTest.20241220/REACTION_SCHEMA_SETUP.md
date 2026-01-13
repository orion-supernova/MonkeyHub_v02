# MessageReaction CloudKit Schema Setup

## Current Schema (Auto-Created)

The MessageReaction record type was auto-created with these fields:
- `id` (String)
- `emoji` (String)
- `userId` (String)
- `messageId` (String)
- `timestamp` (Date)

## Recommended Schema (With Foreign Key)

For proper CASCADE DELETE support, you should add:
- `messageReference` (Reference to ChatMessage)

## Migration Path

### Option 1: Keep Current Schema (Simpler)
✅ Works now with `messageId` string field
✅ No schema changes needed
❌ No automatic cascade delete
❌ Manual cleanup required when deleting messages

**Current Implementation:**
- Uses `messageId` string field for queries
- Backward compatible with existing data
- Still stores reference if schema supports it

### Option 2: Add Reference Field (Better Long-Term)

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard)
2. Select container: `iCloud.CrossTest`
3. Go to Schema > Record Types > MessageReaction
4. Add new field:
   - Name: `messageReference`
   - Type: **Reference**
   - Target: **ChatMessage**
   - Action: **Delete Self**
5. Make it **Queryable**
6. Save and deploy

**Benefits:**
- Automatic cascade delete
- Proper foreign key relationship
- Better data integrity

**The code already handles both cases!**

## Current Implementation Details

### Query Strategy