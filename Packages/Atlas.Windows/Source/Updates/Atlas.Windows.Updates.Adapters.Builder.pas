unit Atlas.Windows.Updates.Adapters.Builder;

// Platform-Feature "Updates" (#1519), Adapter: Packages mit MSBuild der
// eigenen Delphi-Installation bauen.
// - Voraussetzung: rsvars.bat und der Kommandozeilen-Compiler (dcc32.exe für
//   Win32, dcc64.exe für Win64) im bin-Ordner. Die Starter-Edition hat keinen
//   Kommandozeilen-Compiler; dann scheitert CanBuild mit Grund.
// - Gebaut wird über eine kleine Batch-Datei neben dem Projekt (rsvars.bat
//   setzt die Umgebung, MSBuild baut Release für die Plattform); so muss
//   keine Befehlszeile für cmd.exe gequotet werden.

interface

uses
  System.SysUtils,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Updates.Contract;

type
  TUpdateWindowsBuilder = class(TInterfacedObject, IUpdateBuilder)
  private
    FRegistry: IUpdateRegistry;
    FRunner: ICompilerProcess;
  public
    /// <summary>ARunner startet cmd.exe mit Pipe (TProcessRunner, vom Host erzeugt).</summary>
    constructor Create(const ARegistry: IUpdateRegistry; const ARunner: ICompilerProcess);
    function CanBuild(const ABdsVersion, APlatform: string; out AReason: string): Boolean;
    function Build(const ABdsVersion, APlatform, AProject: string; const AOnLine: TUpdateLog): Integer;
  end;

implementation

uses
  System.IOUtils;

function CompilerOf(const APlatform: string): string;
begin
  if SameText(APlatform, 'Win64') then
  begin
    Result := 'dcc64.exe';
  end
  else
  begin
    Result := 'dcc32.exe';
  end;
end;

function LineEvent(const AOnLine: TUpdateLog): TCompilerLineEvent;
begin
  // Eigene Routine: Delphi 12 weist gleich aufgebaute Methodenreferenzen nicht einander zu.
  Result :=
    procedure(const ALine: string)
    begin
      AOnLine(ALine);
    end;
end;

{ TUpdateWindowsBuilder }

constructor TUpdateWindowsBuilder.Create(const ARegistry: IUpdateRegistry; const ARunner: ICompilerProcess);
begin
  inherited Create;
  FRegistry := ARegistry;
  FRunner := ARunner;
end;

function TUpdateWindowsBuilder.CanBuild(const ABdsVersion, APlatform: string; out AReason: string): Boolean;
var
  mBin: string;
begin
  AReason := '';
  mBin := FRegistry.RootDir(ABdsVersion);
  if mBin = '' then
  begin
    AReason := CompilerOf(APlatform);
    Exit(False);
  end;
  mBin := IncludeTrailingPathDelimiter(mBin) + 'bin\';
  if not FileExists(mBin + 'rsvars.bat') or not FileExists(mBin + CompilerOf(APlatform)) then
  begin
    AReason := CompilerOf(APlatform);
    Exit(False);
  end;
  Result := True;
end;

function TUpdateWindowsBuilder.Build(const ABdsVersion, APlatform, AProject: string;
  const AOnLine: TUpdateLog): Integer;
var
  mScript: string;
  mRequest: TCompilerRequest;
begin
  mScript := ChangeFileExt(AProject, '.atlas-build.cmd');
  TFile.WriteAllText(mScript, '@echo off'#13#10 +
    'call "' + IncludeTrailingPathDelimiter(FRegistry.RootDir(ABdsVersion)) + 'bin\rsvars.bat"'#13#10 +
    'msbuild "' + AProject + '" /t:Build /p:Config=Release /p:Platform=' + APlatform +
    ' /nologo /v:minimal'#13#10 + 'exit /b %ERRORLEVEL%'#13#10, TEncoding.ANSI);
  mRequest := Default(TCompilerRequest);
  mRequest.Executable := GetEnvironmentVariable('ComSpec');
  mRequest.Arguments := TArray<string>.Create('/c', mScript);
  mRequest.WorkingDir := ExtractFileDir(AProject);
  Result := FRunner.Run(mRequest, LineEvent(AOnLine));
end;

end.
