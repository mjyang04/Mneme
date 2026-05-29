#!/usr/bin/env node
import { createServer } from "node:http";
import { createReadStream, existsSync } from "node:fs";
import {
  access,
  mkdir,
  readdir,
  readFile,
  rename,
  stat,
  unlink,
  writeFile
} from "node:fs/promises";
import { spawn } from "node:child_process";
import crypto from "node:crypto";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));
const APP_DIR = path.join(MODULE_DIR, "app");
const MAX_BODY_BYTES = 8 * 1024 * 1024;
const MAX_FILE_BYTES = 2 * 1024 * 1024;
const MAX_SCAN_FILES = 4_000;
const MAX_INDEX_CHARS = 1_400;
const DEFAULT_PORT = 47732;

const TEXT_EXTENSIONS = new Set([
  ".md",
  ".markdown",
  ".mdx",
  ".txt",
  ".rst",
  ".org",
  ".tex",
  ".csv",
  ".tsv",
  ".json",
  ".jsonl",
  ".yaml",
  ".yml",
  ".toml",
  ".ini",
  ".log"
]);

const CODE_EXTENSIONS = new Set([
  ".swift",
  ".js",
  ".mjs",
  ".cjs",
  ".ts",
  ".tsx",
  ".jsx",
  ".py",
  ".rs",
  ".go",
  ".java",
  ".kt",
  ".kts",
  ".cs",
  ".cpp",
  ".cc",
  ".c",
  ".h",
  ".hpp",
  ".m",
  ".mm",
  ".sh",
  ".bash",
  ".zsh",
  ".ps1",
  ".sql",
  ".html",
  ".css",
  ".scss",
  ".xml",
  ".vue",
  ".svelte"
]);

const TRANSCRIPT_EXTENSIONS = new Set([".vtt", ".srt", ".transcript", ".txt", ".md"]);
const PDF_EXTENSIONS = new Set([".pdf"]);
const SKIPPED_DIRECTORIES = new Set([
  ".git",
  ".svn",
  ".hg",
  ".build",
  ".cache",
  ".swiftpm",
  "DerivedData",
  "node_modules",
  "dist",
  "build",
  "target",
  "__pycache__"
]);

const STOP_WORDS = new Set([
  "a",
  "an",
  "and",
  "are",
  "as",
  "at",
  "be",
  "by",
  "for",
  "from",
  "how",
  "in",
  "is",
  "it",
  "of",
  "on",
  "or",
  "that",
  "the",
  "this",
  "to",
  "was",
  "what",
  "when",
  "where",
  "with"
]);

export function resolveDataDir(explicitDataDir) {
  if (explicitDataDir) {
    return path.resolve(explicitDataDir);
  }

  if (process.env.MNEME_WINDOWS_DATA_DIR) {
    return path.resolve(process.env.MNEME_WINDOWS_DATA_DIR);
  }

  if (process.platform === "win32" && process.env.APPDATA) {
    return path.join(process.env.APPDATA, "Mneme");
  }

  if (process.platform === "darwin") {
    return path.join(os.homedir(), "Library", "Application Support", "Mneme", "WindowsDesktop");
  }

  return path.join(os.homedir(), ".local", "share", "Mneme", "WindowsDesktop");
}

export async function createWindowsPreviewApp(options = {}) {
  return createWindowsDesktopBackend(options);
}

