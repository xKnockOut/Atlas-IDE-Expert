unit Atlas.Common.Editing.MaintenanceCommands.Tests;

// Tests für die Schnellbefehle /sortuses, /ignore, /todo, /doc und /log (#297).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMaintenanceCommandsTests = class
  public
    [Test]
    procedure SortUsesSortsAndRemovesLine;
    [Test]
    procedure SortUsesDropsUnusedKeepsInitialization;
    [Test]
    procedure SortUsesKeepsUnusedWhenSwitchedOff;
    [Test]
    procedure SortUsesLinesStyleFromSetting;
    [Test]
    procedure CleanUsesKeepsOrder;
    [Test]
    procedure CleanUsesWithoutIndexFails;
    [Test]
    procedure IgnoreWritesSuppression;
    [Test]
    procedure IgnoreWithoutLineBelowFails;
    [Test]
    procedure IgnoreOnlyRulesThatHit;
    [Test]
    procedure TodoUsesIdeFormat;
    [Test]
    procedure TodoWithoutTextFails;
    [Test]
    procedure TodoOwnerAndCategoryFromSettings;
    [Test]
    procedure TodoOptionsInLineWin;
    [Test]
    procedure DocForFunction;
    [Test]
    procedure DocForMultiLineProcedure;
    [Test]
    procedure DocWithoutRoutineFails;
    [Test]
    procedure LogNamesUnitAndRoutine;
    [Test]
    procedure LogOutsideRoutineFails;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.MaintenanceCommands,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.UsesGroups,
  Atlas.Tests.SlashHost,
  Atlas.Common.Editing.SlashCommands.TestSupport,
  Atlas.Tests.TextEdits,
  Atlas.Common.Semantics.Contract;

/// <summary>Führt die Befehlszeile ALine mit AHost aus; False mit AReason.</summary>
function RunWith(const AText: string; ALine: Integer; const AHost: ISlashHost; out AResult, AReason: string): Boolean;
var
  mEdits: TArray<TTextEdit>;
begin
  AResult := '';
  Result := TSlashCommandRegistry.Shared.Run(AText, ALine, 0, TSlashEnvironment.Create(nil, nil, nil, '', '', AHost),
    mEdits, AReason);
  if Result then
  begin
    AResult := TTestEdits.Apply(AText, mEdits);
  end;
end;

function ExpandWith(const AText: string; ALine: Integer; const AHost: ISlashHost): string;
var
  mReason: string;
begin
  Assert.IsTrue(RunWith(AText, ALine, AHost, Result, mReason), mReason);
end;

/// <summary>Index-Auskunft: SysUtils liefert Format, Classes TStringList, Vcl.Forms hat initialization.</summary>
function UnitInfo(const AUnitName: string): TUsesUnitInfo;
begin
  Result := Default(TUsesUnitInfo);
  Result.Known := True;
  if SameText(AUnitName, 'System.SysUtils') then
  begin
    Result.Names := ['Format'];
  end
  else if SameText(AUnitName, 'System.Classes') then
  begin
    Result.Names := ['TStringList'];
  end
  else if SameText(AUnitName, 'Vcl.Forms') then
  begin
    Result.HasInitialization := True;
  end
  else
  begin
    Result.Known := False;
  end;
end;

function UsesHost: TRecordingSlashHost;
begin
  Result := TRecordingSlashHost.Create;
  Result.HasUses := True;
  Result.Uses_.Info :=
    function(const AUnitName: string): TUsesUnitInfo
    begin
      Result := UnitInfo(AUnitName);
    end;
end;

const
  cRoutine =
    'unit Daten;'#10'interface'#10'implementation'#10'procedure TFoo.Laden;'#10'begin'#10'  %s'#10 +
    '  X := 1;'#10'end;'#10'end.';

{ TMaintenanceCommandsTests }

procedure TMaintenanceCommandsTests.SortUsesSortsAndRemovesLine;
const
  cText = 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils, System.Classes;'#10'implementation'#10 +
    '/sortuses'#10#10'end.';
begin
  // Per Vorgabe nach Herkunft (#2794): eine Gruppe, also ohne Gruppenkommentar.
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  System.Classes, System.SysUtils;'#10 +
    'implementation'#10#10'end.', TSlashTest.Expand(cText, 5));
end;

const
  cUnusedText = 'unit U;'#10'interface'#10'uses'#10'  Vcl.Forms, System.SysUtils, System.Classes;'#10 +
    'implementation'#10'/sortuses'#10'procedure P;'#10'begin'#10'  Format('''', []);'#10'end;'#10'end.';

procedure TMaintenanceCommandsTests.SortUsesDropsUnusedKeepsInitialization;
var
  mKeep: ISlashHost;
