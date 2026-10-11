const test = require("node:test");
const assert = require("node:assert/strict");

test("helper client launches only the bundled executable without a shell", async function () {
  const { HelperClient } = require("../AppleBuildTools.novaextension/Scripts/helper-client");
  const processDouble = makeProcessDouble({
    status: 0,
    stdout: ['{"errors":[],"ok":true,"value":[]}']
  });
  const client = new HelperClient({
    nova: makeNova(),
    Process: processDouble.Process
  });

  await client.invoke("containers", { "workspace-root": "/repo" });

  assert.equal(processDouble.invocations[0].command, "/extension/Executables/AppleBuildHelper");
  assert.deepEqual(processDouble.invocations[0].options.args, [
    "containers", "--workspace-root", "/repo"
  ]);
  assert.equal(processDouble.invocations[0].options.cwd, "/repo");
  assert.equal(processDouble.invocations[0].options.shell, false);
});

test("helper client parses one stdout JSON response after exit", async function () {
  const { HelperClient } = require("../AppleBuildTools.novaextension/Scripts/helper-client");
  const processDouble = makeProcessDouble({
    status: 0,
    stdout: ['{"errors":[],', '"ok":true,"value":["App"]}']
  });
  const client = new HelperClient({ nova: makeNova(), Process: processDouble.Process });

  assert.deepEqual(await client.invoke("schemes", {}), ["App"]);
});

test("helper domain failure contains every Swift message", async function () {
  const { HelperClient, HelperDomainError } = require(
    "../AppleBuildTools.novaextension/Scripts/helper-client"
  );
  const processDouble = makeProcessDouble({
    status: 2,
    stdout: ['{"ok":false,"errors":["First.","Second."]}']
  });
  const client = new HelperClient({ nova: makeNova(), Process: processDouble.Process });

  await assert.rejects(client.invoke("prepare-build", {}), function (error) {
    assert.ok(error instanceof HelperDomainError);
    assert.deepEqual(error.errors, ["First.", "Second."]);
    assert.match(error.message, /First\.\nSecond\./);
    return true;
  });
});

test("helper launch or internal failure retains stderr", async function () {
  const { HelperClient, HelperInternalError } = require(
    "../AppleBuildTools.novaextension/Scripts/helper-client"
  );
  const processDouble = makeProcessDouble({
    status: 1,
    stderr: ["Unable to launch helper."]
  });
  const client = new HelperClient({ nova: makeNova(), Process: processDouble.Process });

  await assert.rejects(client.invoke("containers", {}), function (error) {
    assert.ok(error instanceof HelperInternalError);
    assert.equal(error.standardError, "Unable to launch helper.");
    return true;
  });
});

test("non-JSON stdout is rejected", async function () {
  const { HelperClient, HelperProtocolError } = require(
    "../AppleBuildTools.novaextension/Scripts/helper-client"
  );
  const processDouble = makeProcessDouble({ status: 0, stdout: ["not JSON"] });
  const client = new HelperClient({ nova: makeNova(), Process: processDouble.Process });

  await assert.rejects(
    client.invoke("containers", {}),
    function (error) { return error instanceof HelperProtocolError; }
  );
});

function makeNova() {
  return {
    extension: { path: "/extension" },
    workspace: { path: "/repo" },
    path: { join: (...parts) => parts.join("/").replaceAll("//", "/") }
  };
}

test("helper client sends standard input when given and closes it", async function () {
  const { HelperClient } = require("../AppleBuildTools.novaextension/Scripts/helper-client");
  const processDouble = makeProcessDouble({ status: 0, stdout: ['{"errors":[],"ok":true,"value":"/logs/a.md"}'] });
  const client = new HelperClient({ nova: makeNova(), Process: processDouble.Process });

  assert.equal(await client.invoke("write-console", { "workspace-root": "/repo" }, '{"lines":[]}'), "/logs/a.md");

  const invocation = processDouble.invocations[0];
  assert.deepEqual(invocation.options.stdio, ["pipe", "pipe", "pipe"]);
  assert.deepEqual(invocation.written, ['{"lines":[]}\n']);
  assert.equal(invocation.closed, true);
  assert.equal(invocation.writerBeforeStart, true);
});

test("helper client without input does not open standard input", async function () {
  const { HelperClient } = require("../AppleBuildTools.novaextension/Scripts/helper-client");
  const processDouble = makeProcessDouble({ status: 0, stdout: ['{"errors":[],"ok":true,"value":[]}'] });
  await new HelperClient({ nova: makeNova(), Process: processDouble.Process }).invoke("schemes", {});
  assert.equal(processDouble.invocations[0].options.stdio, undefined);
});

function makeProcessDouble(scenario) {
  const invocations = [];

  class FakeProcess {
    constructor(command, options) {
      this.stdoutHandlers = [];
      this.stderrHandlers = [];
      this.exitHandlers = [];
      this.record = { command, options, written: [], closed: false, writerBeforeStart: false, started: false };
      invocations.push(this.record);
      const record = this.record;
      this.stdin = {
        getWriter() {
          record.writerBeforeStart = !record.started;
          return {
            write(chunk) { record.written.push(chunk); return Promise.resolve(); },
            close() { record.closed = true; return Promise.resolve(); }
          };
        }
      };
    }

    onStdout(handler) { this.stdoutHandlers.push(handler); }
    onStderr(handler) { this.stderrHandlers.push(handler); }
    onDidExit(handler) { this.exitHandlers.push(handler); }

    start() {
      this.record.started = true;
      queueMicrotask(() => {
        for (const line of scenario.stdout || []) {
          this.stdoutHandlers.forEach((handler) => handler(line));
        }
        for (const line of scenario.stderr || []) {
          this.stderrHandlers.forEach((handler) => handler(line));
        }
        this.exitHandlers.forEach((handler) => handler(scenario.status));
      });
    }
  }

  return { Process: FakeProcess, invocations };
}
