unit Shell.Composition.RuntimeReport;

// Befehle atlas.server.runtimeReport und atlas.server.runtimeReport.clear (#74) der Komposition: Projekt zur URI aus
// den Arbeitsbereichen wie bei atlas.server.leakSetup; Map neben der EXE der Konfiguration Debug, wenn weder map
// noch exe kommen; Dateien im Projekt über die Quelldateien des Projekts (Unitname bzw. Dateiname). Logik in
// Atlas.Common.Diagnostics.RuntimeReport und Atlas.Common.Lsp.RuntimeReport.

interface

uses
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.RuntimeReport,
  Atlas.Common.Compiler.Results,
  Shell.Composition.LeakSetup;

type
  /// <summary>Was die Befehle außer den Diensten der Leckprüfung brauchen.</summary>
  TShellRuntimeReportServices = record
    /// <summary>Meldungen des letzten Berichts; gehört der Komposition.</summary>
    Results: TCompilerResults;
    /// <summary>Diagnosen der Dateien neu melden.</summary>
    Publish: TRuntimeReportPublish;
  end;

  TShellRuntimeReport = class
  public
    /// <summary>Meldet beide Befehle an.</summary>
    class procedure Attach(ACommands: TLspCommands; const ALeakServices: TShellLeakSetupServices;
      const AServices: TShellRuntimeReportServices); static;
    /// <summary>Datei aus AFiles zu Unit bzw. Dateiname (ohne Ordner, Groß-/Kleinschreibung egal); '' ohne.</summary>
    class function FileOf(const AFiles: TArray<string>; const AUnitName, AFileName: string): string; static;
    /// <summary>Ausgabedatei zum Hauptquelltext: .bpl für Packages, sonst .exe, im Ordner AOutputFolder.</summary>
    class function ExecutableOf(const AOutputFolder, AMainSource: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Leaks.Setup,
  Atlas.Common.Diagnostics.RuntimeReport;

type
  /// <summary>Projekt und Map aus den Arbeitsbereichen.</summary>
  TShellRuntimeReportFiles = class(TInterfacedObject, IRuntimeReportFiles)
  private
    FServices: TShellLeakSetupServices;
  public
    constructor Create(const AServices: TShellLeakSetupServices);
    procedure LoadSymbols(const AUri, AMapName, AExeName: string; ABase: UInt64; out ASymbols: TReportSymbols);
    function UnitFileOf(const AUri: string): TReportUnitFileFunc;
  end;

constructor TShellRuntimeReportFiles.Create(const AServices: TShellLeakSetupServices);
begin
  inherited Create;
  FServices := AServices;
end;

procedure TShellRuntimeReportFiles.LoadSymbols(const AUri, AMapName, AExeName: string; ABase: UInt64;
  out ASymbols: TReportSymbols);
var
  mExe, mReason: string;
  mInput: TLeakSetupInput;
begin
  mExe := AExeName;
  if (AMapName = '') and (mExe = '') and TShellLeakSetup.InputFor(FServices, AUri, mInput, mReason) and
    (mInput.OutputFolder <> '') then
  begin
    mExe := TShellRuntimeReport.ExecutableOf(mInput.OutputFolder, mInput.MainSource);
  end;
  TRuntimeReports.LoadSymbols(AMapName, mExe, ABase, ASymbols);
end;

function TShellRuntimeReportFiles.UnitFileOf(const AUri: string): TReportUnitFileFunc;
var
  mMainSource: string;
  mFiles: TArray<string>;
begin
  mFiles := nil;
  if not TShellLeakSetup.ProjectFilesOf(FServices, TDocumentUris.ToPath(AUri), mMainSource, mFiles) then
  begin
    mFiles := nil;
  end;
  Result :=
    function(const AUnitName, AFileName: string): string
    begin
      Result := TShellRuntimeReport.FileOf(mFiles, AUnitName, AFileName);
    end;
end;

{ TShellRuntimeReport }

class function TShellRuntimeReport.FileOf(const AFiles: TArray<string>; const AUnitName, AFileName: string): string;
var
  mFile, mName, mBareName: string;
begin
  // Berichte nennen Dateien mit Windows-Trennern, auch unter Linux.
  mBareName := ExtractFileName(StringReplace(AFileName, '\', PathDelim, [rfReplaceAll]));
  for mFile in AFiles do
  begin
    mName := ExtractFileName(mFile);
    if ((mBareName <> '') and SameText(mName, mBareName)) or
      ((AUnitName <> '') and SameText(ChangeFileExt(mName, ''), AUnitName) and
      SameText(ExtractFileExt(mName), '.pas')) then
    begin
      Exit(mFile);
    end;
  end;
  Result := '';
end;

class function TShellRuntimeReport.ExecutableOf(const AOutputFolder, AMainSource: string): string;
var
  mExtension: string;
begin
  mExtension := '.exe';
  if SameText(ExtractFileExt(AMainSource), '.dpk') then
  begin
    mExtension := '.bpl';
  end;
  Result := IncludeTrailingPathDelimiter(AOutputFolder) + ChangeFileExt(ExtractFileName(AMainSource), mExtension);
end;

/// <summary>Befehl je Aufruf; die Meldungen bleiben in AServices.Results.</summary>
function NewCommand(const ALeakServices: TShellLeakSetupServices;
  const AServices: TShellRuntimeReportServices): TLspRuntimeReport;
var
  mFiles: IRuntimeReportFiles;
begin
  // Erst in eine Interface-Variable: direkt an den const-Parameter übergeben zählt die Referenz nicht.
  mFiles := TShellRuntimeReportFiles.Create(ALeakServices);
  Result := TLspRuntimeReport.Create(mFiles, AServices.Results, AServices.Publish);
end;

class procedure TShellRuntimeReport.Attach(ACommands: TLspCommands; const ALeakServices: TShellLeakSetupServices;
  const AServices: TShellRuntimeReportServices);
var
  mLeakServices: TShellLeakSetupServices;
  mServices: TShellRuntimeReportServices;
begin
  mLeakServices := ALeakServices;
  mServices := AServices;
  ACommands.RegisterConcurrent(TLspRuntimeReport.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      mCommand: TLspRuntimeReport;
    begin
      mCommand := NewCommand(mLeakServices, mServices);
      try
        Result := mCommand.Execute(AArguments);
      finally
        mCommand.Free;
      end;
    end);
  ACommands.RegisterConcurrent(TLspRuntimeReport.cClearCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      mCommand: TLspRuntimeReport;
    begin
      mCommand := NewCommand(mLeakServices, mServices);
      try
        Result := mCommand.Clear;
      finally
        mCommand.Free;
      end;
    end);
end;

end.
