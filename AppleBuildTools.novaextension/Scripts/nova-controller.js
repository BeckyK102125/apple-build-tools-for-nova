const INITIAL_XCODE = Object.freeze({
  version: "27.0",
  build: "27A266a",
  developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer"
});
const { workspaceRootFor } = require("./workspace-root");
const EXTERNAL_CONTAINER_CHOICE = "Choose a project or workspace path…";
const PREREQUISITE_COMMANDS = Object.freeze({
  developerDirectory: "Select Xcode",
  containerPath: "Select Project or Workspace",
  scheme: "Select Scheme"
});

const CLEARED_VALUE_LABELS = Object.freeze({
  developerDirectory: "Xcode developer directory",
  containerKind: "Container kind",
  containerPath: "Container path",
  scheme: "Scheme",
  configuration: "Configuration",
  destinationLabel: "Destination label",
  destinationSpecifier: "Destination specifier"
});

async function choose(workspace, labels, prompt, chooser) {
  if (chooser) {
    try {
      return await chooser.choose(labels, prompt);
    } catch (error) {
      // Fall back to Nova's palette so a chooser problem never blocks a selection.
    }
  }
  return new Promise(function (resolve) {
    workspace.showChoicePalette(labels, { placeholder: prompt }, function (choice, index) {
      resolve(choice == null ? null : { choice: choice, index: index });
    });
  });
}

function resolveSelected(items, selected, labelFor) {
  if (selected === null) {
    return null;
  }
  if (Number.isInteger(selected.index) && selected.index >= 0 && selected.index < items.length) {
    return items[selected.index];
  }
  const index = items.findIndex((item) => labelFor(item) === selected.choice);
  if (index === -1) {
    throw new Error(`The selected choice could not be matched: ${selected.choice}`);
  }
  return items[index];
}

class NovaController {
  constructor(dependencies) {
    this.helper = dependencies.helper;
    this.store = dependencies.store;
    this.workspace = dependencies.workspace;
    this.reloadTasks = dependencies.reloadTasks;
    this.reloadNavigator = dependencies.reloadNavigator || function () {};
    this.announcer = dependencies.announcer || { say() { return false; } };
    this.chooser = dependencies.chooser || null;
  }

  async selectXcode() {
    return this.runCommand(async () => {
      const saved = this.store.savedSelection();
      const toolchains = await this.helper.invoke("toolchains", toolchainOptions(saved));
      const selected = await choose(
        this.workspace,
        toolchains.map((toolchain) => toolchain.label),
        "Select Xcode",
        this.chooser
      );
      if (selected === null) {
        return;
      }
      const toolchain = resolveSelected(toolchains, selected, (item) => item.label);
      const changed = this.store.selectDeveloperDirectory(toolchain.developerDirectory);
      this.announcer.say(`Xcode ${toolchain.version} selected.`);
      this.reloadIfChanged(changed);
      this.reloadNavigatorIfChanged(changed);
    });
  }

  async selectContainer() {
    return this.runCommand(async () => {
      const containers = await this.helper.invoke("containers", {
        "workspace-root": this.workspace.path
      });
      const selected = await choose(
        this.workspace,
        containers
          .map((container) => `${container.kind === "workspace" ? "Workspace" : "Project"}: ${container.label}`)
          .concat(EXTERNAL_CONTAINER_CHOICE),
        "Select a project or workspace",
        this.chooser
      );
      if (selected === null) {
        return;
      }
      if (selected.choice === EXTERNAL_CONTAINER_CHOICE) {
        const paths = await chooseContainerPath(this.workspace);
        if (!paths || paths.length === 0) {
          return;
        }
        const container = containerFromPath(paths[0]);
        if (!container) {
          this.workspace.showErrorMessage(
            "Choose an Xcode project (.xcodeproj) or workspace (.xcworkspace)."
          );
          return;
        }
        const changed = this.store.selectContainer(container);
        this.announceContainer(container);
        this.reloadIfChanged(changed);
        this.reloadNavigatorIfChanged(changed);
        return;
      }
      const container = resolveSelected(
        containers,
        selected,
        (item) => `${item.kind === "workspace" ? "Workspace" : "Project"}: ${item.label}`
      );
      const changed = this.store.selectContainer(container);
      this.announceContainer(container);
      this.reloadIfChanged(changed);
      this.reloadNavigatorIfChanged(changed);
    });
  }

  async selectScheme() {
    return this.selectStringChoice({
      subcommand: "schemes",
      prompt: "Select a scheme",
      noun: "Scheme",
      save: (scheme) => this.store.selectScheme(scheme)
    });
  }

