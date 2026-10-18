unit Atlas.Core.Documentation.Tests;

// Tests für die strukturierte XMLDoc im Plugin (#654): Lesen der Server-Antwort
// und Satz für Tooltip und Detailpanel. Gemessen wird mit fester Zeichenbreite
// (UI 7, Editorschrift 8 Pixel), damit die Positionen vorhersagbar sind.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Documentation.Layout;

type
  [TestFixture]
  TAtlasDocumentationTests = class
  private
    function Layout(const AJson: string; AWidth: Integer; AFull: Boolean = True): TAtlasDocLayout;
  public
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
    procedure ShortFormLimitsSummaryAndRemarks;
    [Test]
    procedure SelectionCopiesText;
    [Test]
    procedure LongDocumentIsNotTruncated;
    [Test]
    procedure PlainTextOfForeignServers;
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

function TAtlasDocumentationTests.Layout(const AJson: string; AWidth: Integer; AFull: Boolean): TAtlasDocLayout;
begin
  Result := TAtlasDocLayout.Build(DocOf(AJson), AWidth, Metrics, Measure, TAtlasDocLabels.German, AFull);
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
  Fallback := TAtlasDocDisplay.Create(True, 70);
  Assert.AreEqual(TAtlasDocDisplay.MaxMaxLines, Fallback.MaxLines);
  Display := TAtlasDocDisplay.FromJson(nil, TAtlasDocDisplay.Create(False, 5));
  Assert.IsFalse(Display.Known);
  Assert.IsFalse(Display.Full);
  Assert.AreEqual(5, Display.MaxLines);
  Value := TJSONObject.ParseJSONValue('{"full":true,"maxLines":12}');
  try
    Display := TAtlasDocDisplay.FromJson(Value, TAtlasDocDisplay.Create(False, 5));
  finally
    Value.Free;
  end;
  Assert.IsTrue(Display.Known);
  Assert.IsTrue(Display.Full);
  Assert.AreEqual(12, Display.MaxLines);
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
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Tut."}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"erster Wert"}]},' +
    '{"kind":"param","name":"ALangerName","runs":[{"kind":"text","text":"zweiter Wert mit viel Text dazu"}]},' +
    '{"kind":"returns","runs":[{"kind":"text","text":"Summe"}]}]}', 300);
  // Namensspalte: "ALangerName" = 88 Pixel (< 300 / 3), dazu der Abstand.
  Column := 88 + Metrics.ColumnGap;
  Assert.AreEqual('A', Result_.Lines[1].Spans[0].Text);
  Assert.AreEqual(Ord(TAtlasDocColor.Accent), Ord(Result_.Lines[1].Spans[0].Color));
  Assert.IsTrue(Result_.Lines[1].Spans[0].Face.Bold);
  Assert.AreEqual(Column, Result_.Lines[1].Spans[1].Left);
  Assert.AreEqual(Ord(TAtlasDocColor.Muted), Ord(Result_.Lines[1].Spans[1].Color));
  Assert.AreEqual(Column, Result_.Lines[2].Spans[1].Left);
  // Fortsetzungszeile bleibt in der Textspalte.
  Assert.AreEqual(Column, Result_.Lines[3].Spans[0].Left);
  Assert.AreEqual('→', Result_.Lines[High(Result_.Lines)].Spans[0].Text);
  // Sehr lange Namen: Spalte höchstens ein Drittel, Text dann in der nächsten Zeile.
  Result_ := Layout('{"sections":[{"kind":"param","name":"AEinSehrSehrLangerName","runs":' +
    '[{"kind":"text","text":"Text"}]}]}', 150);
  Assert.AreEqual(2, Integer(Length(Result_.Lines)));
  Assert.AreEqual(50 + Metrics.ColumnGap, Result_.Lines[1].Spans[0].Left);
end;

procedure TAtlasDocumentationTests.ExceptionClassIsClickable;
var
  Result_: TAtlasDocLayout;
  Span: TAtlasDocSpan;
begin
  Result_ := Layout('{"sections":[{"kind":"exception","name":"EZeichnen","ref":{"name":"EZeichnen",' +
    '"file":"C:\\U.pas","line":3,"character":2},"runs":[{"kind":"text","text":"bei Fehlern"}]},' +
    '{"kind":"exception","name":"EFremd","runs":[{"kind":"text","text":"unbekannt"}]}]}', 400);
  Span := Result_.Lines[0].Spans[0];
  Assert.AreEqual('! EZeichnen', Span.Text);
  Assert.AreEqual(Ord(TAtlasDocColor.Error), Ord(Span.Color));
  Assert.AreEqual(0, Result_.LinkAt(Span.Left + 3, Result_.Lines[0].Top + 2));
  Assert.AreEqual('EZeichnen', Result_.Links[0].Target.Name);
  Assert.AreEqual(1, Integer(Length(Result_.Links)));
  Assert.AreEqual(-1, Result_.Lines[1].Spans[0].Link);
end;

procedure TAtlasDocumentationTests.CodeBlockKeepsIndentAndColors;
var
  Result_: TAtlasDocLayout;
  First: Integer;
