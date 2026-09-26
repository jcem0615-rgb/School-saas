import {createHmac, createVerify, generateKeyPairSync} from "crypto";
import {
  buildMeetingClaims,
  meetingTokenConfig,
  signMeetingToken,
  MeetingTokenConfig,
} from "../../../src/shared/meeting/token";

const NOW = 1_764_000_000;

const hs256: MeetingTokenConfig = {
  appId: "logicclass",
  appSecret: "a shared secret nobody outside the school has",
  audienceDomain: "meet.example.ph",
};

function decode(token: string): {header: Record<string, unknown>; claims: Record<string, unknown>} {
  const [header, claims] = token.split(".");
  return {
    header: JSON.parse(Buffer.from(header, "base64url").toString()),
    claims: JSON.parse(Buffer.from(claims, "base64url").toString()),
  };
}

/// The token is what stops Jitsi asking a class of children to sign in
/// with a Google account, so it is tested as a credential: what it says
/// about a person, and what it does not open.
describe("the pass that gets one person into one lesson", () => {
  describe("what it claims", () => {
    it("is good for exactly the one room", () => {
      // A wildcard token is a key to every lesson the school will ever
      // hold, handed to a ten-year-old.
      const claims = buildMeetingClaims(
        {name: "Ana Cruz", moderator: false, room: "lc-abcdefghijklmnopqrst", now: NOW},
        hs256
      );
      expect(claims.room).toBe("lc-abcdefghijklmnopqrst");
      expect(claims.room).not.toBe("*");
    });

    it("says nothing about the child beyond their name", () => {
      // A JWT is signed, not encrypted: it sits in a URL and everything
      // in it is readable by anyone who sees it.
      const claims = buildMeetingClaims(
        {name: "Ana Cruz", moderator: false, room: "lc-abcdefghijklmnopqrst", now: NOW},
        hs256
      );
      const printed = JSON.stringify(claims);
      expect(printed).not.toMatch(/grade|section|student.?number|school/i);
    });

    it("claims no email when the account has none", () => {
      const claims = buildMeetingClaims(
        {name: "Ana Cruz", moderator: false, room: "lc-abcdefghijklmnopqrst", now: NOW},
        hs256
      );
      const user = (claims.context as Record<string, Record<string, unknown>>).user;
      expect("email" in JSON.parse(JSON.stringify(user))).toBe(false);
    });

    it("carries an email when there is one", () => {
      const claims = buildMeetingClaims(
        {
          name: "Ms Santos",
          email: "santos@example.ph",
          moderator: true,
          room: "lc-abcdefghijklmnopqrst",
          now: NOW,
        },
        hs256
      );
      const user = (claims.context as Record<string, Record<string, unknown>>).user;
      expect(user.email).toBe("santos@example.ph");
    });

    it("makes the teacher the moderator and nobody else", () => {
      const teacher = buildMeetingClaims(
        {name: "Ms Santos", moderator: true, room: "lc-a", now: NOW},
        hs256
      );
      const pupil = buildMeetingClaims(
        {name: "Ana Cruz", moderator: false, room: "lc-a", now: NOW},
        hs256
      );
      const user = (c: Record<string, unknown>) =>
        (c.context as Record<string, Record<string, unknown>>).user;
      expect(user(teacher).moderator).toBe(true);
      expect(user(pupil).moderator).toBe(false);
    });

    it("refuses recording and streaming in the token, not in the toolbar", () => {
      // A hidden button is a button a determined teenager finds.
      const claims = buildMeetingClaims(
        {name: "Ana Cruz", moderator: false, room: "lc-a", now: NOW},
        hs256
      );
      const features = (claims.context as Record<string, Record<string, unknown>>).features;
      expect(features.recording).toBe(false);
      expect(features.livestreaming).toBe(false);
      expect(features.transcription).toBe(false);
    });

    it("expires, and allows for a server clock that is not ours", () => {
      const claims = buildMeetingClaims(
        {name: "Ana Cruz", moderator: false, room: "lc-a", now: NOW},
        hs256
      );
      expect(claims.iat).toBe(NOW);
      expect(claims.nbf as number).toBeLessThan(NOW);
      expect(claims.exp as number).toBeGreaterThan(NOW);
      // Long enough for a double period plus a lesson that overruns,
      // short enough that a leaked token is not a term pass.
      expect((claims.exp as number) - NOW).toBeLessThanOrEqual(4 * 60 * 60);
    });
  });

  describe("the two deployments name the same claims differently", () => {
    it("a self-hosted Jitsi is told its own app id, and the domain", () => {
      // It checks iss and aud against the app_id in its prosody config
      // and reads sub as the domain the room lives on.
      const claims = buildMeetingClaims(
        {name: "Ana", moderator: false, room: "lc-a", now: NOW},
        hs256
      );
      expect(claims.iss).toBe("logicclass");
      expect(claims.aud).toBe("logicclass");
      expect(claims.sub).toBe("meet.example.ph");
    });

    it("JaaS is told the fixed strings it insists on, and the tenant", () => {
      // It ignores app_id in iss/aud entirely and wants "chat" and
      // "jitsi", with the tenant in sub. Sending it the self-hosted
      // shape gets every token rejected with no clue why -- which is
      // what this used to do.
      const claims = buildMeetingClaims(
        {name: "Ana", moderator: false, room: "lc-a", now: NOW},
        {
          appId: "vpaas-magic-cookie-1234",
          privateKey: "-----BEGIN PRIVATE KEY-----",
          keyId: "vpaas-magic-cookie-1234/abc123",
          audienceDomain: "8x8.vc",
        }
      );
      expect(claims.iss).toBe("chat");
      expect(claims.aud).toBe("jitsi");
      expect(claims.sub).toBe("vpaas-magic-cookie-1234");
    });
  });

  describe("how it is signed", () => {
    it("is verifiable with the shared secret, and only that one", () => {
      const token = signMeetingToken(
        buildMeetingClaims({name: "Ana", moderator: false, room: "lc-a", now: NOW}, hs256),
        hs256
      );
      const [header, claims, signature] = token.split(".");
      const expected = createHmac("sha256", hs256.appSecret!)
        .update(`${header}.${claims}`)
        .digest("base64url");
      expect(signature).toBe(expected);

      const forged = createHmac("sha256", "the wrong secret")
        .update(`${header}.${claims}`)
        .digest("base64url");
      expect(signature).not.toBe(forged);
    });

    it("signs with RSA when a private key is configured, and names the key", () => {
      // What JaaS issues. The kid header is how their edge finds the
      // public half; without it every token is rejected.
      const {privateKey, publicKey} = generateKeyPairSync("rsa", {
        modulusLength: 2048,
        privateKeyEncoding: {type: "pkcs8", format: "pem"},
        publicKeyEncoding: {type: "spki", format: "pem"},
      });
      const config: MeetingTokenConfig = {
        appId: "vpaas-magic-cookie-1234",
        privateKey,
        keyId: "vpaas-magic-cookie-1234/abc123",
        audienceDomain: "8x8.vc",
      };
      const token = signMeetingToken(
        buildMeetingClaims({name: "Ana", moderator: false, room: "lc-a", now: NOW}, config),
        config
      );
      const {header} = decode(token);
      expect(header.alg).toBe("RS256");
      expect(header.kid).toBe("vpaas-magic-cookie-1234/abc123");

      const [h, c, signature] = token.split(".");
      const verified = createVerify("RSA-SHA256")
        .update(`${h}.${c}`)
        .verify(publicKey, Buffer.from(signature, "base64url"));
      expect(verified).toBe(true);
    });

    it("produces three base64url segments with nothing needing escaping", () => {
      // It travels in a URL.
      const token = signMeetingToken(
        buildMeetingClaims(
          {name: "Ñoño Dela Cruz-Reyes", moderator: false, room: "lc-a", now: NOW},
          hs256
        ),
        hs256
      );
      expect(token.split(".")).toHaveLength(3);
      expect(token).toMatch(/^[A-Za-z0-9_.-]+$/);
      expect(encodeURIComponent(token)).toBe(token);
    });
  });

  describe("when the school has not configured one", () => {
    it("is null rather than an error", () => {
      // An unconfigured school still holds lessons; it just gets
      // whatever its Jitsi does without a token.
      expect(meetingTokenConfig({} as NodeJS.ProcessEnv)).toBeNull();
    });

    it("is null when there is an app id but nothing to sign with", () => {
      // Half-configured is the dangerous shape: it looks set up.
      expect(
        meetingTokenConfig({JITSI_APP_ID: "logicclass"} as NodeJS.ProcessEnv)
      ).toBeNull();
    });

    it("reads a shared secret", () => {
      const config = meetingTokenConfig({
        JITSI_APP_ID: "logicclass",
        JITSI_APP_SECRET: "shhh",
        JITSI_DOMAIN: "meet.example.ph",
      } as NodeJS.ProcessEnv);
      expect(config).toEqual({
        appId: "logicclass",
        appSecret: "shhh",
        privateKey: undefined,
        keyId: undefined,
        audienceDomain: "meet.example.ph",
      });
    });

    it("puts the newlines back into a pasted private key", () => {
      // A PEM pasted into an environment variable arrives with its
      // newlines escaped more often than not, and a key that is one
      // long line will not load.
      const config = meetingTokenConfig({
        JITSI_APP_ID: "vpaas-magic-cookie-1234",
        JITSI_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\\nMIIE\\n-----END PRIVATE KEY-----",
      } as NodeJS.ProcessEnv);
      expect(config!.privateKey).toBe(
        "-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----"
      );
    });
  });
});
