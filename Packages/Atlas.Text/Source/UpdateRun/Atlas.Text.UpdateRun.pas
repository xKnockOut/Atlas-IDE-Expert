unit Atlas.Text.UpdateRun;

// Ablauf eines Updates (#1519) zwischen Plugin und AtlasUpdate.exe, gemeinsam
// für beide:
// - Aufruf: AtlasUpdate.exe <Befehl> --name Wert …; Befehle prepare (laden,
//   prüfen, bei Bedarf bauen), apply (nach dem Schließen der IDE tauschen)
//   und install (Erstinstallation aus dem entpackten Paket).
// - Stand der Vorbereitung in <Staging>\state.json: Phase, Fortschritt,
//   Fehlerkennung und die Packages zur Auswahl. Das Plugin liest die Datei
//   und übersetzt die Kennungen in seine Texte.
// - Ergebnis des Tauschs in result.json neben den Staging-Ordnern; das
//   Plugin meldet es beim nächsten Start und löscht die Datei.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TUpdatePhase = (Downloading, Verifying, Building, Ready, Failed);
  TUpdateOutcomeKind = (Installed, RolledBack, Cancelled, Failed);
  /// <summary>Was mit neuen Modulen geschieht (updates.newModules).</summary>
  TUpdateNewModules = (Ask, Install, Skip);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Package der neuen Version in der Auswahl der Module.</summary>
  TUpdateCandidate = record
    /// <summary>Name ohne Versionsendung, z. B. „Atlas.IDE.Debugger“.</summary>
    Name: string;
    /// <summary>Im Profil der IDE unter Known Packages eingetragen (aus dem Atlas-Ordner).</summary>
    Installed: Boolean;
    /// <summary>Gab es in der installierten Version nicht.</summary>
    IsNew: Boolean;
    /// <summary>Bei einem früheren Update als neues Modul abgelehnt; wird nicht erneut vorgeschlagen.</summary>
    Declined: Boolean;
    Required: Boolean;
    /// <summary>Vorschlag: installiert bzw. nach updates.newModules.</summary>
    Selected: Boolean;
  end;

  TUpdateStage = record
    Phase: TUpdatePhase;
    /// <summary>0 bis 100 innerhalb der Phase.</summary>
    Progress: Integer;
    Version: string;
    Previous: string;
    /// <summary>Kennung des Fehlers (TUpdateErrors), '' ohne Fehler.</summary>
    Error: string;
    /// <summary>Datei oder Grund zum Fehler, ohne Adressen.</summary>
    Detail: string;
    FromSource: Boolean;
    /// <summary>Auswahl zeigen, bevor das Update eingeplant wird (neue Module und updates.newModules = ask).
    /// </summary>
    AskSelection: Boolean;
    /// <summary>AtlasUpdate.exe der neuen Version im Staging-Ordner, die den Tausch ausführt.</summary>
    Updater: string;
    Candidates: TArray<TUpdateCandidate>;
    function ToJson: string;
    class function FromJson(const AJson: string): TUpdateStage; static;
    /// <summary>Namen der vorgeschlagenen Packages.</summary>
    function SelectedNames: TArray<string>;
  end;

  TUpdateOutcome = record
    Kind: TUpdateOutcomeKind;
    Version: string;
    Previous: string;
    /// <summary>Kennung (TUpdateErrors) bei Rücknahme oder Fehler.</summary>
    Reason: string;
    Detail: string;
    LogFile: string;
    Added: TArray<string>;
    Removed: TArray<string>;
    function ToJson: string;
    class function FromJson(const AJson: string): TUpdateOutcome; static;
  end;

  /// <summary>Kennungen der Fehler in state.json und result.json.</summary>
  TUpdateErrors = class
  public const
    cManifest = 'manifest';
    cVersionChanged = 'version';
    cNoPackage = 'noPackage';
    cNoCompiler = 'noCompiler';
    cDownload = 'download';
    cHash = 'hash';
    cArchive = 'archive';
    cUnsigned = 'unsigned';
    cSignature = 'signature';
    cBuild = 'build';
    cLocked = 'locked';
    cCopyFailed = 'copy';
    cRegistry = 'registry';
    cCancelled = 'cancelled';
    cElevation = 'elevation';
    cSelection = 'selection';
    /// <summary>Unerwarteter Fehler; Detail nennt die Meldung.</summary>
    cUnexpected = 'unexpected';
  end;

  /// <summary>Dateien und Ordner eines Updates (#1519). Alles liegt unter %LOCALAPPDATA%\Atlas\Updates
  /// (Root); je Version ein Staging-Ordner Root\&lt;Version&gt;.</summary>
  TUpdateLayout = class
  public const
    cUpdaterExe = 'AtlasUpdate.exe';
    cServerExe = 'AtlasServer.exe';
    /// <summary>Stand der Vorbereitung im Staging-Ordner.</summary>
    cStateFile = 'state.json';
    /// <summary>Ergebnis des letzten Tauschs im Root.</summary>
    cResultFile = 'result.json';
    /// <summary>Abgelehnte neue Module im Root (Namen, eine Zeile je Modul).</summary>
    cDeclinedFile = 'declined.txt';
    cLogFile = 'update.log';
    /// <summary>Neue Dateien im Aufbau des Atlas-Ordners.</summary>
    cFilesFolder = 'files';
    cSourceFolder = 'source';
    cBackupFolder = 'backup';
    cDownloadFolder = 'download';
    /// <summary>Endung, unter der eine laufende EXE beim Tausch beiseitegelegt wird.</summary>
    cOldSuffix = '.atlas-old';
  public
    class function Join(const ADir, AName: string): string; static;
  end;

  TUpdateArguments = record
    Command: string;
    ManifestUrl: string;
    Version: string;
    /// <summary>Installierte Atlas-Version (für das Ergebnis „von … auf …“).</summary>
    Previous: string;
    /// <summary>CompilerVersion der IDE, z. B. „37.0“.</summary>
    Ide: string;
    /// <summary>Win32 (klassische IDE) oder Win64 (64-Bit-IDE).</summary>
    Platform: string;
    /// <summary>Registry-Basis der IDE unter HKCU, z. B. Software\Embarcadero\BDS\37.0 (auch eigene Profile).
    /// </summary>
    RegistryKey: string;
    /// <summary>Atlas-Ordner (AtlasServer.exe, Win32\, Win64\).</summary>
    Target: string;
    Staging: string;
    /// <summary>Gewählte Packages (Namen ohne Versionsendung).</summary>
    Select: TArray<string>;
    /// <summary>Auf das Ende dieses Prozesses warten (IDE, die apply startet); 0 = keiner.</summary>
    WaitPid: Cardinal;
    NewModules: TUpdateNewModules;
    class function Parse(const AArgs: TArray<string>): TUpdateArguments; static;
    function ToArgs: TArray<string>;
    /// <summary>Befehlszeile nach den Regeln von CommandLineToArgvW (ohne Programmname).</summary>
    function CommandLine: string;
  end;

  TUpdateNames = class
  public
    class function PhaseName(APhase: TUpdatePhase): string; static;
    class function ParsePhase(const AText: string): TUpdatePhase; static;
    class function OutcomeName(AKind: TUpdateOutcomeKind): string; static;
    class function ParseOutcome(const AText: string): TUpdateOutcomeKind; static;
    class function NewModulesName(AValue: TUpdateNewModules): string; static;
    class function ParseNewModules(const AText: string): TUpdateNewModules; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json,
  Atlas.Text.CommandLine;

