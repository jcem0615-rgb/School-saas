// Mints a pass into a demo video class.
//
// Why this exists at all: a LiveKit pass has to be signed with the API
// secret, a secret cannot live in a browser bundle, and the app's real
// signer is a Cloud Function -- which needs Firebase's Blaze plan and a
// card. The demo has neither, and a demo that cannot show the lesson is
// a demo that cannot sell the feature.
//
// The site is already deployed on Vercel, so the smallest server that
// solves it is one file here. The secret stays in Vercel's environment
// and never reaches a browser.
//
// This is for the demo. The real product mints its passes in
// `issueMeetingToken`, which first checks the register -- the teacher
// from the session, a student from their own line on it. This checks
// nothing of the kind, because in the demo there is no register to
// check and no account that means anything. See the note on what that
// costs, below.

const {createHmac} = require('crypto');

/** The room names this app generates. Nothing else is signed for. */
const ROOM = /^lc-[a-z0-9]{20,40}$/;

/** Long enough for a demonstration, short enough not to be a key. */
const LIFETIME_SECONDS = 2 * 60 * 60;

function base64url(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function sign(claims, secret) {
  const input =
    base64url(JSON.stringify({alg: 'HS256', typ: 'JWT'})) +
    '.' +
    base64url(JSON.stringify(claims));
  return input + '.' + base64url(createHmac('sha256', secret).update(input).digest());
}

/** Trimmed and bounded: these are echoed to everyone in the room. */
function clean(value, fallback) {
  const text = typeof value === 'string' ? value.trim() : '';
  return text ? text.slice(0, 60) : fallback;
}

module.exports = async (req, res) => {
  const url = process.env.LIVEKIT_URL;
  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;

  // Not configured is not an error. The app reads this as "no video
  // here" and says so, which is what an unconfigured deployment should
  // do rather than fail in front of a class.
  if (!url || !apiKey || !apiSecret) {
    res.status(404).json({error: 'not configured'});
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({error: 'POST only'});
    return;
  }

  let body = req.body;
  if (typeof body === 'string') {
    try {
      body = JSON.parse(body);
    } catch (_) {
      body = {};
    }
  }
  body = body || {};

  // Only rooms this app generates. It does not make the endpoint
  // private -- anyone who can reach the demo can ask for a pass -- but
  // it stops it being a general-purpose token mint for somebody else's
  // conferences on this LiveKit quota.
  if (!ROOM.test(body.room || '')) {
    res.status(400).json({error: 'not a LogicClass room'});
    return;
  }

  const now = Math.floor(Date.now() / 1000);
  const token = sign(
    {
      iss: apiKey,
      sub: clean(body.identity, 'guest-' + now),
      nbf: now - 30,
      exp: now + LIFETIME_SECONDS,
      name: clean(body.name, 'Guest'),
      video: {
        room: body.room,
        roomJoin: true,
        canPublish: true,
        canSubscribe: true,
        canPublishData: false,
        // Nobody is a moderator in the demo. There is no register
        // behind it, so there is no basis for saying which of two
        // browsers is the teacher -- and a stranger who found the room
        // must not be able to remove the person demonstrating it.
        roomAdmin: false,
      },
    },
    apiSecret
  );

  // No caching: every pass is for one person and expires.
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json({url, token});
};
