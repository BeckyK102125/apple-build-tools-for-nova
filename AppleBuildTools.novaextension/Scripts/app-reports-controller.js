const { choose } = require("./nova-controller");
const GENERIC_DESTINATION = /^generic\//;
const { workspaceRootFor } = require("./workspace-root");
const { HelperDomainError } = require("./helper-client");

class AppReportsController {
  constructor(dependencies) {
    this.helper = dependencies.helper;
    this.store = dependencies.store;
    this.workspace = dependencies.workspace;
    this.announcer = dependencies.announcer || { say() { return false; } };
    this.runner = dependencies.runner;
    this.Process = dependencies.Process;
    this.readerPath = dependencies.readerPath;
    this.chooser = dependencies.chooser || null;
  }

  async showAppConsole() {
    const session = this.runner.consoleSession();
    if (!session) {
      return this.tell("No App Console yet. Use Build and Run first.");
    }
    try {
      const path = await this.helper.invoke("write-console", {
        "workspace-root": session.workspaceRoot,
        "selection-json": JSON.stringify(session.selection)
      }, JSON.stringify(session.snapshot()));
      if (await this.openDocument(path)) {
        this.announcer.say("App Console ready.");
      }
    } catch (error) {
      const reason = plainReason(error);
      this.tell(reason ? `The App Console could not be saved. ${reason}` : "The App Console could not be saved.");
    }
  }

  async showAppReports() {
    const selection = this.store.savedSelection();
    if (!selection.destinationSpecifier || GENERIC_DESTINATION.test(selection.destinationSpecifier)) {
      return this.tell("App Reports needs a specific destination: your iPhone, My Mac, or a Simulator. Choose Apple Build: Select Destination.");
    }
    const options = {
      "workspace-root": workspaceRootFor(this.workspace.path, selection),
      "selection-json": JSON.stringify(selection)
    };
    try {
      const reports = await this.helper.invoke("app-reports", options);
      if (!reports || reports.length === 0) {
        const device = String(selection.destinationLabel || "your iPhone").split(" — ")[0];
        return this.tell(`No problem reports for ${selection.scheme} on ${device}.`);
      }
      const picked = await choose(this.workspace, reports.map((report) => report.label), "Select an app report", this.chooser);
      if (picked === null) {
        return undefined;
      }
      const report = reports.find((item) => item.label === picked.choice) || reports[picked.index];
      const path = await this.helper.invoke("app-report", { ...options, source: report.source });
      if (await this.openDocument(path)) {
        this.announcer.say("Report ready.");
      }
    } catch (error) {
      this.tell(plainReason(error) || "Apple Build Tools could not read the reports from your iPhone.");
    }
    return undefined;
  }

  // Opens in the native reader (real VoiceOver headings); falls back to Nova if that fails.
  async openDocument(path) {
    if (await this.openInReader(path)) {
      return true;
    }
    await this.workspace.openFile(path);
    this.tell("The reader could not open, so the document opened in Nova.");
    return false;
  }

  openInReader(path) {
    return new Promise((resolve) => {
      if (!this.Process || !this.readerPath) {
        resolve(false);
        return;
      }
      try {
        const process = new this.Process("/usr/bin/open", {
          args: ["-a", this.readerPath, path],
          shell: false
        });
        process.onDidExit((status) => resolve(status === 0));
        process.start();
      } catch (error) {
        resolve(false);
      }
    });
  }

  tell(message) {
    this.workspace.showErrorMessage(message);
    this.announcer.say(message);
  }
}

// Only the helper's own plain-language messages reach the user; anything technical is replaced.
function plainReason(error) {
  if (error instanceof HelperDomainError) {
    return error.errors.join(" ");
  }
  return null;
}

exports.AppReportsController = AppReportsController;
