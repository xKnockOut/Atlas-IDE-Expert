unit Atlas.Core.Debug.BreakpointList;

// Haltepunktfenster (#863), ohne VCL und Open Tools API: Zeilen, Suche,
// Filterchips, Gruppierung, Trefferzahlen und Spaltenanordnung.
//
// - TAtlasBreakpointRow: ein Quelltext-Haltepunkt, wie ihn die IDE-Schicht aus
//   IOTADebuggerServices liest, ergänzt um Methode, Trefferzahl dieser
//   Sitzung, Etiketten (Atlas.Core.Debug.BreakpointTags), „greift nicht“
//   (#577) und Satz (#586).
// - TAtlasBreakpointView.Filter: Suchtext und Filterchips. Der Suchtext wird
//   an Leerzeichen geteilt; jedes Wort muss im Dateinamen, in der Methode, in
//   der Bedingung oder in einem Etikett vorkommen (Groß-/Kleinschreibung
//   egal). Mehrere Chips gelten zusammen („aktiv“ und „mit Bedingung“).
// - TAtlasBreakpointView.Group: Gruppen nach Etikett, Datei oder
//   Haltepunktgruppe der IDE. Ein Haltepunkt mit zwei Etiketten steht in
//   beiden Gruppen; ohne Etikett bzw. Gruppe in der Gruppe mit leerer
//   Überschrift, die immer zuletzt kommt. Gruppen nach Überschrift, Zeilen
//   nach Datei und Zeile sortiert (eindeutig, da TArray.Sort nicht stabil ist).
// - TAtlasBreakpointHits: Trefferzahl je Datei und Zeile in dieser Sitzung.
//   Start (Beginn einer Sitzung) und Reset („Zähler zurücksetzen“) setzen auf
//   0; HasRun sagt, ob „nie getroffen“ schon etwas bedeutet.
// - TAtlasBreakpointColumns: Reihenfolge, Sichtbarkeit und Breite der
//   Spalten als Text, z. B. "enabled:24,location:260,-group:90" (Minus:
//   ausgeblendet). Unbekannte und doppelte Spalten entfallen, fehlende kommen
//   hinten mit ihrer Vorgabe dazu.
// Zeilen zählen ab 1 (wie im Editor).

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  {$SCOPEDENUMS ON}
  /// <summary>Filterchips: Active (eingeschaltet), WithCondition (mit Bedingung), NeverHit (in dieser
  /// Sitzung nicht gehalten), NotEffective (greift nicht, #577).</summary>
  TAtlasBreakpointFilter = (Active, WithCondition, NeverHit, NotEffective);
  TAtlasBreakpointGrouping = (None, ByTag, ByFile, ByGroup);
  TAtlasBreakpointColumn = (Enabled, Location, Condition, PassCount, Hits, Tags, Group, SetName, Rules);
  {$SCOPEDENUMS OFF}
  TAtlasBreakpointFilters = set of TAtlasBreakpointFilter;

  TAtlasBreakpointRow = record
    FileName: string;
    /// <summary>Ab 1.</summary>
    Line: Integer;
    /// <summary>Voller Name der Methode wie TKunde.Speichern; '' außerhalb einer Methode.</summary>
    Method: string;
    Condition: string;
    PassCount: Integer;
    Group: string;
    /// <summary>Sätze (#586), in denen der Haltepunkt steht, mit Komma getrennt.</summary>
    SetName: string;
    /// <summary>Regeln (#864) als kurzer Text; '' ohne.</summary>
    Rules: string;
    Enabled: Boolean;
    /// <summary>Greift nicht (#577); Reason sagt, warum.</summary>
    NotEffective: Boolean;
    Reason: string;
    /// <summary>Trefferzahl dieser Sitzung.</summary>
    Hits: Integer;
    Tags: TArray<string>;
    class function Create(const AFileName: string; ALine: Integer): TAtlasBreakpointRow; static;
    /// <summary>Datei ohne Pfad und Endung, wie die Unit heißt.</summary>
    function UnitName: string;
    /// <summary>Unit, Methode und Zeile, etwa "Kunde · TKunde.Speichern · 42".</summary>
    function Location: string;
    function HasTag(const ATag: string): Boolean;
  end;

  TAtlasBreakpointGroupEntry = record
    /// <summary>Etikett, Dateiname oder Gruppe; '' für „ohne“.</summary>
    Caption: string;
    /// <summary>Indizes in die Zeilen, nach Datei und Zeile sortiert.</summary>
    Rows: TArray<Integer>;
  end;

  TAtlasBreakpointView = record
  public
    class function Matches(const ARow: TAtlasBreakpointRow; const ASearch: string;
      AFilters: TAtlasBreakpointFilters): Boolean; static;
    /// <summary>Indizes der passenden Zeilen in der Reihenfolge von ARows.</summary>
    class function Filter(const ARows: TArray<TAtlasBreakpointRow>; const ASearch: string;
      AFilters: TAtlasBreakpointFilters): TArray<Integer>; static;
    /// <summary>Gruppen der Zeilen AIndices; bei None genau eine Gruppe mit leerer Überschrift (auch ohne
    /// Zeilen).</summary>
    class function Group(const ARows: TArray<TAtlasBreakpointRow>; const AIndices: TArray<Integer>;
      AGrouping: TAtlasBreakpointGrouping): TArray<TAtlasBreakpointGroupEntry>; static;
  end;

  TAtlasBreakpointHits = class
  private
    FCounts: TDictionary<string, Integer>;
    FHasRun: Boolean;
    class function Key(const AFileName: string; ALine: Integer): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neue Debug-Sitzung: alle Zähler auf 0.</summary>
    procedure Start;
    /// <summary>„Zähler zurücksetzen“ während der Sitzung.</summary>
    procedure Reset;
    /// <summary>Halt an AFileName/ALine (ab 1); liefert die neue Zahl.</summary>
    function Hit(const AFileName: string; ALine: Integer): Integer;
    function Count(const AFileName: string; ALine: Integer): Integer;
    /// <summary>Ein Haltepunkt ist an eine andere Zeile gewandert: Zahl mitnehmen.</summary>
    procedure Move(const AFromFile: string; AFromLine: Integer; const AToFile: string; AToLine: Integer);
    /// <summary>Lief seit dem Laden schon eine Sitzung? Vorher heißt „nie getroffen“ nichts.</summary>
    property HasRun: Boolean read FHasRun;
  end;

  TAtlasBreakpointColumnInfo = record
    Column: TAtlasBreakpointColumn;
    Visible: Boolean;
    Width: Integer;
  end;

  TAtlasBreakpointColumns = record
  public const
    cMinWidth = 16;
    cMaxWidth = 2000;
  public
    Items: TArray<TAtlasBreakpointColumnInfo>;
    /// <summary>Alle Spalten sichtbar in der Reihenfolge der Aufzählung mit ihrer Vorgabebreite.</summary>
    class function Default: TAtlasBreakpointColumns; static;
    class function DefaultWidth(AColumn: TAtlasBreakpointColumn): Integer; static;
    class function Name(AColumn: TAtlasBreakpointColumn): string; static;
    class function TryColumn(const AName: string; out AColumn: TAtlasBreakpointColumn): Boolean; static;
    /// <summary>Liest den Text von ToText; Unbrauchbares entfällt, fehlende Spalten hinten mit Vorgabe.</summary>
    class function Parse(const AText: string): TAtlasBreakpointColumns; static;
    function ToText: string;
    function IndexOf(AColumn: TAtlasBreakpointColumn): Integer;
    function IsVisible(AColumn: TAtlasBreakpointColumn): Boolean;
    procedure SetVisible(AColumn: TAtlasBreakpointColumn; AVisible: Boolean);
    procedure SetWidth(AColumn: TAtlasBreakpointColumn; AWidth: Integer);
    /// <summary>AColumn an die Stelle AIndex schieben (die übrigen rücken nach).</summary>
    procedure MoveTo(AColumn: TAtlasBreakpointColumn; AIndex: Integer);
  end;

