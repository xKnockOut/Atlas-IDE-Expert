unit Shell.Composition.Baselines;

// Internals-Rolle Shell: Baselines des Servers (#97, #530) und die Sammelkorrektur (#1352). Die Komposition reicht
// Metrikquelle, Prüfkontext, Defines und Include-Suche als Dienste herein; Dateien liest und schreibt die Unit
// selbst.

interface

uses
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Baseline,
  Atlas.Common.Lsp.BulkFix,
  Atlas.Common.Lsp.CompilerBaseline,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Pascal.Preprocessor;

type
  TShellMetricsSourceFunc = reference to function(const AFileName: string; AProject: Boolean;
    out ASource: TLspMetricsSource): Boolean;
  TShellReadTextFunc = reference to function(const AFileName: string; out AText: string): Boolean;
  TShellRuleContextFunc = reference to function(const AUri: string; out AContext: TRuleCheckContext): Boolean;
  TShellDefinesFunc = reference to function(const AUri: string; out ADefines: TArray<string>): Boolean;
  TShellIncludeResolverFunc = reference to function(const AUri: string): TIncludeResolver;
  TShellRefreshProc = reference to procedure;

  /// <summary>Was die Baselines von der Komposition brauchen.</summary>
  TShellBaselineServices = record
    MetricsSourceFor: TShellMetricsSourceFunc;
    ReadText: TShellReadTextFunc;
    RuleContextFor: TShellRuleContextFunc;
    DefinesFor: TShellDefinesFunc;
    IncludeResolverFor: TShellIncludeResolverFunc;
    /// <summary>Offene Dokumente bald neu prüfen.</summary>
    RefreshLater: TShellRefreshProc;
  end;

  /// <summary>Baseline der Befunde, Baseline der Compilermeldungen und Sammelkorrektur.</summary>
  TShellBaselines = class
  private
    FServices: TShellBaselineServices;
    FBaseline: TLspBaseline;
    FBulkFix: TLspBulkFix;
    FCompilerBaseline: TLspCompilerBaseline;
    function MetricsSource(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function CheckFor(const AFileName: string; out ACheck: TLspBaselineCheck): Boolean;
    function BulkFixInputFor(const AFileName: string; out AInput: TLspBulkFixInput): Boolean;
    procedure Written(AFileName: string);
  public
    constructor Create(const AServices: TShellBaselineServices);
    destructor Destroy; override;
    property Baseline: TLspBaseline read FBaseline;
    property BulkFix: TLspBulkFix read FBulkFix;
    property CompilerBaseline: TLspCompilerBaseline read FCompilerBaseline;
  end;

/// <summary>Dateizugriffe der Baselines: lesen mit erkannter Kodierung, atomar schreiben, defekte beiseitelegen.</summary>
function BaselineFiles: TLspBaselineFiles;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Checker,
  Shell.Platform;

function BaselineFileExists(const AFileName: string): Boolean;
begin
  Result := TFile.Exists(AFileName);
end;

function ReadBaselineFile(const AFileName: string; out AText: string): Boolean;
var
  mFileFormat: TFileFormat;
begin
  Result := TFile.Exists(AFileName);
  if Result then
  begin
    AText := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  end
  else
  begin
    AText := '';
  end;
end;

procedure WriteBaselineFile(const AFileName, AText: string);
var
  mDisk: IIndexFileSystem;
  mError: string;
begin
  // Atomar wie der Index-Cache (Bericht N3): Der Arbeitsbereich liest die Datei nach dem Zeitstempel und sah
  // mit TFile.WriteAllText womöglich einen halben Stand; ein Abbruch hinterließ eine kaputte Baseline.
  // UTF-8 ohne BOM wie bisher.
  mDisk := TDiskIndexFileSystem.Create;
  if not mDisk.WriteBytes(AFileName, TEncoding.UTF8.GetBytes(AText), mError) then
  begin
    raise EInOutError.Create('Baseline nicht geschrieben (' + mError + ')');
  end;
end;

function SetBaselineAside(const AFileName: string; out ATarget: string): Boolean;
begin
  ATarget := AFileName + '.defekt';
  // Eine ältere beiseitegelegte Datei wird in einem Schritt ersetzt: Die jüngere hat den neueren Stand.
  Result := TShellPlatform.MoveReplacing(AFileName, ATarget);
end;

function BaselineFiles: TLspBaselineFiles;
begin
  Result := Default(TLspBaselineFiles);
  Result.Exists := BaselineFileExists;
  Result.Read := ReadBaselineFile;
  Result.Write := WriteBaselineFile;
  Result.SetAside := SetBaselineAside;
end;

constructor TShellBaselines.Create(const AServices: TShellBaselineServices);
begin
  inherited Create;
  FServices := AServices;
  // Baseline (#97): dieselben Dateien wie die Metriken, Prüfung wie im Editor (Regeln, Index, Formulardatei).
  FBaseline := TLspBaseline.Create(MetricsSource, CheckFor, BaselineFiles);
  // Der Arbeitsbereich liest die Datei beim nächsten Prüfen neu; offene Dokumente gleich neu prüfen.
  FBaseline.OnWritten := Written;
  // Sammelkorrektur für das Plugin (#1352): Text, Regeln, Projekt, Index und Baseline wie die Editor-Prüfung, aber
  // nicht Live (unused-uses meldet sich nur außerhalb des Editors) und mit den Symbolen des Projekts wie der Linter.
  FBulkFix := TLspBulkFix.Create(BulkFixInputFor);
  // Compilermeldungen in derselben Baseline (#530): Text wie im Editor, offene Dokumente vor der Platte.
  FCompilerBaseline := TLspCompilerBaseline.Create(MetricsSource, ReadText, BaselineFiles);
  FCompilerBaseline.OnWritten := Written;
end;

destructor TShellBaselines.Destroy;
begin
  FreeAndNil(FCompilerBaseline);
  FreeAndNil(FBaseline);
  FreeAndNil(FBulkFix);
  inherited Destroy;
end;

function TShellBaselines.MetricsSource(const AFileName: string; AProject: Boolean;
  out ASource: TLspMetricsSource): Boolean;
begin
  Result := FServices.MetricsSourceFor(AFileName, AProject, ASource);
end;

function TShellBaselines.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FServices.ReadText(AFileName, AText);
end;

function TShellBaselines.CheckFor(const AFileName: string; out ACheck: TLspBaselineCheck): Boolean;
var
  mContext: TRuleCheckContext;
  mTree: TSyntaxTree;
  mExtension: string;
begin
  ACheck := Default(TLspBaselineCheck);
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := ((mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk')) and
    ReadText(AFileName, ACheck.Text) and FServices.RuleContextFor(TDocumentUris.FromPath(AFileName), mContext) and
    (mContext.RelativePath <> '');
  if not Result then
  begin
    Exit;
  end;
  ACheck.RelativePath := mContext.RelativePath;
  mTree := TSyntaxTreeCache.Parse(ACheck.Text);
  try
    ACheck.Findings := TLspSyntaxDiagnostics.RuleFindings(ACheck.Text, mTree, mContext);
  finally
    mTree.Free;
  end;
end;

function TShellBaselines.BulkFixInputFor(const AFileName: string; out AInput: TLspBulkFixInput): Boolean;
var
  mContext: TRuleCheckContext;
  mDefines: TArray<string>;
  mUri: string;
begin
  AInput := Default(TLspBulkFixInput);
  mUri := TDocumentUris.FromPath(AFileName);
  Result := ReadText(AFileName, AInput.Text) and FServices.RuleContextFor(mUri, mContext);
  if not Result then
  begin
    Exit;
  end;
  AInput.Rules := mContext.Rules;
  AInput.Settings := mContext.Settings;
  AInput.RelativePath := mContext.RelativePath;
  if AInput.RelativePath = '' then
  begin
    AInput.RelativePath := ExtractFileName(AFileName);
  end;
  AInput.Baseline := mContext.Baseline;
  AInput.Project.Application := mContext.Application;
  AInput.Project.Name := mContext.ProjectName;
  AInput.Project.AutoCreateForms := mContext.AutoCreateForms;
  AInput.Project.ProjectMainSource := mContext.ProjectMainSource;
  AInput.Project.FileName := AFileName;
  AInput.Project.Services := mContext.Services;
  if not FServices.DefinesFor(mUri, mDefines) then
  begin
    mDefines := nil;
  end;
  AInput.Source := TCheckSource.Create(AFileName, mDefines, FServices.IncludeResolverFor(mUri));
end;

procedure TShellBaselines.Written(AFileName: string);
begin
  FServices.RefreshLater();
end;

end.
