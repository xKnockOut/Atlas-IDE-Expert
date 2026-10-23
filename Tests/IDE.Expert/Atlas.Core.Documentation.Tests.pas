unit Atlas.Core.Documentation.Tests;

// Tests für die strukturierte XMLDoc im Plugin (#654, #770): Lesen der
// Server-Antwort, Signatur aus der Deklaration, Zustand „wie zuletzt“ und Satz
// für Tooltip und Detailpanel (Abschnitte, Schalter, verborgene Teile). Gemessen
// wird mit fester Zeichenbreite (UI 7, Editorschrift 8 Pixel), damit die
// Positionen vorhersagbar sind.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Documentation.Contract,
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
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

function Measure(const AText: string; const AFace: TAtlasDocFace): Integer;
begin
  if AFace.Font = TAtlasDocFont.Mono then
    Result := 8 * Length(AText)
  else
    Result := 7 * Length(AText);
end;

function Metrics: TAtlasDocMetrics;
begin
  Result := TAtlasDocMetrics.Create(16, 17, 1);
end;

function DocOf(const AJson: string): TAtlasDoc;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasDoc.FromJson(Value);
  finally
    Value.Free;
  end;
end;

function LineText(const ALine: TAtlasDocLine): string;
var
  Span: TAtlasDocSpan;
begin
  Result := '';
  for Span in ALine.Spans do
    Result := Result + Span.Text;
end;

function Summary(const AText: string): string;
begin
  Result := '{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"' + AText + '"}]}]}';
end;

{ TAtlasDocumentationTests }

function Texts(const ALayout: TAtlasDocLayout): string;
var
  Line: TAtlasDocLine;
begin
  Result := '';
  for Line in ALayout.Lines do
    Result := Result + LineText(Line) + '|';
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
  Result := TAtlasDocLayout.Build(DocOf(AJson), AWidth, Metrics, Measure, TAtlasDocLabels.German);
end;

function TAtlasDocumentationTests.LayoutWith(const AJson: string; AWidth: Integer; const ADeclaration: string;
  AExpanded: Boolean): TAtlasDocLayout;
begin
  Result := TAtlasDocLayout.Build(DocOf(AJson), AWidth, Metrics, Measure, TAtlasDocLabels.German,
    TAtlasDocSignature.Parse(ADeclaration), AExpanded);
end;


procedure TAtlasDocumentationTests.ReadsSectionsRunsAndTargets;
var
  Doc: TAtlasDoc;
begin
  Doc := DocOf('{"sections":[' +
    '{"kind":"summary","runs":[{"kind":"text","text":"Filter für "},' +
    '{"kind":"ref","text":"TDBGrid","target":"TDBGrid","name":"TDBGrid","unit":"Vcl.DBGrids",' +
    '"file":"C:\\RTL\\Vcl.DBGrids.pas","line":40,"character":2},' +
    '{"kind":"text","text":" ","bold":true,"italic":true},{"kind":"link","text":"Doku","target":"https://x"}]},' +
    '{"kind":"param","name":"AOwner","runs":[{"kind":"text","text":"Besitzer"}]},' +
    '{"kind":"exception","name":"EZeichnen","ref":{"name":"EZeichnen","file":"C:\\P\\U.pas","line":3,' +
    '"character":2},"runs":[{"kind":"text","text":"bei Fehlern"}]}]}');
  Assert.AreEqual(3, Integer(Length(Doc.Sections)));
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Summary), Ord(Doc.Sections[0].Kind));
  Assert.AreEqual(4, Integer(Length(Doc.Sections[0].Runs)));
  Assert.AreEqual(Ord(TAtlasDocRunKind.Ref), Ord(Doc.Sections[0].Runs[1].Kind));
  Assert.IsTrue(Doc.Sections[0].Runs[1].Location.HasLocation);
  Assert.AreEqual('Vcl.DBGrids', Doc.Sections[0].Runs[1].Location.UnitName);
  Assert.AreEqual(40, Doc.Sections[0].Runs[1].Location.Line);
  Assert.IsTrue(Doc.Sections[0].Runs[2].Bold);
  Assert.IsTrue(Doc.Sections[0].Runs[2].Italic);
  Assert.AreEqual('https://x', Doc.Sections[0].Runs[3].Target);
  Assert.AreEqual('AOwner', Doc.Sections[1].Name);
  Assert.AreEqual('EZeichnen', Doc.Sections[2].NameRef.Name);
  Assert.IsTrue(Doc.Sections[2].NameRef.HasLocation);
  Assert.AreEqual('Filter für TDBGrid Doku', Doc.Sections[0].Text);
  Assert.IsTrue(Doc.Has(TAtlasDocSectionKind.Exception));
  Assert.IsFalse(Doc.Has(TAtlasDocSectionKind.Remarks));
end;

procedure TAtlasDocumentationTests.SkipsUnknownKinds;
var
  Doc: TAtlasDoc;
