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

/** LiveKit refuses to run with a shorter one, so a shorter one is a typo. */
const SECRET_MINIMUM = 32;

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

// What a paste into a settings box actually carries. A copied key
// arrives with the newline that ended the line it came from; a value
// typed the way it appears in a config file arrives inside its quotes.
// Neither is visible in a settings box, and either one is fatal in a
// different way: a stray newline on the key names a key LiveKit has
// never heard of, and a stray newline on the secret signs the pass with
// the wrong secret. Both come back as the same three words, "invalid
// token", with nothing to say which.
//
// So take them off. This is not tidying -- it is the difference between
// a demo that works and an afternoon of redeploying.
function unwrap(value) {
  const raw = typeof value === 'string' ? value : '';
  let text = raw.trim();
  const trimmed = text !== raw;
  let quoted = false;
  while (
    text.length >= 2 &&
    ((text.startsWith('"') && text.endsWith('"')) ||
      (text.startsWith("'") && text.endsWith("'")))
  ) {
    text = text.slice(1, -1).trim();
    quoted = true;
  }
  return {text, trimmed, quoted};
}

/** The dashboard shows an https:// address; a client dials wss://. */
function websocketUrl(url) {
  if (url.startsWith('https://')) return 'wss://' + url.slice('https://'.length);
  if (url.startsWith('http://')) return 'ws://' + url.slice('http://'.length);
  return url;
}

function schemeOf(url) {
  const end = url.indexOf('://');
  return end === -1 ? null : url.slice(0, end).toLowerCase();
}

/**
 * What is wrong with the three values, judged on their shape alone.
 *
 * A present-but-wrong value is the one failure this endpoint could not
 * see, and it is the one that happened: the pass was minted, sent, and
 * refused. Shape does not reveal a wrong secret, but it does catch the
 * mistakes that actually get made -- the pair pasted into each other's
 * boxes, the secret that is half a secret, the dashboard address in
 * place of the project's.
 *
 * Every line here is about length, prefix or punctuation. No value is
 * returned, and there is a test that says so.
 */
function problemsWith(url, apiKey, apiSecret) {
  const problems = [];

  if (apiSecret.text.startsWith('API') && !apiKey.text.startsWith('API')) {
    problems.push(
      'LIVEKIT_API_KEY and LIVEKIT_API_SECRET look swapped: the secret ' +
        'begins with "API", which is how a key begins. Put each in the ' +
        'other box.'
    );
  }

  if (apiSecret.text.length < SECRET_MINIMUM) {
    problems.push(
      'LIVEKIT_API_SECRET is ' +
        apiSecret.text.length +
        ' characters. A LiveKit secret is at least ' +
        SECRET_MINIMUM +
        ', so this one is cut short -- copy it again, whole.'
    );
  }

  for (const [name, value] of [
    ['LIVEKIT_API_KEY', apiKey],
    ['LIVEKIT_API_SECRET', apiSecret],
  ]) {
    if (/\s/.test(value.text)) {
      problems.push(
        name +
          ' has a space or a line break inside it. Two values were ' +
          'probably pasted into one box.'
      );
    }
  }

  const scheme = schemeOf(websocketUrl(url.text));
  if (scheme !== 'wss' && scheme !== 'ws') {
    problems.push(
      'LIVEKIT_URL does not begin with wss:// -- it begins with ' +
        (scheme ? scheme + '://' : 'no scheme at all') +
        '. Copy the project URL from the LiveKit dashboard.'
    );
  } else if (/^wss?:\/\/[^/]*\/./.test(websocketUrl(url.text))) {
    problems.push(
      'LIVEKIT_URL has a path after the host. That is the address of a ' +
        'page in the dashboard, not the project. The project URL ends ' +
        'at the host name.'
    );
  } else if (/cloud\.livekit\.io/.test(url.text)) {
    problems.push(
      'LIVEKIT_URL points at cloud.livekit.io, which is the dashboard ' +
        'you sign in to. The project URL is the one shown on the ' +
        "project's own page and ends in .livekit.cloud."
    );
  }

  return problems;
}

