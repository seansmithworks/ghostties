#!/usr/bin/env node
"use strict";

/**
 * ghostties-install
 *
 * Downloads a pinned, checksum-verified release of Ghostties.app and places
 * it in /Applications (or --target). Zero runtime dependencies: only Node
 * built-ins and macOS system tools (`ditto`).
 *
 * The version/sha256 below are pinned deliberately. See README.md for why,
 * and for how to bump them (it's a manual edit, not automated).
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const https = require("https");
const crypto = require("crypto");
const { execFileSync } = require("child_process");

// ---------------------------------------------------------------------------
// Pinned release. Bump manually when a new release ships. See README.md.
// ---------------------------------------------------------------------------
const RELEASE = {
  tag: "v0.1.0-beta.22",
  assetName: "ghostties-macos-arm64.zip",
  sha256: "0542bd3db77ca60048e3f9aba5096c9779037139a52eee2bd82c6c3e1eea98fc",
};
const DOWNLOAD_URL = `https://github.com/SeanSmithWorks/ghostties/releases/download/${RELEASE.tag}/${RELEASE.assetName}`;
const APP_NAME = "Ghostties.app";

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

Pinned release: ${RELEASE.tag}
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

    const target = path.resolve(args.target);
    const destAppPath = path.join(target, APP_NAME);

    if (fs.existsSync(destAppPath)) {
      if (!args.force) {
        throw new InstallError(
          `${destAppPath} already exists.\n` +
            "Ghostties self-updates via Sparkle, so the installed copy may already be newer " +
            `than the ${RELEASE.tag} build this installer knows about. Refusing to overwrite it.\n` +
            "Pass --force if you want this installer to replace it anyway.",
        );
      }
    }

    fs.mkdirSync(target, { recursive: true });

    workDir = fs.mkdtempSync(path.join(os.tmpdir(), "ghostties-install-"));
    const zipPath = path.join(workDir, RELEASE.assetName);
    const extractDir = path.join(workDir, "extracted");

    console.log(`Ghostties installer — ${RELEASE.tag}`);
    console.log(`Target: ${destAppPath}`);
    console.log("");
    console.log(`Downloading ${RELEASE.assetName} (~154 MB)…`);
    downloadStarted = true;
    await downloadWithProgress(DOWNLOAD_URL, zipPath);

    console.log("Verifying checksum…");
    const actualSha256 = await sha256File(zipPath);
    if (actualSha256 !== RELEASE.sha256) {
      throw new InstallError(
        "Checksum verification FAILED.\n" +
          `  expected: ${RELEASE.sha256}\n` +
          `  actual:   ${actualSha256}\n` +
          "The downloaded file does not match the pinned release and will be deleted. " +
          "This could mean a corrupted download or a tampered asset — not installing.",
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
    console.log(`Version: ${RELEASE.tag}`);
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