export async function createWindowsDesktopBackend(options = {}) {
  const dataDir = resolveDataDir(options.dataDir);
  const platformName = options.platformName ?? "windows-desktop";
  await mkdir(dataDir, { recursive: true });

  const routes = {
    async addSource(payload) {
      const sourcePath = normalizePath(String(payload.path ?? ""));
      const kind = normalizeKind(payload.kind);
      if (!sourcePath) {
        throw httpError(400, "Source path is required.");
      }
      const info = await safeStat(sourcePath);
      if (!info?.isDirectory()) {
        throw httpError(400, `Source folder does not exist: ${sourcePath}`);
      }
      const sources = await readJson(dataFile(dataDir, "sources.json"), []);
      const existing = sources.find((source) => samePath(source.path, sourcePath) && source.kind === kind);
      if (existing) {
        return existing;
      }
      const source = {
        id: crypto.randomUUID(),
        kind,
        path: sourcePath,
        addedAt: new Date().toISOString()
      };
      sources.push(source);
      await writeJson(dataFile(dataDir, "sources.json"), sources);
      return source;
    },

    async deleteSource(sourceId) {
      const sources = await readJson(dataFile(dataDir, "sources.json"), []);
      const next = sources.filter((source) => source.id !== sourceId);
      await writeJson(dataFile(dataDir, "sources.json"), next);
      return { deleted: sources.length - next.length };
    },

    async listStatus() {
      const sources = await readJson(dataFile(dataDir, "sources.json"), []);
      const transcripts = await readJson(dataFile(dataDir, "transcripts.json"), []);
      const index = await readJson(dataFile(dataDir, "index.json"), emptyIndex());
      const settings = await readJson(dataFile(dataDir, "settings.json"), defaultSettings());
      return {
        platform: platformName,
        dataDir,
        sources,
        transcripts,
        settings,
        index: {
          builtAt: index.builtAt,
          chunks: index.chunks.length,
          documents: index.stats.documents,
          skipped: index.stats.skipped,
          warnings: index.stats.warnings
        },
        capabilities: windowsCapabilities()
      };
    },

    async rebuildIndex() {
      return rebuildIndex(dataDir);
    },

    async search(query, filters = {}) {
      const index = await readJson(dataFile(dataDir, "index.json"), emptyIndex());
      const hits = searchIndex(index, String(query ?? ""), filters);
      return { query, hits };
    },

    async answer(query) {
      const index = await readJson(dataFile(dataDir, "index.json"), emptyIndex());
      return answerFromIndex(index, String(query ?? ""));
    },

    async listTranscripts() {
      return readJson(dataFile(dataDir, "transcripts.json"), []);
    },

    async importTranscript(payload) {
      const title = String(payload.title ?? "").trim() || "Untitled transcript";
      const text = String(payload.text ?? "").trim();
      if (!text) {
        throw httpError(400, "Transcript text is required.");
      }
      const transcripts = await readJson(dataFile(dataDir, "transcripts.json"), []);
      const transcript = {
        id: crypto.randomUUID(),
        title,
        text,
        sourcePath: payload.sourcePath ? normalizePath(String(payload.sourcePath)) : null,
        createdAt: new Date().toISOString()
      };
      transcripts.unshift(transcript);
      await writeJson(dataFile(dataDir, "transcripts.json"), transcripts);
      return transcript;
    },

    async activity() {
      const sources = await readJson(dataFile(dataDir, "sources.json"), []);
      return collectActivity(sources);
    },

    async updateSettings(payload) {
      const current = await readJson(dataFile(dataDir, "settings.json"), defaultSettings());
      const settings = {
        ...current,
        quickSearchHotkey: String(payload.quickSearchHotkey ?? current.quickSearchHotkey),
        askTopK: clampNumber(payload.askTopK, 3, 12, current.askTopK)
      };
      await writeJson(dataFile(dataDir, "settings.json"), settings);
      return settings;
    }
  };

  const server = createServer(async (request, response) => {
    try {
      await handleRequest(request, response, routes);
    } catch (error) {
      const status = error.statusCode || 500;
      sendJson(response, status, {
        error: status === 500 ? "Internal server error." : error.message
      });
      if (status === 500 && options.logErrors !== false) {
        console.error(error);
      }
    }
  });

  return {
    dataDir,
    server,
    routes,
    listen(port = options.port ?? DEFAULT_PORT, host = options.host ?? "127.0.0.1") {
      return new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(port, host, () => {
          server.off("error", reject);
          resolve(server.address());
        });
      });
    },
    close() {
      return new Promise((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      });
    }
  };
}

