unit Atlas.Core.Problems.FindingsView;

// Ansicht des Fensters „Atlas-Prüfung“ (#909) ohne VCL: Befunde mit Filter, Stufen (offene Units zuerst, #1108),
// Gruppierung, Sortierung, Zeilen mit aufklappbaren Gruppen und Trennzeilen, Zähler je Art und Auswahl. Die
// Befunde selbst und ihre Typen liefert Atlas.Core.Problems.Findings.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Problems.Findings;

type
  /// <summary>Befunde je Stufe in der angezeigten Reihenfolge (Indizes in die Befunde).</summary>
  TAtlasFindingTierMembers = array[TAtlasFindingTier] of TArray<Integer>;

  /// <summary>Befunde mit Filter und Stufen (offene Units zuerst, #1108); Grundlage von TAtlasFindingsView.
  /// </summary>
  TAtlasFindingsSource = class
  protected
    FFindings: TArray<TAtlasFinding>;
    FFilter: TAtlasFindingFilter;
    FKnown: TDictionary<string, Boolean>;
    FNew: TDictionary<string, Boolean>;
    FFilled: Boolean;
    FOpenFirst: Boolean;
    FClosedUnits: TAtlasClosedUnits;
    FShowCleanActive: Boolean;
    FActiveFile: string;
    FActiveKey: string;
    FActiveChecked: Boolean;
    FOpenKeys: TDictionary<string, Boolean>;
    /// <summary>Zeilen und Zähler nach einer Änderung neu aufbauen.</summary>
    procedure Rebuild; virtual; abstract;
    procedure SetFilter(const AValue: TAtlasFindingFilter);
    procedure SetOpenFirst(AValue: Boolean);
    procedure SetClosedUnits(AValue: TAtlasClosedUnits);
    procedure SetShowCleanActive(AValue: Boolean);
    function TierOf(const AFileName: string): TAtlasFindingTier;
    procedure AssignTiers;
    /// <summary>Wird AFinding wegen problems.window.closedUnits = hidden ausgeblendet?</summary>
    function HiddenByTier(const AFinding: TAtlasFinding): Boolean;
    function IsActiveInScope: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neuer Stand aus dem Speicher. Befunde, deren Schlüssel vorher fehlte, sind neu (nicht beim ersten
    /// Füllen).</summary>
    procedure SetFindings(const AFindings: TArray<TAtlasFinding>);
    /// <summary>Offene Units zuerst (#1108): AActive = Datei des oberen Editors ('' = keine), AOpen = alle in der
    /// IDE geöffneten Dateien; AActiveChecked = der Server hat die aktive Datei schon geliefert (sonst zeigt die
    /// Zeile ohne Befunde „wird geprüft …“).</summary>
    procedure SetOpenFiles(const AActive: string; const AOpen: TArray<string>; AActiveChecked: Boolean);
    /// <summary>Wirkt die Stufe gerade? Offene-zuerst an und Bereich nicht „Aktuelle Datei“.</summary>
    function TiersActive: Boolean;
    /// <summary>Markierung „neu“ entfernen (nach dem kurzen Hervorheben).</summary>
    procedure ClearNew;
    function Finding(AIndex: Integer): TAtlasFinding;
    property Filter: TAtlasFindingFilter read FFilter write SetFilter;
    /// <summary>problems.window.openFirst; im Modell Vorgabe aus, die Einstellung hat Vorgabe an.</summary>
    property OpenFirst: Boolean read FOpenFirst write SetOpenFirst;
    /// <summary>problems.window.closedUnits (Vorgabe ausgegraut).</summary>
    property ClosedUnits: TAtlasClosedUnits read FClosedUnits write SetClosedUnits;
    /// <summary>problems.window.showCleanActive (Vorgabe an).</summary>
    property ShowCleanActive: Boolean read FShowCleanActive write SetShowCleanActive;
    property ActiveFile: string read FActiveFile;
  end;

  /// <summary>Gruppierung und Sortierung der Befunde.</summary>
  TAtlasFindingsSorted = class(TAtlasFindingsSource)
  protected
    FGrouping: TAtlasFindingGrouping;
    FSortColumn: TAtlasFindingColumn;
    FSortDescending: Boolean;
    FSortCustom: Boolean;
    procedure SetGrouping(AValue: TAtlasFindingGrouping);
    function GroupKeyOf(const AFinding: TAtlasFinding): string;
    function Compare(const A, B: TAtlasFinding): Integer;
    /// <summary>Reihenfolge zweier Gruppen nach ihrem ersten Befund; bei Gleichstand nach dem Schlüssel.</summary>
    function CompareGroups(const AFirstA, AFirstB: TAtlasFinding; const AKeyA, AKeyB: string): Integer;
    /// <summary>Indizes der Befunde unter Filter und Stufe, sortiert.</summary>
    function SortedMatches: TArray<Integer>;
    /// <summary>Trennzeilen der Stufen gelten nach Datei (bei Regel und Kategorie würden sie sich wiederholen).
    /// </summary>
    function TiersByFile: Boolean;
  public
    constructor Create;
    /// <summary>Klick auf den Spaltenkopf: nach AColumn sortieren, beim zweiten Klick absteigend.</summary>
    procedure SortBy(AColumn: TAtlasFindingColumn);
    /// <summary>Zurück zur Vorgabe: Art, Datei, Zeile.</summary>
    procedure ResetSort;
    property Grouping: TAtlasFindingGrouping read FGrouping write SetGrouping;
    property SortDescending: Boolean read FSortDescending;
    property SortCustom: Boolean read FSortCustom;
  end;

  TAtlasFindingsView = class(TAtlasFindingsSorted)
  private
    FCollapsed: TDictionary<string, Boolean>;
    FVisible: TArray<Integer>;
    FRows: TArray<TAtlasFindingRow>;
    FSelectedKey: string;
    // Counts bis zum nächsten Rebuild: Das Fenster fragt sie in jedem Takt für die Statuszeile.
    FCounts: TAtlasFindingCounts;
    FCountsValid: Boolean;
    // BeginUpdate/EndUpdate: ein Neuaufbau für mehrere Änderungen.
    FUpdateCount: Integer;
    FRebuildPending: Boolean;
    function GetSelectedRow: Integer;
    /// <summary>Zeile für AFinding mit Stufe, Nadel und Grau.</summary>
    function FindingRow(AIndex: Integer; const AGroupKey: string): TAtlasFindingRow;
    /// <summary>Trennzeile der Stufe ATier über die Befunde AMembers.</summary>
    function SectionRow(ATier: TAtlasFindingTier; const AMembers: TArray<Integer>): TAtlasFindingRow;
    /// <summary>Zeile „Keine Befunde“ der aktiven Unit, wenn sie gezeigt werden soll.</summary>
    function CleanActiveRow(out ARow: TAtlasFindingRow): Boolean;
    /// <summary>Kopfzeile der Gruppe AKey mit ihrem ersten Befund und Aufklappzustand.</summary>
    function GroupRow(const AKey: string; const AFirst: TAtlasFinding; ACount: Integer): TAtlasFindingRow;
    /// <summary>Ohne Gruppierung (#1108): die drei Stufen als Trennzeilen, die aktive Unit auch ohne Befunde.
    /// </summary>
    procedure RebuildFlat(const AOrder: TArray<Integer>; const AOfTier: TAtlasFindingTierMembers;
      ARows: TList<TAtlasFindingRow>);
    procedure RebuildGrouped(const AOrder: TArray<Integer>; const AOfTier: TAtlasFindingTierMembers;
      ARows: TList<TAtlasFindingRow>);
    /// <summary>Indizes der sichtbaren Befunde der Gruppe AGroupKey.</summary>
    function GroupMembers(const AGroupKey: string): TArray<Integer>;
  protected
    procedure Rebuild; override;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Änderungen sammeln (Filter, Befunde, offene Dateien): Zeilen und Zähler werden erst mit dem letzten
    /// EndUpdate einmal neu aufgebaut, nicht nach jeder einzelnen Änderung. Dazwischen nicht lesen.</summary>
    procedure BeginUpdate;
    procedure EndUpdate;
    function Rows: TArray<TAtlasFindingRow>;
    /// <summary>Befunde in der angezeigten Reihenfolge (gefiltert, unabhängig vom Aufklappen).</summary>
    function Visible: TArray<TAtlasFinding>;
    /// <summary>Zähler je Art unter dem Filter ohne die Arten; Files zählt die Dateien der sichtbaren Befunde.
    /// </summary>
    function Counts: TAtlasFindingCounts;
    /// <summary>Gruppe auf- bzw. zuklappen (bleibt über Aktualisierungen erhalten).</summary>
    procedure SetExpanded(const AGroupKey: string; AExpanded: Boolean);
    procedure Toggle(ARow: Integer);
    procedure Select(ARow: Integer);
    /// <summary>Markierung folgt dem Cursor: ersten Befund auf der Zeile (0-basiert) wählen; True, wenn einer
    /// gefunden wurde. Klappt seine Gruppe auf.</summary>
    function SelectAt(const AFileName: string; ALine: Integer): Boolean;
    /// <summary>Nächster bzw. vorheriger Befund der gefilterten Liste ab der Auswahl (am Ende wieder vorn); wählt
    /// ihn aus und klappt seine Gruppe auf.</summary>
    function Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
    /// <summary>Befunde der Zeilen ARows ohne Doppelte, zum Kopieren; eine Gruppenzeile steht für ihre Befunde.
    /// </summary>
    function FindingsOfRows(const ARows: TArray<Integer>): TArray<TAtlasFinding>;
    function SelectedFinding(out AFinding: TAtlasFinding): Boolean;
    property SelectedKey: string read FSelectedKey write FSelectedKey;
    /// <summary>-1 ohne Auswahl oder wenn der gewählte Befund nicht sichtbar ist.</summary>
    property SelectedRow: Integer read GetSelectedRow;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Defaults;

{ TAtlasFindingsSource }

constructor TAtlasFindingsSource.Create;
begin
  inherited Create;
  FFilter := TAtlasFindingFilter.Create;
  FKnown := TDictionary<string, Boolean>.Create;
  FNew := TDictionary<string, Boolean>.Create;
  FOpenKeys := TDictionary<string, Boolean>.Create;
  // Aus, bis die IDE-Schicht die Einstellung setzt: so verhält sich das Modell ohne Stufen genau wie #909.
  FOpenFirst := False;
  FClosedUnits := TAtlasClosedUnits.Dimmed;
  FShowCleanActive := True;
end;

destructor TAtlasFindingsSource.Destroy;
begin
  FOpenKeys.Free;
  FNew.Free;
  FKnown.Free;
  inherited Destroy;
end;

procedure TAtlasFindingsSource.SetFindings(const AFindings: TArray<TAtlasFinding>);
var
  mFinding: TAtlasFinding;
begin
  FFindings := AFindings;
  FNew.Clear;
  if FFilled then
  begin
    for mFinding in AFindings do
    begin
      if not FKnown.ContainsKey(mFinding.Key) then
      begin
        FNew.AddOrSetValue(mFinding.Key, True);
      end;
    end;
  end;
  FKnown.Clear;
  for mFinding in AFindings do
  begin
    FKnown.AddOrSetValue(mFinding.Key, True);
  end;
  FFilled := True;
  AssignTiers;
  Rebuild;
end;

procedure TAtlasFindingsSource.SetOpenFiles(const AActive: string; const AOpen: TArray<string>;
  AActiveChecked: Boolean);
var
  mFileName: string;
begin
  FActiveFile := AActive;
  FActiveKey := '';
  if AActive <> '' then
  begin
    FActiveKey := TAtlasFindings.UnitKey(AActive);
  end;
  // Das Formular steht für seine Unit: Angezeigt wird die .pas.
  if FActiveKey <> AnsiLowerCase(AActive) then
  begin
    FActiveFile := ChangeFileExt(AActive, '.pas');
  end;
  FActiveChecked := AActiveChecked;
  FOpenKeys.Clear;
  for mFileName in AOpen do
  begin
    if mFileName <> '' then
    begin
      FOpenKeys.AddOrSetValue(TAtlasFindings.UnitKey(mFileName), True);
    end;
  end;
  AssignTiers;
  Rebuild;
end;

function TAtlasFindingsSource.TierOf(const AFileName: string): TAtlasFindingTier;
var
  mKey: string;
begin
  mKey := TAtlasFindings.UnitKey(AFileName);
  if (FActiveKey <> '') and (mKey = FActiveKey) then
  begin
    Result := TAtlasFindingTier.Active;
  end
  else if FOpenKeys.ContainsKey(mKey) then
  begin
    Result := TAtlasFindingTier.Open;
  end
  else
  begin
    Result := TAtlasFindingTier.Closed;
  end;
end;

procedure TAtlasFindingsSource.AssignTiers;
var
  mIndex: Integer;
  mLast: string;
  mTier: TAtlasFindingTier;
begin
  // Befunde einer Datei stehen hintereinander: die Stufe je Datei nur einmal bestimmen.
  mLast := '';
  mTier := TAtlasFindingTier.Closed;
  for mIndex := 0 to High(FFindings) do
  begin
    if (mIndex = 0) or (FFindings[mIndex].FileName <> mLast) then
    begin
      mLast := FFindings[mIndex].FileName;
      mTier := TierOf(mLast);
    end;
    FFindings[mIndex].Tier := mTier;
  end;
end;

function TAtlasFindingsSource.TiersActive: Boolean;
begin
  Result := FOpenFirst and (FFilter.Scope <> TAtlasFindingScope.CurrentFile);
end;

function TAtlasFindingsSource.HiddenByTier(const AFinding: TAtlasFinding): Boolean;
begin
  Result := TiersActive and (FClosedUnits = TAtlasClosedUnits.Hidden) and
    (AFinding.Tier = TAtlasFindingTier.Closed);
end;

procedure TAtlasFindingsSource.SetOpenFirst(AValue: Boolean);
begin
  FOpenFirst := AValue;
  Rebuild;
end;

procedure TAtlasFindingsSource.SetClosedUnits(AValue: TAtlasClosedUnits);
begin
  FClosedUnits := AValue;
  Rebuild;
end;

procedure TAtlasFindingsSource.SetShowCleanActive(AValue: Boolean);
begin
  FShowCleanActive := AValue;
  Rebuild;
end;

procedure TAtlasFindingsSource.ClearNew;
begin
  if FNew.Count = 0 then
  begin
    Exit;
  end;
  FNew.Clear;
  Rebuild;
end;

procedure TAtlasFindingsSource.SetFilter(const AValue: TAtlasFindingFilter);
begin
  FFilter := AValue;
  Rebuild;
end;

function TAtlasFindingsSource.IsActiveInScope: Boolean;
var
  mName: string;
begin
  if FActiveKey = '' then
  begin
    Exit(False);
  end;
  if (FFilter.Scope = TAtlasFindingScope.CurrentFile) or (FFilter.Files = nil) then
  begin
    Exit(True);
  end;
  for mName in FFilter.Files do
  begin
    if TAtlasFindings.UnitKey(mName) = FActiveKey then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasFindingsSource.Finding(AIndex: Integer): TAtlasFinding;
begin
  Result := FFindings[AIndex];
end;

{ TAtlasFindingsSorted }

constructor TAtlasFindingsSorted.Create;
begin
  inherited Create;
  FGrouping := TAtlasFindingGrouping.ByFile;
end;

procedure TAtlasFindingsSorted.SetGrouping(AValue: TAtlasFindingGrouping);
begin
  FGrouping := AValue;
  Rebuild;
end;

procedure TAtlasFindingsSorted.SortBy(AColumn: TAtlasFindingColumn);
begin
  if FSortCustom and (FSortColumn = AColumn) then
  begin
    FSortDescending := not FSortDescending;
  end
  else
  begin
    FSortCustom := True;
    FSortColumn := AColumn;
    FSortDescending := False;
  end;
  Rebuild;
end;

procedure TAtlasFindingsSorted.ResetSort;
begin
  FSortCustom := False;
  FSortDescending := False;
  Rebuild;
end;

function TAtlasFindingsSorted.GroupKeyOf(const AFinding: TAtlasFinding): string;
begin
  case FGrouping of
    TAtlasFindingGrouping.ByFile:
      Result := 'file:' + AnsiLowerCase(AFinding.FileName);
    TAtlasFindingGrouping.ByRule:
      Result := 'rule:' + AnsiLowerCase(AFinding.Problem.Code);
    TAtlasFindingGrouping.ByCategory:
      Result := 'category:' + IntToStr(Ord(AFinding.Category));
  else
    Result := '';
  end;
end;

function CompareDefault(const A, B: TAtlasFinding): Integer;
begin
  Result := Ord(A.Kind) - Ord(B.Kind);
  if Result = 0 then
  begin
    Result := CompareText(A.FileName, B.FileName);
  end;
  if Result = 0 then
  begin
    Result := A.Problem.StartLine - B.Problem.StartLine;
  end;
  if Result = 0 then
  begin
    Result := A.Problem.StartCharacter - B.Problem.StartCharacter;
  end;
  if Result = 0 then
  begin
    Result := CompareStr(A.Key, B.Key);
  end;
end;

function CompareLocation(const A, B: TAtlasFinding): Integer;
begin
  Result := CompareText(ExtractFileName(A.FileName), ExtractFileName(B.FileName));
  if Result = 0 then
  begin
    Result := A.Problem.StartLine - B.Problem.StartLine;
  end;
  if Result = 0 then
  begin
    Result := A.Problem.StartCharacter - B.Problem.StartCharacter;
  end;
end;

/// <summary>Vergleich nach der Spalte AColumn (aufsteigend).</summary>
function CompareColumn(AColumn: TAtlasFindingColumn; const A, B: TAtlasFinding): Integer;
begin
  case AColumn of
    TAtlasFindingColumn.Category:
      Result := Ord(A.Category) - Ord(B.Category);
    TAtlasFindingColumn.Message:
      Result := CompareText(A.Problem.Message, B.Problem.Message);
    TAtlasFindingColumn.Line:
      Result := CompareText(A.LineText, B.LineText);
    TAtlasFindingColumn.Location:
      Result := CompareLocation(A, B);
    TAtlasFindingColumn.Rule:
      Result := CompareText(A.Problem.Code, B.Problem.Code);
    TAtlasFindingColumn.Compiler:
      Result := CompareText(A.CompilerText, B.CompilerText);
    TAtlasFindingColumn.Source:
      Result := CompareText(A.SourceText, B.SourceText);
  else
    // Symbol und Art.
    Result := Ord(A.Kind) - Ord(B.Kind);
  end;
end;

function TAtlasFindingsSorted.Compare(const A, B: TAtlasFinding): Integer;
begin
  // Offene Units zuerst (#1108): Die Stufe kommt vor jeder Spalte; ein Klick auf den Spaltenkopf sortiert nur
  // innerhalb der Stufe.
  Result := 0;
  if TiersActive then
  begin
    Result := Ord(A.Tier) - Ord(B.Tier);
  end;
  if (Result = 0) and FSortCustom then
  begin
    Result := CompareColumn(FSortColumn, A, B);
    if FSortDescending then
    begin
      Result := -Result;
    end;
  end;
  if Result = 0 then
  begin
    Result := CompareDefault(A, B);
  end;
end;

function TAtlasFindingsSorted.TiersByFile: Boolean;
begin
  Result := TiersActive and (FGrouping = TAtlasFindingGrouping.ByFile);
end;

function TAtlasFindingsSorted.CompareGroups(const AFirstA, AFirstB: TAtlasFinding;
  const AKeyA, AKeyB: string): Integer;
begin
  // Gruppen nach Datei, Regel bzw. Kategorie; innerhalb der Gruppe die gewählte Sortierung. Nach Datei mit
  // Offene-zuerst (#1108) kommt die Stufe vor dem Namen: aktive Unit, geöffnete und nicht geöffnete je
  // alphabetisch, damit beim Editorwechsel nur die angepinnte Gruppe springt.
  Result := 0;
  if TiersByFile then
  begin
    Result := Ord(AFirstA.Tier) - Ord(AFirstB.Tier);
  end;
  if Result = 0 then
  begin
    case FGrouping of
      TAtlasFindingGrouping.ByFile:
        Result := CompareText(ExtractFileName(AFirstA.FileName), ExtractFileName(AFirstB.FileName));
      TAtlasFindingGrouping.ByRule:
        Result := CompareText(AFirstA.Problem.Code, AFirstB.Problem.Code);
    else
      Result := Ord(AFirstA.Category) - Ord(AFirstB.Category);
    end;
  end;
  if Result = 0 then
  begin
    Result := CompareText(AKeyA, AKeyB);
  end;
end;

function TAtlasFindingsSorted.SortedMatches: TArray<Integer>;
var
  mIndex: Integer;
  mOrder: TList<Integer>;
begin
  mOrder := TList<Integer>.Create;
  try
    for mIndex := 0 to High(FFindings) do
    begin
      if FFilter.Matches(FFindings[mIndex]) and not HiddenByTier(FFindings[mIndex]) then
      begin
        mOrder.Add(mIndex);
      end;
    end;
    mOrder.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Compare(FFindings[A], FFindings[B]);
      end));
    Result := mOrder.ToArray;
  finally
    mOrder.Free;
  end;
