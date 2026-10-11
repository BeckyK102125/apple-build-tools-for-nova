const assert = require("node:assert/strict");
const test = require("node:test");

const { workspaceRootFor } = require("../AppleBuildTools.novaextension/Scripts/workspace-root");

test("container inside the active workspace keeps the workspace as its root", function () {
  assert.equal(
    workspaceRootFor("/repo", { containerPath: "/repo/App/App.xcodeproj" }),
    "/repo"
  );
});

test("container directly in the active workspace keeps the workspace as its root", function () {
  assert.equal(
    workspaceRootFor("/repo/", { containerPath: "/repo/App.xcodeproj" }),
    "/repo/"
  );
});

test("container outside the active workspace uses its parent folder", function () {
  assert.equal(
    workspaceRootFor("/repo", { containerPath: "/other/Worktree/App.xcodeproj" }),
    "/other/Worktree"
  );
});

test("sibling folder sharing a name prefix is outside the active workspace", function () {
  assert.equal(
    workspaceRootFor("/repo", { containerPath: "/repo-copy/App.xcodeproj" }),
    "/repo-copy"
  );
});

test("linked worktree in a hidden folder of the workspace uses its parent folder", function () {
  assert.equal(
    workspaceRootFor("/repo", { containerPath: "/repo/.worktrees/candidate/App.xcodeproj" }),
    "/repo/.worktrees/candidate"
  );
});

test("missing or relative container keeps the active workspace", function () {
  assert.equal(workspaceRootFor("/repo", {}), "/repo");
  assert.equal(workspaceRootFor("/repo", null), "/repo");
  assert.equal(workspaceRootFor("/repo", { containerPath: "App.xcodeproj" }), "/repo");
});

test("container with no active workspace uses its parent folder", function () {
  assert.equal(
    workspaceRootFor(null, { containerPath: "/other/App.xcodeproj" }),
    "/other"
  );
});
