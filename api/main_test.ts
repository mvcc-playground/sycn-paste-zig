// Integration tests for WebSocket API
// Run with: deno test --allow-net main_test.ts

import { assertEquals, assertExists, assertMatch } from "jsr:@std/assert@1";
import { handleRequest } from "./main.ts";

// Type definitions
interface MessagePayload {
  text: string;
}

interface StatsResponse {
  clients: number;
  uptime: number;
}

interface PostResponse {
  success: boolean;
}

interface PollResponse {
  text: string;
}

// Helper to start a test server
async function startTestServer(port: number) {
  const controller = new AbortController();
  const server = Deno.serve(
    { port, signal: controller.signal, onListen: () => {} },
    (req) => handleRequest(req)
  );

  // Wait for server to be ready
  await new Promise((resolve) => setTimeout(resolve, 100));

  return {
    url: `http://localhost:${port}`,
    wsUrl: `ws://localhost:${port}`,
    shutdown: async () => {
      controller.abort();
      await server.finished;
    },
  };
}

Deno.test("GET / returns help documentation", async () => {
  const server = await startTestServer(8001);

  try {
    const response = await fetch(server.url);
    assertEquals(response.status, 200, "Should return 200 OK");
    assertEquals(response.headers.get("content-type"), "text/plain", "Should be text/plain");

    const text = await response.text();
    assertExists(text, "Response body should exist");
    assertMatch(text, /Clipboard WebSocket API/, "Should contain title");
    assertMatch(text, /\/ws/, "Should mention WebSocket endpoint");
    assertMatch(text, /\/messages/, "Should mention messages endpoint");
    assertMatch(text, /\/stats/, "Should mention stats endpoint");
  } finally {
    await server.shutdown();
  }
});

Deno.test("GET /stats returns server statistics", async () => {
  const server = await startTestServer(8002);

  try {
    const response = await fetch(`${server.url}/stats`);
    assertEquals(response.status, 200, "Should return 200 OK");
    assertEquals(response.headers.get("content-type"), "application/json", "Should be JSON");

    const data: StatsResponse = await response.json();
    assertEquals(typeof data.clients, "number", "clients should be a number");
    assertEquals(typeof data.uptime, "number", "uptime should be a number");
    assertEquals(data.clients, 0, "Should have 0 clients initially");
    assertEquals(data.uptime >= 0, true, "uptime should be non-negative");
  } finally {
    await server.shutdown();
  }
});

Deno.test("GET /poll returns empty text when no message exists", async () => {
  const server = await startTestServer(8016);

  try {
    const response = await fetch(`${server.url}/poll`);
    assertEquals(response.status, 200, "Should return 200 OK");
    assertEquals(response.headers.get("content-type"), "application/json", "Should be JSON");

    const data: PollResponse = await response.json();
    assertEquals(data.text, "", "Should return empty text when no message exists");
  } finally {
    await server.shutdown();
  }
});

Deno.test("GET /poll returns latest posted message", async () => {
  const server = await startTestServer(8017);

  try {
    const postResponse = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "Latest for polling" }),
    });
    assertEquals(postResponse.status, 200, "POST should succeed");
    await postResponse.json();

    const response = await fetch(`${server.url}/poll`);
    assertEquals(response.status, 200, "Should return 200 OK");
    assertEquals(response.headers.get("content-type"), "application/json", "Should be JSON");

    const data: PollResponse = await response.json();
    assertEquals(data.text, "Latest for polling", "Should return latest message");
  } finally {
    await server.shutdown();
  }
});

Deno.test("POST /messages with JSON broadcasts to WebSocket", async () => {
  const server = await startTestServer(8003);

  try {
    // Connect WebSocket client
    const ws = new WebSocket(`${server.wsUrl}/ws`);

    // Wait for connection
    await new Promise((resolve) => {
      ws.onopen = resolve;
    });

    // Set up message listener
    const messagePromise = new Promise<string>((resolve) => {
      ws.onmessage = (event) => resolve(event.data);
    });

    // Send POST request
    const response = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "Hello WebSocket" }),
    });

    if (response.status !== 200) {
      throw new Error(`Expected status 200, got ${response.status}`);
    }

    const result: PostResponse = await response.json();
    assertEquals(result.success, true, "POST should return success: true");

    // Verify WebSocket received the message
    const received = await messagePromise;
    const data: MessagePayload = JSON.parse(received);
    assertEquals(typeof data.text, "string", "message.text should be a string");
    assertEquals(data.text, "Hello WebSocket", "Should receive correct message text");

    ws.close();
  } finally {
    await server.shutdown();
  }
});

