import {createHmac} from "crypto";

/**
 * The pass into a class held through a media server.
 *
 * A mesh call -- every browser sending its own video to every other --
 * carries about six people. A Philippine secondary class is sixty, which
 * in a mesh is fifty-nine uploads from one laptop: not slow, impossible.
 * A media server (an SFU) takes one stream from each person and forwards
 * it, so a class of sixty costs a participant what a call of six does.
 *
 * LiveKit is that server. What matters here is that **the app draws the
 * video itself** -- Flutter widgets over tracks, no iframe -- so there is
 * no third-party document for a server to refuse to embed, which is the
 * wall two public Jitsi deployments put the whole feature into.
 *
 * The token is the entitlement this school already decided, said in the
 * form LiveKit reads. Same rule as everywhere else in this module: the
 * caller names a session, the server reads the room off the document
 * that proves they belong in it, and the token is good for that one
 * room.
 */
export interface LiveKitGrant {
  /** Shown to the class, and written on the register. */
  name: string;
  /** Stable per person, so a rejoin replaces rather than duplicates. */
  identity: string;
  /** The one room this opens. */
  room: string;
  /** The teacher, who may remove somebody from the lesson. */
  moderator: boolean;
  /** Seconds since the epoch. Injected so the claims can be tested. */
  now: number;
}

export interface LiveKitConfig {
  apiKey: string;
  apiSecret: string;
  /** The server the client connects to, e.g. wss://x.livekit.cloud. */
  url: string;
}

/** As long as a very long lesson, and no longer. */
const LIFETIME_SECONDS = 6 * 60 * 60;

/** Jitter between this server's clock and LiveKit's. */
const CLOCK_SKEW_SECONDS = 30;

/**
 * The claims LiveKit reads, and nothing beyond them.
 *
 * `roomJoin` with a named `room` is the whole of the access control: a
 * token cannot be used to enter a different lesson, and `roomCreate` is
 * absent so it cannot be used to invent one.
 */
export function buildLiveKitClaims(
  grant: LiveKitGrant,
  config: LiveKitConfig
): Record<string, unknown> {
  return {
    iss: config.apiKey,
    sub: grant.identity,
    nbf: grant.now - CLOCK_SKEW_SECONDS,
    exp: grant.now + LIFETIME_SECONDS,
    // Shown to the class. A register that matches faces to names cannot
    // do it against a grid of nicknames.
    name: grant.name,
    video: {
      room: grant.room,
      roomJoin: true,
      // Absent on purpose: a token that can create rooms is a token
      // that can hold a lesson nobody is on the register for.
      canPublish: true,
      canSubscribe: true,
      // The teacher only. What travels here is the board -- a stroke,
      // a rub, a wipe -- drawn over whatever is being shared.
      //
      // Children still cannot send data, which is the point the
      // original rule was making: chat, if it ever exists, belongs on
      // the school's own record and not in an untracked side channel
      // between children. Receiving needs no permission, so a class
      // sees the teacher's pencil without being able to hold one.
      canPublishData: grant.moderator,
      // A pupil putting their hand up, and answering "yes" without
      // unmuting. It is one small labelled value they set on
      // themselves, replacing whatever was there -- not a stream
      // anybody can write into, not addressable to one child, and
      // visible to the teacher and attributable to whoever set it.
      //
      // That is the difference from canPublishData above, which is a
      // channel and stays with the teacher. Anything unrecognised in
      // the field is ignored on the way in: see app/lib/core/meeting/hands.dart.
      canUpdateOwnMetadata: true,
      // The teacher can remove somebody from the lesson. A child who
      // can do that to the teacher is a child who will.
      roomAdmin: grant.moderator,
    },
  };
}

function base64url(value: Buffer | string): string {
  return Buffer.from(value)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/**
 * Signs [claims]. LiveKit verifies HS256 against the API secret.
 *
 * Node's own crypto rather than a JWT library: the whole of it is three
 * base64url segments and a signature, and a dependency that signs
 * things is a dependency worth not having.
 */
export function signLiveKitToken(
  claims: Record<string, unknown>,
  config: LiveKitConfig
): string {
  const input =
    `${base64url(JSON.stringify({alg: "HS256", typ: "JWT"}))}.` +
    `${base64url(JSON.stringify(claims))}`;
  const signature = createHmac("sha256", config.apiSecret).update(input).digest();
  return `${input}.${base64url(signature)}`;
}

/**
 * The deployment's media server, or null when there is none.
 *
 * Null is a supported state and not a failure: without it the app falls
 * back to a direct call between browsers, which works and carries about
 * six people. It is what a school gets before it has configured
 * anything, and it is why the class-size ceiling is a thing the screens
 * talk about.
 *
 *   LIVEKIT_URL         wss://<project>.livekit.cloud, or your own
 *   LIVEKIT_API_KEY     from the LiveKit console
 *   LIVEKIT_API_SECRET  its secret. Anyone holding it can mint entry
 *                       to any lesson.
 */
export function liveKitConfig(
  env: NodeJS.ProcessEnv = process.env
): LiveKitConfig | null {
  const url = env.LIVEKIT_URL?.trim();
  const apiKey = env.LIVEKIT_API_KEY?.trim();
  const apiSecret = env.LIVEKIT_API_SECRET?.trim();
  if (!url || !apiKey || !apiSecret) return null;
  return {url, apiKey, apiSecret};
}