implementation

uses
  System.Generics.Defaults;

const
  cLocationSeparator = ' · ';
  cColumnSeparator = ',';
  cWidthSeparator = ':';
  cHiddenMark = '-';
  cKeySeparator = '|';
  cWideColumn = 260;
  cMiddleColumn = 160;
  cNarrowColumn = 70;
  cCheckColumn = 24;
  cColumnNames: array[TAtlasBreakpointColumn] of string = ('enabled', 'location', 'condition', 'passCount',
    'hits', 'tags', 'group', 'set', 'rules');

/// <summary>Dateiname ohne Ordner; trennt an "\" und "/" (auch unter Linux, wo ExtractFileName nur "/"
/// kennt).</summary>
function ShortName(const AFileName: string): string;
begin
  Result := AFileName.Substring(LastDelimiter('\/', AFileName));
end;

{ TAtlasBreakpointRow }

class function TAtlasBreakpointRow.Create(const AFileName: string; ALine: Integer): TAtlasBreakpointRow;
begin
  Result := Default(TAtlasBreakpointRow);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Enabled := True;
end;

function TAtlasBreakpointRow.UnitName: string;
begin
  Result := ChangeFileExt(ShortName(FileName), '');
end;

function TAtlasBreakpointRow.Location: string;
begin
  Result := UnitName;
  if Method <> '' then
  begin
    Result := Result + cLocationSeparator + Method;
  end;
  Result := Result + cLocationSeparator + IntToStr(Line);