Deno.test("POST /messages with plain text broadcasts correctly", async () => {
  const server = await startTestServer(8004);

  try {
    const ws = new WebSocket(`${server.wsUrl}/ws`);

    await new Promise((resolve) => {
      ws.onopen = resolve;
    });

    const messagePromise = new Promise<string>((resolve) => {
      ws.onmessage = (event) => resolve(event.data);
    });

    const response = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "text/plain" },
      body: "Plain text message",
    });

    if (response.status !== 200) {
      throw new Error(`Expected status 200, got ${response.status}`);
    }

    await response.json(); // Consume response body

    const received = await messagePromise;
    const data: MessagePayload = JSON.parse(received);
    assertEquals(data.text, "Plain text message", "Should receive plain text message");

    ws.close();
  } finally {
    await server.shutdown();
  }
});

Deno.test("POST /messages with empty text returns 400", async () => {
  const server = await startTestServer(8005);

  try {
    const response = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "" }),
    });

    assertEquals(response.status, 400, "Empty message should return 400 Bad Request");

    const errorText = await response.text();
    assertMatch(errorText, /[Ee]mpty/, "Error message should mention empty message");
  } finally {
    await server.shutdown();
  }
});

Deno.test("Broadcast to multiple WebSocket clients", async () => {
  const server = await startTestServer(8006);

  try {
    // Connect two WebSocket clients
    const ws1 = new WebSocket(`${server.wsUrl}/ws`);
    const ws2 = new WebSocket(`${server.wsUrl}/ws`);

    await Promise.all([
      new Promise((resolve) => ws1.onopen = resolve),
      new Promise((resolve) => ws2.onopen = resolve),
    ]);

    // Set up message listeners
    const message1Promise = new Promise<string>((resolve) => {
      ws1.onmessage = (event) => resolve(event.data);
    });

    const message2Promise = new Promise<string>((resolve) => {
      ws2.onmessage = (event) => resolve(event.data);
    });

    // Send message
    const response = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "Broadcast test" }),
    });
    await response.json(); // Consume response body

    // Both clients should receive the message
    const [received1, received2] = await Promise.all([
      message1Promise,
      message2Promise,
    ]);

    const data1: MessagePayload = JSON.parse(received1);
    const data2: MessagePayload = JSON.parse(received2);

    assertEquals(data1.text, "Broadcast test", "Client 1 should receive message");
    assertEquals(data2.text, "Broadcast test", "Client 2 should receive message");
    assertEquals(data1.text, data2.text, "Both clients should receive identical message");

    ws1.close();
    ws2.close();
  } finally {
    await server.shutdown();
  }
});

Deno.test("WebSocket connection increments client count", async () => {
  const server = await startTestServer(8007);

  try {
    // Check initial stats
    let response = await fetch(`${server.url}/stats`);
    let data: StatsResponse = await response.json();
    assertEquals(data.clients, 0, "Should start with 0 clients");

    // Connect a WebSocket
    const ws = new WebSocket(`${server.wsUrl}/ws`);
    await new Promise((resolve) => ws.onopen = resolve);

    // Wait a bit for server to register the client
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Check stats again
    response = await fetch(`${server.url}/stats`);
    data = await response.json();
    assertEquals(data.clients, 1, "Should have 1 client after connection");

    ws.close();

    // Wait for disconnect
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Should be back to 0
    response = await fetch(`${server.url}/stats`);
    data = await response.json();
    assertEquals(data.clients, 0, "Should return to 0 clients after disconnect");
  } finally {
    await server.shutdown();
  }
});

Deno.test("Unknown route returns 404", async () => {
  const server = await startTestServer(8008);

  try {
    const response = await fetch(`${server.url}/unknown`);

    assertEquals(response.status, 404, "Unknown route should return 404");

    const errorText = await response.text();
    assertMatch(errorText, /[Nn]ot [Ff]ound/, "Should return Not Found message");
  } finally {
    await server.shutdown();
  }
});

