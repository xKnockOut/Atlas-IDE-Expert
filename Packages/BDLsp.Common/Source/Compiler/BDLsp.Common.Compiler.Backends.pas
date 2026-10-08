unit BDLsp.Common.Compiler.Backends;

// Auswahl des Compiler-Backends (#261). Ohne Kommandozeilenlizenz (Starter
// Edition) gibt es dcc32/dcc64 nicht oder es verweigert den Dienst; dann
// übersetzt eine eigene Scratch-IDE über cc.ps1.
//
// - TCompilerEditionProbe erkennt die Edition vorher: Gibt es bin\dcc32.exe
//   bzw. dcc64.exe, und enthält eine Probe-Ausgabe den Lizenztext der Starter-
//   bzw. Community Edition? Das Ergebnis wird je BDS-Wurzel und Version
//   zwischengespeichert.
// - TCompilerBackendChoice wählt aus Einstellung und Edition dcc, ide oder off
//   und liefert den Grund für die sichtbare Meldung.
// - TIdeCompilerCommand baut die Aufrufe von cc.ps1 (immer mit -Instance, die
//   IDE des Benutzers wird nie angesprochen) und liest das logFile mit
//   TCompilerOutputParser.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Compiler.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Unknown: noch nicht geprüft; CommandLine: dcc nutzbar; NoCommandLine: Starter/Community
  /// (dcc fehlt oder verweigert); Missing: keine RAD-Studio-Installation gefunden.</summary>
  TCompilerEdition = (Unknown, CommandLine, NoCommandLine, Missing);
  {$SCOPEDENUMS OFF}

  TCompilerFileExists = reference to function(const APath: string): Boolean;

  TCompilerEditionProbe = class
  private
    FLock: TObject;
    FCache: TDictionary<string, TCompilerEdition>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Enthält die Ausgabe von dcc den Lizenztext der Starter/Community Edition?</summary>
    class function IsLicenseRefusal(const AOutput: string): Boolean; static;
    /// <summary>Edition unter ABdsRoot: AFileExists prüft bin\dcc32.exe/dcc64.exe, AProbeOutput ist die
    /// Ausgabe eines Probelaufs von dcc ('' = nicht gelaufen).</summary>
    class function Detect(const ABdsRoot: string; const AFileExists: TCompilerFileExists;
      const AProbeOutput: string): TCompilerEdition; static;
    /// <summary>Zwischengespeicherte Edition für Wurzel und Version; False ohne Eintrag.</summary>
    function TryGet(const ABdsRoot, AVersion: string; out AEdition: TCompilerEdition): Boolean;
    procedure Store(const ABdsRoot, AVersion: string; AEdition: TCompilerEdition);
  end;

  /// <summary>Gewähltes Backend; Backend ist nie Auto.</summary>
  TCompilerBackendChoice = record
    Backend: TCompilerBackend;
    /// <summary>Grund, wenn Backend = Off, sonst ''. Für window/showMessage und den Status.</summary>
    Reason: string;
    /// <summary>Kurztext für den Status, z. B. "Compiler: nicht verfügbar (Starter Edition)".</summary>
    StatusText: string;
    /// <summary>Darf nach dem Speichern kompiliert werden? Bei ide nicht (Startzeit der IDE).</summary>
    OnSave: Boolean;
    class function Choose(const ASettings: TCompilerSettings; AEdition: TCompilerEdition;
      AIdeCommandExists: Boolean): TCompilerBackendChoice; static;
  end;

  TIdeCompilerCommand = class
  public
    /// <summary>cc.ps1 start: eigene Scratch-IDE für AProject.</summary>
    class function Start(const AScript, AProject: string): TCompilerRequest; static;
    /// <summary>pid der Scratch-IDE aus der Ausgabe von "cc.ps1 start"; 0 ohne.</summary>
    class function InstanceFrom(const AOutput: string): Integer; static;
    /// <summary>cc.ps1 build für AProject in der Instanz AInstance; ECompilerError ohne Instanz.</summary>
    class function Build(const AScript, AProject, APlatform: string; AInstance: Integer): TCompilerRequest; static;
    /// <summary>cc.ps1 quit für AInstance.</summary>
    class function Quit(const AScript: string; AInstance: Integer): TCompilerRequest; static;
    /// <summary>Wert von "logFile" aus der JSON-Antwort von build (davor darf Text stehen); '' ohne.</summary>
    class function LogFileFrom(const AOutput: string): string; static;
    /// <summary>Meldungen aus dem Inhalt des logFile ("[dcc64 Fehler] …"-Zeilen).</summary>
    class function Messages(const ALogText, AWorkingDir: string): TArray<TCompilerMessage>; static;
  end;

