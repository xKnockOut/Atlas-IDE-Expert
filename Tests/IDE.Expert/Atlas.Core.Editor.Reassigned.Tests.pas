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
  cAnswer = '{"symbols": [' +
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
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasReassignedSet.FromJson(mValue);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasReassignedTests.ReadsServerAnswer;
var
  mFound: TAtlasReassignedSet;
  mLine: TArray<TAtlasReassignedUse>;
begin
  mFound := Parsed(cAnswer);
  Assert.IsTrue(mFound.Valid);
  Assert.IsTrue(mFound.HasUses);
  Assert.AreEqual(2, Integer(Length(mFound.Symbols)));
  Assert.AreEqual('Summe', mFound.Symbols[0].Name);
  Assert.AreEqual('local', mFound.Symbols[0].Kind);
  Assert.AreEqual(3, mFound.Symbols[0].Writes);
  Assert.AreEqual('TFoo.Rechne', mFound.Symbols[0].Routine);
  Assert.AreEqual(1, Integer(Length(mFound.UsesAt(4))));
  Assert.IsTrue(mFound.UsesAt(4)[0].Write);
  Assert.AreEqual(0, Integer(Length(mFound.UsesAt(5))));
  Assert.AreEqual(0, Integer(Length(mFound.UsesAt(-1))));
  Assert.AreEqual(0, Integer(Length(mFound.UsesAt(100))));
  // Leere Strecken fallen weg, die Zeile ist nach Zeichen sortiert.
  mLine := mFound.UsesAt(9);
  Assert.AreEqual(2, Integer(Length(mLine)));
  Assert.AreEqual(2, mLine[0].Character);
  Assert.AreEqual(1, mLine[0].Symbol);
  Assert.AreEqual(12, mLine[1].Character);
  Assert.AreEqual(0, mLine[1].Symbol);
  Assert.IsFalse(mLine[1].Write);
end;

procedure TAtlasReassignedTests.IgnoresUnknownFormat;
var
  mFound: TAtlasReassignedSet;
begin
  mFound := Parsed('[1, 2]');
  Assert.IsFalse(mFound.Valid);
  mFound := Parsed('{"symbols": 5}');
  Assert.IsFalse(mFound.Valid);
  mFound := TAtlasReassignedSet.FromJson(nil);
  Assert.IsFalse(mFound.Valid);
  Assert.IsFalse(mFound.HasUses);
  // Gültig, aber ohne Namen.
  mFound := Parsed('{"symbols": []}');
  Assert.IsTrue(mFound.Valid);
  Assert.IsFalse(mFound.HasUses);
end;

procedure TAtlasReassignedTests.BuildsArguments;
var
  mRange: TAtlasReassignedRange;
begin
  Assert.AreEqual('["file:///a.pas",{"targets":["locals","fields"]}]',
    TAtlasReassigned.Arguments('file:///a.pas', [TAtlasReassignedTarget.Fields, TAtlasReassignedTarget.Locals]));
  Assert.AreEqual('["u",{"targets":[]}]', TAtlasReassigned.Arguments('u', []));
  mRange.First := 10;
  mRange.Last := 70;
  Assert.AreEqual('["u",{"targets":["locals"],"range":{"start":10,"end":70}}]',
    TAtlasReassigned.Arguments('u', [TAtlasReassignedTarget.Locals], mRange));
  Assert.AreEqual('["u",{"targets":["locals"]}]',
    TAtlasReassigned.Arguments('u', [TAtlasReassignedTarget.Locals], TAtlasReassignedRange.Whole));
end;

procedure TAtlasReassignedTests.RangeAroundVisibleLines;
var
  mRange: TAtlasReassignedRange;
begin
  // 30 sichtbare Zeilen ab 100: je 30 Zeilen Rand.
  mRange := TAtlasReassignedRange.Around(100, 129);
  Assert.AreEqual(70, mRange.First);
  Assert.AreEqual(159, mRange.Last);
  Assert.IsTrue(mRange.Contains(100, 129));
  Assert.IsTrue(mRange.Contains(70, 99));
  Assert.IsFalse(mRange.Contains(60, 89));
  Assert.IsFalse(mRange.Contains(140, 169));
  // Am Anfang der Datei kein Rand unter null.
  mRange := TAtlasReassignedRange.Around(0, 39);
  Assert.AreEqual(0, mRange.First);
  Assert.AreEqual(79, mRange.Last);
  Assert.IsTrue(TAtlasReassignedRange.Whole.Contains(5000, 6000));
end;

procedure TAtlasReassignedTests.SegmentsPerStyle;
var
  mParts: TArray<TAtlasUnderlineSegment>;
