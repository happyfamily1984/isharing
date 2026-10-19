import { test } from "node:test";
import assert from "node:assert/strict";
import {
  distanceMeters,
  kstDay,
  normalizeDistanceKm,
  pairState,
  placeState,
  updateTogether,
} from "./geo";

test("distance between Gwacheon station and Seoul City Hall is about 15km", () => {
  const d = distanceMeters({ lat: 37.4337, lng: 126.9966 }, { lat: 37.5665, lng: 126.978 });
  assert.ok(d > 14000 && d < 15500, `got ${d}`);
});

test("first observation never notifies", () => {
  assert.deepEqual(placeState(undefined, 10, 100, 0, 5), { state: { inside: true, since: 5 }, transition: "none" });
  assert.deepEqual(pairState(undefined, 9000), { far: true, transition: "none" });
});

const MINUTE = 60 * 1000;
const away = { inside: false, since: 0 };
const home0 = { inside: true, since: 0 };

test("arriving at a place", () => {
  assert.equal(placeState(away, 80, 100, 10, 60 * MINUTE).transition, "enter");
  assert.equal(placeState(away, 120, 100, 10, 60 * MINUTE).transition, "none");
});

test("GPS jitter just outside the radius does not count as leaving", () => {
  assert.equal(placeState(home0, 350, 100, 10, MINUTE).state.inside, true); // 가까운 곳 다녀오기
  assert.equal(placeState(home0, 430, 100, 10, MINUTE).transition, "exit");
});

test("an inaccurate indoor fix far away does not count as leaving", () => {
  // 오차 200m 짜리 위치가 550m 떨어져 찍혀도 집 안으로 본다
  assert.equal(placeState(home0, 550, 100, 200, MINUTE).state.inside, true);
});

test("coming back soon after leaving does not notify again", () => {
  const left = placeState(home0, 800, 100, 10, 60 * MINUTE).state; // 나감
  const back = placeState(left, 20, 100, 10, 70 * MINUTE); // 10분 만에 돌아옴
  assert.equal(back.transition, "none");
  assert.equal(back.state.inside, true);
  const later = placeState(left, 20, 100, 10, 80 * MINUTE); // 20분 뒤 돌아옴
  assert.equal(later.transition, "enter");
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

const MIN = 60 * 1000;
const t0 = Date.UTC(2026, 9, 17, 3, 0); // 한국 시간 12:00
const home = { lat: 37.43, lng: 127.0 };
const cafe = { lat: 37.44, lng: 127.01 }; // 약 1.4km 떨어진 곳

test("time together accumulates only while together", () => {
  let s = updateTogether(undefined, 50, t0, home); // 처음: 함께 있음, 아직 시간 없음
  assert.deepEqual(s.days, {});
  s = updateTogether(s, 60, t0 + 5 * MIN, home);
  s = updateTogether(s, 150, t0 + 10 * MIN, home); // 150m: 아직 함께(200m 전까지)
  assert.equal(s.days["2026-10-17"], 10 * 60);
  s = updateTogether(s, 500, t0 + 15 * MIN, home); // 떨어짐 (직전까지 함께였으니 5분 추가)
  assert.equal(s.together, false);
  s = updateTogether(s, 500, t0 + 20 * MIN, home); // 떨어져 있는 동안은 안 셈
  assert.equal(s.days["2026-10-17"], 15 * 60);
  assert.equal(s.sessions.length, 1);
  assert.deepEqual(
    { start: s.sessions[0].start, end: s.sessions[0].end, lat: s.sessions[0].lat },
    { start: t0, end: t0 + 15 * MIN, lat: home.lat },
  );
});

test("separate meetings at different places become separate sessions", () => {
  let s = updateTogether(undefined, 10, t0, home);
  s = updateTogether(s, 10, t0 + 5 * MIN, home);
  s = updateTogether(s, 3000, t0 + 10 * MIN, home); // 헤어짐
  s = updateTogether(s, 3000, t0 + 60 * MIN, home);
  s = updateTogether(s, 20, t0 + 65 * MIN, cafe); // 카페에서 다시 만남
  s = updateTogether(s, 20, t0 + 70 * MIN, cafe);
  assert.equal(s.sessions.length, 2);
  assert.equal(s.sessions[1].lat, cafe.lat);
  assert.equal(s.sessions[1].end - s.sessions[1].start, 5 * MIN);
});

test("a brief GPS separation at the same place stays one session", () => {
  let s = updateTogether(undefined, 10, t0, home);
  s = updateTogether(s, 10, t0 + 5 * MIN, home);
  s = updateTogether(s, 300, t0 + 7 * MIN, home); // 잠깐 튐
  s = updateTogether(s, 10, t0 + 9 * MIN, home);
  s = updateTogether(s, 10, t0 + 14 * MIN, home);
  assert.equal(s.sessions.length, 1);
  assert.equal(s.sessions[0].end, t0 + 14 * MIN);
});

test("long gaps (phones off) are not counted", () => {
  let s = updateTogether(undefined, 10, t0, home);
  s = updateTogether(s, 10, t0 + 60 * MIN, home);
  assert.deepEqual(s.days, {});
  assert.equal(s.sessions.length, 2); // 끊긴 뒤 새 기록
});

test("days use Korean date and old records are dropped", () => {
  assert.equal(kstDay(Date.UTC(2026, 9, 17, 15, 30)), "2026-10-18"); // 한국 00:30
  const old = { start: Date.UTC(2026, 7, 1), end: Date.UTC(2026, 7, 1), lat: 0, lng: 0 };
  const s = updateTogether(
    { together: false, lastAt: t0, days: { "2026-08-01": 100 }, sessions: [old] },
    500,
    t0,
    home,
  );
  assert.deepEqual(s.days, {});
  assert.deepEqual(s.sessions, []);
});
