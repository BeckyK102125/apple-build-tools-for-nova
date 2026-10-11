const { HelperClient } = require("./helper-client");
const { NovaController } = require("./nova-controller");
const { SelectionStore } = require("./selection-store");
const { AppleBuildTaskAssistant } = require("./task-assistant");
const { DirectActionRunner } = require("./direct-action-runner");
const { Announcer } = require("./announcer");
const { AppReportsController } = require("./app-reports-controller");
const { AccessibleChooser } = require("./accessible-chooser");
const { OPEN_FILE_COMMAND, ProjectNavigator } = require("./project-navigator");
const {
  REFRESH_COMMAND: REFRESH_SIGNING_STATUS_COMMAND,
  SigningStatusSidebar
} = require("./signing-status-provider");

const TASK_ASSISTANT_IDENTIFIER = "io.github.beckyk102125.AppleBuildTools.tasks";
let disposables = [];

exports.activate = function () {
  return activateWith({
    nova,
    Process,
    Task,
    TaskResolvableAction,
    TaskProcessAction,
    TreeView,
    TreeItem,
    TreeItemCollapsibleState
  });
};

async function activateWith(dependencies) {
  const novaAPI = dependencies.nova;
  const store = new SelectionStore(novaAPI.workspace.config);
  const helper = new HelperClient({ nova: novaAPI, Process: dependencies.Process });
  const announcer = new Announcer({ Process: dependencies.Process, config: novaAPI.config });
  const readerPath = novaAPI.path.join(novaAPI.extension.path, "Executables", "Apple Build Reader.app");
  const chooser = new AccessibleChooser({ helper, readerPath });
  const reloadTasks = function () {
    novaAPI.workspace.reloadTasks(TASK_ASSISTANT_IDENTIFIER);
  };
  const signingStatus = new SigningStatusSidebar({
    helper,
    store,
    workspace: novaAPI.workspace,
    TreeView: dependencies.TreeView,
    TreeItem: dependencies.TreeItem,
    TreeItemCollapsibleState: dependencies.TreeItemCollapsibleState
  });
  const projectNavigator = new ProjectNavigator({
    helper,
    store,
    workspace: novaAPI.workspace,
    TreeView: dependencies.TreeView,
    TreeItem: dependencies.TreeItem,
    TreeItemCollapsibleState: dependencies.TreeItemCollapsibleState
  });
  const controller = new NovaController({
    helper,
    store,
    workspace: novaAPI.workspace,
    reloadTasks,
    announcer,
    chooser,
    reloadNavigator() { return projectNavigator.refresh(); }
  });
  const assistant = new AppleBuildTaskAssistant({
    helper,
    store,
    workspace: novaAPI.workspace,
    Task: dependencies.Task,
    TaskResolvableAction: dependencies.TaskResolvableAction,
    TaskProcessAction: dependencies.TaskProcessAction
  });
  const directActions = new DirectActionRunner({
    helper,
    store,
    workspace: novaAPI.workspace,
    Process: dependencies.Process,
    announcer,
    // Saves the build report as a file and opens it in the reader (falls back to Nova inside openDocument).
    async openDocument(markdown, appName, title) {
      const path = await helper.invoke("write-document", { "app-name": appName, title }, markdown);
      await appReports.openDocument(path);
    }
  });
  const appReports = new AppReportsController({
    helper, store, workspace: novaAPI.workspace, announcer, runner: directActions,
    Process: dependencies.Process,
    readerPath,
    chooser
  });

  const commands = [
    ["apple-build.select-xcode", () => controller.selectXcode()],
    ["apple-build.select-container", () => controller.selectContainer()],
    ["apple-build.select-scheme", () => controller.selectScheme()],
    ["apple-build.select-configuration", () => controller.selectConfiguration()],
    ["apple-build.select-destination", () => controller.selectDestination()],
    ["apple-build.refresh-choices", () => controller.refreshChoices()],
    ["apple-build.show-current-choices", () => controller.showCurrentBuildChoices()],
    ["apple-build.refresh-project-navigator", () => projectNavigator.refresh()],
    [OPEN_FILE_COMMAND, () => projectNavigator.openSelectedFile()],
    [REFRESH_SIGNING_STATUS_COMMAND, () => signingStatus.refresh()],
    ["apple-build.run-build", () => directActions.run("build")],
    ["apple-build.run-clean", () => directActions.run("clean")],
    ["apple-build.run-tests", () => directActions.run("test")],
    ["apple-build.build-and-run", () => directActions.run("device")],
    ["apple-build.stop-action", () => directActions.stop()],
    ["apple-build.show-app-console", () => appReports.showAppConsole()],
    ["apple-build.show-app-reports", () => appReports.showAppReports()]
  ];
  for (const [identifier, callback] of commands) {
    disposables.push(novaAPI.commands.register(identifier, callback));
  }
  disposables.push(novaAPI.assistants.registerTaskAssistant(assistant, {
    identifier: TASK_ASSISTANT_IDENTIFIER,
    name: "Apple Build Tools"
  }));
  disposables.push(signingStatus);
  disposables.push(projectNavigator);

  await controller.initializeDefaultToolchain();
  await projectNavigator.refresh();
}

exports.deactivate = function () {
  disposables.forEach(function (item) {
    item.dispose();
  });
  disposables = [];
};

exports.activateWith = activateWith;
