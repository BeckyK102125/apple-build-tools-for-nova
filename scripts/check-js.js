const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.join(__dirname, '..');
let count = 0;
function check(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) continue;
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) check(file);
    else if (entry.name.endsWith('.js')) { execFileSync(process.execPath, ['--check', file], { stdio: 'pipe' }); count++; }
  }
}
for (const name of ['AppleBuildTools.novaextension/Scripts', 'Tests', 'scripts']) check(path.join(root, name));
console.log('Syntax checked ' + count + ' JavaScript files.');