end;

/// <summary>AOrder je Stufe aufgeteilt, Reihenfolge bleibt.</summary>
function SplitByTier(const AFindings: TArray<TAtlasFinding>; const AOrder: TArray<Integer>):
  TAtlasFindingTierMembers;
var
  mCount: array[TAtlasFindingTier] of Integer;
  mTier: TAtlasFindingTier;
  mIndex: Integer;
begin
  for mTier := Low(TAtlasFindingTier) to High(TAtlasFindingTier) do
  begin
    mCount[mTier] := 0;
  end;
  for mIndex in AOrder do
  begin
    Inc(mCount[AFindings[mIndex].Tier]);
  end;
  for mTier := Low(TAtlasFindingTier) to High(TAtlasFindingTier) do
  begin
    SetLength(Result[mTier], mCount[mTier]);
    mCount[mTier] := 0;
  end;
  for mIndex in AOrder do
  begin
    mTier := AFindings[mIndex].Tier;
    Result[mTier][mCount[mTier]] := mIndex;
    Inc(mCount[mTier]);
  end;
end;

{ TAtlasFindingsView }

constructor TAtlasFindingsView.Create;
begin
  inherited Create;
  FCollapsed := TDictionary<string, Boolean>.Create;
end;

destructor TAtlasFindingsView.Destroy;
begin
  FCollapsed.Free;
  inherited Destroy;
