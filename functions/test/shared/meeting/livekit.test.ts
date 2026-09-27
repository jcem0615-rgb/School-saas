import {createHmac} from "crypto";
import {
  buildLiveKitClaims,
  liveKitConfig,
  signLiveKitToken,
  LiveKitConfig,
} from "../../../src/shared/meeting/livekit";

const NOW = 1_764_000_000;
const config: LiveKitConfig = {
  apiKey: "APIabc123",
  apiSecret: "a secret nobody outside the school has",
  url: "wss://school.livekit.cloud",
};

function claimsOf(token: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
}

const teacher = {
  name: "Ms Santos",
  identity: "faculty_1",
  room: "lc-abcdefghijklmnopqrst",
  moderator: true,
  now: NOW,
};
const pupil = {...teacher, name: "Ana Cruz", identity: "student_1", moderator: false};

/// The pass into a class held through a media server -- the only shape
/// that carries sixty people, and the one the app draws itself.
describe("the pass into a forwarded class", () => {
  describe("what it opens", () => {
    it("is one room, and joining it", () => {
      const video = buildLiveKitClaims(pupil, config).video as Record<string, unknown>;
      expect(video.room).toBe("lc-abcdefghijklmnopqrst");
      expect(video.roomJoin).toBe(true);
    });

    it("cannot invent a room of its own", () => {
      // roomCreate absent on purpose: a token that can make rooms is a
      // token that can hold a lesson nobody is on the register for.
      const video = buildLiveKitClaims(teacher, config).video as Record<string, unknown>;
      expect(video.roomCreate).toBeUndefined();
    });

    it("cannot open a different lesson", () => {
      const a = buildLiveKitClaims(pupil, config).video as Record<string, unknown>;
      const b = buildLiveKitClaims(
        {...pupil, room: "lc-zyxwvutsrqponmlkjihg"},
        config
      ).video as Record<string, unknown>;
      expect(a.room).not.toBe(b.room);
    });
  });

  describe("who it says they are", () => {
    it("carries the name the register knows", () => {
      // A register matching faces to names cannot do it against a grid
      // of nicknames.
      expect(buildLiveKitClaims(pupil, config).name).toBe("Ana Cruz");
    });

    it("is stable per person, so a rejoin is not a ghost", () => {
      // Identity is the uid. A dropped connection that reconnects
      // replaces them rather than sitting beside them.
      expect(buildLiveKitClaims(pupil, config).sub).toBe("student_1");
    });

    it("makes only the teacher able to remove somebody", () => {
      // A child who can throw the teacher out of the lesson is a child
      // who will.
      const asTeacher = buildLiveKitClaims(teacher, config).video as Record<string, unknown>;
      const asPupil = buildLiveKitClaims(pupil, config).video as Record<string, unknown>;
      expect(asTeacher.roomAdmin).toBe(true);
      expect(asPupil.roomAdmin).toBe(false);
    });

    it("gives nobody an untracked side channel", () => {
      // Chat between children, if it ever exists, belongs on the
      // school's own record rather than in the media server.
      const video = buildLiveKitClaims(pupil, config).video as Record<string, unknown>;
      expect(video.canPublishData).toBe(false);
    });
  });

  describe("how long and how signed", () => {
    it("outlasts a long lesson and not much more", () => {
      const claims = buildLiveKitClaims(pupil, config);
      expect(claims.nbf as number).toBeLessThan(NOW);
      expect((claims.exp as number) - NOW).toBeLessThanOrEqual(6 * 60 * 60);
    });

    it("verifies against the API secret and nothing else", () => {
      const token = signLiveKitToken(buildLiveKitClaims(pupil, config), config);
      const [header, body, signature] = token.split(".");
      expect(signature).toBe(
        createHmac("sha256", config.apiSecret)
          .update(`${header}.${body}`)
          .digest("base64url")
      );
      expect(signature).not.toBe(
        createHmac("sha256", "wrong").update(`${header}.${body}`).digest("base64url")
      );
      expect(claimsOf(token).iss).toBe("APIabc123");
    });
  });

  describe("a school with no media server", () => {
    it("has no config, which is not an error", () => {
      // It falls back to a direct call between browsers, which works
      // and carries about six people -- and is why the screens talk
      // about a class-size ceiling at all.
      expect(liveKitConfig({} as NodeJS.ProcessEnv)).toBeNull();
    });

    it("is not half-configured into something that looks ready", () => {
      expect(
        liveKitConfig({LIVEKIT_URL: "wss://x", LIVEKIT_API_KEY: "k"} as NodeJS.ProcessEnv)
      ).toBeNull();
    });

    it("reads all three together", () => {
      expect(
        liveKitConfig({
          LIVEKIT_URL: "wss://school.livekit.cloud",
          LIVEKIT_API_KEY: "APIabc123",
          LIVEKIT_API_SECRET: "shhh",
        } as NodeJS.ProcessEnv)
      ).toEqual({
        url: "wss://school.livekit.cloud",
        apiKey: "APIabc123",
        apiSecret: "shhh",
      });
    });
  });
});
