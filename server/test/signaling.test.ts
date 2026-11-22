import test from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { createBubbleServer } from '../src/index.js';

function openWs(url: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
}

function nextMsg(ws: WebSocket): Promise<Record<string, unknown>> {
  return new Promise((resolve) => {
    ws.once('message', (data) => resolve(JSON.parse(data.toString())));
  });
}

test('signaling routes directed offer/answer between two peers without glare', async () => {
  const { server } = createBubbleServer();
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  assert.ok(address && typeof address === 'object');

  const wsUrl = `ws://127.0.0.1:${address.port}/ws`;
  const alice = await openWs(wsUrl);
  const bob = await openWs(wsUrl);

  try {
    const aliceJoinedPromise = nextMsg(alice);
    alice.send(JSON.stringify({ type: 'join', roomCode: '123456', from: 'alice', displayName: 'Alice' }));
    const aliceJoined = await aliceJoinedPromise;
    assert.equal(aliceJoined.type, 'joined');
    assert.deepEqual(aliceJoined.peers, []);

    const aliceNotifiedPromise = nextMsg(alice);
    const bobJoinedPromise = nextMsg(bob);
    bob.send(JSON.stringify({ type: 'join', roomCode: '123456', from: 'bob', displayName: 'Bob' }));

    const aliceNotified = await aliceNotifiedPromise;
    const bobJoined = await bobJoinedPromise;

    assert.equal(aliceNotified.type, 'peer_joined');
    assert.equal(bobJoined.type, 'joined');
    assert.equal((bobJoined.peers as Array<{ peerId: string }>)[0]?.peerId, 'alice');

    const bobOfferPromise = nextMsg(bob);
    alice.send(JSON.stringify({ type: 'offer', from: 'alice', to: 'bob', payload: { sdp: 'fake-offer' } }));
    const bobOffer = await bobOfferPromise;
    assert.equal(bobOffer.type, 'offer');
    assert.equal(bobOffer.from, 'alice');
    assert.deepEqual(bobOffer.payload, { sdp: 'fake-offer' });

    const aliceAnswerPromise = nextMsg(alice);
    bob.send(JSON.stringify({ type: 'answer', from: 'bob', to: 'alice', payload: { sdp: 'fake-answer' } }));
    const aliceAnswer = await aliceAnswerPromise;
    assert.equal(aliceAnswer.type, 'answer');
    assert.equal(aliceAnswer.from, 'bob');
  } finally {
    alice.close();
    bob.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

test('WhatsApp invite page returns OpenGraph HTML for valid 6-digit room code', async () => {
  const { server } = createBubbleServer();
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  assert.ok(address && typeof address === 'object');

  try {
    const base = `http://127.0.0.1:${address.port}`;
    const createRes = await fetch(`${base}/api/rooms`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code: '654321', name: 'Montagna Crew' }),
    });
    assert.equal(createRes.status, 200);

    const htmlRes = await fetch(`${base}/join/654321`);
    assert.equal(htmlRes.status, 200);
    const html = await htmlRes.text();
    assert.match(html, /Montagna Crew/);
    assert.match(html, /bubble:\/\/join\?code=654321/);
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
