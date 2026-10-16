import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2";

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
  if (deletedCode) await db.collection("inviteCodes").doc(deletedCode).delete();
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