begin
  // #284: Classes wird nicht benutzt und fällt weg; Vcl.Forms bleibt wegen initialization. Gruppen mit Kommentar.
  mKeep := UsesHost;
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  ' + TUsesGroups.LabelOf(TUsesGroup.RuntimeLibrary) + #10 +
    '  System.SysUtils,'#10'  ' + TUsesGroups.LabelOf(TUsesGroup.Framework) + #10'  Vcl.Forms;'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  Format('''', []);'#10'end;'#10'end.',
    ExpandWith(cUnusedText, 5, mKeep));
end;

procedure TMaintenanceCommandsTests.SortUsesKeepsUnusedWhenSwitchedOff;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mExpected: string;
begin
  mExpected := 'unit U;'#10'interface'#10'uses'#10'  System.Classes,'#10'  System.SysUtils,'#10'  Vcl.Forms;'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  Format('''', []);'#10'end;'#10'end.';
  mHost := UsesHost;
  mKeep := mHost;
  mHost.Settings := [TSlashSettings.cSortUsesRemoveUnused + '=false', TSlashSettings.cSortUsesOrder + '=alphabetic'];
  Assert.AreEqual(mExpected, ExpandWith(cUnusedText, 5, mKeep));
  // usesKeep hält die Unit ebenfalls.
  mHost.Settings := [TSlashSettings.cSortUsesOrder + '=alphabetic'];
  mHost.Uses_.Keep := ['System.Classes'];
  Assert.AreEqual(mExpected, ExpandWith(cUnusedText, 5, mKeep));
end;

procedure TMaintenanceCommandsTests.SortUsesLinesStyleFromSetting;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
begin
  // usesGroupStyle lines (#2794): jede Gruppe in neuer Zeile, ohne Kommentar.
  mHost := UsesHost;
  mKeep := mHost;
  mHost.Settings := [TSlashSettings.cUsesGroupStyle + '=lines'];
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  System.SysUtils,'#10'  Vcl.Forms;'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  Format('''', []);'#10'end;'#10'end.',
    ExpandWith(cUnusedText, 5, mKeep));
end;

procedure TMaintenanceCommandsTests.CleanUsesKeepsOrder;
var
  mKeep: ISlashHost;
begin
  // Nur System.Classes fällt weg; Vcl.Forms bleibt vor System.SysUtils.
  mKeep := UsesHost;
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Vcl.Forms,'#10'  System.SysUtils;'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  Format('''', []);'#10'end;'#10'end.',
    ExpandWith(StringReplace(cUnusedText, '/sortuses', '/cleanuses', []), 5, mKeep));
end;

procedure TMaintenanceCommandsTests.CleanUsesWithoutIndexFails;
var
  mKeep: ISlashHost;
  mResult_, mReason: string;
begin
  mKeep := TRecordingSlashHost.Create;
  Assert.IsFalse(RunWith(StringReplace(cUnusedText, '/sortuses', '/cleanuses', []), 5, mKeep, mResult_, mReason));
  Assert.AreEqual(CleanUsesNoIndexHint, mReason);
  Assert.AreEqual(CleanUsesNoIndexHint, TSlashTest.ProblemOf(StringReplace(cUnusedText, '/sortuses', '/cleanuses', [])));
end;

procedure TMaintenanceCommandsTests.IgnoreWritesSuppression;
begin
  Assert.AreEqual(Format(cRoutine, ['// lsp-ignore: magic-number -- Absicht']),
    TSlashTest.Expand(Format(cRoutine, ['/ignore Magic-Number Absicht']), 5));
  Assert.AreEqual(Format(cRoutine, ['// lsp-ignore: magic-number']),
    TSlashTest.Expand(Format(cRoutine, ['/ignore magic-number']), 5));
end;

procedure TMaintenanceCommandsTests.IgnoreWithoutLineBelowFails;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'/ignore magic-number'#10#10'end.';
begin
  Assert.AreEqual('Unter /ignore steht keine Zeile, die unterdrückt werden kann', TSlashTest.ProblemOf(cText));
  Assert.AreEqual('Erwartet wird /ignore regel [Begründung]', TSlashTest.ProblemOf(Format(cRoutine, ['/ignore ä'])));
end;

procedure TMaintenanceCommandsTests.IgnoreOnlyRulesThatHit;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
  mResult_, mReason: string;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.HasRuleIds := True;
  mHost.RuleIds := ['magic-number'];
  Assert.IsFalse(RunWith(Format(cRoutine, ['/ignore unused-local']), 5, mKeep, mResult_, mReason));
  Assert.AreEqual(Format(IgnoreNoHitHint, ['unused-local']), mReason);
  Assert.AreEqual(6, mHost.RuleLine);
  Assert.AreEqual(Format(cRoutine, ['// lsp-ignore: magic-number']),
    ExpandWith(Format(cRoutine, ['/ignore magic-number']), 5, mKeep));
  // Muster und Hosts ohne Prüfregeln (False) lassen jede Kennung zu.
  Assert.AreEqual(Format(cRoutine, ['// lsp-ignore: magic-*']),
    ExpandWith(Format(cRoutine, ['/ignore magic-*']), 5, mKeep));
  mHost.HasRuleIds := False;
  Assert.AreEqual(Format(cRoutine, ['// lsp-ignore: unused-local']),
    ExpandWith(Format(cRoutine, ['/ignore unused-local']), 5, mKeep));
