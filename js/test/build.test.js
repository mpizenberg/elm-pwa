import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { generateSW } from "../src/build.js";

function fetchHandler({ networkOnlyPrefixes = [] } = {}) {
  const listeners = new Map();
  const shell = new Response("app shell");
  const network = new Response("network");

  vm.runInNewContext(
    generateSW({
      cacheName: "test",
      precacheUrls: ["/"],
      navigationFallback: "/",
      networkOnlyPrefixes,
    }),
    {
      URL,
      caches: {
        match: async () => shell,
        open: async () => ({
          addAll: async () => {},
          put: async () => {},
        }),
        keys: async () => [],
        delete: async () => true,
      },
      fetch: async () => network,
      self: {
        addEventListener(type, handler) {
          listeners.set(type, handler);
        },
      },
    },
  );

  return listeners.get("fetch");
}

async function navigate(path, options) {
  let response;
  fetchHandler(options)({
    request: {
      method: "GET",
      mode: "navigate",
      url: `https://example.test${path}`,
    },
    respondWith(value) {
      response = value;
    },
  });
  return response;
}

test("network-only prefixes take precedence over the navigation fallback", async () => {
  const response = await navigate("/server-page", {
    networkOnlyPrefixes: ["/server-page"],
  });

  assert.equal(await response.text(), "network");
});

test("other navigations continue to use the cached app shell", async () => {
  const response = await navigate("/app-route");

  assert.equal(await response.text(), "app shell");
});
