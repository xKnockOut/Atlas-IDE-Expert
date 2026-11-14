unit Atlas.Core.Documentation.Tests;

// Tests für die strukturierte XMLDoc im Plugin (#654, #770): Lesen der
// Server-Antwort, Signatur aus der Deklaration, Zustand „wie zuletzt“ und Satz
// für Tooltip und Detailpanel (Abschnitte, Schalter, verborgene Teile). Gemessen
// wird mit fester Zeichenbreite (UI 7, Editorschrift 8 Pixel), damit die
// Positionen vorhersagbar sind.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Documentation.Layout;

type
  [TestFixture]
  TAtlasDocumentationTests = class
  private
    function Layout(const AJson: string; AWidth: Integer): TAtlasDocLayout;
    function LayoutWith(const AJson: string; AWidth: Integer; const ADeclaration: string;
      AExpanded: Boolean): TAtlasDocLayout;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsSectionsRunsAndTargets;
    [Test]
    procedure SkipsUnknownKinds;
    [Test]
    procedure ReadsDisplaySettings;
    [Test]
    procedure WrapsAtWordBoundaries;
    [Test]
    procedure BreaksLongWordsAtCharacters;
    [Test]
    procedure RefsAndLinksAreClickable;
    [Test]
    procedure RefWithoutLocationIsNotClickable;
    [Test]
    procedure ParametersInTwoColumns;
    [Test]
    procedure ExceptionClassIsClickable;
    [Test]
    procedure CodeBlockKeepsIndentAndColors;
    [Test]
    procedure BulletsHangAndIndentPerLevel;
    [Test]
    procedure TableRowsInTwoColumns;
    [Test]
    procedure HeadingsForTypeParamsExampleSeeAlso;
    [Test]
    procedure CollapsedShowsToggleAndHiddenParts;
    [Test]
    procedure SummaryOnlyHasNoToggle;
    [Test]
    procedure ParamsInSignatureOrderWithTypes;
    [Test]
    procedure PropertyTypeUnderValue;
    [Test]
    procedure ParamRefIsPill;
    [Test]
    procedure ParsesSignatures;
    [Test]
    procedure ExpandStatePerSurface;
    [Test]
    procedure SelectionCopiesText;
    [Test]
    procedure LongDocumentIsNotTruncated;
    [Test]
    procedure PlainTextOfForeignServers;
    /// <summary>#1123: Begründungen unter BEGRÜNDUNG, zugeklappt höchstens drei.</summary>
    [Test]
    procedure RationaleBelowDocumentation;
    [Test]
    procedure RationaleBeyondThreeBehindToggle;
    [Test]
    procedure IssueLinksNeedTracker;
    /// <summary>#1919: Offene Signatur zeigt Parameter und Rückgabe auch ohne XMLDoc.</summary>
    [Test]
    procedure OpenSignatureWithoutDoc;
    /// <summary>#1919: Offene Signatur zugeklappt: Parameter und Rückgabe offen, der Rest hinter dem Schalter.
    /// </summary>
    [Test]
    procedure OpenSignatureCollapsedHidesRest;
    /// <summary>#1921: Inhalt einer Unit je Überschrift als Tabelle, immer offen, Namen als Verweise.</summary>
    [Test]
    procedure UnitContentsBelowPath;
  end;

implementation

uses
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Documentation.Typeset,
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

function Measure(const AText: string; const AFace: TAtlasDocFace): Integer;
begin
  if AFace.Font = TAtlasDocFont.Mono then
  begin
    Result := 8 * Length(AText);
  end
  else
  begin
    Result := 7 * Length(AText);
  end;
end;

function Metrics: TAtlasDocMetrics;
begin
  Result := TAtlasDocMetrics.Create(16, 17, 1);
end;

function DocOf(const AJson: string): TAtlasDoc;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasDoc.FromJson(mValue);
  finally
    mValue.Free;
  end;
end;

function LineText(const ALine: TAtlasDocLine): string;
var
  mSpan: TAtlasDocSpan;
begin
  Result := '';
  for mSpan in ALine.Spans do
  begin
    Result := Result + mSpan.Text;
  end;
end;

function Summary(const AText: string): string;
begin
  Result := '{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"' + AText + '"}]}]}';
end;

{ TAtlasDocumentationTests }

function Texts(const ALayout: TAtlasDocLayout): string;
var
  mLine: TAtlasDocLine;
begin
  Result := '';
  for mLine in ALayout.Lines do
  begin
    Result := Result + LineText(mLine) + '|';
  end;
end;

procedure TAtlasDocumentationTests.Setup;
begin
  TAtlasDocExpandState.Reset;
end;

procedure TAtlasDocumentationTests.TearDown;
begin
  TAtlasDocIssueLinks.Clear;
  TAtlasDocExpandState.Reset;
end;

function TAtlasDocumentationTests.Layout(const AJson: string; AWidth: Integer): TAtlasDocLayout;
begin
  Result := TAtlasDocTypeset.Build(DocOf(AJson), AWidth, Metrics, Measure, TAtlasDocLabels.German);
end;

function TAtlasDocumentationTests.LayoutWith(const AJson: string; AWidth: Integer; const ADeclaration: string;
  AExpanded: Boolean): TAtlasDocLayout;
begin
  Result := TAtlasDocTypeset.Build(TAtlasDocContent.Create(DocOf(AJson), TAtlasDocSignature.Parse(ADeclaration),
    AExpanded), AWidth, Metrics, Measure, TAtlasDocLabels.German);
end;

function OpenContent(const AJson, ADeclaration: string; AExpanded: Boolean): TAtlasDocContent;
begin
  Result := TAtlasDocContent.Create(DocOf(AJson), TAtlasDocSignature.Parse(ADeclaration), AExpanded);
  Result.OpenSignature := True;
end;

function OpenLayout(const AJson, ADeclaration: string; AExpanded: Boolean): TAtlasDocLayout;
begin
  Result := TAtlasDocTypeset.Build(OpenContent(AJson, ADeclaration, AExpanded), 600, Metrics, Measure,
    TAtlasDocLabels.German);
end;

procedure TAtlasDocumentationTests.OpenSignatureWithoutDoc;
const
  cSplit = 'function TStringHelper.Split(const Separators: array of Char; Count: Integer): TArray<string>;';
var
  mResult_: TAtlasDocLayout;
