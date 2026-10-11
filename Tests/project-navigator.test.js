const test = require("node:test");
const assert = require("node:assert/strict");

const {
  OPEN_FILE_COMMAND,
  ProjectNavigator,
  ProjectNavigatorDataProvider
} = require("../AppleBuildTools.novaextension/Scripts/project-navigator");

test("provider loads the selected project and maps accessible native tree items", async function () {
  const helper = makeHelper({
    identifier: "project:/repo/App.xcodeproj",
    name: "App",
    kind: "project",
    path: "/repo/App.xcodeproj",
    children: [{
      identifier: "pbx:SOURCES",
      name: "Sources",
      kind: "group",
      path: "/repo/Sources",
      children: [{
        identifier: "pbx:FILE",
        name: "App.swift",
        kind: "file",
        path: "/repo/Sources/App.swift",
        children: []
      }]
    }]
  });
  const provider = makeProvider(helper);

  const roots = await provider.getChildren(null);
  const groups = await provider.getChildren(roots[0]);
  const files = await provider.getChildren(groups[0]);
  const rootItem = provider.getTreeItem(roots[0]);
  const groupItem = provider.getTreeItem(groups[0]);
  const fileItem = provider.getTreeItem(files[0]);

  assert.deepEqual(helper.calls, [["project-navigator", {
    "workspace-root": "/repo",
    "container-kind": "project",
    "container-path": "/repo/App.xcodeproj"
  }]]);
  assert.equal(rootItem.identifier, "project:/repo/App.xcodeproj");
  assert.equal(rootItem.collapsibleState, "expanded");
  assert.equal(rootItem.descriptiveText, "Xcode project");
  assert.equal(groupItem.collapsibleState, "collapsed");
  assert.equal(groupItem.descriptiveText, "Xcode group");
  assert.equal(fileItem.collapsibleState, "none");
  assert.equal(fileItem.descriptiveText, "Swift source file");
  assert.equal(fileItem.command, OPEN_FILE_COMMAND);
  assert.equal(fileItem.path, "/repo/Sources/App.swift");
  assert.equal(provider.getParent(files[0]), groups[0]);
});

test("provider exposes a readable status when no project is selected", async function () {
  const provider = new ProjectNavigatorDataProvider({
    helper: makeHelper(null),
    store: { savedSelection() { return { containerKind: null, containerPath: null }; } },
    workspace: makeWorkspace(),
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });

  const roots = await provider.getChildren(null);
  const item = provider.getTreeItem(roots[0]);

  assert.equal(item.name, "Select an Xcode project to show its source files.");
  assert.equal(item.descriptiveText, "Project Navigator status");
  assert.equal(item.command, null);
});

test("provider converts helper failures into a readable sidebar state", async function () {
  const helper = {
    async invoke() { throw new Error("The selected project could not be read."); }
  };
  const provider = makeProvider(helper);

  const roots = await provider.getChildren(null);
  const item = provider.getTreeItem(roots[0]);

  assert.equal(item.name, "The selected project could not be read.");
  assert.equal(item.descriptiveText, "Project Navigator error");
});

test("provider gives an empty project a readable child status", async function () {
  const provider = makeProvider(makeHelper({
    identifier: "project:/repo/Empty.xcodeproj",
    name: "Empty",
    kind: "project",
    path: "/repo/Empty.xcodeproj",
    children: []
  }));

  const roots = await provider.getChildren(null);
  const children = await provider.getChildren(roots[0]);

  assert.equal(children.length, 1);
  assert.equal(children[0].name, "No source groups or files were found in the selected project.");
  assert.equal(provider.getTreeItem(children[0]).descriptiveText, "Project Navigator status");
  assert.equal(provider.getParent(children[0]), roots[0]);
});

test("navigator refreshes and opens only the selected file leaf", async function () {
  const workspace = makeWorkspace();
  const navigator = new ProjectNavigator({
    helper: makeHelper(null),
    store: makeStore(),
    workspace,
    TreeView: FakeTreeView,
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });
  const file = { kind: "file", path: "/repo/App.swift", children: [] };

  navigator.treeView.selection = [file];
  await navigator.openSelectedFile();
  await navigator.refresh();
  navigator.treeView.selection = [{ kind: "group", path: "/repo", children: [file] }];
  await navigator.openSelectedFile();

  assert.deepEqual(workspace.openedFiles, ["/repo/App.swift"]);
  assert.equal(navigator.treeView.reloadCount, 1);
});

test("navigator reloads when its persisted sidebar becomes visible", async function () {
  const navigator = new ProjectNavigator({
    helper: makeHelper(null),
    store: makeStore(),
    workspace: makeWorkspace(),
    TreeView: FakeTreeView,
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });

  navigator.treeView.visible = true;
  await navigator.treeView.visibilityCallback();

  assert.equal(navigator.treeView.reloadCount, 1);
});

function makeProvider(helper) {
  return new ProjectNavigatorDataProvider({
    helper,
    store: makeStore(),
    workspace: makeWorkspace(),
    TreeItem: FakeTreeItem,
    TreeItemCollapsibleState: states
  });
}

function makeStore() {
  return {
    savedSelection() {
      return { containerKind: "project", containerPath: "/repo/App.xcodeproj" };
    }
  };
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

function makeWorkspace() {
  return {
    path: "/repo",
    openedFiles: [],
    errors: [],
    async openFile(path) { this.openedFiles.push(path); },
    showErrorMessage(message) { this.errors.push(message); }
  };
}

const states = { None: "none", Collapsed: "collapsed", Expanded: "expanded" };

class FakeTreeItem {
  constructor(name, collapsibleState = states.None) {
    this.name = name;
    this.collapsibleState = collapsibleState;
    this.command = null;
  }
}

class FakeTreeView {
  constructor(identifier, options) {
    this.identifier = identifier;
    this.dataProvider = options.dataProvider;
    this.selection = [];
    this.reloadCount = 0;
    this.visible = false;
  }

  reload() {
    this.reloadCount += 1;
    return Promise.resolve();
  }

  onDidChangeVisibility(callback) {
    this.visibilityCallback = callback;
    return { dispose() {} };
  }

  dispose() {}
}
