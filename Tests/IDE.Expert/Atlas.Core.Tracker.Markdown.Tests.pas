unit Atlas.Core.Tracker.Markdown.Tests;

// Markdown der Issue-Vorschau (#1264): Blöcke (Überschrift, Absatz, Listen
// mit Ebenen und Aufgaben, Code mit Sprache, Zitat, Trennlinie, Tabelle,
// Bild mit YouTrack-Attributen und <img>), Fließtext (fett, kursiv, Code,
// Links, nackte Adressen, Entitäten, <br>, snake_case), Doku-Läufe für den
// Renderer der XMLDoc, Stücke um alleinstehende Bilder und Links ohne
// Codeblöcke.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerMarkdownTests = class
  public
    [Test]
    procedure BlocksOfMixedText;
    [Test]
    procedure ListLevelsAndTasks;
    [Test]
    procedure TableRowsAndCells;
    [Test]
    procedure ImageLines;
    [Test]
    procedure IndentedAndUnclosedCode;
    [Test]
    procedure InlineEmphasisCodeAndLinks;
    [Test]
    procedure InlineKeepsSnakeCaseAndLoneStars;
    [Test]
    procedure InlineEntitiesBreaksAndHtml;
    [Test]
    procedure DocRunsAndCodeLanguage;
    [Test]
    procedure SegmentsSplitAtImages;
    [Test]
    procedure LinksSkipCode;
    [Test]
    procedure NumberedTasksAndLines;
    [Test]
    procedure TaskModesBoxesPlainClickable;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Tracker.Markdown;