begin
  // Ohne XMLDoc: Tabelle ohne Textspalte, Rückgabetyp, kein Schalter.
  mResult_ := OpenLayout('{"sections":[]}', cSplit, False);
  Assert.AreEqual('PARAMETER|Separatorsconst array of Char|CountInteger|RÜCKGABE|TArray<string>|', Texts(mResult_));
  Assert.IsFalse(mResult_.Collapsible);
  Assert.AreEqual(0, Integer(Length(mResult_.Links)));
  Assert.AreEqual(2, Integer(Length(mResult_.Lines[1].Spans)));
  // Ohne den Schalter bleibt die Doku leer wie bisher.
  Assert.IsTrue(LayoutWith('{"sections":[]}', 600, cSplit, False).IsEmpty);
  // Nichts zu zeigen: Prozedur ohne Parameter, Property ohne Index, unbekannte Deklaration.
  Assert.IsTrue(OpenLayout('{"sections":[]}', 'procedure TX.Run;', False).IsEmpty);
  Assert.IsTrue(OpenLayout('{"sections":[]}', 'property Count: Integer read FCount;', False).IsEmpty);
  Assert.IsTrue(OpenLayout('{"sections":[]}', 'var Count: Integer', False).IsEmpty);
  // Funktion ohne Parameter: nur RÜCKGABE.
  Assert.AreEqual('RÜCKGABE|Integer|', Texts(OpenLayout('{"sections":[]}', 'function TX.Count: Integer;', False)));
end;

procedure TAtlasDocumentationTests.OpenSignatureCollapsedHidesRest;
const
  cJson = '{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liest."}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"Name"}]},' +
    '{"kind":"exception","name":"EFehler","runs":[{"kind":"text","text":"x"}]},' +
    '{"kind":"remarks","runs":[{"kind":"text","text":"Hinweis"}]}]}';
  cDeclaration = 'function TX.Lies(const A: string; B: Integer): Boolean;';
var
  mResult_: TAtlasDocLayout;
  mColors: TArray<TAtlasDocColor>;
  mParts: TArray<string>;
begin
  mResult_ := OpenLayout(cJson, cDeclaration, False);
  Assert.IsTrue(mResult_.Collapsible);
  Assert.IsFalse(mResult_.Expanded);
  // Ein Parameter beschrieben: der andere „nicht dokumentiert“.
  Assert.AreEqual('Liest.|PARAMETER|Aconst stringName|BIntegernicht dokumentiert|RÜCKGABE|Boolean|' +
    'Mehr anzeigen ▾   1 Ausnahme · Hinweis|', Texts(mResult_));
  mParts := TAtlasDocTypeset.HiddenParts(OpenContent(cJson, cDeclaration, False), TAtlasDocLabels.German, mColors);
  Assert.AreEqual(2, Integer(Length(mParts)));
  Assert.AreEqual('1 Ausnahme', mParts[0]);
  // Aufgeklappt in der gewohnten Reihenfolge.
  Assert.AreEqual('Liest.|PARAMETER|Aconst stringName|BIntegernicht dokumentiert|RÜCKGABE|Boolean|AUSNAHMEN|' +
    'EFehlerx|HINWEISE|Hinweis|Weniger anzeigen ▴|', Texts(OpenLayout(cJson, cDeclaration, True)));
  // Nur Beschreibung und Parameter: nichts mehr verborgen, kein Schalter.
  mResult_ := OpenLayout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liest."}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"Name"}]}]}', cDeclaration, False);
  Assert.IsFalse(mResult_.Collapsible);
  Assert.IsFalse(TAtlasDocTypeset.IsCollapsible(OpenContent(Summary('x'), cDeclaration, False)));
  Assert.AreEqual('Liest.|PARAMETER|Aconst stringName|BIntegernicht dokumentiert|RÜCKGABE|Boolean|',
    Texts(mResult_));
end;


procedure TAtlasDocumentationTests.ReadsSectionsRunsAndTargets;
var
  mDoc: TAtlasDoc;
begin
  mDoc := DocOf('{"sections":[' +
    '{"kind":"summary","runs":[{"kind":"text","text":"Filter für "},' +
    '{"kind":"ref","text":"TDBGrid","target":"TDBGrid","name":"TDBGrid","unit":"Vcl.DBGrids",' +
    '"file":"C:\\RTL\\Vcl.DBGrids.pas","line":40,"character":2},' +
    '{"kind":"text","text":" ","bold":true,"italic":true},{"kind":"link","text":"Doku","target":"https://x"}]},' +
    '{"kind":"param","name":"AOwner","runs":[{"kind":"text","text":"Besitzer"}]},' +
    '{"kind":"exception","name":"EZeichnen","ref":{"name":"EZeichnen","file":"C:\\P\\U.pas","line":3,' +
    '"character":2},"runs":[{"kind":"text","text":"bei Fehlern"}]}]}');
  Assert.AreEqual(3, Integer(Length(mDoc.Sections)));
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Summary), Ord(mDoc.Sections[0].Kind));
  Assert.AreEqual(4, Integer(Length(mDoc.Sections[0].Runs)));
  Assert.AreEqual(Ord(TAtlasDocRunKind.Ref), Ord(mDoc.Sections[0].Runs[1].Kind));
  Assert.IsTrue(mDoc.Sections[0].Runs[1].Location.HasLocation);
  Assert.AreEqual('Vcl.DBGrids', mDoc.Sections[0].Runs[1].Location.UnitName);
  Assert.AreEqual(40, mDoc.Sections[0].Runs[1].Location.Line);
  Assert.IsTrue(mDoc.Sections[0].Runs[2].Bold);
  Assert.IsTrue(mDoc.Sections[0].Runs[2].Italic);
  Assert.AreEqual('https://x', mDoc.Sections[0].Runs[3].Target);
  Assert.AreEqual('AOwner', mDoc.Sections[1].Name);
  Assert.AreEqual('EZeichnen', mDoc.Sections[2].NameRef.Name);
  Assert.IsTrue(mDoc.Sections[2].NameRef.HasLocation);
  Assert.AreEqual('Filter für TDBGrid Doku', mDoc.Sections[0].Text);
  Assert.IsTrue(mDoc.Has(TAtlasDocSectionKind.Exception));
  Assert.IsFalse(mDoc.Has(TAtlasDocSectionKind.Remarks));
end;

procedure TAtlasDocumentationTests.SkipsUnknownKinds;
var
  mDoc: TAtlasDoc;
begin
  mDoc := DocOf('{"sections":[{"kind":"neu","runs":[]},' +
    '{"kind":"remarks","runs":[{"kind":"blink","text":"x"},{"kind":"text","text":"y"}]}]}');
  Assert.AreEqual(1, Integer(Length(mDoc.Sections)));
  Assert.AreEqual(1, Integer(Length(mDoc.Sections[0].Runs)));
  Assert.IsTrue(DocOf('"text"').IsEmpty);
  Assert.IsTrue(DocOf('{}').IsEmpty);
