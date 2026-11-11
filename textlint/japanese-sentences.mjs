// A filter rule that leaves out each finding in a sentence that holds no
// Japanese: no Hiragana, Katakana or Kanji. The rules of the Japanese check
// read any sentence as Japanese, so an English sentence of a file that holds
// both languages would fail them, such as ja-technical-writing/sentence-length.
// It splits the text into sentences as the rules do, with sentence-splitter,
// and leaves out only a finding that lies in one sentence.
const japanese = /[\p{sc=Hiragana}\p{sc=Katakana}\p{sc=Han}]/u;

export default (require) => {
  const { splitAST, SentenceSplitterSyntax } = require("sentence-splitter");
  return (context) => {
    const { Syntax, getSource, shouldIgnore } = context;
    // Each node that holds sentences of its own.
    const split = (node) => {
      for (const sentence of splitAST(node).children) {
        if (sentence.type === SentenceSplitterSyntax.Sentence && !japanese.test(getSource(sentence))) {
          shouldIgnore(sentence.range, { ruleId: "*" });
        }
      }
    };
    return { [Syntax.Paragraph]: split, [Syntax.Header]: split, [Syntax.TableCell]: split };
  };
};
