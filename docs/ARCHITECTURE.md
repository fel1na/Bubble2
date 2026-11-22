# Architettura Tecnica — Bubble2

Questo documento definisce l'architettura decisa per **Bubble2**: un'app vocale intima per **2–8 persone**, **offline-first**, **zero vendor lock-in**, con interfaccia fluida in stile Apple e supporto cross-platform **iOS, iPadOS e Android**.

---

## 1. Modello di Dominio: Gruppi Persistenti + Sessioni Vocali

A differenza del prototipo precedente (dove le stanze erano effimere e legate a un singolo device), Bubble2 separa:

1. **BubbleGroup (Gruppo persistente locale/sincronizzato)**:
   - `id` (UUID v4)
   - `code` (codice rapido a 6 cifre)
   - `secret` (chiave simmetrica a 256-bit generata alla creazione, condivisa nel QR o nel link d'invito)
   - `name` (es. *"Montagna Crew"*)
   - `joinedAt`, `lastSessionAt`, `isCreator`, `notificationsMuted`
   - Resta salvato sul dispositivo finché l'utente non sceglie **"Abbandona Bubble"**.

2. **LiveSession (Sessione vocale effimera)**:
   - Qualsiasi membro di un `BubbleGroup` può avviare o rientrare nella sessione vocale live.
   - Non esiste un "proprietario fisico obbligatorio": il primo membro che apre la sessione locale diventa **Session Host temporaneo**; se l'host esce, un altro peer può riaprire o subentrare senza perdere il gruppo.

---

## 2. Motore di Connessione: Cascata Offline-First

La classe `TransportOrchestrator` seleziona e gestisce il miglior canale disponibile secondo questa priorità:

```text
  [1] Stessa LAN / Wi-Fi (mDNS _bubble._tcp + WebSocket/UDP locale)
         │  (funziona tra iOS ↔ iPadOS ↔ Android anche senza Internet)
         ▼ (nessun peer locale trovato sullo stesso Wi-Fi)
  [2] P2P Prossimità senza Router
         ├─ iOS/iPadOS ↔ iOS/iPadOS: Apple Multipeer Connectivity (BLE + Wi-Fi AWDL)
         ├─ Android Host → Android/iOS: LocalOnlyHotspot + IP reale + BLE/QR
         └─ iOS Host → Android: Personal Hotspot guidato + QR
         │  (se fuori portata fisica o connessione P2P non disponibile)
         ▼
  [3] Fallback Internet Indipendente (server/ WebSocket + WebRTC / TURN)
```

### Perché la vecchia app non funzionava (errori risolti)
- **Bug 1 (IP Hotspot hardcoded)**: `LocalHotspotPlugin.kt` restituiva sempre `192.168.43.1`, ignorando il reale IP assegnato da Android (`192.168.49.1` o subnet dinamica). In Bubble2 leggiamo le `NetworkInterface` attive reali.
- **Bug 2 (WebRTC Glare)**: host e client invocavano entrambi `createOffer()` contemporaneamente sul messaggio `join`. In Bubble2 usiamo una regola deterministica di *polite/impolite peer* (solo l'ID lessicograficamente minore invia `offer`, oppure topologia a stella sull'Host).
- **Bug 3 (WebView / Background)**: in Capacitor la WebView perdeva audio e WebSocket a schermo spento o con cuffie Bluetooth. In Flutter usiamo sessioni audio native (`AVAudioSession` categoria `.playAndRecord` con `.allowBluetooth` su iOS; `ForegroundService` `microphone|mediaPlayback` su Android).
- **Bug 4 (Codice 6 cifre orfano)**: l'ingresso con codice a 6 cifre funzionerà sia su discovery locale (mDNS/BLE matching sull'hash del `roomCode`) sia su fallback Internet tramite `server/`.

---

## 3. Topologia Audio (2–8 Persone)

- **Codec / Trasporto**:
  - **Su WebRTC (LAN / Internet)**: audio Opus 24–32 kbps con cancellazione eco (AEC), soppressione rumore (NS) e controllo guadagno (AGC) hardware.
  - **Su Apple Multipeer Connectivity (iOS ↔ iOS offline)**: stream audio compresso/Opus incapsulato su `MCSession` reliable/unreliable data packets o stream dedicati.
- **MusicMixer locale**: riproduce tracce audio locali (MP3/M4A/WAV) esclusivamente sull'uscita del dispositivo locale, miscelato con il flusso vocale in ingresso e attenuazione automatica (*ducking*) opzionale.

---

## 4. Server Indipendente (`server/`)

Un singolo servizio leggero open-source (Node.js + TypeScript + `ws` + HTTP):
- **WhatsApp Invite Links (`/join/:code`)**:
  - Restituisce una landing page leggera con meta tag OpenGraph per anteprima pulita su WhatsApp e pulsante/redirect verso il deep link `bubble://join?code=...`.
  - Il `roomSecret` può restare nel fragment URL (`#k=...`) così il server non conosce nemmeno la chiave privata del gruppo!
- **Signaling WebSocket (`/ws`)**:
  - Gestisce stanze, presenza partecipanti, scambio SDP/ICE deterministico (zero glare) e relay messaggi di stato stanza.
- **Docker + `coturn` opzionale**:
  - Deployabile con un comando (`docker compose up -d`) su qualsiasi VPS economico (es. Hetzner, Fly.io, Railway) senza alcuna dipendenza da terze parti proprietarie.
