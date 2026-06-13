import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

/**
 * Returns a user's profile, with per-field redaction based on the viewer's
 * relationship to the subject. Pass `viewerUserId` so the backend can apply
 * the subject's visibility rules. Callers omitting `viewerUserId` get the
 * public-only view (used for self-lookups via login response, etc.).
 *
 * Visibility values per field:
 *   "public"  → anyone sees it
 *   "friends" → only accepted friends see it (and the user themselves)
 *   "nobody"  → only the user themselves sees it
 *
 * `friendRequests` doesn't affect the profile payload directly — it's
 * enforced at request-mutation time.
 */
export const getProfile = query({
  args: {
    userId: v.id("users"),
    viewerUserId: v.optional(v.id("users")),
  },
  handler: async (ctx, { userId, viewerUserId }) => {
    const user = await ctx.db.get(userId);
    if (!user) return null;

    const isSelf =
      viewerUserId !== undefined && viewerUserId.toString() === userId.toString();

    // Friends check.
    let isFriend = false;
    if (viewerUserId && !isSelf) {
      const a = await ctx.db
        .query("friendships")
        .withIndex("by_pair", (q) =>
          q.eq("userId", viewerUserId).eq("friendId", userId)
        )
        .first();
      const b = await ctx.db
        .query("friendships")
        .withIndex("by_pair", (q) =>
          q.eq("userId", userId).eq("friendId", viewerUserId)
        )
        .first();
      isFriend = a?.status === "accepted" || b?.status === "accepted";
    }

    function canSee(level: string | undefined): boolean {
      if (isSelf) return true;
      const v = level ?? "public";
      if (v === "public") return true;
      if (v === "friends") return isFriend;
      return false; // "nobody"
    }

    const vis = user.visibility ?? {};
    return {
      _id: user._id,
      username: user.username,
      name: user.name,
      bio: user.bio,
      // Self-only data — never expose to other viewers.
      email: isSelf ? user.email : undefined,
      avatarStorageId: canSee(vis.avatar) ? user.avatarStorageId : undefined,
      status: canSee(vis.status) ? user.status : undefined,
      lastSeen: canSee(vis.lastSeen) ? user.lastSeen : undefined,
      // Mirror the visibility map back so self-view UI can render it without
      // a separate fetch. Other viewers get an empty map — knowing someone's
      // settings is itself a privacy leak.
      visibility: isSelf ? vis : undefined,
      // Hint to the viewer that fields were redacted, so the UI can show
      // a "limited view" pill instead of guessing.
      isRedacted: !isSelf &&
        (!canSee(vis.avatar) ||
          !canSee(vis.status) ||
          !canSee(vis.lastSeen)),
      acceptsFriendRequests: (vis.friendRequests ?? "public") === "public",
    };
  },
});

/**
 * Sets the user's presence status. Called from the Flutter client whenever the
 * app's lifecycle changes (resume → "online", pause/inactive → "away",
 * detach → "offline"). Also stamps `lastSeen` so other clients can render
 * "last seen N minutes ago" based on the most recent transition.
 *
 * Note: this writes the top-level `status` field (the presence indicator),
 * not `visibility.status` (which controls whether other users can SEE this
 * field). Those are two separate concepts that happen to share a name.
 */
export const updateStatus = mutation({
  args: {
    userId: v.id("users"),
    status: v.string(),
  },
  handler: async (ctx, { userId, status }) => {
    const allowed = new Set(["online", "away", "offline"]);
    if (!allowed.has(status)) return; // ignore unknown values silently
    const user = await ctx.db.get(userId);
    if (!user) return; // user gone — nothing to update
    await ctx.db.patch(userId, {
      status,
      lastSeen: Date.now(),
    });
  },
});

export const updateVisibility = mutation({
  args: {
    userId: v.id("users"),
    avatar: v.optional(v.string()),
    status: v.optional(v.string()),
    lastSeen: v.optional(v.string()),
    seen: v.optional(v.string()),
    friendRequests: v.optional(v.string()),
  },
  handler: async (
    ctx,
    { userId, avatar, status, lastSeen, seen, friendRequests }
  ) => {
    const user = await ctx.db.get(userId);
    if (!user) throw new Error("USER_NOT_FOUND");
    const valid = new Set(["public", "friends", "nobody"]);
    const reqValid = new Set(["public", "nobody"]);
    function pick(level: string | undefined, allowed: Set<string>): string | undefined {
      if (level === undefined) return undefined;
      return allowed.has(level) ? level : undefined;
    }
    // Strip any legacy `bio` key from the stored visibility object before
    // merging — old records may still carry it and the new schema rejects it.
    const prev = { ...(user.visibility ?? {}) } as Record<string, unknown>;
    delete prev.bio;
    const next = {
      ...prev,
      ...(avatar !== undefined ? { avatar: pick(avatar, valid) } : {}),
      ...(status !== undefined ? { status: pick(status, valid) } : {}),
      ...(lastSeen !== undefined ? { lastSeen: pick(lastSeen, valid) } : {}),
      ...(seen !== undefined ? { seen: pick(seen, valid) } : {}),
      ...(friendRequests !== undefined
        ? { friendRequests: pick(friendRequests, reqValid) }
        : {}),
    };
    await ctx.db.patch(userId, { visibility: next });
  },
});

