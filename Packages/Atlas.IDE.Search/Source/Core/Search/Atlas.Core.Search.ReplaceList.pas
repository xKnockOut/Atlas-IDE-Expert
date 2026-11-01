unit Atlas.Core.Search.ReplaceList;

// Auswahl der Treffer zum Ersetzen über mehrere Dateien (#893), ohne VCL und
// Open Tools API: das Modell hinter der Liste „Atlas-Suche: Ersetzen“.
// - Jeder Treffer hat ein Häkchen (Vorgabe an), jede Datei eines für alle
//   ihre Treffer: Es ist gesetzt, solange alle Treffer der Datei angehakt sind.
// - Rows: Zeilen für die Liste, je Datei eine Kopfzeile, darunter die Treffer
//   mit „Zeile: Text“ und bei Regex der Vorschau „vorher → nachher“.
// - Plan: Textänderungen für alle angehakten Treffer als WorkspaceEdit.
//   Schreibgeschützte Dateien (AIsReadOnly) und Dateien, deren Text sich seit
//   der Suche geändert hat (ACurrentText), fallen heraus und werden genannt:
//   Die Positionen der Treffer stimmen dort nicht mehr sicher.
// Mit allen Treffern angehakt ist Plan auch „Alle ersetzen“ (eine Datei oder
// mehrere).

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Files;

type
{$SCOPEDENUMS ON}
  TAtlasReplaceRowKind = (FileRow, HitRow);
{$SCOPEDENUMS OFF}

  TAtlasReplaceRow = record
    Kind: TAtlasReplaceRowKind;
    FileIndex: Integer;
    /// <summary>-1 bei der Kopfzeile einer Datei.</summary>
    HitIndex: Integer;
    Checked: Boolean;
    FileName: string;
    /// <summary>Zeile des Treffers, 1-basiert (Kopfzeile: 0).</summary>
    Line: Integer;
    /// <summary>Kopfzeile: Dateiname; Treffer: Zeilentext.</summary>
    Text: string;
    /// <summary>„vorher → nachher“ bei Regex, sonst ''.</summary>
    Preview: string;
  end;

  /// <summary>Ist die Datei schreibgeschützt?</summary>
  TAtlasReplaceFileCheck = reference to function(const AFileName: string): Boolean;
  /// <summary>Aktueller Text der Datei (Puffer der IDE vor der Platte).</summary>
  TAtlasReplaceFileText = reference to function(const AFileName: string): string;

  TAtlasReplacePlan = record
    Edit: TLspWorkspaceEdit;
    Replacements: Integer;
    Files: Integer;
    ReadOnly: TArray<string>;
    Changed: TArray<string>;
  end;

  TAtlasReplaceList = class
  private
    FResults: TArray<TAtlasFileHits>;
    FChecked: TArray<TArray<Boolean>>;
    FQuery: TAtlasSearchQuery;
    FReplace: string;
  public
    constructor Create(const AQuery: TAtlasSearchQuery; const AReplace: string);
    /// <summary>Datei mit Treffern dazu (die Suche meldet nach und nach); alle angehakt.</summary>
    procedure Add(const AFile: TAtlasFileHits);
    procedure SetFileChecked(AFile: Integer; AValue: Boolean);
    procedure SetHitChecked(AFile, AHit: Integer; AValue: Boolean);
    function FileChecked(AFile: Integer): Boolean;
    function HitChecked(AFile, AHit: Integer): Boolean;
    function CheckedCount: Integer;
    function HitCount: Integer;
    function Rows: TArray<TAtlasReplaceRow>;
    function Plan(const AIsReadOnly: TAtlasReplaceFileCheck; const ACurrentText: TAtlasReplaceFileText):
      TAtlasReplacePlan;
    property Results: TArray<TAtlasFileHits> read FResults;
    property Query: TAtlasSearchQuery read FQuery;
    /// <summary>Ersatztext; die Leiste setzt ihn vor Rows und Plan neu (das Feld kann sich ändern).</summary>
    property Replace: string read FReplace write FReplace;
  end;

implementation

uses
  Atlas.Core.Search.Replace;

{ TAtlasReplaceList }

constructor TAtlasReplaceList.Create(const AQuery: TAtlasSearchQuery; const AReplace: string);
begin
  inherited Create;
  FQuery := AQuery;
  FReplace := AReplace;
end;

procedure TAtlasReplaceList.Add(const AFile: TAtlasFileHits);
var
  Checks: TArray<Boolean>;
  Index: Integer;
begin
  if Length(AFile.Hits) = 0 then
    Exit;
  Checks := nil;
  SetLength(Checks, Length(AFile.Hits));
  for Index := 0 to High(Checks) do
    Checks[Index] := True;
  FResults := FResults + [AFile];
  FChecked := FChecked + [Checks];