begin
  Doc := DocOf('{"sections":[{"kind":"neu","runs":[]},' +
    '{"kind":"remarks","runs":[{"kind":"blink","text":"x"},{"kind":"text","text":"y"}]}]}');
  Assert.AreEqual(1, Integer(Length(Doc.Sections)));
  Assert.AreEqual(1, Integer(Length(Doc.Sections[0].Runs)));
  Assert.IsTrue(DocOf('"text"').IsEmpty);
  Assert.IsTrue(DocOf('{}').IsEmpty);
end;

procedure TAtlasDocumentationTests.ReadsDisplaySettings;
var
  Fallback, Display: TAtlasDocDisplay;
  Value: TJSONValue;
begin
  Fallback := TAtlasDocDisplay.Create(TAtlasDocExpand.Expanded, 70);
  Assert.AreEqual(TAtlasDocDisplay.MaxMaxLines, Fallback.MaxLines);
  Display := TAtlasDocDisplay.FromJson(nil, TAtlasDocDisplay.Create(TAtlasDocExpand.Collapsed, 5));
  Assert.IsFalse(Display.Known);
  Assert.AreEqual(Ord(TAtlasDocExpand.Collapsed), Ord(Display.Expand));
  Assert.AreEqual(5, Display.MaxLines);
  Value := TJSONObject.ParseJSONValue('{"expand":"expanded","maxLines":12}');
  try
    Display := TAtlasDocDisplay.FromJson(Value, TAtlasDocDisplay.Create(TAtlasDocExpand.Collapsed, 5));
  finally
    Value.Free;
  end;
  Assert.IsTrue(Display.Known);
  Assert.AreEqual(Ord(TAtlasDocExpand.Expanded), Ord(Display.Expand));
  Assert.AreEqual(12, Display.MaxLines);
  // Server vor #770: "full".
  Value := TJSONObject.ParseJSONValue('{"full":false}');
  try
    Display := TAtlasDocDisplay.FromJson(Value, TAtlasDocDisplay.Create(TAtlasDocExpand.Last, 5));
  finally
    Value.Free;
  end;
  Assert.AreEqual(Ord(TAtlasDocExpand.Collapsed), Ord(Display.Expand));
  Assert.AreEqual(5, Display.MaxLines);
  Assert.AreEqual(Ord(TAtlasDocExpand.Last), Ord(TAtlasDocDisplay.ExpandOf('LAST')));
  Assert.AreEqual(Ord(TAtlasDocExpand.Last), Ord(TAtlasDocDisplay.ExpandOf('unsinn')));
  Assert.AreEqual(Ord(TAtlasDocExpand.Collapsed), Ord(TAtlasDocDisplay.ExpandOf(' collapsed ')));
  Assert.AreEqual('expanded', TAtlasDocDisplay.ExpandName(TAtlasDocExpand.Expanded));
end;

procedure TAtlasDocumentationTests.WrapsAtWordBoundaries;
var
  Result_: TAtlasDocLayout;
  Line: TAtlasDocLine;
  Joined: string;
begin
  // Höchstens 12 Zeichen je Zeile bei 90 Pixeln.
  Result_ := Layout(Summary('Eins zwei drei vier fünf sechs sieben acht'), 90);
  Assert.IsTrue(Length(Result_.Lines) > 2);
  Joined := '';
  for Line in Result_.Lines do
  begin
    Assert.IsTrue(Line.Spans[High(Line.Spans)].Right - 7 * (Length(LineText(Line)) - Length(TrimRight(LineText(Line))))
      <= 90, LineText(Line));
    Assert.AreNotEqual(' ', Copy(LineText(Line), 1, 1));
    Joined := Joined + LineText(Line);
  end;
  Assert.AreEqual('Eins zwei drei vier fünf sechs sieben acht', TrimRight(Joined));
  Assert.AreEqual('Eins zwei ', LineText(Result_.Lines[0]));
  Assert.AreEqual(16, Result_.Lines[1].Top);
  Assert.AreEqual(Result_.Lines[High(Result_.Lines)].Bottom, Result_.Height);
end;

procedure TAtlasDocumentationTests.BreaksLongWordsAtCharacters;
var
  Result_: TAtlasDocLayout;
  Line: TAtlasDocLine;
begin
  Result_ := Layout(Summary('ABCDEFGHIJKLMNOPQRSTUVWXYZ'), 70);
  Assert.AreEqual(3, Integer(Length(Result_.Lines)));
  for Line in Result_.Lines do
    Assert.IsTrue(Line.Spans[High(Line.Spans)].Right <= 70);
  Assert.AreEqual('ABCDEFGHIJ', LineText(Result_.Lines[0]));
end;

procedure TAtlasDocumentationTests.RefsAndLinksAreClickable;
var
  Result_: TAtlasDocLayout;
  Span: TAtlasDocSpan;
  Link: Integer;