begin
  Result_ := Layout('{"sections":[{"kind":"example","runs":[{"kind":"text","text":"So:"},' +
    '{"kind":"codeblock","text":"begin\n  X := ''a'';\nend;"}]}]}', 400);
  // Beispiel, "So:", drei Codezeilen.
  Assert.AreEqual(5, Integer(Length(Result_.Lines)));
  Assert.AreEqual('Beispiel', LineText(Result_.Lines[0]));
  First := 2;
  Assert.AreEqual('begin', LineText(Result_.Lines[First]));
  Assert.AreEqual(Ord(TAtlasDocColor.Keyword), Ord(Result_.Lines[First].Spans[0].Color));
  Assert.AreEqual(Ord(TAtlasDocFont.Mono), Ord(Result_.Lines[First].Spans[0].Face.Font));
  Assert.AreEqual('  X := ''a'';', LineText(Result_.Lines[First + 1]));
  Assert.AreEqual(Ord(TAtlasDocColor.StringLiteral), Ord(Result_.Lines[First + 1].Spans[1].Color));
  Assert.AreEqual(17, Result_.Lines[First].Height);
  Assert.IsTrue(Result_.Lines[First].GapBefore > 0);
  // Zu lange Codezeilen brechen an Zeichen um, eingerückt.
  Result_ := Layout('{"sections":[{"kind":"example","runs":[{"kind":"codeblock","text":"' +
    'WriteLn(Eins, Zwei, Drei);"}]}]}', 100);
  Assert.IsTrue(Length(Result_.Lines) >= 4);
  Assert.AreEqual(Metrics.Indent, Result_.Lines[2].Spans[0].Left);
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
  Texts: string;
  Line: TAtlasDocLine;
  Separators: Integer;
begin
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Liste."}]},' +
    '{"kind":"typeparam","name":"T","runs":[{"kind":"text","text":"Element"}]},' +
    '{"kind":"value","runs":[{"kind":"text","text":"Anzahl"}]},' +
    '{"kind":"remarks","runs":[{"kind":"text","text":"Bemerkung"}]},' +
    '{"kind":"example","runs":[{"kind":"codeblock","text":"L.Add(1);"}]},' +
    '{"kind":"seealso","runs":[{"kind":"ref","text":"TList","target":"TList"}]}]}', 400);
  Texts := '';
  Separators := 0;
  for Line in Result_.Lines do
    if Line.Kind = TAtlasDocLineKind.Separator then
      Inc(Separators)
    else
      Texts := Texts + LineText(Line) + '|';
  Assert.AreEqual('Liste.|Typparameter|TElement|WertAnzahl|Bemerkung|Beispiel|L.Add(1);|Siehe auch: TList|', Texts);
  Assert.AreEqual(1, Separators);
end;

procedure TAtlasDocumentationTests.ShortFormLimitsSummaryAndRemarks;
var
  Result_: TAtlasDocLayout;
  Long: string;
  Index: Integer;
begin
  Long := '';
  for Index := 1 to 20 do
    Long := Long + 'Wort' + IntToStr(Index) + ' ';
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"' + Long + '"}]},' +
    '{"kind":"remarks","runs":[{"kind":"text","text":"' + Long + '"}]},' +
    '{"kind":"example","runs":[{"kind":"text","text":"Beispieltext"}]}]}', 100, False);
  Assert.IsTrue(Result_.Shortened);
  // Vier Zeilen Beschreibung, Linie, drei Zeilen Bemerkungen; kein Beispiel.
  Assert.AreEqual(8, Integer(Length(Result_.Lines)));
  Assert.IsTrue(LineText(Result_.Lines[3]).EndsWith(TAtlasDocLayout.Ellipsis));
  Assert.IsTrue(LineText(Result_.Lines[7]).EndsWith(TAtlasDocLayout.Ellipsis));
  Assert.IsTrue(Result_.Lines[3].Spans[High(Result_.Lines[3].Spans)].Right <= 100);
  Assert.AreEqual(0, Pos('Beispiel', Result_.Text));
  // Volle Anzeige: alles.
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"' + Long + '"}]}]}', 100);
  Assert.IsFalse(Result_.Shortened);
  Assert.AreEqual(Trim(Long), Trim(StringReplace(Result_.Text, #13#10, '', [rfReplaceAll])));
end;

procedure TAtlasDocumentationTests.SelectionCopiesText;
var
  Result_: TAtlasDocLayout;
  From, Till: Integer;
begin
  Result_ := Layout('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Eins zwei drei vier"}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"Wert"}]}]}', 90);
  Assert.AreEqual('Eins zwei '#13#10'drei vier'#13#10'A'#9'Wert', Result_.Text);
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
  Assert.AreEqual(0, Pos(TAtlasDocLayout.Ellipsis, Result_.Text));
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
  Result_ := TAtlasDocLayout.Build(Doc, 400, Metrics, Measure, TAtlasDocLabels.German, True);
  Assert.AreEqual('Erste Zeile'#13#10'zweite'#13#10'Absatz'#13#10'  Code := 1;'#13#10'  Weiter;', Result_.Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDocumentationTests);

end.