end;

procedure TAtlasReplaceList.SetFileChecked(AFile: Integer; AValue: Boolean);
var
  Index: Integer;
begin
  if (AFile < 0) or (AFile > High(FChecked)) then
    Exit;
  for Index := 0 to High(FChecked[AFile]) do
    FChecked[AFile][Index] := AValue;
end;

procedure TAtlasReplaceList.SetHitChecked(AFile, AHit: Integer; AValue: Boolean);
begin
  if (AFile < 0) or (AFile > High(FChecked)) or (AHit < 0) or (AHit > High(FChecked[AFile])) then
    Exit;
  FChecked[AFile][AHit] := AValue;
end;

function TAtlasReplaceList.FileChecked(AFile: Integer): Boolean;
var
  Value: Boolean;
begin
  Result := (AFile >= 0) and (AFile <= High(FChecked));
  if not Result then
    Exit;
  for Value in FChecked[AFile] do
    if not Value then
      Exit(False);
end;

function TAtlasReplaceList.HitChecked(AFile, AHit: Integer): Boolean;
begin
  Result := (AFile >= 0) and (AFile <= High(FChecked)) and (AHit >= 0) and (AHit <= High(FChecked[AFile])) and
    FChecked[AFile][AHit];
end;

function TAtlasReplaceList.CheckedCount: Integer;
var
  Checks: TArray<Boolean>;
  Value: Boolean;
begin
  Result := 0;
  for Checks in FChecked do
    for Value in Checks do
      if Value then
        Inc(Result);
end;

function TAtlasReplaceList.HitCount: Integer;
begin
  Result := TAtlasFileSearch.HitCount(FResults);
end;

function TAtlasReplaceList.Rows: TArray<TAtlasReplaceRow>;
var
  FileIndex, HitIndex: Integer;
  Row: TAtlasReplaceRow;
  Item: TAtlasFileHits;
begin
  Result := nil;
  for FileIndex := 0 to High(FResults) do
  begin
    Item := FResults[FileIndex];
    Row := Default(TAtlasReplaceRow);
    Row.Kind := TAtlasReplaceRowKind.FileRow;
    Row.FileIndex := FileIndex;
    Row.HitIndex := -1;
    Row.Checked := FileChecked(FileIndex);
    Row.FileName := Item.FileName;
    Row.Text := ExtractFileName(Item.FileName);
    Result := Result + [Row];
    for HitIndex := 0 to High(Item.Hits) do
    begin
      Row := Default(TAtlasReplaceRow);
      Row.Kind := TAtlasReplaceRowKind.HitRow;
      Row.FileIndex := FileIndex;
      Row.HitIndex := HitIndex;
      Row.Checked := FChecked[FileIndex][HitIndex];
      Row.FileName := Item.FileName;
      Row.Line := Item.Hits[HitIndex].Line + 1;
      Row.Text := TAtlasTextSearch.HitText(Item.Lines, Item.Hits[HitIndex]);
      if FQuery.Options.Regex then
        Row.Preview := TAtlasSearchReplace.Preview(Item.Lines, Item.Hits[HitIndex], FQuery, FReplace).Caption;
      Result := Result + [Row];
    end;
  end;
end;

function TAtlasReplaceList.Plan(const AIsReadOnly: TAtlasReplaceFileCheck;
  const ACurrentText: TAtlasReplaceFileText): TAtlasReplacePlan;
var
  FileIndex, HitIndex: Integer;
  Item: TAtlasFileHits;
  Chosen: TArray<TAtlasSearchHit>;
  Edits: TLspFileEdits;
begin
  Result := Default(TAtlasReplacePlan);
  for FileIndex := 0 to High(FResults) do
  begin
    Item := FResults[FileIndex];
    Chosen := nil;
    for HitIndex := 0 to High(Item.Hits) do
      if FChecked[FileIndex][HitIndex] then
        Chosen := Chosen + [Item.Hits[HitIndex]];
    if Length(Chosen) = 0 then
      Continue;
    if Assigned(AIsReadOnly) and AIsReadOnly(Item.FileName) then
    begin
      Result.ReadOnly := Result.ReadOnly + [Item.FileName];
      Continue;
    end;
    if Assigned(ACurrentText) and (ACurrentText(Item.FileName) <> Item.Text) then
    begin
      Result.Changed := Result.Changed + [Item.FileName];
      Continue;
    end;
    Edits.FileName := Item.FileName;
    Edits.Edits := TAtlasSearchReplace.Edits(Item.Lines, Chosen, FQuery, FReplace);
    Result.Edit.Files := Result.Edit.Files + [Edits];
    Inc(Result.Replacements, Length(Chosen));
    Inc(Result.Files);
  end;
end;

end.
