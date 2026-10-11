const { workspaceRootFor } = require("./workspace-root");

class AppleBuildTaskAssistant {
  constructor(dependencies) {
    this.helper = dependencies.helper;
    this.store = dependencies.store;
    this.workspace = dependencies.workspace;
    this.Task = dependencies.Task;
    this.TaskResolvableAction = dependencies.TaskResolvableAction;
    this.TaskProcessAction = dependencies.TaskProcessAction;
  }

  provideTasks() {
    const selection = this.store.savedSelection();
    if (!isComplete(selection)) {
      return [];
    }

    const buildTask = new this.Task(`Apple Build: ${selection.scheme}`);
    buildTask.setAction(
      this.Task.Build,
      new this.TaskResolvableAction({ data: { purpose: "build" } })
    );
    buildTask.setAction(
      this.Task.Clean,
      new this.TaskResolvableAction({ data: { purpose: "clean" } })
    );

    const testTask = new this.Task(`Apple Test: ${selection.scheme}`);
    testTask.setAction(
      this.Task.Run,
      new this.TaskResolvableAction({ data: { purpose: "test" } })
    );
    return [buildTask, testTask];
  }

  async resolveTaskAction(context) {
    const approvedActions = new Map([
      [this.Task.Build, "build"],
      [this.Task.Clean, "clean"],
      [this.Task.Run, "test"]
    ]);
    const purpose = context && context.data && context.data.purpose;
    if (!context || approvedActions.get(context.action) !== purpose) {
      return null;
    }

    try {
      const specification = await this.helper.invoke("prepare-action", {
        action: purpose,
        "workspace-root": workspaceRootFor(this.workspace.path, this.store.savedSelection()),
        "selection-json": JSON.stringify(this.store.savedSelection())
      });
      return new this.TaskProcessAction(specification.command, {
        args: specification.arguments,
        env: specification.environment,
        cwd: specification.workingDirectory,
        shell: false,
        matchers: [
          "apple-xcode-error-diagnostic",
          "apple-xcode-warning-diagnostic"
        ]
      });
    } catch (error) {
      if (error && Array.isArray(error.errors)) {
        const details = error.errors.map((message, index) => `${index + 1}. ${message}`);
        this.workspace.showErrorMessage(`Preflight failed.\n${details.join("\n")}`);
      }
      throw error;
    }
  }
}

function isComplete(selection) {
  return [
    selection.developerDirectory,
    selection.containerKind,
    selection.containerPath,
    selection.scheme,
    selection.configuration,
    selection.destinationLabel,
    selection.destinationSpecifier
  ].every((value) => value !== null && value !== undefined && value !== "");
}

function missingSelectionLabels(selection) {
  const values = selection || {};
  const missing = [];
  if (!values.developerDirectory) {
    missing.push("Xcode (Apple Build: Select Xcode)");
  }
  if (!values.containerKind || !values.containerPath) {
    missing.push("project or workspace (Apple Build: Select Project or Workspace)");
  }
  if (!values.scheme) {
    missing.push("scheme (Apple Build: Select Scheme)");
  }
  if (!values.configuration) {
    missing.push("configuration (Apple Build: Select Configuration)");
  }
  if (!values.destinationLabel || !values.destinationSpecifier) {
    missing.push("destination (Apple Build: Select Destination)");
  }
  return missing;
}

exports.AppleBuildTaskAssistant = AppleBuildTaskAssistant;
exports.isComplete = isComplete;
exports.missingSelectionLabels = missingSelectionLabels;