  async selectConfiguration() {
    return this.selectStringChoice({
      subcommand: "configurations",
      prompt: "Select a build configuration",
      noun: "Configuration",
      save: (configuration) => this.store.selectConfiguration(configuration)
    });
  }

  async selectDestination() {
    return this.runCommand(async () => {
      const saved = this.store.savedSelection();
      if (!this.ensureChosen(saved, ["developerDirectory", "containerPath", "scheme"])) {
        return;
      }
      const destinations = await this.helper.invoke("destinations", {
        ...containerOptions(workspaceRootFor(this.workspace.path, saved), saved),
        scheme: saved.scheme
      });
      if (destinations.length === 0) {
        this.workspace.showInformativeMessage(
          "No compatible build destinations were found for the selected scheme: "
            + saved.scheme + "."
        );
        return;
      }
      const selected = await choose(
        this.workspace,
        destinations.map((destination) => destination.label),
        "Select a build destination",
        this.chooser
      );
      if (selected === null) {
        return;
      }
      const destination = resolveSelected(destinations, selected, (item) => item.label);
      const changed = this.store.selectDestination(destination);
      this.announcer.say(`Destination ${spokenDestination(destination.label)} selected.`);
      this.reloadIfChanged(changed);
    });
  }

  async refreshChoices() {
    return this.runCommand(async () => {
      const saved = this.store.savedSelection();
      const toolchains = await this.helper.invoke("toolchains", toolchainOptions(saved));
      const containers = await this.helper.invoke("containers", {
        "workspace-root": workspaceRootFor(this.workspace.path, saved)
      });

      if (
        hasValue(saved.developerDirectory)
        && !toolchains.some((item) => item.developerDirectory === saved.developerDirectory)
      ) {
        return this.finishRefresh(this.store.clearFrom("developerDirectory"));
      }

      const hasSavedContainer = hasValue(saved.containerKind) || hasValue(saved.containerPath);
      const selectedContainerIsCurrent = containers.some((item) => (
        item.kind === saved.containerKind && item.path === saved.containerPath
      ));
      if (hasSavedContainer && !selectedContainerIsCurrent) {
        return this.finishRefresh(this.store.clearFrom("container"));
      }

      const canQueryContainer = hasValue(saved.developerDirectory) && selectedContainerIsCurrent;
      if (!canQueryContainer) {
        return this.finishRefresh([]);
      }

      const schemes = await this.helper.invoke(
        "schemes",
        containerOptions(workspaceRootFor(this.workspace.path, saved), saved)
      );
      const configurations = await this.helper.invoke(
        "configurations",
        containerOptions(workspaceRootFor(this.workspace.path, saved), saved)
      );

      if (hasValue(saved.scheme) && !schemes.includes(saved.scheme)) {
        return this.finishRefresh(this.store.clearFrom("scheme"));
      }
      if (hasValue(saved.configuration) && !configurations.includes(saved.configuration)) {
        return this.finishRefresh(this.store.clearFrom("configuration"));
      }

      if (!hasValue(saved.scheme) || !schemes.includes(saved.scheme)) {
        return this.finishRefresh([]);
      }

      const destinations = await this.helper.invoke("destinations", {
        ...containerOptions(workspaceRootFor(this.workspace.path, saved), saved),
        scheme: saved.scheme
      });
      const hasSavedDestination = (
        hasValue(saved.destinationLabel) || hasValue(saved.destinationSpecifier)
      );
      const matchingDestination = destinations.find(
        (item) => item.specifier === saved.destinationSpecifier
      );
      if (hasSavedDestination && !matchingDestination) {
        return this.finishRefresh(this.store.clearFrom("destination"));
      }
      if (matchingDestination && this.store.refreshDestinationLabel(matchingDestination)) {
        this.reloadTasks();
        this.workspace.showInformativeMessage(
          `Build choices refreshed. Destination label updated to ${matchingDestination.label}.`
        );
        return;
      }

      return this.finishRefresh([]);
    });
  }

  async showCurrentBuildChoices() {
    return this.runCommand(async () => {
      const message = await this.helper.invoke("current-selection", {
        "workspace-root": workspaceRootFor(this.workspace.path, this.store.savedSelection()),
        "selection-json": JSON.stringify(this.store.savedSelection())
      });
      this.workspace.showInformativeMessage(message);
    });
  }

