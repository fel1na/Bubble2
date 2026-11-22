export interface PeerInfo {
  peerId: string;
  displayName: string;
  isMuted: boolean;
  joinedAt: number;
}

export interface RoomRecord {
  code: string;
  name: string;
  createdAt: number;
  lastActiveAt: number;
}

export const MAX_ROOM_PARTICIPANTS = 8;

/**
 * In-memory registry for Bubble groups and live voice sessions.
 * Designed to stay lightweight and self-hostable with zero external DB dependency.
 */
export class RoomRegistry {
  private readonly rooms = new Map<string, RoomRecord>();
  private readonly livePeers = new Map<string, Map<string, PeerInfo>>();

  upsertRoom(code: string, name: string): RoomRecord {
    const normalized = code.trim();
    const now = Date.now();
    const existing = this.rooms.get(normalized);
    if (existing) {
      existing.name = name || existing.name;
      existing.lastActiveAt = now;
      return existing;
    }
    const created: RoomRecord = {
      code: normalized,
      name: name || `Bubble #${normalized}`,
      createdAt: now,
      lastActiveAt: now,
    };
    this.rooms.set(normalized, created);
    return created;
  }

  getRoom(code: string): RoomRecord | undefined {
    return this.rooms.get(code.trim());
  }

  joinSession(code: string, peer: Omit<PeerInfo, 'joinedAt'>): { ok: true; peers: PeerInfo[] } | { ok: false; reason: string } {
    const normalized = code.trim();
    if (!this.rooms.has(normalized)) {
      this.upsertRoom(normalized, `Bubble #${normalized}`);
    } else {
      const room = this.rooms.get(normalized)!;
      room.lastActiveAt = Date.now();
    }

    let session = this.livePeers.get(normalized);
    if (!session) {
      session = new Map();
      this.livePeers.set(normalized, session);
    }

    if (!session.has(peer.peerId) && session.size >= MAX_ROOM_PARTICIPANTS) {
      return { ok: false, reason: 'room_full' };
    }

    session.set(peer.peerId, {
      ...peer,
      joinedAt: Date.now(),
    });

    const others = Array.from(session.values()).filter((p) => p.peerId !== peer.peerId);
    return { ok: true, peers: others };
  }

  updateMute(code: string, peerId: string, isMuted: boolean): void {
    const session = this.livePeers.get(code.trim());
    const peer = session?.get(peerId);
    if (peer) {
      peer.isMuted = isMuted;
    }
  }

  leaveSession(code: string, peerId: string): boolean {
    const normalized = code.trim();
    const session = this.livePeers.get(normalized);
    if (!session) return false;
    const removed = session.delete(peerId);
    if (session.size === 0) {
      this.livePeers.delete(normalized);
    }
    return removed;
  }

  getLivePeers(code: string): PeerInfo[] {
    const session = this.livePeers.get(code.trim());
    return session ? Array.from(session.values()) : [];
  }

  stats(): { registeredRooms: number; activeSessions: number; activePeers: number } {
    let activePeers = 0;
    for (const session of this.livePeers.values()) {
      activePeers += session.size;
    }
    return {
      registeredRooms: this.rooms.size,
      activeSessions: this.livePeers.size,
      activePeers,
    };
  }
}
