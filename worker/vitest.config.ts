import { defineConfig } from "vitest/config";

// Plain Node test environment is sufficient — every test stubs `fetch`
// via `vi.stubGlobal` so the Worker never touches a real upstream and
// we don't need the heavier Cloudflare Workers test runtime.
export default defineConfig({
  test: {
    environment: "node",
    include: ["test/**/*.test.ts"],
    globals: false,
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
      include: ["src/**/*.ts"],
    },
  },
});