begin
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Siehe "},' +
    '{"kind":"ref","text":"TFoo.Bar","target":"TFoo.Bar","name":"Bar","file":"C:\\U.pas","line":9,"character":4},' +
    '{"kind":"text","text":" und "},{"kind":"link","text":"Web","target":"https://example.org"}]}]}', 400);
  Assert.AreEqual(1, Integer(Length(Result_.Lines)));
  Assert.AreEqual(2, Integer(Length(Result_.Links)));
  Span := Result_.Lines[0].Spans[1];
  Assert.AreEqual('TFoo.Bar', Span.Text);
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(Span.Face.Font));
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(Span.Color));
  Assert.IsTrue(Span.Underline);
  Link := Result_.LinkAt(Span.Left + 2, 3);
  Assert.AreEqual(0, Link);
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Ref), Ord(Result_.Links[Link].Kind));
  Assert.AreEqual('C:\U.pas', Result_.Links[Link].Target.FileName);
  Assert.AreEqual(9, Result_.Links[Link].Target.Line);
  Span := Result_.Lines[0].Spans[3];
  Link := Result_.LinkAt(Span.Left + 1, 1);
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Url), Ord(Result_.Links[Link].Kind));
  Assert.AreEqual('https://example.org', Result_.Links[Link].Url);
  Assert.AreEqual(-1, Result_.LinkAt(1, 1));
  Assert.AreEqual(-1, Result_.LinkAt(Span.Left + 1, 40));
end;

procedure TAtlasDocumentationTests.RefWithoutLocationIsNotClickable;
var
  Result_: TAtlasDocLayout;
begin
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"ref","text":"TUnbekannt","target":"TUnbekannt"},' +
    '{"kind":"link","text":"leer"}]}]}', 400);
  Assert.AreEqual(0, Integer(Length(Result_.Links)));
  Assert.IsFalse(Result_.Lines[0].Spans[0].Underline);
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(Result_.Lines[0].Spans[0].Color));
end;

procedure TAtlasDocumentationTests.ParametersInTwoColumns;
var
  Result_: TAtlasDocLayout;
  Column: Integer;
begin
  // Ohne Signatur: Name und Beschreibung, in der Reihenfolge der Doku.
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Tut."}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"erster Wert"}]},' +
    '{"kind":"param","name":"ALangerName","runs":[{"kind":"text","text":"zweiter Wert mit viel Text dazu"}]},' +
    '{"kind":"returns","runs":[{"kind":"text","text":"Summe"}]}]}', 300);
  Assert.AreEqual('Tut.|PARAMETER|Aerster Wert|ALangerNamezweiter Wert mit viel Text |dazu|RÜCKGABE|Summe|' +
    'Weniger anzeigen ▴|', Texts(Result_));
  Assert.IsTrue(Result_.Lines[1].Rule);
  Assert.AreEqual(9 * 7 + Metrics.ColumnGap, Result_.Lines[1].RuleFrom);
  Assert.IsTrue(Result_.Lines[1].Spans[0].Face.Small);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Result_.Lines[1].Spans[0].Color));
  // Namensspalte: "ALangerName" = 88 Pixel (< 30 % von 300), dazu der Abstand.
  Column := 88 + Metrics.ColumnGap;
  Assert.AreEqual('A', Result_.Lines[2].Spans[0].Text);
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(Result_.Lines[2].Spans[0].Color));
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(Result_.Lines[2].Spans[0].Face.Font));
  Assert.IsTrue(Result_.Lines[2].Spans[0].Face.Bold);
  Assert.AreEqual(Column, Result_.Lines[2].Spans[1].Left);
  Assert.AreEqual(Ord(TAtlasDocColor.Text), Ord(Result_.Lines[2].Spans[1].Color));
  Assert.AreEqual(Column, Result_.Lines[3].Spans[1].Left);
  // Fortsetzungszeile bleibt in der Textspalte.
  Assert.AreEqual(Column, Result_.Lines[4].Spans[0].Left);
  // Rückgabe ohne Signatur: nur der Text, gedämpft.
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Result_.Lines[6].Spans[0].Color));
  // Sehr lange Namen: Spalte höchstens 30 % (45 Pixel), der Name bricht an Zeichen um.
  Result_ := Layout('{"sections":[{"kind":"param","name":"AEinSehrSehrLangerName","runs":' +
    '[{"kind":"text","text":"Text"}]}]}', 150);
  Assert.AreEqual('AEinS', Result_.Lines[1].Spans[0].Text);
  Assert.AreEqual(45 + Metrics.ColumnGap, Result_.Lines[1].Spans[1].Left);
end;

procedure TAtlasDocumentationTests.ExceptionClassIsClickable;
var
  Result_: TAtlasDocLayout;
  Span: TAtlasDocSpan;
begin
  Result_ := Layout('{"sections":[{"kind":"exception","name":"EZeichnen","ref":{"name":"EZeichnen",' +
    '"file":"C:\\U.pas","line":3,"character":2},"runs":[{"kind":"text","text":"bei Fehlern"}]},' +
    '{"kind":"exception","name":"EFremd","runs":[{"kind":"text","text":"unbekannt"}]}]}', 400);
  Assert.AreEqual('AUSNAHMEN', LineText(Result_.Lines[0]));
  Span := Result_.Lines[1].Spans[0];
  Assert.AreEqual('EZeichnen', Span.Text);
  Assert.AreEqual(Ord(TAtlasDocColor.Error), Ord(Span.Color));
  Assert.IsTrue(Span.Underline);
  Assert.AreEqual(0, Result_.LinkAt(Span.Left + 3, Result_.Lines[1].Top + 2));
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Ref), Ord(Result_.Links[0].Kind));
  Assert.AreEqual('EZeichnen', Result_.Links[0].Target.Name);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Result_.Lines[1].Spans[1].Color));
  Assert.AreEqual(-1, Result_.Lines[2].Spans[0].Link);
  // Dazu nur der Schalter „Weniger anzeigen“.
  Assert.AreEqual(2, Integer(Length(Result_.Links)));
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Toggle), Ord(Result_.Links[1].Kind));
end;

