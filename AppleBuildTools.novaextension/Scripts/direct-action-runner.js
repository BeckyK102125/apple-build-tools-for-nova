const { isComplete, missingSelectionLabels } = require("./task-assistant");
const { workspaceRootFor } = require("./workspace-root");
const { ConsoleSession } = require("./console-session");

const DIRECT_ACTIONS = new Set(["build", "clean", "test", "device"]);
// devicectl prints this once the app is open; later output is the app's own.
const LAUNCH_CONFIRMATION = /^Launched application\b/i;
const DEVICE_PHASE_WORDS = {
  build: "building the app",
  prepare: "preparing the destination",
  install: "installing the app",
  launch: "opening the app"
};
const GENERIC_DESTINATION = /^generic\//;

class DirectActionRunner {
  constructor(dependencies) {
    this.helper = dependencies.helper;
    this.store = dependencies.store;
    this.workspace = dependencies.workspace;
    this.Process = dependencies.Process;
    this.announcer = dependencies.announcer || { say() { return false; } };
    // Optional: (markdown, appName, title) => Promise; opens the report in the reader.
    this.openDocument = dependencies.openDocument || null;
    this.active = null;
    this.console = null;
  }

  async run(action) {
    if (!DIRECT_ACTIONS.has(action)) {
      throw new Error(`Unsupported Apple action: ${action}`);
    }
    if (this.active) {
      this.workspace.showActionPanel(
        `${labelFor(action)} cannot start because another direct Apple action is already running.`,
        { buttons: ["OK"] }
      );
      return "rejected";
    }

    const selection = this.store.savedSelection();
    if (!isComplete(selection)) {
      const missing = missingSelectionLabels(selection);
      this.workspace.showActionPanel(
        `${labelFor(action)} cannot start until you choose ${joinLabels(missing)}.`,
        { buttons: ["OK"] }
      );
      return "rejected";
    }
    if (action === "device" && GENERIC_DESTINATION.test(selection.destinationSpecifier || "")) {
      this.workspace.showActionPanel(
        "Build and Run needs a specific place to run: your iPhone, My Mac, or a Simulator. Choose Apple Build: Select Destination.",
        { buttons: ["OK"] }
      );
      return "rejected";
    }

    if (action === "device" && this.console) {
      // Also covers a console still checking for a crash, so it cannot speak during the new run.
      const previous = this.console;
      previous.stop({ silent: true });
      if (previous.kind === "mac") {
        // iPhone and Simulator launches replace the running copy themselves; a Mac app must be closed here.
        previous.terminateApp();
      }
    }

    let specification;
    const workspaceRoot = workspaceRootFor(this.workspace.path, selection);
    try {
      specification = await this.helper.invoke("prepare-action", {
        action: action === "device" ? "build" : action,
        "workspace-root": workspaceRoot,
        "selection-json": JSON.stringify(selection)
      });
    } catch (error) {
      const detail = error && error.message ? error.message : String(error);
      this.workspace.showErrorMessage(`${labelFor(action)} could not start. ${detail}`);
      return "rejected";
    }

    const entry = {
      action,
      selection,
      workspaceRoot,
      phase: "build",
      plan: null,
      process: null,
      stopRequested: false,
      finished: false,
      stdout: [],
      stderr: [],
      startedAt: new Date()
    };
    this.active = entry;
    this.announceProgress(entry);
    return this.startStep(entry, specification) ? "started" : "rejected";
  }

  startStep(entry, specification) {
    const process = new this.Process(specification.command, {
      args: specification.arguments,
      env: specification.environment,
      cwd: specification.workingDirectory,
      shell: false
    });
    entry.process = process;
    process.onStdout((line) => this.handleOutput(entry, String(line), entry.stdout));
    process.onStderr((line) => this.handleOutput(entry, String(line), entry.stderr));
    process.onDidExit((status) => {
      if (entry.console) {
        entry.console.ended(status);
        return;
      }
      this.stepEnded(entry, status);
    });
    try {
      process.start();
    } catch (error) {
      this.finish(entry, null, error);
      return false;
    }
    return true;
  }

