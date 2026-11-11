unit Atlas.Common.Lsp.StatusFile;

// Statusdatei je Server (#1356, #1901): Jeder AtlasServer (LSP für die IDE, --mcp für den KI-Assistenten,
// Kommandozeilenlauf) schreibt alle paar Sekunden %LOCALAPPDATA%\Atlas\Status\server-<pid>.json
// (TServerStatusHeartbeat): Art, Befehl und Ziel, Version, Start, Speicher, Zustand, laufende Anfragen mit Dauer,
// Fortschritt, Zähler für Zeitüberschreitungen und Fehler, die Wurzeln der Arbeitsbereiche und beim LSP-Server den
// ausführlichen Status des Fensters „Atlas-Server“. Daraus liest das MCP-Werkzeug get_server_status (Find: jüngster
// LSP-Status für einen Ordner) und AtlasMonitor (List: alle Server). Beim Beenden löscht der Server seine Datei;
// Dateien abgestürzter Prozesse räumen Schreiber und Leser weg. Die Datei bleibt lokal; Pfade stehen nur darin,
// weil der Status selbst sie enthält.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>True, solange der Prozess APid läuft (Leser mit Zugriff auf das System, z. B. AtlasMonitor).</summary>
  TServerAliveFunc = reference to function(APid: Cardinal): Boolean;

  /// <summary>Inhalt einer Statusdatei (#1901).</summary>
  TServerStatusEntry = record
  public const
    cKindLsp = 'lsp';
    cKindMcp = 'mcp';
    cKindCli = 'cli';
    cStateReady = 'ready';
    cStateWorking = 'working';
  public
    Pid: Cardinal;
    /// <summary>Zeitpunkt des Schreibens (Ortszeit).</summary>
    Written: TDateTime;
    Roots: TArray<string>;
    /// <summary>lsp, mcp oder cli; '' bei Dateien ohne Art (gelten als lsp).</summary>
    Kind: string;
    /// <summary>Befehl eines Kommandozeilenlaufs (check, format-check, fix …); sonst ''.</summary>
    Command: string;
    /// <summary>Ziel des Laufs bzw. Ordner des MCP-Servers; sonst ''.</summary>
    Target: string;
    /// <summary>Protokolldatei aus --log; '' ohne.</summary>
    LogFile: string;
    Version: string;
    Started: TDateTime;
    MemoryBytes: Int64;
    /// <summary>ready, working oder ein Zustand des LSP-Status (loading, checking).</summary>
    State: string;
    /// <summary>Zahl der laufenden Anfragen, die am längsten laufende mit Dauer.</summary>
    Running: Integer;
    RunningMethod: string;
    RunningMs: Int64;
    /// <summary>Fortschritt eines Laufs (geprüfte Dateien von allen); Total = 0 ohne.</summary>
    Done: Integer;
    Total: Integer;
    Timeouts: Integer;
    Errors: Integer;
    /// <summary>Ausführlicher Status als JSON-Text (nur LSP-Server); '' ohne.</summary>
    Status: string;
    /// <summary>Gelesene Datei (nur beim Lesen gesetzt).</summary>
    FileName: string;
    /// <summary>Art mit Vorgabe lsp.</summary>
    function KindOrLsp: string;
    function ToJson(AStatus: TJSONObject): TJSONObject;
    /// <summary>Liest einen Eintrag; False, wenn pid oder written fehlen.</summary>
    class function FromJson(AObject: TJSONObject; out AEntry: TServerStatusEntry): Boolean; static;
  end;

  TServerStatusFile = record
  public const
    cFolderName = 'Status';
    /// <summary>Ältere Dateien gelten für get_server_status als veraltet (Server abgestürzt oder hängt).</summary>
    cMaxAgeSeconds = 60;
    /// <summary>Ältere Dateien räumen Schreiber und Leser weg.</summary>
    cOrphanSeconds = 10 * cMaxAgeSeconds;
  public
    class function FolderOf(const ARoot: string): string; static;
    class function FileFor(const ARoot: string; APid: Cardinal): string; static;
    /// <summary>Schreibt AEntry mit AStatus (Kopie; nil ohne ausführlichen Status) und dem Zeitpunkt ANow atomar;
    /// ersetzt die vorige Datei und löscht verwaiste anderer Prozesse. Fehler beim Schreiben bleiben still.
    /// </summary>
    class procedure Write(const ARoot: string; const AEntry: TServerStatusEntry; const AStatus: TJSONObject;
      ANow: TDateTime); overload; static;
    /// <summary>LSP-Status mit pid, Zeitpunkt und Wurzeln, wie Write mit einem Eintrag der Art lsp.</summary>
    class procedure Write(const ARoot: string; APid: Cardinal; const AWorkspaceRoots: TArray<string>;
      const AStatus: TJSONObject; ANow: TDateTime); overload; static;
    class procedure Delete(const ARoot: string; APid: Cardinal); static;
    /// <summary>True, wenn AFolder eine der Wurzeln ist, darunter oder darüber liegt (ohne Groß-/Kleinschreibung).
    /// </summary>
    class function Matches(const AWorkspaceRoots: TArray<string>; const AFolder: string): Boolean; static;
    /// <summary>Jüngster gültiger LSP-Status für AFolder: AStatus als JSON-Text, APid und AWritten; False ohne.
    /// </summary>
    class function Find(const ARoot, AFolder: string; ANow: TDateTime; out AStatus: string; out APid: Cardinal;
      out AWritten: TDateTime): Boolean; static;
    /// <summary>Alle Server, nach Start und pid geordnet. Dateien, deren Prozess laut AIsAlive (nil = nicht prüfen)
    /// nicht mehr läuft oder die älter als cOrphanSeconds sind, werden gelöscht.</summary>
    class function List(const ARoot: string; ANow: TDateTime; const AIsAlive: TServerAliveFunc):
      TArray<TServerStatusEntry>; static;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Math,
  Atlas.Text.Json;

