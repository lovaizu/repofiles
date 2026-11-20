// The textlint rule ja-no-unneeded-comma, which finds a comma (、) right
// after a particle, wherever it stands in a sentence. A comma marks a break
// after a predicate, a noun, a conjunction or an adverb, as in
// 設定ファイルを読み込み、ポートを決定する and 速い、ただし高い. A particle
// ties its word to what follows, so a comma after it marks no break. Where
// the sentence reads badly without the comma, the writer rewrites the
// sentence instead of keeping the comma, so the rule has no exception that
// a writer would have to learn. Issue #15 holds the problem.
//
// check.mjs loads the rule with the modules of textlint: the default
// export takes the function require of those modules, and returns the rule.

const opens = /[「『（(［\[【〈《]/g;
const closes = /[」』）)］\]】〉》]/g;

// sentence-splitter stops at the first text that no child of the paragraph
// holds, and drops the rest of the paragraph. In a list item, the
// indentation after a hard break is such text, so each hard break reaches
// to the next child, and the splitter reads on.
const reachNext = (node, Break) => ({
  ...node,
  children: node.children.map((child, i, all) =>
    child.type === Break && all[i + 1]
      ? { ...child, range: [child.range[0], all[i + 1].range[0]], loc: { ...child.loc, end: all[i + 1].loc.start } }
      : child,
  ),
});

export default (require) => {
  const { tokenize } = require("kuromojin");
  const { splitAST, SentenceSplitterSyntax } = require("sentence-splitter");
  const { StringSource } = require("textlint-util-to-string");
  return (context) => {
    const { Syntax, RuleError, report, locator } = context;
    // Finds each comma right after a particle in the text of $node, which
    // holds only inline nodes. A heading, such as the title of the front
    // matter that front-matter-title.mjs gives as one, and a cell of a
    // table hold text as a paragraph does, and none of them holds another.
    async function check(node) {
      const sentences = splitAST(reachNext(node, Syntax.Break)).children.filter((child) => child.type === SentenceSplitterSyntax.Sentence);
      for (const sentence of sentences) {
        // Code reads as a word of the sentence, by the mask of each of its
        // characters.
        const source = new StringSource(sentence, {
          replacer: ({ node: child, maskValue }) => (child.type === Syntax.Code ? maskValue("_") : undefined),
        });
        const text = source.toString();
        if (!text.includes("、")) continue;
        const tokens = await tokenize(text);
        tokens.forEach((t, i) => {
          if (t.surface_form !== "、" || tokens[i - 1]?.pos !== "助詞") return;
          const index = t.word_position - 1;
          // A comma inside brackets, as in 「設定は、」, belongs to the
          // quote, not to the sentence.
          const before = text.slice(0, index);
          if ((before.match(opens) || []).length > (before.match(closes) || []).length) return;
          const at = sentence.range[0] - node.range[0] + source.originalIndexFromIndex(index);
          report(
            node,
            new RuleError("助詞のあとの読点です。助詞は語を後ろの語へつなぐため、そのあとの読点は文の切れ目を示しません。読点を消してください。消すと読みにくい文なら、文を書き直してください。たとえば節の終わりを述語の連用形や名詞にする、または文を分けます。", {
              padding: locator.range([at, at + 1]),
            }),
          );
        });
      }
    }
    return {
      [Syntax.Paragraph]: check,
      [Syntax.Header]: check,
      [Syntax.TableCell]: check,
    };
  };
};