procedure TAtlasDocumentationTests.CodeBlockKeepsIndentAndColors;
var
  Result_: TAtlasDocLayout;
  First: Integer;
begin
  Result_ := Layout('{"sections":[{"kind":"example","runs":[{"kind":"text","text":"So:"},' +
    '{"kind":"codeblock","text":"begin\n  X := ''a'';\nend;"}]}]}', 400);
  // Überschrift, "So:", drei Codezeilen, Schalter.
  Assert.AreEqual(6, Integer(Length(Result_.Lines)));
  Assert.AreEqual('BEISPIEL', LineText(Result_.Lines[0]));
  Assert.IsFalse(Result_.Lines[1].Shaded);
  First := 2;
  Assert.AreEqual('begin', LineText(Result_.Lines[First]));
  Assert.AreEqual(Ord(TAtlasDocColor.Keyword), Ord(Result_.Lines[First].Spans[0].Color));
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(Result_.Lines[First].Spans[0].Face.Font));
  Assert.AreEqual('  X := ''a'';', LineText(Result_.Lines[First + 1]));
  Assert.AreEqual(Ord(TAtlasDocColor.StringLiteral), Ord(Result_.Lines[First + 1].Spans[1].Color));
  Assert.AreEqual(17, Result_.Lines[First].Height);
  Assert.IsTrue(Result_.Lines[First].GapBefore > 0);
  // Schattierte Fläche ab dem Rand, Text um CodePad eingerückt, ohne Lücke zwischen den Zeilen.
  Assert.IsTrue(Result_.Lines[First].Shaded);
  Assert.IsTrue(Result_.Lines[First + 2].Shaded);
  Assert.AreEqual(0, Result_.Lines[First].ShadeLeft);
  Assert.AreEqual(Metrics.CodePad, Result_.Lines[First].Spans[0].Left);
  Assert.AreEqual(0, Result_.Lines[First + 1].GapBefore);
  Assert.IsFalse(Result_.Lines[First + 3].Shaded);
  // Zu lange Codezeilen brechen an Zeichen um, eingerückt.
  Result_ := Layout('{"sections":[{"kind":"example","runs":[{"kind":"codeblock","text":"' +
    'WriteLn(Eins, Zwei, Drei);"}]}]}', 100);
  Assert.IsTrue(Length(Result_.Lines) >= 4);
  Assert.AreEqual(Metrics.CodePad + Metrics.Indent, Result_.Lines[2].Spans[0].Left);
  Assert.IsTrue(Result_.Lines[2].Shaded);
end;

procedure TAtlasDocumentationTests.BulletsHangAndIndentPerLevel;
var
  Result_: TAtlasDocLayout;
  Hang: Integer;
begin
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liste:"},' +
    '{"kind":"bullet","text":"•","level":1},{"kind":"text","text":"erster Punkt mit langem Text"},' +
    '{"kind":"bullet","text":"1.","level":2},{"kind":"text","text":"innen"},' +
    '{"kind":"para"},{"kind":"text","text":"Danach."}]}]}', 140);
  Assert.AreEqual('Liste:', LineText(Result_.Lines[0]));
  Assert.AreEqual('•', Result_.Lines[1].Spans[0].Text);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Result_.Lines[1].Spans[0].Color));
  Assert.AreEqual(0, Result_.Lines[1].Spans[0].Left);
  // Marke mit festem Platz ("00. " = 28 Pixel); Fortsetzung hängt darunter.
  Hang := 28;
  Assert.AreEqual(Hang, Result_.Lines[1].Spans[1].Left);
  Assert.AreEqual(Hang, Result_.Lines[2].Spans[0].Left);
  Assert.AreEqual(Metrics.Indent, Result_.Lines[High(Result_.Lines) - 1].Spans[0].Left);
  Assert.AreEqual('1.', Result_.Lines[High(Result_.Lines) - 1].Spans[0].Text);
  Assert.AreEqual('Danach.', LineText(Result_.Lines[High(Result_.Lines)]));
  Assert.AreEqual(0, Result_.Lines[High(Result_.Lines)].Spans[0].Left);
end;

procedure TAtlasDocumentationTests.TableRowsInTwoColumns;
var
  Result_: TAtlasDocLayout;
  Column: Integer;
