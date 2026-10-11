const test = require("node:test");
const assert = require("node:assert/strict");

test("choice wrapper resolves null on cancellation", async function () {
  const { choose } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: null, index: -1 });

  assert.equal(await choose(workspace, ["One"], "Choose one"), null);
  assert.deepEqual(workspace.paletteCalls, [
    [["One"], { placeholder: "Choose one" }]
  ]);
});

test("choice wrapper treats Nova's undefined empty-choice callback as cancellation", async function () {
  const { choose } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: undefined, index: undefined });

  assert.equal(await choose(workspace, [], "Choose one"), null);
});

test("Select Xcode uses Swift label and saves only confirmed choice", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({
    choice: "Xcode 27.0, build 27A266a — /Applications/Xcode 27 rc.app/Contents/Developer",
    index: 0
  });
  const store = makeStore();
  const helper = makeHelper({
    toolchains: [{
      version: "27.0",
      build: "27A266a",
      developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
      label: "Xcode 27.0, build 27A266a — /Applications/Xcode 27 rc.app/Contents/Developer"
    }]
  });
  const controller = new NovaController({ helper, store, workspace, reloadTasks() {} });

  await controller.selectXcode();

  assert.deepEqual(helper.calls[0], ["toolchains", {
    applications: "/Applications",
    "saved-developer-directory": "/Applications/Xcode 27 rc.app/Contents/Developer"
  }]);
  assert.deepEqual(store.calls, [
    ["selectDeveloperDirectory", "/Applications/Xcode 27 rc.app/Contents/Developer"]
  ]);
});

test("Select Xcode resolves the displayed choice when Nova omits the optional index", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const label = "Xcode 27.0, build 27A266a — /Applications/Xcode 27 rc.app/Contents/Developer";
  const workspace = makeWorkspace({ choice: label });
  const store = makeStore();
  const helper = makeHelper({ toolchains: [{
    version: "27.0",
    build: "27A266a",
    developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
    label
  }] });
  const controller = new NovaController({ helper, store, workspace, reloadTasks() {} });

  await controller.selectXcode();

  assert.deepEqual(store.calls, [
    ["selectDeveloperDirectory", "/Applications/Xcode 27 rc.app/Contents/Developer"]
  ]);
  assert.deepEqual(workspace.errors, []);
});

test("cancelled palette leaves previous selection untouched", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: null, index: -1 });
  const store = makeStore();
  const helper = makeHelper({ containers: [
    { kind: "project", path: "/repo/App.xcodeproj", label: "App.xcodeproj" }
  ] });
  const controller = new NovaController({ helper, store, workspace, reloadTasks() {} });

  await controller.selectContainer();

  assert.deepEqual(store.calls, []);
});

test("changing project selection refreshes the Project Navigator", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: "Project: App.xcodeproj", index: 0 });
  const store = makeStore();
  const helper = makeHelper({ containers: [
    { kind: "project", path: "/repo/App.xcodeproj", label: "App.xcodeproj" }
  ] });
  let navigatorReloads = 0;
  const controller = new NovaController({
    helper,
    store,
    workspace,
    reloadTasks() {},
    reloadNavigator() { navigatorReloads += 1; }
  });

  await controller.selectContainer();

  assert.equal(navigatorReloads, 1);
});

test("external worktree choice uses Nova's native file chooser", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: "Choose a project or workspace path…", index: 1 });
  workspace.fileChooserResult = [
    "/Users/example/Developer/Swift/Sample-Reader/.worktrees/feature-branch/SampleReader.xcodeproj"
  ];
  const store = makeStore();
  const controller = new NovaController({
    helper: makeHelper({ containers: [{ kind: "project", path: "/repo/App.xcodeproj", label: "App.xcodeproj" }] }),
    store,
    workspace,
    reloadTasks() {}
  });

  await controller.selectContainer();

  assert.deepEqual(workspace.fileChooserCalls, [[
    "Choose an Xcode project or workspace anywhere on disk.",
    {
      prompt: "Choose",
      allowFiles: true,
      allowFolders: true,
      allowMultiple: false,
      relative: false
    }
  ]]);
  assert.deepEqual(store.calls, [[
    "selectContainer",
    {
      kind: "project",
      path: "/Users/example/Developer/Swift/Sample-Reader/.worktrees/feature-branch/SampleReader.xcodeproj",
      label: "SampleReader.xcodeproj"
    }
  ]]);
});

