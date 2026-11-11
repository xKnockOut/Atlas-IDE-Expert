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

  /// <summary>Ein Package der neuen Version in der Auswahl (Mockup 6).</summary>
  TUpdateCandidate = record
    /// <summary>Name ohne Versionsendung, z. B. „Atlas.IDE.Debugger“.</summary>
    Name: string;
    /// <summary>Im Profil der IDE unter Known Packages eingetragen (aus dem Atlas-Ordner).</summary>
    Installed: Boolean;
    /// <summary>Gab es in der installierten Version nicht.</summary>
    IsNew: Boolean;
    /// <summary>Früher als neues Modul abgelehnt; wird nicht erneut vorgeschlagen.</summary>
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
    /// <summary>Ein Argument mit Anführungszeichen nach den Regeln von CommandLineToArgvW.</summary>
    class function QuoteArgument(const AArgument: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json;

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

class function TUpdateNames.QuoteArgument(const AArgument: string): string;
var
  mBuilder: TStringBuilder;
  mIndex, mSlashes: Integer;
begin
  if (AArgument <> '') and (AArgument.IndexOfAny([' ', #9, '"']) < 0) then
  begin
    Exit(AArgument);
  end;
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('"');
    mSlashes := 0;
    for mIndex := 1 to Length(AArgument) do
    begin
      if AArgument[mIndex] = '\' then
      begin
        Inc(mSlashes);
        Continue;
      end;
      // Backslashes vor einem Anführungszeichen verdoppeln, das Zeichen selbst maskieren.
      if AArgument[mIndex] = '"' then
      begin
        mBuilder.Append(StringOfChar('\', mSlashes * 2 + 1));
      end
      else
      begin
        mBuilder.Append(StringOfChar('\', mSlashes));
      end;
      mSlashes := 0;
      mBuilder.Append(AArgument[mIndex]);
    end;
    mBuilder.Append(StringOfChar('\', mSlashes * 2)).Append('"');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ JSON-Hilfen }

function NamesOf(const AObject: TJSONObject; const AName: string): TArray<string>;
var
  mNode, mItem: TJSONValue;
  mList: TList<string>;
begin
  Result := nil;
  mNode := AObject.GetValue(AName);
  if not (mNode is TJSONArray) then
  begin
    Exit;
  end;
  mList := TList<string>.Create;
  try
    for mItem in TJSONArray(mNode) do
    begin
      if mItem is TJSONString then
      begin
        mList.Add(TJSONString(mItem).Value);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function NamesJson(const ANames: TArray<string>): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('[');
    for mIndex := 0 to High(ANames) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(', ');
      end;
      mBuilder.Append(TJsonText.Quote(ANames[mIndex]));
    end;
    mBuilder.Append(']');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function BoolJson(AValue: Boolean): string;
begin
  if AValue then
  begin
    Result := 'true';
  end
  else
  begin
    Result := 'false';
  end;
end;

/// <summary>Wurzelobjekt von AJson oder nil (auch bei kaputtem Text); der Aufrufer gibt es frei.</summary>
function ParseObject(const AJson: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on EJSONException do
    begin
      Exit;
    end;
  end;
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end
  else
  begin
    mValue.Free;
  end;
end;

{ TUpdateStage }

function CandidateJson(const ACandidate: TUpdateCandidate): string;
begin
  Result := '{"name": ' + TJsonText.Quote(ACandidate.Name) + ', "installed": ' + BoolJson(ACandidate.Installed) +
    ', "new": ' + BoolJson(ACandidate.IsNew) + ', "declined": ' + BoolJson(ACandidate.Declined) +
    ', "required": ' + BoolJson(ACandidate.Required) + ', "selected": ' + BoolJson(ACandidate.Selected) + '}';
end;

function TUpdateStage.ToJson: string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{"phase": ').Append(TJsonText.Quote(TUpdateNames.PhaseName(Phase)));
    mBuilder.Append(', "progress": ').Append(IntToStr(Progress));
    mBuilder.Append(', "version": ').Append(TJsonText.Quote(Version));
    mBuilder.Append(', "previous": ').Append(TJsonText.Quote(Previous));
    mBuilder.Append(', "error": ').Append(TJsonText.Quote(Error));
    mBuilder.Append(', "detail": ').Append(TJsonText.Quote(Detail));
    mBuilder.Append(', "fromSource": ').Append(BoolJson(FromSource));
    mBuilder.Append(', "askSelection": ').Append(BoolJson(AskSelection));
    mBuilder.Append(', "updater": ').Append(TJsonText.Quote(Updater));
    mBuilder.Append(', "candidates": [');
    for mIndex := 0 to High(Candidates) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(', ');
      end;
      mBuilder.Append(CandidateJson(Candidates[mIndex]));
    end;
    mBuilder.Append(']}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
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
  mRoot := ParseObject(AJson);
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
begin
  Result := '{"outcome": ' + TJsonText.Quote(TUpdateNames.OutcomeName(Kind)) +
    ', "version": ' + TJsonText.Quote(Version) + ', "previous": ' + TJsonText.Quote(Previous) +
    ', "reason": ' + TJsonText.Quote(Reason) + ', "detail": ' + TJsonText.Quote(Detail) +
    ', "log": ' + TJsonText.Quote(LogFile) + ', "added": ' + NamesJson(Added) +
    ', "removed": ' + NamesJson(Removed) + '}';
end;

class function TUpdateOutcome.FromJson(const AJson: string): TUpdateOutcome;
var
  mRoot: TJSONObject;
begin
  Result := Default(TUpdateOutcome);
  Result.Kind := TUpdateOutcomeKind.Failed;
  mRoot := ParseObject(AJson);
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
    Result.Added := NamesOf(mRoot, 'added');
    Result.Removed := NamesOf(mRoot, 'removed');
  finally
    mRoot.Free;
  end;
end;

{ TUpdateArguments }

const
  cArgumentNames: array[0..10] of string = ('manifest', 'version', 'ide', 'platform', 'registry-key', 'target',
    'staging', 'select', 'wait-pid', 'new-modules', 'previous');

procedure AssignArgument(var AArguments: TUpdateArguments; const AName, AValue: string);
begin
  case IndexText(AName, cArgumentNames) of
    0:
      AArguments.ManifestUrl := AValue;
    1:
      AArguments.Version := AValue;
    2:
      AArguments.Ide := AValue;
    3:
      AArguments.Platform := AValue;
    4:
      AArguments.RegistryKey := AValue;
    5:
      AArguments.Target := AValue;
    6:
      AArguments.Staging := AValue;
    7:
      AArguments.Select := AValue.Split([','], TStringSplitOptions.ExcludeEmpty);
    8:
      AArguments.WaitPid := StrToIntDef(AValue, 0);
    9:
      AArguments.NewModules := TUpdateNames.ParseNewModules(AValue);
    10:
      AArguments.Previous := AValue;
  else
    // Unbekannte Namen übergeht der Aufruf (ältere oder neuere Plugins).
  end;
end;

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
var
  mArgs: TArray<string>;
  mIndex: Integer;
begin
  mArgs := ToArgs;
  Result := '';
  for mIndex := 0 to High(mArgs) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ' ';
    end;
    Result := Result + TUpdateNames.QuoteArgument(mArgs[mIndex]);
  end;
end;

end.
