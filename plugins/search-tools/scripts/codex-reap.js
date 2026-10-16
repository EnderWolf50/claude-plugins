const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const [record, id, token] = process.argv.slice(2);
function stillEnded() {
  try { return JSON.parse(fs.readFileSync(record, 'utf8')).ending === token; }
  catch { return false; }
}
if (stillEnded()) {
  spawnSync(process.env.SEARCH_TOOLS_BASH, [path.join(__dirname, 'tgrep-serve.sh').replaceAll('\\', '/'), 'reap', id],
    {env:process.env, timeout:30000, stdio:'ignore', windowsHide:true});
  if (stillEnded()) fs.rmSync(record, {force:true});
}
