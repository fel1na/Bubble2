class AppStrings {
  final String lang;

  const AppStrings(this.lang);

  bool get isIt => lang == 'it';

  String get appTitle => 'bubble';
  String get tagline => 'intimacy in a noisy world';

  // Onboarding
  String get welcomeTitle => isIt ? 'Benvenuto su Bubble' : 'Welcome to Bubble';
  String get welcomeSubtitle => isIt
      ? 'Stanze vocali private, offline prima di tutto.'
      : 'Private voice rooms, offline-first.';
  String get nicknamePrompt => isIt ? 'Come vuoi chiamarti?' : 'What should we call you?';
  String get nicknameHint => isIt ? 'Il tuo nome...' : 'Your name...';
  String get continueBtn => isIt ? 'Entra in Bubble' : 'Continue';

  // Home
  String get createBubble => isIt ? 'Crea Bubble' : 'Create Bubble';
  String get joinBubble => isIt ? 'Entra / QR' : 'Join / QR';
  String get enterCode => isIt ? 'Codice a 6 cifre' : '6-digit code';
  String get nearbyBubbles => isIt ? 'Bolle vicine' : 'Nearby Bubbles';
  String get noNearby => isIt
      ? 'Nessuna Bubble vicina rilevata ora'
      : 'No nearby Bubbles detected right now';
  String get yourBubbles => isIt ? 'I tuoi Bubble' : 'Your Bubbles';
  String get noSavedBubbles => isIt
      ? 'Non fai ancora parte di nessun Bubble'
      : 'You are not in any Bubble yet';
  String get groupNameHint => isIt ? 'Nome del gruppo (opzionale)' : 'Group name (optional)';

  // Room & Connection Modes
  String get statusOfflineMultipeer => isIt ? 'Offline · Multipeer P2P' : 'Offline · Multipeer P2P';
  String get statusOfflineLan => isIt ? 'Offline · Wi-Fi Locale' : 'Offline · Local Wi-Fi';
  String get statusOfflineHotspot => isIt ? 'Offline · Hotspot Locale' : 'Offline · Local Hotspot';
  String get statusOnline => isIt ? 'Online · Server Indipendente' : 'Online · Independent Server';
  String get statusConnecting => isIt ? 'Connessione offline...' : 'Connecting offline...';
  String get statusReady => isIt ? 'Tocca la bolla per parlare' : 'Tap bubble to join voice';

  String get inviteWhatsapp => isIt ? 'Invita su WhatsApp' : 'Invite via WhatsApp';
  String get showQr => isIt ? 'Mostra QR' : 'Show QR';
  String get leaveSessionTitle => isIt ? 'Uscire dalla voce?' : 'Leave voice session?';
  String get leaveSessionSub => isIt
      ? 'Resterai comunque membro del gruppo e potrai rientrare quando vuoi.'
      : 'You will stay in the group and can rejoin anytime.';
  String get stayBtn => isIt ? 'Resta' : 'Stay';
  String get leaveSessionBtn => isIt ? 'Esci dalla voce' : 'Leave voice';
  String get abandonGroupBtn => isIt ? 'Abbandona Bubble' : 'Leave Bubble group';
  String get tapToJoinVoice => isIt ? 'Tocca la bolla per attivare la voce' : 'Tap the bubble to join voice';
  String get listening => isIt ? 'In ascolto · Tocca per parlare' : 'Ready · Tap to talk';
  String get liveVoice => isIt ? 'Live' : 'Live';
  String get muted => isIt ? 'Microfono disattivato' : 'Microphone muted';

  // Settings
  String get settings => isIt ? 'Impostazioni' : 'Settings';
  String get profile => isIt ? 'Profilo' : 'Profile';
  String get language => isIt ? 'Lingua' : 'Language';
  String get serverUrlLabel => isIt ? 'Server Fallback Indipendente' : 'Independent Fallback Server';
  String get saveBtn => isIt ? 'Salva' : 'Save';
}
