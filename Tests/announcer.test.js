const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ANNOUNCE_SETTING,
  APP_EVENTS_SETTING,
  Announcer
} = require("../AppleBuildTools.novaextension/Scripts/announcer");

test("speaks a phrase with the Mac speech command and no shell", function () {
  const environment = makeEnvironment();
  const announcer = new Announcer(environment.dependencies);

  assert.equal(announcer.say("Scheme App selected."), true);

  assert.equal(environment.processes.length, 1);
  assert.equal(environment.processes[0].command, "/usr/bin/say");
  assert.deepEqual(environment.processes[0].options, { args: ["Scheme App selected."], shell: false });
  assert.equal(environment.processes[0].started, true);
});

test("choice and progress speech is off by default and on only when turned on", function () {
  const off = makeEnvironment({ setting: null });
  assert.equal(new Announcer(off.dependencies).say("Hello"), false);
  assert.equal(off.processes.length, 0);

  assert.equal(new Announcer(makeEnvironment({ setting: true }).dependencies).say("Hello"), true);
});

test("app crash and error alerts are off by default and on only when turned on", function () {
  assert.equal(new Announcer(makeEnvironment({ setting: null }).dependencies).say("The app crashed.", { appEvent: true }), false);
  assert.equal(new Announcer(makeEnvironment({ setting: false, appEvents: true }).dependencies).say("The app crashed.", { appEvent: true }), true);
});

test("a new phrase stops the previous one so speech does not pile up", function () {
  const environment = makeEnvironment();
  const announcer = new Announcer(environment.dependencies);

  announcer.say("First");
  announcer.say("Second");

  assert.equal(environment.processes[0].terminateCount, 1);
  assert.equal(environment.processes[1].terminateCount, 0);
});

test("a finished phrase is not stopped again", function () {
  const environment = makeEnvironment();
  const announcer = new Announcer(environment.dependencies);

  announcer.say("First");
  environment.processes[0].emitExit(0);
  announcer.say("Second");

  assert.equal(environment.processes[0].terminateCount, 0);
});

test("phrases cannot be read as command options and empty phrases are ignored", function () {
  const environment = makeEnvironment();
  const announcer = new Announcer(environment.dependencies);

  announcer.say("--voice Bad");
  assert.deepEqual(environment.processes[0].options.args, ["voice Bad"]);
  assert.equal(announcer.say("  "), false);
  assert.equal(announcer.say(null), false);
  assert.equal(environment.processes.length, 1);
});

test("a speech failure never throws into the calling command", function () {
  const environment = makeEnvironment({ startError: new Error("no say") });
  const announcer = new Announcer(environment.dependencies);

  assert.equal(announcer.say("Hello"), false);
});

test("the setting key matches the manifest", function () {
  const manifest = require("../AppleBuildTools.novaextension/extension.json");
  const entry = manifest.config.find((item) => item.key === ANNOUNCE_SETTING);

  assert.equal(entry.type, "boolean");
  assert.equal(entry.default, false);
  assert.equal(entry.title, "Announce choices and progress");
  const events = manifest.config.find((item) => item.key === APP_EVENTS_SETTING);
  assert.equal(events.default, false);
  assert.equal(events.title, "Announce app crashes and errors");
});

function makeEnvironment(options = {}) {
  const processes = [];
  class FakeProcess {
    constructor(command, processOptions) {
      this.command = command;
      this.options = processOptions;
      this.terminateCount = 0;
      this.exitHandlers = [];
      processes.push(this);
    }

    onDidExit(handler) {
      this.exitHandlers.push(handler);
      return { dispose() {} };
    }

    start() {
      if (options.startError) {
        throw options.startError;
      }
      this.started = true;
    }

    terminate() {
      this.terminateCount += 1;
    }

    emitExit(status) {
      this.exitHandlers.forEach((handler) => handler(status));
    }
  }
  const config = {
    get(key) {
      if (key === APP_EVENTS_SETTING) {
        return "appEvents" in options ? options.appEvents : null;
      }
      assert.equal(key, ANNOUNCE_SETTING);
      return "setting" in options ? options.setting : true;
    }
  };
  return { processes, dependencies: { Process: FakeProcess, config } };
}
