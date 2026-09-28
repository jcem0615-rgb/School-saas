// The demo's token endpoint, checked without a LiveKit account.
//
// Run: node --test vercel/test
//
// This file is deliberately outside vercel/api. The deploy workflow
// copies vercel/api/*.js into the site, and anything it copies there
// Vercel treats as a live endpoint.
//
// It earns its place: this one file has been wrong in three different
// ways in front of a class -- unset variables, a room name the wrong
// shape, and a pass LiveKit would not accept -- and each one cost a
// deploy to find out.

const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createHmac} = require('node:crypto');

const ENDPOINT = require.resolve('../api/livekit-token.js');

const URL = 'wss://logicclass-demo.livekit.cloud';
const KEY = 'APIdemokey12345';
const SECRET = 'a'.repeat(43);
const ROOM = 'lc-abcdefghij0123456789abcd';

/** Loads the handler with exactly the environment given, and no other. */
function endpointWith(env) {
  const saved = {};
  for (const name of ['LIVEKIT_URL', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET']) {
    saved[name] = process.env[name];
    // Assigning undefined would set the four letters "undefined", which
    // is a value, and a variable with a value is not a missing one.
    if (env[name] === undefined) delete process.env[name];
    else process.env[name] = env[name];
  }
  delete require.cache[ENDPOINT];
  const handler = require(ENDPOINT);
  return {
    handler,
    restore() {
      for (const [name, value] of Object.entries(saved)) {
        if (value === undefined) delete process.env[name];
        else process.env[name] = value;
      }
    },
  };
}

/**
 * Stands in for LiveKit while the endpoint asks it about its own keys.
 *
 * Every GET that finds nothing wrong with the shapes now asks the real
 * server, so a test that did not stub this would go out to the network
 * -- slowly, and differently depending on where it ran.
 */
function livekitAnswers(answer) {
  const asked = [];
  const real = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    asked.push({url: String(url), options});
    if (answer instanceof Error) throw answer;
    return {
      status: answer.status,
      text: async () => answer.body ?? '',
    };
  };
  return {
    asked,
    restore() {
      globalThis.fetch = real;
    },
  };
}

/** Calls the endpoint and returns the status and the body it answered. */
async function call({env = {}, method = 'POST', body} = {}) {
  const loaded = endpointWith({
    LIVEKIT_URL: URL,
    LIVEKIT_API_KEY: KEY,
    LIVEKIT_API_SECRET: SECRET,
    ...env,
  });
  const answer = {status: 0, body: undefined, headers: {}};
  const res = {
    setHeader(name, value) {
      answer.headers[name.toLowerCase()] = value;
    },
    status(code) {
      answer.status = code;
      return this;
    },
    json(value) {
      answer.body = value;
    },
  };
  try {
    await loaded.handler({method, body}, res);
  } finally {
    loaded.restore();
  }
  return answer;
}

function decode(part) {
  return JSON.parse(Buffer.from(part, 'base64url').toString());
}

/** Verifies the pass the way a server does, from the secret up. */
function verify(token, secret) {
  const [header, payload, signature] = token.split('.');
  const expected = createHmac('sha256', secret)
    .update(header + '.' + payload)
    .digest('base64url');
  return {
    header: decode(header),
    claims: decode(payload),
    signed: signature === expected,
  };
}

test('mints a pass a LiveKit server can verify', async () => {
  const answer = await call({body: {room: ROOM, identity: 'u1', name: 'Miss Cruz'}});

  assert.equal(answer.status, 200);
  assert.equal(answer.body.url, URL);
  assert.equal(answer.headers['cache-control'], 'no-store');

  const {header, claims, signed} = verify(answer.body.token, SECRET);
  assert.deepEqual(header, {alg: 'HS256', typ: 'JWT'});
  assert.ok(signed, 'the signature must verify against the secret it was signed with');
  assert.equal(claims.iss, KEY);
  assert.equal(claims.sub, 'u1');
  assert.equal(claims.name, 'Miss Cruz');
  assert.equal(claims.video.room, ROOM);
  assert.equal(claims.video.roomJoin, true);
  assert.equal(claims.video.canPublish, true);
  assert.equal(claims.video.canSubscribe, true);
  assert.equal(claims.video.roomAdmin, false, 'nobody moderates the demo');
  assert.ok(claims.nbf <= Math.floor(Date.now() / 1000), 'the pass is valid now');
  assert.ok(claims.exp > claims.nbf, 'and for a while yet');
});