async function handleRequest(request, response, routes) {
  const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");
  if (request.method === "OPTIONS") {
    setCors(response);
    response.writeHead(204);
    response.end();
    return;
  }

  if (request.method === "GET" && requestUrl.pathname === "/api/status") {
    sendJson(response, 200, await routes.listStatus());
    return;
  }

  if (request.method === "POST" && requestUrl.pathname === "/api/sources") {
    sendJson(response, 200, await routes.addSource(await readBodyJson(request)));
    return;
  }

  if (request.method === "DELETE" && requestUrl.pathname.startsWith("/api/sources/")) {
    const sourceId = decodeURIComponent(requestUrl.pathname.slice("/api/sources/".length));
    sendJson(response, 200, await routes.deleteSource(sourceId));
    return;
  }

  if (request.method === "POST" && requestUrl.pathname === "/api/index/rebuild") {
    sendJson(response, 200, await routes.rebuildIndex());
    return;
  }

  if (request.method === "GET" && requestUrl.pathname === "/api/search") {
    sendJson(response, 200, await routes.search(requestUrl.searchParams.get("q") ?? "", {
      kind: requestUrl.searchParams.get("kind") ?? ""
    }));
    return;
  }

  if (request.method === "GET" && requestUrl.pathname === "/api/answer") {
    sendJson(response, 200, await routes.answer(requestUrl.searchParams.get("q") ?? ""));
    return;
  }

  if (request.method === "GET" && requestUrl.pathname === "/api/transcripts") {
    sendJson(response, 200, await routes.listTranscripts());
    return;
  }

  if (request.method === "POST" && requestUrl.pathname === "/api/transcripts/import-text") {
    sendJson(response, 200, await routes.importTranscript(await readBodyJson(request)));
    return;
  }

  if (request.method === "GET" && requestUrl.pathname === "/api/activity") {
    sendJson(response, 200, await routes.activity());
    return;
  }

  if (request.method === "POST" && requestUrl.pathname === "/api/settings") {
    sendJson(response, 200, await routes.updateSettings(await readBodyJson(request)));
    return;
  }

  await serveStatic(requestUrl.pathname, response);
}

async function serveStatic(urlPath, response) {
  const pathname = urlPath === "/" ? "/index.html" : decodeURIComponent(urlPath);
  const candidate = path.normalize(path.join(APP_DIR, pathname));
  if (!candidate.startsWith(APP_DIR)) {
    throw httpError(403, "Forbidden.");
  }

  const info = await safeStat(candidate);
  if (!info?.isFile()) {
    throw httpError(404, "Not found.");
  }

  response.writeHead(200, {
    "Content-Type": mimeType(candidate),
    "Cache-Control": "no-store"
  });
  createReadStream(candidate).pipe(response);
}

async function rebuildIndex(dataDir) {
  const sources = await readJson(dataFile(dataDir, "sources.json"), []);
  const transcripts = await readJson(dataFile(dataDir, "transcripts.json"), []);
  const warnings = [];
  const chunks = [];
  let filesSeen = 0;
  let filesIndexed = 0;
  let skipped = 0;

  for (const source of sources) {
    const root = normalizePath(source.path);
    const rootInfo = await safeStat(root);
    if (!rootInfo?.isDirectory()) {
      warnings.push(`Missing source folder: ${root}`);
      continue;
    }

    for await (const filePath of walkFiles(root, MAX_SCAN_FILES - filesSeen)) {
      filesSeen += 1;
      const ext = path.extname(filePath).toLowerCase();
      if (!isSupportedFile(ext, source.kind)) {
        skipped += 1;
        continue;
      }
      const fileInfo = await safeStat(filePath);
      if (!fileInfo?.isFile()) {
        skipped += 1;
        continue;
      }
      if (fileInfo.size > MAX_FILE_BYTES && !PDF_EXTENSIONS.has(ext)) {
        skipped += 1;
        warnings.push(`Skipped large file: ${filePath}`);
        continue;
      }

      const document = await loadDocument(root, source, filePath, fileInfo);
      if (!document) {
        skipped += 1;
        continue;
      }
      chunks.push(...chunkDocument(document));
      filesIndexed += 1;

      if (filesSeen >= MAX_SCAN_FILES) {
        warnings.push(`Stopped after ${MAX_SCAN_FILES} files to keep the desktop app responsive.`);
        break;
      }
    }
  }

  for (const transcript of transcripts) {
    chunks.push(...chunkDocument({
      documentId: `transcript:${transcript.id}`,
      sourceId: "transcripts",
      kind: "transcript",
      title: transcript.title,
      path: transcript.sourcePath,
      locator: transcript.createdAt,
      text: transcript.text
    }));
  }

  const index = {
    builtAt: new Date().toISOString(),
    chunks,
    stats: {
      filesSeen,
      filesIndexed,
      documents: new Set(chunks.map((chunk) => chunk.documentId)).size,
      skipped,
      warnings
    }
  };
  await writeJson(dataFile(dataDir, "index.json"), index);
  return index.stats;
}