/**
 * A description of the three values with no value in it.
 *
 * Reachable with a plain GET, because a browser address bar is the one
 * tool at hand when the app says the server would not let it in.
 */
function configurationReport(url, apiKey, apiSecret) {
  const problems = problemsWith(url, apiKey, apiSecret);
  return {
    configured: true,
    // Lengths and prefixes. A LiveKit key is public -- it travels in
    // every pass, unencrypted, as the `iss` claim -- and the length of
    // a secret is the same for every project LiveKit issues.
    values: {
      LIVEKIT_URL: {
        characters: url.text.length,
        scheme: schemeOf(url.text),
        hadSurroundingSpace: url.trimmed,
        hadSurroundingQuotes: url.quoted,
      },
      LIVEKIT_API_KEY: {
        characters: apiKey.text.length,
        beginsWithAPI: apiKey.text.startsWith('API'),
        hadSurroundingSpace: apiKey.trimmed,
        hadSurroundingQuotes: apiKey.quoted,
      },
      LIVEKIT_API_SECRET: {
        characters: apiSecret.text.length,
        beginsWithAPI: apiSecret.text.startsWith('API'),
        hadSurroundingSpace: apiSecret.trimmed,
        hadSurroundingQuotes: apiSecret.quoted,
      },
    },
    problems,
    // Shape is where the checking stops. Three well-formed values that
    // came from two different projects look exactly like three that
    // came from one, and only LiveKit can tell them apart -- which it
    // does by refusing the pass.
    verdict:
      problems.length > 0 ?
        'Fix the problems above, save, and deploy again -- a saved ' +
          'variable only reaches deployments made after it was saved.' :
        'All three are the right shape. If the class still says the ' +
          'video server would not let it in, the values are well-formed ' +
          'but not a matching set: copy all three again from one ' +
          "project's Settings -> Keys page, not from two projects.",
    note: 'Shapes and lengths only. No value is ever printed here.',
  };
}

module.exports = async (req, res) => {
  const url = unwrap(process.env.LIVEKIT_URL);
  const apiKey = unwrap(process.env.LIVEKIT_API_KEY);
  const apiSecret = unwrap(process.env.LIVEKIT_API_SECRET);

  // Not configured is not an error. The app reads this as "no video
  // here" and says so, which is what an unconfigured deployment should
  // do rather than fail in front of a class.
  //
  // It names which of the three are missing, because "not configured"
  // on its own cost a round trip: all three absent means they never
  // reached this deployment -- saved after it was made, or saved on a
  // different project -- while one absent is a typo in that one name.
  // Those want different things done and looked identical.
  //
  // Names only. A value is never echoed.
  const missing = [
    ['LIVEKIT_URL', url],
    ['LIVEKIT_API_KEY', apiKey],
    ['LIVEKIT_API_SECRET', apiSecret],
  ]
    .filter(([, value]) => !value.text)
    .map(([name]) => name);

  if (missing.length > 0) {
    res.status(404).json({
      error: 'not configured',
      missing,
      hint:
        missing.length === 3 ?
          'None of the three reached this deployment. Check they were ' +
            'saved on the project this site deploys to, for the ' +
            'Production environment, and that a deployment has been made ' +
            'since saving them.' :
          'Check the spelling of the names above, and that they are set ' +
            'for the Production environment.',
    });
    return;
  }

  // A GET says what the deployment holds, without holding a class to
  // find out. Everything above already answers "is it configured"; this
  // answers "is what it holds the right shape", which is the question
  // left over once LiveKit starts refusing passes.
  if (req.method === 'GET') {
    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json(configurationReport(url, apiKey, apiSecret));
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
      iss: apiKey.text,
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
    apiSecret.text
  );

  // No caching: every pass is for one person and expires.
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json({url: websocketUrl(url.text), token});
};

// Exported for the tests. The handler is the only thing Vercel calls.
module.exports.ROOM = ROOM;
module.exports.unwrap = unwrap;
module.exports.websocketUrl = websocketUrl;
module.exports.problemsWith = problemsWith;
