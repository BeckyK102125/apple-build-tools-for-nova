const test = require("node:test");
const assert = require("node:assert/strict");

const { HelperDomainError } = require("../AppleBuildTools.novaextension/Scripts/helper-client");

test("incomplete selection contributes no task", function () {
  const { AppleBuildTaskAssistant } = require(
    "../AppleBuildTools.novaextension/Scripts/task-assistant"
  );
  const assistant = makeAssistant({ scheme: null });

  assert.deepEqual(assistant.provideTasks(), []);
});

test("complete selection contributes named build and test tasks using documented actions", function () {
  const { AppleBuildTaskAssistant } = require(
    "../AppleBuildTools.novaextension/Scripts/task-assistant"
  );
  const dependencies = makeDependencies();
  const assistant = new AppleBuildTaskAssistant(dependencies);

  const tasks = assistant.provideTasks();

  assert.equal(tasks.length, 2);
  assert.equal(tasks[0].name, "Apple Build: App");
  assert.equal(tasks[1].name, "Apple Test: App");
  const buildAction = tasks[0].getAction(FakeTask.Build);
  assert.ok(buildAction instanceof FakeTaskResolvableAction);
  assert.deepEqual(buildAction.options, { data: { purpose: "build" } });
  assert.deepEqual(tasks[0].getAction(FakeTask.Clean).options, {
    data: { purpose: "clean" }
  });
  assert.equal(tasks[0].getAction(FakeTask.Run), undefined);
  assert.equal(tasks[1].getAction(FakeTask.Build), undefined);
  assert.equal(tasks[1].getAction(FakeTask.Clean), undefined);
  assert.deepEqual(tasks[1].getAction(FakeTask.Run).options, {
    data: { purpose: "test" }
  });
});

test("each native action maps to exactly one matching fixed helper action", async function () {
  const { AppleBuildTaskAssistant } = require(
    "../AppleBuildTools.novaextension/Scripts/task-assistant"
  );
  const args = [
    "xcodebuild", "-project", "/repo/App.xcodeproj",
    "-scheme", "App", "-configuration", "Debug",
    "-destination", "platform=iOS Simulator,id=SIM-A", "build"
  ];
  const dependencies = makeDependencies({
    selectionOverrides: {
      destinationLabel: "iPhone 17 — iOS Simulator 27.0, SIM-A",
      destinationSpecifier: "platform=iOS Simulator,id=SIM-A"
    },
    specification: {
      command: "/usr/bin/xcrun", arguments: args,
      environment: { DEVELOPER_DIR: "/Applications/Xcode 27 rc.app/Contents/Developer" },
      workingDirectory: "/repo"
    }
  });
  const assistant = new AppleBuildTaskAssistant(dependencies);
  const tasks = assistant.provideTasks();

  assert.equal(tasks.length, 2);
  assert.ok(tasks[0].getAction(FakeTask.Build));
  assert.ok(tasks[0].getAction(FakeTask.Clean));
  assert.equal(tasks[0].getAction(FakeTask.Run), undefined);
  assert.ok(tasks[1].getAction(FakeTask.Run));
  const approvedMappings = [
    [FakeTask.Build, "build"],
    [FakeTask.Clean, "clean"],
    [FakeTask.Run, "test"]
  ];
  for (const [novaAction, purpose] of approvedMappings) {
    const action = await assistant.resolveTaskAction({
      action: novaAction,
      data: { purpose }
    });
    assert.deepEqual(action.options.args, args);
    assert.deepEqual(action.options, {
      args,
      env: { DEVELOPER_DIR: "/Applications/Xcode 27 rc.app/Contents/Developer" },
      cwd: "/repo",
      shell: false,
      matchers: [
        "apple-xcode-error-diagnostic",
        "apple-xcode-warning-diagnostic"
      ]
    });
  }
  assert.deepEqual(dependencies.helper.calls.map((call) => call[1].action), [
    "build", "clean", "test"
  ]);
});

test("resolved Build action preserves Swift process specification", async function () {
  const { AppleBuildTaskAssistant } = require(
    "../AppleBuildTools.novaextension/Scripts/task-assistant"
  );
  const specification = {
    command: "/usr/bin/xcrun",
    arguments: ["xcodebuild", "-project", "/repo/App.xcodeproj", "build"],
    environment: { DEVELOPER_DIR: "/Applications/Xcode 27 rc.app/Contents/Developer" },
    workingDirectory: "/repo"
  };
  const dependencies = makeDependencies({ specification });
  const assistant = new AppleBuildTaskAssistant(dependencies);

  const action = await assistant.resolveTaskAction({
    action: FakeTask.Build,
    data: { purpose: "build" }
  });

  assert.ok(action instanceof FakeTaskProcessAction);
  assert.equal(action.command, specification.command);
  assert.deepEqual(action.options, {
    args: specification.arguments,
    env: specification.environment,
    cwd: specification.workingDirectory,
    shell: false,
    matchers: [
      "apple-xcode-error-diagnostic",
      "apple-xcode-warning-diagnostic"
    ]
  });
  assert.equal(dependencies.helper.calls[0][0], "prepare-action");
  assert.equal(dependencies.helper.calls[0][1].action, "build");
});

