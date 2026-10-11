const assert = require("node:assert/strict");
const test = require("node:test");
const { AppReportsController } = require("../AppleBuildTools.novaextension/Scripts/app-reports-controller");
const { HelperDomainError } = require("../AppleBuildTools.novaextension/Scripts/helper-client");

const IPHONE = {
  developerDirectory: "/Applications/Xcode.app/Contents/Developer", containerKind: "project",
  containerPath: "/repo/App.xcodeproj", scheme: "App", configuration: "Debug",
  destinationLabel: "Sam’s iPhone — iOS, arm64e, DEVICE", destinationSpecifier: "platform=iOS,id=DEVICE"
};

function makeController(options = {}) {
  const phrases = [], errors = [], opened = [], palettes = [], calls = [], readerCalls = [];
  const helper = {
    async invoke(subcommand, invokeOptions, input) {
      calls.push({ subcommand, options: invokeOptions, input });
      if (options.helperError) throw options.helperError;
      if (subcommand === "app-reports") return options.reports || [];
      return "/logs/Sample Reader/file.md";
    }
  };
  const workspace = {
    path: "/repo",
    showErrorMessage(message) { errors.push(message); },
    showChoicePalette(labels, paletteOptions, callback) {
      palettes.push(labels);
      callback(options.pick === undefined ? labels[0] : options.pick, options.pick === null ? -1 : 0);
    },
    openFile(path) { opened.push(path); return Promise.resolve({}); }
  };
  const session = options.session === undefined ? {
    selection: IPHONE, workspaceRoot: "/repo",
    snapshot() { return { appName: "Sample Reader", lines: ["hi"] }; }
  } : options.session;
  class FakeProcess {
    constructor(command, processOptions) {
      readerCalls.push({ command, args: processOptions.args });
      this.shell = processOptions.shell;
    }
    onDidExit(handler) { this.exit = handler; return { dispose() {} }; }
    start() { queueMicrotask(() => this.exit(options.readerStatus ?? 0)); }
  }
  const controller = new AppReportsController({
    helper, workspace,
    Process: FakeProcess,
    readerPath: "/ext/Executables/Apple Build Reader.app",
    store: { savedSelection() { return options.selection || IPHONE; } },
    announcer: { say(text) { phrases.push(text); return true; } },
    runner: { consoleSession() { return session; } }
  });
  return { controller, phrases, errors, opened, palettes, calls, readerCalls };
}

test("Show App Console writes the snapshot through standard input and opens the file", async function () {
  const { controller, calls, opened, phrases, readerCalls } = makeController();
  await controller.showAppConsole();

  assert.equal(calls[0].subcommand, "write-console");
  assert.deepEqual(JSON.parse(calls[0].input), { appName: "Sample Reader", lines: ["hi"] });
  assert.deepEqual(readerCalls, [{
    command: "/usr/bin/open",
    args: ["-a", "/ext/Executables/Apple Build Reader.app", "/logs/Sample Reader/file.md"]
  }]);
  assert.deepEqual(opened, []);
  assert.deepEqual(phrases, ["App Console ready."]);
});

test("Show App Console before any run explains the next step", async function () {
  const { controller, errors, phrases, calls } = makeController({ session: null });
  await controller.showAppConsole();
  assert.deepEqual(errors, ["No App Console yet. Use Build and Run first."]);
  assert.deepEqual(phrases, errors);
  assert.deepEqual(calls, []);
});

test("Show App Reports lists plain labels, opens the chosen report, and speaks", async function () {
  const { controller, palettes, calls, opened, phrases } = makeController({ reports: [
    { source: "Retired/App.diskwrites_resource-2026-10-07-064709.ips", kind: "diskWrites", label: "Too much disk writing, October 7 at 6:47 AM" },
    { source: "Retired/App-2026-10-07-063830.ips", kind: "crash", label: "Crash, October 7 at 6:38 AM" }
  ] });
  await controller.showAppReports();

  assert.deepEqual(palettes, [["Too much disk writing, October 7 at 6:47 AM", "Crash, October 7 at 6:38 AM"]]);
  assert.equal(calls[1].subcommand, "app-report");
  assert.equal(calls[1].options.source, "Retired/App.diskwrites_resource-2026-10-07-064709.ips");
  assert.deepEqual(opened, []);
  assert.deepEqual(phrases, ["Report ready."]);
});

test("Show App Reports handles no reports, cancellation, non-iPhone, and helper errors", async function () {
  let result = makeController({ reports: [] });
  await result.controller.showAppReports();
  assert.deepEqual(result.errors, ["No problem reports for App on Sam’s iPhone."]);
  assert.deepEqual(result.palettes, []);

  result = makeController({ reports: [{ source: "a.ips", label: "Crash, October 7 at 6:38 AM" }], pick: null });
  await result.controller.showAppReports();
  assert.equal(result.calls.length, 1);
  assert.deepEqual(result.opened, []);

  result = makeController({ selection: { ...IPHONE, destinationSpecifier: "generic/platform=iOS" } });
  await result.controller.showAppReports();
  assert.deepEqual(result.errors, ["App Reports needs a specific destination: your iPhone, My Mac, or a Simulator. Choose Apple Build: Select Destination."]);

  result = makeController({ helperError: new HelperDomainError(["Your iPhone is not reachable. Unlock it, connect it, and make sure it trusts this Mac."]) });
  await result.controller.showAppReports();
  assert.deepEqual(result.errors, ["Your iPhone is not reachable. Unlock it, connect it, and make sure it trusts this Mac."]);
  assert.deepEqual(result.phrases, result.errors);
});

test("technical helper failures become one plain sentence", async function () {
  let result = makeController({ helperError: new Error("AppleBuildHelper returned a response that was not one JSON object.") });
  await result.controller.showAppReports();
  assert.deepEqual(result.errors, ["Apple Build Tools could not read the reports from your iPhone."]);
  assert.deepEqual(result.phrases, result.errors);

  result = makeController({ helperError: new Error("The file “x” couldn’t be opened.") });
  await result.controller.showAppConsole();
  assert.deepEqual(result.errors, ["The App Console could not be saved."]);
});

test("if the reader cannot open, the document opens in Nova and says why", async function () {
  const { controller, opened, errors, phrases } = makeController({ readerStatus: 1 });
  await controller.showAppConsole();

  assert.deepEqual(opened, ["/logs/Sample Reader/file.md"]);
  assert.deepEqual(errors, ["The reader could not open, so the document opened in Nova."]);
  assert.deepEqual(phrases, ["The reader could not open, so the document opened in Nova."]);
});

test("Show App Reports works for My Mac and Simulator destinations too", async function () {
  for (const destinationSpecifier of ["platform=macOS,arch=arm64e,id=MAC", "platform=iOS Simulator,id=SIM"]) {
    const { controller, calls, errors } = makeController({
      selection: { ...IPHONE, destinationLabel: "My Mac — macOS", destinationSpecifier },
      reports: [{ source: "App-2026-10-07-063830.ips", label: "Crash, October 7 at 6:38 AM" }]
    });
    await controller.showAppReports();
    assert.deepEqual(errors, []);
    assert.equal(calls[0].subcommand, "app-reports");
    assert.equal(calls[1].subcommand, "app-report");
  }
});
