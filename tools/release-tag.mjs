// Checks a release tag against the product's version, used by the release workflows. A tag is
// <product>-v<version> for a release (vscode-v1.2.3), or with a suffix for a test release that is published
// as a GitHub pre-release only (vscode-v1.2.3-rc.1). The suffix is only in the tag: the Marketplace and
// PowerShell's ModuleVersion don't allow one in the version itself.
// Usage: node tools/release-tag.mjs <product> <tag> <version>; prints lines for $GITHUB_ENV.
import { pathToFileURL } from 'node:url';

export function parseReleaseTag(product, tag, version) {
  const match = new RegExp(`^${product}-v(\\d+\\.\\d+\\.\\d+)(-[0-9A-Za-z.-]+)?$`).exec(tag);
  if (!match) throw new Error(`Tag ${tag} is not ${product}-v<version> or ${product}-v<version>-<suffix>`);
  if (match[1] !== version) throw new Error(`Tag ${tag} does not match the ${product} version ${version}`);
  return { version, prerelease: Boolean(match[2]), name: match[1] + (match[2] ?? '') };
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [product, tag, version] = process.argv.slice(2);
  try {
    const release = parseReleaseTag(product, tag, version);
    process.stdout.write(`VERSION=${release.version}\nRELEASE_NAME=${release.name}\nPRERELEASE=${release.prerelease}\n`);
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
