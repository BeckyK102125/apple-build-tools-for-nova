// Containers inside the open Nova workspace keep it as their root, so sibling
// source folders stay visible. Containers chosen elsewhere on disk, or inside a
// hidden folder such as `.worktrees`, use their own parent folder instead.
function workspaceRootFor(activeWorkspacePath, selection) {
  if (!selection || !isAbsolute(selection.containerPath)) {
    return activeWorkspacePath;
  }
  if (isAbsolute(activeWorkspacePath)) {
    const relative = relativeInside(activeWorkspacePath, selection.containerPath);
    if (relative !== null && !relative.split("/").some(isHiddenComponent)) {
      return activeWorkspacePath;
    }
  }
  return dirname(selection.containerPath);
}

function relativeInside(root, path) {
  const prefix = root.endsWith("/") ? root : root + "/";
  return path.startsWith(prefix) ? path.slice(prefix.length) : null;
}

function isHiddenComponent(component) {
  return component.startsWith(".") && component !== "." && component !== "..";
}

function dirname(path) {
  const index = path.lastIndexOf("/");
  if (index <= 0) {
    return "/";
  }
  return path.slice(0, index);
}

function isAbsolute(path) {
  return typeof path === "string" && path.startsWith("/");
}

exports.workspaceRootFor = workspaceRootFor;
