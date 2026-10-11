const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DirectActionRunner
} = require("../AppleBuildTools.novaextension/Scripts/direct-action-runner");
const {
  missingSelectionLabels
} = require("../AppleBuildTools.novaextension/Scripts/task-assistant");

test("incomplete selections produce an accessible setup message without invoking the helper", async function () {
  const environment = makeEnvironment({
    selection: { ...completeSelection(), scheme: null, destinationLabel: null, destinationSpecifier: null }
  });
  const runner = new DirectActionRunner(environment.dependencies);

  assert.equal(await runner.run("build"), "rejected");
  assert.deepEqual(environment.helper.calls, []);
  assert.match(environment.panels[0].message, /Apple Build: Select Scheme/);
  assert.match(environment.panels[0].message, /Apple Build: Select Destination/);
  assert.equal(environment.processes.length, 0);
});

test("missing selection labels are stable and name the corresponding commands", function () {
  assert.deepEqual(missingSelectionLabels({}), [
    "Xcode (Apple Build: Select Xcode)",
    "project or workspace (Apple Build: Select Project or Workspace)",
    "scheme (Apple Build: Select Scheme)",
    "configuration (Apple Build: Select Configuration)",
    "destination (Apple Build: Select Destination)"
  ]);
});

test("build clean and test use the matching helper action and process specification", async function () {
  for (const action of ["build", "clean", "test"]) {
    const environment = makeEnvironment();
    const runner = new DirectActionRunner(environment.dependencies);

    assert.equal(await runner.run(action), "started");
    assert.deepEqual(environment.helper.calls[0], {
      subcommand: "prepare-action",
      options: {
        action,
        "workspace-root": "/repo",
        "selection-json": JSON.stringify(completeSelection())
      }
    });
    assert.deepEqual(environment.processes[0].options, {
      args: ["-scheme", "App"],
      env: { DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer" },
      cwd: "/repo",
      shell: false
    });
  }
});

test("a second direct action is rejected while the first is running", async function () {
  const environment = makeEnvironment();
  const runner = new DirectActionRunner(environment.dependencies);

  assert.equal(await runner.run("build"), "started");
  assert.equal(await runner.run("test"), "rejected");
  assert.equal(environment.processes.length, 1);
  assert.match(environment.panels.at(-1).message, /already running/);
});

test("stop terminates the active process and reports cancellation", async function () {
  const environment = makeEnvironment();
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("build");
  assert.equal(runner.stop(), true);
  assert.equal(environment.processes[0].terminateCount, 1);
  environment.processes[0].emitExit(143);
  assert.equal(runner.isRunning(), false);
  assert.match(environment.panels.at(-1).message, /cancelled/i);
  assert.equal(runner.stop(), false);
});

test("completion offers a readable in-memory Markdown report without writing to the project", async function () {
  const environment = makeEnvironment();
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("test");
  const process = environment.processes[0];
  process.emitStdout("Test Suite 'AppTests' started");
  process.emitStderr("warning: sample warning");
  process.emitExit(0);

  const panel = environment.panels.at(-1);
  assert.deepEqual(panel.options.buttons, ["View Build Command Report", "OK"]);
  assert.match(panel.message, /completed successfully/i);
  panel.callback(0);
  assert.equal(environment.documents.length, 1);
  assert.match(environment.documents[0].content, /^# Apple Test Command Report/m);
  assert.match(environment.documents[0].content, /## Standard output/);
  assert.match(environment.documents[0].content, /Test Suite 'AppTests' started/);
  assert.match(environment.documents[0].content, /## Standard error/);
  assert.match(environment.documents[0].content, /warning: sample warning/);
});

test("nonzero exit status produces a readable failure summary", async function () {
  const environment = makeEnvironment();
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("build");
  environment.processes[0].emitExit(65);

  assert.match(environment.panels.at(-1).message, /failed with exit status 65/i);
});

test("unconfigured test schemes explain how to enable the Test action", async function () {
  const environment = makeEnvironment();
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("test");
  environment.processes[0].emitStderr(
    "xcodebuild: error: Scheme SampleApp is not currently configured for the test action."
  );
  environment.processes[0].emitExit(66);

  assert.match(environment.panels.at(-1).message, /scheme is not configured for the Test action/i);
  assert.match(environment.panels.at(-1).message, /Edit Scheme.*add a test target/i);
});

test("helper errors are reported without starting a process", async function () {
  const environment = makeEnvironment({
    helperError: new Error("Xcode selection is invalid.")
  });
  const runner = new DirectActionRunner(environment.dependencies);

  assert.equal(await runner.run("clean"), "rejected");
  assert.equal(environment.processes.length, 0);
  assert.deepEqual(environment.errors, ["Apple Clean could not start. Xcode selection is invalid."]);
});

function iPhoneSelection() {
  return {
    ...completeSelection(),
    destinationLabel: "Sam’s iPhone — iOS, arm64e, DEVICE",
    destinationSpecifier: "platform=iOS,id=DEVICE"
  };
}

function devicePlan() {
  const step = (args) => ({
    command: "/usr/bin/xcrun",
    arguments: ["devicectl", ...args],
    environment: { DEVELOPER_DIR: "/Applications/Xcode.app/Contents/Developer" },
    workingDirectory: "/repo"
  });
  return {
    appName: "App.app",
    bundleIdentifier: "app.example",
    deviceName: "Sam’s iPhone",
    install: step(["device", "install", "app", "--device", "DEVICE", "/build/App.app"]),
    launch: step(["device", "process", "launch", "--device", "DEVICE", "--terminate-existing", "app.example"])
  };
}

async function settle() {
  await new Promise((resolve) => setImmediate(resolve));
}

test("run on iPhone builds, installs, then opens the app in order", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);

  assert.equal(await runner.run("device"), "started");
  assert.equal(environment.helper.calls[0].options.action, "build");
  environment.processes[0].emitExit(0);
  await settle();

  assert.deepEqual(environment.helper.calls[1], {
    subcommand: "prepare-device-run",
    options: {
      "workspace-root": "/repo",
      "selection-json": JSON.stringify(iPhoneSelection())
    }
  });
  assert.deepEqual(environment.processes[1].options.args.slice(0, 4), ["devicectl", "device", "install", "app"]);
  assert.equal(environment.processes[1].options.shell, false);
  assert.equal(runner.isRunning(), true);
  environment.processes[1].emitExit(0);
  await settle();

  assert.deepEqual(environment.processes[2].options.args.slice(0, 4), ["devicectl", "device", "process", "launch"]);
  environment.processes[2].emitExit(0);

  assert.equal(runner.isRunning(), false);
  assert.equal(environment.panels.length, 1);
  assert.equal(
    environment.panels[0].message,
    "Apple Build and Run completed. App.app is open on Sam’s iPhone."
  );
  environment.panels[0].callback(0);
  assert.match(environment.documents[0].content, /^# Apple Build and Run Command Report/m);
  assert.match(environment.documents[0].content, /Installing App\.app on Sam’s iPhone/);
  assert.match(environment.documents[0].content, /Opening App\.app on Sam’s iPhone/);
});


test("a failed build stops run on iPhone before installing", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("device");
  environment.processes[0].emitExit(65);
  await settle();

  assert.equal(environment.processes.length, 1);
  assert.equal(environment.helper.calls.length, 1);
  assert.equal(
    environment.panels.at(-1).message,
    "Apple Build and Run failed while building the app, exit status 65."
  );
});

test("a failed install explains how to prepare the iPhone and does not open the app", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("device");
  environment.processes[0].emitExit(0);
  await settle();
  environment.processes[1].emitExit(1);
  await settle();

  assert.equal(environment.processes.length, 2);
  assert.equal(
    environment.panels.at(-1).message,
    "Apple Build and Run failed while installing the app, exit status 1. Make sure the iPhone is unlocked, connected, trusts this Mac, and has Developer Mode on."
  );
});

test("helper failure after the build is reported without installing", async function () {
  const environment = makeEnvironment({
    selection: iPhoneSelection(),
    devicePlanError: new Error("Xcode did not report an installable app for the selected scheme.")
  });
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("device");
  environment.processes[0].emitExit(0);
  await settle();

  assert.equal(environment.processes.length, 1);
  assert.equal(runner.isRunning(), false);
  assert.deepEqual(environment.errors, [
    "Apple Build and Run could not prepare the app. Xcode did not report an installable app for the selected scheme."
  ]);
});

test("stop during install cancels run on iPhone without opening the app", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("device");
  environment.processes[0].emitExit(0);
  await settle();
  assert.equal(runner.stop(), true);
  assert.equal(environment.processes[1].terminateCount, 1);
  environment.processes[1].emitExit(143);
  await settle();

  assert.equal(environment.processes.length, 2);
  assert.equal(environment.panels.at(-1).message, "Apple Build and Run was cancelled.");
});

