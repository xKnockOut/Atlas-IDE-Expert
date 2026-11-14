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
  System.Generics.Collections,
  Atlas.Core.Editor.Recursion,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Settings.Plugin;

const
  cAnswer = '{"calls": [' +
    '{"line": 4, "character": 20, "endCharacter": 27, "text": "Speichern → Pruefen → Speichern", "chain": [' +
    '{"name": "TFoo.Speichern", "line": 2, "character": 15}, {"name": "TFoo.Pruefen", "line": 7, "character": 15},' +
    '{"name": "TFoo.Speichern", "line": 2, "character": 15}]},' +
    '{"line": 4, "character": 2, "endCharacter": 5, "text": "Speichern → Speichern", "chain": [' +
    '{"name": "TFoo.Speichern", "line": 2, "character": 15}, {"name": "TFoo.Speichern", "line": 2, "character": 15}]},' +
    '{"line": 9, "character": 4, "endCharacter": 13, "text": "Pruefen → Speichern → Pruefen", "chain": []}]}';

function Parsed(const AJson: string): TAtlasFileRecursion;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasFileRecursion.FromJson(mValue);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasRecursionMarksTests.ReadsServerAnswer;
var
  mMarks: TAtlasFileRecursion;
begin
  mMarks := Parsed(cAnswer);
  Assert.AreEqual(3, Integer(Length(mMarks.Calls)));
  Assert.IsTrue(mMarks.HasCalls);
  Assert.AreEqual(4, mMarks.Calls[0].Line);
  Assert.AreEqual(20, mMarks.Calls[0].Character);
  Assert.AreEqual(27, mMarks.Calls[0].EndCharacter);
  Assert.AreEqual(3, Integer(Length(mMarks.Calls[0].Chain)));
  Assert.AreEqual('TFoo.Pruefen', mMarks.Calls[0].Chain[1].Name);
  Assert.AreEqual(7, mMarks.Calls[0].Chain[1].Line);
  Assert.AreEqual(2, mMarks.Calls[0].Methods);
  Assert.AreEqual(1, mMarks.Calls[1].Methods, 'direkte Rekursion');
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
  mCalls: TArray<TAtlasRecursionCall>;
begin
  mCalls := Parsed(cAnswer).CallsAt(4);
  Assert.AreEqual(2, Integer(Length(mCalls)));
  Assert.AreEqual(2, mCalls[0].Character);
  Assert.AreEqual(20, mCalls[1].Character);
  Assert.AreEqual(0, Integer(Length(Parsed(cAnswer).CallsAt(5))));
end;

procedure TAtlasRecursionMarksTests.LineOfAndLineMatches;
const
  cText = 'unit U;'#13#10'begin'#13#10'  A;  '#10'end.';
begin
  Assert.AreEqual('unit U;', TAtlasRecursionMarks.LineOf(cText, 0));
  Assert.AreEqual('  A;  ', TAtlasRecursionMarks.LineOf(cText, 2));
  Assert.AreEqual('end.', TAtlasRecursionMarks.LineOf(cText, 3));
  Assert.AreEqual('', TAtlasRecursionMarks.LineOf(cText, 9));
  Assert.AreEqual('', TAtlasRecursionMarks.LineOf(cText, -1));
  Assert.IsTrue(TAtlasRecursionMarks.LineMatches('  A;', '  A;  '), 'Leerraum am Ende zählt nicht');
  Assert.IsFalse(TAtlasRecursionMarks.LineMatches('  B;', '  A;'));
end;

procedure TAtlasRecursionMarksTests.TipTextAndLinks;
var
  mTitle, mText: string;
  mLinks: TArray<TAtlasRecursionStep>;
begin
  TAtlasRecursionMarks.TipText(Parsed(cAnswer).CallsAt(4), 'Direkt', 'Über %d', mTitle, mText);
  Assert.AreEqual('Über 2', mTitle, 'die längste Kette der Zeile');
  Assert.AreEqual('Speichern → Speichern'#10'Speichern → Pruefen → Speichern', mText);
  mLinks := TAtlasRecursionMarks.Links(Parsed(cAnswer).CallsAt(4));
  Assert.AreEqual(2, Integer(Length(mLinks)), 'jede Methode einmal');
  Assert.AreEqual('TFoo.Speichern', mLinks[0].Name);
  Assert.AreEqual('TFoo.Pruefen', mLinks[1].Name);
  TAtlasRecursionMarks.TipText(nil, 'Direkt', 'Über %d', mTitle, mText);
  Assert.AreEqual('', mTitle);
end;

procedure TAtlasRecursionMarksTests.SettingsDefaultsAndRange;
var
  mSettings: TAtlasPluginSettings;
  mElement: TAtlasDrawnElement;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.RecursionMarkers, 'editor.recursionMarkers standardmäßig an');
  Assert.AreEqual(4, mSettings.RecursionMarkersDepth);
  mSettings.RecursionMarkersDepth := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinRecursionDepth, mSettings.RecursionMarkersDepth);
  mSettings.RecursionMarkersDepth := 99;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxRecursionDepth, mSettings.RecursionMarkersDepth);
  Assert.IsTrue(TAtlasDrawnElements.ForSetting('RecursionMarkers', mElement));
  Assert.AreEqual<TAtlasDrawnElement>(TAtlasDrawnElement.Recursion, mElement);
  Assert.IsTrue(TAtlasDrawnElements.Info(mElement).Gutter);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRecursionMarksTests);

end.
