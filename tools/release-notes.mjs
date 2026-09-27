// Prints a changelog's entry for one version (the text under its "## <version>" heading), used as the
// GitHub release notes by the release workflows. Usage: node tools/release-notes.mjs <changelog> <version>
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

export function releaseNotes(changelog, version) {
  const section = changelog.split(/^## /m).slice(1).find((s) => s.split(/\s/, 1)[0] === version);
  if (!section) throw new Error(`No "## ${version}" entry`);
  const notes = section.slice(section.indexOf('\n') + 1).trim();
  if (!notes) throw new Error(`The "## ${version}" entry is empty`);
  return notes + '\n';
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [file, version] = process.argv.slice(2);
  try {
    process.stdout.write(releaseNotes(fs.readFileSync(file, 'utf8'), version));
  } catch (e) {
    console.error(`${file}: ${e.message}`);
    process.exit(1);
  }
}