const
  cPhaseNames: array[TUpdatePhase] of string = ('downloading', 'verifying', 'building', 'ready', 'failed');
  cOutcomeNames: array[TUpdateOutcomeKind] of string = ('installed', 'rolledBack', 'cancelled', 'failed');
  cNewModulesNames: array[TUpdateNewModules] of string = ('ask', 'install', 'skip');

{ TUpdateLayout }

class function TUpdateLayout.Join(const ADir, AName: string): string;
begin
  // Windows-Pfade auch beim Test unter Linux: Der Aufbau ist immer der eines Windows-Ordners.
  if (ADir = '') or ADir.EndsWith('\') then
  begin
    Result := ADir + AName;
  end
  else
  begin
    Result := ADir + '\' + AName;
  end;
end;

{ TUpdateNames }

class function TUpdateNames.PhaseName(APhase: TUpdatePhase): string;
begin
  Result := cPhaseNames[APhase];
end;

class function TUpdateNames.ParsePhase(const AText: string): TUpdatePhase;
var
  mPhase: TUpdatePhase;
begin
  for mPhase := Low(TUpdatePhase) to High(TUpdatePhase) do
  begin
    if SameText(AText, cPhaseNames[mPhase]) then
    begin
      Exit(mPhase);
    end;
  end;
  Result := TUpdatePhase.Failed;
end;

class function TUpdateNames.OutcomeName(AKind: TUpdateOutcomeKind): string;
begin
  Result := cOutcomeNames[AKind];
end;

class function TUpdateNames.ParseOutcome(const AText: string): TUpdateOutcomeKind;
var
  mKind: TUpdateOutcomeKind;
begin
  for mKind := Low(TUpdateOutcomeKind) to High(TUpdateOutcomeKind) do
  begin
    if SameText(AText, cOutcomeNames[mKind]) then
    begin
      Exit(mKind);
    end;
  end;
  Result := TUpdateOutcomeKind.Failed;
end;

class function TUpdateNames.NewModulesName(AValue: TUpdateNewModules): string;
begin
  Result := cNewModulesNames[AValue];
end;

class function TUpdateNames.ParseNewModules(const AText: string): TUpdateNewModules;
var
  mValue: TUpdateNewModules;
begin
  for mValue := Low(TUpdateNewModules) to High(TUpdateNewModules) do
  begin
    if SameText(Trim(AText), cNewModulesNames[mValue]) then
    begin
      Exit(mValue);
    end;
  end;
  Result := TUpdateNewModules.Ask;
end;

{ JSON-Hilfen }

/// <summary>Text des JSON-Objekts AObject (Umlaute lesbar) und gibt es frei.</summary>
function JsonTextOf(AObject: TJSONObject): string;
begin
  try
    Result := AObject.ToJSON([]);
  finally
    AObject.Free;
  end;
end;

function CandidateObject(const ACandidate: TUpdateCandidate): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ACandidate.Name);
  Result.AddPair('installed', TJSONBool.Create(ACandidate.Installed));
  Result.AddPair('new', TJSONBool.Create(ACandidate.IsNew));
  Result.AddPair('declined', TJSONBool.Create(ACandidate.Declined));
  Result.AddPair('required', TJSONBool.Create(ACandidate.Required));
  Result.AddPair('selected', TJSONBool.Create(ACandidate.Selected));
