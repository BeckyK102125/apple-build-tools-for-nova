const ANNOUNCE_SETTING = "appleBuild.announceProgress";
const APP_EVENTS_SETTING = "appleBuild.announceAppEvents";

// Speaks short phrases with the Mac speech voice, for people who do not use VoiceOver. Both settings are
// off by default because VoiceOver already reads the chooser, messages, and reports.
class Announcer {
  constructor(dependencies) {
    this.Process = dependencies.Process;
    this.config = dependencies.config;
    this.current = null;
  }

  isEnabled(options = {}) {
    if (options.appEvent) {
      return this.config.get(APP_EVENTS_SETTING) === true;
    }
    return this.config.get(ANNOUNCE_SETTING) === true;
  }

  say(text, options = {}) {
    const phrase = String(text ?? "").trim().replace(/^-+/, "");
    if (!phrase || !this.isEnabled(options)) {
      return false;
    }
    if (this.current) {
      try {
        this.current.terminate();
      } catch (error) {
        // The previous phrase may already have finished.
      }
    }
    try {
      const process = new this.Process("/usr/bin/say", { args: [phrase], shell: false });
      this.current = process;
      process.onDidExit(() => {
        if (this.current === process) {
          this.current = null;
        }
      });
      process.start();
      return true;
    } catch (error) {
      this.current = null;
      return false;
    }
  }
}

exports.ANNOUNCE_SETTING = ANNOUNCE_SETTING;
exports.APP_EVENTS_SETTING = APP_EVENTS_SETTING;
exports.Announcer = Announcer;
