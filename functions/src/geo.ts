// 위치 알림 판단 로직 (Firestore 와 무관한 순수 함수라 단위 테스트한다).

export interface LatLng {
  lat: number;
  lng: number;
}

/** 두 좌표 사이 거리(m) */
export function distanceMeters(a: LatLng, b: LatLng): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** 장소를 벗어났다고 보려면 반경보다 이만큼 더 멀어져야 한다 (경계에서 GPS 흔들림으로 알림이 반복되지 않게). */
export const PLACE_EXIT_MARGIN_M = 50;

/** 거리 알림 기본 기준 (사용자가 설정에서 1/3/5/10km 중 고른다) */
export const DEFAULT_DISTANCE_KM = 5;
export const DISTANCE_CHOICES_KM = [1, 3, 5, 10];

/** 다시 "가까워짐"으로 보려면 기준보다 이 비율만큼 더 가까워야 한다 (5km 기준 300m) */
const NEAR_RATIO = 0.94;

/** 이보다 부정확한 위치로는 상태를 바꾸지 않는다 */
export const MAX_ACCURACY_M = 300;

export type Transition = "enter" | "exit" | "none";

/**
 * 장소 안/밖 판단.
 * [wasInside] 가 undefined 면 처음 판단하는 것이라 알림 없이 상태만 정한다
 * (앱을 집에서 처음 켰을 때 "도착" 알림이 가지 않도록).
 */
export function placeState(
  wasInside: boolean | undefined,
  distance: number,
  radius: number,
): { inside: boolean; transition: Transition } {
  const inside = wasInside ? distance <= radius + PLACE_EXIT_MARGIN_M : distance <= radius;
  if (wasInside === undefined || inside === wasInside) return { inside, transition: "none" };
  return { inside, transition: inside ? "enter" : "exit" };
}

/** 설정값을 허용된 기준(km)으로 정리한다. */
export function normalizeDistanceKm(value: unknown): number {
  return typeof value === "number" && DISTANCE_CHOICES_KM.includes(value) ? value : DEFAULT_DISTANCE_KM;
}

/** 두 사람 사이 거리 상태. [wasFar] 가 undefined 면 알림 없이 상태만 정한다. */
export function pairState(
  wasFar: boolean | undefined,
  distance: number,
  thresholdKm: number = DEFAULT_DISTANCE_KM,
): { far: boolean; transition: "far" | "near" | "none" } {
  const farM = thresholdKm * 1000;
  const far = wasFar ? distance >= farM * NEAR_RATIO : distance > farM;
  if (wasFar === undefined || far === wasFar) return { far, transition: "none" };
  return { far, transition: far ? "far" : "near" };
}

/** "보는 사람 → 대상" 거리 상태 문서 키 (사람마다 기준 거리가 달라 방향별로 따로 둔다) */
export function watchKey(viewer: string, target: string): string {
  return `${viewer}_${target}`;
}

// ---------------------------------------------------------------------------
// 함께한 시간
// ---------------------------------------------------------------------------

/** 이 거리 안이면 함께 있는 것으로 본다 */
export const TOGETHER_ENTER_M = 100;
/** 함께 있다가 이보다 멀어져야 떨어진 것으로 본다 (GPS 흔들림 대비) */
export const TOGETHER_EXIT_M = 200;
/** 기록이 이보다 오래 끊긴 구간은 세지 않는다 (둘 다 폰이 꺼져 있었을 수 있음) */
export const TOGETHER_MAX_GAP_MS = 10 * 60 * 1000;
/** 날짜별 기록 보관 기간 */
export const TOGETHER_KEEP_DAYS = 35;

/** 함께 있었던 한 번의 시간과 장소 */
export interface TogetherSession {
  /** 시작·끝 시각 (ms) */
  start: number;
  end: number;
  /** 함께 있던 곳 (만났을 때 두 사람의 가운데 지점) */
  lat: number;
  lng: number;
}

export interface TogetherState {
  together: boolean;
  /** 마지막으로 판단한 시각 (ms) */
  lastAt: number;
  /** 한국 날짜("2026-10-17")별 함께한 초 */
  days: Record<string, number>;
  /** 함께 있었던 시간·장소 목록 (오래된 것부터) */
  sessions: TogetherSession[];
}

/** 한국 시간 기준 날짜 문자열 */
export function kstDay(ms: number): string {
  return new Date(ms + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/**
 * 두 사람의 거리를 새로 잰 시점에 함께한 시간과 장소 기록을 갱신한다.
 * 직전에 함께 있었다면 그 사이 시간은 함께 보낸 것으로 본다.
 * [meetingPoint] 는 두 사람의 가운데 지점이다.
 */
export function updateTogether(
  prev: TogetherState | undefined,
  distance: number,
  nowMs: number,
  meetingPoint: LatLng,
): TogetherState {
  const together = prev?.together ? distance <= TOGETHER_EXIT_M : distance <= TOGETHER_ENTER_M;
  const days: Record<string, number> = { ...(prev?.days ?? {}) };
  const sessions: TogetherSession[] = (prev?.sessions ?? []).map((x) => ({ ...x }));
  const gap = prev ? nowMs - prev.lastAt : Infinity;
  const continuous = gap > 0 && gap <= TOGETHER_MAX_GAP_MS;

  // 직전에 함께였고 기록이 이어져 있으면 그 사이 시간을 더하고 마지막 기록을 늘린다.
  if (prev?.together && continuous) {
    const day = kstDay(nowMs);
    days[day] = (days[day] ?? 0) + Math.round(gap / 1000);
    const last = sessions[sessions.length - 1];
    if (last) last.end = nowMs;
  }

  // 새로 함께하기 시작: 직전 기록에 바로 이어지면(10분 이내·가까운 곳) 합치고, 아니면 새 기록
  if (together && !(prev?.together && continuous)) {
    const last = sessions[sessions.length - 1];
    const resumes =
      last !== undefined &&
      nowMs - last.end <= TOGETHER_MAX_GAP_MS &&
      distanceMeters(last, meetingPoint) <= TOGETHER_EXIT_M;
    if (!resumes) sessions.push({ start: nowMs, end: nowMs, lat: meetingPoint.lat, lng: meetingPoint.lng });
  }

  const cutoff = nowMs - TOGETHER_KEEP_DAYS * 24 * 60 * 60 * 1000;
  const oldest = kstDay(cutoff);
  for (const day of Object.keys(days)) if (day < oldest) delete days[day];
  return {
    together,
    lastAt: nowMs,
    days,
    sessions: sessions.filter((x) => x.end >= cutoff),
  };
}
