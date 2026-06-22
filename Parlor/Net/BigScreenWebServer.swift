import Foundation
import Network

// MARK: - HTTP helpers

private struct WebResponse {
    var status: Int
    var contentType: String
    var body: Data

    static func json(_ dict: [String: Any], status: Int = 200) -> WebResponse {
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return WebResponse(status: status, contentType: "application/json", body: data)
    }
    static func html(_ html: String) -> WebResponse {
        WebResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(html.utf8))
    }
    static func error(_ msg: String, status: Int = 400) -> WebResponse {
        json(["error": msg], status: status)
    }
    static func notFound() -> WebResponse { json(["error": "Not found"], status: 404) }
    static func ok() -> WebResponse {
        WebResponse(status: 200, contentType: "application/json", body: Data("{}".utf8))
    }

    func wire() -> Data {
        let text = [200:"OK",400:"Bad Request",404:"Not Found",500:"Internal Server Error"][status] ?? "Unknown"
        let hdr = "HTTP/1.1 \(status) \(text)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Headers: Content-Type\r\n" +
            "Connection: close\r\n\r\n"
        return Data(hdr.utf8) + body
    }
}

// MARK: - Web Server

/// Minimal HTTP server that runs alongside a BigScreen host session.
/// Players on the same Wi-Fi network can open the URL in a browser and
/// play the game without installing the Parlor app.
@MainActor
final class BigScreenWebServer: ObservableObject {
    private var listener: NWListener?
    @Published var localURL: URL?

    weak var session: GameSession?

    private struct WebPlayer {
        var playerID: String
        var sessionID: String
        var name: String
        var seat: Int
    }
    private var webPlayers: [String: WebPlayer] = [:]  // sessionID → player

    // MARK: Lifecycle