export const updateProfile = mutation({
  args: {
    userId: v.id("users"),
    name: v.string(),
    email: v.optional(v.string()),
    bio: v.optional(v.string()),
  },
  handler: async (ctx, { userId, name, email, bio }) => {
    const user = await ctx.db.get(userId);
    if (!user) throw new Error("USER_NOT_FOUND");
    await ctx.db.patch(userId, {
      name: name.trim(),
      email: email && email.length > 0 ? email : undefined,
      bio: bio && bio.length > 0 ? bio : undefined,
    });
  },
});

export const updateAvatar = mutation({
  args: {
    userId: v.id("users"),
    storageId: v.id("_storage"),
  },
  handler: async (ctx, { userId, storageId }) => {
    const user = await ctx.db.get(userId);
    if (!user) throw new Error("USER_NOT_FOUND");
    await ctx.db.patch(userId, { avatarStorageId: storageId });
  },
});

export const searchUsers = query({
  args: { query: v.string(), currentUserId: v.id("users") },
  handler: async (ctx, { query: q, currentUserId }) => {
    // Collect ids that should be hidden: anyone *I* have blocked OR who has
    // blocked *me* (in both directions — invisibility is symmetric).
    const blockedByMe = await ctx.db
      .query("blocks")
      .withIndex("by_user", (qb) => qb.eq("userId", currentUserId))
      .collect();
    const blockingMe = await ctx.db
      .query("blocks")
      .collect();
    const hidden = new Set<string>();
    for (const b of blockedByMe) hidden.add(b.blockedUserId.toString());
    for (const b of blockingMe) {
      if (b.blockedUserId.toString() === currentUserId.toString()) {
        hidden.add(b.userId.toString());
      }
    }

    const users = await ctx.db.query("users").collect();
    const filtered = users
      .filter(
        (u) =>
          u._id !== currentUserId &&
          !hidden.has(u._id.toString()) &&
          (u.username.toLowerCase().includes(q.toLowerCase()) ||
            (u.name ?? "").toLowerCase().includes(q.toLowerCase()))
      )
      .slice(0, 20);

    const enriched = await Promise.all(
      filtered.map(async (u) => {
        const outgoing = await ctx.db
          .query("friendships")
          .withIndex("by_pair", (query) =>
            query.eq("userId", currentUserId).eq("friendId", u._id)
          )
          .first();
        const incoming = await ctx.db
          .query("friendships")
          .withIndex("by_pair", (query) =>
            query.eq("userId", u._id).eq("friendId", currentUserId)
          )
          .first();

        let friendshipStatus = "none";
        let requestId = undefined;
        if (outgoing?.status === "accepted" || incoming?.status === "accepted") {
          friendshipStatus = "friend";
        } else if (outgoing?.status === "pending") {
          friendshipStatus = "outgoingPending";
          requestId = outgoing._id;
        } else if (incoming?.status === "pending") {
          friendshipStatus = "incomingPending";
          requestId = incoming._id;
        }

        return {
          _id: u._id,
          username: u.username,
          name: u.name ?? u.username,
          status: u.status,
          avatarStorageId: u.avatarStorageId,
          friendshipStatus,
          requestId,
        };
      })
    );

    return enriched;
  },
});

// ─────────────────────────────── Blocking ───────────────────────────────

export const blockUser = mutation({
  args: {
    userId: v.id("users"),
    targetUserId: v.id("users"),
    /**
     * When true, also wipes the shared DM room between the two users
     * (messages, reactions, media, the room itself, and both memberships).
     * Group rooms the two share are NOT touched — the blocker can leave
     * those manually. The target is never notified either way.
     */
    deleteDm: v.optional(v.boolean()),
  },
  handler: async (ctx, { userId, targetUserId, deleteDm }) => {
    if (userId.toString() === targetUserId.toString()) {
      throw new Error("CANT_BLOCK_SELF");
    }
    // Idempotent: don't insert if a pair row already exists.
    const existing = await ctx.db
      .query("blocks")
      .withIndex("by_pair", (q) =>
        q.eq("userId", userId).eq("blockedUserId", targetUserId)
      )
      .first();
    if (!existing) {
      await ctx.db.insert("blocks", {
        userId,
        blockedUserId: targetUserId,
        createdAt: Date.now(),
      });
    }

    // Tear down any existing friendship so the block is binding.
    const friendships = await ctx.db
      .query("friendships")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();
    for (const f of friendships) {
      if (f.friendId.toString() === targetUserId.toString()) {
        await ctx.db.delete(f._id);
      }
    }
    const reverse = await ctx.db
      .query("friendships")
      .withIndex("by_user", (q) => q.eq("userId", targetUserId))
      .collect();
    for (const f of reverse) {
      if (f.friendId.toString() === userId.toString()) {
        await ctx.db.delete(f._id);
      }
    }

    if (deleteDm) {
      // Find the DM room the two share. DM rooms are named
      //   `dm:<roomKey>:<sortedIdA>:<sortedIdB>`  (see rooms.getOrCreateDM).
      // We don't know which roomKey was used, so we walk both members'
      // memberships and pick rooms whose name starts with "dm:" and whose
      // other member is the target.
      const myRooms = await ctx.db
        .query("roomMembers")
        .withIndex("by_user", (q) => q.eq("userId", userId))
        .collect();
      for (const m of myRooms) {
        const room = await ctx.db.get(m.roomId);
        if (!room || !room.name?.startsWith("dm:")) continue;
        // Confirm target is the other member.
        const otherMember = await ctx.db
          .query("roomMembers")
          .withIndex("by_room_user", (q) =>
            q.eq("roomId", m.roomId).eq("userId", targetUserId)
          )
          .first();
        if (!otherMember) continue;
        await _wipeRoomCompletely(ctx, m.roomId);
      }
    }
  },
});