test("selection commands invoke corresponding helper subcommands", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: "first", index: 0 });
  const store = makeStore();
  const helper = makeHelper({
    containers: [{ kind: "project", path: "/repo/App.xcodeproj", label: "App.xcodeproj" }],
    schemes: ["App"],
    configurations: ["Debug"],
    destinations: [{ label: "My Mac", specifier: "platform=macOS" }]
  });
  const controller = new NovaController({ helper, store, workspace, reloadTasks() {} });

  await controller.selectContainer();
  await controller.selectScheme();
  await controller.selectConfiguration();
  await controller.selectDestination();

  assert.deepEqual(helper.calls.map((call) => call[0]), [
    "containers", "schemes", "configurations", "destinations"
  ]);
  assert.deepEqual(workspace.paletteCalls.map((call) => call[0]), [
    ["Project: App.xcodeproj", "Choose a project or workspace path…"],
    ["App"],
    ["Debug"],
    ["My Mac"]
  ]);
});

test("string selections use the displayed choice when Nova omits the optional index", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: "Release" });
  const store = makeStore();
  const controller = new NovaController({
    helper: makeHelper({ configurations: ["Debug", "Release"] }),
    store,
    workspace,
    reloadTasks() {}
  });

  await controller.selectConfiguration();

  assert.deepEqual(store.calls, [["selectConfiguration", "Release"]]);
  assert.deepEqual(workspace.errors, []);
});

test("saved external worktree drives later metadata queries from its parent", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: "App" });
  const store = makeStore({
    containerPath: "/Users/example/Developer/Swift/Sample-Reader/.worktrees/feature-branch/App.xcodeproj"
  });
  const helper = makeHelper({ schemes: ["App"] });
  const controller = new NovaController({ helper, store, workspace, reloadTasks() {} });

  await controller.selectScheme();

  assert.equal(
    helper.calls[0][1]["workspace-root"],
    "/Users/example/Developer/Swift/Sample-Reader/.worktrees/feature-branch"
  );
});

test("empty destination list announces the selected scheme without opening a palette", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: null, index: -1 });
  const store = makeStore();
  const controller = new NovaController({
    helper: makeHelper({ destinations: [] }), store, workspace, reloadTasks() {}
  });

  await controller.selectDestination();

  assert.deepEqual(workspace.paletteCalls, []);
  assert.deepEqual(store.calls, []);
  assert.deepEqual(workspace.messages, [
    "No compatible build destinations were found for the selected scheme: App."
  ]);
});

test("refresh updates a matching simulator label without switching devices", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: null, index: -1 });
  const specifier = "platform=iOS Simulator,id=SIM-A";
  const destination = {
    label: "iPhone 17 — iOS Simulator 27.0, SIM-A", specifier
  };
  const store = makeStore({
    destinationLabel: "iPhone 17 — iOS Simulator 26.5, SIM-A",
    destinationSpecifier: specifier
  });
  store.refreshDestinationLabel = function (value) {
    this.calls.push(["refreshDestinationLabel", value]);
    return true;
  };
  const helper = makeHelper({
    toolchains: [{ developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer" }],
    containers: [{ kind: "project", path: "/repo/App.xcodeproj" }],
    schemes: ["App"], configurations: ["Debug"], destinations: [destination]
  });
  let reloads = 0;
  const controller = new NovaController({
    helper, store, workspace, reloadTasks() { reloads += 1; }
  });

  await controller.refreshChoices();

  assert.deepEqual(store.calls, [["refreshDestinationLabel", destination]]);
  assert.equal(store.savedSelection().destinationSpecifier, specifier);
  assert.equal(reloads, 1);
  assert.deepEqual(workspace.messages, [
    "Build choices refreshed. Destination label updated to iPhone 17 — iOS Simulator 27.0, SIM-A."
  ]);
});

