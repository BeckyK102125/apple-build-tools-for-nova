const test = require("node:test");
const assert = require("node:assert/strict");

const {
  HELPER_COMMAND,
  SECTION_IDENTIFIER,
  SigningStatusProvider,
  SigningStatusSidebar
} = require("../AppleBuildTools.novaextension/Scripts/signing-status-provider");

const states = { None: "none", Collapsed: "collapsed", Expanded: "expanded" };

test("signing status provider exposes deterministic accessible rows for a complete snapshot", async () => {
  const helper = makeHelper({
    overallStatus: "warning",
    targets: [{
      targetName: "Zeta",
      bundleIdentifier: "app.example.zeta",
      signingStyle: "Manual",
      developmentTeam: "Configured",
      signingIdentity: "Apple Development",
      signingAllowed: true,
      signingRequired: true,
      provisioningProfile: "Configured",
      entitlements: "Zeta/Zeta.entitlements",
      sdkRoot: "iphoneos",
      status: "warning"
    }, {
      targetName: "Alpha",
      bundleIdentifier: null,
      signingStyle: null,
      developmentTeam: null,
      signingIdentity: null,
      signingAllowed: false,
      signingRequired: false,
      provisioningProfile: null,
      entitlements: null,
      sdkRoot: null,
      status: "unavailable"
    }]
  });
  const provider = new SigningStatusProvider({
    helper,
    store: makeStore(),
    workspace: makeWorkspace(),
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });

  await provider.refresh();
  const root = (await provider.getChildren(null))[0];
  const targets = await provider.getChildren(root);

  assert.deepEqual(helper.calls, [[HELPER_COMMAND, {
    "workspace-root": "/repo",
    "selection-json": JSON.stringify(makeStore().savedSelection())
  }]]);
  assert.equal(root.name, "Overall signing status: Warning");
  assert.deepEqual(targets.map((row) => row.name), [
    "Overall status: Warning",
    "Target: Alpha — Unavailable",
    "Target: Zeta — Warning"
  ]);
  const alphaRows = await provider.getChildren(targets[1]);
  assert.deepEqual(alphaRows.map((row) => row.name), [
    "Bundle identifier: Not reported",
    "Signing style: Not reported",
    "Development team: Not configured",
    "Signing identity: Not reported",
    "Signing allowed: No",
    "Signing required: No",
    "Provisioning profile: Not configured",
    "Entitlements: Not reported",
    "SDK root: Not reported",
    "Status: Unavailable — signing is disabled or not applicable"
  ]);
  assert.equal(provider.getTreeItem(root).collapsibleState, states.Expanded);
  assert.equal(provider.getTreeItem(targets[1]).collapsibleState, states.Collapsed);
});

test("signing status provider exposes loading and incomplete states without invoking helper", async () => {
  const helper = makeHelper({});
  const provider = new SigningStatusProvider({
    helper,
    store: makeStore({ scheme: null }),
    workspace: makeWorkspace(),
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });

  provider.showLoading();
  assert.equal((await provider.getChildren(null))[0].name, "Loading Apple Signing Status…");
  await provider.refresh();
  assert.equal(
    (await provider.getChildren(null))[0].name,
    "Select Xcode, project, scheme, configuration, and destination before checking signing status."
  );
  assert.deepEqual(helper.calls, []);
});

test("signing status provider exposes helper errors as one readable error row", async () => {
  const provider = new SigningStatusProvider({
    helper: {
      async invoke() { throw new Error("The selected Xcode is no longer available."); }
    },
    store: makeStore(),
    workspace: makeWorkspace(),
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });

  await provider.refresh();
  const row = (await provider.getChildren(null))[0];
  assert.equal(row.name, "Error: The selected Xcode is no longer available.");
  assert.equal(provider.getTreeItem(row).descriptiveText, "Apple Signing Status error");
});

test("signing status provider names ready and target error states instead of relying on color", async () => {
  const provider = new SigningStatusProvider({
    helper: makeHelper({
      overallStatus: "error",
      targets: [{
        targetName: "App",
        status: "error",
        signingAllowed: true,
        signingRequired: true
      }]
    }),
    store: makeStore(),
    workspace: makeWorkspace(),
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });

  await provider.refresh();
  const root = (await provider.getChildren(null))[0];
  const rows = await provider.getChildren(root);
  assert.equal(root.name, "Overall signing status: Error");
  assert.equal(rows[0].name, "Overall status: Error");
  assert.equal(rows[1].name, "Target: App — Error");
  assert.equal((await provider.getChildren(rows[1])).at(-1).name,
    "Status: Error — signing status could not be determined");
});

test("signing status provider names a complete configuration Ready", async () => {
  const provider = new SigningStatusProvider({
    helper: makeHelper({
      overallStatus: "ready",
      targets: [{ targetName: "App", status: "ready" }]
    }),
    store: makeStore(),
    workspace: makeWorkspace(),
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });

  await provider.refresh();
  const root = (await provider.getChildren(null))[0];
  const target = (await provider.getChildren(root))[1];
  assert.equal(root.name, "Overall signing status: Ready");
  assert.equal(target.name, "Target: App — Ready");
  assert.equal((await provider.getChildren(target)).at(-1).name,
    "Status: Ready — configuration appears complete");
});

test("sidebar refresh replaces rows without requesting focus and disposes only its own resources", async () => {
  const workspace = makeWorkspace();
  const sidebar = new SigningStatusSidebar({
    helper: makeHelper({ overallStatus: "ready", targets: [] }),
    store: makeStore(),
    workspace,
    TreeView: FakeTreeView,
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });

  await sidebar.refresh();
  assert.equal(sidebar.treeView.identifier, SECTION_IDENTIFIER);
  assert.equal(sidebar.treeView.reloadCount, 2);
  assert.equal(workspace.focusCalls, 0);
  sidebar.dispose();
  assert.equal(sidebar.treeView.disposeCount, 1);
  assert.equal(sidebar.visibilityDisposable.disposed, true);
});

function makeStore(overrides = {}) {
  const selection = {
    developerDirectory: "/Applications/Xcode.app/Contents/Developer",
    containerKind: "project",
    containerPath: "/repo/App.xcodeproj",
    scheme: "App",
    configuration: "Debug",
    destinationLabel: "My Mac",
    destinationSpecifier: "platform=macOS",
    ...overrides
  };
  return { savedSelection() { return selection; } };
}

function makeWorkspace() {
  return { path: "/repo", focusCalls: 0 };
}

function makeHelper(value) {
  const calls = [];
  return {
    calls,
    async invoke(command, options) {
      calls.push([command, options]);
      return value;
    }
  };
}

class FakeTreeItem {
  constructor(name, collapsibleState) {
    this.name = name;
    this.collapsibleState = collapsibleState;
    this.command = null;
  }
}

class FakeTreeView {
  constructor(identifier, options) {
    this.identifier = identifier;
    this.dataProvider = options.dataProvider;
    this.reloadCount = 0;
    this.disposeCount = 0;
    this.visible = false;
  }

  reload() {
    this.reloadCount += 1;
    return Promise.resolve();
  }

  onDidChangeVisibility(callback) {
    this.visibilityCallback = callback;
    return { disposed: false, dispose() { this.disposed = true; } };
  }

  dispose() {
    this.disposeCount += 1;
  }
}
