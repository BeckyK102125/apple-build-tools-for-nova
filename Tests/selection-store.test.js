const test = require("node:test");
const assert = require("node:assert/strict");

const {
  CONFIG,
  SelectionStore
} = require("../AppleBuildTools.novaextension/Scripts/selection-store");

test("cancelled choices never write configuration", function () {
  const configuration = makeConfiguration({});
  const store = new SelectionStore(configuration);

  assert.equal(store.selectDeveloperDirectory(null), false);
  assert.equal(store.selectContainer(undefined), false);
  assert.equal(store.selectScheme(null), false);
  assert.equal(store.selectConfiguration(undefined), false);
  assert.equal(store.selectDestination(null), false);
  assert.deepEqual(configuration.calls, []);
});

test("changing Xcode clears container through destination", function () {
  const configuration = makeConfiguration(populatedValues());
  const store = new SelectionStore(configuration);

  assert.equal(store.selectDeveloperDirectory("/Applications/New.app/Contents/Developer"), true);

  assert.deepEqual(configuration.calls, [
    [CONFIG.developerDirectory, "/Applications/New.app/Contents/Developer"],
    [CONFIG.containerKind, null],
    [CONFIG.containerPath, null],
    [CONFIG.scheme, null],
    [CONFIG.configuration, null],
    [CONFIG.destinationLabel, null],
    [CONFIG.destinationSpecifier, null]
  ]);
});

test("changing container clears scheme through destination", function () {
  const configuration = makeConfiguration(populatedValues());
  const store = new SelectionStore(configuration);

  store.selectContainer({ kind: "workspace", path: "/repo/App.xcworkspace" });

  assert.deepEqual(configuration.calls, [
    [CONFIG.containerKind, "workspace"],
    [CONFIG.containerPath, "/repo/App.xcworkspace"],
    [CONFIG.scheme, null],
    [CONFIG.configuration, null],
    [CONFIG.destinationLabel, null],
    [CONFIG.destinationSpecifier, null]
  ]);
});

test("changing scheme clears configuration and destination", function () {
  const configuration = makeConfiguration(populatedValues());
  const store = new SelectionStore(configuration);

  store.selectScheme("NewScheme");

  assert.deepEqual(configuration.calls, [
    [CONFIG.scheme, "NewScheme"],
    [CONFIG.configuration, null],
    [CONFIG.destinationLabel, null],
    [CONFIG.destinationSpecifier, null]
  ]);
});

test("changing configuration clears destination", function () {
  const configuration = makeConfiguration(populatedValues());
  const store = new SelectionStore(configuration);

  store.selectConfiguration("Release");

  assert.deepEqual(configuration.calls, [
    [CONFIG.configuration, "Release"],
    [CONFIG.destinationLabel, null],
    [CONFIG.destinationSpecifier, null]
  ]);
});

test("saved selection contains only seven stable scalar values", function () {
  const configuration = makeConfiguration(populatedValues());

  assert.deepEqual(new SelectionStore(configuration).savedSelection(), {
    developerDirectory: "/Applications/Xcode.app/Contents/Developer",
    containerKind: "project",
    containerPath: "/repo/App.xcodeproj",
    scheme: "App",
    configuration: "Debug",
    destinationLabel: "My Mac",
    destinationSpecifier: "platform=macOS"
  });
});

test("reselecting the same values preserves dependent selections", function () {
  const configuration = makeConfiguration(populatedValues());
  const store = new SelectionStore(configuration);

  assert.equal(store.selectDeveloperDirectory("/Applications/Xcode.app/Contents/Developer"), false);
  assert.equal(store.selectContainer({ kind: "project", path: "/repo/App.xcodeproj" }), false);
  assert.equal(store.selectScheme("App"), false);
  assert.equal(store.selectConfiguration("Debug"), false);
  assert.equal(store.selectDestination({ label: "My Mac", specifier: "platform=macOS" }), false);
  assert.deepEqual(configuration.calls, []);
});

test("clearFrom returns every populated scalar it clears", function () {
  const configuration = makeConfiguration(populatedValues());
  const store = new SelectionStore(configuration);

  assert.deepEqual(store.clearFrom("scheme"), [
    { key: "scheme", value: "App" },
    { key: "configuration", value: "Debug" },
    { key: "destinationLabel", value: "My Mac" },
    { key: "destinationSpecifier", value: "platform=macOS" }
  ]);
  assert.deepEqual(configuration.calls, [
    [CONFIG.scheme, null],
    [CONFIG.configuration, null],
    [CONFIG.destinationLabel, null],
    [CONFIG.destinationSpecifier, null]
  ]);
});

test("refresh changes only the label for the same destination specifier", function () {
  const configuration = makeConfiguration({
    ...populatedValues(),
    [CONFIG.destinationLabel]: "iPhone 17 — iOS Simulator 26.5, SIM-A",
    [CONFIG.destinationSpecifier]: "platform=iOS Simulator,id=SIM-A"
  });
  const store = new SelectionStore(configuration);

  assert.equal(store.refreshDestinationLabel({
    label: "iPhone 17 — iOS Simulator 27.0, SIM-A",
    specifier: "platform=iOS Simulator,id=SIM-A"
  }), true);
  assert.deepEqual(configuration.calls, [[
    CONFIG.destinationLabel, "iPhone 17 — iOS Simulator 27.0, SIM-A"
  ]]);
  assert.equal(store.refreshDestinationLabel({
    label: "Other simulator", specifier: "platform=iOS Simulator,id=SIM-B"
  }), false);
  assert.equal(configuration.calls.length, 1);
});

function populatedValues() {
  return {
    [CONFIG.developerDirectory]: "/Applications/Xcode.app/Contents/Developer",
    [CONFIG.containerKind]: "project",
    [CONFIG.containerPath]: "/repo/App.xcodeproj",
    [CONFIG.scheme]: "App",
    [CONFIG.configuration]: "Debug",
    [CONFIG.destinationLabel]: "My Mac",
    [CONFIG.destinationSpecifier]: "platform=macOS"
  };
}

function makeConfiguration(initialValues) {
  const values = { ...initialValues };
  const calls = [];
  return {
    calls,
    get(key) { return values[key] ?? null; },
    set(key, value) {
      calls.push([key, value]);
      values[key] = value;
    }
  };
}