end;

procedure TAtlasDocumentationTests.ReadsDisplaySettings;
var
  mFallback, mDisplay: TAtlasDocDisplay;
  mValue: TJSONValue;
begin
  mFallback := TAtlasDocDisplay.Create(TAtlasDocExpand.Expanded, 70);
  Assert.AreEqual(TAtlasDocDisplay.cMaxMaxLines, mFallback.MaxLines);
  mDisplay := TAtlasDocDisplay.FromJson(nil, TAtlasDocDisplay.Create(TAtlasDocExpand.Collapsed, 5));
  Assert.IsFalse(mDisplay.Known);
  Assert.AreEqual(Ord(TAtlasDocExpand.Collapsed), Ord(mDisplay.Expand));
  Assert.AreEqual(5, mDisplay.MaxLines);
  mValue := TJSONObject.ParseJSONValue('{"expand":"expanded","maxLines":12}');
  try
    mDisplay := TAtlasDocDisplay.FromJson(mValue, TAtlasDocDisplay.Create(TAtlasDocExpand.Collapsed, 5));
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mDisplay.Known);
  Assert.AreEqual(Ord(TAtlasDocExpand.Expanded), Ord(mDisplay.Expand));
  Assert.AreEqual(12, mDisplay.MaxLines);
  // Server vor #770: "full".
  mValue := TJSONObject.ParseJSONValue('{"full":false}');
  try
    mDisplay := TAtlasDocDisplay.FromJson(mValue, TAtlasDocDisplay.Create(TAtlasDocExpand.Last, 5));
  finally
    mValue.Free;
  end;
  Assert.AreEqual(Ord(TAtlasDocExpand.Collapsed), Ord(mDisplay.Expand));
  Assert.AreEqual(5, mDisplay.MaxLines);
  Assert.AreEqual(Ord(TAtlasDocExpand.Last), Ord(TAtlasDocDisplay.ExpandOf('LAST')));
  Assert.AreEqual(Ord(TAtlasDocExpand.Last), Ord(TAtlasDocDisplay.ExpandOf('unsinn')));
  Assert.AreEqual(Ord(TAtlasDocExpand.Collapsed), Ord(TAtlasDocDisplay.ExpandOf(' collapsed ')));
  Assert.AreEqual('expanded', TAtlasDocDisplay.ExpandName(TAtlasDocExpand.Expanded));
end;

procedure TAtlasDocumentationTests.WrapsAtWordBoundaries;
var
  mResult_: TAtlasDocLayout;
  mLine: TAtlasDocLine;
  mJoined: string;
begin
  // Höchstens 12 Zeichen je Zeile bei 90 Pixeln.
  mResult_ := Layout(Summary('Eins zwei drei vier fünf sechs sieben acht'), 90);
  Assert.IsTrue(Length(mResult_.Lines) > 2);
  mJoined := '';
  for mLine in mResult_.Lines do
  begin
    Assert.IsTrue(mLine.Spans[High(mLine.Spans)].Right - 7 *
      (Length(LineText(mLine)) - Length(TrimRight(LineText(mLine))))
      <= 90, LineText(mLine));
    Assert.AreNotEqual(' ', Copy(LineText(mLine), 1, 1));
    mJoined := mJoined + LineText(mLine);
  end;
  Assert.AreEqual('Eins zwei drei vier fünf sechs sieben acht', TrimRight(mJoined));
  Assert.AreEqual('Eins zwei ', LineText(mResult_.Lines[0]));
  Assert.AreEqual(16, mResult_.Lines[1].Top);
  Assert.AreEqual(mResult_.Lines[High(mResult_.Lines)].Bottom, mResult_.Height);
end;

procedure TAtlasDocumentationTests.BreaksLongWordsAtCharacters;
var
  mResult_: TAtlasDocLayout;
  mLine: TAtlasDocLine;
begin
  mResult_ := Layout(Summary('ABCDEFGHIJKLMNOPQRSTUVWXYZ'), 70);
  Assert.AreEqual(3, Integer(Length(mResult_.Lines)));
  for mLine in mResult_.Lines do
  begin
    Assert.IsTrue(mLine.Spans[High(mLine.Spans)].Right <= 70);
  end;
  Assert.AreEqual('ABCDEFGHIJ', LineText(mResult_.Lines[0]));
end;

procedure TAtlasDocumentationTests.RefsAndLinksAreClickable;
var
  mResult_: TAtlasDocLayout;
  mSpan: TAtlasDocSpan;
  mLink: Integer;
begin
  mResult_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Siehe "},' +
    '{"kind":"ref","text":"TFoo.Bar","target":"TFoo.Bar","name":"Bar","file":"C:\\U.pas","line":9,"character":4},' +
    '{"kind":"text","text":" und "},{"kind":"link","text":"Web","target":"https://example.org"}]}]}', 400);
  Assert.AreEqual(1, Integer(Length(mResult_.Lines)));
  Assert.AreEqual(2, Integer(Length(mResult_.Links)));
  mSpan := mResult_.Lines[0].Spans[1];
  Assert.AreEqual('TFoo.Bar', mSpan.Text);
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(mSpan.Face.Font));
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(mSpan.Color));
  Assert.IsTrue(mSpan.Underline);
  mLink := mResult_.LinkAt(mSpan.Left + 2, 3);
  Assert.AreEqual(0, mLink);
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Ref), Ord(mResult_.Links[mLink].Kind));
  Assert.AreEqual('C:\U.pas', mResult_.Links[mLink].Target.FileName);
  Assert.AreEqual(9, mResult_.Links[mLink].Target.Line);
  mSpan := mResult_.Lines[0].Spans[3];
  mLink := mResult_.LinkAt(mSpan.Left + 1, 1);
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Url), Ord(mResult_.Links[mLink].Kind));
  Assert.AreEqual('https://example.org', mResult_.Links[mLink].Url);
  Assert.AreEqual(-1, mResult_.LinkAt(1, 1));
  Assert.AreEqual(-1, mResult_.LinkAt(mSpan.Left + 1, 40));
end;

procedure TAtlasDocumentationTests.RefWithoutLocationIsNotClickable;
var
  mResult_: TAtlasDocLayout;
begin
  mResult_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"ref","text":"TUnbekannt","target":"TUnbekannt"},' +
    '{"kind":"link","text":"leer"}]}]}', 400);
  Assert.AreEqual(0, Integer(Length(mResult_.Links)));
  Assert.IsFalse(mResult_.Lines[0].Spans[0].Underline);
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(mResult_.Lines[0].Spans[0].Color));
end;

procedure TAtlasDocumentationTests.ParametersInTwoColumns;
var
  mResult_: TAtlasDocLayout;
  mColumn: Integer;