test("stop while preparing the install cancels without starting it", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("device");
  environment.processes[0].emitExit(0);
  assert.equal(runner.stop(), true);
  await settle();

  assert.equal(environment.processes.length, 1);
  assert.equal(environment.panels.at(-1).message, "Apple Build and Run was cancelled.");
});

test("build progress is spoken when an action starts and at each iPhone step", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("device");
  assert.equal(environment.phrases.length, 1);
  environment.processes[0].emitExit(0);
  await settle();
  assert.equal(environment.phrases.length, 2);
  environment.processes[1].emitExit(0);
  await settle();

  assert.equal(environment.phrases.length, 3);
  for (const phrase of environment.phrases) {
    assert.equal(typeof phrase, "string");
    assert.ok(phrase.trim().length > 0);
  }
  assert.equal(new Set(environment.phrases).size, 3);
});

test("plain build, clean, and test each speak a distinct start phrase", async function () {
  const phrases = [];
  for (const action of ["build", "clean", "test"]) {
    const environment = makeEnvironment();
    await new DirectActionRunner(environment.dependencies).run(action);
    assert.equal(environment.phrases.length, 1, action);
    phrases.push(environment.phrases[0]);
  }
  assert.equal(new Set(phrases).size, 3);
});

test("rejected actions speak nothing", async function () {
  const environment = makeEnvironment({ selection: { ...completeSelection(), destinationSpecifier: "generic/platform=iOS" } });
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("device");

  assert.deepEqual(environment.phrases, []);
});

