import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging, Message } from "firebase-admin/messaging";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2";
import {
  LatLng,
  MAX_ACCURACY_M,
  distanceMeters,
  normalizeDistanceKm,
  pairState,
  placeState,
  PlaceMemo,
  TogetherState,
  updateTogether,
  watchKey,
} from "./geo";

initializeApp();
setGlobalOptions({ region: "asia-northeast3" }); // 서울

const db = getFirestore();

const INVITE_TTL_MS = 48 * 60 * 60 * 1000; // 초대코드 유효기간 48시간
// 요금제별 제한. 결제 연동 시 groups/{id}.plan 을 서버(결제 검증 함수)에서만 'premium'으로 바꾼다.
// 클라이언트 앱의 lib/services/plan.dart 와 값을 맞춘다.
type Plan = "free" | "premium";
const PLAN_LIMITS: Record<Plan, { maxMembers: number; historyDays: number }> = {
  free: { maxMembers: 6, historyDays: 2 },
  premium: { maxMembers: 20, historyDays: 30 },
};
const HISTORY_RETENTION_DAYS = PLAN_LIMITS.premium.historyDays; // 서버 최대 보관 기간

function maxMembers(group: FirebaseFirestore.DocumentSnapshot): number {
  return PLAN_LIMITS[(group.get("plan") as Plan) ?? "free"]?.maxMembers ?? PLAN_LIMITS.free.maxMembers;
}
// 혼동되기 쉬운 문자(0/O, 1/I/L) 제외
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

function requireAuth(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  return req.auth.uid;
}

function randomCode(len = 6): string {
  let s = "";
  for (let i = 0; i < len; i++) {
    s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return s;
}

/** 사용되지 않는 초대코드를 만들어 inviteCodes 컬렉션에 예약한다. */
async function issueInviteCode(groupId: string): Promise<{ code: string; expiresAt: Timestamp }> {
  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_TTL_MS);
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = randomCode();
    const ref = db.collection("inviteCodes").doc(code);
    const ok = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists && (snap.get("expiresAt") as Timestamp).toMillis() > Date.now()) return false;
      tx.set(ref, { groupId, expiresAt });
      return true;
    });
    if (ok) return { code, expiresAt };
  }
  throw new HttpsError("resource-exhausted", "초대코드 생성에 실패했습니다. 다시 시도해주세요.");
}

async function getGroupOrThrow(groupId: string) {
  const snap = await db.collection("groups").doc(groupId).get();
  if (!snap.exists) throw new HttpsError("not-found", "그룹을 찾을 수 없습니다.");
  return snap;
}

// ---------------------------------------------------------------------------
// 그룹 관리
// ---------------------------------------------------------------------------