begin
  // Ohne Signatur: Name und Beschreibung, in der Reihenfolge der Doku.
  mResult_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Tut."}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"erster Wert"}]},' +
    '{"kind":"param","name":"ALangerName","runs":[{"kind":"text","text":"zweiter Wert mit viel Text dazu"}]},' +
    '{"kind":"returns","runs":[{"kind":"text","text":"Summe"}]}]}', 300);
  Assert.AreEqual('Tut.|PARAMETER|Aerster Wert|ALangerNamezweiter Wert mit viel Text |dazu|RÜCKGABE|Summe|' +
    'Weniger anzeigen ▴|', Texts(mResult_));
  Assert.IsTrue(mResult_.Lines[1].Rule);
  Assert.AreEqual(9 * 7 + Metrics.ColumnGap, mResult_.Lines[1].RuleFrom);
  Assert.IsTrue(mResult_.Lines[1].Spans[0].Face.Small);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(mResult_.Lines[1].Spans[0].Color));
  // Namensspalte: "ALangerName" = 88 Pixel (< 30 % von 300), dazu der Abstand.
  mColumn := 88 + Metrics.ColumnGap;
  Assert.AreEqual('A', mResult_.Lines[2].Spans[0].Text);
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(mResult_.Lines[2].Spans[0].Color));
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(mResult_.Lines[2].Spans[0].Face.Font));
  Assert.IsTrue(mResult_.Lines[2].Spans[0].Face.Bold);
  Assert.AreEqual(mColumn, mResult_.Lines[2].Spans[1].Left);
  Assert.AreEqual(Ord(TAtlasDocColor.Text), Ord(mResult_.Lines[2].Spans[1].Color));
  Assert.AreEqual(mColumn, mResult_.Lines[3].Spans[1].Left);
  // Fortsetzungszeile bleibt in der Textspalte.
  Assert.AreEqual(mColumn, mResult_.Lines[4].Spans[0].Left);
  // Rückgabe ohne Signatur: nur der Text, gedämpft.
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(mResult_.Lines[6].Spans[0].Color));
  // Sehr lange Namen: Spalte höchstens 30 % (45 Pixel), der Name bricht an Zeichen um.
  mResult_ := Layout('{"sections":[{"kind":"param","name":"AEinSehrSehrLangerName","runs":' +
    '[{"kind":"text","text":"Text"}]}]}', 150);
  Assert.AreEqual('AEinS', mResult_.Lines[1].Spans[0].Text);
  Assert.AreEqual(45 + Metrics.ColumnGap, mResult_.Lines[1].Spans[1].Left);
end;

procedure TAtlasDocumentationTests.ExceptionClassIsClickable;
var
  mResult_: TAtlasDocLayout;
  mSpan: TAtlasDocSpan;
begin
  mResult_ := Layout('{"sections":[{"kind":"exception","name":"EZeichnen","ref":{"name":"EZeichnen",' +
    '"file":"C:\\U.pas","line":3,"character":2},"runs":[{"kind":"text","text":"bei Fehlern"}]},' +
    '{"kind":"exception","name":"EFremd","runs":[{"kind":"text","text":"unbekannt"}]}]}', 400);
  Assert.AreEqual('AUSNAHMEN', LineText(mResult_.Lines[0]));
  mSpan := mResult_.Lines[1].Spans[0];
  Assert.AreEqual('EZeichnen', mSpan.Text);
  Assert.AreEqual(Ord(TAtlasDocColor.Error), Ord(mSpan.Color));
  Assert.IsTrue(mSpan.Underline);
  Assert.AreEqual(0, mResult_.LinkAt(mSpan.Left + 3, mResult_.Lines[1].Top + 2));
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Ref), Ord(mResult_.Links[0].Kind));
  Assert.AreEqual('EZeichnen', mResult_.Links[0].Target.Name);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(mResult_.Lines[1].Spans[1].Color));
  Assert.AreEqual(-1, mResult_.Lines[2].Spans[0].Link);
  // Dazu nur der Schalter „Weniger anzeigen“.
  Assert.AreEqual(2, Integer(Length(mResult_.Links)));
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Toggle), Ord(mResult_.Links[1].Kind));
end;

procedure TAtlasDocumentationTests.CodeBlockKeepsIndentAndColors;
var
  mResult_: TAtlasDocLayout;
  mFirst: Integer;
begin
  mResult_ := Layout('{"sections":[{"kind":"example","runs":[{"kind":"text","text":"So:"},' +
    '{"kind":"codeblock","text":"begin\n  X := ''a'';\nend;"}]}]}', 400);
  // Überschrift, "So:", drei Codezeilen, Schalter.
  Assert.AreEqual(6, Integer(Length(mResult_.Lines)));
  Assert.AreEqual('BEISPIEL', LineText(mResult_.Lines[0]));
  Assert.IsFalse(mResult_.Lines[1].Shaded);
  mFirst := 2;
  Assert.AreEqual('begin', LineText(mResult_.Lines[mFirst]));
  Assert.AreEqual(Ord(TAtlasDocColor.Keyword), Ord(mResult_.Lines[mFirst].Spans[0].Color));
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(mResult_.Lines[mFirst].Spans[0].Face.Font));
  Assert.AreEqual('  X := ''a'';', LineText(mResult_.Lines[mFirst + 1]));
  Assert.AreEqual(Ord(TAtlasDocColor.StringLiteral), Ord(mResult_.Lines[mFirst + 1].Spans[1].Color));
  Assert.AreEqual(17, mResult_.Lines[mFirst].Height);
  Assert.IsTrue(mResult_.Lines[mFirst].GapBefore > 0);
  // Schattierte Fläche ab dem Rand, Text um CodePad eingerückt, ohne Lücke zwischen den Zeilen.
  Assert.IsTrue(mResult_.Lines[mFirst].Shaded);
  Assert.IsTrue(mResult_.Lines[mFirst + 2].Shaded);
  Assert.AreEqual(0, mResult_.Lines[mFirst].ShadeLeft);
  Assert.AreEqual(Metrics.CodePad, mResult_.Lines[mFirst].Spans[0].Left);
  Assert.AreEqual(0, mResult_.Lines[mFirst + 1].GapBefore);
  Assert.IsFalse(mResult_.Lines[mFirst + 3].Shaded);
  // Zu lange Codezeilen brechen an Zeichen um, eingerückt.
  mResult_ := Layout('{"sections":[{"kind":"example","runs":[{"kind":"codeblock","text":"' +
    'WriteLn(Eins, Zwei, Drei);"}]}]}', 100);
  Assert.IsTrue(Length(mResult_.Lines) >= 4);
  Assert.AreEqual(Metrics.CodePad + Metrics.Indent, mResult_.Lines[2].Spans[0].Left);
  Assert.IsTrue(mResult_.Lines[2].Shaded);
