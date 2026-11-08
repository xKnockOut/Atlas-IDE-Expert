unit Shell.Compiler;

// Host-Rolle Shell: Kompilieren ohne Kommandozeilen-Compiler (#261).
// - TShellCompilerEditions erkennt je BDS-Wurzel und Version vorher, ob
//   dcc32/dcc64 da und nutzbar ist (Probelauf ohne Argumente, Lizenztext der
//   Starter bzw. Community Edition), und merkt sich das in
//   %LOCALAPPDATA%\Atlas\compiler-editions.json (Atlas.Common.Compiler.Edition).
// Ohne nutzbaren Kommandozeilen-Compiler baut eine laufende RAD Studio mit
// Atlas (Werkzeug build_project); einen eigenen Weg über eine Bau-IDE gibt
// es seit #1904 nicht mehr. Der Prozess kommt von außen, damit die Tests ohne
// Windows laufen.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.Edition,
  Atlas.Common.Compiler.Backend;

type
  /// <summary>Ein Compilerlauf mit dcc und fertigem Aufruf.</summary>
  TShellCompileJob = record
    Backend: TCompilerBackend;
    /// <summary>Über den Befehl „Projekt kompilieren“ statt nach dem Speichern.</summary>
    Manual: Boolean;
    /// <summary>Aufruf von dcc32/dcc64 (nur Backend Dcc).</summary>
    Request: TCompilerRequest;
    /// <summary>Eigener Ausgabeordner von dcc; entsteht erst vor dem Lauf.</summary>
    OutputDir: string;
    Project: string;
    Platform: string;
    BdsRoot: string;
    Version: string;
    Settings: TCompilerSettings;
  end;

  TShellCompilerEditions = class
  private
    FProcess: ICompilerProcess;
    FLogger: ILogger;
    FFileName: string;
    FLock: TObject;
    FCache: TCompilerEditionCache;
    FLoaded: Boolean;
    procedure EnsureLoaded;
    procedure Save;
    procedure Store(const ABdsRoot, AVersion, AStamp: string; AEdition: TCompilerEdition);
  public
    /// <summary>AFileName: Ablage des Zwischenspeichers ('' = nur im Speicher).</summary>
    constructor Create(const AProcess: ICompilerProcess; const ALogger: ILogger; const AFileName: string);
    destructor Destroy; override;
    /// <summary>Ausgabe zu AExecutable (dcc32/dcc64 unter ABdsRoot): aus dem Zwischenspeicher oder per Probelauf.
    /// Threadsicher.</summary>
    function Resolve(const ABdsRoot, AVersion, AExecutable: string): TCompilerEdition;
    /// <summary>Ein echter Lauf hat den Lizenztext gezeigt (#261): merken. Threadsicher.</summary>
    procedure Remember(const ABdsRoot, AVersion, AExecutable: string; AEdition: TCompilerEdition);
    /// <summary>Fingerabdruck einer Datei aus Größe und Zeitstempel; '' ohne Datei.</summary>
    class function StampOf(const AFileName: string): string; static;
    /// <summary>%LOCALAPPDATA%\Atlas\compiler-editions.json.</summary>
    class function DefaultFile: string; static;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils;

{ TShellCompilerEditions }

constructor TShellCompilerEditions.Create(const AProcess: ICompilerProcess; const ALogger: ILogger;
  const AFileName: string);
begin
  inherited Create;
  FProcess := AProcess;
  FLogger := ALogger;
  FFileName := AFileName;
  FLock := TObject.Create;
  FCache := TCompilerEditionCache.Create;
end;

destructor TShellCompilerEditions.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited;
end;

class function TShellCompilerEditions.DefaultFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TCompilerEditionCache.cFileName);
end;

class function TShellCompilerEditions.StampOf(const AFileName: string): string;
begin
  Result := '';
  try
    if TFile.Exists(AFileName) then
    begin
      Result := Format('%d-%s', [TFile.GetSize(AFileName),
        DateToISO8601(TFile.GetLastWriteTimeUtc(AFileName), True)]);
    end;
  except
    on Exception do
      Result := '';
  end;
end;

procedure TShellCompilerEditions.EnsureLoaded;
begin
  if FLoaded then
  begin
    Exit;
  end;
  FLoaded := True;
  if (FFileName = '') or not TFile.Exists(FFileName) then
  begin
    Exit;
  end;
  try
    FCache.Load(TFile.ReadAllText(FFileName, TEncoding.UTF8));
  except
    on E: Exception do
      FLogger.Warning('Erkannte Delphi-Ausgaben nicht lesbar: ' + E.ClassName);
  end;
end;

procedure TShellCompilerEditions.Save;
begin
  if FFileName = '' then
  begin
    Exit;
  end;
  try
    ForceDirectories(ExtractFileDir(FFileName));
    TFile.WriteAllText(FFileName, FCache.ToJson, TEncoding.UTF8);
  except
    on E: Exception do
      FLogger.Warning('Erkannte Delphi-Ausgaben nicht gespeichert: ' + E.ClassName);
  end;
end;

procedure TShellCompilerEditions.Store(const ABdsRoot, AVersion, AStamp: string; AEdition: TCompilerEdition);
var
  mEntry: TCompilerEditionEntry;
begin
  mEntry := Default(TCompilerEditionEntry);
  mEntry.Root := ABdsRoot;
  mEntry.Version := AVersion;
  mEntry.Edition := AEdition;
  mEntry.Stamp := AStamp;
  mEntry.Checked := DateToISO8601(Now, False);
  FCache.Store(mEntry);
  Save;
end;

function TShellCompilerEditions.Resolve(const ABdsRoot, AVersion, AExecutable: string): TCompilerEdition;
var
  mStamp: string;
  mOutput: TArray<string>;
  mRequest: TCompilerRequest;
  mExists: Boolean;
begin
  mStamp := StampOf(AExecutable);
  TMonitor.Enter(FLock);
  try
    EnsureLoaded;
    Result := FCache.Find(ABdsRoot, AVersion, mStamp);
    if Result <> TCompilerEdition.Unknown then
    begin
      Exit;
    end;
    mExists := mStamp <> '';
    mOutput := nil;
    if mExists then
    begin
      // Ohne Argumente nennt sich dcc mit Kopfzeile und Aufrufhilfe; Starter und Community melden den Lizenztext.
      mRequest := Default(TCompilerRequest);
      mRequest.Executable := AExecutable;
      mRequest.WorkingDir := ExtractFileDir(AExecutable);
      try
        FProcess.Run(mRequest,
          procedure(const ALine: string)
          begin
            mOutput := mOutput + [ALine];
          end);
      except
        on E: ECompilerCancelled do
          raise;
        on E: Exception do
          FLogger.Warning('Probelauf des Compilers fehlgeschlagen: ' + E.ClassName);
      end;
    end;
    Result := TCompilerEditions.Detect(mExists, mOutput);
    FLogger.Info(Format('Delphi %s: %s', [AVersion, TCompilerEditions.Describe(Result)]));
    // Unklar (keine Ausgabe) wird nicht gemerkt; der nächste Lauf prüft erneut.
    if Result <> TCompilerEdition.Unknown then
    begin
      Store(ABdsRoot, AVersion, mStamp, Result);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellCompilerEditions.Remember(const ABdsRoot, AVersion, AExecutable: string; AEdition: TCompilerEdition);
begin
  TMonitor.Enter(FLock);
  try
    EnsureLoaded;
    Store(ABdsRoot, AVersion, StampOf(AExecutable), AEdition);
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
