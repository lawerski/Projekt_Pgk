const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8910 });
const ROOMS = {}; // { code: { host: ws, clients: Map<id, ws>, vipId: string|null } }
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function genRoomCode() {
    let code;
    do {
        code = Array.from({length:4},()=>CODE_CHARS[Math.floor(Math.random()*CODE_CHARS.length)]).join('');
    } while (ROOMS[code]);
    return code;
}
function genClientId() {
    return Math.random().toString(36).substr(2, 8);
}

wss.on('connection', ws => {
    ws._room = null;
    ws._isHost = false;
    ws._clientId = null;

    ws.on('message', msg => {
        let data;
        try { data = JSON.parse(msg); } catch { return; }
        // --- Host registration ---
        if (data.type === 'register_host') {
            const code = genRoomCode();
            ROOMS[code] = { host: ws, clients: {}, vipId: null, nextId: 1 }; // <-- dodaj nextId: 1
            ws._room = code;
            ws._isHost = true;
            ws.send(JSON.stringify({ type: 'host_registered', room: code }));
            return;
        }
        // --- Player join ---
        if (data.type === 'join_request') {
            const code = (data.room || '').toUpperCase();
            if (!ROOMS[code] || !ROOMS[code].host) {
                ws.send(JSON.stringify({ type: 'join_error', message: 'Pokój nie istnieje.' }));
                return;
            }
            const clientId = 'C' + ROOMS[code].nextId++;
            ws.roomCode = code;
            ws.clientId = clientId;
            ws._clientId = clientId; // <-- DODAJ TO!
            ws._room = code;         // <-- DODAJ TO!
            ROOMS[code].clients[clientId] = ws;
            ws.send(JSON.stringify({ type: 'join_accepted', clientId: clientId }));
            ROOMS[code].host.send(JSON.stringify({
                type: 'join_request',
                clientId,
                player_info: {
                    name: data.name,
                    avatar_base64: data.avatar,
                    team: data.team // <-- DODANE!
                }
            }));
            return;
        }
        // --- Host to client routing ---
        if (data.targetId && data.data && ws._isHost && ws._room) {
            const room = ROOMS[ws._room];
            // Wysyłanie do klienta:
            if (room && room.clients[data.targetId]) {
                room.clients[data.targetId].send(JSON.stringify(data.data));
            }
            return;
        }
        // --- Client to host (answers, commands, etc) ---
        if (ws._clientId && ws._room && ROOMS[ws._room]) {
            const host = ROOMS[ws._room].host;
            host.send(JSON.stringify({
                type: data.type,
                clientId: ws._clientId,
                ...data
            }));
        }
        // --- Choose team ---
        if (data.type === 'choose_team' && ws.clientId && ws.roomCode && ROOMS[ws.roomCode]) {
            ROOMS[ws.roomCode].host.send(JSON.stringify({
                type: 'choose_team',
                clientId: ws.clientId,
                team: data.team
            }));
            ws.send(JSON.stringify({ type: 'team_confirmed', team: data.team }));
            return;
        }
    });

        ws.on('close', () => {
        if (ws._isHost && ws._room && ROOMS[ws._room]) {
            // Close all clients
            for (const clientId in ROOMS[ws._room].clients) {
                ROOMS[ws._room].clients[clientId].close();
            }
            delete ROOMS[ws._room];
        } else if (ws._room && ws._clientId && ROOMS[ws._room]) {
            const room = ROOMS[ws._room];
            // Inform host about client disconnect so host can update UI
            try {
                if (room.host && room.host.readyState === WebSocket.OPEN) {
                    room.host.send(JSON.stringify({ type: 'player_left', clientId: ws._clientId }));
                }
            } catch (e) {
                // ignore
            }
            delete ROOMS[ws._room].clients[ws._clientId];
        }
    });
});

console.log('Relay server running on ws://0.0.0.0:8910');