end;

procedure TAtlasDocumentationTests.BulletsHangAndIndentPerLevel;
var
  mResult_: TAtlasDocLayout;
  mHang: Integer;
begin
  mResult_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liste:"},' +
    '{"kind":"bullet","text":"•","level":1},{"kind":"text","text":"erster Punkt mit langem Text"},' +
    '{"kind":"bullet","text":"1.","level":2},{"kind":"text","text":"innen"},' +
    '{"kind":"para"},{"kind":"text","text":"Danach."}]}]}', 140);
  Assert.AreEqual('Liste:', LineText(mResult_.Lines[0]));
  Assert.AreEqual('•', mResult_.Lines[1].Spans[0].Text);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(mResult_.Lines[1].Spans[0].Color));
  Assert.AreEqual(0, mResult_.Lines[1].Spans[0].Left);
  // Marke mit festem Platz ("00. " = 28 Pixel); Fortsetzung hängt darunter.
  mHang := 28;
  Assert.AreEqual(mHang, mResult_.Lines[1].Spans[1].Left);
  Assert.AreEqual(mHang, mResult_.Lines[2].Spans[0].Left);
  Assert.AreEqual(Metrics.Indent, mResult_.Lines[High(mResult_.Lines) - 1].Spans[0].Left);
  Assert.AreEqual('1.', mResult_.Lines[High(mResult_.Lines) - 1].Spans[0].Text);
  Assert.AreEqual('Danach.', LineText(mResult_.Lines[High(mResult_.Lines)]));
  Assert.AreEqual(0, mResult_.Lines[High(mResult_.Lines)].Spans[0].Left);
end;

procedure TAtlasDocumentationTests.TableRowsInTwoColumns;
var
  mResult_: TAtlasDocLayout;
  mColumn: Integer;
begin
  mResult_ := Layout('{"sections":[{"kind":"summary","runs":[' +
    '{"kind":"bullet","text":"","level":1,"bold":true},{"kind":"text","text":"Wert","bold":true},' +
    '{"kind":"cell"},{"kind":"text","text":"Bedeutung","bold":true},' +
    '{"kind":"bullet","text":"","level":1},{"kind":"text","text":"0"},{"kind":"cell"},' +
    '{"kind":"text","text":"keine Spalten werden gefiltert"},' +
    '{"kind":"para"},{"kind":"text","text":"Ende"}]}]}', 200);
  // Begriffsspalte "Wert" = 28 Pixel.
  mColumn := 28 + Metrics.ColumnGap;
  Assert.AreEqual('Wert', mResult_.Lines[0].Spans[0].Text);
  Assert.IsTrue(mResult_.Lines[0].Spans[0].Face.Bold);
  Assert.AreEqual(mColumn, mResult_.Lines[0].Spans[1].Left);
  Assert.AreEqual('0', mResult_.Lines[1].Spans[0].Text);
  Assert.AreEqual(mColumn, mResult_.Lines[1].Spans[1].Left);
  // Beschreibung bricht in ihrer Spalte um.
  Assert.AreEqual(mColumn, mResult_.Lines[2].Spans[0].Left);
  Assert.AreEqual('Ende', LineText(mResult_.Lines[High(mResult_.Lines)]));
  Assert.IsTrue(Pos('Wert'#9'Bedeutung', mResult_.Text) > 0, mResult_.Text);
end;

procedure TAtlasDocumentationTests.HeadingsForTypeParamsExampleSeeAlso;
var
  mResult_: TAtlasDocLayout;
  mLine: TAtlasDocLine;
  mRules: Integer;
begin
  // Feste Reihenfolge, gleich in welcher Reihenfolge die Doku die Abschnitte hat.
  mResult_ := Layout('{"sections":[{"kind":"seealso","runs":[{"kind":"ref","text":"TList","target":"TList"}]},' +
    '{"kind":"example","runs":[{"kind":"codeblock","text":"L.Add(1);"}]},' +
    '{"kind":"remarks","runs":[{"kind":"text","text":"Bemerkung"}]},' +
    '{"kind":"value","runs":[{"kind":"text","text":"Anzahl"}]},' +
    '{"kind":"typeparam","name":"T","runs":[{"kind":"text","text":"Element"}]},' +
    '{"kind":"summary","runs":[{"kind":"text","text":"Liste."}]}]}', 400);
  Assert.AreEqual('Liste.|TYPPARAMETER|TElement|WERT|Anzahl|HINWEISE|Bemerkung|BEISPIEL|L.Add(1);|' +
    'SIEHE AUCH  TList|Weniger anzeigen ▴|', Texts(mResult_));
  mRules := 0;
  for mLine in mResult_.Lines do
  begin
    if mLine.Rule then
    begin
      Inc(mRules);
    end;
  end;
  // SIEHE AUCH steht in der Zeile der Verweise, ohne Linie.
  Assert.AreEqual(4, mRules);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(mResult_.Lines[6].Spans[0].Color));
  Assert.IsTrue(mResult_.Lines[9].Spans[0].Face.Small);
end;

procedure TAtlasDocumentationTests.CollapsedShowsToggleAndHiddenParts;
const
  cJson = '{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liest."}]},' +
    '{"kind":"param","name":"AName","runs":[{"kind":"text","text":"Name"}]},' +
    '{"kind":"exception","name":"EFehler","runs":[{"kind":"text","text":"x"}]},' +
    '{"kind":"remarks","runs":[{"kind":"text","text":"Hinweis"}]},' +
    '{"kind":"example","runs":[{"kind":"text","text":"So"}]}]}';
  cDeclaration = 'function TX.Lies(const AName: string; AFrom, ATo: Integer): Boolean;';
var
  mResult_: TAtlasDocLayout;
  mSpan: TAtlasDocSpan;
  mColors: TArray<TAtlasDocColor>;
  mParts: TArray<string>;
  mErrorSeen: Boolean;
begin
  mResult_ := LayoutWith(cJson, 600, cDeclaration, False);
  Assert.IsTrue(mResult_.Collapsible);
  Assert.IsFalse(mResult_.Expanded);
  Assert.AreEqual('Liest.|Mehr anzeigen ▾   3 Parameter · Rückgabe · 1 Ausnahme · Hinweis · Beispiel|',
    Texts(mResult_));
  mSpan := mResult_.Lines[1].Spans[0];
  Assert.AreEqual('Mehr anzeigen ▾', TrimRight(mSpan.Text));
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(mSpan.Color));
  Assert.IsFalse(mSpan.Underline);
  Assert.AreEqual(1, Integer(Length(mResult_.Links)));
  Assert.AreEqual(0, mResult_.LinkAt(mSpan.Left + 2, mResult_.Lines[1].Top + 2));
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Toggle), Ord(mResult_.Links[0].Kind));
  // Ausnahmen in Fehlerfarbe, der Rest gedämpft.
  mErrorSeen := False;
  for mSpan in mResult_.Lines[1].Spans do
  begin
    if mSpan.Color = TAtlasDocColor.Error then
    begin
      Assert.AreEqual('1 Ausnahme', mSpan.Text);
      mErrorSeen := True;
    end;
  end;
  Assert.IsTrue(mErrorSeen);
  mParts := TAtlasDocTypeset.HiddenParts(DocOf(cJson), TAtlasDocSignature.Parse(cDeclaration), TAtlasDocLabels.German,
    mColors);
  Assert.AreEqual(5, Integer(Length(mParts)));
  Assert.AreEqual('3 Parameter', mParts[0]);
  Assert.AreEqual(Ord(TAtlasDocColor.Error), Ord(mColors[2]));
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(mColors[0]));
  // Ohne erkannte Signatur zählen die <param> der Doku; Einzahl.
  mParts := TAtlasDocTypeset.HiddenParts(DocOf(cJson), Default(TAtlasDocSignature), TAtlasDocLabels.German, mColors);
  Assert.AreEqual('1 Parameter', mParts[0]);
  Assert.AreEqual('1 Ausnahme', mParts[1]);
  // Aufgeklappt endet mit „Weniger anzeigen“.
  mResult_ := LayoutWith(cJson, 600, cDeclaration, True);
  Assert.IsTrue(mResult_.Expanded);
  Assert.AreEqual('Weniger anzeigen ▴', LineText(mResult_.Lines[High(mResult_.Lines)]));
