import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  users: defineTable({
    username: v.string(),
    passwordHash: v.string(),
    recoveryKeyHash: v.optional(v.string()),
    createdAt: v.number(),
    status: v.optional(v.string()), // "online", "away", "offline"
    lastSeen: v.optional(v.number()),
    bio: v.optional(v.string()),
  }).index("by_username", ["username"]),

  friendships: defineTable({
    userId: v.id("users"),
    friendId: v.id("users"),
    status: v.string(), // "pending", "accepted"
    createdAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_friend", ["friendId"])
    .index("by_pair", ["userId", "friendId"]),

  rooms: defineTable({
    name: v.string(),
    description: v.optional(v.string()),
    createdBy: v.id("users"),
    createdAt: v.number(),
    isPrivate: v.boolean(),
    memberCount: v.number(),
    passwordHash: v.optional(v.string()),
  }).index("by_name", ["name"]),

  roomMembers: defineTable({
    roomId: v.id("rooms"),
    userId: v.id("users"),
    joinedAt: v.number(),
    role: v.string(), // "owner", "member"
  })
    .index("by_room", ["roomId"])
    .index("by_user", ["userId"])
    .index("by_room_user", ["roomId", "userId"]),

  messages: defineTable({
    roomId: v.id("rooms"),
    userId: v.id("users"),
    content: v.string(),
    createdAt: v.number(),
    edited: v.optional(v.boolean()),
  })
    .index("by_room", ["roomId"])
    .index("by_room_time", ["roomId", "createdAt"]),
});
