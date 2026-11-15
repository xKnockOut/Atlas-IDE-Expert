unit Atlas.Core.Commands.ShortcutTable.Tests;

// Tests für die Tabelle Kürzel → Befehle der Tastenkürzel-Tipps (#600, #1967): Kürzel mit einem und zwei
// Schritten, Zeitfenster für den zweiten Schritt, Neubau nach Alter und nach Invalidate, gelernte Kürzel und
// selbst gemeldete Aufrufe.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Commands.ShortcutTable;

type
  [TestFixture]
  TAtlasShortcutTableTests = class
  private
    FTable: TAtlasShortcutTable;
    FBuilds: Integer;
    procedure Build;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SingleStrokeFindsAllCommands;
    [Test]
    procedure SecondStepNeedsRecentFirstStep;
    [Test]
    procedure PlainKeyCountsOnlyAsSecondStep;
    [Test]
    procedure RebuildsAfterMaxAgeOrInvalidate;
    [Test]
    procedure LearnedKeysSurviveRebuild;
    [Test]
    procedure ExplicitCallExpires;
    [Test]
    procedure IgnoresEmptyKeysAndIds;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.ShortcutTips;

const
  cCtrlK = TAtlasKeyConflicts.cScCtrl or Ord('K');
  cCtrlD = TAtlasKeyConflicts.cScCtrl or Ord('D');
  cKeyD = Ord('D');
  cStart = 1000;

{ TAtlasShortcutTableTests }

procedure TAtlasShortcutTableTests.Build;
begin
  Inc(FBuilds);
  FTable.AddKey(cCtrlD, 'Duplizieren');
  FTable.AddText('Strg+D', 'Zweiter');
  FTable.AddText('Strg+K, D', 'Kette');
  FTable.AddText('Strg+K, Strg+D', 'KetteStrg');
  FTable.AddLearned;
end;

procedure TAtlasShortcutTableTests.Setup;
begin
  FBuilds := 0;
  FTable := TAtlasShortcutTable.Create;
  FTable.OnBuild := Build;
end;

procedure TAtlasShortcutTableTests.TearDown;
begin
  FTable.OnBuild := nil;
  FreeAndNil(FTable);
end;

procedure TAtlasShortcutTableTests.SingleStrokeFindsAllCommands;
var
  mIds: TArray<string>;
begin
  mIds := FTable.Stroke(cCtrlD, True, cStart);
  Assert.AreEqual(2, Integer(Length(mIds)));
  Assert.AreEqual('Duplizieren', mIds[0]);
  Assert.AreEqual('Zweiter', mIds[1]);
  Assert.AreEqual(Integer(cCtrlD), Integer(FTable.PrevKey));
  Assert.IsTrue(FTable.PrevAge(cStart + 5) = 5, 'Alter des vorigen Schritts');
end;

procedure TAtlasShortcutTableTests.SecondStepNeedsRecentFirstStep;
var
  mIds: TArray<string>;
begin
  Assert.AreEqual(0, Integer(Length(FTable.Stroke(cCtrlK, True, cStart))), 'Strg+K allein hat keinen Befehl');
  Assert.IsTrue(FTable.ChordPending(cStart + 1));
  mIds := FTable.Stroke(cCtrlD, True, cStart + 10);
  Assert.AreEqual(3, Integer(Length(mIds)), 'Strg+D allein und als zweiter Schritt');
  Assert.AreEqual('KetteStrg', mIds[2]);
  FTable.Stroke(cCtrlK, True, cStart + 20);
  mIds := FTable.Stroke(cCtrlD, True, cStart + 20 + TAtlasShortcutTips.cChordMs);
  Assert.AreEqual(2, Integer(Length(mIds)), 'zu spät für den zweiten Schritt');
end;

procedure TAtlasShortcutTableTests.PlainKeyCountsOnlyAsSecondStep;
var
  mIds: TArray<string>;
begin
  Assert.AreEqual(0, Integer(Length(FTable.Stroke(cKeyD, False, cStart))), 'D ohne vorigen Schritt');
  Assert.AreEqual(0, Integer(FTable.PrevKey), 'vergisst den vorigen Schritt');
  FTable.Stroke(cCtrlK, True, cStart + 1);
  mIds := FTable.Stroke(cKeyD, False, cStart + 2);
  Assert.AreEqual(1, Integer(Length(mIds)));
  Assert.AreEqual('Kette', mIds[0]);
  Assert.AreEqual(Integer(cKeyD), Integer(FTable.PrevKey));
end;

procedure TAtlasShortcutTableTests.RebuildsAfterMaxAgeOrInvalidate;
begin
  FTable.Stroke(cCtrlD, True, cStart);
  FTable.Stroke(cCtrlD, True, cStart + TAtlasShortcutTable.cMaxAgeMs - 1);
  Assert.AreEqual(1, FBuilds, 'innerhalb des Alters einmal');
  FTable.Stroke(cCtrlD, True, cStart + TAtlasShortcutTable.cMaxAgeMs);
  Assert.AreEqual(2, FBuilds, 'nach dem Alter neu');
  FTable.Invalidate;
  Assert.AreEqual(2, Integer(Length(FTable.Stroke(cCtrlD, True, cStart + TAtlasShortcutTable.cMaxAgeMs + 1))),
    'Neubau leert und füllt, ohne doppelte Einträge');
  Assert.AreEqual(3, FBuilds);
  FTable.Stroke(cKeyD, False, cStart + 3 * TAtlasShortcutTable.cMaxAgeMs);
  Assert.AreEqual(3, FBuilds, 'ohne Kürzel kein Neubau');
end;

procedure TAtlasShortcutTableTests.LearnedKeysSurviveRebuild;
var
  mIds: TArray<string>;
begin
  FTable.Stroke(cCtrlD, True, cStart);
  FTable.Learn('Gelernt', 'Strg+Umschalt+L');
  FTable.Learn('Leer', '');
  Assert.AreEqual(1, FBuilds);
  mIds := FTable.Stroke(TAtlasKeyConflicts.cScCtrl or TAtlasKeyConflicts.cScShift or Ord('L'), True, cStart + 1);
  Assert.AreEqual(2, FBuilds, 'Lernen baut neu');
  Assert.AreEqual(1, Integer(Length(mIds)));
  Assert.AreEqual('Gelernt', mIds[0]);
end;

procedure TAtlasShortcutTableTests.ExplicitCallExpires;
begin
  Assert.IsFalse(FTable.IsExplicit('Befehl', cStart));
  FTable.Explicit('Befehl', cStart);
  Assert.IsTrue(FTable.IsExplicit('befehl', cStart + TAtlasShortcutTable.cExplicitMs - 1));
  Assert.IsFalse(FTable.IsExplicit('Befehl', cStart + TAtlasShortcutTable.cExplicitMs));
  Assert.IsFalse(FTable.IsExplicit('Anderer', cStart));
end;

procedure TAtlasShortcutTableTests.IgnoresEmptyKeysAndIds;
begin
  FTable.OnBuild := nil;
  FTable.AddKey(0, 'Ohne');
  FTable.AddKey(cCtrlK, '');
  FTable.AddText('Strg+Unsinn', 'Unlesbar');
  FTable.AddText('', 'Leer');
  Assert.AreEqual(0, Integer(Length(FTable.Stroke(cCtrlK, True, cStart))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasShortcutTableTests);

end.
