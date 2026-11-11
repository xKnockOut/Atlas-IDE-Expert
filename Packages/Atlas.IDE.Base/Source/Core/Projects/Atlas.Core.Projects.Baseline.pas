unit Atlas.Core.Projects.Baseline;

// Baseline des Projekts im Plugin (#97), ohne VCL und Open Tools API.
// - Befehl „Baseline des Projekts aktualisieren“ (Atlas.UpdateBaseline):
//   Argumente für den Serverbefehl atlas.updateBaseline und dessen Antwort
//   mit den Zählern (TAtlasBaselineUpdate).
// - Zustand der Datei im Projektordner (TAtlasBaselineState): atlas-baseline.json,
//   sonst der frühere Name delphi-lsp-baseline.json; Einträge, Treffer und
//   Einträge ohne Datei. Das Plugin liest ihn vor dem Aktualisieren (Rückfrage
//   zu den Einträgen ohne Datei, bevor sie entfernt werden) und nach jedem
//   Build für den Abschnitt "baseline" der Projekt-Zusammenfassung
//   (Projektverlauf #758, Einrichtung #759).
// - Ordner (#758): Der Server schreibt die Baseline in den Ordner des
//   Arbeitsbereichs, zu dem das Projekt gehört; das Plugin liest sie im
//   Projektordner. In RAD Studio ist das derselbe Ordner: Das Plugin meldet
//   jedes Projekt der Gruppe als eigenen Arbeitsbereich (Ordner der .dproj).
//   Abweichen kann er nur über Ausweichwege des Servers (Projekt noch nicht
//   als Arbeitsbereich bekannt). WrittenElsewhere erkennt das an der Antwort
//   ("file"); das Plugin meldet es dann und liest weiter den Projektordner.
//
// Pfade in der Baseline sind relativ zum Ordner der Datei und mit „/“
// getrennt; zum Prüfen setzt StateOf sie mit „\“ an den Ordner (das Plugin
// läuft nur unter Windows). Dateizugriffe kommen von außen (Tests ohne Platte);
// StateOnDisk ist die dünne Hülle mit der Platte für Base und das Modul
// Prüfregeln (#1455).
//
// Antwort von atlas.updateBaseline (Format 1):
//   {"format": 1, "file": "C:\\Projekte\\Kasse\\atlas-baseline.json",
//    "previous": "none|valid|invalid",
//    "setAside": "C:\\Projekte\\Kasse\\atlas-baseline.json.defekt" (nur nach
//    "invalid": die unbrauchbare bisherige Datei, Bericht N3),
//    "skipped": 0, "total": 120, "files": 40,
//    "added": 3, "removed": 5, "unchanged": 117, "completed": 0,
//    "orphaned": {"count": 2, "entries": [{"path": "Alt/U.pas", "count": 2}]}}

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Baseline,
  Atlas.Core.Projects.Summary;

