# Clipboard WebSocket API

API WebSocket para substituir o sistema de tick do app Zig. Permite enviar mensagens via HTTP que são broadcastadas em tempo real para clientes WebSocket conectados.

## Arquitetura

```
HTTP POST /messages → Broadcast → WebSocket Clients → Zig App → Clipboard
```

## Iniciar o Servidor

```bash
# Desenvolvimento (auto-reload)
deno task dev

# Produção
deno task start
```

O servidor inicia em `http://localhost:8000`

## Endpoints

### WebSocket
```
GET ws://localhost:8000/ws
```
Conecta cliente WebSocket para receber mensagens em tempo real.

**Formato das mensagens recebidas:**
```json
{"text": "conteúdo da mensagem"}
```

### HTTP POST
```
POST http://localhost:8000/messages
Content-Type: application/json

{"text": "Hello from API"}
```

Também aceita `text/plain`:
```
POST http://localhost:8000/messages
Content-Type: text/plain

Hello from API
```

### Estatísticas
```
GET http://localhost:8000/stats
```

Retorna número de clientes conectados e uptime.

## Exemplos de Uso

### Enviar mensagem (curl)
```bash
# JSON
curl -X POST http://localhost:8000/messages \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello World"}'

# Plain text
curl -X POST http://localhost:8000/messages \
  -H "Content-Type: text/plain" \
  -d "Hello World"
```

### Conectar WebSocket (JavaScript)
```javascript
const ws = new WebSocket('ws://localhost:8000/ws');

ws.onopen = () => console.log('Connected');
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Received:', data.text);
};
```

### Conectar WebSocket (websocat CLI)
```bash
websocat ws://localhost:8000/ws
```

## Integração Futura com Zig

O cliente Zig substituirá o `WindowsTickAdapter` por um `WebSocketAdapter`:

```zig
// Futuro adapter WebSocket
pub const WebSocketAdapter = struct {
    // Conecta em ws://localhost:8000/ws
    // Recebe {"text": "..."}
    // Dispara onTick callback
};
```

## Características

- ✅ Zero dependências externas (apenas Deno runtime)
- ✅ Broadcast em tempo real
- ✅ Sem persistência (in-memory apenas)
- ✅ Sem autenticação (localhost apenas)
- ✅ Suporta múltiplos clientes simultâneos
- ✅ Auto-cleanup de conexões mortas
