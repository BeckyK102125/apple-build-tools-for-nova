const MAX_LINES = 10000;
const MAX_LINE_LENGTH = 2000;
const ERROR_LINE = /\b(error|fault)\b/i;
const WARNING_LINE = /\bwarning\b/i;
// iOS writes a crash report a few seconds after the app dies, so look again before saying it quit.
const CRASH_RETRY_DELAYS_MS = [5000, 15000];
// devicectl's own status line, not something the app printed.
const DEVICECTL_WAITING = /^Waiting for the application to terminate/;

class ConsoleSession {
  constructor(dependencies) {
    this.helper = dependencies.helper;
    this.announcer = dependencies.announcer || { say() { return false; } };
    this.process = dependencies.process;
    this.selection = dependencies.selection;
    this.workspaceRoot = dependencies.workspaceRoot;
    this.appName = dependencies.appName;
    this.deviceName = dependencies.deviceName;
    this.kind = dependencies.kind || "iphone";
    // Off only when a caller has no way to look up crash reports.
    this.checksCrashReports = dependencies.checksCrashReports !== false;
    this.now = dependencies.now || (() => new Date());
    this.sleep = dependencies.sleep || ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    this.startedAt = this.now();
    this.endedAt = null;
    this.state = "running";
    this.lines = [];
    this.droppedLines = 0;
    this.errorAnnounced = false;
    this.crashSource = null;
  }

  isListening() {
    return this.state === "running";
  }

  append(line) {
    if (this.state !== "running" || DEVICECTL_WAITING.test(String(line))) {
      return;
    }
    // Count characters, not UTF-16 units, so an emoji is never cut in half.
    const text = Array.from(String(line)).slice(0, MAX_LINE_LENGTH).join("");
    this.lines.push(text);
    if (this.lines.length > MAX_LINES) {
      this.lines.shift();
      this.droppedLines += 1;
    }
    if (!this.errorAnnounced && ERROR_LINE.test(text)) {
      this.errorAnnounced = true;
      this.announcer.say("The app reported an error.", { appEvent: true });
    }
  }

  stop(options = {}) {
    if (this.state !== "running" && this.state !== "checking") {
      return false;
    }
    this.state = "stopped";
    this.endedAt = this.now();
    this.silentStop = Boolean(options.silent);
    // Ending devicectl would close the app on the iPhone, so only stop recording.
    // devicectl exits by itself when the app quits or the next run replaces it.
    return true;
  }

  async ended(status) {
    if (this.state !== "running") {
      return;
    }
    this.endedAt = this.now();
    this.state = "checking";
    const delays = this.checksCrashReports ? CRASH_RETRY_DELAYS_MS : null;
    for (let attempt = 0; delays && attempt <= delays.length; attempt += 1) {
      if (attempt > 0) {
        await this.sleep(delays[attempt - 1]);
      }
      if (this.state !== "checking") {
        return;
      }
      const crash = await this.findCrash();
      if (this.state !== "checking") {
        return;
      }
      if (crash) {
        this.state = "crashed";
        this.crashSource = crash.source;
        this.announcer.say("The app crashed.", { appEvent: true });
        return;
      }
    }
    this.state = "ended";
    this.announcer.say("The app quit.", { appEvent: true });
  }

  // Closes the app itself (used for Mac apps, which Nova started directly).
  terminateApp() {
    try {
      this.process.terminate();
    } catch (error) {
      // The app may already have quit.
    }
  }

  async findCrash() {
    try {
      const reports = await this.helper.invoke("app-reports", {
        "workspace-root": this.workspaceRoot,
        "selection-json": JSON.stringify(this.selection),
        "since-epoch": Math.floor(this.startedAt.getTime() / 1000)
      });
      return (reports || []).find((report) => report.kind === "crash") || null;
    } catch (error) {
      // A locked or disconnected phone still means the app stopped.
      return null;
    }
  }

  snapshot() {
    return {
      appName: this.appName,
      deviceName: this.deviceName,
      startedAt: this.startedAt.toISOString(),
      endedAt: this.endedAt ? this.endedAt.toISOString() : null,
      state: this.state,
      lines: this.lines.slice(),
      droppedLines: this.droppedLines,
      crashSource: this.crashSource
    };
  }
}

exports.ConsoleSession = ConsoleSession;
exports.ERROR_LINE = ERROR_LINE;
exports.MAX_LINES = MAX_LINES;
exports.MAX_LINE_LENGTH = MAX_LINE_LENGTH;
exports.WARNING_LINE = WARNING_LINE;