  // Build and Run continues build -> preparation steps -> install -> launch only while each step succeeds.
  stepEnded(entry, status) {
    if (entry.action !== "device" || entry.stopRequested || status !== 0 || entry.phase === "launch") {
      this.finish(entry, status);
      return;
    }
    if (entry.phase === "build") {
      this.prepareDeviceSteps(entry);
      return;
    }
    this.nextDeviceStep(entry);
  }

  nextDeviceStep(entry) {
    const plan = entry.plan;
    if (entry.pendingSteps.length > 0) {
      if (entry.phase !== "prepare") {
        entry.phase = "prepare";
        this.announceProgress(entry);
      }
      this.startStep(entry, entry.pendingSteps.shift());
      return;
    }
    if (plan.install && entry.phase !== "install") {
      entry.phase = "install";
      entry.stdout.push(`--- Installing ${plan.appName} on ${plan.deviceName} ---`);
      this.announceProgress(entry);
      this.startStep(entry, plan.install);
      return;
    }
    entry.phase = "launch";
    entry.stdout.push(`--- Opening ${plan.appName} on ${plan.deviceName} ---`);
    this.announceProgress(entry);
    if (this.startStep(entry, plan.launch) && !entry.readyPattern) {
      this.appReady(entry);
    }
  }

  // The app is open: hand its output to a console session, report success, and bring a Mac app forward.
  appReady(entry) {
    const kind = entry.plan.kind || "iphone";
    entry.console = new ConsoleSession({
      helper: this.helper,
      announcer: this.announcer,
      process: entry.process,
      selection: entry.selection,
      workspaceRoot: entry.workspaceRoot,
      appName: entry.plan.appName.replace(/\.app$/, ""),
      deviceName: entry.plan.deviceName,
      kind,
      // iPhone reports come from the phone; Mac and Simulator reports from this Mac's DiagnosticReports.
      checksCrashReports: true
    });
    this.console = entry.console;
    this.finish(entry, 0);
    if (entry.plan.activate) {
      try {
        new this.Process(entry.plan.activate.command, {
          args: entry.plan.activate.arguments,
          env: entry.plan.activate.environment,
          cwd: entry.plan.activate.workingDirectory,
          shell: false
        }).start();
      } catch (error) {
        // The app is running; failing to bring it forward is not worth an error.
      }
    }
  }

  async prepareDeviceSteps(entry) {
    // Between the build and the first device step, while the helper works out the run plan.
    entry.phase = "planning";
    entry.process = null;
    let plan;
    try {
      plan = await this.helper.invoke("prepare-device-run", {
        "workspace-root": entry.workspaceRoot,
        "selection-json": JSON.stringify(entry.selection)
      });
    } catch (error) {
      if (entry.stopRequested) {
        this.finish(entry, null);
        return;
      }
      entry.finished = true;
      if (this.active === entry) {
        this.active = null;
      }
      const detail = error && error.message ? error.message : String(error);
      this.workspace.showErrorMessage(`Apple Build and Run could not prepare the app. ${detail}`);
      return;
    }
    if (entry.stopRequested) {
      this.finish(entry, null);
      return;
    }
    entry.plan = plan;
    entry.pendingSteps = (plan.steps || []).slice();
    // A Mac app is open as soon as it starts; iPhone and Simulator launches print a line first.
    entry.readyPattern = plan.kind === "mac"
      ? null
      : (plan.readyPattern ? new RegExp(plan.readyPattern) : LAUNCH_CONFIRMATION);
    this.nextDeviceStep(entry);
  }

  stop() {
    const entry = this.active;
    if (!entry) {
      if (this.console && this.console.stop()) {
        this.workspace.showActionPanel(
          `Stopped listening to the app. It is still open on ${this.console.deviceName}.`,
          { buttons: ["OK"] }
        );
        return true;
      }
      this.workspace.showActionPanel("No direct Apple action is running.", { buttons: ["OK"] });
      return false;
    }
    entry.stopRequested = true;
    this.active = null;
    try {
      if (entry.process) {
        entry.process.terminate();
      }
    } catch (error) {
      const detail = error && error.message ? error.message : String(error);
      this.workspace.showErrorMessage(`The direct Apple action could not be stopped. ${detail}`);
    }
    return true;
  }

