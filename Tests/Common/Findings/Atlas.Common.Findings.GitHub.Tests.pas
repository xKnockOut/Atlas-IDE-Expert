unit Atlas.Common.Findings.GitHub.Tests;

// Tests für --format github (#1432): Zeile je Befund, Schweregrade, Kodierung der Workflow-Befehle, Pfade relativ
// zur Quellwurzel und die Zusammenfassung für $GITHUB_STEP_SUMMARY.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGitHubAnnotationsTests = class
  public
    [Test]
    procedure WritesOneLinePerFinding;
    [Test]
    procedure MapsSeverities;
    [Test]
    procedure EscapesDataAndProperties;
    [Test]
    procedure PathRelativeToSourceRootWithSlashes;
    [Test]
    procedure SummaryCountsRulesAndLinksLines;
    [Test]
    procedure SummaryWithoutFindingsAndWithoutLinks;
    [Test]
    procedure LinkBaseNeedsAllValues;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Findings.Output,
  Atlas.Common.Findings.GitHub;

function NewFinding(const ARuleId: string; ASeverity: TRuleSeverity; ALine, AColumn, AEndColumn: Integer;
  const AMessage: string): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Severity := ASeverity;
  Result.Confidence := TRuleConfidence.High;
  Result.Range := TTextRange.Create(ALine, AColumn, ALine, AEndColumn);
  Result.Message := AMessage;
end;

{ TGitHubAnnotationsTests }

procedure TGitHubAnnotationsTests.WritesOneLinePerFinding;
var
  mFiles: TArray<TCheckedFile>;
begin
  // Zeile 12, Spalte 3 (ab 1), Bereich bis Spalte 9.
  mFiles := TArray<TCheckedFile>.Create(TCheckedFile.Create('Src\A.pas', 'C:\P\Src\A.pas',
    TArray<TRuleFinding>.Create(NewFinding('empty-except', TRuleSeverity.Warning, 11, 2, 9, 'Leerer except-Block'))));
  Assert.AreEqual('::warning file=Src/A.pas,line=12,col=3,endLine=12,endColumn=9,title=empty-except::' +
    'Leerer except-Block' + sLineBreak, TGitHubAnnotations.Render(mFiles, 'C:\P'));
  mFiles := nil;
end;

procedure TGitHubAnnotationsTests.MapsSeverities;
begin
  Assert.AreEqual('error', TGitHubAnnotations.Command(TRuleSeverity.Error));
  Assert.AreEqual('warning', TGitHubAnnotations.Command(TRuleSeverity.Warning));
  Assert.AreEqual('notice', TGitHubAnnotations.Command(TRuleSeverity.Hint));
  Assert.AreEqual('notice', TGitHubAnnotations.Command(TRuleSeverity.Information));
end;

procedure TGitHubAnnotationsTests.EscapesDataAndProperties;
begin
  Assert.AreEqual('100%25 sicher%0D%0Azweite: Zeile, mit Komma', TGitHubAnnotations.EscapeData(
    '100% sicher'#13#10'zweite: Zeile, mit Komma'));
  Assert.AreEqual('C%3A/Ordner%2C neu/A.pas', TGitHubAnnotations.EscapeProperty('C:/Ordner, neu/A.pas'));
  Assert.AreEqual('50%25%0A', TGitHubAnnotations.EscapeProperty('50%'#10));
end;

procedure TGitHubAnnotationsTests.PathRelativeToSourceRootWithSlashes;
begin
  Assert.AreEqual('Src/Unter/A.pas', TGitHubAnnotations.PathOf(
    TCheckedFile.Create('Unter\A.pas', 'C:\P\Src\Unter\A.pas', nil), 'c:\p\'));
  // Außerhalb der Quellwurzel bzw. ohne sie: der Pfad aus der Prüfung.
  Assert.AreEqual('../Lib/B.pas', TGitHubAnnotations.PathOf(
    TCheckedFile.Create('..\Lib\B.pas', 'C:\Lib\B.pas', nil), 'C:\P'));
  Assert.AreEqual('Src/C.pas', TGitHubAnnotations.PathOf(TCheckedFile.Create('Src\C.pas', 'C:\P\Src\C.pas', nil), ''));
end;

procedure TGitHubAnnotationsTests.SummaryCountsRulesAndLinksLines;
var
  mFiles: TArray<TCheckedFile>;
  mSummary: string;
begin
  mFiles := TArray<TCheckedFile>.Create(
    TCheckedFile.Create('Src\A.pas', 'C:\P\Src\A.pas', TArray<TRuleFinding>.Create(
      NewFinding('empty-except', TRuleSeverity.Warning, 4, 0, 3, 'Leer | mit Strich'),
      NewFinding('result-not-set', TRuleSeverity.Error, 9, 0, 3, 'Kein Result'))),
    TCheckedFile.Create('Src\B.pas', 'C:\P\Src\B.pas', TArray<TRuleFinding>.Create(
      NewFinding('empty-except', TRuleSeverity.Hint, 1, 0, 3, 'Noch einer'))),
    TCheckedFile.Create('Src\C.pas', 'C:\P\Src\C.pas', nil));
  mSummary := TGitHubAnnotations.Summary(mFiles, 'C:\P', 'https://github.com/o/r/blob/abc/');
  Assert.IsTrue(mSummary.Contains('3 '), mSummary);
  Assert.IsTrue(mSummary.Contains('| `empty-except` | 0 | 1 | 1 |'), mSummary);
  Assert.IsTrue(mSummary.Contains('| `result-not-set` | 1 | 0 | 0 |'), mSummary);
  Assert.IsTrue(mSummary.Contains('[Src/A.pas:10](https://github.com/o/r/blob/abc/Src/A.pas#L10)'), mSummary);
  Assert.IsTrue(mSummary.Contains('Leer \| mit Strich'), mSummary);
  mFiles := nil;
end;

procedure TGitHubAnnotationsTests.SummaryWithoutFindingsAndWithoutLinks;
var
  mFiles: TArray<TCheckedFile>;
  mSummary: string;
begin
  mSummary := TGitHubAnnotations.Summary(
    TArray<TCheckedFile>.Create(TCheckedFile.Create('A.pas', 'C:\P\A.pas', nil)), 'C:\P', '');
  Assert.IsFalse(mSummary.Contains('|'), 'ohne Befunde keine Tabelle: ' + mSummary);
  mFiles := TArray<TCheckedFile>.Create(TCheckedFile.Create('A.pas', 'C:\P\A.pas',
    TArray<TRuleFinding>.Create(NewFinding('magic-number', TRuleSeverity.Hint, 0, 0, 2, 'Zahl'))));
  mSummary := TGitHubAnnotations.Summary(mFiles, 'C:\P', '');
  Assert.IsTrue(mSummary.Contains('| notice | A.pas:1 | `magic-number` | Zahl |'), mSummary);
  Assert.IsFalse(mSummary.Contains(']('), 'ohne Basis kein Link');
  mFiles := nil;
end;

procedure TGitHubAnnotationsTests.LinkBaseNeedsAllValues;
begin
  Assert.AreEqual('https://github.com/o/r/blob/abc/', TGitHubAnnotations.LinkBase('https://github.com/', 'o/r',
    'abc'));
  Assert.AreEqual('', TGitHubAnnotations.LinkBase('https://github.com', '', 'abc'));
  Assert.AreEqual('', TGitHubAnnotations.LinkBase('https://github.com', 'o/r', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TGitHubAnnotationsTests);

end.