async function loadDocument(root, source, filePath, fileInfo) {
  const ext = path.extname(filePath).toLowerCase();
  const relativePath = path.relative(root, filePath);
  const baseTitle = path.basename(filePath);
  const kind = inferKind(source.kind, ext);
  let text = "";

  if (PDF_EXTENSIONS.has(ext)) {
    text = [
      `PDF document: ${baseTitle}.`,
      `Path: ${filePath}.`,
      "The Windows desktop build indexes PDF metadata only; full PDF text extraction remains a native Windows adapter task."
    ].join(" ");
  } else {
    text = await readFile(filePath, "utf8");
  }

  const normalized = normalizeText(text);
  if (!normalized) {
    return null;
  }

  return {
    documentId: stableId(`${source.id}:${filePath}:${fileInfo.mtimeMs}`),
    sourceId: source.id,
    kind,
    title: titleFromContent(baseTitle, normalized),
    path: filePath,
    locator: relativePath,
    text: normalized
  };
}

function chunkDocument(document) {
  const blocks = splitBlocks(document.text);
  const chunks = [];
  let current = "";
  let chunkIndex = 0;

  for (const block of blocks) {
    if ((current + "\n\n" + block).length > MAX_INDEX_CHARS && current) {
      chunks.push(makeChunk(document, current, chunkIndex));
      chunkIndex += 1;
      current = "";
    }
    current = current ? `${current}\n\n${block}` : block;
  }

  if (current) {
    chunks.push(makeChunk(document, current, chunkIndex));
  }

  return chunks;
}

function makeChunk(document, text, chunkIndex) {
  return {
    id: `${document.documentId}#${chunkIndex}`,
    documentId: document.documentId,
    sourceId: document.sourceId,
    kind: document.kind,
    title: document.title,
    path: document.path,
    locator: document.locator,
    text,
    tokens: tokenize(text)
  };
}

function searchIndex(index, query, filters = {}) {
  const tokens = tokenize(query);
  const normalizedQuery = normalizeForSearch(query);
  if (!tokens.length && !normalizedQuery) {
    return [];
  }

  const termIdf = new Map();
  for (const token of new Set(tokens)) {
    let docsWithTerm = 0;
    for (const chunk of index.chunks) {
      if (chunk.tokens?.includes(token)) {
        docsWithTerm += 1;
      }
    }
    termIdf.set(token, Math.log((1 + index.chunks.length) / (1 + docsWithTerm)) + 1);
  }

  return index.chunks
    .filter((chunk) => !filters.kind || chunk.kind === filters.kind)
    .map((chunk) => {
      const tokenCounts = countTokens(chunk.tokens ?? []);
      let score = 0;
      for (const token of tokens) {
        score += (tokenCounts.get(token) ?? 0) * (termIdf.get(token) ?? 1);
      }
      const haystack = normalizeForSearch(`${chunk.title} ${chunk.text}`);
      if (normalizedQuery && haystack.includes(normalizedQuery)) {
        score += 8;
      }
      if (chunk.title && normalizeForSearch(chunk.title).includes(normalizedQuery)) {
        score += 4;
      }
      return {
        id: chunk.id,
        documentId: chunk.documentId,
        kind: chunk.kind,
        title: chunk.title,
        path: chunk.path,
        locator: chunk.locator,
        score: Number(score.toFixed(4)),
        snippet: bestSnippet(chunk.text, tokens)
      };
    })
    .filter((hit) => hit.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 20);
}

function answerFromIndex(index, query) {
  const hits = searchIndex(index, query, {}).slice(0, 5);
  if (!hits.length) {
    return {
      answer: "No local evidence matched this question in the Windows desktop index.",
      citations: []
    };
  }

  const chunkById = new Map(index.chunks.map((chunk) => [chunk.id, chunk]));
  const tokens = tokenize(query);
  const answerParts = [];
  const citations = [];

  hits.forEach((hit, index) => {
    const chunk = chunkById.get(hit.id);
    const sentence = bestSentence(chunk?.text ?? hit.snippet, tokens);
    citations.push({
      number: index + 1,
      title: hit.title,
      path: hit.path,
      locator: hit.locator,
      kind: hit.kind
    });
    if (sentence) {
      answerParts.push(`${sentence} [${index + 1}]`);
    }
  });

  return {
    answer: answerParts.join(" "),
    citations
  };
}

