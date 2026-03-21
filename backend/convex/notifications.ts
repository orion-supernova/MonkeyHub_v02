import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";

// Required Convex environment variables (set in Convex dashboard → Settings → Environment Variables):
//   ONESIGNAL_API_KEY  — REST API key from OneSignal dashboard → Settings → Keys & IDs
//
// The App ID is hardcoded (same as PushNotificationManager.swift — not a secret).

const ONESIGNAL_APP_ID = "c191a9f0-15cf-402a-8a04-dcc16108f4b0";
const ONESIGNAL_BASE = "https://api.onesignal.com";

export const sendMessagePush = internalAction({
  args: {
    roomId: v.id("rooms"),
    messageId: v.id("messages"),
    senderId: v.id("users"),
    senderName: v.string(),
    content: v.string(),
    type: v.string(),
  },
  handler: async (ctx, { roomId, senderId, senderName, content, type }) => {
    const apiKey = process.env.ONESIGNAL_API_KEY;

    if (!apiKey) {
      console.error(
        "sendMessagePush: ONESIGNAL_API_KEY env var is not set — push skipped."
      );
      return;
    }

    // Fetch all room members except the sender
    const members: Array<{ userId: string }> = await ctx.runQuery(
      internal.rooms.getMemberIds,
      { roomId, excludeUserId: senderId }
    );

    if (members.length === 0) return;

    const externalIds = members.map((m) => m.userId.toString());

    const body =
      type === "text"
        ? content
        : type === "image"
        ? "📷 Image"
        : type === "video"
        ? "🎥 Video"
        : type === "audio"
        ? "🎵 Audio"
        : "New message";

    // Use the OneSignal v5 User Model API: target users by external_id via
    // include_aliases + target_channel. This lets OneSignal resolve the correct
    // subscription server-side — no client-side subscription ID fetch needed.
    // This is the only approach that is race-condition free when a device switches
    // between APNs environments (Xcode dev ↔ TestFlight prod).
    const payload = {
      app_id: ONESIGNAL_APP_ID,
      target_channel: "push",
      include_aliases: {
        external_id: externalIds,
      },
      headings: { en: senderName },
      contents: { en: body },
      data: {
        roomId: roomId.toString(),
        senderId: senderId.toString(),
        senderName,
        content: body,
        type,
      },
      ios_badgeType: "Increase",
      ios_badgeCount: 1,
      ios_category: "CHAT_MESSAGE",
    };

    console.log(
      `sendMessagePush: targeting ${externalIds.length} user(s) by external_id`
    );

    const response = await fetch(`${ONESIGNAL_BASE}/notifications`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Key ${apiKey}`,
      },
      body: JSON.stringify(payload),
    });

    const responseText = await response.text();

    if (!response.ok) {
      console.error(
        `sendMessagePush: OneSignal API error (HTTP ${response.status}): ${responseText}`
      );
    } else {
      console.log(`sendMessagePush: OneSignal accepted — ${responseText}`);
    }
  },
});
