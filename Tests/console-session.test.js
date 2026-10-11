const assert = require("node:assert/strict");
const test = require("node:test");
const { ConsoleSession, MAX_LINES } = require("../AppleBuildTools.novaextension/Scripts/console-session");

function makeSession(options = {}) {
  const phrases = [];
  const calls = [];
  const sleeps = [];
  let lookups = 0;
  const process = { terminateCount: 0, terminate() { this.terminateCount += 1; } };
  const helper = {
    async invoke(subcommand, invokeOptions) {
      calls.push({ subcommand, options: invokeOptions });
      lookups += 1;
      if (options.pending) return new Promise(() => {});
      if (options.reportsError) throw options.reportsError;
      if (options.reportsByLookup) return options.reportsByLookup[lookups - 1] || [];
      return options.reports || [];
    }
  };
  const session = new ConsoleSession({
    helper, process,
    announcer: { say(text, options) { assert.equal(options && options.appEvent, true); phrases.push(text); return true; } },
    selection: { scheme: "App", destinationSpecifier: "platform=iOS,id=DEVICE" },
    workspaceRoot: "/repo", appName: "Sample App", deviceName: "Sam’s iPhone",
    now: () => new Date("2026-10-09T18:10:05Z"),
    sleep: async (ms) => { sleeps.push(ms); },
    checksCrashReports: options.checksCrashReports
  });
  return { session, phrases, calls, process, sleeps };
}

test("collects lines, speaks the first error once, and snapshots while running", function () {
  const { session, phrases } = makeSession();
  session.append("Launched");
  session.append("Error: could not open file");
  session.append("another error");
  const snapshot = session.snapshot();

  assert.deepEqual(phrases, ["The app reported an error."]);
  assert.equal(snapshot.state, "running");
  assert.deepEqual(snapshot.lines, ["Launched", "Error: could not open file", "another error"]);
  assert.equal(snapshot.appName, "Sample App");
  assert.equal(snapshot.endedAt, null);
  assert.equal(snapshot.droppedLines, 0);
  assert.equal(session.isListening(), true);
});

test("keeps the newest lines and cuts very long ones", function () {
  const { session } = makeSession();
  for (let index = 0; index < MAX_LINES + 5; index += 1) session.append(`line ${index}`);
  session.append("x".repeat(5000));
  const snapshot = session.snapshot();

  assert.equal(snapshot.lines.length, MAX_LINES);
  assert.equal(snapshot.droppedLines, 6);
  assert.equal(snapshot.lines.at(-1).length, 2000);
});

test("an unexpected end with a new crash report is announced and recorded", async function () {
  const { session, phrases, calls } = makeSession({ reports: [
    { source: "Sample App.cpu_resource-2026-10-09-141030.ips", kind: "cpu" },
    { source: "Sample App-2026-10-09-141031.ips", kind: "crash" }
  ] });
  await session.ended(0);

  assert.equal(calls[0].subcommand, "app-reports");
  assert.equal(calls[0].options["since-epoch"], 1791569405);
  assert.deepEqual(phrases, ["The app crashed."]);
  assert.equal(session.snapshot().state, "crashed");
  assert.equal(session.snapshot().crashSource, "Sample App-2026-10-09-141031.ips");
  assert.equal(session.isListening(), false);
});

test("an end without a crash, or a failed lookup, says the app quit", async function () {
  for (const options of [{ reports: [] }, { reportsError: new Error("locked") }]) {
    const { session, phrases } = makeSession(options);
    await session.ended(0);
    assert.deepEqual(phrases, ["The app quit."]);
    assert.equal(session.snapshot().state, "ended");
  }
});

test("a crash report that appears a few seconds late is still found", async function () {
  const { session, phrases, calls, sleeps } = makeSession({ reportsByLookup: [
    [],
    [{ source: "Sample App-2026-10-09-141031.ips", kind: "crash" }]
  ] });
  await session.ended(0);

  assert.equal(calls.length, 2);
  assert.deepEqual(sleeps, [5000]);
  assert.deepEqual(phrases, ["The app crashed."]);
  assert.equal(session.snapshot().crashSource, "Sample App-2026-10-09-141031.ips");
});

test("the console says it is checking while the crash lookup runs", function () {
  const { session, phrases } = makeSession({ pending: true });
  session.ended(0);

  assert.equal(session.snapshot().state, "checking");
  assert.deepEqual(phrases, []);
});

test("lines are cut without splitting an emoji", function () {
  const { session } = makeSession();
  session.append("a".repeat(1999) + "😀 tail");
  const line = session.snapshot().lines[0];

  assert.equal(Array.from(line).length, 2000);
  assert.equal(/[\ud800-\udbff]$/.test(line), false);
  assert.equal(JSON.parse(JSON.stringify(line)), line);
});

test("after Stop, later output is not recorded", function () {
  const { session } = makeSession();
  session.append("before");
  session.stop();
  session.append("after");

  assert.deepEqual(session.snapshot().lines, ["before"]);
});

test("devicectl's own waiting line is not part of the app output", function () {
  const { session } = makeSession();
  session.append("Waiting for the application to terminate...");
  session.append("hello");
  session.append("The app terminated with the exit code 0.");

  assert.deepEqual(session.snapshot().lines, ["hello", "The app terminated with the exit code 0."]);
});

test("a Mac or Simulator console does not look for iPhone crash reports", async function () {
  const { session, phrases, calls } = makeSession({ checksCrashReports: false });
  await session.ended(0);

  assert.deepEqual(calls, []);
  assert.deepEqual(phrases, ["The app quit."]);
});

test("stop ends listening without a crash lookup and can be silent", async function () {
  const { session, phrases, calls, process } = makeSession();
  assert.equal(session.stop({ silent: true }), true);
  await session.ended(15);

  assert.equal(process.terminateCount, 0);
  assert.deepEqual(calls, []);
  assert.deepEqual(phrases, []);
  assert.equal(session.snapshot().state, "stopped");
  assert.equal(session.stop(), false);
});
