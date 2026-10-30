unit Atlas.Common.Lsp.StatusFile;

// Letzter Status des Servers als Datei (#1356), damit das MCP-Werkzeug
// get_server_status dieselben Zahlen zeigt wie das Fenster „Atlas-Server“ der
// IDE. Der MCP-Prozess ist ein eigener Prozess ohne Verbindung zum Server der
// IDE; dieser schreibt deshalb bei jeder Abfrage von atlas.server.status (das
// Plugin fragt alle 5 s, solange der Server läuft) die Antwort nach
// %LOCALAPPDATA%\Atlas\Status\server-<pid>.json, mit den Wurzeln seiner
// Arbeitsbereiche und dem Zeitpunkt. Find wählt die jüngste Datei, die nicht
// älter als MaxAgeSeconds ist und deren Wurzeln den Ordner enthalten bzw. in
// ihm liegen. Beim Beenden löscht der Server seine Datei; eine liegen
// gebliebene veraltet und wird beim nächsten Schreiben eines Servers
// weggeräumt. Die Datei bleibt lokal; Pfade stehen nur darin, weil der Status
// selbst sie enthält.

interface

uses
  System.SysUtils,
  System.JSON;

type
  TServerStatusFile = record
  public const
    FolderName = 'Status';
    /// <summary>Ältere Dateien gelten als verwaist (Server abgestürzt oder ohne Abfrage).</summary>
    MaxAgeSeconds = 60;
  public
    class function FolderOf(const ARoot: string): string; static;
    class function FileFor(const ARoot: string; APid: Cardinal): string; static;
    /// <summary>Schreibt den Status (Kopie von AStatus) mit pid, Zeitpunkt und Wurzeln; ersetzt die vorige Datei
    /// und löscht verwaiste anderer Prozesse. Fehler beim Schreiben bleiben still (nur Anzeige).</summary>
    class procedure Write(const ARoot: string; APid: Cardinal; const AWorkspaceRoots: TArray<string>;
      const AStatus: TJSONObject; ANow: TDateTime); static;
    class procedure Delete(const ARoot: string; APid: Cardinal); static;
    /// <summary>True, wenn AFolder eine der Wurzeln ist, darunter oder darüber liegt (ohne Groß-/Kleinschreibung).
    /// </summary>
    class function Matches(const AWorkspaceRoots: TArray<string>; const AFolder: string): Boolean; static;
    /// <summary>Jüngster gültiger Status für AFolder: AStatus als JSON-Text, APid und AWritten; False ohne.</summary>
    class function Find(const ARoot, AFolder: string; ANow: TDateTime; out AStatus: string; out APid: Cardinal;
      out AWritten: TDateTime): Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils;

