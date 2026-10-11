const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const manifestPath = "AppleBuildTools.novaextension/extension.json";

test("manifest is local-only and least-privileged", function () {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

  assert.equal(manifest.identifier, "io.github.beckyk102125.AppleBuildTools");
  assert.deepEqual(manifest.entitlements, { filesystem: "readonly", process: true });
  assert.equal(manifest.entitlements.requests, undefined);
  assert.equal(manifest.entitlements.clipboard, undefined);
});

test("manifest main resolves inside Nova's Scripts directory", function () {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

  assert.equal(manifest.main, "main.js");
  assert.equal(
    fs.existsSync(`AppleBuildTools.novaextension/Scripts/${manifest.main}`),
    true
  );
});

test("manifest exposes the approved build, navigator, and signing commands", function () {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

  assert.deepEqual(manifest.commands.extensions, [
    { title: "Apple Build: Select Xcode", command: "apple-build.select-xcode" },
    { title: "Apple Build: Select Project or Workspace", command: "apple-build.select-container" },
    { title: "Apple Build: Select Scheme", command: "apple-build.select-scheme" },
    { title: "Apple Build: Select Configuration", command: "apple-build.select-configuration" },
    { title: "Apple Build: Select Destination", command: "apple-build.select-destination" },
    { title: "Apple Build: Refresh Build Choices", command: "apple-build.refresh-choices" },
    { title: "Apple Build: Show Current Build Choices", command: "apple-build.show-current-choices" },
    { title: "Apple Build: Refresh Project Navigator", command: "apple-build.refresh-project-navigator" },
    {
      title: "Apple Build: Open Selected Project Navigator File",
      command: "apple-build.open-project-navigator-file"
    },
    {
      title: "Apple Signing: Refresh Status",
      command: "apple-build.refresh-signing-status"
    },
    { title: "Apple Build: Run Build", command: "apple-build.run-build" },
    { title: "Apple Build: Run Clean", command: "apple-build.run-clean" },
    { title: "Apple Build: Run Tests", command: "apple-build.run-tests" },
    { title: "Apple Build: Build and Run", command: "apple-build.build-and-run" },
    { title: "Apple Build: Stop Current Action", command: "apple-build.stop-action" },
    { title: "Apple Build: Show App Console", command: "apple-build.show-app-console" },
    { title: "Apple Build: Show App Reports", command: "apple-build.show-app-reports" }
  ]);
});

test("manifest contributes one single-select project navigator with an accessible refresh control", function () {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

  assert.ok(manifest.categories.includes("sidebars"));
  assert.deepEqual(manifest.sidebars[0], {
    id: "apple-build-project-navigator",
    name: "Apple Project Navigator",
    sections: [{
      id: "apple-build-project-navigator",
      name: "Project Navigator",
      allowMultiple: false,
      placeholderText: "Select an Xcode project to show its source files.",
      headerCommands: [
        {
          title: "Open",
          image: "__builtin.next",
          tooltip: "Open Selected Project Navigator File",
          command: "apple-build.open-project-navigator-file",
          when: "viewItem == 'file'"
        },
        {
          title: "Refresh",
          image: "__builtin.refresh",
          tooltip: "Refresh Project Navigator",
          command: "apple-build.refresh-project-navigator"
        }
      ]
    }]
  });
});

test("manifest contributes one single-select signing status sidebar with a labeled refresh control", function () {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

  assert.deepEqual(manifest.sidebars[1], {
    id: "apple-build-signing-status",
    name: "Apple Signing Status",
    sections: [{
      id: "apple-build-signing-status",
      name: "Signing Status",
      allowMultiple: false,
      placeholderText: "Activate Refresh to check Apple signing status.",
      headerCommands: [{
        title: "Refresh",
        image: "__builtin.refresh",
        tooltip: "Refresh Apple Signing Status",
        command: "apple-build.refresh-signing-status"
      }]
    }]
  });
  assert.doesNotMatch(JSON.stringify(manifest.commands), /archive|export|upload|repair signing|change signing/i);
});

test("issue matchers preserve Xcode error and warning severity", function () {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const lines = fs.readFileSync("Tests/fixtures/source-diagnostics.txt", "utf8").trim().split("\n");
  const errorMatcher = manifest.issueMatchers["apple-xcode-error-diagnostic"];
  const warningMatcher = manifest.issueMatchers["apple-xcode-warning-diagnostic"];
  const errorExpression = new RegExp(errorMatcher.pattern.regexp);
  const warningExpression = new RegExp(warningMatcher.pattern.regexp);

  assert.equal(errorMatcher.pattern.severity, "error");
  assert.equal(warningMatcher.pattern.severity, "warning");
  assert.deepEqual(lines.map((line) => errorExpression.test(line)), [false, true, false, false, false]);
  assert.deepEqual(lines.map((line) => warningExpression.test(line)), [true, false, false, false, false]);
});
