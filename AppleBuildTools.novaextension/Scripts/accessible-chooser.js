// Shows a list in the reader's native chooser window, which VoiceOver can read, instead of
// Nova's choice palette, which VoiceOver cannot see. The helper opens it in front and waits.
class AccessibleChooser {
  constructor(dependencies) {
    this.helper = dependencies.helper;
    this.readerPath = dependencies.readerPath;
  }

  // Resolves to { choice, index }, or null when cancelled; rejects when the chooser cannot open.
  async choose(labels, prompt) {
    const answer = await this.helper.invoke(
      "choose",
      { reader: this.readerPath },
      JSON.stringify({ title: prompt, items: labels })
    );
    if (!answer || answer.index === null || answer.index === undefined) {
      return null;
    }
    if (!Number.isInteger(answer.index) || answer.index < 0 || answer.index >= labels.length) {
      throw new Error("The accessible chooser returned an unknown choice.");
    }
    return { choice: labels[answer.index], index: answer.index };
  }
}

exports.AccessibleChooser = AccessibleChooser;
