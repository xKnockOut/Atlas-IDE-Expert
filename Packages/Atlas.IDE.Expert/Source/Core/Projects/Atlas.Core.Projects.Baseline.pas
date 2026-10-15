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
//
// Pfade in der Baseline sind relativ zum Ordner der Datei und mit „/“
// getrennt; zum Prüfen setzt StateOf sie mit „\“ an den Ordner (das Plugin
// läuft nur unter Windows). Dateizugriffe kommen von außen (Tests ohne Platte).
//
// Antwort von atlas.updateBaseline (Format 1):
//   {"format": 1, "file": "C:\\Projekte\\Kasse\\atlas-baseline.json",
//    "previous": "none|valid|invalid", "skipped": 0, "total": 120, "files": 40,
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
    Command = 'atlas.updateBaseline';
    /// <summary>Zeitlimit des Befehls: Er prüft alle Dateien des Projekts.</summary>
    TimeoutMs = 600000;
    FileName = TAtlasBaselineInfo.FileName;
    LegacyFileName = TAtlasBaselineInfo.LegacyFileName;
  public
    /// <summary>AFolder\atlas-baseline.json, sonst AFolder\delphi-lsp-baseline.json, wenn nur diese existiert;
    /// '' ohne Datei.</summary>
    class function FileIn(const AFolder: string; const AExists: TAtlasBaselineFileExists): string; static;
    /// <summary>Zustand der Baseline in AFolder; Einträge ohne Datei über AExists (AFolder\Pfad).</summary>
    class function StateOf(const AFolder: string; const AExists: TAtlasBaselineFileExists;
      const ARead: TAtlasBaselineReadText): TAtlasBaselineState; static;
    /// <summary>Wie StateOf, aber aus dem Text AText einer Datei in AFolder.</summary>
    class function StateOfText(const AFolder, AText: string; const AExists: TAtlasBaselineFileExists):
      TAtlasBaselineState; static;
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
  System.JSON;

{ TAtlasBaselineState }

function TAtlasBaselineState.OrphanCount: Integer;
var
  Orphan: TAtlasBaselineOrphan;
begin
  Result := 0;
  for Orphan in Orphans do
    Inc(Result, Orphan.Count);
end;

{ Helfer }

