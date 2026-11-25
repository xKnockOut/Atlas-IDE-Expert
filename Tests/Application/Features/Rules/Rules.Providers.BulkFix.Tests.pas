unit Rules.Providers.BulkFix.Tests;

// Tests des Anbieters der Sammelkorrektur (#1352) für andere Features: korrigiert Texte, ohne zu schreiben, liefert
// Diff mit / im Pfad und beide Zusammenfassungen; eine niedrigere Untergrenze als fix.minConfidence lehnt er ab.
// Über Dateien des Arbeitsbereichs: Umfeld und Text je Datei, Baseline-Treffer bleiben, unlesbare Dateien fehlen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleBulkFixProviderTests = class
  public
    [Test]
    procedure FixesTextsAndDiffs;
    [Test]
    procedure LeavesCleanFileUnchanged;
    [Test]
    procedure RefusesLowerConfidence;
    [Test]
    procedure WorkspaceFixesWithContextOfFile;
    [Test]
    procedure WorkspaceKeepsBaselineFindings;
    [Test]
    procedure WorkspaceRefusesLowerConfidence;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Baseline,
  Rules.Checker,
  Rules.CheckContext,
  Atlas.Common.Documents.Uris,
  Rules.Builtin,
  Rules.Contract.Api,
  Rules.Providers.BulkFix;

const
  cAssignedFree = 'unit U;'#10#10'interface'#10#10'uses'#10'  System.Classes;'#10#10'implementation'#10#10 +
    'procedure Weg(AList: TStringList);'#10'begin'#10'  if Assigned(AList) then'#10'    AList.Free;'#10'end;'#10#10 +
    'end.'#10;
  cClean = 'unit V;'#10#10'interface'#10#10'implementation'#10#10'end.'#10;

function Input(const AFileName, ARelativePath, AText: string): TRuleBulkFixInput;
begin
  Result := Default(TRuleBulkFixInput);
  Result.FileName := AFileName;
  Result.RelativePath := ARelativePath;
  Result.Text := AText;
end;

function Provider: IRuleBulkFix;
begin
  Result := TRuleBulkFixProvider.Create(BuiltinRules, nil, nil);
end;

var
  Baseline: IRuleBaseline;

/// <summary>Text von U.pas und V.pas; andere Dateien sind nicht lesbar.</summary>
function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := True;
  if SameText(ExtractFileName(AFileName), 'U.pas') then
  begin
    AText := cAssignedFree;
  end
  else if SameText(ExtractFileName(AFileName), 'V.pas') then
  begin
    AText := cClean;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Umfeld je Datei: eingebaute Regeln, Vorgaben, Pfad unter Src, Baseline.</summary>
function Contexts: TRuleContextProvider;
begin
  Result :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := Default(TRuleCheckContext);
      AContext.Rules := BuiltinRules;
      AContext.Settings := TServerSettings.Default;
      AContext.RelativePath := 'Src\' + ExtractFileName(TDocumentUris.ToPath(AUri));
      AContext.Baseline := Baseline;
      Result := True;
    end;
end;

function Workspace: IRuleWorkspaceBulkFix;
begin
  Result := TRuleBulkFixProvider.CreateForWorkspace(Contexts(), ReadText, nil);
end;

{ TRuleBulkFixProviderTests }

procedure TRuleBulkFixProviderTests.FixesTextsAndDiffs;
var
  mRun: TRuleBulkFixRun;
  mError: string;
begin
  Assert.IsTrue(Provider.Run([Input('C:\P\Src\U.pas', 'Src\U.pas', cAssignedFree)], ['redundant-assigned-free'],
    '', TServerSettings.Default, mRun, mError), mError);
  Assert.AreEqual(1, Integer(Length(mRun.Files)));
  Assert.AreEqual('C:\P\Src\U.pas', mRun.Files[0].FileName);
  Assert.AreEqual(cAssignedFree, mRun.Files[0].OldText);
  Assert.IsTrue(mRun.Files[0].Changed);
  Assert.IsFalse(Pos('Assigned', mRun.Files[0].NewText) > 0, mRun.Files[0].NewText);
  Assert.Contains(mRun.Files[0].Diff, '--- a/Src/U.pas');
  Assert.Contains(mRun.Files[0].Diff, '-  if Assigned(AList) then');
  Assert.Contains(mRun.PreviewSummary, 'Vorschau: 1 Korrekturen in 1 Dateien');
  Assert.Contains(mRun.WrittenSummary, '1 Korrekturen in 1 Dateien geschrieben');