test("refresh clears a disconnected saved destination without choosing another", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: null, index: -1 });
  const store = makeStore({
    destinationLabel: "iPhone 17 — iOS Simulator 27.0, SIM-A",
    destinationSpecifier: "platform=iOS Simulator,id=SIM-A"
  });
  store.clearFrom = function (level) {
    this.calls.push(["clearFrom", level]);
    return [
      { key: "destinationLabel", value: "iPhone 17 — iOS Simulator 27.0, SIM-A" },
      { key: "destinationSpecifier", value: "platform=iOS Simulator,id=SIM-A" }
    ];
  };
  const helper = makeHelper({
    toolchains: [{ developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer" }],
    containers: [{ kind: "project", path: "/repo/App.xcodeproj" }],
    schemes: ["App"], configurations: ["Debug"],
    destinations: [{ label: "My Mac", specifier: "platform=macOS" }]
  });
  let reloads = 0;
  const controller = new NovaController({
    helper, store, workspace, reloadTasks() { reloads += 1; }
  });

  await controller.refreshChoices();

  assert.deepEqual(store.calls, [["clearFrom", "destination"]]);
  assert.equal(reloads, 1);
  assert.deepEqual(workspace.messages, [
    "Cleared stale build choices:\n"
      + "1. Destination label: iPhone 17 — iOS Simulator 27.0, SIM-A\n"
      + "2. Destination specifier: platform=iOS Simulator,id=SIM-A"
  ]);
  assert.deepEqual(workspace.paletteCalls, []);
});

test("initialization adopts only the exact verified Xcode 27 RC", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: null, index: -1 });
  const store = makeStore({ developerDirectory: null });
  const helper = makeHelper({ toolchains: [
    {
      version: "27.0",
      build: "27A999",
      developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
      label: "Wrong build"
    },
    {
      version: "27.0",
      build: "27A266a",
      developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
      label: "Exact"
    }
  ] });
  let reloadCount = 0;
  const controller = new NovaController({
    helper,
    store,
    workspace,
    reloadTasks() { reloadCount += 1; }
  });

  await controller.initializeDefaultToolchain();

  assert.deepEqual(store.calls, [[
    "selectDeveloperDirectory", "/Applications/Xcode 27 rc.app/Contents/Developer"
  ]]);
  assert.equal(reloadCount, 1);
});

test("refresh clears a stale scheme and names every dependent value", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: null, index: -1 });
  const store = makeStore();
  store.clearFrom = function (level) {
    this.calls.push(["clearFrom", level]);
    return [
      { key: "scheme", value: "App" },
      { key: "configuration", value: "Debug" },
      { key: "destinationLabel", value: "My Mac" },
      { key: "destinationSpecifier", value: "platform=macOS" }
    ];
  };
  const helper = makeHelper({
    toolchains: [{ developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer" }],
    containers: [{ kind: "project", path: "/repo/App.xcodeproj" }],
    schemes: ["Other"],
    configurations: ["Debug"]
  });
  let reloadCount = 0;
  const controller = new NovaController({
    helper,
    store,
    workspace,
    reloadTasks() { reloadCount += 1; }
  });

  await controller.refreshChoices();

  assert.deepEqual(helper.calls.map((call) => call[0]), [
    "toolchains", "containers", "schemes", "configurations"
  ]);
  assert.deepEqual(store.calls, [["clearFrom", "scheme"]]);
  assert.equal(reloadCount, 1);
  assert.deepEqual(workspace.messages, [
    "Cleared stale build choices:\n"
      + "1. Scheme: App\n"
      + "2. Configuration: Debug\n"
      + "3. Destination label: My Mac\n"
      + "4. Destination specifier: platform=macOS"
  ]);
});

