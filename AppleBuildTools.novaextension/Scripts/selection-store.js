const CONFIG = Object.freeze({
  developerDirectory: "appleBuild.developerDirectory",
  containerKind: "appleBuild.containerKind",
  containerPath: "appleBuild.containerPath",
  scheme: "appleBuild.scheme",
  configuration: "appleBuild.configuration",
  destinationLabel: "appleBuild.destinationLabel",
  destinationSpecifier: "appleBuild.destinationSpecifier"
});

const CLEAR_GROUPS = Object.freeze({
  developerDirectory: [
    "developerDirectory",
    "containerKind",
    "containerPath",
    "scheme",
    "configuration",
    "destinationLabel",
    "destinationSpecifier"
  ],
  container: [
    "containerKind",
    "containerPath",
    "scheme",
    "configuration",
    "destinationLabel",
    "destinationSpecifier"
  ],
  scheme: ["scheme", "configuration", "destinationLabel", "destinationSpecifier"],
  configuration: ["configuration", "destinationLabel", "destinationSpecifier"],
  destination: ["destinationLabel", "destinationSpecifier"]
});

class SelectionStore {
  constructor(configuration) {
    this.configuration = configuration;
  }

  savedSelection() {
    return {
      developerDirectory: this.configuration.get(CONFIG.developerDirectory),
      containerKind: this.configuration.get(CONFIG.containerKind),
      containerPath: this.configuration.get(CONFIG.containerPath),
      scheme: this.configuration.get(CONFIG.scheme),
      configuration: this.configuration.get(CONFIG.configuration),
      destinationLabel: this.configuration.get(CONFIG.destinationLabel),
      destinationSpecifier: this.configuration.get(CONFIG.destinationSpecifier)
    };
  }

  selectDeveloperDirectory(developerDirectory) {
    if (developerDirectory === null || developerDirectory === undefined) {
      return false;
    }
    if (this.configuration.get(CONFIG.developerDirectory) === developerDirectory) {
      return false;
    }
    this.configuration.set(CONFIG.developerDirectory, developerDirectory);
    this.clear([
      CONFIG.containerKind,
      CONFIG.containerPath,
      CONFIG.scheme,
      CONFIG.configuration,
      CONFIG.destinationLabel,
      CONFIG.destinationSpecifier
    ]);
    return true;
  }

  selectContainer(container) {
    if (!container) {
      return false;
    }
    if (
      this.configuration.get(CONFIG.containerKind) === container.kind
      && this.configuration.get(CONFIG.containerPath) === container.path
    ) {
      return false;
    }
    this.configuration.set(CONFIG.containerKind, container.kind);
    this.configuration.set(CONFIG.containerPath, container.path);
    this.clear([
      CONFIG.scheme,
      CONFIG.configuration,
      CONFIG.destinationLabel,
      CONFIG.destinationSpecifier
    ]);
    return true;
  }

  selectScheme(scheme) {
    if (scheme === null || scheme === undefined) {
      return false;
    }
    if (this.configuration.get(CONFIG.scheme) === scheme) {
      return false;
    }
    this.configuration.set(CONFIG.scheme, scheme);
    this.clear([
      CONFIG.configuration,
      CONFIG.destinationLabel,
      CONFIG.destinationSpecifier
    ]);
    return true;
  }

  selectConfiguration(configuration) {
    if (configuration === null || configuration === undefined) {
      return false;
    }
    if (this.configuration.get(CONFIG.configuration) === configuration) {
      return false;
    }
    this.configuration.set(CONFIG.configuration, configuration);
    this.clear([CONFIG.destinationLabel, CONFIG.destinationSpecifier]);
    return true;
  }

  selectDestination(destination) {
    if (!destination) {
      return false;
    }
    if (
      this.configuration.get(CONFIG.destinationLabel) === destination.label
      && this.configuration.get(CONFIG.destinationSpecifier) === destination.specifier
    ) {
      return false;
    }
    this.configuration.set(CONFIG.destinationLabel, destination.label);
    this.configuration.set(CONFIG.destinationSpecifier, destination.specifier);
    return true;
  }

  refreshDestinationLabel(destination) {
    if (!destination || this.configuration.get(CONFIG.destinationSpecifier) !== destination.specifier
        || this.configuration.get(CONFIG.destinationLabel) === destination.label) {
      return false;
    }
    this.configuration.set(CONFIG.destinationLabel, destination.label);
    return true;
  }

  clearFrom(level) {
    const propertyNames = CLEAR_GROUPS[level];
    if (!propertyNames) {
      throw new Error(`Unknown build-choice level: ${level}`);
    }

    const cleared = [];
    for (const propertyName of propertyNames) {
      const key = CONFIG[propertyName];
      const value = this.configuration.get(key);
      if (value !== null && value !== undefined) {
        cleared.push({ key: propertyName, value });
        this.configuration.set(key, null);
      }
    }
    return cleared;
  }

  clear(keys) {
    for (const key of keys) {
      this.configuration.set(key, null);
    }
  }
}

exports.CONFIG = CONFIG;
exports.SelectionStore = SelectionStore;