/**
 * Helper: delete every trace of a room — messages, their reactions, their
 * media, typing rows, memberships, and the room itself.
 */
async function _wipeRoomCompletely(ctx: any, roomId: any) {
  // Messages → reactions + media + row
  const msgs = await ctx.db
    .query("messages")
    .withIndex("by_room", (q: any) => q.eq("roomId", roomId))
    .collect();
  for (const msg of msgs) {
    const reactions = await ctx.db
      .query("reactions")
      .withIndex("by_message", (q: any) => q.eq("messageId", msg._id))
      .collect();
    for (const r of reactions) await ctx.db.delete(r._id);
    if (msg.mediaStorageId) {
      try {
        await ctx.storage.delete(msg.mediaStorageId);
      } catch (_) {/* already gone */}
    }
    await ctx.db.delete(msg._id);
  }
  // Memberships
  const members = await ctx.db
    .query("roomMembers")
    .withIndex("by_room", (q: any) => q.eq("roomId", roomId))
    .collect();
  for (const m of members) await ctx.db.delete(m._id);
  // Typing indicators
  const typing = await ctx.db
    .query("typingIndicators")
    .withIndex("by_room", (q: any) => q.eq("roomId", roomId))
    .collect();
  for (const t of typing) await ctx.db.delete(t._id);
  // The room itself
  await ctx.db.delete(roomId);
}

export const unblockUser = mutation({
  args: { userId: v.id("users"), targetUserId: v.id("users") },
  handler: async (ctx, { userId, targetUserId }) => {
    const existing = await ctx.db
      .query("blocks")
      .withIndex("by_pair", (q) =>
        q.eq("userId", userId).eq("blockedUserId", targetUserId)
      )
      .first();
    if (existing) {
      await ctx.db.delete(existing._id);
    }
  },
});

/**
 * Returns the user-profiles this account has blocked, including the
 * blocked person's username/name/avatar so the UI can render an unblock list.
 */
export const listBlocked = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const rows = await ctx.db
      .query("blocks")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();
    const out: Array<{
      _id: string;
      username: string;
      name: string;
      avatarStorageId?: string;
    }> = [];
    for (const r of rows) {
      const u = await ctx.db.get(r.blockedUserId);
      if (!u) continue;
      out.push({
        _id: u._id.toString(),
        username: u.username,
        name: u.name ?? u.username,
        avatarStorageId: u.avatarStorageId,
      });
    }
    return out;
  },
});

/**
 * True when EITHER user has blocked the other — used by clients before
 * showing message-send or friend-request UI. The backend should ALSO check
 * inside sendRequest/sendMessage; this is convenience.
 */
export const isBlocked = query({
  args: { userId: v.id("users"), otherUserId: v.id("users") },
  handler: async (ctx, { userId, otherUserId }) => {
    const a = await ctx.db
      .query("blocks")
      .withIndex("by_pair", (q) =>
        q.eq("userId", userId).eq("blockedUserId", otherUserId)
      )
      .first();
    if (a) return true;
    const b = await ctx.db
      .query("blocks")
      .withIndex("by_pair", (q) =>
        q.eq("userId", otherUserId).eq("blockedUserId", userId)
      )
      .first();
    return !!b;
  },
});

// ─────────────────────────────── Reporting ───────────────────────────────

export const report = mutation({
  args: {
    reporterId: v.id("users"),
    targetType: v.string(), // "user" | "message" | "room"
    targetId: v.string(),
    reason: v.string(),
    note: v.optional(v.string()),
  },
  handler: async (ctx, { reporterId, targetType, targetId, reason, note }) => {
    if (!["user", "message", "room"].includes(targetType)) {
      throw new Error("INVALID_TARGET_TYPE");
    }
    await ctx.db.insert("reports", {
      reporterId,
      targetType,
      targetId,
      reason,
      note: note && note.length > 0 ? note : undefined,
      createdAt: Date.now(),
      status: "open",
    });
  },
});