// The failure that cost the most: a key pasted out of the dashboard
// brings the newline that ended its line, and nothing shows it. LiveKit
// then cannot find a key by that name, and says "invalid token" --
// which reads as a signing bug and is not one.
test('a pasted newline does not change the pass', async () => {
  const pasted = await call({
    env: {LIVEKIT_API_KEY: KEY + '\n', LIVEKIT_API_SECRET: '  ' + SECRET + '\n'},
    body: {room: ROOM, identity: 'u1'},
  });
  const clean = await call({body: {room: ROOM, identity: 'u1'}});

  assert.equal(pasted.status, 200);
  assert.equal(verify(pasted.body.token, SECRET).claims.iss, KEY);
  assert.ok(verify(pasted.body.token, SECRET).signed);
  assert.equal(
    verify(pasted.body.token, SECRET).claims.video.room,
    verify(clean.body.token, SECRET).claims.video.room
  );
});

test('a value saved inside quotes is read without them', async () => {
  const answer = await call({
    env: {LIVEKIT_API_KEY: `"${KEY}"`, LIVEKIT_URL: `'${URL}'`},
    body: {room: ROOM},
  });

  assert.equal(answer.status, 200);
  assert.equal(answer.body.url, URL);
  assert.equal(verify(answer.body.token, SECRET).claims.iss, KEY);
});

test('an https:// project address is dialled as wss://', async () => {
  const answer = await call({
    env: {LIVEKIT_URL: 'https://logicclass-demo.livekit.cloud'},
    body: {room: ROOM},
  });

  assert.equal(answer.status, 200);
  assert.equal(answer.body.url, 'wss://logicclass-demo.livekit.cloud');
});

test('names the variables that never arrived', async () => {
  const none = await call({
    env: {LIVEKIT_URL: undefined, LIVEKIT_API_KEY: undefined, LIVEKIT_API_SECRET: undefined},
  });

  assert.equal(none.status, 404);
  assert.deepEqual(none.body.missing, [
    'LIVEKIT_URL',
    'LIVEKIT_API_KEY',
    'LIVEKIT_API_SECRET',
  ]);
  assert.match(none.body.hint, /deployment has been made/);

  const one = await call({env: {LIVEKIT_API_SECRET: undefined}});
  assert.equal(one.status, 404);
  assert.deepEqual(one.body.missing, ['LIVEKIT_API_SECRET']);
});

test('a value that is only whitespace counts as missing', async () => {
  const answer = await call({env: {LIVEKIT_API_SECRET: '   \n'}});

  assert.equal(answer.status, 404);
  assert.deepEqual(answer.body.missing, ['LIVEKIT_API_SECRET']);
});

test('signs only for rooms this app generates', async () => {
  for (const room of [
    undefined,
    '',
    'lc-short',
    'lc-room_0001k3j9x2p1',
    'lc-ABCDEFGHIJ0123456789abcd',
    'someone-elses-conference',
    'lc-' + 'a'.repeat(41),
  ]) {
    const answer = await call({body: {room}});
    assert.equal(answer.status, 400, `should refuse ${JSON.stringify(room)}`);
    assert.equal(answer.body.error, 'not a LogicClass room');
  }
});

test('reads a body that arrived as text', async () => {
  const answer = await call({body: JSON.stringify({room: ROOM, name: 'Ana'})});

  assert.equal(answer.status, 200);
  assert.equal(verify(answer.body.token, SECRET).claims.name, 'Ana');
});

test('bounds the names it will put in front of a class', async () => {
  const answer = await call({body: {room: ROOM, name: 'x'.repeat(500)}});

  assert.equal(answer.status, 200);
  assert.equal(verify(answer.body.token, SECRET).claims.name.length, 60);
});

test('a method that is neither GET nor POST is refused', async () => {
  const answer = await call({method: 'DELETE', body: {room: ROOM}});

  assert.equal(answer.status, 405);
  assert.equal(answer.body.error, 'POST only');
});

test('a GET describes the configuration and hands back no pass', async () => {
  const livekit = livekitAnswers({status: 200, body: '{"rooms":[]}'});
  const answer = await call({method: 'GET'}).finally(livekit.restore);

  assert.equal(answer.status, 200);
  assert.equal(answer.body.configured, true);
  assert.equal(answer.body.token, undefined);
  assert.deepEqual(answer.body.problems, []);
  assert.match(answer.body.verdict, /matching set/);
  assert.equal(answer.body.values.LIVEKIT_API_KEY.characters, KEY.length);
  assert.equal(answer.body.values.LIVEKIT_API_KEY.beginsWithAPI, true);
  assert.equal(answer.body.values.LIVEKIT_API_SECRET.beginsWithAPI, false);
  assert.equal(answer.body.values.LIVEKIT_URL.scheme, 'wss');
});