implementation

uses
  System.StrUtils,
  System.JSON,
  BDLsp.Common.Projects.Paths,
  BDLsp.Common.Compiler.OutputParser;

const
  // Bekannte Lizenztexte von dcc32/dcc64 ohne Kommandozeilenlizenz (englisch, deutsch).
  LicenseTexts: array[0..3] of string = (
    'does not support command line compil',
    'command line compiler is not available',
    'unterstützt keine kompilierung über die befehlszeile',
    'kommandozeilen-compiler ist nicht verfügbar');

{ TCompilerEditionProbe }

constructor TCompilerEditionProbe.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FCache := TDictionary<string, TCompilerEdition>.Create;
end;

destructor TCompilerEditionProbe.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited;
end;

class function TCompilerEditionProbe.IsLicenseRefusal(const AOutput: string): Boolean;
var
  Text: string;
begin
  for Text in LicenseTexts do
    if ContainsText(AOutput, Text) then
      Exit(True);
  Result := False;
end;

class function TCompilerEditionProbe.Detect(const ABdsRoot: string; const AFileExists: TCompilerFileExists;
  const AProbeOutput: string): TCompilerEdition;
begin
  if ABdsRoot = '' then
    Exit(TCompilerEdition.Missing);
  if not AFileExists(TProjectPaths.Combine(ABdsRoot, 'bin\dcc32.exe')) and
    not AFileExists(TProjectPaths.Combine(ABdsRoot, 'bin\dcc64.exe')) then
  begin
    // Ohne dcc, aber mit IDE: Starter/Community; ganz ohne bds.exe keine Installation.
    if AFileExists(TProjectPaths.Combine(ABdsRoot, 'bin\bds.exe')) then
      Exit(TCompilerEdition.NoCommandLine);
    Exit(TCompilerEdition.Missing);
  end;
  if IsLicenseRefusal(AProbeOutput) then
    Exit(TCompilerEdition.NoCommandLine);
  if AProbeOutput = '' then
    Exit(TCompilerEdition.Unknown);
  Result := TCompilerEdition.CommandLine;
end;

function KeyOf(const ABdsRoot, AVersion: string): string;
begin
  Result := LowerCase(TProjectPaths.Normalize(ABdsRoot)) + '|' + LowerCase(AVersion);
end;

function TCompilerEditionProbe.TryGet(const ABdsRoot, AVersion: string; out AEdition: TCompilerEdition): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCache.TryGetValue(KeyOf(ABdsRoot, AVersion), AEdition);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TCompilerEditionProbe.Store(const ABdsRoot, AVersion: string; AEdition: TCompilerEdition);
begin
  TMonitor.Enter(FLock);
  try
    FCache.AddOrSetValue(KeyOf(ABdsRoot, AVersion), AEdition);
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TCompilerBackendChoice }

function OffChoice(const AReason, AStatus: string): TCompilerBackendChoice;
begin
  Result := Default(TCompilerBackendChoice);
  Result.Backend := TCompilerBackend.Off;
  Result.Reason := AReason;
  Result.StatusText := 'Compiler: ' + AStatus;
end;

function IdeChoice(AIdeCommandExists: Boolean; const AWhy: string): TCompilerBackendChoice;
begin
  if not AIdeCommandExists then
    Exit(OffChoice(AWhy + ' Für Compilermeldungen "compiler.backend": "ide" mit "compiler.ideCommand" ' +
      '(Pfad zu cc.ps1) einstellen.', 'nicht verfügbar (Starter Edition)'));
  Result := Default(TCompilerBackendChoice);
  Result.Backend := TCompilerBackend.Ide;
  Result.StatusText := 'Compiler: IDE (cc.ps1)';
  Result.OnSave := False;
end;

class function TCompilerBackendChoice.Choose(const ASettings: TCompilerSettings; AEdition: TCompilerEdition;
  AIdeCommandExists: Boolean): TCompilerBackendChoice;
const
  StarterText = 'Diese RAD-Studio-Edition hat keinen Kommandozeilen-Compiler (Starter/Community).';