end;

procedure TAtlasFindingsView.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TAtlasFindingsView.EndUpdate;
begin
  if FUpdateCount = 0 then
  begin
    Exit;
  end;
  Dec(FUpdateCount);
  if (FUpdateCount = 0) and FRebuildPending then
  begin
    Rebuild;
  end;
end;

function TAtlasFindingsView.FindingRow(AIndex: Integer; const AGroupKey: string): TAtlasFindingRow;
begin
  Result := Default(TAtlasFindingRow);
  Result.GroupKey := AGroupKey;
  Result.Finding := AIndex;
  Result.IsNew := FNew.ContainsKey(FFindings[AIndex].Key);
  Result.Tier := FFindings[AIndex].Tier;
  if TiersActive then
  begin
    Result.Pinned := Result.Tier = TAtlasFindingTier.Active;
    Result.Dimmed := (Result.Tier = TAtlasFindingTier.Closed) and (FClosedUnits = TAtlasClosedUnits.Dimmed);
  end;
end;

function TAtlasFindingsView.SectionRow(ATier: TAtlasFindingTier; const AMembers: TArray<Integer>): TAtlasFindingRow;
var
  mIndex: Integer;
  mUnits: TDictionary<string, Boolean>;
begin
  Result := Default(TAtlasFindingRow);
  Result.IsSection := True;
  Result.Finding := -1;
  Result.Tier := ATier;
  Result.Pinned := ATier = TAtlasFindingTier.Active;
  Result.Dimmed := (ATier = TAtlasFindingTier.Closed) and (FClosedUnits = TAtlasClosedUnits.Dimmed);
  Result.Count := Length(AMembers);
  mUnits := TDictionary<string, Boolean>.Create;
  try
    for mIndex in AMembers do
    begin
      mUnits.AddOrSetValue(TAtlasFindings.UnitKey(FFindings[mIndex].FileName), True);
    end;
    Result.Units := mUnits.Count;
  finally
    mUnits.Free;
  end;
  if ATier = TAtlasFindingTier.Active then
  begin
    Result.Caption := ExtractFileName(FActiveFile);
  end;