test("stale selection shows every numbered error and rejects resolution", async function () {
  const { AppleBuildTaskAssistant } = require(
    "../AppleBuildTools.novaextension/Scripts/task-assistant"
  );
  const dependencies = makeDependencies({
    helperError: new HelperDomainError(["First stale value.", "Second stale value."])
  });
  const assistant = new AppleBuildTaskAssistant(dependencies);

  await assert.rejects(assistant.resolveTaskAction({
    action: FakeTask.Build,
    data: { purpose: "build" }
  }));
  assert.deepEqual(dependencies.workspace.errors, [
    "Preflight failed.\n1. First stale value.\n2. Second stale value."
  ]);
});

test("resolver rejects mismatched action and purpose without invoking helper", async function () {
  const { AppleBuildTaskAssistant } = require(
    "../AppleBuildTools.novaextension/Scripts/task-assistant"
  );
  const dependencies = makeDependencies({ specification: {} });
  const assistant = new AppleBuildTaskAssistant(dependencies);

  assert.equal(await assistant.resolveTaskAction({
    action: FakeTask.Clean,
    data: { purpose: "test" }
  }), null);
  assert.equal(await assistant.resolveTaskAction({
    action: FakeTask.Run, data: { purpose: "build" }
  }), null);
  assert.equal(await assistant.resolveTaskAction({
    action: FakeTask.Build, data: { purpose: "test" }
  }), null);
  assert.deepEqual(dependencies.helper.calls, []);
});

test("helper failure is readable and launches no fallback process", async function () {
  const { AppleBuildTaskAssistant } = require(
    "../AppleBuildTools.novaextension/Scripts/task-assistant"
  );
  const dependencies = makeDependencies({
    helperError: new HelperDomainError(["Selection is stale."])
  });
  const assistant = new AppleBuildTaskAssistant(dependencies);

  await assert.rejects(assistant.resolveTaskAction({
    action: FakeTask.Run, data: { purpose: "test" }
  }));
  assert.deepEqual(dependencies.workspace.errors, [
    "Preflight failed.\n1. Selection is stale."
  ]);
  assert.equal(dependencies.processActions.length, 0);
});

function makeAssistant(overrides) {
  return new (require("../AppleBuildTools.novaextension/Scripts/task-assistant").AppleBuildTaskAssistant)(
    makeDependencies({ selectionOverrides: overrides })
  );
}

function makeDependencies(options = {}) {
  const selection = {
    developerDirectory: "/Applications/Xcode 27 rc.app/Contents/Developer",
    containerKind: "project",
    containerPath: "/repo/App.xcodeproj",
    scheme: "App",
    configuration: "Debug",
    destinationLabel: "My Mac",
    destinationSpecifier: "platform=macOS",
    ...(options.selectionOverrides || {})
  };
  const helper = {
    calls: [],
    async invoke(subcommand, invocationOptions) {
      this.calls.push([subcommand, invocationOptions]);
      if (options.helperError) {
        throw options.helperError;
      }
      return options.specification;
    }
  };
  const result = {
    helper,
    store: { savedSelection() { return { ...selection }; } },
    workspace: {
      path: "/repo",
      errors: [],
      showErrorMessage(message) { this.errors.push(message); }
    },
    Task: FakeTask,
    TaskResolvableAction: FakeTaskResolvableAction,
    TaskProcessAction: class extends FakeTaskProcessAction {
      constructor(command, processOptions) {
        super(command, processOptions);
        result.processActions.push(this);
      }
    },
    processActions: []
  };
  return result;
}

class FakeTask {
  static Build = "build";
  static Run = "run";
  static Clean = "clean";

  constructor(name) {
    this.name = name;
    this.actions = new Map();
  }

  setAction(name, action) { this.actions.set(name, action); }
  getAction(name) { return this.actions.get(name); }
}

class FakeTaskResolvableAction {
  constructor(options) { this.options = options; }
}

class FakeTaskProcessAction {
  constructor(command, options) {
    this.command = command;
    this.options = options;
  }
}
