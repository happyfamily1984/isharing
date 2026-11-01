import { readFileSync } from "node:fs";
import { after, before, beforeEach, test } from "node:test";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, addDoc, collection, Timestamp } from "firebase/firestore";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-familylocator",
    firestore: { rules: readFileSync("../firestore.rules", "utf8") },
  });
});
after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  // 서버(Functions)가 만든 상태를 흉내낸다: alice, bob 은 같은 그룹, mallory 는 외부인
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/alice"), { displayName: "Alice", viewers: ["bob"], lastLocation: { lat: 1, lng: 2 } });
    await setDoc(doc(db, "users/bob"), { displayName: "Bob", viewers: ["alice"] });
    await setDoc(doc(db, "users/mallory"), { displayName: "M", viewers: [] });
    await setDoc(doc(db, "users/alice/locations/p1"), { lat: 1, lng: 2, ts: Timestamp.now() });
    await setDoc(doc(db, "groups/g1"), { name: "Fam", ownerId: "alice", members: ["alice", "bob"] });
    await setDoc(doc(db, "groups/g1/requests/mallory"), { displayName: "M" });
    await setDoc(doc(db, "together/alice_bob"), { members: ["alice", "bob"], days: {}, sessions: [] });
    await setDoc(doc(db, "groups/g1/places/home"), { name: "집", emoji: "🏠", lat: 1, lng: 2, radius: 150 });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();

test("group members can read each other's location and history", async () => {
  await assertSucceeds(getDoc(doc(as("bob"), "users/alice")));
  await assertSucceeds(getDoc(doc(as("bob"), "users/alice/locations/p1")));
});

test("outsiders and anonymous users cannot read location", async () => {
  await assertFails(getDoc(doc(as("mallory"), "users/alice")));
  await assertFails(getDoc(doc(as("mallory"), "users/alice/locations/p1")));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "users/alice")));
});

test("users cannot grant themselves access by editing viewers/groupIds", async () => {
  await assertFails(updateDoc(doc(as("mallory"), "users/mallory"), { viewers: ["alice"] }));
  await assertFails(updateDoc(doc(as("mallory"), "users/alice"), { viewers: ["alice", "bob", "mallory"] }));
  await assertFails(setDoc(doc(as("newbie"), "users/newbie"), { displayName: "N", groupIds: ["g1"] }));
});

test("users can update their own location and create their profile", async () => {
  await assertSucceeds(updateDoc(doc(as("alice"), "users/alice"), { lastLocation: { lat: 3, lng: 4 }, sharing: true }));
  await assertSucceeds(setDoc(doc(as("newbie"), "users/newbie"), { displayName: "N", sharing: true }));
});

test("only the owner can append history; no one can write another's history", async () => {
  await assertSucceeds(addDoc(collection(as("alice"), "users/alice/locations"), { lat: 1, lng: 2, accuracy: 5, ts: Timestamp.now() }));
  await assertFails(addDoc(collection(as("bob"), "users/alice/locations"), { lat: 1, lng: 2, ts: Timestamp.now() }));
  await assertFails(addDoc(collection(as("alice"), "users/alice/locations"), { lat: 1, lng: 2, ts: Timestamp.now(), extra: 1 }));
});

test("groups are readable by members only and never writable by clients", async () => {
  await assertSucceeds(getDoc(doc(as("bob"), "groups/g1")));
  await assertFails(getDoc(doc(as("mallory"), "groups/g1")));
  await assertFails(updateDoc(doc(as("alice"), "groups/g1"), { members: ["alice", "bob", "mallory"] }));
});

test("join requests are visible to the group owner and the requester only", async () => {
  await assertSucceeds(getDoc(doc(as("alice"), "groups/g1/requests/mallory")));
  await assertSucceeds(getDoc(doc(as("mallory"), "groups/g1/requests/mallory")));
  await assertFails(getDoc(doc(as("bob"), "groups/g1/requests/mallory")));
});

test("invite codes are server-only", async () => {
  await assertFails(getDoc(doc(as("alice"), "inviteCodes/ABC123")));
});

const place = { name: "회사", emoji: "🏢", lat: 37.5, lng: 127.0, radius: 150, createdBy: "bob" };

test("group members can manage places; outsiders cannot see them", async () => {
  await assertSucceeds(getDoc(doc(as("bob"), "groups/g1/places/home")));
  await assertSucceeds(setDoc(doc(as("bob"), "groups/g1/places/work"), place));
  await assertFails(getDoc(doc(as("mallory"), "groups/g1/places/home")));
  await assertFails(setDoc(doc(as("mallory"), "groups/g1/places/evil"), place));
});

test("place fields are validated", async () => {
  await assertFails(setDoc(doc(as("bob"), "groups/g1/places/x"), { ...place, radius: 5000 }));
  await assertFails(setDoc(doc(as("bob"), "groups/g1/places/x"), { ...place, name: "" }));
  await assertFails(setDoc(doc(as("bob"), "groups/g1/places/x"), { ...place, extra: true }));
});

test("alert state is server-only", async () => {
  await assertFails(getDoc(doc(as("alice"), "geoState/alice")));
  await assertFails(getDoc(doc(as("alice"), "distState/alice_bob")));
});

test("time together is visible only to the two people and never client-written", async () => {
  await assertSucceeds(getDoc(doc(as("alice"), "together/alice_bob")));
  await assertSucceeds(getDoc(doc(as("bob"), "together/alice_bob")));
  await assertFails(getDoc(doc(as("mallory"), "together/alice_bob")));
  await assertFails(setDoc(doc(as("alice"), "together/alice_bob"), { members: ["alice", "bob"], days: { x: 99999 } }));
});

test("check-ins are write-only for the owner and validated", async () => {
  const at = Timestamp.now();
  await assertSucceeds(setDoc(doc(as("alice"), "checkins/alice"), { lat: 1, lng: 2, accuracy: 10, at }));
  await assertFails(setDoc(doc(as("bob"), "checkins/alice"), { lat: 1, lng: 2, accuracy: 10, at }));
  await assertFails(setDoc(doc(as("alice"), "checkins/alice"), { lat: "x", lng: 2 }));
  await assertFails(setDoc(doc(as("alice"), "checkins/alice"), { lat: 1, lng: 2, viewers: ["mallory"] }));
  await assertFails(getDoc(doc(as("alice"), "checkins/alice")));
});
