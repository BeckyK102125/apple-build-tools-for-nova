const assert = require("node:assert/strict");
const test = require("node:test");
const { AccessibleChooser } = require("../AppleBuildTools.novaextension/Scripts/accessible-chooser");
const { choose } = require("../AppleBuildTools.novaextension/Scripts/nova-controller");

function makeHelper(answer) {
  const calls = [];
  return {
    calls,
    async invoke(subcommand, options, input) {
      calls.push({ subcommand, options, input });
      if (answer instanceof Error) throw answer;
      return answer;
    }
  };
}

function makeWorkspace() {
  return {
    palettes: [],
    showChoicePalette(labels, options, callback) {
      this.palettes.push(labels);
      callback(labels[0], 0);
    }
  };
}

test("the chooser sends the prompt and items and returns the chosen label and index", async function () {
  const helper = makeHelper({ index: 1 });
  const chooser = new AccessibleChooser({ helper, readerPath: "/ext/Executables/Apple Build Reader.app" });

  assert.deepEqual(await chooser.choose(["My Mac", "iPhone"], "Select a build destination"), { choice: "iPhone", index: 1 });
  assert.deepEqual(helper.calls[0], {
    subcommand: "choose",
    options: { reader: "/ext/Executables/Apple Build Reader.app" },
    input: JSON.stringify({ title: "Select a build destination", items: ["My Mac", "iPhone"] })
  });
});

test("cancelling the chooser returns null", async function () {
  const chooser = new AccessibleChooser({ helper: makeHelper({ index: null }), readerPath: "/r.app" });
  assert.equal(await chooser.choose(["a"], "Pick"), null);
});

test("an out-of-range answer is treated as a failure", async function () {
  const chooser = new AccessibleChooser({ helper: makeHelper({ index: 3 }), readerPath: "/r.app" });
  await assert.rejects(chooser.choose(["a"], "Pick"));
});

test("choose uses the accessible chooser when given one, and Nova's palette otherwise", async function () {
  const workspace = makeWorkspace();
  const chooser = new AccessibleChooser({ helper: makeHelper({ index: 1 }), readerPath: "/r.app" });

  assert.deepEqual(await choose(workspace, ["a", "b"], "Pick", chooser), { choice: "b", index: 1 });
  assert.deepEqual(workspace.palettes, []);
  assert.deepEqual(await choose(workspace, ["a", "b"], "Pick"), { choice: "a", index: 0 });
  assert.equal(workspace.palettes.length, 1);
});

test("choose falls back to Nova's palette when the chooser fails, but not when it is cancelled", async function () {
  let workspace = makeWorkspace();
  const failing = new AccessibleChooser({ helper: makeHelper(new Error("could not open")), readerPath: "/r.app" });
  assert.deepEqual(await choose(workspace, ["a", "b"], "Pick", failing), { choice: "a", index: 0 });
  assert.equal(workspace.palettes.length, 1);

  workspace = makeWorkspace();
  const cancelled = new AccessibleChooser({ helper: makeHelper({ index: null }), readerPath: "/r.app" });
  assert.equal(await choose(workspace, ["a", "b"], "Pick", cancelled), null);
  assert.deepEqual(workspace.palettes, []);
});