function Lines(const AParts: TArray<string>): string;
begin
  Result := string.Join(#10, AParts);
end;

{ TAtlasTrackerMarkdownTests }

procedure TAtlasTrackerMarkdownTests.BlocksOfMixedText;
var
  mBlocks: TArray<TAtlasMarkdownBlock>;
begin
  mBlocks := TAtlasTrackerMarkdown.Blocks(Lines(TArray<string>.Create('## Ziel ##', '', 'Erste Zeile',
    'zweite Zeile', '', '```js', 'var x = 1;', '```', '', '> Zitat', '> weiter', '', '---', '',
    '<!-- Kommentar -->', 'Ende')));
  Assert.AreEqual(Integer(6), Integer(Length(mBlocks)));
  Assert.IsTrue(mBlocks[0].Kind = TAtlasMarkdownBlockKind.Heading);
  Assert.AreEqual(Integer(2), mBlocks[0].Level);
  Assert.AreEqual('Ziel', mBlocks[0].Text);
  Assert.IsTrue(mBlocks[1].Kind = TAtlasMarkdownBlockKind.Paragraph);
  Assert.AreEqual('Erste Zeile'#10'zweite Zeile', mBlocks[1].Text, 'Umbruch bleibt');
  Assert.IsTrue(mBlocks[2].Kind = TAtlasMarkdownBlockKind.Code);
  Assert.AreEqual('js', mBlocks[2].Info);
  Assert.AreEqual('var x = 1;', mBlocks[2].Text);
  Assert.IsTrue(mBlocks[3].Kind = TAtlasMarkdownBlockKind.Quote);
  Assert.AreEqual('Zitat'#10'weiter', mBlocks[3].Text);
  Assert.IsTrue(mBlocks[4].Kind = TAtlasMarkdownBlockKind.Rule);
  Assert.IsTrue(mBlocks[5].Kind = TAtlasMarkdownBlockKind.Paragraph, 'HTML-Kommentar entfällt');
  Assert.AreEqual('Ende', mBlocks[5].Text);
end;

procedure TAtlasTrackerMarkdownTests.ListLevelsAndTasks;
var
  mBlocks: TArray<TAtlasMarkdownBlock>;
begin
  mBlocks := TAtlasTrackerMarkdown.Blocks(Lines(TArray<string>.Create('- eins', '  Fortsetzung', '  - zwei',
    '    - drei', '      - vier', '        - fünf', '- [ ] offen', '- [x] erledigt', '1. Nummer', '2) Klammer',
    '-kein Punkt')));
  Assert.AreEqual(Integer(10), Integer(Length(mBlocks)));
  Assert.AreEqual('•', mBlocks[0].Marker);
  Assert.AreEqual(Integer(1), mBlocks[0].Level);
  Assert.AreEqual('eins'#10'Fortsetzung', mBlocks[0].Text);
  Assert.AreEqual(Integer(2), mBlocks[1].Level);
  Assert.AreEqual(Integer(3), mBlocks[2].Level);
  Assert.AreEqual(Integer(4), mBlocks[3].Level);
  Assert.AreEqual(Integer(TAtlasTrackerMarkdown.MaxListLevel), mBlocks[4].Level, 'tiefer bleibt auf der letzten Ebene');
  Assert.AreEqual('☐', mBlocks[5].Marker);
  Assert.AreEqual('offen', mBlocks[5].Text);
  Assert.AreEqual(Integer(1), mBlocks[5].Level);
  Assert.AreEqual('☑', mBlocks[6].Marker);
  Assert.AreEqual('1.', mBlocks[7].Marker);
  Assert.AreEqual('2.', mBlocks[8].Marker);
  Assert.AreEqual('Klammer', mBlocks[8].Text);
  Assert.IsTrue(mBlocks[9].Kind = TAtlasMarkdownBlockKind.Paragraph);
end;

procedure TAtlasTrackerMarkdownTests.TableRowsAndCells;
var
  mBlocks: TArray<TAtlasMarkdownBlock>;
begin
  mBlocks := TAtlasTrackerMarkdown.Blocks(Lines(TArray<string>.Create('| Feld | Wert |', '|:---|---:|',
    '| a \| b | `x|y` |', '| c | d |', '', 'danach')));
  Assert.AreEqual(Integer(2), Integer(Length(mBlocks)));
  Assert.IsTrue(mBlocks[0].Kind = TAtlasMarkdownBlockKind.Table);
  Assert.AreEqual(Integer(3), Integer(Length(mBlocks[0].Rows)));
  Assert.AreEqual('Feld', mBlocks[0].Rows[0][0]);
  Assert.AreEqual('Wert', mBlocks[0].Rows[0][1]);
  Assert.AreEqual('a | b', mBlocks[0].Rows[1][0], 'maskierter Trenner');
  Assert.AreEqual('`x|y`', mBlocks[0].Rows[1][1], 'Trenner im Code');
  Assert.AreEqual('d', mBlocks[0].Rows[2][1]);
end;

procedure TAtlasTrackerMarkdownTests.ImageLines;
var
  mBlocks: TArray<TAtlasMarkdownBlock>;
begin
  mBlocks := TAtlasTrackerMarkdown.Blocks(Lines(TArray<string>.Create('![Skizze](skizze.png){width=70%}', '',
    '![](https://h.de/a.png "Titel")', '', '<img src="b.png" alt="B &amp; C">', '',
    'Text mit ![inline](c.png) bleibt Absatz')));
  Assert.AreEqual(Integer(4), Integer(Length(mBlocks)));
  Assert.IsTrue(mBlocks[0].Kind = TAtlasMarkdownBlockKind.Image);
  Assert.AreEqual('Skizze', mBlocks[0].Text);
  Assert.AreEqual('skizze.png', mBlocks[0].Info);
  Assert.AreEqual('https://h.de/a.png', mBlocks[1].Info, 'ohne Titel');
  Assert.AreEqual('b.png', mBlocks[2].Info);
  Assert.AreEqual('B & C', mBlocks[2].Text);
  Assert.IsTrue(mBlocks[3].Kind = TAtlasMarkdownBlockKind.Paragraph);
end;

procedure TAtlasTrackerMarkdownTests.IndentedAndUnclosedCode;
var
  mBlocks: TArray<TAtlasMarkdownBlock>;
begin
  mBlocks := TAtlasTrackerMarkdown.Blocks(Lines(TArray<string>.Create('    begin', '      x := 1;', '    end;', '',
    '~~~', 'offen bis zum Ende')));
  Assert.AreEqual(Integer(2), Integer(Length(mBlocks)));
  Assert.IsTrue(mBlocks[0].Kind = TAtlasMarkdownBlockKind.Code);
  Assert.AreEqual('begin'#10'  x := 1;'#10'end;', mBlocks[0].Text);
  Assert.IsTrue(mBlocks[1].Kind = TAtlasMarkdownBlockKind.Code);
  Assert.AreEqual('offen bis zum Ende', mBlocks[1].Text);
  Assert.AreEqual('', mBlocks[1].Info);
end;

procedure TAtlasTrackerMarkdownTests.InlineEmphasisCodeAndLinks;
var
  mRuns: TAtlasDocRuns;
begin
  mRuns := TAtlasTrackerMarkdown.InlineRuns('**fett** und *kursiv* mit `code` und [Link](https://x.de/a "T") ' +
    'oder https://y.de/b.');
  Assert.AreEqual(Integer(10), Integer(Length(mRuns)));
  Assert.AreEqual('fett', mRuns[0].Text);
  Assert.IsTrue(mRuns[0].Bold);
  Assert.AreEqual(' und ', mRuns[1].Text);
  Assert.IsFalse(mRuns[1].Bold);
  Assert.AreEqual('kursiv', mRuns[2].Text);
  Assert.IsTrue(mRuns[2].Italic);
  Assert.IsTrue(mRuns[4].Kind = TAtlasDocRunKind.Code);
  Assert.AreEqual('code', mRuns[4].Text);
  Assert.IsTrue(mRuns[6].Kind = TAtlasDocRunKind.Link);
  Assert.AreEqual('Link', mRuns[6].Text);
  Assert.AreEqual('https://x.de/a', mRuns[6].Target);
  Assert.IsTrue(mRuns[8].Kind = TAtlasDocRunKind.Link, 'nackte Adresse');
  Assert.AreEqual('https://y.de/b', mRuns[8].Target, 'Punkt am Ende gehört nicht dazu');
  Assert.AreEqual('.', mRuns[9].Text);
end;

procedure TAtlasTrackerMarkdownTests.InlineKeepsSnakeCaseAndLoneStars;
var
  mRuns: TAtlasDocRuns;
begin
  mRuns := TAtlasTrackerMarkdown.InlineRuns('my_var_name * 2 und ~~alt~~ \*kein\*');
  Assert.AreEqual(Integer(1), Integer(Length(mRuns)));
  Assert.AreEqual('my_var_name * 2 und alt *kein*', mRuns[0].Text);
  Assert.IsFalse(mRuns[0].Italic);
  mRuns := TAtlasTrackerMarkdown.InlineRuns('Titel', True, False);
  Assert.IsTrue(mRuns[0].Bold, 'Überschrift fett');
end;

procedure TAtlasTrackerMarkdownTests.InlineEntitiesBreaksAndHtml;
var
  mRuns: TAtlasDocRuns;
begin
  mRuns := TAtlasTrackerMarkdown.InlineRuns('a &amp; b &#65;<br>c'#10'<a href="https://z.de">Z</a> <https://w.de>');
  Assert.AreEqual(Integer(7), Integer(Length(mRuns)));
  Assert.AreEqual('a & b A', mRuns[0].Text);
  Assert.IsTrue(mRuns[1].Kind = TAtlasDocRunKind.LineBreak);
  Assert.AreEqual('c', mRuns[2].Text);
  Assert.IsTrue(mRuns[3].Kind = TAtlasDocRunKind.LineBreak);
  Assert.IsTrue(mRuns[4].Kind = TAtlasDocRunKind.Link);
  Assert.AreEqual('Z', mRuns[4].Text);
  Assert.AreEqual('https://z.de', mRuns[4].Target);
  Assert.AreEqual('https://w.de', mRuns[6].Target);
  Assert.AreEqual('<b> & "x"', TAtlasTrackerMarkdown.DecodeHtml('&lt;b&gt; &amp; &quot;x&quot;'));
  Assert.AreEqual('a b ''c'' &nbsp;', TAtlasTrackerMarkdown.DecodeHtml('a&nbsp;b &#39;c&#39; &amp;nbsp;'));
end;

procedure TAtlasTrackerMarkdownTests.DocRunsAndCodeLanguage;
var
  mDoc: TAtlasDoc;
  mRuns: TAtlasDocRuns;
begin
  mDoc := TAtlasTrackerMarkdown.ToDoc(Lines(TArray<string>.Create('# Kopf', '', '- a', '- b', '', '```json',
    '{}', '```', '', '```pascal', 'begin end;', '```')));
  Assert.AreEqual(Integer(1), Integer(Length(mDoc.Sections)));
  mRuns := mDoc.Sections[0].Runs;
  Assert.AreEqual('Kopf', mRuns[0].Text);
  Assert.IsTrue(mRuns[0].Bold);
  Assert.IsTrue(mRuns[1].Kind = TAtlasDocRunKind.Paragraph);
  Assert.IsTrue(mRuns[2].Kind = TAtlasDocRunKind.Bullet);
  Assert.AreEqual(Integer(1), mRuns[2].Level);
  Assert.IsTrue(mRuns[4].Kind = TAtlasDocRunKind.Bullet, 'kein Absatz zwischen Punkten');
  Assert.IsTrue(mRuns[6].Kind = TAtlasDocRunKind.Paragraph, 'Absatz nach der Liste');
  Assert.IsTrue(mRuns[7].Kind = TAtlasDocRunKind.CodeBlock);
  Assert.AreEqual('json', mRuns[7].Target);
  Assert.IsFalse(mRuns[7].IsDelphiCode, 'JSON nicht als Delphi einfärben');
  Assert.IsTrue(mRuns[8].Kind = TAtlasDocRunKind.CodeBlock);
  Assert.IsTrue(mRuns[8].IsDelphiCode);
  Assert.AreEqual(Integer(9), Integer(Length(mRuns)), 'kein Absatz am Ende');
  Assert.IsTrue(TAtlasTrackerMarkdown.ToDoc('   ').IsEmpty);
end;

procedure TAtlasTrackerMarkdownTests.NumberedTasksAndLines;
var
  mBlocks: TArray<TAtlasMarkdownBlock>;
begin
  mBlocks := TAtlasTrackerMarkdown.Blocks(Lines(TArray<string>.Create('Vorher', '', '1. [ ] eins', '   weiter',
    '2) [X] zwei', '- [x]')));
  Assert.AreEqual(Integer(4), Integer(Length(mBlocks)));
  Assert.IsTrue(mBlocks[1].Task = TAtlasMarkdownTask.Open);
  Assert.AreEqual('☐', mBlocks[1].Marker);
  Assert.AreEqual('1.', mBlocks[1].ListMarker);
  Assert.AreEqual('eins'#10'weiter', mBlocks[1].Text);
  Assert.AreEqual(Integer(2), mBlocks[1].Line);
  Assert.AreEqual(Integer(3), mBlocks[1].LastLine);
  Assert.IsTrue(mBlocks[2].Task = TAtlasMarkdownTask.Done, 'großes X');
  Assert.AreEqual('2.', mBlocks[2].ListMarker);
  Assert.IsTrue(mBlocks[3].Task = TAtlasMarkdownTask.Done, 'ohne Text');
  Assert.AreEqual('', mBlocks[3].Text);
  Assert.AreEqual(Integer(-1), mBlocks[0].Line, 'nur Listenpunkte tragen die Zeile');
end;

procedure TAtlasTrackerMarkdownTests.TaskModesBoxesPlainClickable;
const
  cText = '- [ ] a'#10'- b'#10'1. [x] c';
var
  mRuns: TAtlasDocRuns;
  mIndex: Integer;
begin
  mRuns := TAtlasTrackerMarkdown.ToDoc(cText).Sections[0].Runs;
  Assert.AreEqual('☐', mRuns[0].Text);
  Assert.AreEqual('', mRuns[0].Target, 'Kästchen ohne Ziel');
  // Plain (Checklisten aus): Listenmarke und das Kästchen als Text.
  mRuns := TAtlasTrackerMarkdown.ToDoc(cText, TAtlasMarkdownTasks.Plain).Sections[0].Runs;
  Assert.IsTrue(mRuns[0].Kind = TAtlasDocRunKind.Bullet);
  Assert.AreEqual('•', mRuns[0].Text);
  Assert.AreEqual('[ ] a', mRuns[1].Text);
  Assert.AreEqual('1.', mRuns[4].Text);
  Assert.AreEqual('[x] c', mRuns[5].Text);
  // Clickable: Kästchen mit Ziel, gezählt nur über Aufgaben.
  mRuns := TAtlasTrackerMarkdown.ToDoc(cText, TAtlasMarkdownTasks.Clickable).Sections[0].Runs;
  Assert.AreEqual(TAtlasTrackerMarkdown.TaskTarget(0), mRuns[0].Target);
  Assert.AreEqual('', mRuns[2].Target, 'Punkt ohne Kästchen');
  Assert.AreEqual('☑', mRuns[4].Text);
  Assert.IsTrue(TAtlasTrackerMarkdown.TaskIndexOf(mRuns[4].Target, mIndex));
  Assert.AreEqual(Integer(1), mIndex);
  // Über Bilder hinweg weiter gezählt.
  Assert.AreEqual(TAtlasTrackerMarkdown.TaskTarget(1), TAtlasTrackerMarkdown.Segments('- [ ] a'#10#10'![](b.png)'#10#10 +
    '- [ ] c', TAtlasMarkdownTasks.Clickable)[2].Doc.Sections[0].Runs[0].Target);
end;

procedure TAtlasTrackerMarkdownTests.SegmentsSplitAtImages;
var
  mSegments: TArray<TAtlasMarkdownSegment>;
begin
  mSegments := TAtlasTrackerMarkdown.Segments(Lines(TArray<string>.Create('Vorher', '', '![s](bilder/skizze.png)',
    '', 'Nachher')));
  Assert.AreEqual(Integer(3), Integer(Length(mSegments)));
  Assert.IsTrue(mSegments[0].Kind = TAtlasMarkdownSegmentKind.Doc);
  Assert.IsTrue(mSegments[1].Kind = TAtlasMarkdownSegmentKind.Image);
  Assert.AreEqual('bilder/skizze.png', mSegments[1].Image.Url);
  Assert.AreEqual('s', mSegments[1].Image.Text);
  Assert.IsTrue(mSegments[2].Kind = TAtlasMarkdownSegmentKind.Doc);
  // In einer Doku ohne Bildfläche wird das Bild zum Link mit dem Dateinamen.
  Assert.AreEqual('skizze.png', TAtlasTrackerMarkdown.ToDoc('![](bilder/skizze.png)').Sections[0].Runs[0].Text);
end;

procedure TAtlasTrackerMarkdownTests.LinksSkipCode;
var
  mLinks: TArray<TAtlasMarkdownLink>;
begin
  mLinks := TAtlasTrackerMarkdown.Links(Lines(TArray<string>.Create('[a](https://h.de/1) ![b](c.png)', '',
    '```', '[x](https://nicht.de)', '```', '', '`[y](https://auch-nicht.de)`', '', '| [t](https://t.de) |', '|---|',
    '', '![d](d.png)')));
  Assert.AreEqual(Integer(4), Integer(Length(mLinks)));
  Assert.AreEqual('https://h.de/1', mLinks[0].Url);
  Assert.AreEqual('c.png', mLinks[1].Url);
  Assert.AreEqual('b', mLinks[1].Text);
  Assert.AreEqual('https://t.de', mLinks[2].Url);
  Assert.AreEqual('d.png', mLinks[3].Url);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerMarkdownTests);

end.