end;

function TAtlasFindingsView.CleanActiveRow(out ARow: TAtlasFindingRow): Boolean;
begin
  ARow := Default(TAtlasFindingRow);
  Result := TiersActive and FShowCleanActive and IsActiveInScope;
  if not Result then
  begin
    Exit;
  end;
  ARow := SectionRow(TAtlasFindingTier.Active, nil);
  ARow.IsCleanActive := True;
  ARow.Checking := not FActiveChecked;
end;

function TAtlasFindingsView.GroupRow(const AKey: string; const AFirst: TAtlasFinding;
  ACount: Integer): TAtlasFindingRow;
var
  mCollapsed: Boolean;
begin
  Result := Default(TAtlasFindingRow);
  Result.IsGroup := True;
  Result.GroupKey := AKey;
  Result.Finding := -1;
  Result.Count := ACount;
  Result.Category := AFirst.Category;
  if TiersByFile then
  begin
    Result.Tier := AFirst.Tier;
    Result.Pinned := AFirst.Tier = TAtlasFindingTier.Active;
    Result.Dimmed := (AFirst.Tier = TAtlasFindingTier.Closed) and (FClosedUnits = TAtlasClosedUnits.Dimmed);
  end;
  case FGrouping of
    TAtlasFindingGrouping.ByFile:
      Result.Caption := ExtractFileName(AFirst.FileName);
    TAtlasFindingGrouping.ByRule:
      Result.Caption := AFirst.Problem.Code;
    TAtlasFindingGrouping.ByCategory:
      Result.Caption := TAtlasFindings.CategoryName(AFirst.Category);
    TAtlasFindingGrouping.None: ;
  end;
  if not FCollapsed.TryGetValue(AKey, mCollapsed) then
  begin
    mCollapsed := False;
  end;
  Result.Expanded := not mCollapsed;