test("show current choices displays the Swift-formatted message unchanged", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const workspace = makeWorkspace({ choice: null, index: -1 });
  const store = makeStore();
  const message = "Xcode: Xcode 27.0, build 27A266a\nScheme: App";
  const helper = makeHelper({ "current-selection": message });
  const controller = new NovaController({ helper, store, workspace, reloadTasks() {} });

  await controller.showCurrentBuildChoices();

  assert.equal(helper.calls[0][0], "current-selection");
  assert.deepEqual(JSON.parse(helper.calls[0][1]["selection-json"]), store.savedSelection());
  assert.deepEqual(workspace.messages, [message]);
});

function makeWorkspace(paletteResult) {
  return {
    path: "/repo",
    paletteCalls: [],
    messages: [],
    errors: [],
    fileChooserCalls: [],
    fileChooserResult: null,
    showChoicePalette(labels, options, callback) {
      this.paletteCalls.push([labels, options]);
      callback(paletteResult.choice, paletteResult.index);
    },
    showInformativeMessage(message) { this.messages.push(message); },
    showErrorMessage(message) { this.errors.push(message); },
    showFileChooser(message, options, callback) {
      this.fileChooserCalls.push([message, options]);
      callback(this.fileChooserResult);
    }
  };
}

function makeStore(overrides = {}) {
  const selection = {
    developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
    containerKind: "project",
    containerPath: "/repo/App.xcodeproj",
    scheme: "App",
    configuration: "Debug",
    destinationLabel: "My Mac",
    destinationSpecifier: "platform=macOS",
    ...overrides
  };
  const calls = [];
  return {
    calls,
    savedSelection() { return { ...selection }; },
    selectDeveloperDirectory(value) { calls.push(["selectDeveloperDirectory", value]); return true; },
    selectContainer(value) { calls.push(["selectContainer", value]); return true; },
    selectScheme(value) { calls.push(["selectScheme", value]); return true; },
    selectConfiguration(value) { calls.push(["selectConfiguration", value]); return true; },
    selectDestination(value) { calls.push(["selectDestination", value]); return true; },
    clearFrom() { return []; }
  };
}

function makeHelper(values) {
  const calls = [];
  return {
    calls,
    async invoke(subcommand, options) {
      calls.push([subcommand, options]);
      return values[subcommand] || [];
    }
  };
}

function makeAnnouncer() {
  return { phrases: [], say(text) { this.phrases.push(text); return true; } };
}

test("each saved choice is confirmed out loud", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const announcer = makeAnnouncer();
  const store = makeStore();
  const helper = makeHelper({
    toolchains: [{ version: "27.0", build: "27A266a", developerDirectory: "/Applications/Xcode.app/Contents/Developer", label: "Xcode 27.0" }],
    containers: [{ kind: "project", path: "/repo/App.xcodeproj", label: "App.xcodeproj" }],
    schemes: ["App"],
    configurations: ["Debug"],
    destinations: [{ label: "Sam’s iPhone — iOS, arm64, DEVICE", specifier: "platform=iOS,id=DEVICE" }]
  });
  const controller = new NovaController({
    helper, store, workspace: makeWorkspace({ choice: "first", index: 0 }), announcer, reloadTasks() {}
  });

  await controller.selectXcode();
  await controller.selectContainer();
  await controller.selectScheme();
  await controller.selectConfiguration();
  await controller.selectDestination();

  assert.deepEqual(announcer.phrases, [
    "Xcode 27.0 selected.",
    "Project App.xcodeproj selected.",
    "Scheme App selected.",
    "Configuration Debug selected.",
    "Destination Sam’s iPhone selected."
  ]);
});

