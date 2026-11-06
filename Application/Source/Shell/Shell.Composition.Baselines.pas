unit Shell.Composition.Baselines;

// Internals-Rolle Shell: Baselines des Servers (#97, #530) und die Sammelkorrektur (#1352). Die Komposition reicht
// Metrikquelle, Prüfkontext, Defines und Include-Suche als Dienste herein; Dateien liest und schreibt die Unit
// selbst. Die Befehle dazu schreiben nur Zahlen ins Log, keine Pfade.

interface

uses
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Baseline,
  Atlas.Common.Lsp.BulkFix,
  Atlas.Common.Lsp.CompilerBaseline,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Pascal.Preprocessor;

type
  TShellReadTextFunc = reference to function(const AFileName: string; out AText: string): Boolean;
  TShellRuleContextFunc = reference to function(const AUri: string; out AContext: TRuleCheckContext): Boolean;
  TShellIncludeResolverFunc = reference to function(const AUri: string): TIncludeResolver;
  TShellRefreshProc = reference to procedure;

  /// <summary>Was die Baselines von der Komposition brauchen.</summary>
  TShellBaselineServices = record
    MetricsSourceFor: TLspMetricsSourceFunc;
    ReadText: TShellReadTextFunc;
    RuleContextFor: TShellRuleContextFunc;
    DefinesFor: TDefinesProvider;
    IncludeResolverFor: TShellIncludeResolverFunc;
    /// <summary>Offene Dokumente bald neu prüfen.</summary>
    RefreshLater: TShellRefreshProc;
    Logger: ILogger;
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
    function RunBaseline(const AArguments: TJSONArray): TJSONValue;
    function RunBulkFix(const AArguments: TJSONArray): TJSONValue;
    function RunCompilerBaselineAdd(const AArguments: TJSONArray): TJSONValue;
    function RunCompilerBaselineClassify(const AArguments: TJSONArray): TJSONValue;
  public
    constructor Create(const AServices: TShellBaselineServices);
    destructor Destroy; override;
    /// <summary>Baseline aktualisieren, Sammelkorrektur und Compilermeldungen in die Baseline.</summary>
    procedure RegisterCommands(ACommands: TLspCommands);
    /// <summary>Compilermeldungen einordnen (Schnellbefehl im Editor).</summary>
    procedure RegisterClassifyCommand(ACommands: TLspCommands);
    property Baseline: TLspBaseline read FBaseline;
    property CompilerBaseline: TLspCompilerBaseline read FCompilerBaseline;
  end;

/// <summary>Dateizugriffe der Baselines: lesen mit erkannter Kodierung, atomar schreiben, defekte beiseitelegen.</summary>
function BaselineFiles: TLspBaselineFiles;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Diagnostics,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Checker,
  Shell.Platform,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TBaselineHostText = (NotWritten);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TBaselineHostText] of TAtlasText = (
    (De: 'Baseline nicht geschrieben (%s)'; En: 'Baseline not written (%s)'));

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
    raise EInOutError.Create(cTexts[TBaselineHostText.NotWritten].Fmt([mError]));
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

procedure TShellBaselines.RegisterCommands(ACommands: TLspCommands);
begin
  ACommands.Register(TLspBaseline.Command, RunBaseline);
  ACommands.Register(TLspBulkFix.Command, RunBulkFix);
  ACommands.Register(TLspCompilerBaseline.AddCommand, RunCompilerBaselineAdd);
end;

procedure TShellBaselines.RegisterClassifyCommand(ACommands: TLspCommands);
begin
  ACommands.Register(TLspCompilerBaseline.ClassifyCommand, RunCompilerBaselineClassify);
end;

function TShellBaselines.RunBaseline(const AArguments: TJSONArray): TJSONValue;
var
  mWatch: TStopwatch;
  mAnswer: TJSONObject;
begin
  // Prüft das ganze Projekt: in großen Altprojekten dauert das; nur Zahlen ins Log, keine Pfade.
  mWatch := TStopwatch.StartNew;
  Result := FBaseline.Execute(AArguments);
  if Result is TJSONObject then
  begin
    mAnswer := TJSONObject(Result);
    FServices.Logger.Info(Format('Baseline aktualisiert: %d Treffer, %d Dateien geprüft ' +
      '(%d neu, %d entfernt, %d ohne Datei), %d ms', [mAnswer.GetValue<Integer>('total', -1),
      mAnswer.GetValue<Integer>('files', -1), mAnswer.GetValue<Integer>('added', -1),
      mAnswer.GetValue<Integer>('removed', -1), mAnswer.GetValue<Integer>('orphaned.count', -1),
      mWatch.ElapsedMilliseconds]));
  end;
end;

function TShellBaselines.RunBulkFix(const AArguments: TJSONArray): TJSONValue;
var
  mWatch: TStopwatch;
  mSummary: string;
begin
  // Nur die Vorschau; geschrieben wird im Plugin. Ins Log nur Zahlen und Regeln, keine Pfade.
  mWatch := TStopwatch.StartNew;
  Result := FBulkFix.Execute(AArguments);
  if not (Result is TJSONObject) then
  begin
    Exit;
  end;
  mSummary := TJSONObject(Result).GetValue<string>('summary', '');
  if Pos(sLineBreak, mSummary) > 0 then
  begin
    mSummary := Copy(mSummary, 1, Pos(sLineBreak, mSummary) - 1);
  end;
  FServices.Logger.Info(Format('Sammelkorrektur berechnet (%s), %d ms', [mSummary, mWatch.ElapsedMilliseconds]));
end;

function TShellBaselines.RunCompilerBaselineAdd(const AArguments: TJSONArray): TJSONValue;
var
  mAnswer: TJSONObject;
begin
  Result := FCompilerBaseline.ExecuteAdd(AArguments);
  if Result is TJSONObject then
  begin
    mAnswer := TJSONObject(Result);
    FServices.Logger.Info(Format('Compilermeldungen in die Baseline: %d Einträge (%d neu, %d entfernt)',
      [mAnswer.GetValue<Integer>('total', -1), mAnswer.GetValue<Integer>('added', -1),
      mAnswer.GetValue<Integer>('removed', -1)]));
  end;
end;

function TShellBaselines.RunCompilerBaselineClassify(const AArguments: TJSONArray): TJSONValue;
begin
  Result := FCompilerBaseline.ExecuteClassify(AArguments);
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.Baselines', cTexts);

end.