/// <summary>Ordner zum Vergleichen: klein, beide Trenner als „/“, mit „/“ am Ende.</summary>
function NormalFolder(const AFolder: string): string;
begin
  Result := AnsiLowerCase(StringReplace(Trim(AFolder), '\', '/', [rfReplaceAll]));
  if not Result.EndsWith('/') then
  begin
    Result := Result + '/';
  end;
end;

/// <summary>Zeitpunkt als ISO 8601 (Ortszeit); '' für 0.</summary>
function DateText(AValue: TDateTime): string;
begin
  Result := '';
  if AValue <> 0 then
  begin
    Result := DateToISO8601(AValue, False);
  end;
end;

/// <summary>Zeitpunkt aus ISO 8601; 0, wenn der Text fehlt oder ungültig ist.</summary>
function DateOf(const AText: string): TDateTime;
begin
  if (AText = '') or not TryISO8601ToDate(AText, Result, False) then
  begin
    Result := 0;
  end;
end;

{ TServerStatusEntry }

function TServerStatusEntry.KindOrLsp: string;
begin
  Result := Kind;
  if Result = '' then
  begin
    Result := cKindLsp;
  end;
end;

function TServerStatusEntry.ToJson(AStatus: TJSONObject): TJSONObject;
var
  mRoots: TJSONArray;
  mRoot: string;
  mRunning, mProgress: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('pid', TJSONNumber.Create(Pid));
  Result.AddPair('written', DateText(Written));
  mRoots := TJSONArray.Create;
  for mRoot in Roots do
  begin
    mRoots.Add(mRoot);
  end;
  Result.AddPair('roots', mRoots);
  Result.AddPair('kind', KindOrLsp);
  Result.AddPair('command', Command);
  Result.AddPair('target', Target);
  Result.AddPair('logFile', LogFile);
  Result.AddPair('version', Version);
  Result.AddPair('started', DateText(Started));
  Result.AddPair('memoryBytes', TJSONNumber.Create(MemoryBytes));
  Result.AddPair('state', State);
  mRunning := TJSONObject.Create;
  mRunning.AddPair('count', TJSONNumber.Create(Running));
  mRunning.AddPair('method', RunningMethod);
  mRunning.AddPair('ms', TJSONNumber.Create(RunningMs));
  Result.AddPair('running', mRunning);
  mProgress := TJSONObject.Create;
  mProgress.AddPair('done', TJSONNumber.Create(Done));
  mProgress.AddPair('total', TJSONNumber.Create(Total));
  Result.AddPair('progress', mProgress);
  Result.AddPair('timeouts', TJSONNumber.Create(Timeouts));
  Result.AddPair('errors', TJSONNumber.Create(Errors));
  if AStatus <> nil then
  begin
    Result.AddPair('status', TJSONObject(AStatus.Clone));
  end;
end;

/// <summary>Texte der Einträge in roots von AObject.</summary>
function RootsOf(AObject: TJSONObject): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AObject.GetValue('roots') is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AObject.GetValue('roots')) do
  begin
    if mItem is TJSONString then
    begin
      Result := Result + [mItem.Value];
    end;
  end;
end;

/// <summary>Laufende Anfragen und Fortschritt aus den Unterobjekten running und progress.</summary>
procedure ReadActivity(AObject: TJSONObject; var AEntry: TServerStatusEntry);
var
  mRunning, mProgress: TJSONObject;
begin
  mRunning := TJsonRead.Obj(AObject, 'running');
  mProgress := TJsonRead.Obj(AObject, 'progress');
  AEntry.Running := TJsonRead.Int(mRunning, 'count');
  AEntry.RunningMethod := TJsonRead.Text(mRunning, 'method');
  AEntry.RunningMs := TJsonRead.Int64Or(mRunning, 'ms', 0);
  AEntry.Done := TJsonRead.Int(mProgress, 'done');
  AEntry.Total := TJsonRead.Int(mProgress, 'total');
end;

class function TServerStatusEntry.FromJson(AObject: TJSONObject; out AEntry: TServerStatusEntry): Boolean;
var
  mPid, mWritten: TJSONValue;
begin
  AEntry := Default(TServerStatusEntry);
  mPid := AObject.GetValue('pid');
  mWritten := AObject.GetValue('written');
  Result := (mPid is TJSONNumber) and (mWritten is TJSONString) and
    TryISO8601ToDate(mWritten.Value, AEntry.Written, False);
  if not Result then
  begin
    Exit;
  end;
  AEntry.Pid := Cardinal(TJSONNumber(mPid).AsInt64);
  AEntry.Roots := RootsOf(AObject);
  AEntry.Kind := TJsonRead.Text(AObject, 'kind');
  AEntry.Command := TJsonRead.Text(AObject, 'command');
  AEntry.Target := TJsonRead.Text(AObject, 'target');
  AEntry.LogFile := TJsonRead.Text(AObject, 'logFile');
  AEntry.Version := TJsonRead.Text(AObject, 'version');
  AEntry.Started := DateOf(TJsonRead.Text(AObject, 'started'));
  AEntry.MemoryBytes := TJsonRead.Int64Or(AObject, 'memoryBytes', 0);
  AEntry.State := TJsonRead.Text(AObject, 'state');
  ReadActivity(AObject, AEntry);
  AEntry.Timeouts := TJsonRead.Int(AObject, 'timeouts');
  AEntry.Errors := TJsonRead.Int(AObject, 'errors');
  if AObject.GetValue('status') is TJSONObject then
  begin
    AEntry.Status := AObject.GetValue('status').ToJSON([]);
  end;
end;

{ TServerStatusFile }

class function TServerStatusFile.FolderOf(const ARoot: string): string;
begin
  Result := TPath.Combine(ARoot, cFolderName);
end;

class function TServerStatusFile.FileFor(const ARoot: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(FolderOf(ARoot), Format('server-%d.json', [APid]));
end;

class function TServerStatusFile.Matches(const AWorkspaceRoots: TArray<string>; const AFolder: string): Boolean;
var
  mRoot, mFolder, mWanted: string;
begin
  mWanted := NormalFolder(AFolder);
  for mRoot in AWorkspaceRoots do
  begin
    mFolder := NormalFolder(mRoot);
    if (mFolder = '/') or (mWanted = '/') then
    begin
      Continue;
    end;
    if mWanted.StartsWith(mFolder) or mFolder.StartsWith(mWanted) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Inhalt der Datei; '' wenn sie fehlt oder gerade ersetzt wird.</summary>
function ReadText(const AFileName: string): string;
begin
  try
    Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    // lsp-ignore: catch-all-without-raise -- Statusdatei nach Kräften; nur Anzeige
    on Exception do
      Result := '';
  end;
end;

/// <summary>Liest eine Statusdatei; False bei unlesbarem oder unvollständigem Inhalt.</summary>
function ReadEntry(const AFileName: string; out AEntry: TServerStatusEntry): Boolean;
var
  mText: string;
  mValue: TJSONValue;
begin
  Result := False;
  AEntry := Default(TServerStatusEntry);
  mText := ReadText(AFileName);
  if mText = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    if mValue is TJSONObject then
    begin
      Result := TServerStatusEntry.FromJson(TJSONObject(mValue), AEntry);
      AEntry.FileName := AFileName;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Löscht AFileName; Fehler bleiben still (ein anderer Leser war schneller).</summary>
procedure DeleteQuietly(const AFileName: string);
begin
  try
    if TFile.Exists(AFileName) then
    begin
      TFile.Delete(AFileName);
    end;
  except
    // lsp-ignore: catch-all-without-raise -- Statusdatei nach Kräften; nur Anzeige
    on Exception do
      Exit;
  end;
end;

/// <summary>Verwaiste Dateien anderer Prozesse in AFolder wegräumen (Absturz ohne Delete); AOwn bleibt.</summary>
procedure DeleteOrphans(const AFolder, AOwn: string; ANow: TDateTime);
var
  mOther: string;
  mEntry: TServerStatusEntry;
begin
  for mOther in TDirectory.GetFiles(AFolder, 'server-*.json') do
  begin
    if SameText(mOther, AOwn) then
    begin
      Continue;
    end;
    if not ReadEntry(mOther, mEntry) or (SecondsBetween(ANow, mEntry.Written) > TServerStatusFile.cOrphanSeconds)
    then
    begin
      DeleteQuietly(mOther);
    end;
  end;
end;

class procedure TServerStatusFile.Write(const ARoot: string; const AEntry: TServerStatusEntry;
  const AStatus: TJSONObject; ANow: TDateTime);
var
  mEntry: TServerStatusEntry;
  mJson: TJSONObject;
  mTarget, mTemp: string;
begin
  if ARoot = '' then
  begin
    Exit;
  end;
  mEntry := AEntry;
  mEntry.Written := ANow;
  mJson := mEntry.ToJson(AStatus);
  try
    try
      ForceDirectories(FolderOf(ARoot));
      mTarget := FileFor(ARoot, mEntry.Pid);
      // Erst vollständig schreiben, dann ersetzen: Ein Leser sieht nie eine halbe Datei.
      mTemp := mTarget + '.tmp';
      TFile.WriteAllText(mTemp, mJson.ToJSON([]), TEncoding.UTF8);
      if TFile.Exists(mTarget) then
      begin
        TFile.Delete(mTarget);
      end;
      TFile.Move(mTemp, mTarget);
      DeleteOrphans(FolderOf(ARoot), mTarget, ANow);
    except
      // lsp-ignore: catch-all-without-raise -- Statusdatei nach Kräften; nur Anzeige
      on Exception do
        // Nur Anzeige für MCP und AtlasMonitor; der Server arbeitet weiter.
        Exit;
    end;
  finally
    mJson.Free;
  end;
end;

class procedure TServerStatusFile.Write(const ARoot: string; APid: Cardinal; const AWorkspaceRoots: TArray<string>;
  const AStatus: TJSONObject; ANow: TDateTime);
var
  mEntry: TServerStatusEntry;
begin
  if AStatus = nil then
  begin
    Exit;
  end;
  mEntry := Default(TServerStatusEntry);
  mEntry.Pid := APid;
  mEntry.Roots := AWorkspaceRoots;
  mEntry.Kind := TServerStatusEntry.cKindLsp;
  TServerStatusFile.Write(ARoot, mEntry, AStatus, ANow);
end;

class procedure TServerStatusFile.Delete(const ARoot: string; APid: Cardinal);
begin
  DeleteQuietly(FileFor(ARoot, APid));
end;

class function TServerStatusFile.Find(const ARoot, AFolder: string; ANow: TDateTime; out AStatus: string;
  out APid: Cardinal; out AWritten: TDateTime): Boolean;
var
  mFile: string;
  mEntry: TServerStatusEntry;
begin
  Result := False;
  AStatus := '';
  APid := 0;
  AWritten := 0;
  if not TDirectory.Exists(FolderOf(ARoot)) then
  begin
    Exit;
  end;
  // Ohne Variable für die Dateiliste: Delphi liefert TStringDynArray, Free Pascal TArray<string>.
  for mFile in TDirectory.GetFiles(FolderOf(ARoot), 'server-*.json') do
  begin
    // Nur der LSP-Server der IDE trägt den ausführlichen Status.
    if not ReadEntry(mFile, mEntry) or (mEntry.Status = '') or (mEntry.KindOrLsp <> TServerStatusEntry.cKindLsp)
    then
    begin
      Continue;
    end;
    if (mEntry.Written > ANow + OneSecond * cMaxAgeSeconds) or (SecondsBetween(ANow, mEntry.Written) > cMaxAgeSeconds)
    then
    begin
      Continue;
    end;
    if not Matches(mEntry.Roots, AFolder) then
    begin
      Continue;
    end;
    // Jüngste gewinnt, bei Gleichstand die kleinere pid (eindeutig).
    if not Result or (mEntry.Written > AWritten) or ((mEntry.Written = AWritten) and (mEntry.Pid < APid)) then
    begin
      Result := True;
      AStatus := mEntry.Status;
      APid := mEntry.Pid;
      AWritten := mEntry.Written;
    end;
  end;
end;

/// <summary>Ordnung der Liste: früher gestartet zuerst, bei Gleichstand die kleinere pid.</summary>
function CompareEntries(const ALeft, ARight: TServerStatusEntry): Integer;
begin
  Result := CompareValue(ALeft.Started, ARight.Started);
  if Result = 0 then
  begin
    Result := CompareValue(Int64(ALeft.Pid), Int64(ARight.Pid));
  end;
end;

class function TServerStatusFile.List(const ARoot: string; ANow: TDateTime; const AIsAlive: TServerAliveFunc):
  TArray<TServerStatusEntry>;
var
  mFile: string;
  mEntry: TServerStatusEntry;
  mEntries: TList<TServerStatusEntry>;
begin
  Result := nil;
  if not TDirectory.Exists(FolderOf(ARoot)) then
  begin
    Exit;
  end;
  mEntries := TList<TServerStatusEntry>.Create;
  try
    for mFile in TDirectory.GetFiles(FolderOf(ARoot), 'server-*.json') do
    begin
      if not ReadEntry(mFile, mEntry) then
      begin
        Continue;
      end;
      if (SecondsBetween(ANow, mEntry.Written) > cOrphanSeconds) or (Assigned(AIsAlive) and not AIsAlive(mEntry.Pid))
      then
      begin
        DeleteQuietly(mFile);
        Continue;
      end;
      mEntries.Add(mEntry);
    end;
    mEntries.Sort(TComparer<TServerStatusEntry>.Construct(CompareEntries));
    Result := mEntries.ToArray;
  finally
    mEntries.Free;
  end;
end;

end.