  async initializeDefaultToolchain() {
    return this.runCommand(async () => {
      const saved = this.store.savedSelection();
      if (hasValue(saved.developerDirectory)) {
        return;
      }
      const toolchains = await this.helper.invoke("toolchains", toolchainOptions(saved));
      // Prefer the original install path, but still adopt the same build after the app is renamed.
      const sameBuild = (toolchain) => (
        toolchain.version === INITIAL_XCODE.version && toolchain.build === INITIAL_XCODE.build
      );
      const verified = toolchains.find((toolchain) => (
        sameBuild(toolchain) && toolchain.developerDirectory === INITIAL_XCODE.developerDirectory
      )) || toolchains.find(sameBuild);
      if (verified) {
        this.reloadIfChanged(this.store.selectDeveloperDirectory(verified.developerDirectory));
      }
    });
  }

  async selectStringChoice(options) {
    return this.runCommand(async () => {
      const saved = this.store.savedSelection();
      if (!this.ensureChosen(saved, ["developerDirectory", "containerPath"])) {
        return;
      }
      const values = await this.helper.invoke(
        options.subcommand,
        containerOptions(workspaceRootFor(this.workspace.path, saved), saved)
      );
      const selected = await choose(this.workspace, values, options.prompt, this.chooser);
      if (selected === null) {
        return;
      }
      const value = resolveSelected(values, selected, (item) => item);
      const changed = options.save(value);
      this.announcer.say(`${options.noun} ${value} selected.`);
      this.reloadIfChanged(changed);
    });
  }

  // Explains the first missing earlier step instead of passing an incomplete request to the helper.
  ensureChosen(saved, keys) {
    const missing = keys.find((key) => !hasValue(saved[key]));
    if (!missing) {
      return true;
    }
    const message = `Choose Apple Build: ${PREREQUISITE_COMMANDS[missing]} first.`;
    this.workspace.showErrorMessage(message);
    this.announcer.say(message);
    return false;
  }

  announceContainer(container) {
    const kind = container.kind === "workspace" ? "Workspace" : "Project";
    this.announcer.say(`${kind} ${container.label} selected.`);
  }

  finishRefresh(cleared) {
    if (cleared.length === 0) {
      this.workspace.showInformativeMessage(
        "Build choices refreshed. No saved choices were cleared."
      );
      return;
    }

    const details = cleared.map((item, index) => (
      `${index + 1}. ${CLEARED_VALUE_LABELS[item.key]}: ${item.value}`
    ));
    this.workspace.showInformativeMessage(`Cleared stale build choices:\n${details.join("\n")}`);
    this.reloadTasks();
    if (cleared.some((item) => [
      "developerDirectory", "containerKind", "containerPath"
    ].includes(item.key))) {
      this.reloadNavigator();
    }
  }

  reloadIfChanged(changed) {
    if (changed) {
      this.reloadTasks();
    }
  }

  reloadNavigatorIfChanged(changed) {
    if (changed) {
      this.reloadNavigator();
    }
  }

  async runCommand(operation) {
    try {
      return await operation();
    } catch (error) {
      this.workspace.showErrorMessage(error && error.message ? error.message : String(error));
      return undefined;
    }
  }
}

function toolchainOptions(saved) {
  const options = { applications: "/Applications" };
  if (hasValue(saved.developerDirectory)) {
    options["saved-developer-directory"] = saved.developerDirectory;
  }
  return options;
}

function containerOptions(workspaceRoot, saved) {
  return {
    "workspace-root": workspaceRoot,
    "developer-directory": saved.developerDirectory,
    "container-kind": saved.containerKind,
    "container-path": saved.containerPath
  };
}

// Destination labels end with platform, architecture, and device ID; speak only the name.
function spokenDestination(label) {
  return String(label).split(" — ")[0];
}

function hasValue(value) {
  return value !== null && value !== undefined && value !== "";
}

function chooseContainerPath(workspace) {
  return new Promise(function (resolve) {
    workspace.showFileChooser(
      "Choose an Xcode project or workspace anywhere on disk.",
      {
        prompt: "Choose",
        allowFiles: true,
        allowFolders: true,
        allowMultiple: false,
        relative: false
      },
      resolve
    );
  });
}

function containerFromPath(path) {
  if (typeof path !== "string" || !path.startsWith("/")) {
    return null;
  }
  const normalized = path.replace(/\/+$/, "");
  if (normalized.endsWith(".xcodeproj")) {
    return { kind: "project", path: normalized, label: basename(normalized) };
  }
  if (normalized.endsWith(".xcworkspace")) {
    return { kind: "workspace", path: normalized, label: basename(normalized) };
  }
  return null;
}

function basename(path) {
  return path.slice(path.lastIndexOf("/") + 1);
}

exports.INITIAL_XCODE = INITIAL_XCODE;
exports.NovaController = NovaController;
exports.choose = choose;
exports.resolveSelected = resolveSelected;
exports.containerFromPath = containerFromPath;
exports.workspaceRootFor = workspaceRootFor;
