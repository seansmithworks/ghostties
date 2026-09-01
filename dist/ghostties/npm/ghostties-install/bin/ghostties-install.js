#!/usr/bin/env node
"use strict";

/**
 * ghostties-install
 *
 * Resolves the newest published release of Ghostties.app at run time,
 * downloads it, verifies the download against GitHub's own asset digest,
 * and verifies the extracted app bundle's code signature — then places it
 * in /Applications (or --target). Zero runtime dependencies: only Node
 * built-ins and macOS system tools (`ditto`, `codesign`).
 *
 * There is no pinned version to bump. See README.md for how release
 * resolution works and why it's safe to trust "newest" without a pin.
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const https = require("https");
const crypto = require("crypto");
const { execFileSync, spawnSync } = require("child_process");

// ---------------------------------------------------------------------------
// Release resolution
// ---------------------------------------------------------------------------
const REPO = "SeanSmithWorks/ghostties";
const ASSET_NAME = "ghostties-macos-arm64.zip";
const APP_NAME = "Ghostties.app";
// The identity every Ghostties release is signed with (Developer ID, Sean's
// team). Verified after extraction, independent of any version pin.
const EXPECTED_TEAM_ID = "5P7G79U672";

// GitHub's `/releases/latest` endpoint excludes prereleases, and every
// Ghostties release published so far is a prerelease — so it would find
// nothing. Read the release list instead and take the newest entry
// (the API returns releases newest-first), keeping prereleases in scope.
// The Homebrew cask's `livecheck` block (dist/ghostties/homebrew/ghostties.rb)
// works around the same GitHub behavior the same way.
const RELEASES_API_URL = `https://api.github.com/repos/${REPO}/releases?per_page=10`;

// ---------------------------------------------------------------------------
// CLI plumbing
// ---------------------------------------------------------------------------

function printUsage() {
  console.log(`
ghostties-install — install Ghostties.app (macOS, Apple silicon)

Usage:
  npx ghostties-install [options]

Options:
  --target <dir>   Install directory (default: /Applications)
                    Also settable via GHOSTTIES_INSTALL_DIR.
  --force           Overwrite an existing install at the target.
  -h, --help        Show this help.

Always installs the newest published release (GitHub API resolves it at run
time — nothing is pinned). The download is verified against GitHub's own
asset digest, and the extracted app bundle's code signature is verified
against Sean's Developer ID team identifier before install.
`);
}

function parseArgs(argv) {
  const args = { target: null, force: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--target") {
      const value = argv[i + 1];
      if (value === undefined || value.startsWith("--")) {
        throw new Error("--target requires a directory argument.");
      }
      args.target = value;
      i++;
    } else if (arg.startsWith("--target=")) {
      args.target = arg.slice("--target=".length);
    } else if (arg === "--force") {
      args.force = true;
    } else if (arg === "-h" || arg === "--help") {
      args.help = true;
    } else {
      throw new Error(`Unrecognized argument: ${arg}`);
    }
  }
  if (!args.target) {
    args.target = process.env.GHOSTTIES_INSTALL_DIR || "/Applications";
  }
  return args;
}

// ---------------------------------------------------------------------------
// Platform gate
// ---------------------------------------------------------------------------

function checkPlatform(platform, arch) {
  if (platform !== "darwin") {
    throw new InstallError(
      `Ghostties only runs on macOS. Detected platform: "${platform}".\n` +
        "There is no Linux or Windows build — this project follows upstream Ghostty's " +
        "AppKit-first, macOS-only design.",
    );
  }
  if (arch !== "arm64") {
    throw new InstallError(
      `Ghostties is built for Apple silicon (arm64) only. Detected architecture: "${arch}".\n` +
        "There is no Intel (x64) build and none is planned.",
    );
  }
}

class InstallError extends Error {}

// ---------------------------------------------------------------------------
// GitHub API
// ---------------------------------------------------------------------------

function httpsGetJson(url, { redirectsLeft = 5 } = {}) {
  return new Promise((resolve, reject) => {
    const request = https.get(
      url,
      {
        headers: {
          "User-Agent": "ghostties-install",
          Accept: "application/vnd.github+json",
        },
      },
      (res) => {
        const { statusCode, headers } = res;

        if (statusCode >= 300 && statusCode < 400 && headers.location) {
          res.resume();
          if (redirectsLeft <= 0) {
            reject(
              new InstallError(
                "Too many redirects while querying the GitHub API.",
              ),
            );
            return;
          }
          httpsGetJson(headers.location, {
            redirectsLeft: redirectsLeft - 1,
          }).then(resolve, reject);
          return;
        }

        let body = "";
        res.on("data", (chunk) => (body += chunk));
        res.on("end", () => {
          if (statusCode === 403 || statusCode === 429) {
            reject(
              new InstallError(
                `GitHub API rate limit hit (HTTP ${statusCode}) while resolving the latest ` +
                  "Ghostties release.\nTry again in a few minutes, or download a release " +
                  `directly from https://github.com/${REPO}/releases.`,
              ),
            );
            return;
          }
          if (statusCode !== 200) {
            reject(
              new InstallError(
                `GitHub API request failed: HTTP ${statusCode} for ${url}.\n` +
                  "GitHub may be down, or the repository may be unreachable.",
              ),
            );
            return;
          }
          try {
            resolve(JSON.parse(body));
          } catch (err) {
            reject(
              new InstallError(
                `GitHub API returned a response that could not be parsed as JSON: ${err.message}`,
              ),
            );
          }
        });
        res.on("error", (err) => reject(err));
      },
    );

    request.on("error", (err) => {
      reject(
        new InstallError(
          `Network error while contacting the GitHub API at ${url}: ${err.message}`,
        ),
      );
    });
  });
}

async function resolveLatestRelease() {
  let releases;
  try {
    releases = await httpsGetJson(RELEASES_API_URL);
  } catch (err) {
    if (err instanceof InstallError) throw err;
    throw new InstallError(
      `Could not resolve the latest Ghostties release: ${err.message}`,
    );
  }

  if (!Array.isArray(releases) || releases.length === 0) {
    throw new InstallError(
      `No releases found for ${REPO}. This is unexpected — the project always has at ` +
        "least one published release. GitHub's API may be having issues.",
    );
  }

  // The API returns releases newest-first; drafts are never returned to
  // unauthenticated requests, but skip them defensively anyway.
  const release = releases.find((r) => !r.draft);
  if (!release) {
    throw new InstallError(
      `No published (non-draft) releases found for ${REPO}.`,
    );
  }

  const asset = (release.assets || []).find((a) => a.name === ASSET_NAME);
  if (!asset) {
    throw new InstallError(
      `Release ${release.tag_name} has no "${ASSET_NAME}" asset.\n` +
        `See https://github.com/${REPO}/releases/tag/${release.tag_name} for what it does have.`,
    );
  }

  if (!asset.digest || !asset.digest.startsWith("sha256:")) {
    throw new InstallError(
      `Release ${release.tag_name}'s "${ASSET_NAME}" asset has no sha256 digest from GitHub.\n` +
        "Refusing to install an asset that can't be integrity-checked.",
    );
  }

  return {
    tag: release.tag_name,
    downloadUrl: asset.browser_download_url,
    sha256: asset.digest.slice("sha256:".length),
  };
}

// ---------------------------------------------------------------------------
// Download with progress
// ---------------------------------------------------------------------------

function downloadWithProgress(url, destPath, { redirectsLeft = 5 } = {}) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, (res) => {
      const { statusCode, headers } = res;

      if (statusCode >= 300 && statusCode < 400 && headers.location) {
        res.resume();
        if (redirectsLeft <= 0) {
          reject(
            new InstallError(
              "Too many redirects while downloading the release asset.",
            ),
          );
          return;
        }
        downloadWithProgress(headers.location, destPath, {
          redirectsLeft: redirectsLeft - 1,
        }).then(resolve, reject);
        return;
      }

      if (statusCode !== 200) {
        res.resume();
        reject(
          new InstallError(
            `Download failed: server responded with HTTP ${statusCode} for ${url}.\n` +
              "The release asset may have moved or been removed.",
          ),
        );
        return;
      }

      const total = parseInt(headers["content-length"] || "0", 10);
      let downloaded = 0;
      const fileStream = fs.createWriteStream(destPath);

      res.on("data", (chunk) => {
        downloaded += chunk.length;
        if (total > 0 && process.stdout.isTTY) {
          const pct = ((downloaded / total) * 100).toFixed(1);
          const mb = (downloaded / 1024 / 1024).toFixed(1);
          const totalMb = (total / 1024 / 1024).toFixed(1);
          process.stdout.write(
            `\r  downloading… ${mb} / ${totalMb} MB (${pct}%)`,
          );
        }
      });

      res.pipe(fileStream);

      fileStream.on("finish", () => {
        if (process.stdout.isTTY) process.stdout.write("\n");
        fileStream.close(resolve);
      });

      fileStream.on("error", (err) => reject(err));
      res.on("error", (err) => reject(err));
    });

    request.on("error", (err) => {
      reject(
        new InstallError(
          `Network error while downloading ${url}: ${err.message}`,
        ),
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Checksum
// ---------------------------------------------------------------------------

function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
    stream.on("error", reject);
  });
}

// ---------------------------------------------------------------------------
// Code signature
// ---------------------------------------------------------------------------

function verifyCodeSignature(appPath) {
  // codesign writes its -dv/--verbose output to stderr regardless of
  // success or failure, so both streams have to be captured explicitly —
  // execFileSync only returns stdout on success.
  const result = spawnSync("codesign", ["-dv", "--verbose=4", appPath], {
    encoding: "utf8",
  });

  if (result.error) {
    throw new InstallError(
      `Could not run codesign to verify ${appPath}: ${result.error.message}`,
    );
  }

  const output = `${result.stdout || ""}${result.stderr || ""}`;

  if (result.status !== 0) {
    throw new InstallError(
      "Code signature verification FAILED.\n" +
        `codesign could not verify ${appPath}:\n${output || `exit code ${result.status}`}\n` +
        "This build will not be installed — it may be corrupted or tampered with.",
    );
  }

  const match = output.match(/TeamIdentifier=([A-Z0-9]+)/);
  const teamId = match ? match[1] : null;
  if (teamId !== EXPECTED_TEAM_ID) {
    throw new InstallError(
      "Code signature verification FAILED.\n" +
        `  expected team identifier: ${EXPECTED_TEAM_ID}\n` +
        `  actual:                   ${teamId || "(not found)"}\n` +
        "The app bundle is not signed by the identity Ghostties releases are signed with. " +
        "Not installing.",
    );
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  let downloadStarted = false;
  let workDir = null;
  try {
    const args = parseArgs(process.argv.slice(2));
    if (args.help) {
      printUsage();
      return;
    }

    checkPlatform(process.platform, process.arch);

    console.log("Resolving the latest Ghostties release…");
    const release = await resolveLatestRelease();

    const target = path.resolve(args.target);
    const destAppPath = path.join(target, APP_NAME);

    if (fs.existsSync(destAppPath)) {
      if (!args.force) {
        throw new InstallError(
          `${destAppPath} already exists.\n` +
            "Ghostties self-updates via Sparkle, so the installed copy may already be newer " +
            `than the ${release.tag} build this installer just resolved. Refusing to overwrite it.\n` +
            "Pass --force if you want this installer to replace it anyway.",
        );
      }
    }

    fs.mkdirSync(target, { recursive: true });

    workDir = fs.mkdtempSync(path.join(os.tmpdir(), "ghostties-install-"));
    const zipPath = path.join(workDir, ASSET_NAME);
    const extractDir = path.join(workDir, "extracted");

    console.log(`Ghostties installer — ${release.tag}`);
    console.log(`Target: ${destAppPath}`);
    console.log("");
    console.log(`Downloading ${ASSET_NAME} (~154 MB)…`);
    downloadStarted = true;
    await downloadWithProgress(release.downloadUrl, zipPath);

    console.log("Verifying checksum…");
    const actualSha256 = await sha256File(zipPath);
    if (actualSha256 !== release.sha256) {
      throw new InstallError(
        "Checksum verification FAILED.\n" +
          `  expected: ${release.sha256}\n` +
          `  actual:   ${actualSha256}\n` +
          "The downloaded file does not match the digest GitHub published for this release " +
          "and will be deleted. This could mean a corrupted download or a tampered asset — not installing.",
      );
    }
    console.log("Checksum OK.");

    console.log("Extracting…");
    fs.mkdirSync(extractDir, { recursive: true });
    // ditto (not unzip) to preserve extended attributes, symlinks, and
    // code-signature integrity on the .app bundle.
    execFileSync("ditto", ["-x", "-k", zipPath, extractDir], {
      stdio: "inherit",
    });

    const extractedAppPath = findApp(extractDir);
    if (!extractedAppPath) {
      throw new InstallError(
        `Could not find ${APP_NAME} inside the downloaded archive after extraction.`,
      );
    }

    console.log("Verifying code signature…");
    verifyCodeSignature(extractedAppPath);
    console.log("Code signature OK.");

    console.log(`Installing to ${destAppPath}…`);
    // Stage into a temp name in the target directory, then rename into place
    // so a failure mid-copy never leaves a half-written app at the real path.
    const stagingPath = path.join(
      target,
      `.${APP_NAME}.ghostties-install-staging`,
    );
    rmIfExists(stagingPath);
    execFileSync("ditto", [extractedAppPath, stagingPath], {
      stdio: "inherit",
    });

    if (args.force) {
      rmIfExists(destAppPath);
    }
    fs.renameSync(stagingPath, destAppPath);

    console.log("");
    console.log(`Installed ${APP_NAME} to ${target}.`);
    console.log(`Version: ${release.tag}`);
    console.log(
      "Ghostties updates itself from here on via Sparkle — no need to re-run this installer.",
    );
  } catch (err) {
    if (err instanceof InstallError) {
      console.error("");
      console.error(`Error: ${err.message}`);
    } else {
      console.error("");
      console.error(`Unexpected error: ${err.message}`);
    }
    process.exitCode = 1;
  } finally {
    if (downloadStarted) {
      rmIfExists(workDir, { recursive: true });
    }
  }
}

function findApp(rootDir) {
  const direct = path.join(rootDir, APP_NAME);
  if (fs.existsSync(direct)) return direct;
  const entries = fs.readdirSync(rootDir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isDirectory() && entry.name === APP_NAME) {
      return path.join(rootDir, entry.name);
    }
  }
  return null;
}

function rmIfExists(targetPath, opts = {}) {
  if (fs.existsSync(targetPath)) {
    fs.rmSync(targetPath, { recursive: true, force: true, ...opts });
  }
}

module.exports = { checkPlatform, InstallError, parseArgs };

if (require.main === module) {
  main();
}
