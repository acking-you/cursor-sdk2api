import { afterEach, expect, test } from "vitest";
import { api, closeTestApp, startTestApp, type TestContext } from "../helpers/app.js";

let ctx: TestContext | undefined;

afterEach(async () => {
  if (ctx) await closeTestApp(ctx);
  ctx = undefined;
});

test("managed mode returns the gateway key so the console can render client recipes", async () => {
  ctx = await startTestApp({
    config: { authMode: "managed", gatewayAccessKey: "gateway-key", managedCursorKey: undefined },
  });

  const res = await api(ctx, "/v0/management/gateway-key", { method: "GET" });

  expect(res.status).toBe(200);
  expect(await res.json()).toEqual({ auth_mode: "managed", gateway_access_key: "gateway-key" });
});

test("byok mode never returns a key because each client presents its own Cursor credential", async () => {
  ctx = await startTestApp({ config: { authMode: "byok" } });

  const res = await api(ctx, "/v0/management/gateway-key", { method: "GET" });

  expect(res.status).toBe(200);
  expect(await res.json()).toEqual({ auth_mode: "byok", gateway_access_key: null });
});

test("the gateway key endpoint never discloses a pooled Cursor credential", async () => {
  const cursorKey = "sk-cursor-CANARY-987654321";
  ctx = await startTestApp({
    config: { authMode: "managed", gatewayAccessKey: "gateway-key", managedCursorKey: undefined },
  });
  await api(ctx, "/v0/management/accounts", {
    method: "POST",
    body: JSON.stringify({ api_key: cursorKey }),
  });

  const raw = await (await api(ctx, "/v0/management/gateway-key", { method: "GET" })).text();

  expect(raw).not.toContain(cursorKey);
});

test("only GET is routed, so the key cannot be changed over HTTP", async () => {
  ctx = await startTestApp({
    config: { authMode: "managed", gatewayAccessKey: "gateway-key", managedCursorKey: undefined },
  });

  const res = await api(ctx, "/v0/management/gateway-key", {
    method: "POST",
    body: JSON.stringify({ gateway_access_key: "attacker-key" }),
  });

  expect(res.status).toBe(404);
});