end;

{ TUpdateStage }

function TUpdateStage.ToJson: string;
var
  mRoot: TJSONObject;
  mCandidates: TJSONArray;
  mCandidate: TUpdateCandidate;
begin
  mRoot := TJSONObject.Create;
  mRoot.AddPair('phase', TUpdateNames.PhaseName(Phase));
  mRoot.AddPair('progress', TJSONNumber.Create(Progress));
  mRoot.AddPair('version', Version);
  mRoot.AddPair('previous', Previous);
  mRoot.AddPair('error', Error);
  mRoot.AddPair('detail', Detail);
  mRoot.AddPair('fromSource', TJSONBool.Create(FromSource));
  mRoot.AddPair('askSelection', TJSONBool.Create(AskSelection));
  mRoot.AddPair('updater', Updater);
  mCandidates := TJSONArray.Create;
  mRoot.AddPair('candidates', mCandidates);
  for mCandidate in Candidates do
  begin
    mCandidates.AddElement(CandidateObject(mCandidate));
  end;
  Result := JsonTextOf(mRoot);
end;

function CandidatesOf(const ARoot: TJSONObject): TArray<TUpdateCandidate>;
var
  mNode, mItem: TJSONValue;
  mList: TList<TUpdateCandidate>;
  mCandidate: TUpdateCandidate;
begin
  Result := nil;
  mNode := ARoot.GetValue('candidates');
  if not (mNode is TJSONArray) then
  begin
    Exit;
  end;
  mList := TList<TUpdateCandidate>.Create;
  try
    for mItem in TJSONArray(mNode) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mCandidate := Default(TUpdateCandidate);
      mCandidate.Name := TJsonRead.Text(TJSONObject(mItem), 'name');
      mCandidate.Installed := TJsonRead.Flag(TJSONObject(mItem), 'installed');
      mCandidate.IsNew := TJsonRead.Flag(TJSONObject(mItem), 'new');
      mCandidate.Declined := TJsonRead.Flag(TJSONObject(mItem), 'declined');
      mCandidate.Required := TJsonRead.Flag(TJSONObject(mItem), 'required');
      mCandidate.Selected := TJsonRead.Flag(TJSONObject(mItem), 'selected');
      if mCandidate.Name <> '' then
      begin
        mList.Add(mCandidate);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TUpdateStage.FromJson(const AJson: string): TUpdateStage;