begin
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[' +
    '{"kind":"bullet","text":"","level":1,"bold":true},{"kind":"text","text":"Wert","bold":true},' +
    '{"kind":"cell"},{"kind":"text","text":"Bedeutung","bold":true},' +
    '{"kind":"bullet","text":"","level":1},{"kind":"text","text":"0"},{"kind":"cell"},' +
    '{"kind":"text","text":"keine Spalten werden gefiltert"},' +
    '{"kind":"para"},{"kind":"text","text":"Ende"}]}]}', 200);
  // Begriffsspalte "Wert" = 28 Pixel.
  Column := 28 + Metrics.ColumnGap;
  Assert.AreEqual('Wert', Result_.Lines[0].Spans[0].Text);
  Assert.IsTrue(Result_.Lines[0].Spans[0].Face.Bold);
  Assert.AreEqual(Column, Result_.Lines[0].Spans[1].Left);
  Assert.AreEqual('0', Result_.Lines[1].Spans[0].Text);
  Assert.AreEqual(Column, Result_.Lines[1].Spans[1].Left);
  // Beschreibung bricht in ihrer Spalte um.
  Assert.AreEqual(Column, Result_.Lines[2].Spans[0].Left);
  Assert.AreEqual('Ende', LineText(Result_.Lines[High(Result_.Lines)]));
  Assert.IsTrue(Pos('Wert'#9'Bedeutung', Result_.Text) > 0, Result_.Text);
end;

procedure TAtlasDocumentationTests.HeadingsForTypeParamsExampleSeeAlso;
var
  Result_: TAtlasDocLayout;
  Line: TAtlasDocLine;
  Rules: Integer;
begin
  // Feste Reihenfolge, gleich in welcher Reihenfolge die Doku die Abschnitte hat.
  Result_ := Layout('{"sections":[{"kind":"seealso","runs":[{"kind":"ref","text":"TList","target":"TList"}]},' +
    '{"kind":"example","runs":[{"kind":"codeblock","text":"L.Add(1);"}]},' +
    '{"kind":"remarks","runs":[{"kind":"text","text":"Bemerkung"}]},' +
    '{"kind":"value","runs":[{"kind":"text","text":"Anzahl"}]},' +
    '{"kind":"typeparam","name":"T","runs":[{"kind":"text","text":"Element"}]},' +
    '{"kind":"summary","runs":[{"kind":"text","text":"Liste."}]}]}', 400);
  Assert.AreEqual('Liste.|TYPPARAMETER|TElement|WERT|Anzahl|HINWEISE|Bemerkung|BEISPIEL|L.Add(1);|' +
    'SIEHE AUCH  TList|Weniger anzeigen ▴|', Texts(Result_));
  Rules := 0;
  for Line in Result_.Lines do
    if Line.Rule then
      Inc(Rules);
  // SIEHE AUCH steht in der Zeile der Verweise, ohne Linie.
  Assert.AreEqual(4, Rules);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Result_.Lines[6].Spans[0].Color));
  Assert.IsTrue(Result_.Lines[9].Spans[0].Face.Small);
end;

procedure TAtlasDocumentationTests.CollapsedShowsToggleAndHiddenParts;
const
  Json = '{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liest."}]},' +
    '{"kind":"param","name":"AName","runs":[{"kind":"text","text":"Name"}]},' +
    '{"kind":"exception","name":"EFehler","runs":[{"kind":"text","text":"x"}]},' +
    '{"kind":"remarks","runs":[{"kind":"text","text":"Hinweis"}]},' +
    '{"kind":"example","runs":[{"kind":"text","text":"So"}]}]}';
  Declaration = 'function TX.Lies(const AName: string; AFrom, ATo: Integer): Boolean;';
var
  Result_: TAtlasDocLayout;
  Span: TAtlasDocSpan;
  Colors: TArray<TAtlasDocColor>;
  Parts: TArray<string>;
  ErrorSeen: Boolean;
begin
  Result_ := LayoutWith(Json, 600, Declaration, False);
  Assert.IsTrue(Result_.Collapsible);
  Assert.IsFalse(Result_.Expanded);
  Assert.AreEqual('Liest.|Mehr anzeigen ▾   3 Parameter · Rückgabe · 1 Ausnahme · Hinweis · Beispiel|',
    Texts(Result_));
  Span := Result_.Lines[1].Spans[0];
  Assert.AreEqual('Mehr anzeigen ▾', TrimRight(Span.Text));
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(Span.Color));
  Assert.IsFalse(Span.Underline);
  Assert.AreEqual(1, Integer(Length(Result_.Links)));
  Assert.AreEqual(0, Result_.LinkAt(Span.Left + 2, Result_.Lines[1].Top + 2));
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Toggle), Ord(Result_.Links[0].Kind));
  // Ausnahmen in Fehlerfarbe, der Rest gedämpft.
  ErrorSeen := False;
  for Span in Result_.Lines[1].Spans do
    if Span.Color = TAtlasDocColor.Error then
    begin
      Assert.AreEqual('1 Ausnahme', Span.Text);
      ErrorSeen := True;
    end;
  Assert.IsTrue(ErrorSeen);
  Parts := TAtlasDocLayout.HiddenParts(DocOf(Json), TAtlasDocSignature.Parse(Declaration), TAtlasDocLabels.German,
    Colors);
  Assert.AreEqual(5, Integer(Length(Parts)));
  Assert.AreEqual('3 Parameter', Parts[0]);
  Assert.AreEqual(Ord(TAtlasDocColor.Error), Ord(Colors[2]));
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Colors[0]));
  // Ohne erkannte Signatur zählen die <param> der Doku; Einzahl.
  Parts := TAtlasDocLayout.HiddenParts(DocOf(Json), Default(TAtlasDocSignature), TAtlasDocLabels.German, Colors);
  Assert.AreEqual('1 Parameter', Parts[0]);
  Assert.AreEqual('1 Ausnahme', Parts[1]);
  // Aufgeklappt endet mit „Weniger anzeigen“.
  Result_ := LayoutWith(Json, 600, Declaration, True);
  Assert.IsTrue(Result_.Expanded);
  Assert.AreEqual('Weniger anzeigen ▴', LineText(Result_.Lines[High(Result_.Lines)]));