end;

procedure TAtlasDocumentationTests.SummaryOnlyHasNoToggle;
var
  mResult_: TAtlasDocLayout;
begin
  // Nur Beschreibung: kein Schalter, auch nicht mit Parametern in der Signatur.
  mResult_ := LayoutWith(Summary('Nur das.'), 400, 'procedure P(A, B: Integer);', False);
  Assert.IsFalse(mResult_.Collapsible);
  Assert.IsTrue(mResult_.Expanded);
  Assert.AreEqual('Nur das.|', Texts(mResult_));
  Assert.AreEqual(0, Integer(Length(mResult_.Links)));
  Assert.IsFalse(TAtlasDocTypeset.IsCollapsible(DocOf(Summary('x'))));
end;

procedure TAtlasDocumentationTests.ParamsInSignatureOrderWithTypes;
var
  mResult_: TAtlasDocLayout;
  mNameWidth, mTypeWidth: Integer;
begin
  mResult_ := LayoutWith('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Tut."}]},' +
    '{"kind":"param","name":"C","runs":[{"kind":"text","text":"drittes"}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"erstes"}]},' +
    '{"kind":"param","name":"X","runs":[{"kind":"text","text":"gibt es nicht"}]}]}', 600,
    'function TX.Foo(const A: string; var B, C: Integer; out D): Boolean; overload;', True);
  Assert.AreEqual('Tut.|PARAMETER|Aconst stringerstes|Bvar Integernicht dokumentiert|Cvar Integerdrittes|' +
    'Doutnicht dokumentiert|Xgibt es nicht|RÜCKGABE|Boolean|Weniger anzeigen ▴|', Texts(mResult_));
  // Spalten: Name (1 Zeichen), Art und Typ ("const string" = 12 Zeichen), Beschreibung.
  mNameWidth := 8;
  mTypeWidth := 12 * 8;
  Assert.AreEqual(mNameWidth + Metrics.ColumnGap, mResult_.Lines[2].Spans[1].Left);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(mResult_.Lines[2].Spans[1].Color));
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(mResult_.Lines[2].Spans[1].Face.Font));
  Assert.AreEqual(mNameWidth + mTypeWidth + 2 * Metrics.ColumnGap, mResult_.Lines[2].Spans[2].Left);
  // Ohne <param>: kursiv und gedämpft.
  Assert.IsTrue(mResult_.Lines[3].Spans[2].Face.Italic);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(mResult_.Lines[3].Spans[2].Color));
  // Unbekannter Parameter am Ende in Warnfarbe.
  Assert.AreEqual(Ord(TAtlasDocColor.Warn), Ord(mResult_.Lines[6].Spans[0].Color));
  Assert.AreEqual(Ord(TAtlasDocColor.Warn), Ord(mResult_.Lines[6].Spans[1].Color));
  // Rückgabe ohne <returns>: nur der Typ, in Schlüsselwortfarbe.
  Assert.AreEqual(Ord(TAtlasDocColor.Keyword), Ord(mResult_.Lines[8].Spans[0].Color));
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(mResult_.Lines[8].Spans[0].Face.Font));
  // Mit <returns>: Typ und Text.
  mResult_ := LayoutWith('{"sections":[{"kind":"returns","runs":[{"kind":"text","text":"Treffer"}]}]}', 600,
    'function F: Integer;', True);
  Assert.AreEqual('RÜCKGABE|IntegerTreffer|Weniger anzeigen ▴|', Texts(mResult_));
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(mResult_.Lines[1].Spans[1].Color));
end;

procedure TAtlasDocumentationTests.PropertyTypeUnderValue;
var
  mResult_: TAtlasDocLayout;
begin
  mResult_ := LayoutWith('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Zeilen."}]},' +
    '{"kind":"value","runs":[{"kind":"text","text":"Anzahl"}]}]}', 600,
    'property Items[AIndex: Integer]: TItem read GetItem; default;', True);
  Assert.AreEqual('Zeilen.|PARAMETER|AIndexIntegernicht dokumentiert|WERT|TItemAnzahl|Weniger anzeigen ▴|',
    Texts(mResult_));
end;

procedure TAtlasDocumentationTests.ParamRefIsPill;
var
  mResult_: TAtlasDocLayout;
  mSpan: TAtlasDocSpan;