    func start(with session: GameSession) {
        self.session = session
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params) else { return }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.handle(conn) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, case .ready = state,
                      let port = self.listener?.port?.rawValue,
                      let ip = Self.localIPv4() else { return }
                self.localURL = URL(string: "http://\(ip):\(port)")
            }
        }
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        webPlayers = [:]
        localURL = nil
    }

    // MARK: Connection

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self, let data, !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else {
                    connection.cancel(); return
                }
                let response = self.route(text)
                connection.send(content: response.wire(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    // MARK: Routing

    private func route(_ raw: String) -> WebResponse {
        let lines = raw.components(separatedBy: "\r\n")
        guard let first = lines.first else { return .error("Bad request") }
        let parts = first.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return .error("Bad request") }
        let method = String(parts[0])
        let rawPath = String(parts[1])
        let (path, query) = Self.parsePath(rawPath)

        var body: [String: Any] = [:]
        if let range = raw.range(of: "\r\n\r\n") {
            let bodyText = String(raw[range.upperBound...])
            if !bodyText.isEmpty, let d = bodyText.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                body = j
            }
        }

        switch (method, path) {
        case (_, "/"):          return .html(Self.controllerPage)
        case ("GET", "/api/lobby"):  return apiLobby()
        case ("POST", "/api/join"):  return apiJoin(body: body)
        case ("GET", "/api/state"):  return apiState(sessionID: query["id"] ?? "")
        case ("POST", "/api/move"):  return apiMove(body: body)
        case ("OPTIONS", _):        return .ok()
        default:                    return .notFound()
        }
    }

    // MARK: API endpoints

    private func apiLobby() -> WebResponse {
        guard let session else { return .error("No session") }
        let seats: [[String: Any]] = (0..<session.seatsTotal).map { seat in
            let p = session.lobby.players[safe: seat]
            return ["seat": seat, "name": p?.name ?? "", "filled": p != nil]
        }
        return .json([
            "gameName": session.lobby.gameKind.title,
            "seatsTotal": session.seatsTotal,
            "seatsFilled": session.seatsFilled,
            "started": session.game != nil,
            "seats": seats
        ])
    }

    private func apiJoin(body: [String: Any]) -> WebResponse {
        guard let session else { return .error("No session") }
        let rawName = body["name"] as? String ?? ""
        let name = String(rawName.trimmingCharacters(in: .whitespaces).prefix(20))
        guard !name.isEmpty else { return .error("Name required") }
        guard session.game == nil else { return .error("Game already started — wait for the next round") }
        guard session.seatsFilled < session.seatsTotal else { return .error("Game is full") }

        let playerID = "web-\(UUID().uuidString.prefix(8))"
        let sessionID = UUID().uuidString
        guard session.addWebPlayer(PlayerInfo(id: playerID, name: name)) else {
            return .error("Could not join")
        }
        let seat = session.seatsFilled - 1
        webPlayers[sessionID] = WebPlayer(playerID: playerID, sessionID: sessionID, name: name, seat: seat)
        return .json(["sessionID": sessionID, "seat": seat, "name": name,
                      "gameName": session.lobby.gameKind.title])
    }

    private func apiState(sessionID: String) -> WebResponse {
        guard let session else { return .error("No session") }
        guard let wp = webPlayers[sessionID] else { return .error("Session expired") }

        guard let game = session.game else {
            return .json([
                "waiting": true,
                "statusText": "Waiting for host to start\u{2026}",
                "seatsFilled": session.seatsFilled,
                "seatsTotal": session.seatsTotal,
                "mySeat": wp.seat,
                "myName": wp.name
            ])
        }

        let engine = game.engine.redacted(for: wp.seat)
        let isMyTurn = engine.currentPlayer == wp.seat && !engine.isOver

        var result: [String: Any] = [
            "isOver": engine.isOver,
            "statusText": engine.statusText,
            "isMyTurn": isMyTurn,
            "mySeat": wp.seat,
            "myName": wp.name,
            "currentPlayer": engine.currentPlayer,
            "currentPlayerName": session.playerName(seat: engine.currentPlayer)
        ]
        if let rt = engine.resultText { result["resultText"] = rt }

        if isMyTurn {
            let moves = engine.legalMoves()

            // Hearts pass phase: player must select 3 cards manually
            if let hg = game.engine as? HeartsGame,
               hg.phase == .passing,
               hg.currentPlayer == wp.seat {
                let hand = hg.hands[safe: wp.seat] ?? []
                result["phase"] = "passCards"
                result["passCount"] = 3
                result["hand"] = hand.map { c -> [String: Any] in
                    ["label": c.label, "isRed": c.suit == .hearts || c.suit == .diamonds]
                }
                result["moves"] = [] as [[String: Any]]
            } else {
                let isCardGame = moves.contains { if case .playCard = $0 { return true }; return false }
                result["isCardGame"] = isCardGame
                result["moves"] = moves.enumerated().map { i, m -> [String: Any] in
                    ["index": i, "label": m.webLabel]
                }
                // Expose hand for card games that have it
                if let hand = Self.extractHand(engine: game.engine, seat: wp.seat), !hand.isEmpty {
                    result["hand"] = hand.map { c -> [String: Any] in
                        ["label": c.label, "isRed": c.suit == .hearts || c.suit == .diamonds]
                    }
                }
            }
        }
        return .json(result)
    }

    private func apiMove(body: [String: Any]) -> WebResponse {
        guard let session else { return .error("No session") }
        guard let sessionID = body["id"] as? String,
              let wp = webPlayers[sessionID] else { return .error("Session expired") }
        guard let game = session.game, !game.isOver else { return .error("Game not active") }
        guard game.currentPlayer == wp.seat else { return .error("Not your turn") }

        // Multi-card pass (Hearts pass phase)
        if let labels = body["passLabels"] as? [String] {
            let cards = labels.compactMap { lbl in Self.cardByLabel(lbl) }
            guard cards.count == 3 else { return .error("Select exactly 3 cards") }
            session.submitFromWeb(move: .passCards(cards), seat: wp.seat)
            return .json(["ok": true])
        }

        // Standard single-move by index
        guard let idx = body["moveIndex"] as? Int else { return .error("Missing moveIndex") }
        let moves = game.engine.legalMoves()
        guard moves.indices.contains(idx) else { return .error("Invalid move index") }
        session.submitFromWeb(move: moves[idx], seat: wp.seat)
        return .json(["ok": true])
    }

    // MARK: Helpers

    private static func cardByLabel(_ label: String) -> Card? {
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                let c = Card(suit: suit, rank: rank)
                if c.label == label { return c }
            }
        }
        return nil
    }

    private static func extractHand(engine: any GameEngine, seat: Int) -> [Card]? {
        if let g = engine as? HeartsGame  { return g.hands[safe: seat] }
        if let g = engine as? SpadesGame  { return g.hands[safe: seat] }
        if let g = engine as? EuchreGame  { return g.hands[safe: seat] }
        if let g = engine as? BridgeGame  { return g.hands[safe: seat] }
        return nil
    }

    static func parsePath(_ raw: String) -> (String, [String: String]) {
        guard let qi = raw.firstIndex(of: "?") else { return (raw, [:]) }
        let path = String(raw[raw.startIndex..<qi])
        let qs = String(raw[raw.index(after: qi)...])
        var q: [String: String] = [:]
        for pair in qs.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                q[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return (path, q)
    }

    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var result: String?
        var ptr = ifaddr
        while let curr = ptr {
            defer { ptr = curr.pointee.ifa_next }
            let flags = Int32(curr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard curr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(curr.pointee.ifa_addr,
                        socklen_t(curr.pointee.ifa_addr.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let addr = String(cString: host)
            if !addr.isEmpty { result = addr }
        }
        return result
    }

    // MARK: Embedded HTML controller page

    static let controllerPage = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <title>Parlor</title>
    <style>
    *{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
    body{background:#0f1523;color:#e8e8f0;font-family:-apple-system,BlinkMacSystemFont,sans-serif;min-height:100vh;padding-bottom:40px}
    h1{text-align:center;font-size:26px;font-weight:800;padding:22px 0 4px;letter-spacing:-.5px}
    h1 span{color:#4db6ac}
    .sub{text-align:center;color:rgba(255,255,255,.4);font-size:14px;margin-bottom:16px}
    .card{background:#1a2035;border-radius:18px;padding:18px;margin:10px 14px;border:1px solid rgba(255,255,255,.07)}
    .btn{display:block;width:100%;padding:14px 12px;border:none;border-radius:12px;font-size:17px;font-weight:600;margin:7px 0;cursor:pointer;background:#1e3a5f;color:#e8e8f0;transition:all .1s}
    .btn:active{transform:scale(.97);opacity:.85}
    .btn.primary{background:linear-gradient(135deg,#2196f3,#0d47a1)}
    .btn.accent{background:linear-gradient(135deg,#4db6ac,#00796b)}
    .turn{text-align:center;font-size:22px;font-weight:800;color:#4db6ac;padding:10px 0 6px}
    .wait{text-align:center;color:rgba(255,255,255,.45);font-size:15px;padding:16px}
    .seat-row{display:flex;align-items:center;justify-content:center;gap:8px;padding:6px 0;font-size:14px;color:rgba(255,255,255,.6)}
    .sbadge{background:#4db6ac22;color:#4db6ac;border-radius:8px;padding:3px 9px;font-weight:700;font-size:13px}
    .hgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;padding:4px 0}
    .ctile{background:#fff;color:#222;border-radius:10px;padding:14px 4px 10px;text-align:center;font-size:22px;font-weight:800;cursor:pointer;border:3px solid transparent;transition:all .1s;line-height:1;user-select:none}
    .ctile.red{color:#d32f2f}
    .ctile:active{transform:translateY(-2px);box-shadow:0 4px 12px rgba(0,0,0,.3)}
    .ctile.sel{border-color:#f59e0b;background:#fffde7;transform:translateY(-4px)}
    .bgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:7px}
    .bbtn{background:#1e3a5f;border:none;border-radius:10px;color:#e8e8f0;font-size:17px;font-weight:700;padding:14px 0;cursor:pointer;transition:all .1s}
    .bbtn:active{transform:scale(.95);background:#2196f3}
    .agrid{display:grid;grid-template-columns:1fr 1fr;gap:9px}
    .abtn{background:#1a2b50;border:2px solid #2a3d6e;border-radius:14px;color:#e8e8f0;font-size:15px;font-weight:600;padding:16px 10px;cursor:pointer;text-align:left;transition:all .1s;display:flex;align-items:center;gap:8px}
    .abtn:active{transform:scale(.97);background:#1e3a5f}
    .aletter{background:#2196f3;color:#fff;border-radius:7px;width:26px;height:26px;text-align:center;line-height:26px;font-size:14px;font-weight:800;flex-shrink:0}
    input[type=text]{width:100%;padding:14px;border:2px solid #2a3d6e;border-radius:12px;background:#111827;color:#e8e8f0;font-size:17px;outline:none}
    input[type=text]:focus{border-color:#4db6ac}
    .err{color:#ef5350;text-align:center;font-size:14px;padding:8px 0}
    .irow{display:flex;justify-content:space-between;align-items:center;font-size:13px;color:rgba(255,255,255,.5);padding:4px 0}
    .pbar{height:4px;background:#1e3a5f;border-radius:4px;margin-top:10px;overflow:hidden}
    .pfill{height:100%;background:#4db6ac;transition:width .4s}
    .passbtns{margin-top:10px;display:none}
    .passbtns.show{display:block}
    </style>
    </head>
    <body>
    <h1>&#127924; <span>Parlor</span></h1>
    <p class="sub" id="gname">Loading&hellip;</p>
    <div id="app"></div>
    <script>
    var sid=null,mySeat=null,myName=null,poll_=null,passSelected=[];
    var app=function(){return document.getElementById('app')};
    var sub=function(t){document.getElementById('gname').textContent=t};
    var render=function(h){app().innerHTML=h};
    var esc=function(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')};

    async function api(method,path,body){
      try{
        var r=await fetch(path,{method:method,headers:{'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
        return r.json();
      }catch(e){return{error:'Network error'}}
    }

    async function showJoin(){
      var d=await api('GET','/api/lobby');
      if(d.error){render('<div class="card"><p class="err">'+esc(d.error)+'</p></div>');return}
      sub(d.gameName||'Parlor');
      var pct=Math.round((d.seatsFilled/d.seatsTotal)*100);
      render('<div class="card"><p style="text-align:center;margin-bottom:14px;color:rgba(255,255,255,.55);font-size:14px">'+
        d.seatsFilled+'/'+d.seatsTotal+' players joined</p>'+
        '<div class="pbar"><div class="pfill" style="width:'+pct+'%"></div></div>'+
        '<p style="height:10px"></p>'+
        '<input type="text" id="pname" placeholder="Your name" maxlength="20" autocomplete="off">'+
        '<p class="err" id="jerr"></p>'+
        '<button class="btn primary" onclick="joinGame()">Join Game</button>'+
        '</div>');
      var el=document.getElementById('pname');
      if(el){el.focus();el.addEventListener('keydown',function(e){if(e.key==='Enter')joinGame()});}
    }

    async function joinGame(){
      var name=(document.getElementById('pname')||{}).value||'';
      name=name.trim();
      if(!name){document.getElementById('jerr').textContent='Enter your name';return}
      var d=await api('POST','/api/join',{name:name});
      if(d.error){document.getElementById('jerr').textContent=d.error;return}
      sid=d.sessionID; mySeat=d.seat; myName=d.name;
      sub(d.gameName);
      startPoll();
    }

    function startPoll(){if(poll_)clearInterval(poll_);poll_=setInterval(doPoll,900);doPoll();}

    async function doPoll(){
      var d=await api('GET','/api/state?id='+sid);
      if(d.error){clearInterval(poll_);render('<div class="card"><p class="err">'+esc(d.error)+'</p><button class="btn" onclick="location.reload()">Reconnect</button></div>');return}
      renderState(d);
    }

    function renderState(d){
      if(d.waiting){
        var pct=Math.round((d.seatsFilled/d.seatsTotal)*100);
        render('<div class="card"><div class="turn" style="color:rgba(255,255,255,.6)">&#9203; Waiting for host&hellip;</div>'+
          '<p class="wait">'+esc(d.statusText||'')+'</p>'+
          '<div class="irow"><span>Players joined</span><span>'+d.seatsFilled+'/'+d.seatsTotal+'</span></div>'+
          '<div class="pbar"><div class="pfill" style="width:'+pct+'%"></div></div>'+
          '</div>');
        return;
      }
      if(d.isOver){
        clearInterval(poll_);
        render('<div class="card"><div class="turn">Game Over!</div>'+
          '<p style="text-align:center;padding:12px;opacity:.8">'+esc(d.resultText||'')+'</p></div>');
        return;
      }

      var html='<div style="text-align:center;font-size:13px;color:rgba(255,255,255,.45);padding:6px 14px 0">'+esc(d.statusText||'')+'</div>'+
        '<div class="card" style="padding:10px 18px">'+
        '<div class="seat-row"><span class="sbadge">Seat '+(+(d.mySeat||0)+1)+'</span><span>'+esc(d.myName||'')+'</span></div>'+
        '</div>';

      if(d.isMyTurn){
        html+='<div class="card"><div class="turn">&#127775; Your Turn!</div>';
        if(d.phase==='passCards'){html+=buildPass(d);}
        else if(d.moves&&d.moves.length){html+=buildMoves(d);}
        html+='</div>';
      } else {
        html+='<div class="card"><p class="wait">Waiting for <b>'+esc(d.currentPlayerName||'other player')+'</b>&hellip;</p></div>';
      }
      render(html);
    }

    function buildMoves(d){
      var m=d.moves||[];
      // Trivia-style: exactly 4 single-letter labels A/B/C/D
      if(m.length===4&&m.every(function(x){return /^[A-D]$/.test(x.label)})){
        return '<div class="agrid">'+m.map(function(x){
          return '<button class="abtn" onclick="doMove('+x.index+')"><span class="aletter">'+esc(x.label)+'</span></button>';
        }).join('')+'</div>';
      }
      // Numeric bids (8+ buttons that parse as numbers or are "Nil")
      if(m.length>=5&&m.every(function(x){return !isNaN(parseInt(x.label))||x.label==='Nil'||x.label==='Pass'})){
        return '<div class="bgrid">'+m.map(function(x){
          return '<button class="bbtn" onclick="doMove('+x.index+')">'+esc(x.label)+'</button>';
        }).join('')+'</div>';
      }
      // Card game: grid of card tiles
      if(d.isCardGame){
        return '<div class="hgrid">'+m.map(function(x){
          var red=x.label.indexOf('♥')>=0||x.label.indexOf('♦')>=0;
          return '<div class="ctile'+(red?' red':'')+'" onclick="doMove('+x.index+')">'+esc(x.label)+'</div>';
        }).join('')+'</div>';
      }
      // Generic buttons
      return m.map(function(x){return '<button class="btn" onclick="doMove('+x.index+')">'+esc(x.label)+'</button>';}).join('');
    }

    function buildPass(d){
      passSelected=[];
      var hand=d.hand||[], count=d.passCount||3;
      var html='<p style="text-align:center;font-size:14px;color:rgba(255,255,255,.6);margin-bottom:10px">Select '+count+' cards to pass</p>'+
        '<div class="hgrid" id="pgrid">';
      hand.forEach(function(c,i){
        var red=c.isRed;
        html+='<div class="ctile'+(red?' red':'')+'" id="pc'+i+'" onclick="togglePass(\''+esc(c.label)+'\','+i+')">'+esc(c.label)+'</div>';
      });
      html+='</div><div class="passbtns" id="passbtn">'+
        '<button class="btn accent" onclick="submitPass()">Pass Selected (0/'+count+')</button></div>';
      return html;
    }

    function togglePass(label,idx){
      var el=document.getElementById('pc'+idx);
      if(!el)return;
      var pos=passSelected.indexOf(label);
      if(pos>=0){passSelected.splice(pos,1);el.classList.remove('sel');}
      else if(passSelected.length<3){passSelected.push(label);el.classList.add('sel');}
      var btn=document.getElementById('passbtn');
      if(btn){
        btn.querySelector('button').textContent='Pass Selected ('+passSelected.length+'/3)';
        if(passSelected.length===3)btn.classList.add('show'); else btn.classList.remove('show');
      }
    }

    async function submitPass(){
      var d=await api('POST','/api/move',{id:sid,passLabels:passSelected});
      if(!d.error)doPoll();
    }

    async function doMove(idx){
      var d=await api('POST','/api/move',{id:sid,moveIndex:idx});
      if(d.error){
        var el=document.createElement('p');el.className='err';el.textContent=d.error;
        var c=document.querySelector('.card');if(c)c.appendChild(el);
      } else { doPoll(); }
    }

    showJoin();
    </script>
    </body>
    </html>
    """
}