end;

procedure TAtlasDocumentationTests.SummaryOnlyHasNoToggle;
var
  Result_: TAtlasDocLayout;
begin
  // Nur Beschreibung: kein Schalter, auch nicht mit Parametern in der Signatur.
  Result_ := LayoutWith(Summary('Nur das.'), 400, 'procedure P(A, B: Integer);', False);
  Assert.IsFalse(Result_.Collapsible);
  Assert.IsTrue(Result_.Expanded);
  Assert.AreEqual('Nur das.|', Texts(Result_));
  Assert.AreEqual(0, Integer(Length(Result_.Links)));
  Assert.IsFalse(TAtlasDocLayout.IsCollapsible(DocOf(Summary('x'))));
end;

procedure TAtlasDocumentationTests.ParamsInSignatureOrderWithTypes;
var
  Result_: TAtlasDocLayout;
  NameWidth, TypeWidth: Integer;
begin
  Result_ := LayoutWith('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Tut."}]},' +
    '{"kind":"param","name":"C","runs":[{"kind":"text","text":"drittes"}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"erstes"}]},' +
    '{"kind":"param","name":"X","runs":[{"kind":"text","text":"gibt es nicht"}]}]}', 600,
    'function TX.Foo(const A: string; var B, C: Integer; out D): Boolean; overload;', True);
  Assert.AreEqual('Tut.|PARAMETER|Aconst stringerstes|Bvar Integernicht dokumentiert|Cvar Integerdrittes|' +
    'Doutnicht dokumentiert|Xgibt es nicht|RÜCKGABE|Boolean|Weniger anzeigen ▴|', Texts(Result_));
  // Spalten: Name (1 Zeichen), Art und Typ ("const string" = 12 Zeichen), Beschreibung.
  NameWidth := 8;
  TypeWidth := 12 * 8;
  Assert.AreEqual(NameWidth + Metrics.ColumnGap, Result_.Lines[2].Spans[1].Left);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Result_.Lines[2].Spans[1].Color));
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(Result_.Lines[2].Spans[1].Face.Font));
  Assert.AreEqual(NameWidth + TypeWidth + 2 * Metrics.ColumnGap, Result_.Lines[2].Spans[2].Left);
  // Ohne <param>: kursiv und gedämpft.
  Assert.IsTrue(Result_.Lines[3].Spans[2].Face.Italic);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Result_.Lines[3].Spans[2].Color));
  // Unbekannter Parameter am Ende in Warnfarbe.
  Assert.AreEqual(Ord(TAtlasDocColor.Warn), Ord(Result_.Lines[6].Spans[0].Color));
  Assert.AreEqual(Ord(TAtlasDocColor.Warn), Ord(Result_.Lines[6].Spans[1].Color));
  // Rückgabe ohne <returns>: nur der Typ, in Schlüsselwortfarbe.
  Assert.AreEqual(Ord(TAtlasDocColor.Keyword), Ord(Result_.Lines[8].Spans[0].Color));
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(Result_.Lines[8].Spans[0].Face.Font));
  // Mit <returns>: Typ und Text.
  Result_ := LayoutWith('{"sections":[{"kind":"returns","runs":[{"kind":"text","text":"Treffer"}]}]}', 600,
    'function F: Integer;', True);
  Assert.AreEqual('RÜCKGABE|IntegerTreffer|Weniger anzeigen ▴|', Texts(Result_));
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Result_.Lines[1].Spans[1].Color));
end;

procedure TAtlasDocumentationTests.PropertyTypeUnderValue;
var
  Result_: TAtlasDocLayout;
begin
  Result_ := LayoutWith('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Zeilen."}]},' +
    '{"kind":"value","runs":[{"kind":"text","text":"Anzahl"}]}]}', 600,
    'property Items[AIndex: Integer]: TItem read GetItem; default;', True);
  Assert.AreEqual('Zeilen.|PARAMETER|AIndexIntegernicht dokumentiert|WERT|TItemAnzahl|Weniger anzeigen ▴|',
    Texts(Result_));
end;

procedure TAtlasDocumentationTests.ParamRefIsPill;
var
  Result_: TAtlasDocLayout;
  Span: TAtlasDocSpan;