test("run on iPhone completes at launch confirmation and keeps listening", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);
  await runner.run("device");
  environment.processes[0].emitExit(0); await settle();
  environment.processes[1].emitExit(0); await settle();

  const launch = environment.processes[2];
  launch.emitStdout("Launched application with app.example bundle identifier.");

  assert.equal(runner.isRunning(), false);
  assert.match(environment.panels.at(-1).message, /is open on Sam’s iPhone/);
  launch.emitStdout("Hello from the app");
  const session = runner.consoleSession();
  assert.ok(session.isListening());
  assert.deepEqual(session.snapshot().lines, ["Hello from the app"]);
  assert.equal(session.appName, "App");
  assert.equal(session.deviceName, "Sam’s iPhone");
});

test("stop with no action running stops listening to the app", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);
  await runner.run("device");
  environment.processes[0].emitExit(0); await settle();
  environment.processes[1].emitExit(0); await settle();
  environment.processes[2].emitStdout("Launched application with app.example bundle identifier.");

  assert.equal(runner.stop(), true);
  assert.equal(environment.processes[2].terminateCount, 0);
  assert.equal(environment.panels.at(-1).message, "Stopped listening to the app. It is still open on Sam’s iPhone.");
  assert.equal(runner.consoleSession().snapshot().state, "stopped");
});

