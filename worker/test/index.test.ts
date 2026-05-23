import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";

// A fully-populated test env. Each route only reads the keys it needs, but
// we pass them all so individual tests don't have to construct their own.
const testEnv = {
  ANTHROPIC_API_KEY: "test-anthropic-key",
  ELEVENLABS_API_KEY: "test-elevenlabs-key",
  ELEVENLABS_VOICE_ID: "test-voice-id-xyz",
  ASSEMBLYAI_API_KEY: "test-assemblyai-key",
};

// Convenience: build a Request the way Cloudflare delivers one to the Worker.
function buildRequest(
  path: string,
  init: RequestInit = { method: "POST" }
): Request {
  return new Request(`https://proxy.example.com${path}`, init);
}

// Convenience: pull the (url, init) the Worker passed to its `fetch` call.
function lastFetchCall(fetchMock: ReturnType<typeof vi.fn>): {
  url: string;
  init: RequestInit;
} {
  const call = fetchMock.mock.calls[0];
  if (!call) {
    throw new Error("fetch mock was never called");
  }
  return { url: String(call[0]), init: (call[1] as RequestInit) ?? {} };
}

// Headers may arrive as a plain object or a `Headers` instance — normalize.
function headerValue(init: RequestInit, name: string): string | null {
  const rawHeaders = init.headers;
  if (!rawHeaders) return null;
  if (rawHeaders instanceof Headers) {
    return rawHeaders.get(name);
  }
  const lowerName = name.toLowerCase();
  for (const [key, value] of Object.entries(
    rawHeaders as Record<string, string>
  )) {
    if (key.toLowerCase() === lowerName) {
      return value;
    }
  }
  return null;
}

