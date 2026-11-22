# Bubble2

> *intimacy in a noisy world*

Bubble2 è una piattaforma di stanze vocali private **offline-first** e **completamente indipendente** (zero lock-in su Base44 o servizi proprietari).  
Progettata per permettere a gruppi intimi (2–8 persone) di parlarsi in tempo reale anche **senza copertura cellulare o Internet** (al ristorante, in montagna, in locali affollati), con fallback automatico su server indipendente self-hosted quando gli utenti sono lontani o tramite invito WhatsApp.

---

## Principi Architetturali

1. **Offline-First reale (Cascata intelligente)**:
   - **Livello 1 — Stessa rete Wi-Fi / LAN**: scoperta automatica tramite mDNS (`_bubble._tcp`) + scambio diretto sulla rete locale (Android ↔ iOS ↔ iPadOS).
   - **Livello 2 — Zero router (Montagna / Nessun segnale)**:
     - **iPhone / iPad ↔ iPhone / iPad**: *Apple Multipeer Connectivity* (BLE discovery + Peer-to-Peer Wi-Fi AWDL automatico, zero hotspot manuale e zero password).
     - **Android ↔ Android / iOS**: *Android LocalOnlyHotspot* automatico (senza SIM/dati, rilevamento dinamico dell'IP reale dell'interfaccia) + advertising BLE / QR istantaneo.
     - **Host iPhone → Guest Android**: flusso guidato Hotspot Personale + QR.
   - **Livello 3 — Fallback Internet indipendente**: se i canali offline non sono raggiungibili o un partecipante è remoto, connessione tramite il micro-server open-source in `server/`.

2. **Modello a Gruppi Persistenti (stile WhatsApp)**:
   - Ogni Bubble ha un `roomId` (codice 6 cifre) e un `roomSecret` crittografico condiviso nell'invito (QR o link WhatsApp).
   - Una volta entrati in una Bubble, resti membro del gruppo finché non lo abbandoni esplicitamente.
   - Puoi entrare e uscire dalla sessione vocale quando vuoi, e qualsiasi membro può avviare una sessione offline locale per quel gruppo.

3. **Zero registrazione obbligatoria**:
   - Solo Nickname e identità crittografica locale salvata sul dispositivo.

---

## Struttura della Repository

```text
Bubble2/
├── app/                      # App Flutter cross-platform (iOS, iPadOS, Android)
│   ├── lib/
│   │   ├── core/             # Tema Apple-fluid, l10n (IT/EN), motore di trasporto offline/online
│   │   └── features/         # Splash, Onboarding, Home, Room, Bubble visuals, MusicMixer
│   ├── ios/                  # Plugin nativi Swift (Multipeer Connectivity, AVAudioSession VoIP)
│   └── android/              # Plugin nativi Kotlin (LocalOnlyHotspot dinamico, Foreground Service)
├── server/                   # Micro-server indipendente Node.js/TypeScript + Docker + coturn
├── docs/
│   └── ARCHITECTURE.md       # Specifica tecnica dettagliata di trasporto, audio e sicurezza
└── .github/workflows/        # Build iOS (.ipa) su macOS runner per test su iPhone/iPad da Windows
```

---

## Come testare su iPhone / iPad sviluppando da Windows

Poiché Xcode richiede macOS, il repository include il workflow [ios-build.yml](file:///.github/workflows/ios-build.yml) per compilare automaticamente su GitHub Actions (`macos-latest`) un `.ipa` installabile sui tuoi iPhone e iPad (via AltStore / Sideloadly / TestFlight).

## Avvio rapido Server Indipendente

```bash
cd server
npm install
npm run dev
```

Oppure con Docker (include signaling + pagina web per inviti WhatsApp + TURN opzionale):

```bash
cd server
docker compose up --build
```
