class HelperDomainError extends Error {
  constructor(errors) {
    super(errors.join("\n"));
    this.name = "HelperDomainError";
    this.errors = errors;
  }
}

class HelperInternalError extends Error {
  constructor(message, standardError) {
    super(message);
    this.name = "HelperInternalError";
    this.standardError = standardError;
  }
}

class HelperProtocolError extends Error {
  constructor(message) {
    super(message);
    this.name = "HelperProtocolError";
  }
}

class HelperClient {
  constructor(dependencies) {
    this.nova = dependencies.nova;
    this.Process = dependencies.Process;
  }

  invoke(subcommand, options, input) {
    const helperPath = this.nova.path.join(
      this.nova.extension.path,
      "Executables",
      "AppleBuildHelper"
    );
    const args = [subcommand];
    for (const [name, value] of Object.entries(options || {})) {
      if (value === null || value === undefined) {
        continue;
      }
      args.push(name.startsWith("--") ? name : `--${name}`, String(value));
    }

    return new Promise((resolve, reject) => {
      const standardOutput = [];
      const standardError = [];
      const disposables = [];
      let process;

      try {
        const processOptions = { args, cwd: this.nova.workspace.path, shell: false };
        if (typeof input === "string") {
          processOptions.stdio = ["pipe", "pipe", "pipe"];
        }
        process = new this.Process(helperPath, processOptions);
        disposables.push(process.onStdout((line) => standardOutput.push(line)));
        disposables.push(process.onStderr((line) => standardError.push(line)));
        disposables.push(process.onDidExit((status) => {
          disposeAll(disposables);
          const stdout = standardOutput.join("\n").trim();
          const stderr = standardError.join("\n").trim();

          if (status === 1) {
            reject(new HelperInternalError(
              stderr || "AppleBuildHelper failed without an error message.",
              stderr
            ));
            return;
          }

          let response;
          try {
            response = JSON.parse(stdout);
          } catch (_) {
            reject(new HelperProtocolError(
              "AppleBuildHelper returned a response that was not one JSON object."
            ));
            return;
          }

          if (!response || typeof response.ok !== "boolean" || !Array.isArray(response.errors)) {
            reject(new HelperProtocolError("AppleBuildHelper returned an invalid response shape."));
            return;
          }
          if (!response.ok) {
            reject(new HelperDomainError(response.errors.map(String)));
            return;
          }
          if (status !== 0) {
            reject(new HelperProtocolError(
              `AppleBuildHelper reported success with unexpected exit status ${status}.`
            ));
            return;
          }
          resolve(response.value);
        }));
        // Nova needs the writer before start; one JSON line, then close so the helper sees end of input.
        const writer = typeof input === "string" ? process.stdin.getWriter() : null;
        process.start();
        if (writer) {
          Promise.resolve(writer.write(input + "\n")).then(() => writer.close()).catch(() => {});
        }
      } catch (error) {
        disposeAll(disposables);
        reject(new HelperInternalError(
          `AppleBuildHelper could not launch. ${error.message || String(error)}`,
          standardError.join("\n").trim()
        ));
      }
    });
  }
}

function disposeAll(disposables) {
  for (const disposable of disposables) {
    if (disposable && typeof disposable.dispose === "function") {
      disposable.dispose();
    }
  }
}

exports.HelperClient = HelperClient;
exports.HelperDomainError = HelperDomainError;
exports.HelperInternalError = HelperInternalError;
exports.HelperProtocolError = HelperProtocolError;
