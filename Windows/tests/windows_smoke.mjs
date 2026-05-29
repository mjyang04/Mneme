import test from "node:test";
import assert from "node:assert/strict";
import { cp, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createWindowsPreviewApp } from "../mneme-windows.mjs";

const TEST_DIR = path.dirname(fileURLToPath(import.meta.url));
const WINDOWS_DIR = path.dirname(TEST_DIR);
const FIXTURES_DIR = path.join(WINDOWS_DIR, "fixtures");

test("Windows preview indexes local sources, searches, answers, and imports transcripts", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "mneme-windows-preview-"));
  const dataDir = path.join(root, "data");
  const sourceDir = path.join(root, "source");
  await mkdir(sourceDir, { recursive: true });
  await cp(FIXTURES_DIR, sourceDir, { recursive: true });
  await writeFile(
    path.join(sourceDir, "meeting-notes.txt"),
    "Activity summary: Mneme watched local research folders and generated private daily notes.\n",
    "utf8"
  );

  const app = await createWindowsPreviewApp({ dataDir, port: 0, logErrors: false });
  const address = await app.listen(0);
  const base = `http://127.0.0.1:${address.port}`;

  try {
    const source = await postJson(`${base}/api/sources`, {
      kind: "folder",
      path: sourceDir
    });
    assert.equal(source.kind, "folder");

    const stats = await postJson(`${base}/api/index/rebuild`, {});
    assert.ok(stats.documents >= 3);
    assert.equal(stats.warnings.length, 0);

    const search = await getJson(`${base}/api/search?q=${encodeURIComponent("local research citations")}`);
    assert.ok(search.hits.length >= 1);
    assert.match(search.hits[0].snippet, /local/i);

    const answer = await getJson(`${base}/api/answer?q=${encodeURIComponent("Where does Mneme keep research data?")}`);
    assert.match(answer.answer, /\[1\]/);
    assert.ok(answer.citations.length >= 1);

    const transcript = await postJson(`${base}/api/transcripts/import-text`, {
      title: "Design review",
      text: "The Windows interface mirrors Mneme search, sources, transcripts, activity, and settings."
    });
    assert.equal(transcript.title, "Design review");

    const rebuilt = await postJson(`${base}/api/index/rebuild`, {});
    assert.ok(rebuilt.documents >= stats.documents);

    const status = await getJson(`${base}/api/status`);
    assert.equal(status.sources.length, 1);
    assert.equal(status.transcripts.length, 1);
    assert.ok(status.index.chunks > 0);
    assert.match(status.dataDir, /data$/);

    const html = await getText(`${base}/`);
    assert.match(html, /Search \/ Ask/);
    assert.match(html, /Transcripts/);
    assert.match(html, /Activity/);
    assert.match(await getText(`${base}/styles.css`), /\.shell/);
    assert.match(await getText(`${base}/app.js`), /performSearch/);

    const localHtml = await readFile(path.join(WINDOWS_DIR, "app", "index.html"), "utf8");
    assert.match(localHtml, /Windows Preview/);
  } finally {
    await app.close();
    await rm(root, { recursive: true, force: true });
  }
});

async function getJson(url) {
  const response = await fetch(url);
  if (!response.ok) {
    assert.fail(await response.text());
  }
  return response.json();
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!response.ok) {
    assert.fail(await response.text());
  }
  return response.json();
}

async function getText(url) {
  const response = await fetch(url);
  if (!response.ok) {
    assert.fail(await response.text());
  }
  return response.text();
}