end;

procedure TMaintenanceCommandsTests.TodoUsesIdeFormat;
begin
  Assert.AreEqual(Format(cRoutine, ['// TODO : Fehlerfall prüfen']),
    TSlashTest.Expand(Format(cRoutine, ['/todo Fehlerfall prüfen']), 5));
end;

procedure TMaintenanceCommandsTests.TodoWithoutTextFails;
begin
  Assert.AreEqual('Erwartet wird /todo Text', TSlashTest.ProblemOf(Format(cRoutine, ['/todo'])));
end;

procedure TMaintenanceCommandsTests.TodoOwnerAndCategoryFromSettings;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.Settings := [TSlashSettings.cTodoOwner + '=Marco', TSlashSettings.cTodoCategory + '=Review'];
  Assert.AreEqual(Format(cRoutine, ['// TODO -oMarco -cReview : Fehlerfall prüfen']),
    ExpandWith(Format(cRoutine, ['/todo Fehlerfall prüfen']), 5, mKeep));
end;

procedure TMaintenanceCommandsTests.TodoOptionsInLineWin;
var
  mHost: TRecordingSlashHost;
  mKeep: ISlashHost;
begin
  mHost := TRecordingSlashHost.Create;
  mKeep := mHost;
  mHost.Settings := [TSlashSettings.cTodoOwner + '=Marco', TSlashSettings.cTodoCategory + '=Review'];
  Assert.AreEqual(Format(cRoutine, ['// TODO -oEva -cTest : Fehlerfall prüfen']),
    ExpandWith(Format(cRoutine, ['/todo -oEva -cTest Fehlerfall prüfen']), 5, mKeep));
  // -c ohne Kategorie lässt sie weg, -o ohne Namen nimmt den Standardnamen.
  Assert.AreEqual(Format(cRoutine, ['// TODO -oMarco : Fehlerfall prüfen']),
    ExpandWith(Format(cRoutine, ['/todo -o -c Fehlerfall prüfen']), 5, mKeep));
  Assert.AreEqual('Erwartet wird /todo Text', TSlashTest.ProblemOf(Format(cRoutine, ['/todo -oEva'])));
end;

procedure TMaintenanceCommandsTests.DocForFunction;
const
  cText = 'unit U;'#10'interface'#10'/doc'#10'function Summe(const A, B: Integer): Integer;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual('unit U;'#10'interface'#10'/// <summary></summary>'#10'/// <param name="A"></param>'#10 +
    '/// <param name="B"></param>'#10'/// <returns></returns>'#10 +
    'function Summe(const A, B: Integer): Integer;'#10'implementation'#10'end.', TSlashTest.Expand(cText, 2));
end;

procedure TMaintenanceCommandsTests.DocForMultiLineProcedure;
const
  cText = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    /doc'#10'    procedure Lauf(X: Integer;'#10 +
    '      var Y: string);'#10'  end;'#10'implementation'#10'end.';
var
  mResult_: string;
begin
  mResult_ := TSlashTest.Expand(cText, 4);
  Assert.IsTrue(Pos('    /// <summary></summary>'#10'    /// <param name="X"></param>'#10 +
    '    /// <param name="Y"></param>'#10'    procedure Lauf(', mResult_) > 0, mResult_);
  Assert.AreEqual(0, Pos('returns', mResult_));
end;

procedure TMaintenanceCommandsTests.DocWithoutRoutineFails;
begin
  Assert.AreEqual('/doc gilt nur über einer Routine', TSlashTest.ProblemOf(Format(cRoutine, ['/doc'])));
end;

procedure TMaintenanceCommandsTests.LogNamesUnitAndRoutine;
begin
  Assert.AreEqual(Format(cRoutine, ['OutputDebugString(PChar(''Daten.TFoo.Laden''));']),
    TSlashTest.Expand(Format(cRoutine, ['/log']), 5));
  Assert.AreEqual(Format(cRoutine, ['OutputDebugString(PChar(''Daten.TFoo.Laden: Start''));']),
    TSlashTest.Expand(Format(cRoutine, ['/log Start']), 5));
end;

procedure TMaintenanceCommandsTests.LogOutsideRoutineFails;
const
  cText = 'unit U;'#10'interface'#10'/log'#10#10'implementation'#10'end.';
begin
  Assert.AreEqual('/log gilt nur im Rumpf einer Routine', TSlashTest.ProblemOf(cText));
end;

initialization
  TDUnitX.RegisterTestFixture(TMaintenanceCommandsTests);

end.
