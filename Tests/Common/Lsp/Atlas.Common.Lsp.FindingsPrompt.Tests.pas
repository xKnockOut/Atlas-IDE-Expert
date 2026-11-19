unit Atlas.Common.Lsp.FindingsPrompt.Tests;

// Tests für den Befehl atlas.server.findingsPrompt (#2570): Befund der Prüfung mit weiteren Stellen und Pfad
// relativ zur Konfiguration, Angaben des Plugins für Compilermeldungen und ungeprüfte Dateien, jede Datei einmal
// geprüft, Obergrenze, Fehler ohne Befunde.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspFindingsPromptTests = class
  public
    [Test]
    procedure CheckedFindingBringsRelatedAndRelativePath;
    [Test]
    procedure ClientDataForCompilerMessages;
    [Test]
    procedure EachFileCheckedOnce;
    [Test]
    procedure LimitFromArguments;
    [Test]
    procedure RefusesMissingFindings;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Lsp.Baseline,
  Atlas.Common.Lsp.FindingsPrompt;

const
  cUnit = 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10'end;'#13#10'end.';

var
  Checks: Integer;

function CheckFor(const AFileName: string; out ACheck: TLspBaselineCheck): Boolean;
var
  mFinding: TRuleFinding;
  mRelated: TRuleRelated;
begin
  ACheck := Default(TLspBaselineCheck);
  Result := SameText(ExtractFileExt(AFileName), '.pas');
  if not Result then
  begin
    Exit;
  end;
  Inc(Checks);
  ACheck.Text := cUnit;
  ACheck.RelativePath := 'Src/' + ExtractFileName(AFileName);
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'uses-cycle';
  mFinding.Range := TTextRange.Create(3, 0, 3, 9);
  mFinding.Message := 'Zyklus aus der Prüfung';
  mFinding.Severity := TRuleSeverity.Warning;
  mFinding.Confidence := TRuleConfidence.Medium;
  mRelated := Default(TRuleRelated);
  mRelated.FileName := 'B.pas';
  mRelated.Range := TTextRange.Create(4, 0, 4, 1);
  mRelated.Message := 'uses U';
  mFinding.Related := TArray<TRuleRelated>.Create(mRelated);
  ACheck.Findings := TArray<TRuleFinding>.Create(mFinding);
end;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := 'object Form1: TForm1'#13#10'  Left = 0'#13#10'end';
  Result := SameText(ExtractFileExt(AFileName), '.dfm');
end;

function Execute(const AArguments: string): TJSONObject;
var
  mPrompt: TLspFindingsPrompt;
  mArguments: TJSONArray;
begin
  mPrompt := TLspFindingsPrompt.Create(CheckFor, ReadText);
  mArguments := TJSONObject.ParseJSONValue(AArguments) as TJSONArray;
  try
    Result := mPrompt.Execute(mArguments) as TJSONObject;
  finally
    mArguments.Free;
    mPrompt.Free;
  end;
end;

{ TLspFindingsPromptTests }

procedure TLspFindingsPromptTests.CheckedFindingBringsRelatedAndRelativePath;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  Checks := 0;
  mAnswer := Execute('[{"findings": [{"file": "C:\\P\\U.pas", "line": 3, "character": 0, "rule": "uses-cycle", ' +
    '"message": "Zyklus aus dem Plugin", "severity": "error"}]}]');
  try
    mText := mAnswer.GetValue<string>('text');
    Assert.AreEqual(1, mAnswer.GetValue<Integer>('count'));
  finally
    mAnswer.Free;
  end;
  Assert.Contains(mText, 'Datei: `Src/U.pas`, Zeile 4, Spalte 1');
  Assert.Contains(mText, 'Zyklus aus der Prüfung');
  Assert.Contains(mText, '  - `B.pas`, Zeile 5: uses U');
  Assert.Contains(mText, '>    4 | procedure P;');
  Assert.Contains(mText, 'Prüfen mit: `check_code` (file: `Src/U.pas`)');
end;

procedure TLspFindingsPromptTests.ClientDataForCompilerMessages;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  Checks := 0;
  mAnswer := Execute('[{"findings": [{"file": "C:\\P\\U.pas", "line": 5, "character": 2, "rule": "E2003", ' +
    '"message": "Undeklarierter Bezeichner", "severity": "error", "compiler": true}]}]');
  try
    mText := mAnswer.GetValue<string>('text');
  finally
    mAnswer.Free;
  end;
  Assert.StartsWith('## Compilermeldung E2003', mText);
  Assert.Contains(mText, 'Schweregrad: error');
  Assert.Contains(mText, 'Meldung: Undeklarierter Bezeichner');
  Assert.Contains(mText, '>    6 | end;');
  Assert.IsFalse(mText.Contains('Konfidenz'), 'Compilermeldung ohne Konfidenz');
end;

procedure TLspFindingsPromptTests.EachFileCheckedOnce;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  Checks := 0;
  mAnswer := Execute('[{"findings": [' +
    '{"file": "U.pas", "line": 3, "rule": "uses-cycle", "message": "a", "severity": "warning"},' +
    '{"file": "U.pas", "line": 1, "rule": "test-regel", "message": "b", "severity": "hint"},' +
    '{"file": "F.dfm", "line": 1, "rule": "dfm-regel", "message": "c", "severity": "info"}]}]');
  try
    mText := mAnswer.GetValue<string>('text');
    Assert.AreEqual(3, mAnswer.GetValue<Integer>('count'));
  finally
    mAnswer.Free;
  end;
  Assert.AreEqual(1, Checks, 'U.pas einmal geprüft');
  Assert.StartsWith('# 3 Befunde in 2 Dateien beheben', mText);
  Assert.Contains(mText, '## Datei `Src/U.pas`');
  Assert.Contains(mText, '## Datei `F.dfm`');
  Assert.Contains(mText, '>    2 |   Left = 0');
end;

procedure TLspFindingsPromptTests.LimitFromArguments;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  mAnswer := Execute('[{"limit": 1, "findings": [' +
    '{"file": "U.pas", "line": 3, "rule": "uses-cycle", "message": "a", "severity": "warning"},' +
    '{"file": "U.pas", "line": 1, "rule": "test-regel", "message": "b", "severity": "hint"}]}]');
  try
    mText := mAnswer.GetValue<string>('text');
  finally
    mAnswer.Free;
  end;
  Assert.Contains(mText, 'Weitere 1 Befunde sind hier nicht aufgeführt');
end;

procedure TLspFindingsPromptTests.RefusesMissingFindings;
begin
  Assert.WillRaise(
    procedure
    begin
      Execute('[{"files": ["U.pas"]}]').Free;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFindingsPromptTests);

end.