end;

procedure TRuleBulkFixProviderTests.LeavesCleanFileUnchanged;
var
  mRun: TRuleBulkFixRun;
  mError: string;
begin
  Assert.IsTrue(Provider.Run([Input('C:\P\V.pas', 'V.pas', cClean)], ['all'], '', TServerSettings.Default, mRun,
    mError), mError);
  Assert.AreEqual(1, Integer(Length(mRun.Files)));
  Assert.IsFalse(mRun.Files[0].Changed);
  Assert.AreEqual(cClean, mRun.Files[0].NewText);
  Assert.AreEqual('', mRun.Files[0].Diff);
end;

procedure TRuleBulkFixProviderTests.RefusesLowerConfidence;
var
  mRun: TRuleBulkFixRun;
  mError: string;
begin
  Assert.IsFalse(Provider.Run([Input('C:\P\U.pas', 'U.pas', cAssignedFree)], ['redundant-assigned-free'], 'medium',
    TServerSettings.Default, mRun, mError));
  Assert.Contains(mError, 'fix.minConfidence');
  Assert.AreEqual(0, Integer(Length(mRun.Files)));
end;

procedure TRuleBulkFixProviderTests.WorkspaceFixesWithContextOfFile;
var
  mRun: TRuleBulkFixRun;
  mError: string;
begin
  Baseline := nil;
  Assert.IsTrue(Workspace.Run(['C:\P\Src\U.pas', 'C:\P\Fehlt.pas'], ['redundant-assigned-free'], '', mRun,
    mError), mError);
  Assert.AreEqual(1, Integer(Length(mRun.Files)));
  Assert.IsTrue(mRun.Files[0].Changed);
  Assert.IsFalse(mRun.Files[0].Rejected);
  Assert.AreEqual(1, mRun.Files[0].FixCount);
  Assert.AreEqual(1, Integer(Length(mRun.Files[0].Applied)));
  Assert.AreEqual('redundant-assigned-free', mRun.Files[0].Applied[0].RuleId);
  Assert.Contains(mRun.Files[0].Diff, '--- a/Src/U.pas');
  Assert.Contains(mRun.PreviewSummary, 'Vorschau: 1 Korrekturen in 1 Dateien');
end;

procedure TRuleBulkFixProviderTests.WorkspaceKeepsBaselineFindings;
var
  mSource: TBaselineSource;
  mRun: TRuleBulkFixRun;
  mError: string;
begin
  mSource.Path := 'Src\U.pas';
  mSource.Text := cAssignedFree;
  mSource.Findings := TFileChecker.CheckText(BuiltinRules, TServerSettings.Default, 'Src\U.pas', cAssignedFree);
  Baseline := TRuleBaseline.FromJson(TRuleBaseline.Build(TArray<TBaselineSource>.Create(mSource)));
  try
    Assert.IsTrue(Workspace.Run(['C:\P\Src\U.pas'], ['redundant-assigned-free'], '', mRun, mError), mError);
    Assert.AreEqual(1, Integer(Length(mRun.Files)));
    Assert.IsFalse(mRun.Files[0].Changed);
  finally
    Baseline := nil;
  end;
end;

procedure TRuleBulkFixProviderTests.WorkspaceRefusesLowerConfidence;
var
  mRun: TRuleBulkFixRun;
  mError: string;
begin
  Baseline := nil;
  Assert.IsFalse(Workspace.Run(['C:\P\Src\U.pas'], ['redundant-assigned-free'], 'medium', mRun, mError));
  Assert.Contains(mError, 'fix.minConfidence');
  Assert.AreEqual(0, Integer(Length(mRun.Files)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleBulkFixProviderTests);

end.