begin
  case ASettings.Backend of
    TCompilerBackend.Off:
      Exit(OffChoice('Der Compiler ist abgeschaltet ("compiler.backend": "off").', 'abgeschaltet'));
    TCompilerBackend.Ide:
      if AIdeCommandExists then
        Exit(IdeChoice(True, ''))
      else
        Exit(OffChoice('"compiler.ideCommand" fehlt oder zeigt auf keine Datei; ohne cc.ps1 kann die IDE ' +
          'nicht kompilieren.', 'nicht verfügbar (cc.ps1 fehlt)'));
    TCompilerBackend.Dcc:
      if AEdition = TCompilerEdition.NoCommandLine then
        Exit(OffChoice(StarterText + ' "compiler.backend": "ide" nutzt stattdessen die IDE über cc.ps1.',
          'nicht verfügbar (Starter Edition)'));
  else
    // Auto
    case AEdition of
      TCompilerEdition.NoCommandLine:
        Exit(IdeChoice(AIdeCommandExists, StarterText));
      TCompilerEdition.Missing:
        Exit(OffChoice('Keine RAD-Studio-Installation gefunden; Compilermeldungen gibt es erst mit ' +
          'installiertem Delphi.', 'nicht verfügbar (keine Installation)'));
    end;
  end;
  if AEdition = TCompilerEdition.Missing then
    Exit(OffChoice('Keine RAD-Studio-Installation gefunden.', 'nicht verfügbar (keine Installation)'));
  Result := Default(TCompilerBackendChoice);
  Result.Backend := TCompilerBackend.Dcc;
  Result.StatusText := 'Compiler: dcc';
  Result.OnSave := ASettings.OnSave;
end;

{ TIdeCompilerCommand }

function ScriptRequest(const AScript: string; const AArguments: TArray<string>): TCompilerRequest;
begin
  Result := Default(TCompilerRequest);
  Result.Executable := 'pwsh.exe';
  Result.Arguments := ['-NoProfile', '-NonInteractive', '-File', AScript] + AArguments;
  Result.WorkingDir := TProjectPaths.DirectoryOf(AScript);
end;

class function TIdeCompilerCommand.Start(const AScript, AProject: string): TCompilerRequest;
begin
  Result := ScriptRequest(AScript, ['start', '-Project', AProject]);
end;

class function TIdeCompilerCommand.InstanceFrom(const AOutput: string): Integer;
var
  Index, Start: Integer;
  Text: string;
begin
  // Wie Tools/Build-Test.ps1: "pid", beliebige Nicht-Ziffern, dann die Zahl.
  Text := LowerCase(AOutput);
  Index := Pos('pid', Text);
  if Index = 0 then
    Exit(0);
  Inc(Index, 3);
  while (Index <= Length(Text)) and not CharInSet(Text[Index], ['0'..'9']) do
    Inc(Index);
  Start := Index;
  while (Index <= Length(Text)) and CharInSet(Text[Index], ['0'..'9']) do
    Inc(Index);
  Result := StrToIntDef(Copy(Text, Start, Index - Start), 0);
end;

class function TIdeCompilerCommand.Build(const AScript, AProject, APlatform: string;
  AInstance: Integer): TCompilerRequest;
begin
  // Nie ohne -Instance: sonst nähme cc.ps1 die IDE des Benutzers.
  if AInstance <= 0 then
    raise ECompilerError.Create('Keine Scratch-IDE gestartet; cc.ps1 build braucht -Instance');
  Result := ScriptRequest(AScript, ['build', '-Instance', IntToStr(AInstance), '-Project', AProject,
    '-Platform', APlatform, '-Json']);
end;

class function TIdeCompilerCommand.Quit(const AScript: string; AInstance: Integer): TCompilerRequest;
begin
  if AInstance <= 0 then
    raise ECompilerError.Create('Keine Scratch-IDE gestartet');
  Result := ScriptRequest(AScript, ['quit', '-Instance', IntToStr(AInstance)]);
end;

class function TIdeCompilerCommand.LogFileFrom(const AOutput: string): string;
var
  Start: Integer;
  Value: TJSONValue;
begin
  Result := '';
  Start := Pos('{', AOutput);
  if Start = 0 then
    Exit;
  Value := TJSONObject.ParseJSONValue(Copy(AOutput, Start, MaxInt));
  try
    if Value is TJSONObject then
      Result := TJSONObject(Value).GetValue<string>('logFile', '');
  finally
    Value.Free;
  end;
end;

class function TIdeCompilerCommand.Messages(const ALogText, AWorkingDir: string): TArray<TCompilerMessage>;
begin
  Result := TCompilerOutputParser.Parse(StringReplace(ALogText, #13, '', [rfReplaceAll]).Split([#10]), AWorkingDir);
end;

end.