begin
  mParts := TAtlasReassigned.Segments(TAtlasReassignedStyle.Solid, 10, 30, 20, 1);
  Assert.AreEqual(1, Integer(Length(mParts)));
  Assert.AreEqual(10, mParts[0].X1);
  Assert.AreEqual(30, mParts[0].X2);
  Assert.AreEqual(20, mParts[0].Y1);
  Assert.AreEqual(20, mParts[0].Y2);
  // Punkte: 1 an, 1 aus.
  mParts := TAtlasReassigned.Segments(TAtlasReassignedStyle.Dotted, 10, 15, 20, 1);
  Assert.AreEqual(3, Integer(Length(mParts)));
  Assert.AreEqual(12, mParts[1].X1);
  Assert.AreEqual(13, mParts[1].X2);
  Assert.AreEqual(15, mParts[2].X2, 'am Ende begrenzt');
  // Mit der Skalierung wachsen die Punkte.
  mParts := TAtlasReassigned.Segments(TAtlasReassignedStyle.Dotted, 0, 8, 20, 2);
  Assert.AreEqual(2, Integer(Length(mParts)));
  Assert.AreEqual(4, mParts[1].X1);
  Assert.AreEqual(6, mParts[1].X2);
  // Welle: abwechselnd hoch und runter, letzte Strecke am Ende begrenzt.
  mParts := TAtlasReassigned.Segments(TAtlasReassignedStyle.Wavy, 0, 5, 20, 1);
  Assert.AreEqual(3, Integer(Length(mParts)));
  Assert.AreEqual(19, mParts[0].Y2);
  Assert.AreEqual(19, mParts[1].Y1);
  Assert.AreEqual(20, mParts[1].Y2);
  Assert.AreEqual(5, mParts[2].X2);
  // Leere Breite und Einheit 0.
  Assert.AreEqual(0, Integer(Length(TAtlasReassigned.Segments(TAtlasReassignedStyle.Solid, 5, 5, 20, 1))));
  Assert.AreEqual(2, Integer(Length(TAtlasReassigned.Segments(TAtlasReassignedStyle.Dotted, 0, 4, 20, 0))));
end;

procedure TAtlasReassignedTests.TargetNamesAndColor;
var
  mTarget: TAtlasReassignedTarget;
  mColor: TAtlasColor;
begin
  Assert.AreEqual('locals,valueParams', TAtlasReassignedNames.TargetsText(TAtlasReassignedNames.cDefaultTargets));
  Assert.AreEqual('loopVars,fields', TAtlasReassignedNames.NormalizeTargets(' Fields; loopvars, unbekannt,fields'));
  Assert.AreEqual('', TAtlasReassignedNames.NormalizeTargets(''));
  Assert.IsTrue(TAtlasReassignedNames.TryTarget('VARPARAMS', mTarget));
  Assert.AreEqual<TAtlasReassignedTarget>(TAtlasReassignedTarget.VarParams, mTarget);
  Assert.IsFalse(TAtlasReassignedNames.TryTarget('globals', mTarget));
  Assert.AreEqual<TAtlasReassignedStyle>(TAtlasReassignedStyle.Wavy, TAtlasReassignedNames.StyleOf('Wavy'));
  Assert.AreEqual<TAtlasReassignedStyle>(TAtlasReassignedStyle.Dotted, TAtlasReassignedNames.StyleOf('dashed'));
  Assert.IsTrue(TAtlasReassignedNames.TryColor('#102030', mColor));
  Assert.AreEqual('#102030', TAtlasColorMath.ToHex(mColor));
  Assert.IsFalse(TAtlasReassignedNames.TryColor('theme', mColor));
  Assert.IsFalse(TAtlasReassignedNames.TryColor('#12345', mColor));
  Assert.IsFalse(TAtlasReassignedNames.TryColor('#GG0000', mColor));
  Assert.AreEqual('#ABCDEF', TAtlasReassignedNames.NormalizeColor(' #abcdef '));
  Assert.AreEqual('theme', TAtlasReassignedNames.NormalizeColor('blau'));
end;

procedure TAtlasReassignedTests.SettingsDefaultsAndElement;
var
  mSettings: TAtlasPluginSettings;
  mElement: TAtlasDrawnElement;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.Reassigned, 'highlight.reassigned standardmaessig an');
  Assert.AreEqual('locals,valueParams', mSettings.ReassignedTargets);
  Assert.AreEqual('dotted', mSettings.ReassignedStyle);
  Assert.AreEqual('theme', mSettings.ReassignedColor);
  mSettings.ReassignedTargets := 'fields,bogus';
  mSettings.ReassignedStyle := 'zickzack';
  mSettings.ReassignedColor := '#zz';
  mSettings.Normalize;
  Assert.AreEqual('fields', mSettings.ReassignedTargets);
  Assert.AreEqual('dotted', mSettings.ReassignedStyle);
  Assert.AreEqual('theme', mSettings.ReassignedColor);
  Assert.IsTrue(TAtlasDrawnElements.ForSetting('Reassigned', mElement));
  Assert.AreEqual<TAtlasDrawnElement>(TAtlasDrawnElement.Reassigned, mElement);
  Assert.IsTrue(TAtlasDrawnElements.Info(mElement).Overlay);
  Assert.IsFalse(TAtlasDrawnElements.Info(mElement).Gutter);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasReassignedTests);

end.