test("a new iPhone run silently replaces the previous console", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);
  await runner.run("device");
  environment.processes[0].emitExit(0); await settle();
  environment.processes[1].emitExit(0); await settle();
  environment.processes[2].emitStdout("Launched application with app.example bundle identifier.");
  const first = runner.consoleSession();
  const phrasesBefore = environment.phrases.length;

  await runner.run("device");

  assert.equal(first.snapshot().state, "stopped");
  assert.equal(environment.phrases.length, phrasesBefore + 1);
  assert.match(environment.phrases.at(-1), /^Building /);
});

test("launch that exits before confirmation behaves as before", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);
  await runner.run("device");
  environment.processes[0].emitExit(0); await settle();
  environment.processes[1].emitExit(0); await settle();
  environment.processes[2].emitExit(1); await settle();

  assert.equal(runner.consoleSession(), null);
  assert.match(environment.panels.at(-1).message, /failed while opening the app/);
});

test("a new iPhone run also silences a console still checking for a crash", async function () {
  const environment = makeEnvironment({ selection: iPhoneSelection() });
  const runner = new DirectActionRunner(environment.dependencies);
  await runner.run("device");
  environment.processes[0].emitExit(0); await settle();
  environment.processes[1].emitExit(0); await settle();
  environment.processes[2].emitStdout("Launched application with app.example bundle identifier.");
  const first = runner.consoleSession();
  first.state = "checking";

  await runner.run("device");

  assert.equal(first.snapshot().state, "stopped");
});

function macSelection() {
  return { ...completeSelection(), destinationLabel: "My Mac — generic macOS destination", destinationSpecifier: "platform=macOS" };
}

function macPlan() {
  return {
    kind: "mac", appName: "Poster.app", bundleIdentifier: "app.example.poster", deviceName: "My Mac", steps: [],
    launch: { command: "/x/Poster.app/Contents/MacOS/Poster", arguments: [], environment: {}, workingDirectory: "/repo" },
    activate: { command: "/usr/bin/open", arguments: ["-a", "/x/Poster.app"], environment: {}, workingDirectory: "/repo" }
  };
}

function simulatorPlan() {
  const xcrun = (args) => ({ command: "/usr/bin/xcrun", arguments: args, environment: {}, workingDirectory: "/repo" });
  return {
    kind: "simulator", appName: "Poster.app", bundleIdentifier: "app.example.poster", deviceName: "iPhone 17",
    steps: [xcrun(["simctl", "bootstatus", "SIM", "-b"]), { command: "/usr/bin/open", arguments: ["-a", "Simulator.app"], environment: {}, workingDirectory: "/repo" }],
    install: xcrun(["simctl", "install", "SIM", "/x/Poster.app"]),
    launch: xcrun(["simctl", "launch", "--console-pty", "--terminate-running-process", "SIM", "app.example.poster"]),
    readyPattern: "^app\\.example\\.poster: [0-9]+"
  };
}

test("Build and Run on My Mac starts the app, brings it forward, and keeps listening", async function () {
  const environment = makeEnvironment({ selection: macSelection(), plan: macPlan() });
  const runner = new DirectActionRunner(environment.dependencies);

  assert.equal(await runner.run("device"), "started");
  environment.processes[0].emitExit(0); await settle();

  assert.equal(environment.processes[1].command, "/x/Poster.app/Contents/MacOS/Poster");
  assert.equal(environment.processes[1].options.shell, false);
  assert.equal(environment.processes[2].command, "/usr/bin/open");
  assert.deepEqual(environment.processes[2].options.args, ["-a", "/x/Poster.app"]);
  assert.equal(environment.panels.at(-1).message, "Apple Build and Run completed. Poster.app is open on My Mac.");
  environment.processes[1].emitStdout("hello from the Mac app");
  assert.deepEqual(runner.consoleSession().snapshot().lines, ["hello from the Mac app"]);
});

