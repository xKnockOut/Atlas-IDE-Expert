unit Atlas.Core.Editor.Recursion.Tests;

// Tests der Rekursionssymbole im Plugin (#623): Antwort von
// atlas.server.recursion lesen, Aufrufe je Zeile, Zeilentext, Tooltip,
// Links und die Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasRecursionMarksTests = class
  public
    [Test]
    procedure ReadsServerAnswer;
    [Test]
    procedure IgnoresUnknownFormat;
    [Test]
    procedure CallsAtLineFromLeftToRight;
    [Test]
    procedure LineOfAndLineMatches;
    [Test]
    procedure TipTextAndLinks;
    [Test]
    procedure SettingsDefaultsAndRange;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.Recursion,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Settings.Plugin;

const
  Answer = '{"calls": [' +
    '{"line": 4, "character": 20, "endCharacter": 27, "text": "Speichern → Pruefen → Speichern", "chain": [' +
    '{"name": "TFoo.Speichern", "line": 2, "character": 15}, {"name": "TFoo.Pruefen", "line": 7, "character": 15},' +
    '{"name": "TFoo.Speichern", "line": 2, "character": 15}]},' +
    '{"line": 4, "character": 2, "endCharacter": 5, "text": "Speichern → Speichern", "chain": [' +
    '{"name": "TFoo.Speichern", "line": 2, "character": 15}, {"name": "TFoo.Speichern", "line": 2, "character": 15}]},' +
    '{"line": 9, "character": 4, "endCharacter": 13, "text": "Pruefen → Speichern → Pruefen", "chain": []}]}';

function Parsed(const AJson: string): TAtlasFileRecursion;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasFileRecursion.FromJson(Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasRecursionMarksTests.ReadsServerAnswer;
var
  Marks: TAtlasFileRecursion;
begin
  Marks := Parsed(Answer);
  Assert.AreEqual(3, Integer(Length(Marks.Calls)));
  Assert.IsTrue(Marks.HasCalls);
  Assert.AreEqual(4, Marks.Calls[0].Line);
  Assert.AreEqual(20, Marks.Calls[0].Character);
  Assert.AreEqual(27, Marks.Calls[0].EndCharacter);
  Assert.AreEqual(3, Integer(Length(Marks.Calls[0].Chain)));
  Assert.AreEqual('TFoo.Pruefen', Marks.Calls[0].Chain[1].Name);
  Assert.AreEqual(7, Marks.Calls[0].Chain[1].Line);
  Assert.AreEqual(2, Marks.Calls[0].Methods);
  Assert.AreEqual(1, Marks.Calls[1].Methods, 'direkte Rekursion');
end;

procedure TAtlasRecursionMarksTests.IgnoresUnknownFormat;
begin
  Assert.IsFalse(Parsed('[]').HasCalls);
  Assert.IsFalse(Parsed('{"calls": 3}').HasCalls);
  Assert.IsFalse(Parsed('{"calls": [{"character": 1}, 5]}').HasCalls, 'ohne Zeile');
  Assert.IsFalse(TAtlasFileRecursion.FromJson(nil).HasCalls);
end;

procedure TAtlasRecursionMarksTests.CallsAtLineFromLeftToRight;
var
  Calls: TArray<TAtlasRecursionCall>;
begin
  Calls := Parsed(Answer).CallsAt(4);
  Assert.AreEqual(2, Integer(Length(Calls)));
  Assert.AreEqual(2, Calls[0].Character);
  Assert.AreEqual(20, Calls[1].Character);
  Assert.AreEqual(0, Integer(Length(Parsed(Answer).CallsAt(5))));
end;

procedure TAtlasRecursionMarksTests.LineOfAndLineMatches;
const
  Text = 'unit U;'#13#10'begin'#13#10'  A;  '#10'end.';
begin
  Assert.AreEqual('unit U;', TAtlasRecursionMarks.LineOf(Text, 0));
  Assert.AreEqual('  A;  ', TAtlasRecursionMarks.LineOf(Text, 2));
  Assert.AreEqual('end.', TAtlasRecursionMarks.LineOf(Text, 3));
  Assert.AreEqual('', TAtlasRecursionMarks.LineOf(Text, 9));
  Assert.AreEqual('', TAtlasRecursionMarks.LineOf(Text, -1));
  Assert.IsTrue(TAtlasRecursionMarks.LineMatches('  A;', '  A;  '), 'Leerraum am Ende zählt nicht');
  Assert.IsFalse(TAtlasRecursionMarks.LineMatches('  B;', '  A;'));
end;

procedure TAtlasRecursionMarksTests.TipTextAndLinks;
var
  Title, Text: string;
  Links: TArray<TAtlasRecursionStep>;
begin
  TAtlasRecursionMarks.TipText(Parsed(Answer).CallsAt(4), 'Direkt', 'Über %d', Title, Text);
  Assert.AreEqual('Über 2', Title, 'die längste Kette der Zeile');
  Assert.AreEqual('Speichern → Speichern'#10'Speichern → Pruefen → Speichern', Text);
  Links := TAtlasRecursionMarks.Links(Parsed(Answer).CallsAt(4));
  Assert.AreEqual(2, Integer(Length(Links)), 'jede Methode einmal');
  Assert.AreEqual('TFoo.Speichern', Links[0].Name);
  Assert.AreEqual('TFoo.Pruefen', Links[1].Name);
  TAtlasRecursionMarks.TipText(nil, 'Direkt', 'Über %d', Title, Text);
  Assert.AreEqual('', Title);
end;

procedure TAtlasRecursionMarksTests.SettingsDefaultsAndRange;
var
  Settings: TAtlasPluginSettings;
  Element: TAtlasDrawnElement;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.RecursionMarkers, 'editor.recursionMarkers standardmäßig an');
  Assert.AreEqual(4, Settings.RecursionMarkersDepth);
  Settings.RecursionMarkersDepth := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinRecursionDepth, Settings.RecursionMarkersDepth);
  Settings.RecursionMarkersDepth := 99;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxRecursionDepth, Settings.RecursionMarkersDepth);
  Assert.IsTrue(TAtlasDrawnElements.ForSetting('RecursionMarkers', Element));
  Assert.IsTrue(Element = TAtlasDrawnElement.Recursion);
  Assert.IsTrue(TAtlasDrawnElements.Info(Element).Gutter);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRecursionMarksTests);

end.