end;

procedure TAtlasFindingsView.Rebuild;
var
  mOrder: TArray<Integer>;
  mOfTier: TAtlasFindingTierMembers;
  mRows: TList<TAtlasFindingRow>;
begin
  FCountsValid := False;
  if FUpdateCount > 0 then
  begin
    FRebuildPending := True;
    Exit;
  end;
  FRebuildPending := False;
  mOrder := SortedMatches;
  mOfTier := SplitByTier(FFindings, mOrder);
  // Zeilen über Listen statt Array + [x]: Mit zehntausenden Befunden wäre jeder Neuaufbau quadratisch.
  mRows := TList<TAtlasFindingRow>.Create;
  try
    if FGrouping = TAtlasFindingGrouping.None then
    begin
      RebuildFlat(mOrder, mOfTier, mRows);
    end
    else
    begin
      RebuildGrouped(mOrder, mOfTier, mRows);
    end;
    FRows := mRows.ToArray;
  finally
    mRows.Free;
  end;
  // Zugeklappte Gruppen, die gerade keine Befunde haben, bleiben gemerkt: Kommen ihre Befunde wieder, bleiben sie
  // zugeklappt.
end;

procedure TAtlasFindingsView.RebuildFlat(const AOrder: TArray<Integer>; const AOfTier: TAtlasFindingTierMembers;
  ARows: TList<TAtlasFindingRow>);