test("Build and Run on a Simulator prepares it, installs, and opens with the console", async function () {
  const environment = makeEnvironment({ selection: { ...completeSelection(), destinationLabel: "iPhone 17 — iOS Simulator 27.0, SIM", destinationSpecifier: "platform=iOS Simulator,id=SIM" }, plan: simulatorPlan() });
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("device");
  environment.processes[0].emitExit(0); await settle();
  assert.deepEqual(environment.processes[1].options.args, ["simctl", "bootstatus", "SIM", "-b"]);
  environment.processes[1].emitExit(0); await settle();
  assert.deepEqual(environment.processes[2].options.args, ["-a", "Simulator.app"]);
  environment.processes[2].emitExit(0); await settle();
  assert.deepEqual(environment.processes[3].options.args.slice(0, 2), ["simctl", "install"]);
  environment.processes[3].emitExit(0); await settle();
  environment.processes[4].emitStdout("app.example.poster: 4242");

  assert.equal(environment.panels.at(-1).message, "Apple Build and Run completed. Poster.app is open on iPhone 17.");
  assert.ok(runner.consoleSession().isListening());
});

test("a failed preparation step stops Build and Run in plain words", async function () {
  const environment = makeEnvironment({ selection: macSelection(), plan: simulatorPlan() });
  const runner = new DirectActionRunner(environment.dependencies);

  await runner.run("device");
  environment.processes[0].emitExit(0); await settle();
  environment.processes[1].emitExit(1); await settle();

  assert.equal(environment.processes.length, 2);
  assert.equal(environment.panels.at(-1).message, "Apple Build and Run failed while preparing the destination, exit status 1.");
});

test("Build and Run refuses a generic destination before building", async function () {
  const environment = makeEnvironment({ selection: { ...completeSelection(), destinationLabel: "Any iOS Device", destinationSpecifier: "generic/platform=iOS" } });
  const runner = new DirectActionRunner(environment.dependencies);

  assert.equal(await runner.run("device"), "rejected");
  assert.deepEqual(environment.helper.calls, []);
  assert.equal(environment.panels[0].message, "Build and Run needs a specific place to run: your iPhone, My Mac, or a Simulator. Choose Apple Build: Select Destination.");
});

test("a new Mac run closes the previous copy of the Mac app", async function () {
  const environment = makeEnvironment({ selection: macSelection(), plan: macPlan() });
  const runner = new DirectActionRunner(environment.dependencies);
  await runner.run("device");
  environment.processes[0].emitExit(0); await settle();
  const firstApp = environment.processes[1];

  await runner.run("device");

  assert.equal(firstApp.terminateCount, 1);
});

function completeSelection() {
  return {
    developerDirectory: "/Applications/Xcode.app/Contents/Developer",
    containerKind: "project",
    containerPath: "/repo/App.xcodeproj",
    scheme: "App",
    configuration: "Debug",
    destinationLabel: "My Mac",
    destinationSpecifier: "platform=macOS"
  };
}

function makeEnvironment(options = {}) {
  const selection = options.selection || completeSelection();
  const panels = [];
  const documents = [];
  const errors = [];
  const processes = [];
  const helper = {
    calls: [],
    async invoke(subcommand, invokeOptions) {
      this.calls.push({ subcommand, options: invokeOptions });
      if (options.helperError) {
        throw options.helperError;
      }
      if (subcommand === "prepare-device-run") {
        if (options.devicePlanError) {
          throw options.devicePlanError;
        }
        return options.plan || devicePlan();
      }
      return {
        command: "/usr/bin/xcodebuild",
        arguments: ["-scheme", "App"],
        environment: { DEVELOPER_DIR: selection.developerDirectory },
        workingDirectory: "/repo"
      };
    }
  };
  const workspace = {
    path: "/repo",
    showActionPanel(message, panelOptions, callback) {
      panels.push({ message, options: panelOptions, callback });
    },
    showErrorMessage(message) {
      errors.push(message);
    },
    openNewTextDocument(documentOptions) {
      documents.push(documentOptions);
      return Promise.resolve(documentOptions);
    }
  };
  const store = { savedSelection() { return selection; } };
  const phrases = [];
  const announcer = { say(text) { phrases.push(text); return true; } };

  class FakeProcess {
    constructor(command, processOptions) {
      this.command = command;
      this.options = processOptions;
      this.stdoutHandlers = [];
      this.stderrHandlers = [];
      this.exitHandlers = [];
      this.terminateCount = 0;
      processes.push(this);
    }

    onStdout(handler) {
      this.stdoutHandlers.push(handler);
      return { dispose() {} };
    }

    onStderr(handler) {
      this.stderrHandlers.push(handler);
      return { dispose() {} };
    }

    onDidExit(handler) {
      this.exitHandlers.push(handler);
      return { dispose() {} };
    }

    start() {
      this.started = true;
    }

    terminate() {
      this.terminateCount += 1;
    }

    emitStdout(line) {
      this.stdoutHandlers.forEach((handler) => handler(line));
    }

    emitStderr(line) {
      this.stderrHandlers.forEach((handler) => handler(line));
    }

    emitExit(status) {
      this.exitHandlers.forEach((handler) => handler(status));
    }
  }

  return {
    helper,
    panels,
    documents,
    errors,
    processes,
    phrases,
    dependencies: { helper, store, workspace, Process: FakeProcess, announcer }
  };
}