begin
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Setzt "},' +
    '{"kind":"paramref","text":"AValue"},{"kind":"text","text":" neu."}]}]}', 400);
  Span := Result_.Lines[0].Spans[1];
  Assert.AreEqual('AValue', Span.Text);
  Assert.IsTrue(Span.Pill);
  Assert.AreEqual(Metrics.PillPad, Span.Pad);
  Assert.AreEqual(6 * 8 + 2 * Metrics.PillPad, Span.Width);
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(Span.Color));
  Assert.AreEqual(Span.Right, Result_.Lines[0].Spans[2].Left);
  Assert.AreEqual('Setzt AValue neu.', Result_.Text);
  // Markieren rechnet mit dem Innenabstand.
  Assert.AreEqual(6, Result_.PositionAt(Span.Left + 1, 4, Measure));
  Assert.AreEqual(7, Result_.PositionAt(Span.Left + Span.Pad + 5, 4, Measure));
end;

procedure TAtlasDocumentationTests.ParsesSignatures;
var
  Signature: TAtlasDocSignature;
begin
  Signature := TAtlasDocSignature.Parse('class function TList<T>.Find(const AItem: T; [Ref] var AIndex: Integer;' +
    ' AComparer: IComparer<T> = nil; const A, B: TArray<string>): Boolean; overload;');
  Assert.IsTrue(Signature.Known);
  Assert.IsFalse(Signature.IsProperty);
  Assert.AreEqual(5, Integer(Length(Signature.Params)));
  Assert.AreEqual('AItem', Signature.Params[0].Name);
  Assert.AreEqual('const T', Signature.Params[0].TypeText);
  Assert.AreEqual('AIndex', Signature.Params[1].Name);
  Assert.AreEqual('var', Signature.Params[1].Modifier);
  Assert.AreEqual('IComparer<T>', Signature.Params[2].TypeName);
  Assert.AreEqual('B', Signature.Params[4].Name);
  Assert.AreEqual('TArray<string>', Signature.Params[4].TypeName);
  Assert.AreEqual('Boolean', Signature.ResultType);
  Assert.AreEqual(3, Signature.IndexOf('a'));
  Assert.AreEqual(-1, Signature.IndexOf('Z'));
  Assert.IsTrue(Signature.HasTypes);
  Signature := TAtlasDocSignature.Parse('procedure Lauf;');
  Assert.IsTrue(Signature.Known);
  Assert.AreEqual(0, Integer(Length(Signature.Params)));
  Assert.AreEqual('', Signature.ResultType);
  Signature := TAtlasDocSignature.Parse('procedure Untyped(var Buffer; Count: Integer);');
  Assert.AreEqual('var', Signature.Params[0].TypeText);
  Assert.AreEqual('Integer', Signature.Params[1].TypeText);
  Signature := TAtlasDocSignature.Parse('property Caption: string read FCaption write SetCaption;');
  Assert.IsTrue(Signature.IsProperty);
  Assert.AreEqual('string', Signature.ResultType);
  Signature := TAtlasDocSignature.Parse('constructor Create(AOwner: TComponent); override;');
  Assert.AreEqual('AOwner', Signature.Params[0].Name);
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
  Result_: TAtlasDocLayout;
  From, Till: Integer;
