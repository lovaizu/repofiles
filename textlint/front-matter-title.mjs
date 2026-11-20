// The textlint plugin that reads Markdown as the Markdown plugin of
// textlint does, and gives the title of the front matter to each rule as
// a heading, at its place in the file. The Markdown plugin puts the whole
// front matter into one Yaml node, which no rule reads, so a rule would
// pass any title.
//
// It reads only a title of YAML front matter on one line, quoted or not,
// whose text is the value that YAML gives: a title on more lines, or with
// an escape or a comment, has no one place in the file for each character.
//
// check.mjs loads the plugin with the modules of textlint: the default
// export takes the function require of those modules and the Markdown
// plugin of textlint, and returns the plugin. title-line.mjs finds the
// same title for Vale, with findTitle.

// Finds the title in text $text, whose tree from the Markdown plugin is
// $ast, with the js-yaml module $yaml. Returns the Header that holds the
// title as a Str, or nothing.
export function findTitle(yaml, text, ast) {
  const front = ast.children[0];
  if (front?.type !== "Yaml") return;
  const raw = text.slice(...front.range);
  const line = raw.match(/^title:[ \t]*(?:'([^'\r\n]*)'|"([^"\\\r\n]*)"|([^'"\s][^\r\n]*?))[ \t]*$/m);
  const value = line && (line[1] ?? line[2] ?? line[3]);
  let title;
  try {
    title = yaml.load(front.value)?.title;
  } catch {
    return;
  }
  if (!value || title !== value) return;
  const start = front.range[0] + line.index + line[0].indexOf(value, "title:".length);
  const range = [start, start + value.length];
  const at = (i) => ({ line: text.slice(0, i).split("\n").length, column: i - text.lastIndexOf("\n", i - 1) - 1 });
  const loc = { start: at(range[0]), end: at(range[1]) };
  const str = { type: "Str", value, raw: value, range, loc };
  return { type: "Header", depth: 1, children: [str], raw: value, range, loc };
}

export default (require, markdown) => {
  const yaml = require("js-yaml");
  class Processor extends markdown.Processor {
    processor(ext) {
      const { preProcess, postProcess } = super.processor(ext);
      return {
        postProcess,
        preProcess(text, filePath) {
          const ast = preProcess(text, filePath);
          const header = findTitle(yaml, text, ast);
          if (header) ast.children.splice(1, 0, header);
          return ast;
        },
      };
    }
  }
  return { Processor };
};