end;

function TAtlasBreakpointRow.HasTag(const ATag: string): Boolean;
var
  mTag: string;
begin
  for mTag in Tags do
  begin
    if SameText(mTag, ATag) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasBreakpointView }

function ContainsWord(const ARow: TAtlasBreakpointRow; const AWord: string): Boolean;
var
  mTag: string;
begin
  Result := ShortName(ARow.FileName).ToLower.Contains(AWord) or
    ARow.Method.ToLower.Contains(AWord) or ARow.Condition.ToLower.Contains(AWord);
  if Result then
  begin
    Exit;
  end;
  for mTag in ARow.Tags do
  begin
    if mTag.ToLower.Contains(AWord) then
    begin
      Exit(True);
    end;
  end;
end;

function MatchesSearch(const ARow: TAtlasBreakpointRow; const ASearch: string): Boolean;
var
  mWord: string;
begin
  for mWord in ASearch.ToLower.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
  begin
    if not ContainsWord(ARow, mWord) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function MatchesFilters(const ARow: TAtlasBreakpointRow; AFilters: TAtlasBreakpointFilters): Boolean;
begin
  Result := not ((TAtlasBreakpointFilter.Active in AFilters) and not ARow.Enabled);
  Result := Result and not ((TAtlasBreakpointFilter.WithCondition in AFilters) and (Trim(ARow.Condition) = ''));
  Result := Result and not ((TAtlasBreakpointFilter.NeverHit in AFilters) and (ARow.Hits > 0));
  Result := Result and not ((TAtlasBreakpointFilter.NotEffective in AFilters) and not ARow.NotEffective);
end;

class function TAtlasBreakpointView.Matches(const ARow: TAtlasBreakpointRow; const ASearch: string;
  AFilters: TAtlasBreakpointFilters): Boolean;
begin
  Result := MatchesFilters(ARow, AFilters) and MatchesSearch(ARow, ASearch);
end;

class function TAtlasBreakpointView.Filter(const ARows: TArray<TAtlasBreakpointRow>; const ASearch: string;
  AFilters: TAtlasBreakpointFilters): TArray<Integer>;
var
  mIndex, mCount: Integer;
begin
  SetLength(Result, Length(ARows));
  mCount := 0;
  for mIndex := 0 to High(ARows) do
  begin
    if Matches(ARows[mIndex], ASearch, AFilters) then
    begin
      Result[mCount] := mIndex;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

