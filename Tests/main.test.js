const test = require("node:test");
const assert = require("node:assert/strict");

test("activation registers build and navigator integrations and disposes them", async function () {
  FakeTreeView.disposalCount = 0;
  const main = require("../AppleBuildTools.novaextension/Scripts/main");
  const registeredCommands = [];
  const disposals = [];
  let registeredAssistant;
  const nova = {
    extension: { path: "/extension" },
    path: { join(...parts) { return parts.join("/"); } },
    workspace: {
      path: "/repo",
      config: makeConfiguration({
        "appleBuild.developerDirectory": "/Applications/Xcode 27 rc.app/Contents/Developer"
      }),
      reloadTasks() {},
      showChoicePalette() {},
      showInformativeMessage() {},
      showErrorMessage() {}
    },
    commands: {
      register(identifier, callback) {
        registeredCommands.push([identifier, callback]);
        return disposable(identifier, disposals);
      }
    },
    assistants: {
      registerTaskAssistant(assistant, options) {
        registeredAssistant = [assistant, options];
        return disposable(options.identifier, disposals);
      }
    },
    subscriptions: { add() {} }
  };

  await main.activateWith({
    nova,
    Process: class {},
    Task: FakeTask,
    TaskResolvableAction: class {},
    TaskProcessAction: class {},
    TreeView: FakeTreeView,
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: { None: 0, Collapsed: 1, Expanded: 2 }
  });

  assert.deepEqual(registeredCommands.map((entry) => entry[0]), [
    "apple-build.select-xcode",
    "apple-build.select-container",
    "apple-build.select-scheme",
    "apple-build.select-configuration",
    "apple-build.select-destination",
    "apple-build.refresh-choices",
    "apple-build.show-current-choices",
    "apple-build.refresh-project-navigator",
    "apple-build.open-project-navigator-file",
    "apple-build.refresh-signing-status",
    "apple-build.run-build",
    "apple-build.run-clean",
    "apple-build.run-tests",
    "apple-build.build-and-run",
    "apple-build.stop-action",
    "apple-build.show-app-console",
    "apple-build.show-app-reports"
  ]);
  assert.deepEqual(registeredAssistant[1], {
    identifier: "io.github.beckyk102125.AppleBuildTools.tasks",
    name: "Apple Build Tools"
  });
  assert.equal(FakeTreeView.lastCreated.reloadCount, 1);

  main.deactivate();
  assert.equal(disposals.length, 18);
  assert.equal(FakeTreeView.disposalCount, 2);
});

function disposable(identifier, disposals) {
  return { dispose() { disposals.push(identifier); } };
}

function makeConfiguration(initial) {
  const values = { ...initial };
  return {
    get(key) { return values[key] ?? null; },
    set(key, value) { values[key] = value; }
  };
}

class FakeTask {
  static Build = "build";
  constructor(name) { this.name = name; }
  setAction() {}
}

class FakeTreeItem {
  constructor(name, collapsibleState) {
    this.name = name;
    this.collapsibleState = collapsibleState;
  }
}

class FakeTreeView {
  constructor(identifier, options) {
    this.identifier = identifier;
    this.dataProvider = options.dataProvider;
    this.selection = [];
    this.reloadCount = 0;
    this.visible = false;
    FakeTreeView.lastCreated = this;
  }
  reload() { this.reloadCount += 1; return Promise.resolve(); }
  onDidChangeVisibility(callback) {
    this.visibilityCallback = callback;
    return { dispose() {} };
  }
  dispose() { FakeTreeView.disposalCount += 1; }
}
