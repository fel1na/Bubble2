import type { WebSocket, WebSocketServer } from 'ws';
import type { RoomRegistry } from './roomRegistry.js';

interface ClientMeta {
  roomCode?: string;
  peerId?: string;
  isAlive: boolean;
}

export interface SignalMessage {
  type: 'join' | 'offer' | 'answer' | 'ice' | 'mute_state' | 'leave' | 'ping';
  roomCode?: string;
  from?: string;
  to?: string;
  displayName?: string;
  isMuted?: boolean;
  payload?: unknown;
}

function safeSend(ws: WebSocket, data: unknown): void {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(data));
  }
}

/**
 * Deterministic WebRTC signaling router with direct peer targeting (no blind broadcast)
 * to avoid offer glare between connecting mobile clients.
 */
export function attachSignaling(wss: WebSocketServer, registry: RoomRegistry): () => void {
  const clientMeta = new WeakMap<WebSocket, ClientMeta>();
  const roomSockets = new Map<string, Map<string, WebSocket>>();

  const removeClient = (ws: WebSocket): void => {
    const meta = clientMeta.get(ws);
    if (!meta?.roomCode || !meta.peerId) return;

    const { roomCode, peerId } = meta;
    registry.leaveSession(roomCode, peerId);

    const peers = roomSockets.get(roomCode);
    if (peers) {
      peers.delete(peerId);
      for (const peerWs of peers.values()) {
        safeSend(peerWs, { type: 'peer_left', roomCode, peerId });
      }
      if (peers.size === 0) {
        roomSockets.delete(roomCode);
      }
    }
    meta.roomCode = undefined;
    meta.peerId = undefined;
  };

  wss.on('connection', (ws) => {
    clientMeta.set(ws, { isAlive: true });

    ws.on('pong', () => {
      const meta = clientMeta.get(ws);
      if (meta) meta.isAlive = true;
    });

    ws.on('message', (raw) => {
      let msg: SignalMessage;
      try {
        msg = JSON.parse(raw.toString()) as SignalMessage;
      } catch {
        safeSend(ws, { type: 'error', reason: 'invalid_json' });
        return;
      }

      if (msg.type === 'ping') {
        safeSend(ws, { type: 'pong' });
        return;
      }

      const meta = clientMeta.get(ws);
      if (!meta) return;

      if (msg.type === 'join') {
        const roomCode = msg.roomCode?.trim();
        const peerId = msg.from?.trim();
        const displayName = msg.displayName?.trim() || 'Guest';

        if (!roomCode || !peerId) {
          safeSend(ws, { type: 'error', reason: 'missing_join_fields' });
          return;
        }

        // Clean up any prior session bound to this socket
        if (meta.roomCode && meta.peerId) {
          removeClient(ws);
        }

        const result = registry.joinSession(roomCode, {
          peerId,
          displayName,
          isMuted: Boolean(msg.isMuted),
        });

        if (!result.ok) {
          safeSend(ws, { type: 'error', reason: result.reason });
          return;
        }

        meta.roomCode = roomCode;
        meta.peerId = peerId;

        let sockets = roomSockets.get(roomCode);
        if (!sockets) {
          sockets = new Map();
          roomSockets.set(roomCode, sockets);
        }

        // Notify existing peers about the newcomer
        for (const [existingId, peerWs] of sockets.entries()) {
          if (existingId !== peerId) {
            safeSend(peerWs, {
              type: 'peer_joined',
              roomCode,
              peer: {
                peerId,
                displayName,
                isMuted: Boolean(msg.isMuted),
              },
            });
          }
        }

        sockets.set(peerId, ws);

        // Return current peers so the client applies deterministic offer initiation
        safeSend(ws, {
          type: 'joined',
          roomCode,
          peerId,
          peers: result.peers,
        });
        return;
      }

      if (!meta.roomCode || !meta.peerId) {
        safeSend(ws, { type: 'error', reason: 'not_joined' });
        return;
      }

      const roomCode = meta.roomCode;
      const peerId = meta.peerId;
      const sockets = roomSockets.get(roomCode);
      if (!sockets) return;

      if (msg.type === 'leave') {
        removeClient(ws);
        return;
      }

      if (msg.type === 'mute_state') {
        const isMuted = Boolean(msg.isMuted);
        registry.updateMute(roomCode, peerId, isMuted);
        for (const [otherId, peerWs] of sockets.entries()) {
          if (otherId !== peerId) {
            safeSend(peerWs, { type: 'mute_state', roomCode, peerId, isMuted });
          }
        }
        return;
      }

      if (msg.type === 'offer' || msg.type === 'answer' || msg.type === 'ice') {
        if (!msg.to) {
          safeSend(ws, { type: 'error', reason: 'missing_target_peer' });
          return;
        }
        const targetWs = sockets.get(msg.to);
        if (targetWs) {
          safeSend(targetWs, {
            type: msg.type,
            roomCode,
            from: peerId,
            to: msg.to,
            payload: msg.payload,
          });
        }
      }
    });

    ws.on('close', () => removeClient(ws));
    ws.on('error', () => removeClient(ws));
  });

  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      const meta = clientMeta.get(ws);
      if (!meta) continue;
      if (!meta.isAlive) {
        removeClient(ws);
        ws.terminate();
        continue;
      }
      meta.isAlive = false;
      ws.ping();
    }
  }, 30_000);
  heartbeat.unref();

  return () => clearInterval(heartbeat);
}