begin
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Eins zwei drei vier"}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"Wert"}]}]}', 90);
  Assert.AreEqual('Eins zwei '#13#10'drei vier'#13#10'PARAMETER'#13#10'A'#9'Wert'#13#10'Weniger anzeigen ▴',
    Result_.Text);
  // Von der Mitte von "zwei" (Zeichen 6 = 42 Pixel) bis hinter "drei".
  From := Result_.PositionAt(7 * 5 + 2, 4, Measure);
  Till := Result_.PositionAt(7 * 4 + 1, 16 + 4, Measure);
  Assert.AreEqual('zwei '#13#10'drei', Result_.Selected(From, Till));
  Assert.AreEqual('zwei '#13#10'drei', Result_.Selected(Till, From));
  Assert.AreEqual(0, Result_.PositionAt(50, -5, Measure));
  Assert.AreEqual(Integer(Length(Result_.Text)), Result_.PositionAt(0, 1000, Measure));
  Assert.AreEqual(Result_.Text, Result_.Selected(0, MaxInt));
end;

procedure TAtlasDocumentationTests.LongDocumentIsNotTruncated;
var
  Result_: TAtlasDocLayout;
  Long: string;
  Index: Integer;
begin
  Long := '';
  for Index := 1 to 200 do
    Long := Long + 'Wort ';
  Result_ := Layout(Summary(Long), 140);
  Assert.AreEqual(50, Integer(Length(Result_.Lines)));
  Assert.AreEqual(50 * 16, Result_.Height);
  Assert.AreEqual(10 * 16, Result_.HeightOfLines(10));
  Assert.AreEqual(0, Pos('…', Result_.Text));
end;

procedure TAtlasDocumentationTests.PlainTextOfForeignServers;
var
  Doc: TAtlasDoc;
  Result_: TAtlasDocLayout;
begin
  Doc := TAtlasDoc.FromText('Erste Zeile'#13#10'zweite'#10#10'Absatz'#10'  Code := 1;'#10'  Weiter;'#10);
  Assert.AreEqual(1, Integer(Length(Doc.Sections)));
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Summary), Ord(Doc.Sections[0].Kind));
  Assert.AreEqual(7, Integer(Length(Doc.Sections[0].Runs)));
  Assert.AreEqual(Ord(TAtlasDocRunKind.LineBreak), Ord(Doc.Sections[0].Runs[1].Kind));
  Assert.AreEqual(Ord(TAtlasDocRunKind.Paragraph), Ord(Doc.Sections[0].Runs[3].Kind));
  Assert.AreEqual('  Code := 1;'#10'  Weiter;', Doc.Sections[0].Runs[6].Text);
  Assert.IsTrue(TAtlasDoc.FromText('  ').IsEmpty);
  Result_ := TAtlasDocLayout.Build(Doc, 400, Metrics, Measure, TAtlasDocLabels.German);
  Assert.AreEqual('Erste Zeile'#13#10'zweite'#13#10'Absatz'#13#10'  Code := 1;'#13#10'  Weiter;', Result_.Text);
end;

function Rationale(const AMarker, AText: string): string;
begin
  Result := '{"kind":"rationale","name":"' + AMarker + '","runs":[{"kind":"text","text":"' + AText + '"}]}';
end;

procedure TAtlasDocumentationTests.RationaleBelowDocumentation;
var
  Doc: TAtlasDoc;
  Result_: TAtlasDocLayout;
begin
  Doc := DocOf('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liest."}]},' +
    Rationale('WHY', 'Schnell.') + ',' + Rationale('HACK', 'QC 1.') + ']}');
  Assert.AreEqual(3, Integer(Length(Doc.Sections)));
  Assert.AreEqual(Ord(TAtlasDocSectionKind.Rationale), Ord(Doc.Sections[1].Kind));
  Assert.AreEqual('WHY', Doc.Sections[1].Name);
  Assert.AreEqual(2, Integer(Length(Doc.SectionsOf(TAtlasDocSectionKind.Rationale))));
  // Bis drei Einträge kein Schalter.
  Assert.IsFalse(TAtlasDocLayout.IsCollapsible(Doc));
  Result_ := TAtlasDocLayout.Build(Doc, 600, Metrics, Measure, TAtlasDocLabels.German, Default(TAtlasDocSignature),
    False);
  Assert.AreEqual('Liest.|BEGRÜNDUNG|WHYSchnell.|HACKQC 1.|', Texts(Result_));
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(Result_.Lines[2].Spans[0].Color));
end;

procedure TAtlasDocumentationTests.RationaleBeyondThreeBehindToggle;
const
  Json = '{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liest."}]},';
var
  Doc: TAtlasDoc;
  Result_: TAtlasDocLayout;
begin
  Doc := DocOf(Json + Rationale('WHY', 'A') + ',' + Rationale('WHY', 'B') + ',' + Rationale('NOTE', 'C') + ',' +
    Rationale('HACK', 'D') + ',' + Rationale('HACK', 'E') + ']}');
  Assert.IsTrue(TAtlasDocLayout.IsCollapsible(Doc));
  Result_ := TAtlasDocLayout.Build(Doc, 600, Metrics, Measure, TAtlasDocLabels.German, Default(TAtlasDocSignature),
    False);
  Assert.AreEqual('Liest.|BEGRÜNDUNG|WHYA|WHYB|NOTEC|Mehr anzeigen ▾   2 weitere Begründungen|', Texts(Result_));
  Result_ := TAtlasDocLayout.Build(Doc, 600, Metrics, Measure, TAtlasDocLabels.German, Default(TAtlasDocSignature),
    True);
  Assert.AreEqual('Liest.|BEGRÜNDUNG|WHYA|WHYB|NOTEC|HACKD|HACKE|Weniger anzeigen ▴|', Texts(Result_));
end;

procedure TAtlasDocumentationTests.IssueLinksNeedTracker;
const
  Json = '{"sections":[{"kind":"rationale","name":"WHY","runs":[{"kind":"text","text":"Siehe "},' +
    '{"kind":"link","text":"#312","target":"issue:312"}]}]}';
var
  Result_: TAtlasDocLayout;
begin
  // Ohne Tracker: Text, kein Link.
  Result_ := Layout(Json, 600);
  Assert.AreEqual(0, Integer(Length(Result_.Links)));
  TAtlasDocIssueLinks.SetResolver(
    function(const AKey: string): string
    begin
      Result := 'https://github.com/o/r/issues/' + AKey;
    end);
  Result_ := Layout(Json, 600);
  Assert.AreEqual(1, Integer(Length(Result_.Links)));
  Assert.AreEqual(Ord(TAtlasDocLinkKind.Url), Ord(Result_.Links[0].Kind));
  Assert.AreEqual('https://github.com/o/r/issues/312', Result_.Links[0].Url);
  // Nur Web-Adressen.
  TAtlasDocIssueLinks.SetResolver(
    function(const AKey: string): string
    begin
      Result := 'file:///C:/x';
    end);
  Assert.AreEqual(0, Integer(Length(Layout(Json, 600).Links)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDocumentationTests);

end.