  handleOutput(entry, line, bucket) {
    if (entry.console) {
      entry.console.append(line);
      return;
    }
    bucket.push(line);
    if (entry.action === "device" && entry.phase === "launch" && entry.readyPattern && entry.readyPattern.test(line)) {
      this.appReady(entry);
    }
  }

  consoleSession() {
    return this.console;
  }

  async showReport(report, entry) {
    if (this.openDocument) {
      try {
        await this.openDocument(report, entry.selection.scheme, `${labelFor(entry.action)} Command Report`);
        return;
      } catch (error) {
        // Fall back to an untitled document below.
      }
    }
    this.workspace.openNewTextDocument({ content: report });
  }

  announceProgress(entry) {
    this.announcer.say(progressPhrase(entry.action, entry.phase, entry.selection, entry.plan));
  }

  isRunning() {
    return this.active !== null;
  }

  finish(entry, status, launchError) {
    if (entry.finished) {
      return;
    }
    entry.finished = true;
    if (this.active === entry) {
      this.active = null;
    }
    const endedAt = new Date();
    const report = reportFor(entry, status, endedAt, launchError);
    if (launchError) {
      const detail = launchError.message ? launchError.message : String(launchError);
      this.workspace.showErrorMessage(`${labelFor(entry.action)} could not start. ${detail}`);
      return;
    }
    let message;
    if (entry.stopRequested) {
      message = `${labelFor(entry.action)} was cancelled.`;
    } else if (status === 0 && entry.action === "device") {
      message = `Apple Build and Run completed. ${entry.plan.appName} is open on ${entry.plan.deviceName}.`;
    } else if (status === 0) {
      message = `${labelFor(entry.action)} completed successfully.`;
    } else {
      message = failureMessageFor(entry, status);
    }
    this.workspace.showActionPanel(
      message,
      { buttons: ["View Build Command Report", "OK"] },
      (buttonIndex) => {
        if (buttonIndex === 0) {
          this.showReport(report, entry);
        }
      }
    );
  }
}

// What the Mac voice says when an action starts or an iPhone run moves to its next step.
// action: "build" | "clean" | "test" | "device"
// phase:  "build" for every start; then "install" and "launch" for "device" only
// selection: saved choices, e.g. selection.scheme, selection.destinationLabel
// plan: null until the install step; then plan.appName and plan.deviceName
function progressPhrase(action, phase, selection, plan) {
  const scheme = selection && selection.scheme ? selection.scheme : "the app";
  if (action === "device") {
    const device = plan && plan.deviceName ? plan.deviceName : "your iPhone";
    const app = plan && plan.appName ? plan.appName.replace(/\.app$/, "") : scheme;
    if (phase === "prepare") {
      return `Starting ${device}.`;
    }
    if (phase === "install") {
      return `Installing ${app} on ${device}.`;
    }
    if (phase === "launch") {
      return `Opening ${app} on ${device}.`;
    }
    const destination = selection && selection.destinationLabel
      ? String(selection.destinationLabel).split(" — ")[0]
      : "your device";
    return `Building ${scheme} for ${destination}.`;
  }
  return {
    build: `Build started for ${scheme}.`,
    clean: `Clean started for ${scheme}.`,
    test: `Tests started for ${scheme}.`
  }[action] || "";
}

// The first "error:" line Xcode printed, without its "(in target …)" suffix, for the failure message.
function firstError(entry) {
  for (const line of entry.stdout.concat(entry.stderr)) {
    const match = /\berror:\s*(.+)$/i.exec(line);
    if (match) {
      const text = match[1].replace(/\s*\(in target .*\)\s*$/, "").trim();
      return text.length > 200 ? `${text.slice(0, 199)}…` : text;
    }
  }
  return null;
}