export const createGroup = onCall(async (req) => {
  const uid = requireAuth(req);
  const name = String(req.data?.name ?? "").trim();
  if (!name || name.length > 30) throw new HttpsError("invalid-argument", "그룹 이름은 1~30자여야 합니다.");

  const groupRef = db.collection("groups").doc();
  const { code, expiresAt } = await issueInviteCode(groupRef.id);
  await groupRef.set({
    name,
    ownerId: uid,
    members: [uid],
    plan: "free",
    inviteCode: code,
    inviteExpiresAt: expiresAt,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { groupId: groupRef.id, inviteCode: code };
});

/** 방장이 초대코드를 새로 발급한다. 기존 코드는 즉시 무효화된다. */
export const regenerateInvite = onCall(async (req) => {
  const uid = requireAuth(req);
  const groupId = String(req.data?.groupId ?? "");
  const group = await getGroupOrThrow(groupId);
  if (group.get("ownerId") !== uid) throw new HttpsError("permission-denied", "방장만 할 수 있습니다.");

  const oldCode = group.get("inviteCode") as string | undefined;
  const { code, expiresAt } = await issueInviteCode(groupId);
  await group.ref.update({ inviteCode: code, inviteExpiresAt: expiresAt });
  if (oldCode) await db.collection("inviteCodes").doc(oldCode).delete();
  return { inviteCode: code };
});

/**
 * 초대코드로 가입 "요청"을 보낸다. 방장이 승인해야 실제 멤버가 되고 위치 공유가 시작된다.
 * 코드가 유출되더라도 모르는 사람이 바로 위치를 볼 수 없도록 하기 위함.
 */
export const requestJoin = onCall(async (req) => {
  const uid = requireAuth(req);
  const code = String(req.data?.code ?? "").trim().toUpperCase();
  const codeSnap = await db.collection("inviteCodes").doc(code).get();
  if (!codeSnap.exists || (codeSnap.get("expiresAt") as Timestamp).toMillis() < Date.now()) {
    throw new HttpsError("not-found", "유효하지 않거나 만료된 초대코드입니다.");
  }
  const groupId = codeSnap.get("groupId") as string;
  const group = await getGroupOrThrow(groupId);
  const members = group.get("members") as string[];
  if (members.includes(uid)) throw new HttpsError("already-exists", "이미 가입된 그룹입니다.");
  if (members.length >= maxMembers(group)) throw new HttpsError("resource-exhausted", "그룹 인원이 가득 찼습니다.");

  const user = await db.collection("users").doc(uid).get();
  await group.ref.collection("requests").doc(uid).set({
    displayName: user.get("displayName") ?? "이름 없음",
    createdAt: FieldValue.serverTimestamp(),
  });

  // 방장에게 알림
  const owner = await db.collection("users").doc(group.get("ownerId")).get();
  const token = owner.get("fcmToken") as string | undefined;
  if (token) {
    await getMessaging()
      .send({
        token,
        notification: {
          title: "새 가입 요청",
          body: `${user.get("displayName") ?? "누군가"}님이 '${group.get("name")}' 그룹 가입을 요청했어요.`,
        },
        data: { type: "join_request", groupId },
      })
      .catch(() => undefined);
  }
  return { groupId, groupName: group.get("name") };
});

/** 방장이 가입 요청을 승인/거절한다. */
export const respondJoin = onCall(async (req) => {
  const uid = requireAuth(req);
  const groupId = String(req.data?.groupId ?? "");
  const targetUid = String(req.data?.uid ?? "");
  const approve = req.data?.approve === true;

  const groupRef = db.collection("groups").doc(groupId);
  await db.runTransaction(async (tx) => {
    const group = await tx.get(groupRef);
    if (!group.exists) throw new HttpsError("not-found", "그룹을 찾을 수 없습니다.");
    if (group.get("ownerId") !== uid) throw new HttpsError("permission-denied", "방장만 할 수 있습니다.");
    const reqRef = groupRef.collection("requests").doc(targetUid);
    const reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) throw new HttpsError("not-found", "가입 요청이 없습니다.");
    if (approve) {
      if ((group.get("members") as string[]).length >= maxMembers(group)) {
        throw new HttpsError("resource-exhausted", "그룹 인원이 가득 찼습니다.");
      }
      tx.update(groupRef, { members: FieldValue.arrayUnion(targetUid) });
    }
    tx.delete(reqRef);
  });
  return { ok: true };
});

async function removeFromGroup(groupId: string, targetUid: string) {
  const groupRef = db.collection("groups").doc(groupId);
  let deletedCode: string | undefined;
  await db.runTransaction(async (tx) => {
    const group = await tx.get(groupRef);
    if (!group.exists) return;
    const remaining = (group.get("members") as string[]).filter((m) => m !== targetUid);
    if (remaining.length === 0) {
      deletedCode = group.get("inviteCode");
      tx.delete(groupRef);
      return;
    }
    const update: Record<string, unknown> = { members: remaining };
    // 방장이 나가면 가장 먼저 가입한 남은 멤버에게 방장 위임
    if (group.get("ownerId") === targetUid) update.ownerId = remaining[0];
    tx.update(groupRef, update);
  });
  if (deletedCode) {
    await db.collection("inviteCodes").doc(deletedCode).delete();
    await db.recursiveDelete(groupRef); // 남은 장소·가입요청 정리
  }
}

export const leaveGroup = onCall(async (req) => {
  const uid = requireAuth(req);
  await removeFromGroup(String(req.data?.groupId ?? ""), uid);
  return { ok: true };
});

/** 방장이 멤버를 내보낸다. */
export const removeMember = onCall(async (req) => {
  const uid = requireAuth(req);
  const groupId = String(req.data?.groupId ?? "");
  const targetUid = String(req.data?.uid ?? "");
  const group = await getGroupOrThrow(groupId);
  if (group.get("ownerId") !== uid) throw new HttpsError("permission-denied", "방장만 할 수 있습니다.");
  if (targetUid === uid) throw new HttpsError("invalid-argument", "자기 자신은 '그룹 나가기'를 이용하세요.");
  await removeFromGroup(groupId, targetUid);
  return { ok: true };
});

/** 회원 탈퇴: 모든 그룹에서 나가고 위치 기록을 포함한 내 데이터를 삭제한다. */
export const deleteMyData = onCall(async (req) => {
  const uid = requireAuth(req);
  const groups = await db.collection("groups").where("members", "array-contains", uid).get();
  for (const g of groups.docs) await removeFromGroup(g.id, uid);
  await db.recursiveDelete(db.collection("users").doc(uid));
  // 위치 알림 상태 정리
  await db.collection("geoState").doc(uid).delete();
  const watches = await Promise.all([
    db.collection("distState").where("viewer", "==", uid).get(),
    db.collection("distState").where("target", "==", uid).get(),
    db.collection("together").where("members", "array-contains", uid).get(),
  ]);
  const batch = db.batch();
  watches.flatMap((q) => q.docs).forEach((d) => batch.delete(d.ref));
  await batch.commit();
  return { ok: true };
});

// ---------------------------------------------------------------------------
// 열람 권한(viewers) 동기화
// 그룹 멤버십이 바뀔 때마다 각 사용자의 users/{uid}.viewers 를 다시 계산한다.
// 보안 규칙은 이 viewers 목록으로 위치 열람을 허용한다.
// ---------------------------------------------------------------------------

async function recomputeViewers(uid: string) {
  const groups = await db.collection("groups").where("members", "array-contains", uid).get();
  const viewers = new Set<string>();
  for (const g of groups.docs) for (const m of g.get("members") as string[]) if (m !== uid) viewers.add(m);
  const userRef = db.collection("users").doc(uid);
  // 탈퇴(deleteMyData)로 지워진 사용자 문서를 다시 만들지 않는다.
  if (groups.empty && !(await userRef.get()).exists) return;
  await userRef.set(
    { viewers: [...viewers], groupIds: groups.docs.map((g) => g.id) },
    { merge: true },
  );
}

export const onGroupWritten = onDocumentWritten("groups/{groupId}", async (event) => {
  const before = (event.data?.before.get("members") as string[] | undefined) ?? [];
  const after = (event.data?.after.get("members") as string[] | undefined) ?? [];
  const affected = new Set([...before, ...after]);
  await Promise.all([...affected].map(recomputeViewers));
});

// ---------------------------------------------------------------------------
// 벨 울리기
// ---------------------------------------------------------------------------

export const ringDevice = onCall(async (req) => {
  const uid = requireAuth(req);
  const targetUid = String(req.data?.targetUid ?? "");
  const target = await db.collection("users").doc(targetUid).get();
  const isSelf = targetUid === uid;
  if (!target.exists || (!isSelf && !((target.get("viewers") as string[] | undefined) ?? []).includes(uid))) {
    throw new HttpsError("permission-denied", "같은 그룹 멤버에게만 벨을 울릴 수 있습니다.");
  }
  const token = target.get("fcmToken") as string | undefined;
  if (!token) throw new HttpsError("failed-precondition", "상대방 기기가 아직 알림을 등록하지 않았습니다.");

  const me = await db.collection("users").doc(uid).get();
  const fromName = (me.get("displayName") as string) ?? "그룹 멤버";

  await getMessaging().send({
    token,
    // Android: data-only + high priority → 네이티브 RingReceiver가 무음 모드여도 알람 볼륨으로 재생
    data: { type: "ring", fromName },
    android: { priority: "high", ttl: 60 * 1000 },
    // iOS: 무음 모드를 무시하려면 Apple의 Critical Alerts 권한(entitlement)이 필요하다.
    apns: {
      headers: { "apns-priority": "10", "apns-push-type": "alert" },
      payload: {
        aps: {
          alert: { title: "휴대폰 찾기", body: `${fromName}님이 벨을 울리고 있어요` },
          sound: { critical: true, name: "default", volume: 1.0 },
          "interruption-level": "critical",
        },
      },
    },
  });
  await db.collection("users").doc(targetUid).collection("rings").add({
    from: uid,
    fromName,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// 실시간 보기: 누군가 지도를 보고 있는 동안 가족 폰이 2~3초마다 위치를 올린다
// ---------------------------------------------------------------------------

/** 신호 한 번에 빠르게 올리는 시간 (앱은 보는 동안 1분마다 다시 보낸다) */
const LIVE_SECONDS = 90;
/** 같은 사람이 이보다 자주 요청하면 무시한다 */
const LIVE_MIN_INTERVAL_MS = 40 * 1000;

export const requestLive = onCall(async (req) => {
  const uid = requireAuth(req);
  const ref = db.collection("liveRequests").doc(uid);
  const fresh = await db.runTransaction(async (tx) => {
    const last = (await tx.get(ref)).get("at") as Timestamp | undefined;
    if (last && Date.now() - last.toMillis() < LIVE_MIN_INTERVAL_MS) return false;
    tx.set(ref, { at: FieldValue.serverTimestamp() });
    return true;
  });
  if (!fresh) return { ok: true, sent: 0 };

  // 내가 볼 수 있는 사람들 = viewers 에 내가 들어 있는 사람들
  const targets = await db.collection("users").where("viewers", "array-contains", uid).get();
  const tokens = targets.docs
    .filter((d) => d.id !== uid && d.get("sharing") !== false)
    .map((d) => d.get("fcmToken") as string | undefined)
    .filter((t): t is string => !!t);
  if (tokens.length === 0) return { ok: true, sent: 0 };
  // data 전용 + 높은 우선순위: 앱이 꺼져 있어도 Android 위치 서비스가 받는다 (예전 버전 앱은 무시)
  await getMessaging()
    .sendEach(
      tokens.map((token) => ({
        token,
        data: { type: "live", seconds: String(LIVE_SECONDS) },
        android: { priority: "high" as const, ttl: 60 * 1000 },
      })),
    )
    .catch((e) => console.warn("live request failed", e));
  return { ok: true, sent: tokens.length };
});

// ---------------------------------------------------------------------------
// 오래된 이동경로 정리 (개인정보 최소 보관)
// ---------------------------------------------------------------------------

export const cleanupOldLocations = onSchedule({ schedule: "every day 04:00", timeZone: "Asia/Seoul" }, async () => {
  const cutoff = Timestamp.fromMillis(Date.now() - HISTORY_RETENTION_DAYS * 24 * 60 * 60 * 1000);
  for (;;) {
    const old = await db.collectionGroup("locations").where("ts", "<", cutoff).limit(400).get();
    if (old.empty) break;
    const batch = db.batch();
    old.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  const expired = await db.collection("inviteCodes").where("expiresAt", "<", Timestamp.now()).limit(400).get();
  const batch = db.batch();
  expired.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
});

// ---------------------------------------------------------------------------
// 위치 알림: 장소 도착, 가족과의 거리
// 위치가 바뀔 때마다 서버에서 판단하므로 앱이 꺼져 있어도 동작한다.
// 각자 설정(users/{uid}.alertPlaces / alertDistance / alertDistanceKm)을 따른다.
// ---------------------------------------------------------------------------

type UserData = FirebaseFirestore.DocumentData;

/** 이보다 오래된 위치는 거리 비교에 쓰지 않는다 (전원 꺼짐 등) */
const STALE_LOCATION_MS = 30 * 60 * 1000;

/**
 * 알림 보내기.
 * [autoDismissMs] 를 주면 Android 에서는 앱(RingReceiver)이 직접 알림을 띄우고 그 시간이 지나면
 * 알림창에서 저절로 사라진다 (data 전용 메시지). iOS 는 일반 알림으로 보낸다.
 */
async function notify(
  user: UserData | undefined,
  title: string,
  body: string,
  type: string,
  autoDismissMs?: number,
) {
  const token = user?.fcmToken as string | undefined;
  if (!token) return;
  const message: Message = autoDismissMs
    ? {
        token,
        data: { type, title, body, timeoutMs: String(autoDismissMs) },
        android: { priority: "high", ttl: autoDismissMs },
        apns: { payload: { aps: { alert: { title, body }, sound: "default" } } },
      }
    : {
        token,
        notification: { title, body },
        data: { type },
        android: { priority: "high", notification: { channelId: "general" } },
        apns: { payload: { aps: { sound: "default" } } },
      };
  await getMessaging()
    .send(message)
    .catch((e) => console.warn("notify failed", e));
}

/** 거리 알림은 알림창에 이만큼만 떠 있다가 사라진다 */
const DISTANCE_ALERT_DISMISS_MS = 15 * 1000;

function displayName(user: UserData | undefined): string {
  return (user?.displayName as string | undefined) || "가족";
}

export const onLocationChanged = onDocumentUpdated("users/{uid}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  const loc = after?.lastLocation as (LatLng & { accuracy?: number }) | undefined;
  const prev = before?.lastLocation as LatLng | undefined;
  if (!after || !loc) return;
  if (prev && prev.lat === loc.lat && prev.lng === loc.lng) return; // 위치 외 변경
  if (after.sharing === false) return;
  if ((loc.accuracy ?? 0) > MAX_ACCURACY_M) return;
  // 실시간 보기 중 2~3초마다 오는 위치는 지도 표시용이라 알림 계산은 15초마다 오는 위치로만 한다
  if (after.liveOnly === true) return;

  const uid = event.params.uid;
  await Promise.all([
    checkPlaces(uid, after, loc),
    checkDistances(uid, after, loc),
  ]);
});

/** 그룹에 등록된 장소에 도착했는지 확인하고, 같은 그룹의 다른 가족에게 알린다. */
async function checkPlaces(uid: string, me: UserData, loc: LatLng & { accuracy?: number }) {
  const groupIds = (me.groupIds as string[] | undefined) ?? [];
  if (groupIds.length === 0) return;

  // 위치가 연달아 올라와도 같은 도착을 두 번 알리지 않도록 트랜잭션으로 상태를 읽고 쓴다.
  const groups = await Promise.all(
    groupIds.map(async (gid) => {
      const groupRef = db.collection("groups").doc(gid);
      const [group, places] = await Promise.all([groupRef.get(), groupRef.collection("places").get()]);
      return { gid, group, places };
    }),
  );
  const stateRef = db.collection("geoState").doc(uid);
  const now = Date.now();
  const arrivals = await db.runTransaction(async (tx) => {
    const snap = await tx.get(stateRef);
    const prevPlaces = (snap.get("places") as Record<string, PlaceMemo> | undefined) ?? {};
    // 예전 형식({ inside: { key: boolean } })도 읽는다
    const oldInside = (snap.get("inside") as Record<string, boolean> | undefined) ?? {};
    const places: Record<string, PlaceMemo> = {};
    const found: { members: string[]; name: string; emoji: string }[] = [];
    for (const { gid, group, places: docs } of groups) {
      if (!group.exists) continue;
      for (const p of docs.docs) {
        const key = `${gid}/${p.id}`;
        const prev =
          prevPlaces[key] ?? (key in oldInside ? { inside: oldInside[key], since: 0 } : undefined);
        const d = distanceMeters(loc, { lat: p.get("lat"), lng: p.get("lng") });
        const r = placeState(prev, d, (p.get("radius") as number) ?? 150, loc.accuracy ?? 0, now);
        places[key] = r.state;
        if (r.transition === "enter") {
          found.push({
            members: group.get("members") as string[],
            name: p.get("name") as string,
            emoji: (p.get("emoji") as string) ?? "📍",
          });
        }
      }
    }
    tx.set(stateRef, { places, updatedAt: FieldValue.serverTimestamp() });
    return found;
  });

  for (const a of arrivals) {
    const others = a.members.filter((m) => m !== uid);
    const users = await Promise.all(others.map((m) => db.collection("users").doc(m).get()));
    await Promise.all(
      users
        .filter((u) => u.get("alertPlaces") !== false)
        .map((u) =>
          notify(u.data(), `${a.emoji} ${a.name} 도착`, `${displayName(me)}님이 ${a.name}에 도착했어요`, "place"),
        ),
    );
  }
}

/**
 * 나와 가족 사이 거리가 각자 정한 기준(기본 5km)을 넘거나 다시 들어오면 알린다.
 * "보는 사람 → 대상" 방향마다 상태를 따로 둔다 (사람마다 기준 거리가 다를 수 있음).
 */
async function checkDistances(uid: string, me: UserData, loc: LatLng) {
  const viewers = (me.viewers as string[] | undefined) ?? [];
  await Promise.all(
    viewers.map(async (otherUid) => {
      const otherSnap = await db.collection("users").doc(otherUid).get();
      const other = otherSnap.data();
      const otherLoc = other?.lastLocation as LatLng | undefined;
      const updatedAt = other?.updatedAt as Timestamp | undefined;
      if (!other || !otherLoc || other.sharing === false) return;
      if (!updatedAt || Date.now() - updatedAt.toMillis() > STALE_LOCATION_MS) return;

      const d = distanceMeters(loc, otherLoc);
      await Promise.all([
        recordTogether(uid, otherUid, d, {
          lat: (loc.lat + otherLoc.lat) / 2,
          lng: (loc.lng + otherLoc.lng) / 2,
        }),
        updateWatch(otherUid, other, uid, me, d), // 가족이 나를 보는 방향
        updateWatch(uid, me, otherUid, other, d), // 내가 가족을 보는 방향
      ]);
    }),
  );
}

/** 두 가족이 함께 있었던 시간과 장소를 누적한다 (together/{두 사람 키}). */
async function recordTogether(a: string, b: string, distance: number, meetingPoint: LatLng) {
  const [x, y] = a < b ? [a, b] : [b, a];
  const ref = db.collection("together").doc(`${x}_${y}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const prev = snap.exists ? (snap.data() as TogetherState) : undefined;
    const next = updateTogether(prev, distance, Date.now(), meetingPoint);
    tx.set(ref, { members: [x, y], ...next });
  });
}

async function updateWatch(
  viewerUid: string,
  viewer: UserData,
  targetUid: string,
  target: UserData,
  distance: number,
) {
  const ref = db.collection("distState").doc(watchKey(viewerUid, targetUid));
  if (viewer.alertDistance === false) {
    await ref.delete(); // 다시 켜면 현재 상태부터 새로 시작
    return;
  }
  const km = normalizeDistanceKm(viewer.alertDistanceKm);
  const snap = await ref.get();
  const wasFar = snap.exists && snap.get("km") === km ? (snap.get("far") as boolean) : undefined;
  const r = pairState(wasFar, distance, km);
  if (snap.exists && wasFar === r.far) return; // 변화 없음: 쓰기 생략
  await ref.set({ viewer: viewerUid, target: targetUid, far: r.far, km });

  const name = displayName(target);
  if (r.transition === "far") {
    await notify(viewer, "거리 알림", `${name}님과 ${km}km 이상 멀어졌어요`, "distance", DISTANCE_ALERT_DISMISS_MS);
  } else if (r.transition === "near") {
    await notify(viewer, "거리 알림", `${name}님이 ${km}km 이내에 있어요`, "distance", DISTANCE_ALERT_DISMISS_MS);
  }
}
