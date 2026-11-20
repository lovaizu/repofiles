// Finds the title of the front matter of a Markdown file, as
// front-matter-title.mjs finds it for textlint, and writes it as JSON:
// {line, value}, or nothing where the file has no such title. lib/lib.sh
// gives Vale the title as a heading at that line, as Vale reads the title
// of the front matter as plain text, which no heading rule reads.
//
// Usage: node title-line.mjs <node_modules> <file>
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { findTitle } from "./front-matter-title.mjs";

const [modules, file] = process.argv.slice(2);
const require = createRequire(path.join(path.resolve(modules), "x.js"));
const { builtInPlugins } = require("textlint/lib/src/loader/TextlintrcLoader.js");
const markdown = builtInPlugins.find((p) => p.pluginId === "@textlint/textlint-plugin-markdown").plugin;
const text = fs.readFileSync(file, "utf8");
const ast = new markdown.Processor({}).processor(path.extname(file)).preProcess(text, path.resolve(file));
const header = findTitle(require("js-yaml"), text, ast);
if (header) process.stdout.write(JSON.stringify({ line: header.loc.start.line, value: header.raw }));