var
  mRoot: TJSONObject;
begin
  Result := Default(TUpdateStage);
  Result.Phase := TUpdatePhase.Failed;
  mRoot := TJsonRead.ParseObject(AJson);
  if mRoot = nil then
  begin
    Result.Error := TUpdateErrors.cManifest;
    Exit;
  end;
  try
    Result.Phase := TUpdateNames.ParsePhase(TJsonRead.Text(mRoot, 'phase'));
    Result.Progress := TJsonRead.Int(mRoot, 'progress');
    Result.Version := TJsonRead.Text(mRoot, 'version');
    Result.Previous := TJsonRead.Text(mRoot, 'previous');
    Result.Error := TJsonRead.Text(mRoot, 'error');
    Result.Detail := TJsonRead.Text(mRoot, 'detail');
    Result.FromSource := TJsonRead.Flag(mRoot, 'fromSource');
    Result.AskSelection := TJsonRead.Flag(mRoot, 'askSelection');
    Result.Updater := TJsonRead.Text(mRoot, 'updater');
    Result.Candidates := CandidatesOf(mRoot);
  finally
    mRoot.Free;
  end;
end;

function TUpdateStage.SelectedNames: TArray<string>;
var
  mCandidate: TUpdateCandidate;
  mList: TList<string>;
begin
  mList := TList<string>.Create;
  try
    for mCandidate in Candidates do
    begin
      if mCandidate.Selected or mCandidate.Required then
      begin
        mList.Add(mCandidate.Name);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

{ TUpdateOutcome }

function TUpdateOutcome.ToJson: string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  mRoot.AddPair('outcome', TUpdateNames.OutcomeName(Kind));
  mRoot.AddPair('version', Version);
  mRoot.AddPair('previous', Previous);
  mRoot.AddPair('reason', Reason);
  mRoot.AddPair('detail', Detail);
  mRoot.AddPair('log', LogFile);
  mRoot.AddPair('added', TJsonBuild.Strings(Added));
  mRoot.AddPair('removed', TJsonBuild.Strings(Removed));
  Result := JsonTextOf(mRoot);
end;

class function TUpdateOutcome.FromJson(const AJson: string): TUpdateOutcome;
var
  mRoot: TJSONObject;
begin
  Result := Default(TUpdateOutcome);
  Result.Kind := TUpdateOutcomeKind.Failed;
  mRoot := TJsonRead.ParseObject(AJson);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    Result.Kind := TUpdateNames.ParseOutcome(TJsonRead.Text(mRoot, 'outcome'));
    Result.Version := TJsonRead.Text(mRoot, 'version');
    Result.Previous := TJsonRead.Text(mRoot, 'previous');
    Result.Reason := TJsonRead.Text(mRoot, 'reason');
    Result.Detail := TJsonRead.Text(mRoot, 'detail');
    Result.LogFile := TJsonRead.Text(mRoot, 'log');
    Result.Added := TJsonRead.Strings(mRoot, 'added');
    Result.Removed := TJsonRead.Strings(mRoot, 'removed');
  finally
    mRoot.Free;
  end;
end;

{ TUpdateArguments }

type
{$SCOPEDENUMS ON}
  /// <summary>Argumente des Aktualisierers, gleich geordnet wie cArgumentNames.</summary>
  TUpdateArgument = (Manifest, Version, Ide, Platform, RegistryKey, Target, Staging, Select, WaitPid, NewModules,
    Previous);
{$SCOPEDENUMS OFF}

const
  cArgumentNames: array[TUpdateArgument] of string = ('manifest', 'version', 'ide', 'platform', 'registry-key',
    'target', 'staging', 'select', 'wait-pid', 'new-modules', 'previous');

/// <summary>Prozesskennung aus dem Aufruf; 0 bei ungültigem Text oder einem Wert außerhalb von Cardinal.</summary>
function ProcessIdOf(const AValue: string): Cardinal;
var
  mValue: Int64;