async function collectActivity(sources) {
  const projects = [];
  for (const source of sources) {
    const root = normalizePath(source.path);
    const rootInfo = await safeStat(root);
    if (!rootInfo?.isDirectory()) {
      continue;
    }
    const recentFiles = [];
    for await (const filePath of walkFiles(root, 120)) {
      const info = await safeStat(filePath);
      if (info?.isFile()) {
        recentFiles.push({
          path: filePath,
          relativePath: path.relative(root, filePath),
          modifiedAt: new Date(info.mtimeMs).toISOString()
        });
      }
    }
    recentFiles.sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt));
    projects.push({
      name: path.basename(root) || root,
      root,
      recentFiles: recentFiles.slice(0, 20),
      commits: await gitCommits(root)
    });
  }
  return {
    day: new Date().toISOString().slice(0, 10),
    projects
  };
}

function gitCommits(root) {
  if (!existsSync(path.join(root, ".git"))) {
    return [];
  }
  return new Promise((resolve) => {
    const child = spawn("git", ["-C", root, "log", "--oneline", "--max-count=5"], {
      stdio: ["ignore", "pipe", "ignore"]
    });
    let output = "";
    child.stdout.on("data", (chunk) => {
      output += chunk.toString("utf8");
    });
    child.on("close", () => {
      resolve(output
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean)
        .map((line) => {
          const [hash, ...message] = line.split(" ");
          return { hash, message: message.join(" ") };
        }));
    });
    child.on("error", () => resolve([]));
  });
}

async function* walkFiles(root, limit) {
  const stack = [root];
  let yielded = 0;
  while (stack.length && yielded < limit) {
    const directory = stack.pop();
    let entries = [];
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      continue;
    }
    entries.sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        if (!SKIPPED_DIRECTORIES.has(entry.name)) {
          stack.push(absolute);
        }
      } else if (entry.isFile()) {
        yielded += 1;
        yield absolute;
        if (yielded >= limit) {
          return;
        }
      }
    }
  }
}

function isSupportedFile(ext, sourceKind) {
  if (PDF_EXTENSIONS.has(ext)) {
    return sourceKind === "papers" || sourceKind === "folder";
  }
  if (CODE_EXTENSIONS.has(ext)) {
    return sourceKind === "code" || sourceKind === "folder";
  }
  if (TRANSCRIPT_EXTENSIONS.has(ext) && sourceKind === "transcripts") {
    return true;
  }
  return TEXT_EXTENSIONS.has(ext) || sourceKind === "notes" || sourceKind === "activity";
}

function inferKind(sourceKind, ext) {
  if (sourceKind && sourceKind !== "folder") {
    return sourceKind.slice(0, -1) || sourceKind;
  }
  if (PDF_EXTENSIONS.has(ext)) return "paper";
  if (CODE_EXTENSIONS.has(ext)) return "code";
  return "notes";
}

function splitBlocks(text) {
  return text
    .split(/\n{2,}/)
    .map((block) => block.trim())
    .filter(Boolean)
    .flatMap((block) => {
      if (block.length <= MAX_INDEX_CHARS) {
        return [block];
      }
      const parts = [];
      for (let offset = 0; offset < block.length; offset += MAX_INDEX_CHARS) {
        parts.push(block.slice(offset, offset + MAX_INDEX_CHARS));
      }
      return parts;
    });
}

function bestSnippet(text, tokens) {
  const sentences = splitSentences(text);
  return bestSentenceFromList(sentences, tokens).slice(0, 360);
}

function bestSentence(text, tokens) {
  return bestSentenceFromList(splitSentences(text), tokens).slice(0, 500);
}

function bestSentenceFromList(sentences, tokens) {
  if (!sentences.length) {
    return "";
  }
  const tokenSet = new Set(tokens);
  let best = sentences[0];
  let bestScore = -1;
  for (const sentence of sentences) {
    const score = tokenize(sentence).filter((token) => tokenSet.has(token)).length;
    if (score > bestScore) {
      best = sentence;
      bestScore = score;
    }
  }
  return best.trim();
}

function splitSentences(text) {
  return normalizeText(text)
    .split(/(?<=[.!?。！？])\s+|\n+/)
    .map((sentence) => sentence.trim())
    .filter(Boolean);
}

function tokenize(text) {
  return normalizeForSearch(text)
    .split(/[^\p{L}\p{N}_-]+/u)
    .map((token) => token.trim())
    .filter((token) => token.length > 1 && !STOP_WORDS.has(token))
    .slice(0, 1_000);
}

