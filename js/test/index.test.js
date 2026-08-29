import assert from "node:assert/strict";
import test from "node:test";
import { observeServiceWorkerUpdates } from "../src/index.js";

function worker(initialState = "installing") {
  const listeners = new Map();
  return {
    state: initialState,
    addEventListener(type, listener) {
      listeners.set(type, listener);
    },
    moveTo(state) {
      this.state = state;
      listeners.get("statechange")?.();
    },
  };
}

function registration(overrides = {}) {
  const listeners = new Map();
  return {
    active: null,
    waiting: null,
    installing: null,
    ...overrides,
    addEventListener(type, listener) {
      listeners.set(type, listener);
    },
    updateFound() {
      listeners.get("updatefound")?.();
    },
  };
}

test("announces a worker that was already waiting", () => {
  const waiting = worker("installed");
  const reg = registration({ active: worker("activated"), waiting });
  let announcements = 0;

  observeServiceWorkerUpdates(reg, () => announcements++);

  assert.equal(announcements, 1);
});

test("announces an update when a forced reload has no controller", () => {
  const installing = worker();
  const reg = registration({ active: worker("activated"), installing });
  let announcements = 0;

  observeServiceWorkerUpdates(reg, () => announcements++);
  installing.moveTo("installed");

  assert.equal(announcements, 1);
});

test("does not announce the first service-worker install", () => {
  const installing = worker();
  const reg = registration({ installing });
  let announcements = 0;

  observeServiceWorkerUpdates(reg, () => announcements++);
  installing.moveTo("installed");

  assert.equal(announcements, 0);
});

test("observes an update found after registration resolved", () => {
  const reg = registration({ active: worker("activated") });
  let announcements = 0;

  observeServiceWorkerUpdates(reg, () => announcements++);
  const installing = worker();
  reg.installing = installing;
  reg.updateFound();
  installing.moveTo("installed");

  assert.equal(announcements, 1);
});