begin
  mResult_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Setzt "},' +
    '{"kind":"paramref","text":"AValue"},{"kind":"text","text":" neu."}]}]}', 400);
  mSpan := mResult_.Lines[0].Spans[1];
  Assert.AreEqual('AValue', mSpan.Text);
  Assert.IsTrue(mSpan.Pill);
  Assert.AreEqual(Metrics.PillPad, mSpan.Pad);
  Assert.AreEqual(6 * 8 + 2 * Metrics.PillPad, mSpan.Width);
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(mSpan.Color));
  Assert.AreEqual(mSpan.Right, mResult_.Lines[0].Spans[2].Left);
  Assert.AreEqual('Setzt AValue neu.', mResult_.Text);
  // Markieren rechnet mit dem Innenabstand.
  Assert.AreEqual(6, mResult_.PositionAt(mSpan.Left + 1, 4, Measure));
  Assert.AreEqual(7, mResult_.PositionAt(mSpan.Left + mSpan.Pad + 5, 4, Measure));
end;

procedure TAtlasDocumentationTests.ParsesSignatures;
var
  mSignature: TAtlasDocSignature;
begin
  mSignature := TAtlasDocSignature.Parse('class function TList<T>.Find(const AItem: T; [Ref] var AIndex: Integer;' +
    ' AComparer: IComparer<T> = nil; const A, B: TArray<string>): Boolean; overload;');
  Assert.IsTrue(mSignature.Known);
  Assert.IsFalse(mSignature.IsProperty);
  Assert.AreEqual(5, Integer(Length(mSignature.Params)));
  Assert.AreEqual('AItem', mSignature.Params[0].Name);
  Assert.AreEqual('const T', mSignature.Params[0].TypeText);
  Assert.AreEqual('AIndex', mSignature.Params[1].Name);
  Assert.AreEqual('var', mSignature.Params[1].Modifier);
  Assert.AreEqual('IComparer<T>', mSignature.Params[2].TypeName);
  Assert.AreEqual('B', mSignature.Params[4].Name);
  Assert.AreEqual('TArray<string>', mSignature.Params[4].TypeName);
  Assert.AreEqual('Boolean', mSignature.ResultType);
  Assert.AreEqual(3, mSignature.IndexOf('a'));
  Assert.AreEqual(-1, mSignature.IndexOf('Z'));
  Assert.IsTrue(mSignature.HasTypes);
  mSignature := TAtlasDocSignature.Parse('procedure Lauf;');
  Assert.IsTrue(mSignature.Known);
  Assert.AreEqual(0, Integer(Length(mSignature.Params)));
  Assert.AreEqual('', mSignature.ResultType);
  mSignature := TAtlasDocSignature.Parse('procedure Untyped(var Buffer; Count: Integer);');
  Assert.AreEqual('var', mSignature.Params[0].TypeText);
  Assert.AreEqual('Integer', mSignature.Params[1].TypeText);
  mSignature := TAtlasDocSignature.Parse('property Caption: string read FCaption write SetCaption;');
  Assert.IsTrue(mSignature.IsProperty);
  Assert.AreEqual('string', mSignature.ResultType);
  mSignature := TAtlasDocSignature.Parse('constructor Create(AOwner: TComponent); override;');
  Assert.AreEqual('AOwner', mSignature.Params[0].Name);
  Assert.IsFalse(TAtlasDocSignature.Parse('TGalleryFrameClass = class of TBFrame;').Known);
  Assert.IsFalse(TAtlasDocSignature.Parse('').Known);
end;

procedure TAtlasDocumentationTests.ExpandStatePerSurface;
begin
  Assert.IsFalse(TAtlasDocExpandState.Initial(TAtlasDocExpand.Last, TAtlasDocSurface.Tooltip));
  Assert.IsTrue(TAtlasDocExpandState.Initial(TAtlasDocExpand.Expanded, TAtlasDocSurface.Tooltip));
  TAtlasDocExpandState.Remember(TAtlasDocSurface.Tooltip, True);
  Assert.IsTrue(TAtlasDocExpandState.Initial(TAtlasDocExpand.Last, TAtlasDocSurface.Tooltip));
  // Getrennt je Fläche; „immer zugeklappt“ gilt trotz Merker.
  Assert.IsFalse(TAtlasDocExpandState.Initial(TAtlasDocExpand.Last, TAtlasDocSurface.Details));
  Assert.IsFalse(TAtlasDocExpandState.Initial(TAtlasDocExpand.Collapsed, TAtlasDocSurface.Tooltip));
  TAtlasDocExpandState.Reset;
  Assert.IsFalse(TAtlasDocExpandState.Initial(TAtlasDocExpand.Last, TAtlasDocSurface.Tooltip));
end;

procedure TAtlasDocumentationTests.SelectionCopiesText;
var
  mResult_: TAtlasDocLayout;
  mFrom, mTill: Integer;