function countTokens(tokens) {
  const counts = new Map();
  for (const token of tokens) {
    counts.set(token, (counts.get(token) ?? 0) + 1);
  }
  return counts;
}

function titleFromContent(fileName, text) {
  const heading = text.match(/^#\s+(.+)$/m);
  return heading?.[1]?.trim() || fileName;
}

function normalizeText(text) {
  return String(text)
    .replace(/\r\n/g, "\n")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function normalizeForSearch(text) {
  return normalizeText(text).toLocaleLowerCase();
}

function stableId(input) {
  return crypto.createHash("sha256").update(input).digest("hex").slice(0, 20);
}

function normalizeKind(kind) {
  const value = String(kind ?? "folder").trim().toLowerCase();
  if (["notes", "papers", "code", "transcripts", "activity", "folder"].includes(value)) {
    return value;
  }
  return "folder";
}

function normalizePath(value) {
  return value.trim() ? path.resolve(value.trim()) : "";
}

function samePath(lhs, rhs) {
  return path.normalize(lhs).toLocaleLowerCase() === path.normalize(rhs).toLocaleLowerCase();
}

function clampNumber(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return fallback;
  }
  return Math.max(min, Math.min(max, Math.round(number)));
}

function dataFile(dataDir, name) {
  return path.join(dataDir, name);
}

function emptyIndex() {
  return {
    builtAt: null,
    chunks: [],
    stats: {
      filesSeen: 0,
      filesIndexed: 0,
      documents: 0,
      skipped: 0,
      warnings: []
    }
  };
}

function defaultSettings() {
  return {
    quickSearchHotkey: "Ctrl+Space",
    askTopK: 5
  };
}

function windowsCapabilities() {
  return [
    "Tray-style local workbench layout",
    "Folder source registration",
    "Local notes/code/text indexing",
    "PDF metadata indexing",
    "Local lexical search",
    "Extractive Ask answers with citations",
    "Transcript text import and indexing",
    "Activity scan for recent files and git commits",
    "Local data directory under %APPDATA%\\\\Mneme on Windows"
  ];
}

async function safeStat(filePath) {
  try {
    return await stat(filePath);
  } catch {
    return null;
  }
}

async function readJson(filePath, fallback) {
  try {
    await access(filePath);
    return JSON.parse(await readFile(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

async function writeJson(filePath, value) {
  await mkdir(path.dirname(filePath), { recursive: true });
  const temporary = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  try {
    await rename(temporary, filePath);
  } catch (error) {
    await unlink(temporary).catch(() => {});
    throw error;
  }
}

async function readBodyJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      throw httpError(413, "Request body is too large.");
    }
    chunks.push(chunk);
  }
  if (!chunks.length) {
    return {};
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw httpError(400, "Request body must be valid JSON.");
  }
}

function sendJson(response, status, payload) {
  setCors(response);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(`${JSON.stringify(payload, null, 2)}\n`);
}

function setCors(response) {
  response.setHeader("Access-Control-Allow-Origin", "http://127.0.0.1");
  response.setHeader("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS");
  response.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function mimeType(filePath) {
  switch (path.extname(filePath).toLowerCase()) {
    case ".html":
      return "text/html; charset=utf-8";
    case ".css":
      return "text/css; charset=utf-8";
    case ".js":
    case ".mjs":
      return "text/javascript; charset=utf-8";
    case ".svg":
      return "image/svg+xml";
    default:
      return "application/octet-stream";
  }
}

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function parseArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--port") {
      options.port = Number(argv[index + 1]);
      index += 1;
    } else if (arg === "--host") {
      options.host = argv[index + 1];
      index += 1;
    } else if (arg === "--data-dir") {
      options.dataDir = argv[index + 1];
      index += 1;
    }
  }
  return options;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const app = await createWindowsDesktopBackend(options);
  const address = await app.listen(options.port ?? DEFAULT_PORT, options.host ?? "127.0.0.1");
  const host = typeof address === "object" && address ? address.address : options.host ?? "127.0.0.1";
  const port = typeof address === "object" && address ? address.port : options.port ?? DEFAULT_PORT;
  console.log(`Mneme Windows desktop backend running at http://${host}:${port}`);
  console.log(`Data directory: ${app.dataDir}`);

  const shutdown = async () => {
    await app.close().catch(() => {});
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (invokedPath && invokedPath === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
