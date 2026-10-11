const SECTION_IDENTIFIER = "apple-build-project-navigator";
const OPEN_FILE_COMMAND = "apple-build.open-project-navigator-file";
const { workspaceRootFor } = require("./workspace-root");

class ProjectNavigatorDataProvider {
  constructor(dependencies) {
    this.helper = dependencies.helper;
    this.store = dependencies.store;
    this.workspace = dependencies.workspace;
    this.TreeItem = dependencies.TreeItem;
    this.states = dependencies.TreeItemCollapsibleState;
    this.rootPromise = null;
  }

  async getChildren(element) {
    if (element) {
      return Array.isArray(element.children) ? element.children : [];
    }
    if (!this.rootPromise) {
      this.rootPromise = this.loadRoots();
    }
    return this.rootPromise;
  }

  getParent(element) {
    return element.parent || null;
  }

  getTreeItem(element) {
    const hasChildren = Array.isArray(element.children) && element.children.length > 0;
    let collapsibleState = this.states.None;
    if (hasChildren) {
      collapsibleState = element.kind === "project"
        ? this.states.Expanded
        : this.states.Collapsed;
    }

    const item = new this.TreeItem(element.name, collapsibleState);
    item.identifier = element.identifier;
    item.contextValue = element.kind;
    item.descriptiveText = descriptionFor(element);
    if (element.path) {
      item.path = element.path;
      item.tooltip = element.path;
    }
    if (element.kind === "file" && element.path) {
      item.command = OPEN_FILE_COMMAND;
    }
    return item;
  }

  invalidate() {
    this.rootPromise = null;
  }

  async loadRoots() {
    const saved = this.store.savedSelection();
    if (!saved.containerKind || !saved.containerPath) {
      return [statusNode(
        "status:no-project",
        "Select an Xcode project to show its source files.",
        "status"
      )];
    }

    try {
      const root = await this.helper.invoke("project-navigator", {
        "workspace-root": workspaceRootFor(this.workspace.path, saved),
        "container-kind": saved.containerKind,
        "container-path": saved.containerPath
      });
      if (!root || typeof root !== "object" || !Array.isArray(root.children)) {
        throw new Error("AppleBuildHelper returned an invalid Project Navigator tree.");
      }
      if (root.children.length === 0) {
        root.children = [statusNode(
          "status:empty-project",
          "No source groups or files were found in the selected project.",
          "status"
        )];
      }
      attachParents(root, null);
      return [root];
    } catch (error) {
      const message = error && error.message ? error.message : String(error);
      return [statusNode("status:error", message, "error")];
    }
  }
}

class ProjectNavigator {
  constructor(dependencies) {
    this.workspace = dependencies.workspace;
    this.provider = new ProjectNavigatorDataProvider(dependencies);
    this.treeView = new dependencies.TreeView(SECTION_IDENTIFIER, {
      dataProvider: this.provider
    });
    this.visibilityDisposable = this.treeView.onDidChangeVisibility(() => {
      if (this.treeView.visible) {
        return this.refresh();
      }
      return undefined;
    });
  }

  async refresh() {
    this.provider.invalidate();
    return this.treeView.reload();
  }

  async openSelectedFile() {
    const selection = this.treeView.selection || [];
    const selected = selection[0];
    if (!selected || selected.kind !== "file" || !selected.path) {
      return;
    }
    try {
      await this.workspace.openFile(selected.path);
    } catch (error) {
      const detail = error && error.message ? error.message : String(error);
      this.workspace.showErrorMessage(`Could not open ${selected.name || "the selected file"}. ${detail}`);
    }
  }

  dispose() {
    this.visibilityDisposable.dispose();
    this.treeView.dispose();
  }
}

function attachParents(element, parent) {
  Object.defineProperty(element, "parent", {
    configurable: true,
    enumerable: false,
    writable: true,
    value: parent
  });
  for (const child of element.children || []) {
    attachParents(child, element);
  }
}

function statusNode(identifier, name, statusKind) {
  return {
    identifier,
    name,
    kind: statusKind,
    path: null,
    children: []
  };
}

function descriptionFor(element) {
  switch (element.kind) {
  case "project":
    return "Xcode project";
  case "group":
    return "Xcode group";
  case "folder":
    return "Folder";
  case "file":
    return fileDescription(element.path);
  case "error":
    return "Project Navigator error";
  default:
    return "Project Navigator status";
  }
}

function fileDescription(path) {
  const extension = String(path || "").split(".").pop().toLowerCase();
  const descriptions = {
    swift: "Swift source file",
    plist: "Property list",
    json: "JSON file",
    xcassets: "Asset catalog",
    strings: "Localization strings file",
    storyboard: "Storyboard",
    xib: "Interface file"
  };
  return descriptions[extension] || "File";
}

exports.OPEN_FILE_COMMAND = OPEN_FILE_COMMAND;
exports.ProjectNavigator = ProjectNavigator;
exports.ProjectNavigatorDataProvider = ProjectNavigatorDataProvider;
exports.SECTION_IDENTIFIER = SECTION_IDENTIFIER;