var
  mIndex: Integer;
  mTier: TAtlasFindingTier;
  mStarted: set of TAtlasFindingTier;
  mRow: TAtlasFindingRow;
  mTiers: Boolean;
begin
  FVisible := AOrder;
  mTiers := TiersActive;
  mStarted := [];
  if mTiers and (Length(AOfTier[TAtlasFindingTier.Active]) = 0) and CleanActiveRow(mRow) then
  begin
    ARows.Add(mRow);
  end;
  for mIndex in FVisible do
  begin
    mTier := FFindings[mIndex].Tier;
    if mTiers and not (mTier in mStarted) then
    begin
      Include(mStarted, mTier);
      ARows.Add(SectionRow(mTier, AOfTier[mTier]));
    end;
    ARows.Add(FindingRow(mIndex, ''));
  end;
end;

/// <summary>Gruppenschlüssel in der Reihenfolge des ersten Auftretens und ihre Befunde.</summary>
procedure CollectGroups(const AKeys: TArray<string>; const AOrder: TArray<Integer>; AGroups: TList<string>;
  AMembers: TObjectDictionary<string, TList<Integer>>);
var
  mIndex: Integer;
  mList: TList<Integer>;
begin
  for mIndex := 0 to High(AOrder) do
  begin
    if not AMembers.TryGetValue(AKeys[mIndex], mList) then
    begin
      AGroups.Add(AKeys[mIndex]);
      mList := TList<Integer>.Create;
      AMembers.Add(AKeys[mIndex], mList);
    end;
    mList.Add(AOrder[mIndex]);
  end;
end;

procedure TAtlasFindingsView.RebuildGrouped(const AOrder: TArray<Integer>; const AOfTier: TAtlasFindingTierMembers;
  ARows: TList<TAtlasFindingRow>);
var
  mKeys: TArray<string>;
  mIndex, mMember: Integer;
  mGroups: TList<string>;
  mMembers: TObjectDictionary<string, TList<Integer>>;
  mKey: string;
  mRow: TAtlasFindingRow;
  mFirst: TAtlasFinding;
  mStarted: set of TAtlasFindingTier;
  mVisible: TList<Integer>;
