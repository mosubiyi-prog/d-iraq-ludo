"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {projectShadowMonthlyTopTen, monthOfBaghdadInstant} =
  require("../deda_weekly_monthly_top10_archive_NOT_EXPORTED.js");

const WEEK_MS = 7 * 86400000;
const REWARDS = [150,100,50,10,10,10,10,10,10,10];

function makeWeek(index, opts={}) {
  const startMs = Date.parse("2026-10-01T21:00:00Z") +
    (opts.offsetDays ?? index * 7) * 86400000;
  const endMs = startMs + WEEK_MS;
  const weekId = opts.weekId || "oct-wk-" + index;
  const rows = Array.from({length: 12}, (_, i) => ({
    place: i + 1,
    accountKey: String(7700000000 + i).padStart(11, "0"),
    publicCompetitorId: "leader-participant-" + String(i+1000000000000000),
    activePublicId: "@DEDA-" + String(1000 + i),
    displayName: "متسابق " + (i + 1),
    earnedLevelXp: (12 - i) * 20,
    taskClaims: 12 - i,
    lastEarnedAtMs: startMs + 1000,
    potentialDiamonds: REWARDS[i] || 0,
  }));
  return {
    weekConfig: {weekId, startMs, endMs},
    snapshot: {
      issuer: "privileged_server_only_weekly_ranker_v1",
      state: "closed",
      weekId,
      generatedAtMs: endMs - 1,
      rows,
    },
  };
}
function project(weeks, now="2026-10-20T00:00:00Z", monthId="2026-10") {
  return projectShadowMonthlyTopTen({
    monthId, closedWeeks: weeks, serverNowMs: Date.parse(now),
  });
}

test("monthly history shows 10 authentic-shape ranks and three per closed week", () => {
  const a=makeWeek(0), b=makeWeek(1);
  const x=project([b,a]);
  assert.equal(x.monthId, "2026-10");
  assert.equal(x.status, "collecting");
  assert.deepEqual(x.weeks.map(w => w.weekId), ["oct-wk-0","oct-wk-1"]);
  for(const w of x.weeks) {
    assert.equal(w.topTen.length,10);
    assert.deepEqual(w.topThree.map(p=>p.place),[1,2,3]);
    assert.equal(w.topTen[0].weeklyPoints,240);
    assert.equal(w.topTen[9].weeklyPoints,60);
    assert.match(w.integrityDigest,/^[a-f0-9]{64}$/);
    assert.ok(Object.isFrozen(w.topTen));
    assert.ok(Object.isFrozen(w.topThree));
  }
  assert.equal(x.grantsDiamonds,false);
  assert.equal(x.shadowOnly,true);
  assert.equal(x.adminAccessValidated,false);
});
test("archives do not expose canonical private account keys, phone, or balances", () => {
  const x=project([makeWeek(0)]);
  const rendered=JSON.stringify(x);
  assert.doesNotMatch(rendered,/"accountKey"|"phone"|"uid"|"wallet"/);
  assert.equal(x.weeks[0].topTen[0].activePublicId, "@DEDA-1000");
  assert.equal(x.weeks[0].topTen[0].participantId, "leader-participant-1000000000000000");
});
test("closed historical month stays distinct from later month, no reset or awards", () => {
  const october=project([makeWeek(0)],"2026-11-03T00:00:00Z");
  assert.equal(october.status,"closed");
  assert.equal(october.weeks.length,1);
  assert.equal(october.readOnly,true);
  assert.equal(october.verifiedProduction,false);
});
test("rejects unclosed weekly snapshot and fabricated final timestamp", () => {
  const week=makeWeek(0);
  assert.throws(()=>project([week],"2026-10-03T00:00:00Z"),/BLOCK_/);
  week.snapshot.generatedAtMs--;
  assert.throws(()=>project([week]),/BLOCK_/);
});
test("rejects anonymous pseudo issuer, forged rank, unsorted scores", () => {
  const week=makeWeek(0);
  week.snapshot.issuer="client_json";
  assert.throws(()=>project([week]),/BLOCK_/);
  week.snapshot.issuer="privileged_server_only_weekly_ranker_v1";
  week.snapshot.rows[0].place=99;
  assert.throws(()=>project([week]),/BLOCK_/);
});
test("rejects duplicate week, overlapping windows, and month misfiling", () => {
  assert.throws(()=>project([makeWeek(0),makeWeek(0)]),/BLOCK_/);
  assert.throws(()=>project([
    makeWeek(0),makeWeek(1,{weekId:"overlap",offsetDays:3})
  ]),/BLOCK_/);
  assert.throws(()=>project([makeWeek(0)],"2026-11-20T00:00:00Z","2026-11"),/BLOCK_/);
});
test("zero weeks is empty month, no fake competitors or prize", () => {
  const r=project([]);
  assert.deepEqual(r.weeks,[]);
  assert.equal(r.grantsDiamonds,false);
});
test("rejects extra client fields and malformed month", () => {
  assert.throws(()=>projectShadowMonthlyTopTen({
    monthId:"2026-10",closedWeeks:[],serverNowMs:Date.now(),
    diamonds: 1000000,
  }),/BLOCK_/);
  assert.throws(()=>project([],"2026-10-20T00:00:00Z","2026-13"),/BLOCK_/);
});
test("Baghdad month cutoff checks last eligible instant, not server's UTC month", () => {
  const close=Date.parse("2026-10-31T21:00:00.000Z");
  assert.equal(monthOfBaghdadInstant(close - 1),"2026-10");
  assert.equal(monthOfBaghdadInstant(close),"2026-11");
});