// The point of the report is that it can be opened from a phone in the
// middle of a demo. That is only safe while it contains no value.
test('the report never prints a value', async () => {
  // LiveKit is made to say the worst thing it could: the credentials
  // back, in its own refusal. Nothing that came back from it reaches
  // the report unredacted.
  const livekit = livekitAnswers({
    status: 401,
    body: `{"msg":"invalid token for ${KEY} / ${SECRET}"}`,
  });
  const answer = await call({
    method: 'GET',
    env: {LIVEKIT_API_KEY: KEY + '\n', LIVEKIT_API_SECRET: SECRET},
  }).finally(livekit.restore);
  const printed = JSON.stringify(answer.body);

  for (const secret of [SECRET, KEY, URL, 'logicclass-demo', 'livekit.cloud']) {
    assert.ok(!printed.includes(secret), `the report leaked ${secret}`);
  }
  assert.equal(answer.body.values.LIVEKIT_API_KEY.hadSurroundingSpace, true);
});

test('the report names the mistakes shape can see', async () => {
  const swapped = await call({
    method: 'GET',
    env: {LIVEKIT_API_KEY: SECRET, LIVEKIT_API_SECRET: KEY},
  });
  assert.ok(
    swapped.body.problems.some((p) => /look swapped/.test(p)),
    JSON.stringify(swapped.body.problems)
  );

  const halfSecret = await call({method: 'GET', env: {LIVEKIT_API_SECRET: 'abcdef'}});
  assert.ok(halfSecret.body.problems.some((p) => /at least 32/.test(p)));

  const pair = await call({
    method: 'GET',
    env: {LIVEKIT_API_SECRET: SECRET + ' ' + SECRET},
  });
  assert.ok(pair.body.problems.some((p) => /pasted into one box/.test(p)));

  const notAWebsocket = await call({
    method: 'GET',
    env: {LIVEKIT_URL: 'logicclass-demo.livekit.cloud'},
  });
  assert.ok(notAWebsocket.body.problems.some((p) => /does not begin with wss/.test(p)));

  const dashboardPage = await call({
    method: 'GET',
    env: {LIVEKIT_URL: 'https://cloud.livekit.io/projects/p_123/settings/keys'},
  });
  assert.ok(dashboardPage.body.problems.some((p) => /path after the host/.test(p)));

  const dashboardHost = await call({
    method: 'GET',
    env: {LIVEKIT_URL: 'wss://cloud.livekit.io'},
  });
  assert.ok(dashboardHost.body.problems.some((p) => /dashboard you sign in to/.test(p)));

  const livekit = livekitAnswers({status: 200, body: '{"rooms":[]}'});
  const fine = await call({method: 'GET'}).finally(livekit.restore);
  assert.deepEqual(fine.body.problems, []);

  // Shape already had the answer; LiveKit's opinion would only add six
  // seconds in front of somebody who is waiting.
  assert.equal(swapped.body.livekit, null);
});

test('asks LiveKit itself, with the same key and the same secret', async () => {
  const livekit = livekitAnswers({status: 200, body: '{"rooms":[]}'});
  const answer = await call({method: 'GET'}).finally(livekit.restore);

  assert.equal(livekit.asked.length, 1);
  const [request] = livekit.asked;
  assert.equal(
    request.url,
    'https://logicclass-demo.livekit.cloud/twirp/livekit.RoomService/ListRooms'
  );
  assert.equal(request.options.method, 'POST');

  const sent = request.options.headers.Authorization.replace('Bearer ', '');
  const {claims, signed} = verify(sent, SECRET);
  assert.ok(signed, 'asked with a token signed by the configured secret');
  assert.equal(claims.iss, KEY);
  assert.deepEqual(claims.video, {roomList: true});
  assert.ok(claims.exp - claims.nbf <= 120, 'and one that expires at once');

  assert.equal(answer.body.livekit.status, 200);
  assert.match(answer.body.summary, /matching set and the fault is not in them/);
});

// The whole point: this is the one thing shape could never see.
test("repeats LiveKit's refusal, and what it means", async () => {
  const livekit = livekitAnswers({
    status: 401,
    body: '{"code":"unauthenticated","msg":"invalid token"}',
  });
  const answer = await call({method: 'GET'}).finally(livekit.restore);

  assert.equal(answer.body.livekit.status, 401);
  assert.match(answer.body.summary, /refuses this key and secret/);
  assert.match(answer.body.summary, /invalid token/);
  assert.match(answer.body.summary, /reveal the secret in full/);
});

test('says so when the address does not answer at all', async () => {
  const livekit = livekitAnswers(new Error('getaddrinfo ENOTFOUND'));
  const answer = await call({method: 'GET'}).finally(livekit.restore);

  assert.equal(answer.body.livekit.reached, false);
  assert.match(answer.body.summary, /did not answer/);
  assert.match(answer.body.summary, /ENOTFOUND/);
});

test('an address that answers but is not LiveKit is named as such', async () => {
  const livekit = livekitAnswers({status: 404, body: 'Not Found'});
  const answer = await call({method: 'GET'}).finally(livekit.restore);

  assert.match(answer.body.summary, /not a LiveKit project/);
});