type
  /// <summary>Treffer einer Datei, die es nicht mehr gibt; Path relativ wie in der Baseline.</summary>
  TAtlasBaselineOrphan = record
    Path: string;
    Count: Integer;
  end;

  TAtlasBaselineFileExists = reference to function(const AFileName: string): Boolean;
  /// <summary>Liest AFileName als Text; False, wenn die Datei nicht lesbar ist.</summary>
  TAtlasBaselineReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Stand der Baseline-Datei eines Projektordners.</summary>
  TAtlasBaselineState = record
    /// <summary>Voller Pfad; '' ohne Datei.</summary>
    FileName: string;
    Exists: Boolean;
    /// <summary>Lesbar und mit Liste "findings".</summary>
    Valid: Boolean;
    Entries: Integer;
    /// <summary>Summe von "count" (ohne "count" 1 je Eintrag).</summary>
    Hits: Integer;
    /// <summary>Je Pfad zusammengefasst, in der Reihenfolge der Datei.</summary>
    Orphans: TArray<TAtlasBaselineOrphan>;
    /// <summary>Treffer in Orphans.</summary>
    function OrphanCount: Integer;
  end;

  /// <summary>Antwort von atlas.updateBaseline.</summary>
  TAtlasBaselineUpdate = record
    FileName: string;
    /// <summary>"none", "valid" oder "invalid": bisherige Datei.</summary>
    Previous: string;
    /// <summary>Voller Pfad, unter dem der Server eine unbrauchbare bisherige Baseline beiseitegelegt hat
    /// (Bericht N3); '' sonst.</summary>
    SetAside: string;
    Skipped: Integer;
    Total: Integer;
    Files: Integer;
    Added: Integer;
    Removed: Integer;
    Unchanged: Integer;
    Completed: Integer;
    Orphans: TArray<TAtlasBaselineOrphan>;
    /// <summary>"orphaned.count" der Antwort (Treffer in Orphans).</summary>
    OrphanCount: Integer;
  end;

  TAtlasProjectBaselines = class
  public const
    cCommand = 'atlas.updateBaseline';
    /// <summary>Zeitlimit des Befehls: Er prüft alle Dateien des Projekts.</summary>
    cTimeoutMs = 600000;
    cFileName = TAtlasBaselineInfo.cFileName;
    cLegacyFileName = TAtlasBaselineInfo.cLegacyFileName;
  public
    /// <summary>AFolder\atlas-baseline.json, sonst AFolder\delphi-lsp-baseline.json, wenn nur diese existiert;
    /// '' ohne Datei.</summary>
    class function FileIn(const AFolder: string; const AExists: TAtlasBaselineFileExists): string; static;
    /// <summary>Zustand der Baseline in AFolder; Einträge ohne Datei über AExists (AFolder\Pfad).</summary>
    class function StateOf(const AFolder: string; const AExists: TAtlasBaselineFileExists;
      const ARead: TAtlasBaselineReadText): TAtlasBaselineState; static;
    /// <summary>StateOf mit der Platte (FileExists, UTF-8); auch im Hintergrund. Eine unlesbare Datei zählt als
    /// vorhanden, aber ungültig.</summary>
    class function StateOnDisk(const AFolder: string): TAtlasBaselineState; static;
    /// <summary>Wie StateOf, aber aus dem Text AText einer Datei in AFolder.</summary>
    class function StateOfText(const AFolder, AText: string; const AExists: TAtlasBaselineFileExists):
      TAtlasBaselineState; static;
    /// <summary>Hat der Server die Baseline AWrittenFile außerhalb des Ordners von AProject geschrieben? Pfade
    /// ohne Rücksicht auf Groß-/Kleinschreibung, „/“ oder „\“; False, wenn eine Angabe fehlt.</summary>
    class function WrittenElsewhere(const AProject, AWrittenFile: string): Boolean; static;
    /// <summary>Argumente für atlas.updateBaseline: [uri].</summary>
    class function Arguments(const AProjectUri: string): string; static;
    /// <summary>Liest die Antwort von atlas.updateBaseline; False bei leerem oder ungültigem Text.</summary>
    class function FromServer(const AJson: string; out AUpdate: TAtlasBaselineUpdate): Boolean; static;
    /// <summary>Abschnitt "baseline" der Projekt-Zusammenfassung nach dem Lesen der Datei; Updated, Added und
    /// Removed bleiben.</summary>
    class procedure Measured(var ASection: TAtlasProjectBaseline; const AState: TAtlasBaselineState;
      AAtUtc: TDateTime); static;
    /// <summary>Nach dem Aktualisieren: Zähler aus AUpdate, Zeitpunkt AAtUtc, Zustand aus AState (Datei danach).
    /// </summary>
    class procedure Updated(var ASection: TAtlasProjectBaseline; const AUpdate: TAtlasBaselineUpdate;
      const AState: TAtlasBaselineState; AAtUtc: TDateTime); static;
  end;

implementation

uses
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.Json;

