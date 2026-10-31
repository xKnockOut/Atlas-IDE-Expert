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
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.MaintenanceCommands,
  Atlas.Tests.SlashHost;

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in AEdits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function Expand(const AText: string; ALine: Integer): string;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(AText, ALine, Edits), AText);
  Result := Apply(AText, Edits);
end;

/// <summary>Führt die Befehlszeile ALine mit AHost aus; False mit AReason.</summary>
function RunWith(const AText: string; ALine: Integer; const AHost: ISlashHost; out AResult, AReason: string): Boolean;
var
  Edits: TArray<TTextEdit>;
begin
  AResult := '';
  Result := TSlashCommandRegistry.Shared.Run(AText, ALine, 0, nil, nil, nil, '', '', AHost, Edits, AReason);
  if Result then
    AResult := Apply(AText, Edits);
end;

function ExpandWith(const AText: string; ALine: Integer; const AHost: ISlashHost): string;
var
  Reason: string;
begin
  Assert.IsTrue(RunWith(AText, ALine, AHost, Result, Reason), Reason);
end;

/// <summary>Index-Auskunft: SysUtils liefert Format, Classes TStringList, Vcl.Forms hat initialization.</summary>
function UnitInfo(const AUnitName: string): TUsesUnitInfo;
begin
  Result := Default(TUsesUnitInfo);
  Result.Known := True;
  if SameText(AUnitName, 'System.SysUtils') then
    Result.Names := ['Format']
  else if SameText(AUnitName, 'System.Classes') then
    Result.Names := ['TStringList']
  else if SameText(AUnitName, 'Vcl.Forms') then
    Result.HasInitialization := True
  else
    Result.Known := False;
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

function ProblemOf(const AText: string): string;
var
  Problems: TArray<TSlashProblem>;
begin
  Problems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Result := Problems[0].Message;
end;

const
  Routine =
    'unit Daten;'#10'interface'#10'implementation'#10'procedure TFoo.Laden;'#10'begin'#10'  %s'#10 +
    '  X := 1;'#10'end;'#10'end.';

procedure TMaintenanceCommandsTests.SortUsesSortsAndRemovesLine;
const
  Text = 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils, System.Classes;'#10'implementation'#10 +
    '/sortuses'#10#10'end.';
begin
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  System.Classes,'#10'  System.SysUtils;'#10 +
    'implementation'#10#10'end.', Expand(Text, 5));
end;

const
  UnusedText = 'unit U;'#10'interface'#10'uses'#10'  Vcl.Forms, System.SysUtils, System.Classes;'#10 +
    'implementation'#10'/sortuses'#10'procedure P;'#10'begin'#10'  Format('''', []);'#10'end;'#10'end.';

procedure TMaintenanceCommandsTests.SortUsesDropsUnusedKeepsInitialization;
var
  Keep: ISlashHost;
begin
  // #284: Classes wird nicht benutzt und fällt weg; Vcl.Forms bleibt wegen initialization.
  Keep := UsesHost;
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  System.SysUtils,'#10'  Vcl.Forms;'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  Format('''', []);'#10'end;'#10'end.',
    ExpandWith(UnusedText, 5, Keep));
end;

procedure TMaintenanceCommandsTests.SortUsesKeepsUnusedWhenSwitchedOff;
var
  Host: TRecordingSlashHost;
  Keep: ISlashHost;
  Expected: string;
begin
  Expected := 'unit U;'#10'interface'#10'uses'#10'  System.Classes,'#10'  System.SysUtils,'#10'  Vcl.Forms;'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  Format('''', []);'#10'end;'#10'end.';
  Host := UsesHost;
  Keep := Host;
  Host.Settings := [TSlashSettings.SortUsesRemoveUnused + '=false'];
  Assert.AreEqual(Expected, ExpandWith(UnusedText, 5, Keep));
  // usesKeep hält die Unit ebenfalls.
  Host.Settings := nil;
  Host.Uses_.Keep := ['System.Classes'];
  Assert.AreEqual(Expected, ExpandWith(UnusedText, 5, Keep));
