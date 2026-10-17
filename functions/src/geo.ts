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