begin
  SetLength(mKeys, Length(AOrder));
  for mIndex := 0 to High(AOrder) do
  begin
    mKeys[mIndex] := GroupKeyOf(FFindings[AOrder[mIndex]]);
  end;
  mStarted := [];
  mVisible := TList<Integer>.Create;
  mGroups := TList<string>.Create;
  mMembers := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  try
    CollectGroups(mKeys, AOrder, mGroups, mMembers);
    mGroups.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareGroups(FFindings[mMembers[A][0]], FFindings[mMembers[B][0]], A, B);
      end));
    if TiersByFile and (Length(AOfTier[TAtlasFindingTier.Active]) = 0) and CleanActiveRow(mRow) then
    begin
      ARows.Add(mRow);
    end;
    for mKey in mGroups do
    begin
      mFirst := FFindings[mMembers[mKey][0]];
      // Trennzeilen „Geöffnet“ und „Nicht geöffnet“ nur nach Datei.
      if TiersByFile and (mFirst.Tier <> TAtlasFindingTier.Active) and not (mFirst.Tier in mStarted) then
      begin
        Include(mStarted, mFirst.Tier);
        ARows.Add(SectionRow(mFirst.Tier, AOfTier[mFirst.Tier]));
      end;
      mRow := GroupRow(mKey, mFirst, mMembers[mKey].Count);
      ARows.Add(mRow);
      for mMember in mMembers[mKey] do
      begin
        mVisible.Add(mMember);
        if mRow.Expanded then
        begin
          ARows.Add(FindingRow(mMember, mKey));
        end;
      end;
    end;
    FVisible := mVisible.ToArray;
  finally
    mMembers.Free;
    mGroups.Free;
    mVisible.Free;
  end;
end;

function TAtlasFindingsView.Rows: TArray<TAtlasFindingRow>;
begin
  Result := FRows;
end;

function TAtlasFindingsView.Visible: TArray<TAtlasFinding>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(FVisible));
  for mIndex := 0 to High(FVisible) do
  begin
    Result[mIndex] := FFindings[FVisible[mIndex]];
  end;
end;

type
  /// <summary>Units und Dateien, die Counts zählt.</summary>
  TCountUnits = record
    Files: TDictionary<string, Boolean>;
    Open: TDictionary<string, Boolean>;
    Closed: TDictionary<string, Boolean>;
    Hidden: TDictionary<string, Boolean>;
    procedure Init;
    procedure Done;
  end;

procedure TCountUnits.Init;
begin
  Files := TDictionary<string, Boolean>.Create;
  Open := TDictionary<string, Boolean>.Create;
  Closed := TDictionary<string, Boolean>.Create;
  Hidden := TDictionary<string, Boolean>.Create;
end;

procedure TCountUnits.Done;
begin
  Hidden.Free;
  Closed.Free;
  Open.Free;
  Files.Free;
end;

procedure CountKind(AKind: TAtlasFindingKind; var ACounts: TAtlasFindingCounts);
begin
  case AKind of
    TAtlasFindingKind.Error:
      Inc(ACounts.Errors);
    TAtlasFindingKind.Warning:
      Inc(ACounts.Warnings);
  else
    Inc(ACounts.Infos);
  end;
end;

/// <summary>Einen Befund unter dem Filter ohne die Arten zählen; AInKinds = seine Art ist im Filter.</summary>
procedure CountFinding(const AFinding: TAtlasFinding; AHidden, ATiers, AInKinds: Boolean;
  var ACounts: TAtlasFindingCounts; const AUnits: TCountUnits);
begin
  // Ausgegraut ist reine Darstellung und zählt mit; ausgeblendet zählt nicht (#1108).
  if AHidden then
  begin
    if AInKinds then
    begin
      AUnits.Hidden.AddOrSetValue(TAtlasFindings.UnitKey(AFinding.FileName), True);
    end;
    Exit;
  end;
  if ATiers and AInKinds and (AFinding.Tier = TAtlasFindingTier.Closed) then
  begin
    AUnits.Closed.AddOrSetValue(TAtlasFindings.UnitKey(AFinding.FileName), True);
    Inc(ACounts.ClosedFindings);
  end
  else if ATiers and AInKinds then
  begin
    AUnits.Open.AddOrSetValue(TAtlasFindings.UnitKey(AFinding.FileName), True);
    Inc(ACounts.OpenFindings);
  end;
  CountKind(AFinding.Kind, ACounts);
  if AInKinds then
  begin
    AUnits.Files.AddOrSetValue(AnsiLowerCase(AFinding.FileName), True);
  end;
end;

function TAtlasFindingsView.Counts: TAtlasFindingCounts;
var
  mFinding: TAtlasFinding;
  mUnits: TCountUnits;
  mTiers: Boolean;
begin
  if FCountsValid then
  begin
    Exit(FCounts);
  end;
  Result := Default(TAtlasFindingCounts);
  mTiers := TiersActive;
  mUnits.Init;
  try
    for mFinding in FFindings do
    begin
      if FFilter.MatchesExceptKind(mFinding) then
      begin
        CountFinding(mFinding, HiddenByTier(mFinding), mTiers, mFinding.Kind in FFilter.Kinds, Result, mUnits);
      end;
    end;
    Result.Files := mUnits.Files.Count;
    Result.OpenUnits := mUnits.Open.Count;
    Result.ClosedUnits := mUnits.Closed.Count;
    Result.HiddenUnits := mUnits.Hidden.Count;
    FCounts := Result;
    FCountsValid := True;
  finally
    mUnits.Done;
  end;
end;

procedure TAtlasFindingsView.SetExpanded(const AGroupKey: string; AExpanded: Boolean);
begin
  if AExpanded then
  begin
    FCollapsed.Remove(AGroupKey);
  end
  else
  begin
    FCollapsed.AddOrSetValue(AGroupKey, True);
  end;
  Rebuild;
