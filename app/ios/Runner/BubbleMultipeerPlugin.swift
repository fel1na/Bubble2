import Flutter
import MultipeerConnectivity

/// Offline peer-to-peer transport for iPhone & iPad using Apple MultipeerConnectivity
/// (BLE discovery + automatic Peer-to-Peer Wi-Fi AWDL, zero router or password required).
final class BubbleMultipeerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let serviceType = "bubble-p2p"

  private var methodChannel: FlutterMethodChannel?
  private var eventSink: FlutterEventSink?

  private var peerID: MCPeerID?
  private var session: MCSession?
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?
  private var activeRoomCode: String?
  private var isScanningNearbyOnly = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BubbleMultipeerPlugin()
    let methodChannel = FlutterMethodChannel(
      name: "com.bubble/multipeer",
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: "com.bubble/multipeer_events",
      binaryMessenger: registrar.messenger()
    )
    instance.methodChannel = methodChannel
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "startNearbyScan":
      let displayName = (args["displayName"] as? String) ?? UIDevice.current.name
      startNearbyDiscovery(displayName: displayName)
      result(true)

    case "stopNearbyScan":
      stopBrowser()
      result(true)

    case "startRoomSession":
      guard let roomCode = args["roomCode"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing roomCode", details: nil))
        return
      }
      let displayName = (args["displayName"] as? String) ?? UIDevice.current.name
      let roomName = (args["roomName"] as? String) ?? "Bubble #\(roomCode)"
      startSession(roomCode: roomCode, roomName: roomName, displayName: displayName)
      result(true)

    case "sendMessage":
      guard let text = args["message"] as? String,
            let data = text.data(using: .utf8),
            let session = self.session else {
        result(false)
        return
      }
      let reliable = (args["reliable"] as? Bool) ?? true
      let peers = session.connectedPeers
      if peers.isEmpty {
        result(true)
        return
      }
      do {
        try session.send(data, toPeers: peers, with: reliable ? .reliable : .unreliable)
        result(true)
      } catch {
        result(FlutterError(code: "SEND_FAILED", message: error.localizedDescription, details: nil))
      }

    case "stopSession":
      stopAll()
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func ensurePeerID(displayName: String) -> MCPeerID {
    let trimmed = String(displayName.prefix(48))
    let id = MCPeerID(displayName: trimmed.isEmpty ? "BubbleUser" : trimmed)
    self.peerID = id
    return id
  }

  private func startNearbyDiscovery(displayName: String) {
    stopBrowser()
    isScanningNearbyOnly = true
    let localID = self.peerID ?? ensurePeerID(displayName: displayName)
    let browser = MCNearbyServiceBrowser(peer: localID, serviceType: Self.serviceType)
    browser.delegate = self
    browser.startBrowsingForPeers()
    self.browser = browser
  }

  private func startSession(roomCode: String, roomName: String, displayName: String) {
    stopAll()
    isScanningNearbyOnly = false
    activeRoomCode = roomCode

    let localID = ensurePeerID(displayName: displayName)
    let session = MCSession(peer: localID, securityIdentity: nil, encryptionPreference: .required)
    session.delegate = self
    self.session = session

    let advertiser = MCNearbyServiceAdvertiser(
      peer: localID,
      discoveryInfo: ["room": roomCode, "name": String(roomName.prefix(40))],
      serviceType: Self.serviceType
    )
    advertiser.delegate = self
    advertiser.startAdvertisingPeer()
    self.advertiser = advertiser

    let browser = MCNearbyServiceBrowser(peer: localID, serviceType: Self.serviceType)
    browser.delegate = self
    browser.startBrowsingForPeers()
    self.browser = browser
  }

  private func stopBrowser() {
    browser?.stopBrowsingForPeers()
    browser?.delegate = nil
    browser = nil
  }

  private func stopAll() {
    advertiser?.stopAdvertisingPeer()
    advertiser?.delegate = nil
    advertiser = nil
    stopBrowser()
    session?.disconnect()
    session?.delegate = nil
    session = nil
    activeRoomCode = nil
    isScanningNearbyOnly = false
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }
}

extension BubbleMultipeerPlugin: MCNearbyServiceAdvertiserDelegate {
  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    let invitedRoom = context.flatMap { String(data: $0, encoding: .utf8) }
    let matches = (activeRoomCode != nil && invitedRoom == activeRoomCode)
    invitationHandler(matches, matches ? session : nil)
  }

  func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
    emit(["type": "error", "message": error.localizedDescription])
  }
}

extension BubbleMultipeerPlugin: MCNearbyServiceBrowserDelegate {
  func browser(
    _ browser: MCNearbyServiceBrowser,
    foundPeer peerID: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    let roomCode = info?["room"] ?? ""
    let roomName = info?["name"] ?? "Bubble #\(roomCode)"
    guard !roomCode.isEmpty else { return }

    emit([
      "type": "nearby_found",
      "roomCode": roomCode,
      "roomName": roomName,
      "hostName": peerID.displayName,
    ])

    if !isScanningNearbyOnly,
       let activeRoom = activeRoomCode,
       activeRoom == roomCode,
       let session = self.session,
       let localID = self.peerID {
      // Deterministic invite initiation to avoid simultaneous dual-invite loops
      if localID.displayName <= peerID.displayName {
        let context = activeRoom.data(using: .utf8)
        browser.invitePeer(peerID, to: session, withContext: context, timeout: 15)
      }
    }
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    emit(["type": "nearby_lost", "hostName": peerID.displayName])
  }

  func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    emit(["type": "error", "message": error.localizedDescription])
  }
}

extension BubbleMultipeerPlugin: MCSessionDelegate {
  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    let stateStr: String
    switch state {
    case .notConnected: stateStr = "disconnected"
    case .connecting: stateStr = "connecting"
    case .connected: stateStr = "connected"
    @unknown default: stateStr = "unknown"
    }
    emit([
      "type": "peer_state",
      "peerName": peerID.displayName,
      "state": stateStr,
    ])
  }

  func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    guard let text = String(data: data, encoding: .utf8) else { return }
    emit([
      "type": "message",
      "peerName": peerID.displayName,
      "message": text,
    ])
  }

  func session(
    _ session: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {}

  func session(
    _ session: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {}

  func session(
    _ session: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: Error?
  ) {}
}