describe("Clicky Proxy Worker", () => {
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    // Silence the Worker's console.error so the test output stays clean —
    // we still assert behaviour, just not the log line itself.
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  describe("POST /chat", () => {
    it("happy path: 200 with body forwarded and event-stream content-type", async () => {
      const upstreamBody = "event: message_start\ndata: {}\n\n";
      fetchMock.mockResolvedValueOnce(
        new Response(upstreamBody, {
          status: 200,
          headers: { "content-type": "text/event-stream" },
        })
      );

      const requestBody = JSON.stringify({ model: "claude", messages: [] });
      const response = await worker.fetch(
        buildRequest("/chat", { method: "POST", body: requestBody }),
        testEnv
      );

      expect(response.status).toBe(200);
      expect(response.headers.get("content-type")).toContain("event-stream");
      expect(await response.text()).toBe(upstreamBody);
    });

    it("forwards x-api-key and anthropic-version headers upstream", async () => {
      fetchMock.mockResolvedValueOnce(
        new Response("ok", {
          status: 200,
          headers: { "content-type": "text/event-stream" },
        })
      );

      await worker.fetch(
        buildRequest("/chat", { method: "POST", body: "{}" }),
        testEnv
      );

      const { url, init } = lastFetchCall(fetchMock);
      expect(url).toBe("https://api.anthropic.com/v1/messages");
      expect(init.method).toBe("POST");
      expect(headerValue(init, "x-api-key")).toBe(testEnv.ANTHROPIC_API_KEY);
      expect(headerValue(init, "anthropic-version")).toBe("2023-06-01");
      expect(headerValue(init, "content-type")).toBe("application/json");
    });

    it("forwards request body verbatim with no transformation", async () => {
      fetchMock.mockResolvedValueOnce(
        new Response("ok", { status: 200 })
      );

      const requestBody = JSON.stringify({
        model: "claude-sonnet-4-6",
        messages: [{ role: "user", content: "hello" }],
        stream: true,
      });

      await worker.fetch(
        buildRequest("/chat", { method: "POST", body: requestBody }),
        testEnv
      );

      const { init } = lastFetchCall(fetchMock);
      expect(init.body).toBe(requestBody);
    });

    it("forwards Anthropic 429 status and body verbatim", async () => {
      const upstreamError = JSON.stringify({
        type: "error",
        error: { type: "rate_limit_error", message: "slow down" },
      });
      fetchMock.mockResolvedValueOnce(
        new Response(upstreamError, {
          status: 429,
          headers: { "content-type": "application/json" },
        })
      );

      const response = await worker.fetch(
        buildRequest("/chat", { method: "POST", body: "{}" }),
        testEnv
      );

      expect(response.status).toBe(429);
      expect(await response.text()).toBe(upstreamError);
    });

    it("forwards Anthropic 500 status and body verbatim", async () => {
      const upstreamError = JSON.stringify({
        type: "error",
        error: { type: "api_error", message: "boom" },
      });
      fetchMock.mockResolvedValueOnce(
        new Response(upstreamError, {
          status: 500,
          headers: { "content-type": "application/json" },
        })
      );

      const response = await worker.fetch(
        buildRequest("/chat", { method: "POST", body: "{}" }),
        testEnv
      );

      expect(response.status).toBe(500);
      expect(await response.text()).toBe(upstreamError);
    });
  });

  describe("POST /tts", () => {
    it("happy path: 200 with audio/mpeg body forwarded", async () => {
      const audioBytes = new Uint8Array([0xff, 0xfb, 0x90, 0x00]);
      fetchMock.mockResolvedValueOnce(
        new Response(audioBytes, {
          status: 200,
          headers: { "content-type": "audio/mpeg" },
        })
      );

      const response = await worker.fetch(
        buildRequest("/tts", {
          method: "POST",
          body: JSON.stringify({ text: "hi" }),
        }),
        testEnv
      );

      expect(response.status).toBe(200);
      expect(response.headers.get("content-type")).toBe("audio/mpeg");
      const responseBytes = new Uint8Array(await response.arrayBuffer());
      expect(Array.from(responseBytes)).toEqual(Array.from(audioBytes));
    });

    it("injects the voice ID from env into the upstream URL", async () => {
      fetchMock.mockResolvedValueOnce(
        new Response(new Uint8Array(), { status: 200 })
      );

      await worker.fetch(
        buildRequest("/tts", { method: "POST", body: "{}" }),
        testEnv
      );

      const { url } = lastFetchCall(fetchMock);
      expect(url).toBe(
        `https://api.elevenlabs.io/v1/text-to-speech/${testEnv.ELEVENLABS_VOICE_ID}`
      );
    });

    it("forwards ElevenLabs 401 status and body verbatim", async () => {
      const upstreamError = JSON.stringify({
        detail: { status: "unauthorized" },
      });
      fetchMock.mockResolvedValueOnce(
        new Response(upstreamError, {
          status: 401,
          headers: { "content-type": "application/json" },
        })
      );

      const response = await worker.fetch(
        buildRequest("/tts", { method: "POST", body: "{}" }),
        testEnv
      );

      expect(response.status).toBe(401);
      expect(await response.text()).toBe(upstreamError);
    });

    it("forwards xi-api-key, accept, and content-type headers upstream", async () => {
      fetchMock.mockResolvedValueOnce(
        new Response(new Uint8Array(), { status: 200 })
      );

      await worker.fetch(
        buildRequest("/tts", { method: "POST", body: "{}" }),
        testEnv
      );

      const { init } = lastFetchCall(fetchMock);
      expect(init.method).toBe("POST");
      expect(headerValue(init, "xi-api-key")).toBe(testEnv.ELEVENLABS_API_KEY);
      expect(headerValue(init, "accept")).toBe("audio/mpeg");
      expect(headerValue(init, "content-type")).toBe("application/json");
    });
  });

  describe("POST /transcribe-token", () => {
    it("happy path: returns upstream token JSON verbatim as application/json", async () => {
      const upstreamJson = JSON.stringify({
        token: "asm-temp-token-abc",
        expires_in_seconds: 480,
      });
      fetchMock.mockResolvedValueOnce(
        new Response(upstreamJson, {
          status: 200,
          headers: { "content-type": "application/json" },
        })
      );

      const response = await worker.fetch(
        buildRequest("/transcribe-token", { method: "POST" }),
        testEnv
      );

      expect(response.status).toBe(200);
      expect(response.headers.get("content-type")).toBe("application/json");
      expect(await response.text()).toBe(upstreamJson);
    });

    it("calls AssemblyAI upstream with GET, not POST", async () => {
      fetchMock.mockResolvedValueOnce(
        new Response("{}", {
          status: 200,
          headers: { "content-type": "application/json" },
        })
      );

      await worker.fetch(
        buildRequest("/transcribe-token", { method: "POST" }),
        testEnv
      );

      const { init } = lastFetchCall(fetchMock);
      expect(init.method).toBe("GET");
    });

    it("sets authorization header to the raw AssemblyAI key (no Bearer prefix)", async () => {
      fetchMock.mockResolvedValueOnce(
        new Response("{}", {
          status: 200,
          headers: { "content-type": "application/json" },
        })
      );

      await worker.fetch(
        buildRequest("/transcribe-token", { method: "POST" }),
        testEnv
      );

      const { init } = lastFetchCall(fetchMock);
      const authHeader = headerValue(init, "authorization");
      expect(authHeader).toBe(testEnv.ASSEMBLYAI_API_KEY);
      expect(authHeader).not.toMatch(/^Bearer\s/i);
    });

    it("includes expires_in_seconds=480 in the upstream URL", async () => {
      fetchMock.mockResolvedValueOnce(
        new Response("{}", {
          status: 200,
          headers: { "content-type": "application/json" },
        })
      );

      await worker.fetch(
        buildRequest("/transcribe-token", { method: "POST" }),
        testEnv
      );

      const { url } = lastFetchCall(fetchMock);
      expect(url).toContain("streaming.assemblyai.com/v3/token");
      expect(url).toContain("expires_in_seconds=480");
    });

    it("forwards AssemblyAI 403 status and body verbatim", async () => {
      const upstreamError = JSON.stringify({ error: "forbidden" });
      fetchMock.mockResolvedValueOnce(
        new Response(upstreamError, {
          status: 403,
          headers: { "content-type": "application/json" },
        })
      );

      const response = await worker.fetch(
        buildRequest("/transcribe-token", { method: "POST" }),
        testEnv
      );

      expect(response.status).toBe(403);
      expect(await response.text()).toBe(upstreamError);
    });
  });

  describe("Method and route fallbacks", () => {
    it("GET /chat returns 405 Method not allowed", async () => {
      const response = await worker.fetch(
        buildRequest("/chat", { method: "GET" }),
        testEnv
      );

      expect(response.status).toBe(405);
      expect(await response.text()).toBe("Method not allowed");
      expect(fetchMock).not.toHaveBeenCalled();
    });

    it("POST /unknown-route returns 404 Not found", async () => {
      const response = await worker.fetch(
        buildRequest("/unknown-route", { method: "POST", body: "" }),
        testEnv
      );

      expect(response.status).toBe(404);
      expect(await response.text()).toBe("Not found");
      expect(fetchMock).not.toHaveBeenCalled();
    });

    it("returns 500 with JSON error envelope when the upstream fetch throws", async () => {
      fetchMock.mockRejectedValueOnce(new Error("network exploded"));

      const response = await worker.fetch(
        buildRequest("/chat", { method: "POST", body: "{}" }),
        testEnv
      );

      expect(response.status).toBe(500);
      expect(response.headers.get("content-type")).toBe("application/json");
      const errorPayload = (await response.json()) as { error: string };
      expect(errorPayload.error).toContain("network exploded");
    });
  });
});
