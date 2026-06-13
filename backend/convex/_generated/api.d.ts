/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as auth from "../auth.js";
import type * as calls from "../calls.js";
import type * as crons from "../crons.js";
import type * as files from "../files.js";
import type * as friends from "../friends.js";
import type * as messages from "../messages.js";
import type * as notifications from "../notifications.js";
import type * as reactions from "../reactions.js";
import type * as rooms from "../rooms.js";
import type * as typing from "../typing.js";
import type * as users from "../users.js";
import type * as voipPush from "../voipPush.js";
import type * as voipTokens from "../voipTokens.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  auth: typeof auth;
  calls: typeof calls;
  crons: typeof crons;
  files: typeof files;
  friends: typeof friends;
  messages: typeof messages;
  notifications: typeof notifications;
  reactions: typeof reactions;
  rooms: typeof rooms;
  typing: typeof typing;
  users: typeof users;
  voipPush: typeof voipPush;
  voipTokens: typeof voipTokens;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