end;

procedure TAtlasFindingsView.Toggle(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FRows)) or not FRows[ARow].IsGroup then
  begin
    Exit;
  end;
  SetExpanded(FRows[ARow].GroupKey, not FRows[ARow].Expanded);
end;

procedure TAtlasFindingsView.Select(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FRows)) then
  begin
    FSelectedKey := '';
  end
  else if FRows[ARow].IsSection then
  begin
    // Trennzeilen sind nicht wählbar: Die Auswahl bleibt, wo sie war.
    Exit;
  end
  else if FRows[ARow].IsGroup then
  begin
    FSelectedKey := 'group:' + FRows[ARow].GroupKey;
  end
  else
  begin
    FSelectedKey := FFindings[FRows[ARow].Finding].Key;
  end;
end;

function TAtlasFindingsView.GetSelectedRow: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if FSelectedKey = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FRows) do
  begin
    if FRows[mIndex].IsSection then
    begin
      Continue;
    end
    else if FRows[mIndex].IsGroup then
    begin
      if FSelectedKey = 'group:' + FRows[mIndex].GroupKey then
      begin
        Exit(mIndex);
      end;
    end
    else if FFindings[FRows[mIndex].Finding].Key = FSelectedKey then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasFindingsView.SelectedFinding(out AFinding: TAtlasFinding): Boolean;
var
  mRow: Integer;
begin
  AFinding := Default(TAtlasFinding);
  mRow := GetSelectedRow;
  Result := (mRow >= 0) and not FRows[mRow].IsGroup and not FRows[mRow].IsSection;
  if Result then
  begin
    AFinding := FFindings[FRows[mRow].Finding];
  end;
end;

function TAtlasFindingsView.SelectAt(const AFileName: string; ALine: Integer): Boolean;
var
  mIndex: Integer;
  mFinding: TAtlasFinding;
  mKey: string;
begin
  for mIndex in FVisible do
  begin
    mFinding := FFindings[mIndex];
    if SameText(mFinding.FileName, AFileName) and (ALine >= mFinding.Problem.StartLine) and
      (ALine <= Max(mFinding.Problem.StartLine, mFinding.Problem.EndLine)) then
    begin
      FSelectedKey := mFinding.Key;
      mKey := GroupKeyOf(mFinding);
      if (mKey <> '') and FCollapsed.ContainsKey(mKey) then
      begin
        SetExpanded(mKey, True);
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasFindingsView.Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
var
  mCurrent, mIndex, mTarget: Integer;
  mKey: string;
begin
  AFinding := Default(TAtlasFinding);
  if Length(FVisible) = 0 then
  begin
    Exit(False);
  end;
  mCurrent := -1;
  for mIndex := 0 to High(FVisible) do
  begin
    if FFindings[FVisible[mIndex]].Key = FSelectedKey then
    begin
      mCurrent := mIndex;
    end;
  end;
  if mCurrent < 0 then
  begin
    if AForward then
    begin
      mTarget := 0;
    end
    else
    begin
      mTarget := High(FVisible);
    end;
  end
  else if AForward then
  begin
    mTarget := (mCurrent + 1) mod Length(FVisible);
  end
  else
  begin
    mTarget := (mCurrent - 1 + Length(FVisible)) mod Length(FVisible);
  end;
  AFinding := FFindings[FVisible[mTarget]];
  FSelectedKey := AFinding.Key;
  mKey := GroupKeyOf(AFinding);
  if (mKey <> '') and FCollapsed.ContainsKey(mKey) then
  begin
    SetExpanded(mKey, True);
  end;
  Result := True;
end;

function TAtlasFindingsView.GroupMembers(const AGroupKey: string): TArray<Integer>;
var
  mIndex: Integer;
  mList: TList<Integer>;
begin
  mList := TList<Integer>.Create;
  try
    for mIndex in FVisible do
    begin
      if GroupKeyOf(FFindings[mIndex]) = AGroupKey then
      begin
        mList.Add(mIndex);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TAtlasFindingsView.FindingsOfRows(const ARows: TArray<Integer>): TArray<TAtlasFinding>;
var
  mRow, mIndex: Integer;
  mMembers: TArray<Integer>;
  mDone: TDictionary<Integer, Boolean>;
  mList: TList<TAtlasFinding>;
begin
  mDone := TDictionary<Integer, Boolean>.Create;
  mList := TList<TAtlasFinding>.Create;
  try
    for mRow in ARows do
    begin
      if (mRow < 0) or (mRow > High(FRows)) or FRows[mRow].IsSection then
      begin
        Continue;
      end;
      if FRows[mRow].IsGroup then
      begin
        mMembers := GroupMembers(FRows[mRow].GroupKey);
      end
      else
      begin
        mMembers := TArray<Integer>.Create(FRows[mRow].Finding);
      end;
      for mIndex in mMembers do
      begin
        if not mDone.ContainsKey(mIndex) then
        begin
          mDone.Add(mIndex, True);
          mList.Add(FFindings[mIndex]);
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mDone.Free;
  end;
end;

end.
