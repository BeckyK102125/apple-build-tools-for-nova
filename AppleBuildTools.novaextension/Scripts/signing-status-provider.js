const SECTION_IDENTIFIER = "apple-build-signing-status";
const REFRESH_COMMAND = "apple-build.refresh-signing-status";
const HELPER_COMMAND = "signing-status";
const { workspaceRootFor } = require("./workspace-root");

const REQUIRED_SELECTION_KEYS = [
  "developerDirectory",
  "containerKind",
  "containerPath",
  "scheme",
  "configuration",
  "destinationLabel",
  "destinationSpecifier"
];

const FIELD_DEFINITIONS = [
  ["bundleIdentifier", "Bundle identifier"],
  ["signingStyle", "Signing style"],
  ["developmentTeam", "Development team"],
  ["signingIdentity", "Signing identity"],
  ["signingAllowed", "Signing allowed"],
  ["signingRequired", "Signing required"],
  ["provisioningProfile", "Provisioning profile"],
  ["entitlements", "Entitlements"],
  ["sdkRoot", "SDK root"]
];

class SigningStatusProvider {
  constructor(dependencies) {
    this.helper = dependencies.helper;
    this.store = dependencies.store;
    this.workspace = dependencies.workspace;
    this.TreeItem = dependencies.TreeItem;
    this.states = dependencies.TreeItemCollapsibleState;
    this.onChange = dependencies.onChange || function () {};
    this.roots = [statusNode(
      "status:idle",
      "Activate Refresh to check Apple signing status.",
      "status"
    )];
    this.loadedKey = null;
    this.requestNumber = 0;
  }

  async getChildren(element) {
    return element ? (Array.isArray(element.children) ? element.children : []) : this.roots;
  }

  getParent(element) {
    return element && element.parent ? element.parent : null;
  }

  getTreeItem(element) {
    const hasChildren = Array.isArray(element.children) && element.children.length > 0;
    const state = hasChildren
      ? (element.kind === "root" ? this.states.Expanded : this.states.Collapsed)
      : this.states.None;
    const item = new this.TreeItem(element.name, state);
    item.identifier = element.identifier;
    item.contextValue = element.kind;
    item.descriptiveText = descriptionFor(element);
    return item;
  }

  showLoading() {
    this.setRoots([statusNode(
      "status:loading",
      "Loading Apple Signing Status…",
      "loading"
    )]);
  }

  async refresh() {
    const requestNumber = ++this.requestNumber;
    const selection = this.store.savedSelection();
    const selectionKey = keyFor(selection);
    this.loadedKey = null;
    this.showLoading();

    if (!isComplete(selection)) {
      if (requestNumber !== this.requestNumber) {
        return;
      }
      this.loadedKey = selectionKey;
      this.setRoots([statusNode(
        "status:incomplete-selection",
        "Select Xcode, project, scheme, configuration, and destination before checking signing status.",
        "status"
      )]);
      return;
    }

    try {
      const snapshot = await this.helper.invoke(HELPER_COMMAND, {
        "workspace-root": workspaceRootFor(this.workspace.path, selection),
        "selection-json": JSON.stringify(selection)
      });
      if (requestNumber !== this.requestNumber || keyFor(this.store.savedSelection()) !== selectionKey) {
        return;
      }
      this.loadedKey = selectionKey;
      this.setRoots(snapshotRoots(snapshot));
    } catch (error) {
      if (requestNumber !== this.requestNumber) {
        return;
      }
      this.loadedKey = selectionKey;
      const message = error && error.message ? error.message : String(error);
      this.setRoots([statusNode(`status:error:${requestNumber}`, `Error: ${message}`, "error")]);
    }
  }

  hasLoadedForCurrentSelection() {
    return this.loadedKey !== null && this.loadedKey === keyFor(this.store.savedSelection());
  }

  setRoots(roots) {
    this.roots = roots;
    roots.forEach((root) => attachParents(root, null));
    return Promise.resolve(this.onChange());
  }
}

class SigningStatusSidebar {
  constructor(dependencies) {
    let treeView;
    this.provider = new SigningStatusProvider({
      ...dependencies,
      onChange() {
        return treeView ? treeView.reload() : undefined;
      }
    });
    treeView = new dependencies.TreeView(SECTION_IDENTIFIER, {
      dataProvider: this.provider
    });
    this.treeView = treeView;
    this.visibilityDisposable = treeView.onDidChangeVisibility(() => {
      if (treeView.visible && !this.provider.hasLoadedForCurrentSelection()) {
        return this.refresh();
      }
      return undefined;
    });
  }

