unit Shell.Composition.Baselines.Tests;

// Baselines des Servers: Dateizugriffe (lesen, atomar schreiben, beiseitelegen) und das Neuprüfen der offenen
// Dokumente nach dem Schreiben einer Baseline.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Baselines;

type
  [TestFixture]
  TShellBaselinesTests = class
  private
    FFolder: string;
    FRefreshes: Integer;
    function NewServices: TShellBaselineServices;
    procedure CountRefresh;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Geschriebener Text kommt beim Lesen unverändert zurück, die Datei existiert danach.</summary>
    [Test]
    procedure FilesWriteAndRead;
    /// <summary>Eine fehlende Datei liest sich als leer und meldet False.</summary>
    [Test]
    procedure FilesReadMissing;
    /// <summary>Beiseitelegen benennt in .defekt um.</summary>
    [Test]
    procedure FilesSetAside;
    /// <summary>Nach dem Schreiben einer der beiden Baselines prüfen die offenen Dokumente neu.</summary>
    [Test]
    procedure WrittenRefreshesDiagnostics;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Baseline,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Pascal.Preprocessor;

function NoMetricsSource(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean;
begin
  ASource := Default(TLspMetricsSource);
  Result := False;
end;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoRuleContext(const AUri: string; out AContext: TRuleCheckContext): Boolean;
begin
  AContext := Default(TRuleCheckContext);
  Result := False;
end;

function NoDefines(const AUri: string; out ADefines: TArray<string>): Boolean;
begin
  ADefines := nil;
  Result := False;
end;

function NoIncludeResolver(const AUri: string): TIncludeResolver;
begin
  Result := nil;
end;

procedure TShellBaselinesTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-baselines-' + IntToStr(Random(MaxInt)));
  ForceDirectories(FFolder);
  FRefreshes := 0;
end;

procedure TShellBaselinesTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TShellBaselinesTests.CountRefresh;
begin
  Inc(FRefreshes);
end;

function TShellBaselinesTests.NewServices: TShellBaselineServices;
begin
  Result := Default(TShellBaselineServices);
  Result.MetricsSourceFor := NoMetricsSource;
  Result.ReadText := NoText;
  Result.RuleContextFor := NoRuleContext;
  Result.DefinesFor := NoDefines;
  Result.IncludeResolverFor := NoIncludeResolver;
  Result.RefreshLater := CountRefresh;
end;

procedure TShellBaselinesTests.FilesWriteAndRead;
var
  mFiles: TLspBaselineFiles;
  mFileName, mText: string;
begin
  mFiles := BaselineFiles;
  mFileName := TPath.Combine(FFolder, 'atlas-baseline.json');
  mFiles.Write(mFileName, '{"format": 1, "ä": true}');
  Assert.IsTrue(mFiles.Exists(mFileName));
  Assert.IsTrue(mFiles.Read(mFileName, mText));
  Assert.AreEqual('{"format": 1, "ä": true}', mText);
end;

procedure TShellBaselinesTests.FilesReadMissing;
var
  mText: string;
begin
  mText := 'alt';
  Assert.IsFalse(BaselineFiles.Read(TPath.Combine(FFolder, 'fehlt.json'), mText));
  Assert.AreEqual('', mText);
end;

procedure TShellBaselinesTests.FilesSetAside;
var
  mFiles: TLspBaselineFiles;
  mFileName, mTarget: string;
begin
  mFiles := BaselineFiles;
  mFileName := TPath.Combine(FFolder, 'atlas-baseline.json');
  mFiles.Write(mFileName, 'kaputt');
  Assert.IsTrue(mFiles.SetAside(mFileName, mTarget));
  Assert.AreEqual(mFileName + '.defekt', mTarget);
  Assert.IsFalse(TFile.Exists(mFileName));
  Assert.IsTrue(TFile.Exists(mTarget));
end;

procedure TShellBaselinesTests.WrittenRefreshesDiagnostics;
var
  mBaselines: TShellBaselines;
begin
  mBaselines := TShellBaselines.Create(NewServices);
  try
    mBaselines.Baseline.OnWritten('a.json');
    mBaselines.CompilerBaseline.OnWritten('a.json');
    Assert.AreEqual(2, FRefreshes);
  finally
    mBaselines.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellBaselinesTests);

end.