/// <summary>Ordner von AFileName, normiert (Großbuchstaben, „\“, ohne Trenner am Ende); '' ohne Ordner.</summary>
function FolderKey(const AFileName: string): string;
var
  mIndex: Integer;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(AFileName);
  mIndex := Length(Result);
  while (mIndex > 0) and (Result[mIndex] <> '\') do
  begin
    Dec(mIndex);
  end;
  Result := Copy(Result, 1, mIndex - 1);
end;

{ TAtlasBaselineState }

function TAtlasBaselineState.OrphanCount: Integer;
var
  mOrphan: TAtlasBaselineOrphan;
begin
  Result := 0;
  for mOrphan in Orphans do
  begin
    Inc(Result, mOrphan.Count);
  end;
end;

{ Helfer }

function Joined(const AFolder, AName: string): string;
begin
  Result := AFolder;
  if (Result <> '') and not CharInSet(Result[Length(Result)], ['\', '/']) then
  begin
    Result := Result + '\';
  end;
  Result := Result + AName;
end;

function ParseObject(const AText: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  try
    mValue := TJSONObject.ParseJSONValue(AText);
  except
    on Exception do
      mValue := nil;
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

/// <summary>Fügt ACount Treffer zu APath hinzu (gleicher Pfad ohne Rücksicht auf Groß-/Kleinschreibung).</summary>
procedure AddOrphan(var AOrphans: TArray<TAtlasBaselineOrphan>; const APath: string; ACount: Integer);
var
  mIndex: Integer;
  mOrphan: TAtlasBaselineOrphan;
begin
  for mIndex := 0 to High(AOrphans) do
  begin
    if SameText(AOrphans[mIndex].Path, APath) then
    begin
      Inc(AOrphans[mIndex].Count, ACount);
      Exit;
    end;
  end;
  mOrphan.Path := APath;
  mOrphan.Count := ACount;
  AOrphans := AOrphans + [mOrphan];
end;

{ TAtlasProjectBaselines }

class function TAtlasProjectBaselines.WrittenElsewhere(const AProject, AWrittenFile: string): Boolean;
begin
  Result := (Trim(AProject) <> '') and (Trim(AWrittenFile) <> '') and (FolderKey(AProject) <> FolderKey(AWrittenFile));
end;

class function TAtlasProjectBaselines.FileIn(const AFolder: string; const AExists: TAtlasBaselineFileExists): string;
begin
  Result := '';
  if AFolder = '' then
  begin
    Exit;
  end;
  if AExists(Joined(AFolder, cFileName)) then
  begin
    Exit(Joined(AFolder, cFileName));
  end;
  if AExists(Joined(AFolder, cLegacyFileName)) then
  begin
    Result := Joined(AFolder, cLegacyFileName);
  end;
end;

type
  /// <summary>Fragt je Pfad einer Grundlinie nur einmal, ob die Datei fehlt: Eine Datei hat oft viele
  /// Einträge.</summary>
  TBaselineFileCheck = class
  private
    FFolder: string;
    FExists: TAtlasBaselineFileExists;
    FGone: TDictionary<string, Boolean>;
  public
    constructor Create(const AFolder: string; const AExists: TAtlasBaselineFileExists);
    destructor Destroy; override;
    /// <summary>True, wenn die Datei zu APath (relativ zu AFolder, „/“ erlaubt) fehlt; False ohne Pfad oder
    /// ohne AExists.</summary>
    function Gone(const APath: string): Boolean;
  end;

constructor TBaselineFileCheck.Create(const AFolder: string; const AExists: TAtlasBaselineFileExists);
begin
  inherited Create;
  FFolder := AFolder;
  FExists := AExists;
  FGone := TDictionary<string, Boolean>.Create;
end;

destructor TBaselineFileCheck.Destroy;
begin
  FGone.Free;
  inherited;
end;

function TBaselineFileCheck.Gone(const APath: string): Boolean;
var
  mKey: string;
begin
  Result := False;
  if (APath = '') or not Assigned(FExists) then
  begin
    Exit;
  end;
  // Wie SameText: nur ASCII ohne Groß- und Kleinschreibung.
  mKey := UpperCase(APath);
  if not FGone.TryGetValue(mKey, Result) then
  begin
    Result := not FExists(Joined(FFolder, StringReplace(APath, '/', '\', [rfReplaceAll])));
    FGone.Add(mKey, Result);
  end;
end;

/// <summary>Anzahl (Vorgabe 1) und Pfad eines Eintrags aus findings.</summary>
procedure ReadBaselineEntry(AItem: TJSONValue; out ACount: Integer; out APath: string);
begin
  ACount := 1;
  APath := '';
  if AItem is TJSONObject then
  begin
    ACount := TJsonRead.IntOr(TJSONObject(AItem), 'count', 1);
    APath := TJsonRead.Text(TJSONObject(AItem), 'path');
  end;
end;

class function TAtlasProjectBaselines.StateOfText(const AFolder, AText: string;
  const AExists: TAtlasBaselineFileExists): TAtlasBaselineState;
var
  mRoot: TJSONObject;
  mFindings, mItem: TJSONValue;
  mPath: string;
  mCount: Integer;
  mCheck: TBaselineFileCheck;
begin
  Result := Default(TAtlasBaselineState);
  Result.Orphans := nil;
  Result.Exists := True;
  mRoot := ParseObject(AText);
  mCheck := TBaselineFileCheck.Create(AFolder, AExists);
  try
    if mRoot = nil then
    begin
      Exit;
    end;
    mFindings := mRoot.GetValue('findings');
    if not (mFindings is TJSONArray) then
    begin
      Exit;
    end;
    Result.Valid := True;
    for mItem in TJSONArray(mFindings) do
    begin
      Inc(Result.Entries);
      ReadBaselineEntry(mItem, mCount, mPath);
      Inc(Result.Hits, mCount);
      if mCheck.Gone(mPath) then
      begin
        AddOrphan(Result.Orphans, mPath, mCount);
      end;
    end;
  finally
    mCheck.Free;
    mRoot.Free;
  end;
end;

class function TAtlasProjectBaselines.StateOf(const AFolder: string; const AExists: TAtlasBaselineFileExists;
  const ARead: TAtlasBaselineReadText): TAtlasBaselineState;
var
  mName, mText: string;
begin
  Result := Default(TAtlasBaselineState);
  Result.Orphans := nil;
  mName := FileIn(AFolder, AExists);
  if mName = '' then
  begin
    Exit;
  end;
  if ARead(mName, mText) then
  begin
    Result := StateOfText(AFolder, mText, AExists);
  end
  else
  begin
    Result.Exists := True;
  end;
  Result.FileName := mName;
end;

function FileOnDisk(const AFileName: string): Boolean;
begin
  Result := FileExists(AFileName);
end;

function ReadFromDisk(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  try
    AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
    Result := True;
  except
    on Exception do
      Result := False;
  end;
end;

class function TAtlasProjectBaselines.StateOnDisk(const AFolder: string): TAtlasBaselineState;
begin
  Result := StateOf(AFolder, FileOnDisk, ReadFromDisk);
end;

class function TAtlasProjectBaselines.Arguments(const AProjectUri: string): string;
var
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AProjectUri);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

/// <summary>Liest orphaned der Serverantwort: Einträge ohne Datei und ihre Anzahl.</summary>
procedure ReadServerOrphans(ARoot: TJSONObject; var AUpdate: TAtlasBaselineUpdate);
var
  mOrphaned: TJSONObject;
  mEntries, mItem: TJSONValue;
  mPath: string;
begin
  if not (ARoot.GetValue('orphaned') is TJSONObject) then
  begin
    Exit;
  end;
  mOrphaned := TJSONObject(ARoot.GetValue('orphaned'));
  mEntries := mOrphaned.GetValue('entries');
  if mEntries is TJSONArray then
  begin
    for mItem in TJSONArray(mEntries) do
    begin
      mPath := '';
      if mItem is TJSONObject then
      begin
        mPath := TJsonRead.Text(TJSONObject(mItem), 'path');
      end;
      if mPath <> '' then
      begin
        AddOrphan(AUpdate.Orphans, mPath, TJsonRead.IntOr(TJSONObject(mItem), 'count', 1));
      end;
    end;
  end;
  AUpdate.OrphanCount := TJsonRead.IntOr(mOrphaned, 'count', 0);
end;

class function TAtlasProjectBaselines.FromServer(const AJson: string; out AUpdate: TAtlasBaselineUpdate): Boolean;
var
  mRoot: TJSONObject;
begin
  AUpdate := Default(TAtlasBaselineUpdate);
  AUpdate.Orphans := nil;
  mRoot := ParseObject(AJson);
  try
    Result := (mRoot <> nil) and (mRoot.GetValue('total') is TJSONNumber) and (TJsonRead.Text(mRoot, 'file') <> '');
    if not Result then
    begin
      Exit;
    end;
    AUpdate.FileName := TJsonRead.Text(mRoot, 'file');
    AUpdate.Previous := TJsonRead.Text(mRoot, 'previous');
    AUpdate.SetAside := TJsonRead.Text(mRoot, 'setAside');
    AUpdate.Skipped := TJsonRead.IntOr(mRoot, 'skipped', 0);
    AUpdate.Total := TJsonRead.IntOr(mRoot, 'total', 0);
    AUpdate.Files := TJsonRead.IntOr(mRoot, 'files', 0);
    AUpdate.Added := TJsonRead.IntOr(mRoot, 'added', 0);
    AUpdate.Removed := TJsonRead.IntOr(mRoot, 'removed', 0);
    AUpdate.Unchanged := TJsonRead.IntOr(mRoot, 'unchanged', 0);
    AUpdate.Completed := TJsonRead.IntOr(mRoot, 'completed', 0);
    ReadServerOrphans(mRoot, AUpdate);
  finally
    mRoot.Free;
  end;
end;

class procedure TAtlasProjectBaselines.Measured(var ASection: TAtlasProjectBaseline;
  const AState: TAtlasBaselineState; AAtUtc: TDateTime);
begin
  ASection.Known := True;
  ASection.At := AAtUtc;
  ASection.Exists := AState.Exists;
  ASection.Valid := AState.Valid;
  ASection.Entries := AState.Entries;
  ASection.Hits := AState.Hits;
  ASection.Orphaned := AState.OrphanCount;
end;

class procedure TAtlasProjectBaselines.Updated(var ASection: TAtlasProjectBaseline;
  const AUpdate: TAtlasBaselineUpdate; const AState: TAtlasBaselineState; AAtUtc: TDateTime);
begin
  Measured(ASection, AState, AAtUtc);
  ASection.Updated := AAtUtc;
  ASection.Added := AUpdate.Added;
  ASection.Removed := AUpdate.Removed;
end;

end.