test("a cancelled choice is not announced", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const announcer = makeAnnouncer();
  const controller = new NovaController({
    helper: makeHelper({ schemes: ["App"] }),
    store: makeStore(),
    workspace: makeWorkspace({ choice: null, index: -1 }),
    announcer,
    reloadTasks() {}
  });

  await controller.selectScheme();

  assert.deepEqual(announcer.phrases, []);
});

test("choices that need Xcode or a project explain the missing step without calling the helper", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const cases = [
    [{ developerDirectory: null }, "selectScheme", "Choose Apple Build: Select Xcode first."],
    [{ containerPath: null, containerKind: null }, "selectConfiguration", "Choose Apple Build: Select Project or Workspace first."],
    [{ scheme: null }, "selectDestination", "Choose Apple Build: Select Scheme first."]
  ];
  for (const [overrides, method, message] of cases) {
    const workspace = makeWorkspace({ choice: "first", index: 0 });
    const helper = makeHelper({});
    const announcer = makeAnnouncer();
    const controller = new NovaController({
      helper, store: makeStore(overrides), workspace, announcer, reloadTasks() {}
    });

    await controller[method]();

    assert.deepEqual(helper.calls, [], method);
    assert.deepEqual(workspace.errors, [message], method);
    assert.deepEqual(announcer.phrases, [message], method);
  }
});

test("initialization adopts Xcode 27 RC after the app is renamed", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const store = makeStore({ developerDirectory: null });
  const controller = new NovaController({
    helper: makeHelper({ toolchains: [{
      version: "27.0",
      build: "27A266a",
      developerDirectory: "/Applications/Xcode.app/Contents/Developer",
      label: "Xcode 27.0"
    }] }),
    store,
    workspace: makeWorkspace({ choice: null, index: -1 }),
    reloadTasks() {}
  });

  await controller.initializeDefaultToolchain();

  assert.deepEqual(store.calls, [["selectDeveloperDirectory", "/Applications/Xcode.app/Contents/Developer"]]);
});

test("destination selection uses the displayed choice when Nova omits the optional index", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const store = makeStore();
  const destination = { label: "Sam’s iPhone — iOS, arm64, DEVICE", specifier: "platform=iOS,id=DEVICE" };
  const workspace = makeWorkspace({ choice: destination.label });
  const controller = new NovaController({
    helper: makeHelper({ destinations: [{ label: "My Mac", specifier: "platform=macOS" }, destination] }),
    store,
    workspace,
    reloadTasks() {}
  });

  await controller.selectDestination();

  assert.deepEqual(store.calls, [["selectDestination", destination]]);
  assert.deepEqual(workspace.errors, []);
});

test("every build choice uses the accessible chooser instead of Nova's palette when one is given", async function () {
  const { NovaController } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");
  const prompts = [];
  const chooser = { async choose(labels, prompt) { prompts.push(prompt); return { choice: labels[0], index: 0 }; } };
  const workspace = makeWorkspace({ choice: "first", index: 0 });
  const controller = new NovaController({
    helper: makeHelper({
      toolchains: [{ version: "27.0", build: "27A266a", developerDirectory: "/Applications/Xcode.app/Contents/Developer", label: "Xcode 27.0" }],
      containers: [{ kind: "project", path: "/repo/App.xcodeproj", label: "App.xcodeproj" }],
      schemes: ["App"], configurations: ["Debug"],
      destinations: [{ label: "My Mac", specifier: "platform=macOS" }]
    }),
    store: makeStore(), workspace, chooser, reloadTasks() {}
  });

  await controller.selectXcode();
  await controller.selectContainer();
  await controller.selectScheme();
  await controller.selectConfiguration();
  await controller.selectDestination();

  assert.deepEqual(prompts, [
    "Select Xcode", "Select a project or workspace", "Select a scheme",
    "Select a build configuration", "Select a build destination"
  ]);
  assert.deepEqual(workspace.paletteCalls, []);
});
