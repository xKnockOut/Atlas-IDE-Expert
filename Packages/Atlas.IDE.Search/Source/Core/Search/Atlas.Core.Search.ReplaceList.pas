unit Atlas.Core.Search.ReplaceList;

// Auswahl der Treffer zum Ersetzen über mehrere Dateien (#893), ohne VCL und
// Open Tools API: das Modell hinter der Liste „Atlas-Suche: Ersetzen“.
// - Jeder Treffer hat ein Häkchen (Vorgabe an), jede Datei eines für alle
//   ihre Treffer: Es ist gesetzt, solange alle Treffer der Datei angehakt sind.
// - Rows: Zeilen für die Liste, je Datei eine Kopfzeile, darunter die Treffer
//   mit „Zeile: Text“ und der Vorschau „vorher → nachher“.
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
    /// <summary>„vorher → nachher“; ohne Regex ist „nachher“ der Ersatz selbst.</summary>
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
  mChecks: TArray<Boolean>;
  mIndex: Integer;
begin
  if Length(AFile.Hits) = 0 then
  begin
    Exit;
  end;
  mChecks := nil;
  SetLength(mChecks, Length(AFile.Hits));
  for mIndex := 0 to High(mChecks) do
  begin
    mChecks[mIndex] := True;
  end;
  FResults := FResults + [AFile];
  FChecked := FChecked + [mChecks];
end;

procedure TAtlasReplaceList.SetFileChecked(AFile: Integer; AValue: Boolean);
var
  mIndex: Integer;
begin
  if (AFile < 0) or (AFile > High(FChecked)) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FChecked[AFile]) do
  begin
    FChecked[AFile][mIndex] := AValue;
  end;
end;

procedure TAtlasReplaceList.SetHitChecked(AFile, AHit: Integer; AValue: Boolean);
begin
  if (AFile < 0) or (AFile > High(FChecked)) or (AHit < 0) or (AHit > High(FChecked[AFile])) then
  begin
    Exit;
  end;
  FChecked[AFile][AHit] := AValue;
end;

function TAtlasReplaceList.FileChecked(AFile: Integer): Boolean;
var
  mValue: Boolean;
begin
  Result := (AFile >= 0) and (AFile <= High(FChecked));
  if not Result then
  begin
    Exit;
  end;
  for mValue in FChecked[AFile] do
  begin
    if not mValue then
    begin
      Exit(False);
    end;
  end;
end;

function TAtlasReplaceList.HitChecked(AFile, AHit: Integer): Boolean;
begin
  Result := (AFile >= 0) and (AFile <= High(FChecked)) and (AHit >= 0) and (AHit <= High(FChecked[AFile])) and
    FChecked[AFile][AHit];
end;

function TAtlasReplaceList.CheckedCount: Integer;
var
  mChecks: TArray<Boolean>;
  mValue: Boolean;
begin
  Result := 0;
  for mChecks in FChecked do
  begin
    for mValue in mChecks do
    begin
      if mValue then
      begin
        Inc(Result);
      end;
    end;
  end;
end;

function TAtlasReplaceList.HitCount: Integer;
begin
  Result := TAtlasFileSearch.HitCount(FResults);
end;

function TAtlasReplaceList.Rows: TArray<TAtlasReplaceRow>;
var
  mFileIndex, mHitIndex: Integer;
  mRow: TAtlasReplaceRow;
  mItem: TAtlasFileHits;
begin
  Result := nil;
  for mFileIndex := 0 to High(FResults) do
  begin
    mItem := FResults[mFileIndex];
    mRow := Default(TAtlasReplaceRow);
    mRow.Kind := TAtlasReplaceRowKind.FileRow;
    mRow.FileIndex := mFileIndex;
    mRow.HitIndex := -1;
    mRow.Checked := FileChecked(mFileIndex);
    mRow.FileName := mItem.FileName;
    mRow.Text := ExtractFileName(mItem.FileName);
    Result := Result + [mRow];
    for mHitIndex := 0 to High(mItem.Hits) do
    begin
      mRow := Default(TAtlasReplaceRow);
      mRow.Kind := TAtlasReplaceRowKind.HitRow;
      mRow.FileIndex := mFileIndex;
      mRow.HitIndex := mHitIndex;
      mRow.Checked := FChecked[mFileIndex][mHitIndex];
      mRow.FileName := mItem.FileName;
      mRow.Line := mItem.Hits[mHitIndex].Line + 1;
      mRow.Text := TAtlasTextSearch.HitText(mItem.Lines, mItem.Hits[mHitIndex]);
      mRow.Preview := TAtlasSearchReplace.Preview(mItem.Lines, mItem.Hits[mHitIndex], FQuery, FReplace).Caption;
      Result := Result + [mRow];
    end;
  end;
end;

function TAtlasReplaceList.Plan(const AIsReadOnly: TAtlasReplaceFileCheck;
  const ACurrentText: TAtlasReplaceFileText): TAtlasReplacePlan;
var
  mFileIndex, mHitIndex: Integer;
  mItem: TAtlasFileHits;
  mChosen: TArray<TAtlasSearchHit>;
  mEdits: TLspFileEdits;
begin
  Result := Default(TAtlasReplacePlan);
  for mFileIndex := 0 to High(FResults) do
  begin
    mItem := FResults[mFileIndex];
    mChosen := nil;
    for mHitIndex := 0 to High(mItem.Hits) do
    begin
      if FChecked[mFileIndex][mHitIndex] then
      begin
        mChosen := mChosen + [mItem.Hits[mHitIndex]];
      end;
    end;
    if Length(mChosen) = 0 then
    begin
      Continue;
    end;
    if Assigned(AIsReadOnly) and AIsReadOnly(mItem.FileName) then
    begin
      Result.ReadOnly := Result.ReadOnly + [mItem.FileName];
      Continue;
    end;
    if Assigned(ACurrentText) and (ACurrentText(mItem.FileName) <> mItem.Text) then
    begin
      Result.Changed := Result.Changed + [mItem.FileName];
      Continue;
    end;
    mEdits.FileName := mItem.FileName;
    mEdits.Edits := TAtlasSearchReplace.Edits(mItem.Lines, mChosen, FQuery, FReplace);
    Result.Edit.Files := Result.Edit.Files + [mEdits];
    Inc(Result.Replacements, Length(mChosen));
    Inc(Result.Files);
  end;
end;

end.