function CompareRows(const ARows: TArray<TAtlasBreakpointRow>; ALeft, ARight: Integer): Integer;
begin
  Result := CompareText(ShortName(ARows[ALeft].FileName), ShortName(ARows[ARight].FileName));
  if Result = 0 then
  begin
    Result := CompareText(ARows[ALeft].FileName, ARows[ARight].FileName);
  end;
  if Result = 0 then
  begin
    Result := ARows[ALeft].Line - ARows[ARight].Line;
  end;
  if Result = 0 then
  begin
    Result := ALeft - ARight;
  end;
end;

procedure SortRows(const ARows: TArray<TAtlasBreakpointRow>; var AIndices: TArray<Integer>);
begin
  TArray.Sort<Integer>(AIndices, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := CompareRows(ARows, ALeft, ARight);
    end));
end;

function CompareCaptions(const ALeft, ARight: TAtlasBreakpointGroupEntry): Integer;
begin
  // Ohne Überschrift ("ohne Etikett") immer zuletzt.
  Result := Ord(ALeft.Caption = '') - Ord(ARight.Caption = '');
  if Result = 0 then
  begin
    Result := CompareText(ALeft.Caption, ARight.Caption);
  end;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Caption, ARight.Caption);
  end;
end;

function CaptionsOf(const ARow: TAtlasBreakpointRow; AGrouping: TAtlasBreakpointGrouping): TArray<string>;
begin
  case AGrouping of
    TAtlasBreakpointGrouping.None:
      Result := nil;
    TAtlasBreakpointGrouping.ByTag:
      Result := ARow.Tags;
    TAtlasBreakpointGrouping.ByFile:
      Result := TArray<string>.Create(ShortName(ARow.FileName));
    TAtlasBreakpointGrouping.ByGroup:
      Result := TArray<string>.Create(Trim(ARow.Group));
  end;
  if Length(Result) = 0 then
  begin
    Result := TArray<string>.Create('');
  end;
end;

procedure AddToGroup(AGroups: TDictionary<string, Integer>; var AEntries: TArray<TAtlasBreakpointGroupEntry>;
  const ACaption: string; ARow: Integer);
var
  mSlot: Integer;
begin
  if not AGroups.TryGetValue(ACaption.ToLower, mSlot) then
  begin
    mSlot := Length(AEntries);
    SetLength(AEntries, mSlot + 1);
    AEntries[mSlot].Caption := ACaption;
    AEntries[mSlot].Rows := nil;
    AGroups.Add(ACaption.ToLower, mSlot);
  end;
  AEntries[mSlot].Rows := AEntries[mSlot].Rows + [ARow];
end;

class function TAtlasBreakpointView.Group(const ARows: TArray<TAtlasBreakpointRow>;
  const AIndices: TArray<Integer>; AGrouping: TAtlasBreakpointGrouping): TArray<TAtlasBreakpointGroupEntry>;
var
  mGroups: TDictionary<string, Integer>;
  mRow, mSlot: Integer;
  mCaption: string;
begin
  if AGrouping = TAtlasBreakpointGrouping.None then
  begin
    SetLength(Result, 1);
    Result[0].Caption := '';
    Result[0].Rows := Copy(AIndices);
    SortRows(ARows, Result[0].Rows);
    Exit;
  end;
  Result := nil;
  mGroups := TDictionary<string, Integer>.Create;
  try
    for mRow in AIndices do
    begin
      for mCaption in CaptionsOf(ARows[mRow], AGrouping) do
      begin
        AddToGroup(mGroups, Result, mCaption, mRow);
      end;
    end;
  finally
    mGroups.Free;
  end;
  for mSlot := 0 to High(Result) do
  begin
    SortRows(ARows, Result[mSlot].Rows);
  end;
  TArray.Sort<TAtlasBreakpointGroupEntry>(Result, TComparer<TAtlasBreakpointGroupEntry>.Construct(CompareCaptions));
end;

{ TAtlasBreakpointHits }

constructor TAtlasBreakpointHits.Create;
begin
  inherited Create;
  FCounts := TDictionary<string, Integer>.Create;