end;

procedure TMaintenanceCommandsTests.CleanUsesKeepsOrder;
var
  Keep: ISlashHost;
begin
  // Nur System.Classes fällt weg; Vcl.Forms bleibt vor System.SysUtils.
  Keep := UsesHost;
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Vcl.Forms,'#10'  System.SysUtils;'#10 +
    'implementation'#10'procedure P;'#10'begin'#10'  Format('''', []);'#10'end;'#10'end.',
    ExpandWith(StringReplace(UnusedText, '/sortuses', '/cleanuses', []), 5, Keep));
end;

procedure TMaintenanceCommandsTests.CleanUsesWithoutIndexFails;
var
  Keep: ISlashHost;
  Result_, Reason: string;
begin
  Keep := TRecordingSlashHost.Create;
  Assert.IsFalse(RunWith(StringReplace(UnusedText, '/sortuses', '/cleanuses', []), 5, Keep, Result_, Reason));
  Assert.AreEqual(CleanUsesNoIndexHint, Reason);
  Assert.AreEqual(CleanUsesNoIndexHint, ProblemOf(StringReplace(UnusedText, '/sortuses', '/cleanuses', [])));
end;

procedure TMaintenanceCommandsTests.IgnoreWritesSuppression;
begin
  Assert.AreEqual(Format(Routine, ['// lsp-ignore: magic-number -- Absicht']),
    Expand(Format(Routine, ['/ignore Magic-Number Absicht']), 5));
  Assert.AreEqual(Format(Routine, ['// lsp-ignore: magic-number']),
    Expand(Format(Routine, ['/ignore magic-number']), 5));
end;

procedure TMaintenanceCommandsTests.IgnoreWithoutLineBelowFails;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'/ignore magic-number'#10#10'end.';
begin
  Assert.AreEqual('Unter /ignore steht keine Zeile, die unterdrückt werden kann', ProblemOf(Text));
  Assert.AreEqual('Erwartet wird /ignore regel [Begründung]', ProblemOf(Format(Routine, ['/ignore ä'])));
end;

procedure TMaintenanceCommandsTests.IgnoreOnlyRulesThatHit;
var
  Host: TRecordingSlashHost;
  Keep: ISlashHost;
  Result_, Reason: string;
begin
  Host := TRecordingSlashHost.Create;
  Keep := Host;
  Host.HasRuleIds := True;
  Host.RuleIds := ['magic-number'];
  Assert.IsFalse(RunWith(Format(Routine, ['/ignore unused-local']), 5, Keep, Result_, Reason));
  Assert.AreEqual(Format(IgnoreNoHitHint, ['unused-local']), Reason);
  Assert.AreEqual(6, Host.RuleLine);
  Assert.AreEqual(Format(Routine, ['// lsp-ignore: magic-number']),
    ExpandWith(Format(Routine, ['/ignore magic-number']), 5, Keep));
  // Muster und Hosts ohne Prüfregeln (False) lassen jede Kennung zu.
  Assert.AreEqual(Format(Routine, ['// lsp-ignore: magic-*']),
    ExpandWith(Format(Routine, ['/ignore magic-*']), 5, Keep));
  Host.HasRuleIds := False;
  Assert.AreEqual(Format(Routine, ['// lsp-ignore: unused-local']),
    ExpandWith(Format(Routine, ['/ignore unused-local']), 5, Keep));
end;

procedure TMaintenanceCommandsTests.TodoUsesIdeFormat;
begin
  Assert.AreEqual(Format(Routine, ['// TODO : Fehlerfall prüfen']),
    Expand(Format(Routine, ['/todo Fehlerfall prüfen']), 5));
end;

procedure TMaintenanceCommandsTests.TodoWithoutTextFails;
begin
  Assert.AreEqual('Erwartet wird /todo Text', ProblemOf(Format(Routine, ['/todo'])));
