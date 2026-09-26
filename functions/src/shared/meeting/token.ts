import {createHmac, createSign} from "crypto";

/**
 * The proof that somebody is allowed into a class, signed by this server.
 *
 * ## Why this exists
 *
 * Jitsi asked people to sign in. Not because of anything in this app --
 * the public deployment, meet.jit.si, requires the first person into a
 * room to authenticate with Google, Facebook or GitHub. No client flag
 * turns that off, because it is not the client's decision: a server that
 * demands a token demands a token.
 *
 * Asking a teacher to hold a Google account is bad. Asking a class of
 * ten-year-olds to is worse -- most of them do not have one, and the
 * ones who do would be signing children into a third party's account
 * system to attend a lesson at their own school.
 *
 * They are already signed in. They signed into LogicClass. So LogicClass
 * says who they are, in a token Jitsi accepts, and nobody is asked
 * anything. That is what a built-in class means.
 *
 * ## What is in it
 *
 * Only what the meeting needs: a display name, whether this person runs
 * the lesson, and the one room it is good for. No email unless the
 * account has one, no student number, no section, no school name -- a
 * JWT is not encrypted, it sits in a URL and in the browser's memory,
 * and every claim in it is readable by anybody who sees it.
 *
 * `room` is the important one. A token minted for one lesson must not
 * open another, or a student who attended Monday's class holds a key to
 * every class after it.
 */
export interface MeetingIdentity {
  /** Shown to the class. */
  name: string;
  /** Optional: many pupil accounts have none, and it is not required. */
  email?: string;
  /** The teacher runs the lesson; everybody else attends it. */
  moderator: boolean;
  /** The single room this token opens. */
  room: string;
  /** Seconds since the epoch. Injected so the claims can be tested. */
  now: number;
}

/**
 * What a deployment needs before it can be trusted to issue tokens.
 *
 * Absent means an unconfigured deployment, and that is a supported
 * state rather than an error: the app falls back to joining without a
 * token, which is what it did before this existed.
 */
export interface MeetingTokenConfig {
  /** `app_id` on a self-hosted Jitsi; the AppID on a JaaS tenant. */
  appId: string;
  /** HS256 shared secret. Self-hosted Jitsi's `app_secret`. */
  appSecret?: string;
  /** RS256 private key, PEM. JaaS issues these. */
  privateKey?: string;
  /** The `kid` header JaaS requires alongside its private key. */
  keyId?: string;
  /** Who the token is for. `sub` on the claims. */
  audienceDomain: string;
}

/** How long a token is good for. */
const LIFETIME_SECONDS = 4 * 60 * 60;

/**
 * A token is not valid until slightly before it was issued.
 *
 * Jitsi checks `nbf` against its own clock, and a server thirty seconds
 * ahead of ours would reject a token the moment it was made. The cost of
 * this leeway is that a token is valid thirty seconds early, which is
 * worth nothing to anybody.
 */
const CLOCK_SKEW_SECONDS = 30;

/**
 * The claims Jitsi reads, and nothing else.
 *
 * Pure, so what a token says about a person is testable without a
 * signing key or a Firestore.
 */
export function buildMeetingClaims(
  identity: MeetingIdentity,
  config: MeetingTokenConfig
): Record<string, unknown> {
  // Two deployments, two sets of names for the same three claims, and
  // getting them wrong means every token is rejected with no clue why.
  //
  // A self-hosted Jitsi checks `iss` and `aud` against the `app_id` in
  // its prosody config, and reads `sub` as the domain the room lives
  // on. JaaS ignores all of that and wants fixed strings -- `chat` and
  // `jitsi` -- with the tenant in `sub` instead.
  //
  // Which one is in front of us is decided by the key: JaaS issues an
  // RSA private key, a self-hosted install has a shared secret.
  return {
    aud: config.privateKey ? "jitsi" : config.appId,
    iss: config.privateKey ? "chat" : config.appId,
    sub: config.privateKey ? config.appId : config.audienceDomain,
    // The room, not "*". A wildcard token is a key to every lesson the
    // school will ever hold, handed to a ten-year-old.
    room: identity.room,
    nbf: identity.now - CLOCK_SKEW_SECONDS,
    exp: identity.now + LIFETIME_SECONDS,
    iat: identity.now,
    context: {
      user: {
        name: identity.name,
        // Only when there is one. `undefined` is dropped by JSON.stringify,
        // so an account without an email claims nothing rather than
        // claiming an empty one.
        email: identity.email || undefined,
        moderator: identity.moderator,
        // Nobody is anonymous in a school's lesson: the register is the
        // point, and a name that cannot be changed from the browser is
        // part of that.
        "hidden-from-recorder": false,
      },
      features: {
        // A lesson is not a broadcast and not a recording studio. These
        // are refused in the token rather than hidden in the toolbar,
        // because a hidden button is a button a determined teenager
        // finds and a refused feature is one the server will not run.
        livestreaming: false,
        recording: false,
        transcription: false,
        "outbound-call": false,
      },
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
 * Signs [claims] into a JWT.
 *
 * Written against node's own crypto rather than a JWT library, because
 * the whole of it is three base64url segments and a signature, and a
 * dependency that signs things is a dependency worth not having.
 *
 * HS256 when a shared secret is configured -- what a self-hosted Jitsi
 * uses. RS256 when a private key is, which is what JaaS issues. Neither
 * configured is not an error: see [meetingTokenConfig].
 */
export function signMeetingToken(
  claims: Record<string, unknown>,
  config: MeetingTokenConfig
): string {
  const rsa = !!config.privateKey;
  const header: Record<string, unknown> = {
    alg: rsa ? "RS256" : "HS256",
    typ: "JWT",
  };
  if (rsa && config.keyId) header.kid = config.keyId;

  const signingInput =
    `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;

  const signature = rsa ?
    base64url(createSign("RSA-SHA256").update(signingInput).sign(config.privateKey!)) :
    base64url(createHmac("sha256", config.appSecret!).update(signingInput).digest());

  return `${signingInput}.${signature}`;
}

/**
 * The deployment's signing configuration, or null when there is none.
 *
 * Null is the default and it is not a failure. A school that has not
 * pointed this at its own Jitsi gets what it got before: an
 * unauthenticated join, which works on a deployment that does not ask
 * and shows Jitsi's own sign-in on one that does. Set these and the
 * sign-in goes away for everybody:
 *
 *   JITSI_APP_ID        the tenant. `app_id` self-hosted, AppID on JaaS
 *   JITSI_APP_SECRET    self-hosted: the matching `app_secret`
 *   JITSI_PRIVATE_KEY   JaaS instead: the RSA private key, PEM
 *   JITSI_KEY_ID        JaaS: the key's id, which goes in the header
 *   JITSI_DOMAIN        the deployment, for the `sub` claim
 *
 * A private key pasted into an environment variable arrives with its
 * newlines escaped more often than not, so they are put back.
 */
export function meetingTokenConfig(
  env: NodeJS.ProcessEnv = process.env
): MeetingTokenConfig | null {
  const appId = env.JITSI_APP_ID?.trim();
  const appSecret = env.JITSI_APP_SECRET?.trim();
  const privateKey = env.JITSI_PRIVATE_KEY?.trim().replace(/\\n/g, "\n");
  if (!appId) return null;
  if (!appSecret && !privateKey) return null;
  return {
    appId,
    appSecret: appSecret || undefined,
    privateKey: privateKey || undefined,
    keyId: env.JITSI_KEY_ID?.trim() || undefined,
    audienceDomain: env.JITSI_DOMAIN?.trim() || "meet.jitsi",
  };
}
