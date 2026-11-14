unit Atlas.Core.Editor.Reassigned.Tests;

// Tests der Unterstreichung neu zugewiesener Variablen im Plugin (#712):
// Antwort von atlas.server.reassigned lesen, Stellen je Zeile, Argumente,
// Strecken je Linienart und die Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasReassignedTests = class
  public
    [Test]
    procedure ReadsServerAnswer;
    [Test]
    procedure IgnoresUnknownFormat;
    [Test]
    procedure BuildsArguments;
    [Test]
    procedure RangeAroundVisibleLines;
    [Test]
    procedure SegmentsPerStyle;
    [Test]
    procedure TargetNamesAndColor;
    [Test]
    procedure SettingsDefaultsAndElement;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.Reassigned,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Reassigned,
  Atlas.Core.Style.Color;

const
  Answer = '{"symbols": [' +
    '{"name": "Summe", "kind": "local", "writes": 3, "routine": "TFoo.Rechne", "writeLines": [4, 6, 8],' +
    ' "uses": [{"line": 6, "character": 4, "endCharacter": 9, "write": true},' +
    ' {"line": 4, "character": 2, "endCharacter": 7, "write": true},' +
    ' {"line": 9, "character": 12, "endCharacter": 17, "write": false},' +
    ' {"line": 9, "character": 3, "endCharacter": 3, "write": false}]},' +
    '{"name": "A", "kind": "valueParameter", "writes": 2, "routine": "TFoo.Rechne",' +
    ' "uses": [{"line": 9, "character": 2, "endCharacter": 3, "write": true}]},' +
    '5]}';