end;

procedure TMaintenanceCommandsTests.TodoOwnerAndCategoryFromSettings;
var
  Host: TRecordingSlashHost;
  Keep: ISlashHost;
begin
  Host := TRecordingSlashHost.Create;
  Keep := Host;
  Host.Settings := [TSlashSettings.TodoOwner + '=Marco', TSlashSettings.TodoCategory + '=Review'];
  Assert.AreEqual(Format(Routine, ['// TODO -oMarco -cReview : Fehlerfall prüfen']),
    ExpandWith(Format(Routine, ['/todo Fehlerfall prüfen']), 5, Keep));
end;

procedure TMaintenanceCommandsTests.TodoOptionsInLineWin;
var
  Host: TRecordingSlashHost;
  Keep: ISlashHost;
begin
  Host := TRecordingSlashHost.Create;
  Keep := Host;
  Host.Settings := [TSlashSettings.TodoOwner + '=Marco', TSlashSettings.TodoCategory + '=Review'];
  Assert.AreEqual(Format(Routine, ['// TODO -oEva -cTest : Fehlerfall prüfen']),
    ExpandWith(Format(Routine, ['/todo -oEva -cTest Fehlerfall prüfen']), 5, Keep));
  // -c ohne Kategorie lässt sie weg, -o ohne Namen nimmt den Standardnamen.
  Assert.AreEqual(Format(Routine, ['// TODO -oMarco : Fehlerfall prüfen']),
    ExpandWith(Format(Routine, ['/todo -o -c Fehlerfall prüfen']), 5, Keep));
  Assert.AreEqual('Erwartet wird /todo Text', ProblemOf(Format(Routine, ['/todo -oEva'])));
end;

procedure TMaintenanceCommandsTests.DocForFunction;
const
  Text = 'unit U;'#10'interface'#10'/doc'#10'function Summe(const A, B: Integer): Integer;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual('unit U;'#10'interface'#10'/// <summary></summary>'#10'/// <param name="A"></param>'#10 +
    '/// <param name="B"></param>'#10'/// <returns></returns>'#10 +
    'function Summe(const A, B: Integer): Integer;'#10'implementation'#10'end.', Expand(Text, 2));
end;

procedure TMaintenanceCommandsTests.DocForMultiLineProcedure;
const
  Text = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    /doc'#10'    procedure Lauf(X: Integer;'#10 +
    '      var Y: string);'#10'  end;'#10'implementation'#10'end.';
var
  Result_: string;
begin
  Result_ := Expand(Text, 4);
  Assert.IsTrue(Pos('    /// <summary></summary>'#10'    /// <param name="X"></param>'#10 +
    '    /// <param name="Y"></param>'#10'    procedure Lauf(', Result_) > 0, Result_);
  Assert.AreEqual(0, Pos('returns', Result_));
end;

procedure TMaintenanceCommandsTests.DocWithoutRoutineFails;
begin
  Assert.AreEqual('/doc gilt nur über einer Routine', ProblemOf(Format(Routine, ['/doc'])));
end;

procedure TMaintenanceCommandsTests.LogNamesUnitAndRoutine;
begin
  Assert.AreEqual(Format(Routine, ['OutputDebugString(PChar(''Daten.TFoo.Laden''));']),
    Expand(Format(Routine, ['/log']), 5));
  Assert.AreEqual(Format(Routine, ['OutputDebugString(PChar(''Daten.TFoo.Laden: Start''));']),
    Expand(Format(Routine, ['/log Start']), 5));
end;

procedure TMaintenanceCommandsTests.LogOutsideRoutineFails;
const
  Text = 'unit U;'#10'interface'#10'/log'#10#10'implementation'#10'end.';
begin
  Assert.AreEqual('/log gilt nur im Rumpf einer Routine', ProblemOf(Text));
end;

initialization
  TDUnitX.RegisterTestFixture(TMaintenanceCommandsTests);

end.