function Joined(const AFolder, AName: string): string;
begin
  Result := AFolder;
  if (Result <> '') and not CharInSet(Result[Length(Result)], ['\', '/']) then
    Result := Result + '\';
  Result := Result + AName;
end;

function NumberOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function ParseObject(const AText: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  try
    Value := TJSONObject.ParseJSONValue(AText);
  except
    on Exception do
      Value := nil;
  end;
  if Value is TJSONObject then
    Result := TJSONObject(Value)
  else
    Value.Free;
end;

/// <summary>Fügt ACount Treffer zu APath hinzu (gleicher Pfad ohne Rücksicht auf Groß-/Kleinschreibung).</summary>
procedure AddOrphan(var AOrphans: TArray<TAtlasBaselineOrphan>; const APath: string; ACount: Integer);
var
  Index: Integer;
  Orphan: TAtlasBaselineOrphan;
begin
  for Index := 0 to High(AOrphans) do
    if SameText(AOrphans[Index].Path, APath) then
    begin
      Inc(AOrphans[Index].Count, ACount);
      Exit;
    end;
  Orphan.Path := APath;
  Orphan.Count := ACount;
  AOrphans := AOrphans + [Orphan];
end;

{ TAtlasProjectBaselines }

class function TAtlasProjectBaselines.FileIn(const AFolder: string; const AExists: TAtlasBaselineFileExists): string;
begin
  Result := '';
  if AFolder = '' then
    Exit;
  if AExists(Joined(AFolder, FileName)) then
    Exit(Joined(AFolder, FileName));
  if AExists(Joined(AFolder, LegacyFileName)) then
    Result := Joined(AFolder, LegacyFileName);
end;

class function TAtlasProjectBaselines.StateOfText(const AFolder, AText: string;
  const AExists: TAtlasBaselineFileExists): TAtlasBaselineState;
var
  Root: TJSONObject;
  Findings, Item: TJSONValue;
  Path: string;
  Count: Integer;
  Known: TArray<string>;
  Missing: TArray<string>;
  Index: Integer;
  Found, Gone: Boolean;
begin
  Result := Default(TAtlasBaselineState);
  Result.Orphans := nil;
  Result.Exists := True;
  Known := nil;
  Missing := nil;
  Root := ParseObject(AText);
  try
    if Root = nil then
      Exit;
    Findings := Root.GetValue('findings');
    if not (Findings is TJSONArray) then
      Exit;
    Result.Valid := True;
    for Item in TJSONArray(Findings) do
    begin
      Inc(Result.Entries);
      Count := 1;
      Path := '';
      if Item is TJSONObject then
      begin
        Count := NumberOf(TJSONObject(Item), 'count', 1);
        Path := TextOf(TJSONObject(Item), 'path');
      end;
      Inc(Result.Hits, Count);
      if (Path = '') or not Assigned(AExists) then
        Continue;
      // Jeden Pfad nur einmal prüfen: Eine Datei hat oft viele Einträge.
      Found := False;
      Gone := False;
      for Index := 0 to High(Known) do
        if SameText(Known[Index], Path) then
        begin
          Found := True;
          Gone := Missing[Index] <> '';
          Break;
        end;
      if not Found then
      begin
        Gone := not AExists(Joined(AFolder, StringReplace(Path, '/', '\', [rfReplaceAll])));
        Known := Known + [Path];
        if Gone then
          Missing := Missing + [Path]
        else
          Missing := Missing + [''];
      end;
      if Gone then
        AddOrphan(Result.Orphans, Path, Count);
    end;
  finally
    Root.Free;
  end;
end;

class function TAtlasProjectBaselines.StateOf(const AFolder: string; const AExists: TAtlasBaselineFileExists;
  const ARead: TAtlasBaselineReadText): TAtlasBaselineState;
var
  Name, Text: string;
begin
  Result := Default(TAtlasBaselineState);
  Result.Orphans := nil;
  Name := FileIn(AFolder, AExists);
  if Name = '' then
    Exit;
  if ARead(Name, Text) then
    Result := StateOfText(AFolder, Text, AExists)
  else
    Result.Exists := True;
  Result.FileName := Name;
end;

class function TAtlasProjectBaselines.Arguments(const AProjectUri: string): string;
var
  Items: TJSONArray;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AProjectUri);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasProjectBaselines.FromServer(const AJson: string; out AUpdate: TAtlasBaselineUpdate): Boolean;
var
  Root, Orphaned: TJSONObject;
  Entries, Item: TJSONValue;
  Path: string;
begin
  AUpdate := Default(TAtlasBaselineUpdate);
  AUpdate.Orphans := nil;
  Result := False;
  Root := ParseObject(AJson);
  try
    if (Root = nil) or not (Root.GetValue('total') is TJSONNumber) or (TextOf(Root, 'file') = '') then
      Exit;
    AUpdate.FileName := TextOf(Root, 'file');
    AUpdate.Previous := TextOf(Root, 'previous');
    AUpdate.Skipped := NumberOf(Root, 'skipped', 0);
    AUpdate.Total := NumberOf(Root, 'total', 0);
    AUpdate.Files := NumberOf(Root, 'files', 0);
    AUpdate.Added := NumberOf(Root, 'added', 0);
    AUpdate.Removed := NumberOf(Root, 'removed', 0);
    AUpdate.Unchanged := NumberOf(Root, 'unchanged', 0);
    AUpdate.Completed := NumberOf(Root, 'completed', 0);
    Orphaned := nil;
    if Root.GetValue('orphaned') is TJSONObject then
      Orphaned := TJSONObject(Root.GetValue('orphaned'));
    if Orphaned <> nil then
    begin
      Entries := Orphaned.GetValue('entries');
      if Entries is TJSONArray then
        for Item in TJSONArray(Entries) do
          if Item is TJSONObject then
          begin
            Path := TextOf(TJSONObject(Item), 'path');
            if Path <> '' then
              AddOrphan(AUpdate.Orphans, Path, NumberOf(TJSONObject(Item), 'count', 1));
          end;
      AUpdate.OrphanCount := NumberOf(Orphaned, 'count', 0);
    end;
    Result := True;
  finally
    Root.Free;
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