test('a shape problem is the summary, and LiveKit is not asked', async () => {
  const livekit = livekitAnswers({status: 200, body: '{"rooms":[]}'});
  const answer = await call({
    method: 'GET',
    env: {LIVEKIT_API_SECRET: 'abcdef'},
  }).finally(livekit.restore);

  assert.equal(livekit.asked.length, 0);
  assert.match(answer.body.summary, /at least 32/);
});

test('minting a pass never asks LiveKit anything', async () => {
  const livekit = livekitAnswers({status: 200, body: '{"rooms":[]}'});
  const answer = await call({body: {room: ROOM}}).finally(livekit.restore);

  // A lesson starting must not wait on a diagnostic.
  assert.equal(answer.status, 200);
  assert.equal(livekit.asked.length, 0);
});

// The one that actually happened, and the one every other check on
// this page waved through: a secret of exactly the right sort of
// length, no whitespace, no prefix, and not a secret at all.
test('catches the row of dots the dashboard prints in place of a value',
    async () => {
  const livekit = livekitAnswers({status: 200, body: '{"rooms":[]}'});
  const answer = await call({
    method: 'GET',
    env: {LIVEKIT_API_SECRET: '\u2022'.repeat(32)},
  }).finally(livekit.restore);

  assert.match(answer.body.summary, /row of dots/);
  assert.match(answer.body.summary, /LIVEKIT_API_SECRET/);
  assert.match(answer.body.summary, /Reveal it on the Keys page/);
  // It is not a space, and it is long enough, so nothing else was
  // ever going to catch it.
  assert.equal(answer.body.values.LIVEKIT_API_SECRET.characters, 32);
  assert.equal(livekit.asked.length, 0, 'and LiveKit is not troubled with it');
});

test('and the same in the other two boxes', async () => {
  for (const [name, masked] of [
    ['LIVEKIT_API_KEY', '\u25cf'.repeat(15)],
    ['LIVEKIT_URL', 'wss://\u2022\u2022\u2022\u2022.livekit.cloud'],
  ]) {
    const livekit = livekitAnswers({status: 200, body: '{}'});
    const answer = await call({
      method: 'GET',
      env: {[name]: masked},
    }).finally(livekit.restore);

    assert.match(answer.body.summary, new RegExp(name + ' is the row of dots'));
  }
});

test('and does not see dots in a real key, secret or address', async () => {
  const livekit = livekitAnswers({status: 200, body: '{"rooms":[]}'});
  const answer = await call({
    method: 'GET',
    env: {
      LIVEKIT_API_KEY: 'APIx-_9aBcDeFgH',
      LIVEKIT_API_SECRET: 'aB3-_' + 'x'.repeat(38),
      LIVEKIT_URL: 'wss://a-project-1234.livekit.cloud',
    },
  }).finally(livekit.restore);

  assert.deepEqual(answer.body.problems, []);
});

// The lengths in the dialog that creates a key: 15 and 43. Anything
// else on a .livekit.cloud address is part of a value, and the two ways
// that happens -- the masked display, a selection that stopped early --
// both arrive looking perfectly reasonable.
test('holds a LiveKit Cloud pair to the lengths LiveKit Cloud issues',
    async () => {
  const livekit = livekitAnswers({status: 200, body: '{}'});
  const answer = await call({
    method: 'GET',
    env: {LIVEKIT_API_SECRET: 'x'.repeat(32)},
  }).finally(livekit.restore);

  assert.match(answer.body.summary, /issues one of 43/);
  assert.match(answer.body.summary, /copy the secret from that dialog/);
  assert.equal(livekit.asked.length, 0);
});

test('and says the same of a key that is not 15 characters', async () => {
  const livekit = livekitAnswers({status: 200, body: '{}'});
  const answer = await call({
    method: 'GET',
    env: {LIVEKIT_API_KEY: 'APIshort'},
  }).finally(livekit.restore);

  assert.match(answer.body.summary, /LIVEKIT_API_KEY is 8 characters/);
});

test('but holds a self-hosted server to nothing of the kind', async () => {
  // Those lengths are LiveKit Cloud's. A school running its own server
  // generates its own keys, and they are whatever it made them.
  const livekit = livekitAnswers({status: 200, body: '{}'});
  const answer = await call({
    method: 'GET',
    env: {
      LIVEKIT_URL: 'wss://video.school.edu.ph',
      LIVEKIT_API_KEY: 'schoolkey',
      LIVEKIT_API_SECRET: 's'.repeat(36),
    },
  }).finally(livekit.restore);

  assert.deepEqual(answer.body.problems, []);
});

test('a GET on an unconfigured deployment still says so', async () => {
  const answer = await call({method: 'GET', env: {LIVEKIT_API_KEY: undefined}});

  assert.equal(answer.status, 404);
  assert.deepEqual(answer.body.missing, ['LIVEKIT_API_KEY']);
});