/// <summary>Ordner zum Vergleichen: klein, beide Trenner als „/“, mit „/“ am Ende.</summary>
function NormalFolder(const AFolder: string): string;
begin
  Result := AnsiLowerCase(StringReplace(Trim(AFolder), '\', '/', [rfReplaceAll]));
  if not Result.EndsWith('/') then
    Result := Result + '/';
end;

class function TServerStatusFile.FolderOf(const ARoot: string): string;
begin
  Result := TPath.Combine(ARoot, FolderName);
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
      Continue;
    if mWanted.StartsWith(mFolder) or mFolder.StartsWith(mWanted) then
      Exit(True);
  end;
  Result := False;
end;

/// <summary>Inhalt der Datei; '' wenn sie fehlt oder gerade ersetzt wird.</summary>
function ReadText(const AFileName: string): string;
begin
  try
    Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    on Exception do
      Result := '';
  end;
end;

/// <summary>Liest eine Statusdatei; False bei unlesbarem oder unvollständigem Inhalt.</summary>
function ReadEntry(const AFileName: string; out APid: Cardinal; out AWritten: TDateTime;
  out ARoots: TArray<string>; out AStatus: string): Boolean;
var
  mText: string;
  mValue: TJSONValue;
  mObject: TJSONObject;
  mItem: TJSONValue;
  mStatus: TJSONValue;
  mPid: TJSONValue;
  mWritten: TJSONValue;
begin
  Result := False;
  APid := 0;
  AWritten := 0;
  ARoots := nil;
  AStatus := '';
  mText := ReadText(AFileName);
  if mText = '' then
    Exit;
  mValue := TJSONObject.ParseJSONValue(mText);
  if mValue = nil then
    Exit;
  try
    if mValue is TJSONObject then
    begin
      mObject := TJSONObject(mValue);
      mPid := mObject.GetValue('pid');
      mWritten := mObject.GetValue('written');
      mStatus := mObject.GetValue('status');
      if (mPid is TJSONNumber) and (mWritten is TJSONString) and (mStatus is TJSONObject) and
        TryISO8601ToDate(mWritten.Value, AWritten, False) then
      begin
        APid := Cardinal(TJSONNumber(mPid).AsInt64);
        if mObject.GetValue('roots') is TJSONArray then
          for mItem in TJSONArray(mObject.GetValue('roots')) do
            if mItem is TJSONString then
              ARoots := ARoots + [mItem.Value];
        AStatus := mStatus.ToJSON;
        Result := True;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class procedure TServerStatusFile.Write(const ARoot: string; APid: Cardinal; const AWorkspaceRoots: TArray<string>;
  const AStatus: TJSONObject; ANow: TDateTime);
var
  mEntry: TJSONObject;
  mRoots: TJSONArray;
  mRoot, mTarget, mTemp, mOther: string;
  mOtherPid: Cardinal;
  mWritten: TDateTime;
  mOtherRoots: TArray<string>;
  mOtherStatus: string;
  mOrphan: Boolean;
begin
  if (ARoot = '') or (AStatus = nil) then
    Exit;
  mEntry := TJSONObject.Create;
  try
    mEntry.AddPair('pid', TJSONNumber.Create(APid));
    mEntry.AddPair('written', DateToISO8601(ANow, False));
    mRoots := TJSONArray.Create;
    for mRoot in AWorkspaceRoots do
      mRoots.Add(mRoot);
    mEntry.AddPair('roots', mRoots);
    mEntry.AddPair('status', TJSONObject(AStatus.Clone));
    try
      ForceDirectories(FolderOf(ARoot));
      mTarget := FileFor(ARoot, APid);
      // Erst vollständig schreiben, dann ersetzen: Ein Leser sieht nie eine halbe Datei.
      mTemp := mTarget + '.tmp';
      TFile.WriteAllText(mTemp, mEntry.ToJSON([]), TEncoding.UTF8);
      if TFile.Exists(mTarget) then
        TFile.Delete(mTarget);
      TFile.Move(mTemp, mTarget);
      // Verwaiste Dateien anderer Prozesse wegräumen (Absturz ohne Delete).
      for mOther in TDirectory.GetFiles(FolderOf(ARoot), 'server-*.json') do
      begin
        if SameText(mOther, mTarget) then
          Continue;
        mOrphan := not ReadEntry(mOther, mOtherPid, mWritten, mOtherRoots, mOtherStatus);
        if not mOrphan then
          mOrphan := SecondsBetween(ANow, mWritten) > 10 * MaxAgeSeconds;
        if mOrphan then
          TFile.Delete(mOther);
      end;
    except
      on Exception do
        // Nur Anzeige für MCP; der Status selbst ist schon beantwortet.
        Exit;
    end;
  finally
    mEntry.Free;
  end;
end;

class procedure TServerStatusFile.Delete(const ARoot: string; APid: Cardinal);
begin
  try
    if TFile.Exists(FileFor(ARoot, APid)) then
      TFile.Delete(FileFor(ARoot, APid));
  except
    on Exception do
      Exit;
  end;
end;

class function TServerStatusFile.Find(const ARoot, AFolder: string; ANow: TDateTime; out AStatus: string;
  out APid: Cardinal; out AWritten: TDateTime): Boolean;
var
  mFile: string;
  mPid: Cardinal;
  mWritten: TDateTime;
  mRoots: TArray<string>;
  mStatus: string;
begin
  Result := False;
  AStatus := '';
  APid := 0;
  AWritten := 0;
  if not TDirectory.Exists(FolderOf(ARoot)) then
    Exit;
  // Ohne Variable für die Dateiliste: Delphi liefert TStringDynArray, Free Pascal TArray<string>.
  for mFile in TDirectory.GetFiles(FolderOf(ARoot), 'server-*.json') do
  begin
    if not ReadEntry(mFile, mPid, mWritten, mRoots, mStatus) then
      Continue;
    if (mWritten > ANow + OneSecond * MaxAgeSeconds) or (SecondsBetween(ANow, mWritten) > MaxAgeSeconds) then
      Continue;
    if not Matches(mRoots, AFolder) then
      Continue;
    // Jüngste gewinnt, bei Gleichstand die kleinere pid (eindeutig).
    if not Result or (mWritten > AWritten) or ((mWritten = AWritten) and (mPid < APid)) then
    begin
      Result := True;
      AStatus := mStatus;
      APid := mPid;
      AWritten := mWritten;
    end;
  end;
end;

end.