begin
  mResult_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Eins zwei drei vier"}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"Wert"}]}]}', 90);
  Assert.AreEqual('Eins zwei '#13#10'drei vier'#13#10'PARAMETER'#13#10'A'#9'Wert'#13#10'Weniger anzeigen ▴',
    mResult_.Text);
  // Von der Mitte von "zwei" (Zeichen 6 = 42 Pixel) bis hinter "drei".
  mFrom := mResult_.PositionAt(7 * 5 + 2, 4, Measure);
  mTill := mResult_.PositionAt(7 * 4 + 1, 16 + 4, Measure);
  Assert.AreEqual('zwei '#13#10'drei', mResult_.Selected(mFrom, mTill));
  Assert.AreEqual('zwei '#13#10'drei', mResult_.Selected(mTill, mFrom));
  Assert.AreEqual(0, mResult_.PositionAt(50, -5, Measure));
  Assert.AreEqual(Integer(Length(mResult_.Text)), mResult_.PositionAt(0, 1000, Measure));
  Assert.AreEqual(mResult_.Text, mResult_.Selected(0, MaxInt));
end;

procedure TAtlasDocumentationTests.LongDocumentIsNotTruncated;
var
  mResult_: TAtlasDocLayout;
  mLong: string;
  mIndex: Integer;
begin
  mLong := '';
  for mIndex := 1 to 200 do
  begin
    mLong := mLong + 'Wort ';
  end;
  mResult_ := Layout(Summary(mLong), 140);
  Assert.AreEqual(50, Integer(Length(mResult_.Lines)));
  Assert.AreEqual(50 * 16, mResult_.Height);
  Assert.AreEqual(10 * 16, mResult_.HeightOfLines(10));
  Assert.AreEqual(0, Pos('…', mResult_.Text));
end;

procedure TAtlasDocumentationTests.PlainTextOfForeignServers;
var
  mDoc: TAtlasDoc;
  mResult_: TAtlasDocLayout;
begin
  mDoc := TAtlasDoc.FromText('Erste Zeile'#13#10'zweite'#10#10'Absatz'#10'  Code := 1;'#10'  Weiter;'#10);
  Assert.AreEqual(1, Integer(Length(mDoc.Sections)));
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Summary), Ord(mDoc.Sections[0].Kind));
  Assert.AreEqual(7, Integer(Length(mDoc.Sections[0].Runs)));
  Assert.AreEqual(Ord(TAtlasDocRunKind.LineBreak), Ord(mDoc.Sections[0].Runs[1].Kind));
  Assert.AreEqual(Ord(TAtlasDocRunKind.Paragraph), Ord(mDoc.Sections[0].Runs[3].Kind));
  Assert.AreEqual('  Code := 1;'#10'  Weiter;', mDoc.Sections[0].Runs[6].Text);
  Assert.IsTrue(TAtlasDoc.FromText('  ').IsEmpty);
  mResult_ := TAtlasDocTypeset.Build(mDoc, 400, Metrics, Measure, TAtlasDocLabels.German);
  Assert.AreEqual('Erste Zeile'#13#10'zweite'#13#10'Absatz'#13#10'  Code := 1;'#13#10'  Weiter;', mResult_.Text);
end;

function Rationale(const AMarker, AText: string): string;
begin
  Result := '{"kind":"rationale","name":"' + AMarker + '","runs":[{"kind":"text","text":"' + AText + '"}]}';
end;

procedure TAtlasDocumentationTests.RationaleBelowDocumentation;
var
  mDoc: TAtlasDoc;
  mResult_: TAtlasDocLayout;
begin
  mDoc := DocOf('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liest."}]},' +
    Rationale('WHY', 'Schnell.') + ',' + Rationale('HACK', 'QC 1.') + ']}');
  Assert.AreEqual(3, Integer(Length(mDoc.Sections)));
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Rationale), Ord(mDoc.Sections[1].Kind));
  Assert.AreEqual('WHY', mDoc.Sections[1].Name);
  Assert.AreEqual(2, Integer(Length(mDoc.SectionsOf(TAtlasDocSectionKind.Rationale))));
  // Bis drei Einträge kein Schalter.
  Assert.IsFalse(TAtlasDocTypeset.IsCollapsible(mDoc));
  mResult_ := TAtlasDocTypeset.Build(TAtlasDocContent.Create(mDoc, Default(TAtlasDocSignature), False), 600, Metrics,
    Measure, TAtlasDocLabels.German);
  Assert.AreEqual('Liest.|BEGRÜNDUNG|WHYSchnell.|HACKQC 1.|', Texts(mResult_));
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(mResult_.Lines[2].Spans[0].Color));
end;

procedure TAtlasDocumentationTests.RationaleBeyondThreeBehindToggle;
const
  cJson = '{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liest."}]},';
var
  mDoc: TAtlasDoc;
  mResult_: TAtlasDocLayout;
begin
  mDoc := DocOf(cJson + Rationale('WHY', 'A') + ',' + Rationale('WHY', 'B') + ',' + Rationale('NOTE', 'C') + ',' +
    Rationale('HACK', 'D') + ',' + Rationale('HACK', 'E') + ']}');
  Assert.IsTrue(TAtlasDocTypeset.IsCollapsible(mDoc));
  mResult_ := TAtlasDocTypeset.Build(TAtlasDocContent.Create(mDoc, Default(TAtlasDocSignature), False), 600, Metrics,
    Measure, TAtlasDocLabels.German);
  Assert.AreEqual('Liest.|BEGRÜNDUNG|WHYA|WHYB|NOTEC|Mehr anzeigen ▾   2 weitere Begründungen|', Texts(mResult_));
  mResult_ := TAtlasDocTypeset.Build(TAtlasDocContent.Create(mDoc, Default(TAtlasDocSignature), True), 600, Metrics,
    Measure, TAtlasDocLabels.German);
  Assert.AreEqual('Liest.|BEGRÜNDUNG|WHYA|WHYB|NOTEC|HACKD|HACKE|Weniger anzeigen ▴|', Texts(mResult_));
end;

function UnitGroup(const AHeading, AName, AType: string): string;
begin
  Result := '{"kind":"unitContents","heading":"' + AHeading + '","name":"' + AName + '","runs":[' +
    '{"kind":"ref","text":"' + AType + '","target":"' + AType + '","file":"C:\\P\\Werk.pas","line":3}]}';
end;

procedure TAtlasDocumentationTests.UnitContentsBelowPath;
var
  mDoc: TAtlasDoc;
  mResult_: TAtlasDocLayout;
begin
  mDoc := DocOf('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Werk.pas"}]},' +
    UnitGroup('BENUTZT (1)', 'Klassen', 'TKunde') + ',' + UnitGroup('WEITERE (2)', 'Klassen', 'TAuftrag') + ',' +
    UnitGroup('WEITERE (2)', 'Records', 'TPunkt') + ']}');
  Assert.AreEqual(3, Integer(Length(mDoc.SectionsOf(TAtlasDocSectionKind.UnitContents))));
  Assert.AreEqual('WEITERE (2)', mDoc.Sections[2].Heading);
  Assert.IsFalse(TAtlasDocTypeset.IsCollapsible(mDoc));
  mResult_ := TAtlasDocTypeset.Build(TAtlasDocContent.Create(mDoc, Default(TAtlasDocSignature), False), 600, Metrics,
    Measure, TAtlasDocLabels.German);
  Assert.AreEqual('Werk.pas|BENUTZT (1)|KlassenTKunde|WEITERE (2)|KlassenTAuftrag|RecordsTPunkt|', Texts(mResult_));
  Assert.AreEqual(3, Integer(Length(mResult_.Links)));
end;

procedure TAtlasDocumentationTests.IssueLinksNeedTracker;
const
  cJson = '{"sections":[{"kind":"rationale","name":"WHY","runs":[{"kind":"text","text":"Siehe "},' +
    '{"kind":"link","text":"#312","target":"issue:312"}]}]}';
var
  mResult_: TAtlasDocLayout;
begin
  // Ohne Tracker: Text, kein Link.
  mResult_ := Layout(cJson, 600);
  Assert.AreEqual(0, Integer(Length(mResult_.Links)));
  TAtlasDocIssueLinks.SetResolver(
    function(const AKey: string): string
    begin
      Result := 'https://github.com/o/r/issues/' + AKey;
    end);
  mResult_ := Layout(cJson, 600);
  Assert.AreEqual(1, Integer(Length(mResult_.Links)));
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Url), Ord(mResult_.Links[0].Kind));
  Assert.AreEqual('https://github.com/o/r/issues/312', mResult_.Links[0].Url);
  // Nur Web-Adressen.
  TAtlasDocIssueLinks.SetResolver(
    function(const AKey: string): string
    begin
      Result := 'file:///C:/x';
    end);
  Assert.AreEqual(0, Integer(Length(Layout(cJson, 600).Links)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDocumentationTests);

end.