Deno.test("POST /messages accepts 'message' field as alias", async () => {
  const server = await startTestServer(8009);

  try {
    const ws = new WebSocket(`${server.wsUrl}/ws`);
    await new Promise((resolve) => ws.onopen = resolve);

    const messagePromise = new Promise<string>((resolve) => {
      ws.onmessage = (event) => resolve(event.data);
    });

    // Use 'message' field instead of 'text'
    const response = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: "Using message field" }),
    });
    await response.json(); // Consume response body

    const received = await messagePromise;
    const data: MessagePayload = JSON.parse(received);
    assertEquals(data.text, "Using message field", "Should accept 'message' field as alias");

    ws.close();
  } finally {
    await server.shutdown();
  }
});

Deno.test("POST /messages with invalid JSON returns 400", async () => {
  const server = await startTestServer(8010);

  try {
    const response = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{invalid json}",
    });

    assertEquals(response.status, 400, "Invalid JSON should return 400");

    const errorText = await response.text();
    assertMatch(errorText, /[Ii]nvalid/, "Should mention invalid request");
  } finally {
    await server.shutdown();
  }
});

Deno.test("POST /messages with whitespace-only text returns 400", async () => {
  const server = await startTestServer(8011);

  try {
    const response = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "text/plain" },
      body: "   \n\t  ",
    });

    assertEquals(response.status, 400, "Whitespace-only message should return 400");
    await response.text();
  } finally {
    await server.shutdown();
  }
});

Deno.test("WebSocket receives messages in correct order", async () => {
  const server = await startTestServer(8012);

  try {
    const ws = new WebSocket(`${server.wsUrl}/ws`);
    await new Promise((resolve) => ws.onopen = resolve);

    const messages: string[] = [];
    const messageCount = 3;
    const allMessagesPromise = new Promise<void>((resolve) => {
      ws.onmessage = (event) => {
        const data: MessagePayload = JSON.parse(event.data);
        messages.push(data.text);
        if (messages.length === messageCount) {
          resolve();
        }
      };
    });

    // Send multiple messages
    for (let i = 1; i <= messageCount; i++) {
      const response = await fetch(`${server.url}/messages`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: `Message ${i}` }),
      });
      await response.json();
    }

    await allMessagesPromise;

    assertEquals(messages.length, 3, "Should receive all 3 messages");
    assertEquals(messages[0], "Message 1", "First message should be correct");
    assertEquals(messages[1], "Message 2", "Second message should be correct");
    assertEquals(messages[2], "Message 3", "Third message should be correct");

    ws.close();
  } finally {
    await server.shutdown();
  }
});

Deno.test("POST to /messages with no connected clients succeeds", async () => {
  const server = await startTestServer(8013);

  try {
    const response = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "No one listening" }),
    });

    assertEquals(response.status, 200, "Should succeed even with no clients");

    const result: PostResponse = await response.json();
    assertEquals(result.success, true, "Should return success");
  } finally {
    await server.shutdown();
  }
});

Deno.test("GET /ws without upgrade header returns 426", async () => {
  const server = await startTestServer(8014);

  try {
    const response = await fetch(`${server.url}/ws`);

    assertEquals(response.status, 426, "Should return 426 Upgrade Required");

    const text = await response.text();
    assertMatch(text, /[Ww]eb[Ss]ocket/, "Should mention WebSocket");
  } finally {
    await server.shutdown();
  }
});

Deno.test("POST /messages accepts Unicode characters", async () => {
  const server = await startTestServer(8015);

  try {
    const ws = new WebSocket(`${server.wsUrl}/ws`);
    await new Promise((resolve) => ws.onopen = resolve);

    const unicodeText = "Hello 世界 🚀 Ñoño";
    const messagePromise = new Promise<string>((resolve) => {
      ws.onmessage = (event) => resolve(event.data);
    });

    const response = await fetch(`${server.url}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: unicodeText }),
    });

    const result: PostResponse = await response.json();
    assertEquals(result.success, true, "POST should succeed");

    const received = await messagePromise;
    const data: MessagePayload = JSON.parse(received);

    assertEquals(data.text, unicodeText, "Should handle Unicode correctly");

    ws.close();
  } finally {
    await server.shutdown();
  }
});
