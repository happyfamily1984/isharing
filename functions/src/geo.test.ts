import { test } from "node:test";
import assert from "node:assert/strict";
import { distanceMeters, normalizeDistanceKm, pairState, placeState } from "./geo";

test("distance between Gwacheon station and Seoul City Hall is about 15km", () => {
  const d = distanceMeters({ lat: 37.4337, lng: 126.9966 }, { lat: 37.5665, lng: 126.978 });
  assert.ok(d > 14000 && d < 15500, `got ${d}`);
});

test("first observation never notifies", () => {
  assert.deepEqual(placeState(undefined, 10, 100), { inside: true, transition: "none" });
  assert.deepEqual(pairState(undefined, 9000), { far: true, transition: "none" });
});

test("arriving at a place", () => {
  assert.equal(placeState(false, 80, 100).transition, "enter");
  assert.equal(placeState(false, 120, 100).transition, "none");
});

test("GPS jitter just outside the radius does not count as leaving", () => {
  assert.deepEqual(placeState(true, 130, 100), { inside: true, transition: "none" });
  assert.equal(placeState(true, 160, 100).transition, "exit");
});

test("5km far/near with hysteresis", () => {
  assert.equal(pairState(false, 5100).transition, "far");
  assert.equal(pairState(false, 4900).transition, "none");
  assert.deepEqual(pairState(true, 4900), { far: true, transition: "none" }); // 경계 근처는 유지
  assert.equal(pairState(true, 4600).transition, "near");
});

test("custom threshold", () => {
  assert.equal(pairState(false, 1100, 1).transition, "far");
  assert.equal(pairState(true, 900, 1).transition, "near");
  assert.equal(pairState(false, 9000, 10).transition, "none");
});

test("invalid distance setting falls back to 5km", () => {
  assert.equal(normalizeDistanceKm(7), 5);
  assert.equal(normalizeDistanceKm("3"), 5);
  assert.equal(normalizeDistanceKm(10), 10);
});