function Parsed(const AJson: string): TAtlasReassignedSet;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasReassignedSet.FromJson(Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasReassignedTests.ReadsServerAnswer;
var
  Found: TAtlasReassignedSet;
  Line: TArray<TAtlasReassignedUse>;
begin
  Found := Parsed(Answer);
  Assert.IsTrue(Found.Valid);
  Assert.IsTrue(Found.HasUses);
  Assert.AreEqual(2, Integer(Length(Found.Symbols)));
  Assert.AreEqual('Summe', Found.Symbols[0].Name);
  Assert.AreEqual('local', Found.Symbols[0].Kind);
  Assert.AreEqual(3, Found.Symbols[0].Writes);
  Assert.AreEqual('TFoo.Rechne', Found.Symbols[0].Routine);
  Assert.AreEqual(1, Integer(Length(Found.UsesAt(4))));
  Assert.IsTrue(Found.UsesAt(4)[0].Write);
  Assert.AreEqual(0, Integer(Length(Found.UsesAt(5))));
  Assert.AreEqual(0, Integer(Length(Found.UsesAt(-1))));
  Assert.AreEqual(0, Integer(Length(Found.UsesAt(100))));
  // Leere Strecken fallen weg, die Zeile ist nach Zeichen sortiert.
  Line := Found.UsesAt(9);
  Assert.AreEqual(2, Integer(Length(Line)));
  Assert.AreEqual(2, Line[0].Character);
  Assert.AreEqual(1, Line[0].Symbol);
  Assert.AreEqual(12, Line[1].Character);
  Assert.AreEqual(0, Line[1].Symbol);
  Assert.IsFalse(Line[1].Write);
end;

procedure TAtlasReassignedTests.IgnoresUnknownFormat;
var
  Found: TAtlasReassignedSet;
begin
  Found := Parsed('[1, 2]');
  Assert.IsFalse(Found.Valid);
  Found := Parsed('{"symbols": 5}');
  Assert.IsFalse(Found.Valid);
  Found := TAtlasReassignedSet.FromJson(nil);
  Assert.IsFalse(Found.Valid);
  Assert.IsFalse(Found.HasUses);
  // Gültig, aber ohne Namen.
  Found := Parsed('{"symbols": []}');
  Assert.IsTrue(Found.Valid);
  Assert.IsFalse(Found.HasUses);
end;

procedure TAtlasReassignedTests.BuildsArguments;
var
  Range: TAtlasReassignedRange;
begin
  Assert.AreEqual('["file:///a.pas",{"targets":["locals","fields"]}]',
    TAtlasReassigned.Arguments('file:///a.pas', [TAtlasReassignedTarget.Fields, TAtlasReassignedTarget.Locals]));
  Assert.AreEqual('["u",{"targets":[]}]', TAtlasReassigned.Arguments('u', []));
  Range.First := 10;
  Range.Last := 70;
  Assert.AreEqual('["u",{"targets":["locals"],"range":{"start":10,"end":70}}]',
    TAtlasReassigned.Arguments('u', [TAtlasReassignedTarget.Locals], Range));
  Assert.AreEqual('["u",{"targets":["locals"]}]',
    TAtlasReassigned.Arguments('u', [TAtlasReassignedTarget.Locals], TAtlasReassignedRange.Whole));
end;

procedure TAtlasReassignedTests.RangeAroundVisibleLines;
var
  Range: TAtlasReassignedRange;
begin
  // 30 sichtbare Zeilen ab 100: je 30 Zeilen Rand.
  Range := TAtlasReassignedRange.Around(100, 129);
  Assert.AreEqual(70, Range.First);
  Assert.AreEqual(159, Range.Last);
  Assert.IsTrue(Range.Contains(100, 129));
  Assert.IsTrue(Range.Contains(70, 99));
  Assert.IsFalse(Range.Contains(60, 89));
  Assert.IsFalse(Range.Contains(140, 169));
  // Am Anfang der Datei kein Rand unter null.
  Range := TAtlasReassignedRange.Around(0, 39);
  Assert.AreEqual(0, Range.First);
  Assert.AreEqual(79, Range.Last);
  Assert.IsTrue(TAtlasReassignedRange.Whole.Contains(5000, 6000));
end;

procedure TAtlasReassignedTests.SegmentsPerStyle;
var
  Parts: TArray<TAtlasUnderlineSegment>;
begin
  Parts := TAtlasReassigned.Segments(TAtlasReassignedStyle.Solid, 10, 30, 20, 1);
  Assert.AreEqual(1, Integer(Length(Parts)));
  Assert.AreEqual(10, Parts[0].X1);
  Assert.AreEqual(30, Parts[0].X2);
  Assert.AreEqual(20, Parts[0].Y1);
  Assert.AreEqual(20, Parts[0].Y2);
  // Punkte: 1 an, 1 aus.
  Parts := TAtlasReassigned.Segments(TAtlasReassignedStyle.Dotted, 10, 15, 20, 1);
  Assert.AreEqual(3, Integer(Length(Parts)));
  Assert.AreEqual(12, Parts[1].X1);
  Assert.AreEqual(13, Parts[1].X2);
  Assert.AreEqual(15, Parts[2].X2, 'am Ende begrenzt');
  // Mit der Skalierung wachsen die Punkte.
  Parts := TAtlasReassigned.Segments(TAtlasReassignedStyle.Dotted, 0, 8, 20, 2);
  Assert.AreEqual(2, Integer(Length(Parts)));
  Assert.AreEqual(4, Parts[1].X1);
  Assert.AreEqual(6, Parts[1].X2);
  // Welle: abwechselnd hoch und runter, letzte Strecke am Ende begrenzt.
  Parts := TAtlasReassigned.Segments(TAtlasReassignedStyle.Wavy, 0, 5, 20, 1);
  Assert.AreEqual(3, Integer(Length(Parts)));
  Assert.AreEqual(19, Parts[0].Y2);
  Assert.AreEqual(19, Parts[1].Y1);
  Assert.AreEqual(20, Parts[1].Y2);
  Assert.AreEqual(5, Parts[2].X2);
  // Leere Breite und Einheit 0.
  Assert.AreEqual(0, Integer(Length(TAtlasReassigned.Segments(TAtlasReassignedStyle.Solid, 5, 5, 20, 1))));
  Assert.AreEqual(2, Integer(Length(TAtlasReassigned.Segments(TAtlasReassignedStyle.Dotted, 0, 4, 20, 0))));
end;

procedure TAtlasReassignedTests.TargetNamesAndColor;
var
  Target: TAtlasReassignedTarget;
  Color: TAtlasColor;
begin
  Assert.AreEqual('locals,valueParams', TAtlasReassignedNames.TargetsText(TAtlasReassignedNames.cDefaultTargets));
  Assert.AreEqual('loopVars,fields', TAtlasReassignedNames.NormalizeTargets(' Fields; loopvars, unbekannt,fields'));
  Assert.AreEqual('', TAtlasReassignedNames.NormalizeTargets(''));
  Assert.IsTrue(TAtlasReassignedNames.TryTarget('VARPARAMS', Target));
  Assert.AreEqual<TAtlasReassignedTarget>(TAtlasReassignedTarget.VarParams, Target);
  Assert.IsFalse(TAtlasReassignedNames.TryTarget('globals', Target));
  Assert.AreEqual<TAtlasReassignedStyle>(TAtlasReassignedStyle.Wavy, TAtlasReassignedNames.StyleOf('Wavy'));
  Assert.AreEqual<TAtlasReassignedStyle>(TAtlasReassignedStyle.Dotted, TAtlasReassignedNames.StyleOf('dashed'));
  Assert.IsTrue(TAtlasReassignedNames.TryColor('#102030', Color));
  Assert.AreEqual('#102030', TAtlasColorMath.ToHex(Color));
  Assert.IsFalse(TAtlasReassignedNames.TryColor('theme', Color));
  Assert.IsFalse(TAtlasReassignedNames.TryColor('#12345', Color));
  Assert.IsFalse(TAtlasReassignedNames.TryColor('#GG0000', Color));
  Assert.AreEqual('#ABCDEF', TAtlasReassignedNames.NormalizeColor(' #abcdef '));
  Assert.AreEqual('theme', TAtlasReassignedNames.NormalizeColor('blau'));
end;

procedure TAtlasReassignedTests.SettingsDefaultsAndElement;
var
  Settings: TAtlasPluginSettings;
  Element: TAtlasDrawnElement;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Reassigned, 'highlight.reassigned standardmaessig an');
  Assert.AreEqual('locals,valueParams', Settings.ReassignedTargets);
  Assert.AreEqual('dotted', Settings.ReassignedStyle);
  Assert.AreEqual('theme', Settings.ReassignedColor);
  Settings.ReassignedTargets := 'fields,bogus';
  Settings.ReassignedStyle := 'zickzack';
  Settings.ReassignedColor := '#zz';
  Settings.Normalize;
  Assert.AreEqual('fields', Settings.ReassignedTargets);
  Assert.AreEqual('dotted', Settings.ReassignedStyle);
  Assert.AreEqual('theme', Settings.ReassignedColor);
  Assert.IsTrue(TAtlasDrawnElements.ForSetting('Reassigned', Element));
  Assert.AreEqual<TAtlasDrawnElement>(TAtlasDrawnElement.Reassigned, Element);
  Assert.IsTrue(TAtlasDrawnElements.Info(Element).Overlay);
  Assert.IsFalse(TAtlasDrawnElements.Info(Element).Gutter);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasReassignedTests);

end.