end;

destructor TAtlasBreakpointHits.Destroy;
begin
  FCounts.Free;
  inherited Destroy;
end;

class function TAtlasBreakpointHits.Key(const AFileName: string; ALine: Integer): string;
begin
  Result := AFileName.Replace('/', '\').ToLower + cKeySeparator + IntToStr(ALine);
end;

procedure TAtlasBreakpointHits.Start;
begin
  FCounts.Clear;
  FHasRun := True;
end;

procedure TAtlasBreakpointHits.Reset;
begin
  FCounts.Clear;
end;

function TAtlasBreakpointHits.Hit(const AFileName: string; ALine: Integer): Integer;
var
  mKey: string;
begin
  mKey := Key(AFileName, ALine);
  if not FCounts.TryGetValue(mKey, Result) then
  begin
    Result := 0;
  end;
  Inc(Result);
  FCounts.AddOrSetValue(mKey, Result);
end;

function TAtlasBreakpointHits.Count(const AFileName: string; ALine: Integer): Integer;
begin
  if not FCounts.TryGetValue(Key(AFileName, ALine), Result) then
  begin
    Result := 0;
  end;
end;

procedure TAtlasBreakpointHits.Move(const AFromFile: string; AFromLine: Integer; const AToFile: string;
  AToLine: Integer);
var
  mCount: Integer;
begin
  mCount := Count(AFromFile, AFromLine);
  FCounts.Remove(Key(AFromFile, AFromLine));
  if mCount > 0 then
  begin
    FCounts.AddOrSetValue(Key(AToFile, AToLine), mCount);
  end;
end;

{ TAtlasBreakpointColumns }

class function TAtlasBreakpointColumns.DefaultWidth(AColumn: TAtlasBreakpointColumn): Integer;
begin
  case AColumn of
    TAtlasBreakpointColumn.Enabled:
      Result := cCheckColumn;
    TAtlasBreakpointColumn.Location:
      Result := cWideColumn;
    TAtlasBreakpointColumn.Condition, TAtlasBreakpointColumn.Tags, TAtlasBreakpointColumn.Rules:
      Result := cMiddleColumn;
  else
    Result := cNarrowColumn;
  end;
end;

class function TAtlasBreakpointColumns.Name(AColumn: TAtlasBreakpointColumn): string;
begin
  Result := cColumnNames[AColumn];
end;

class function TAtlasBreakpointColumns.TryColumn(const AName: string; out AColumn: TAtlasBreakpointColumn): Boolean;
var
  mColumn: TAtlasBreakpointColumn;
begin
  for mColumn := Low(TAtlasBreakpointColumn) to High(TAtlasBreakpointColumn) do
  begin
    if SameText(cColumnNames[mColumn], Trim(AName)) then
    begin
      AColumn := mColumn;
      Exit(True);
    end;
  end;
  AColumn := TAtlasBreakpointColumn.Enabled;
  Result := False;
end;

function DefaultInfo(AColumn: TAtlasBreakpointColumn): TAtlasBreakpointColumnInfo;
begin
  Result.Column := AColumn;
  Result.Visible := True;
  Result.Width := TAtlasBreakpointColumns.DefaultWidth(AColumn);
end;

class function TAtlasBreakpointColumns.Default: TAtlasBreakpointColumns;
var
  mColumn: TAtlasBreakpointColumn;
begin
  Result.Items := nil;
  for mColumn := Low(TAtlasBreakpointColumn) to High(TAtlasBreakpointColumn) do
  begin
    Result.Items := Result.Items + [DefaultInfo(mColumn)];
  end;
end;

function ClampWidth(AWidth: Integer): Integer;
begin
  Result := AWidth;
  if Result < TAtlasBreakpointColumns.cMinWidth then
  begin
    Result := TAtlasBreakpointColumns.cMinWidth;
  end;
  if Result > TAtlasBreakpointColumns.cMaxWidth then
  begin
    Result := TAtlasBreakpointColumns.cMaxWidth;
  end;
end;

function TryParseItem(const APart: string; out AInfo: TAtlasBreakpointColumnInfo): Boolean;
var
  mText, mName, mWidth: string;
  mColon, mValue: Integer;
begin
  mText := Trim(APart);
  AInfo := DefaultInfo(TAtlasBreakpointColumn.Enabled);
  AInfo.Visible := not mText.StartsWith(cHiddenMark);
  if not AInfo.Visible then
  begin
    mText := mText.Substring(Length(cHiddenMark));
  end;
  mColon := mText.IndexOf(cWidthSeparator);
  mName := mText;
  mWidth := '';
  if mColon >= 0 then
  begin
    mName := mText.Substring(0, mColon);
    mWidth := mText.Substring(mColon + 1);
  end;
  Result := TAtlasBreakpointColumns.TryColumn(mName, AInfo.Column);
  AInfo.Width := TAtlasBreakpointColumns.DefaultWidth(AInfo.Column);
  if Result and TryStrToInt(Trim(mWidth), mValue) then
  begin
    AInfo.Width := ClampWidth(mValue);
  end;
end;

class function TAtlasBreakpointColumns.Parse(const AText: string): TAtlasBreakpointColumns;
var
  mPart: string;
  mInfo: TAtlasBreakpointColumnInfo;
  mColumn: TAtlasBreakpointColumn;
begin
  Result.Items := nil;
  for mPart in AText.Split([cColumnSeparator]) do
  begin
    if TryParseItem(mPart, mInfo) and (Result.IndexOf(mInfo.Column) < 0) then
    begin
      Result.Items := Result.Items + [mInfo];
    end;
  end;
  for mColumn := Low(TAtlasBreakpointColumn) to High(TAtlasBreakpointColumn) do
  begin
    if Result.IndexOf(mColumn) < 0 then
    begin
      Result.Items := Result.Items + [DefaultInfo(mColumn)];
    end;
  end;
end;

function TAtlasBreakpointColumns.ToText: string;
var
  mInfo: TAtlasBreakpointColumnInfo;
  mParts: TArray<string>;
  mPart: string;
begin
  mParts := nil;
  for mInfo in Items do
  begin
    mPart := Name(mInfo.Column) + cWidthSeparator + IntToStr(mInfo.Width);
    if not mInfo.Visible then
    begin
      mPart := cHiddenMark + mPart;
    end;
    mParts := mParts + [mPart];
  end;
  Result := string.Join(cColumnSeparator, mParts);
end;

function TAtlasBreakpointColumns.IndexOf(AColumn: TAtlasBreakpointColumn): Integer;
begin
  for Result := 0 to High(Items) do
  begin
    if Items[Result].Column = AColumn then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TAtlasBreakpointColumns.IsVisible(AColumn: TAtlasBreakpointColumn): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AColumn);
  Result := (mIndex >= 0) and Items[mIndex].Visible;
end;

procedure TAtlasBreakpointColumns.SetVisible(AColumn: TAtlasBreakpointColumn; AVisible: Boolean);
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AColumn);
  if mIndex >= 0 then
  begin
    Items[mIndex].Visible := AVisible;
  end;
end;

procedure TAtlasBreakpointColumns.SetWidth(AColumn: TAtlasBreakpointColumn; AWidth: Integer);
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AColumn);
  if mIndex >= 0 then
  begin
    Items[mIndex].Width := ClampWidth(AWidth);
  end;
end;

procedure TAtlasBreakpointColumns.MoveTo(AColumn: TAtlasBreakpointColumn; AIndex: Integer);
var
  mFrom: Integer;
  mInfo: TAtlasBreakpointColumnInfo;
begin
  mFrom := IndexOf(AColumn);
  if mFrom < 0 then
  begin
    Exit;
  end;
  mInfo := Items[mFrom];
  Delete(Items, mFrom, 1);
  if AIndex < 0 then
  begin
    AIndex := 0;
  end;
  if AIndex > Length(Items) then
  begin
    AIndex := Length(Items);
  end;
  Insert(mInfo, Items, AIndex);
end;

end.