  refresh() {
    return this.provider.refresh();
  }

  dispose() {
    if (this.visibilityDisposable && typeof this.visibilityDisposable.dispose === "function") {
      this.visibilityDisposable.dispose();
    }
    if (this.treeView && typeof this.treeView.dispose === "function") {
      this.treeView.dispose();
    }
  }
}

function snapshotRoots(snapshot) {
  if (!snapshot || typeof snapshot !== "object" || !Array.isArray(snapshot.targets)) {
    throw new Error("AppleBuildHelper returned an invalid signing status snapshot.");
  }
  const overallStatus = normalizeStatus(snapshot.overallStatus);
  const targets = snapshot.targets
    .map((target) => targetNode(target))
    .sort((left, right) => left.sortName.localeCompare(right.sortName));
  return [withChildren(
    "signing-status:root",
    `Overall signing status: ${statusWord(overallStatus)}`,
    "root",
    [statusNode(
      `signing-status:overall:${overallStatus}`,
      overallDescription(overallStatus),
      "status"
    ), ...targets]
  )];
}

function targetNode(target) {
  if (!target || typeof target !== "object") {
    throw new Error("AppleBuildHelper returned an invalid signing target.");
  }
  const targetName = boundedText(target.targetName) || "Unnamed target";
  const status = normalizeStatus(target.status);
  const fields = FIELD_DEFINITIONS.map(([key, label]) => statusNode(
    `signing-status:${targetName}:${key}`,
    `${label}: ${fieldValue(key, target[key])}`,
    "field"
  ));
  fields.push(statusNode(
    `signing-status:${targetName}:status`,
    statusDescription(status),
    "status"
  ));
  return withChildren(
    `signing-status:target:${targetName}`,
    `Target: ${targetName} — ${statusWord(status)}`,
    "target",
    fields,
    targetName
  );
}

function fieldValue(key, value) {
  if (value === null || value === undefined || value === "") {
    return key === "developmentTeam" || key === "provisioningProfile"
      ? "Not configured"
      : "Not reported";
  }
  if (typeof value === "boolean") {
    return value ? "Yes" : "No";
  }
  return boundedText(value) || "Not reported";
}

function normalizeStatus(value) {
  const status = String(value || "").toLowerCase();
  if (!["ready", "warning", "unavailable", "error"].includes(status)) {
    throw new Error("AppleBuildHelper returned an invalid signing status.");
  }
  return status;
}

function statusWord(status) {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

function overallDescription(status) {
  return `Overall status: ${statusWord(status)}`;
}

function statusDescription(status) {
  const descriptions = {
    ready: "Status: Ready — configuration appears complete",
    warning: "Status: Warning — configuration may need attention",
    unavailable: "Status: Unavailable — signing is disabled or not applicable",
    error: "Status: Error — signing status could not be determined"
  };
  return descriptions[status];
}

function descriptionFor(element) {
  switch (element.kind) {
  case "root": return "Apple Signing Status overview";
  case "target": return "Signing status target; expand for named fields";
  case "field": return "Apple Signing Status field";
  case "loading": return "Apple Signing Status loading";
  case "error": return "Apple Signing Status error";
  default: return "Apple Signing Status status";
  }
}

function statusNode(identifier, name, kind) {
  return { identifier, name, kind, children: [] };
}

function withChildren(identifier, name, kind, children, sortName) {
  return {
    identifier,
    name,
    kind,
    children,
    sortName: sortName || name
  };
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

function isComplete(selection) {
  return REQUIRED_SELECTION_KEYS.every((key) => (
    selection && selection[key] !== null && selection[key] !== undefined && selection[key] !== ""
  ));
}

function keyFor(selection) {
  return JSON.stringify(REQUIRED_SELECTION_KEYS.map((key) => selection && selection[key]));
}

function boundedText(value) {
  if (typeof value !== "string") {
    return value === null || value === undefined ? null : String(value).slice(0, 256);
  }
  return value.slice(0, 256);
}

exports.HELPER_COMMAND = HELPER_COMMAND;
exports.REFRESH_COMMAND = REFRESH_COMMAND;
exports.SECTION_IDENTIFIER = SECTION_IDENTIFIER;
exports.SigningStatusProvider = SigningStatusProvider;
exports.SigningStatusSidebar = SigningStatusSidebar;
exports.snapshotRoots = snapshotRoots;