test("a Mac app's console also checks for crash reports", async function () {
  const environment = makeEnvironment({ selection: macSelection(), plan: macPlan() });
  const runner = new DirectActionRunner(environment.dependencies);
  await runner.run("device");
  environment.processes[0].emitExit(0); await settle();

  assert.equal(runner.consoleSession().checksCrashReports, true);
});

test("a failed build names its first error in the message", async function () {
  const environment = makeEnvironment();
  const runner = new DirectActionRunner(environment.dependencies);
  await runner.run("build");
  environment.processes[0].emitStdout("CpResource Sample App.app/Contents/Resources/sample-helper");
  environment.processes[0].emitStdout("error: The file “sample-helper” couldn’t be opened because there is no such file. (in target 'SampleApp' from project 'SampleApp')");
  environment.processes[0].emitStderr("** BUILD FAILED **");
  environment.processes[0].emitExit(65);

  assert.equal(
    environment.panels.at(-1).message,
    "Apple Build failed with exit status 65: The file “sample-helper” couldn’t be opened because there is no such file."
  );
});

test("the build report puts an Errors heading first, with only the error lines", function () {
  const { reportFor } = require("../AppleBuildTools.novaextension/Scripts/direct-action-runner");
  const entry = {
    action: "build", selection: { scheme: "SampleApp" }, startedAt: new Date("2026-10-10T17:35:29Z"),
    stdout: ["Compiling A.swift", "error: The file “sample-helper” couldn’t be opened.", "note: something"],
    stderr: ["** BUILD FAILED **", "The following build commands failed:", "\tCpResource sample-helper (in target 'SampleApp')", "(1 failure)"]
  };
  const report = reportFor(entry, 65, new Date("2026-10-10T17:35:42Z"));
  const headings = report.split("\n").filter((line) => line.startsWith("#"));

  assert.deepEqual(headings, ["# Apple Build Command Report", "## Summary", "## Errors", "## Standard output", "## Standard error"]);
  const errors = report.split("## Errors")[1].split("## Standard output")[0];
  assert.match(errors, /error: The file “sample-helper” couldn’t be opened\./);
  assert.match(errors, /CpResource sample-helper/);
  assert.doesNotMatch(errors, /Compiling A\.swift/);
});

test("View Build Command Report opens the report through the document opener when given one", async function () {
  const opened = [];
  const environment = makeEnvironment();
  environment.dependencies.openDocument = async (markdown, appName, title) => { opened.push({ appName, title, markdown }); return true; };
  const runner = new DirectActionRunner(environment.dependencies);
  await runner.run("build");
  environment.processes[0].emitExit(0);
  environment.panels.at(-1).callback(0);
  await settle();

  assert.equal(opened.length, 1);
  assert.equal(opened[0].appName, "App");
  assert.equal(opened[0].title, "Apple Build Command Report");
  assert.match(opened[0].markdown, /^# Apple Build Command Report/);
  assert.deepEqual(environment.documents, []);
});