// Error lines plus Xcode's "The following build commands failed" list, for the report's Errors heading.
function errorLines(entry) {
  const lines = [];
  let inFailedList = false;
  for (const line of entry.stdout.concat(entry.stderr)) {
    if (/^The following build commands failed:/.test(line)) {
      inFailedList = true;
      lines.push(line);
      continue;
    }
    if (inFailedList) {
      if (!line.trim()) {
        continue;
      }
      lines.push(line);
      if (/^\(\d+ failures?\)/.test(line.trim())) {
        inFailedList = false;
      }
      continue;
    }
    if (/\berror:/i.test(line)) {
      lines.push(line);
    }
  }
  return lines;
}

function failureMessageFor(entry, status) {
  if (entry.action === "device") {
    const error = firstError(entry);
    const message = `Apple Build and Run failed while ${DEVICE_PHASE_WORDS[entry.phase]}, exit status ${status}${error ? `: ${error}` : ""}.`;
    const kind = entry.plan ? entry.plan.kind || "iphone" : "iphone";
    if (kind !== "iphone" || entry.phase === "build" || entry.phase === "prepare") {
      return message;
    }
    return `${message} Make sure the iPhone is unlocked, connected, trusts this Mac, and has Developer Mode on.`;
  }
  if (
    entry.action === "test" &&
    entry.stderr.some((line) => /scheme .*not currently configured for the test action/i.test(line))
  ) {
    return "Apple Test failed because this scheme is not configured for the Test action. In Xcode, choose Product > Scheme > Edit Scheme…, open Test, and add a test target.";
  }
  const error = firstError(entry);
  return `${labelFor(entry.action)} failed with exit status ${status}${error ? `: ${error.replace(/\.$/, "")}` : ""}.`;
}

function labelFor(action) {
  return {
    build: "Apple Build",
    clean: "Apple Clean",
    test: "Apple Test",
    device: "Apple Build and Run"
  }[action] || "Apple action";
}

function joinLabels(labels) {
  if (labels.length <= 1) {
    return labels[0] || "all required build choices";
  }
  if (labels.length === 2) {
    return `${labels[0]} and ${labels[1]}`;
  }
  return `${labels.slice(0, -1).join(", ")}, and ${labels.at(-1)}`;
}

function reportFor(entry, status, endedAt, launchError) {
  const title = `${labelFor(entry.action)} Command Report`;
  const exitStatus = launchError ? "not started" : String(status);
  const errors = errorLines(entry);
  return [
    `# ${title}`,
    "",
    "## Summary",
    `Action: ${entry.action}`,
    `Scheme: ${entry.selection.scheme}`,
    `Exit status: ${exitStatus}`,
    `Started: ${entry.startedAt.toISOString()}`,
    `Ended: ${endedAt.toISOString()}`,
    "",
    "## Errors",
    errors.length > 0 ? fenced(errors.join("\n")) : "No errors.",
    "",
    "## Standard output",
    entry.stdout.length > 0 ? fenced(entry.stdout.join("\n")) : "(none)",
    "",
    "## Standard error",
    entry.stderr.length > 0 ? fenced(entry.stderr.join("\n")) : "(none)",
    ""
  ].join("\n");
}

// A fence one backtick longer than any run inside, so build output cannot create headings.
function fenced(text) {
  const longest = Math.max(0, ...(text.match(/`+/g) || []).map((run) => run.length));
  const fence = "`".repeat(Math.max(3, longest + 1));
  return `${fence}\n${text}\n${fence}`;
}

exports.DIRECT_ACTIONS = DIRECT_ACTIONS;
exports.LAUNCH_CONFIRMATION = LAUNCH_CONFIRMATION;
exports.DirectActionRunner = DirectActionRunner;
exports.labelFor = labelFor;
exports.reportFor = reportFor;
exports.failureMessageFor = failureMessageFor;
exports.progressPhrase = progressPhrase;