begin
  Result := 0;
  if TryStrToInt64(AValue, mValue) and (mValue >= 0) and (mValue <= High(Cardinal)) then
  begin
    Result := Cardinal(mValue);
  end;
end;

/// <summary>Argument zum Namen AName (ohne "--"); False bei unbekanntem Namen.</summary>
function ArgumentOf(const AName: string; out AArgument: TUpdateArgument): Boolean;
var
  mArgument: TUpdateArgument;
begin
  for mArgument := Low(TUpdateArgument) to High(TUpdateArgument) do
  begin
    if SameText(AName, cArgumentNames[mArgument]) then
    begin
      AArgument := mArgument;
      Exit(True);
    end;
  end;
  AArgument := TUpdateArgument.Manifest;
  Result := False;
end;

procedure AssignArgument(var AArguments: TUpdateArguments; const AName, AValue: string);
var
  mArgument: TUpdateArgument;
begin
  // Unbekannte Namen übergeht der Aufruf (ältere oder neuere Plugins).
  if not ArgumentOf(AName, mArgument) then
  begin
    Exit;
  end;
  case mArgument of
    TUpdateArgument.Manifest:
      AArguments.ManifestUrl := AValue;
    TUpdateArgument.Version:
      AArguments.Version := AValue;
    TUpdateArgument.Ide:
      AArguments.Ide := AValue;
    TUpdateArgument.Platform:
      AArguments.Platform := AValue;
    TUpdateArgument.RegistryKey:
      AArguments.RegistryKey := AValue;
    TUpdateArgument.Target:
      AArguments.Target := AValue;
    TUpdateArgument.Staging:
      AArguments.Staging := AValue;
    TUpdateArgument.Select:
      AArguments.Select := AValue.Split([','], TStringSplitOptions.ExcludeEmpty);
    TUpdateArgument.WaitPid:
      AArguments.WaitPid := ProcessIdOf(AValue);
    TUpdateArgument.NewModules:
      AArguments.NewModules := TUpdateNames.ParseNewModules(AValue);
    TUpdateArgument.Previous:
      AArguments.Previous := AValue;
  end;
end;

{ TUpdateArguments }

class function TUpdateArguments.Parse(const AArgs: TArray<string>): TUpdateArguments;
var
  mIndex: Integer;
  mName: string;
begin
  Result := Default(TUpdateArguments);
  Result.NewModules := TUpdateNewModules.Ask;
  mIndex := 0;
  if (Length(AArgs) > 0) and not AArgs[0].StartsWith('--') then
  begin
    Result.Command := LowerCase(AArgs[0]);
    mIndex := 1;
  end;
  while mIndex < Length(AArgs) - 1 do
  begin
    mName := LowerCase(AArgs[mIndex]);
    if mName.StartsWith('--') then
    begin
      AssignArgument(Result, mName.Substring(2), AArgs[mIndex + 1]);
      Inc(mIndex);
    end;
    Inc(mIndex);
  end;
end;

procedure AddPair(AList: TList<string>; const AName, AValue: string);
begin
  if AValue <> '' then
  begin
    AList.Add('--' + AName);
    AList.Add(AValue);
  end;
end;

function TUpdateArguments.ToArgs: TArray<string>;
var
  mList: TList<string>;
begin
  mList := TList<string>.Create;
  try
    if Command <> '' then
    begin
      mList.Add(Command);
    end;
    AddPair(mList, 'manifest', ManifestUrl);
    AddPair(mList, 'version', Version);
    AddPair(mList, 'previous', Previous);
    AddPair(mList, 'ide', Ide);
    AddPair(mList, 'platform', Platform);
    AddPair(mList, 'registry-key', RegistryKey);
    AddPair(mList, 'target', Target);
    AddPair(mList, 'staging', Staging);
    AddPair(mList, 'select', string.Join(',', Select));
    if WaitPid <> 0 then
    begin
      AddPair(mList, 'wait-pid', IntToStr(WaitPid));
    end;
    AddPair(mList, 'new-modules', TUpdateNames.NewModulesName(NewModules));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TUpdateArguments.CommandLine: string;
begin
  Result := TTextCommandLine.JoinArguments(ToArgs);
end;

end.
