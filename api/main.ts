// WebSocket server for clipboard message distribution
// Replaces the Windows tick adapter with websocket-driven updates
// Zero external dependencies - uses only Deno runtime APIs

const clients = new Set<WebSocket>();
let lastMessage: string | null = null;

function broadcast(text: string) {
  lastMessage = text;
  const payload = JSON.stringify({ text });
  const deadClients: WebSocket[] = [];

  for (const client of clients) {
    try {
      if (client.readyState === WebSocket.OPEN) {
        client.send(payload);
      } else {
        deadClients.push(client);
      }
    } catch (error) {
      console.error("Failed to send to client:", error);
      deadClients.push(client);
    }
  }

  deadClients.forEach((client) => clients.delete(client));
}

function handleWebSocket(req: Request): Response {
  const { socket, response } = Deno.upgradeWebSocket(req);

  socket.addEventListener("open", () => {
    clients.add(socket);
    console.log(`[WS] Client connected. Total: ${clients.size}`);
  });

  socket.addEventListener("close", () => {
    clients.delete(socket);
    console.log(`[WS] Client disconnected. Total: ${clients.size}`);
  });

  socket.addEventListener("error", (event) => {
    console.error("[WS] Client error:", event);
    clients.delete(socket);
  });

  return response;
}

async function handlePostMessage(req: Request): Promise<Response> {
  const contentType = req.headers.get("content-type") || "";

  try {
    let text: string;

    if (contentType.includes("application/json")) {
      const body = await req.json();
      text = body.text || body.message || "";
    } else {
      text = await req.text();
    }

    if (!text.trim()) {
      return new Response("Empty message", { status: 400 });
    }

    console.log(`[POST] Broadcasting: "${text}" to ${clients.size} client(s)`);
    broadcast(text);

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(`Invalid request: ${error}`, { status: 400 });
  }
}

function handleStats(): Response {
  const stats = {
    clients: clients.size,
    uptime: Math.floor(performance.now() / 1000),
  };

  return new Response(JSON.stringify(stats), {
    headers: { "Content-Type": "application/json" },
  });
}

function handlePoll(): Response {
  if (lastMessage === null) {
    return new Response(JSON.stringify({ text: "" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ text: lastMessage }), {
    headers: { "Content-Type": "application/json" },
  });
}

function handleRoot(): Response {
  const help = `Clipboard WebSocket API

Available endpoints:
  GET  /           - This help message
  GET  /ws         - WebSocket connection for receiving messages
  POST /messages   - Send a new message (JSON or plain text)
  GET  /poll       - Get latest message (for HTTP polling clients)
  GET  /stats      - Server statistics

Examples:
  # Send message (JSON)
  curl -X POST http://localhost:8000/messages \\
    -H "Content-Type: application/json" \\
    -d '{"text":"Hello from API"}'

  # Send message (plain text)
  curl -X POST http://localhost:8000/messages \\
    -H "Content-Type: text/plain" \\
    -d "Hello from API"

  # Connect to WebSocket (websocat)
  websocat ws://localhost:8000/ws

  # Connect to WebSocket (JavaScript)
  const ws = new WebSocket('ws://localhost:8000/ws');
  ws.onmessage = (event) => console.log(JSON.parse(event.data));
`;

  return new Response(help, {
    headers: { "Content-Type": "text/plain" },
  });
}

function handleRequest(req: Request): Response | Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;
  const method = req.method;

  // WebSocket endpoint
  if (path === "/ws") {
    if (req.headers.get("upgrade") === "websocket") {
      return handleWebSocket(req);
    }
    return new Response("WebSocket endpoint. Use ws:// protocol", { status: 426 });
  }

  // HTTP endpoints
  if (path === "/messages" && method === "POST") {
    return handlePostMessage(req);
  }

  if (path === "/stats" && method === "GET") {
    return handleStats();
  }

  if (path === "/poll" && method === "GET") {
    return handlePoll();
  }

  if (path === "/" && method === "GET") {
    return handleRoot();
  }

  return new Response("Not Found", { status: 404 });
}

if (import.meta.main) {
  const PORT = 8000;
  console.log(`\n🚀 Clipboard API Server Starting\n`);
  console.log(`   WebSocket: ws://localhost:${PORT}/ws`);
  console.log(`   HTTP POST: http://localhost:${PORT}/messages`);
  console.log(`   HTTP Poll: http://localhost:${PORT}/poll`);
  console.log(`   Docs:      http://localhost:${PORT}/\n`);

  Deno.serve({ port: PORT }, handleRequest);
}

export { handleRequest };
