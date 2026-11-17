unit Atlas.Core.Welcome.QuickActionRows;

// Zeilen der Knopfleiste mit Schnellaktionen (#764) eines Bereichs der
// Willkommensseite, ohne VCL: Projekte der Zeilen mit Knöpfen, Stand der
// letzten Aktion und Rechtecken der Knöpfe (entstehen beim Zeichnen) sowie die
// Zeile und der Knopf unter der Maus bzw. mit der Tastatur gewählt. Welche
// Zeile die Leiste zeigt (ActiveRow) und welcher Knopf an einer Stelle liegt
// (HitButton), entscheidet diese Klasse; Zeichnen, Zeitgeber und Tastatur
// bleiben in TAtlasQuickActionsBar (Atlas.UI.Welcome.QuickActions).

interface

uses
  System.Types,
  Atlas.Core.Welcome.QuickActions;

type
  /// <summary>Zeile und Knopf unter der Maus bzw. mit der Tastatur gewählt (-1 = keine).</summary>
  TAtlasQuickActionSelection = class
  private
    FHoverRow: Integer;
    FHoverButton: Integer;
    FKeyRow: Integer;
    FKeyButton: Integer;
    FUseKey: Boolean;
  public
    constructor Create;
    property HoverRow: Integer read FHoverRow write FHoverRow;
    property HoverButton: Integer read FHoverButton write FHoverButton;
    property KeyRow: Integer read FKeyRow write FKeyRow;
    property KeyButton: Integer read FKeyButton write FKeyButton;
    /// <summary>Letzte Eingabe kam von der Tastatur: Die gewählte Zeile ist die aktive, nicht die unter der Maus.
    /// </summary>
    property UseKey: Boolean read FUseKey write FUseKey;
  end;

  TAtlasQuickActionRows = class
  private
    FProjects: TArray<string>;
    FButtons: TArray<TAtlasQuickActionButtons>;
    FStates: TArray<TAtlasQuickActionState>;
    FRects: TArray<TArray<TRect>>;
    FNowMs: UInt64;
    FSelection: TAtlasQuickActionSelection;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Zeilen neu: Knöpfe (nil = keine) und Stand je Projekt, Zeitpunkt ANowMs; Rechtecke leer, Auswahl
    /// in die neuen Grenzen.</summary>
    procedure Load(const AProjects: TArray<string>; const AButtons: TArray<TAtlasQuickActionButtons>;
      const AStates: TArray<TAtlasQuickActionState>; ANowMs: UInt64);
    /// <summary>Nur Stand und Zeitpunkt neu (Zeitgeber, „baut … 12 s“).</summary>
    procedure Refresh(const AStates: TArray<TAtlasQuickActionState>; ANowMs: UInt64);
    function Count: Integer;
    function IsRow(ARow: Integer): Boolean;
    function Projects: TArray<string>;
    function Project(ARow: Integer): string;
    /// <summary>Knöpfe der Zeile; leer außerhalb.</summary>
    function Buttons(ARow: Integer): TAtlasQuickActionButtons;
    /// <summary>Stand der Zeile; Idle außerhalb.</summary>
    function State(ARow: Integer): TAtlasQuickActionState;
    /// <summary>Läuft in einer Zeile eine Aktion?</summary>
    function Running: Boolean;
    /// <summary>Rechtecke der Knöpfe aus dem letzten Zeichnen; leer außerhalb.</summary>
    function Rects(ARow: Integer): TArray<TRect>;
    procedure SetRects(ARow: Integer; const ARects: TArray<TRect>);
    /// <summary>Zeile mit Knopfleiste: mit der Tastatur gewählt (AFocused: Tastatur hat den Fokus) bzw. unter der
    /// Maus; -1 = keine oder ohne Knöpfe.</summary>
    function ActiveRow(AFocused: Boolean): Integer;
    /// <summary>Knopf an AX, AY in ARow (nach dem Zeichnen); AMenu: auf dem Teil ▾ von „Öffnen und bauen“
    /// (AMenuWidth breit).</summary>
    function HitButton(ARow, AX, AY, AMenuWidth: Integer; out AIndex: Integer; out AMenu: Boolean): Boolean;
    /// <summary>Zeitpunkt der letzten Aktualisierung (ms).</summary>
    property NowMs: UInt64 read FNowMs;
    /// <summary>Auswahl; die Leiste und ihre Tastatur setzen sie direkt.</summary>
    property Selection: TAtlasQuickActionSelection read FSelection;
  end;

implementation

{ TAtlasQuickActionSelection }

constructor TAtlasQuickActionSelection.Create;
begin
  inherited Create;
  FHoverRow := -1;
  FHoverButton := -1;
  FKeyRow := -1;
  FKeyButton := -1;
end;

{ TAtlasQuickActionRows }

constructor TAtlasQuickActionRows.Create;
begin
  inherited Create;
  FSelection := TAtlasQuickActionSelection.Create;
end;

destructor TAtlasQuickActionRows.Destroy;
begin
  FSelection.Free;
  inherited;
end;

procedure TAtlasQuickActionRows.Load(const AProjects: TArray<string>;
  const AButtons: TArray<TAtlasQuickActionButtons>; const AStates: TArray<TAtlasQuickActionState>; ANowMs: UInt64);
var
  mRow: Integer;
begin
  FProjects := Copy(AProjects);
  FNowMs := ANowMs;
  FButtons := nil;
  FStates := nil;
  FRects := nil;
  SetLength(FButtons, Length(FProjects));
  SetLength(FStates, Length(FProjects));
  SetLength(FRects, Length(FProjects));
  for mRow := 0 to High(FProjects) do
  begin
    FStates[mRow] := TAtlasQuickActionState.Idle;
    if mRow <= High(AButtons) then
    begin
      FButtons[mRow] := AButtons[mRow];
    end;
    if mRow <= High(AStates) then
    begin
      FStates[mRow] := AStates[mRow];
    end;
  end;
  if Selection.KeyRow > High(FProjects) then
  begin
    Selection.KeyRow := High(FProjects);
  end;
  if Selection.HoverRow > High(FProjects) then
  begin
    Selection.HoverRow := -1;
  end;
  if IsRow(Selection.KeyRow) and (Selection.KeyButton > High(FButtons[Selection.KeyRow])) then
  begin
    Selection.KeyButton := -1;
  end;
  Selection.HoverButton := -1;
end;

procedure TAtlasQuickActionRows.Refresh(const AStates: TArray<TAtlasQuickActionState>; ANowMs: UInt64);
var
  mRow: Integer;
begin
  FNowMs := ANowMs;
  for mRow := 0 to High(FStates) do
  begin
    if mRow <= High(AStates) then
    begin
      FStates[mRow] := AStates[mRow];
    end;
  end;
end;

function TAtlasQuickActionRows.Count: Integer;
begin
  Result := Length(FProjects);
end;

function TAtlasQuickActionRows.IsRow(ARow: Integer): Boolean;
begin
  Result := (ARow >= 0) and (ARow <= High(FProjects));
end;

function TAtlasQuickActionRows.Projects: TArray<string>;
begin
  Result := Copy(FProjects);
end;

function TAtlasQuickActionRows.Project(ARow: Integer): string;
begin
  Result := '';
  if IsRow(ARow) then
  begin
    Result := FProjects[ARow];
  end;
end;

function TAtlasQuickActionRows.Buttons(ARow: Integer): TAtlasQuickActionButtons;
begin
  Result := nil;
  if IsRow(ARow) then
  begin
    Result := FButtons[ARow];
  end;
end;

function TAtlasQuickActionRows.State(ARow: Integer): TAtlasQuickActionState;
begin
  Result := TAtlasQuickActionState.Idle;
  if IsRow(ARow) then
  begin
    Result := FStates[ARow];
  end;
end;

function TAtlasQuickActionRows.Running: Boolean;
var
  mState: TAtlasQuickActionState;
begin
  Result := False;
  for mState in FStates do
  begin
    Result := Result or mState.Running;
  end;
end;

function TAtlasQuickActionRows.Rects(ARow: Integer): TArray<TRect>;
begin
  Result := nil;
  if IsRow(ARow) then
  begin
    Result := FRects[ARow];
  end;
end;

procedure TAtlasQuickActionRows.SetRects(ARow: Integer; const ARects: TArray<TRect>);
begin
  if IsRow(ARow) then
  begin
    FRects[ARow] := ARects;
  end;
end;

function TAtlasQuickActionRows.ActiveRow(AFocused: Boolean): Integer;
begin
  Result := -1;
  if Selection.UseKey and AFocused and IsRow(Selection.KeyRow) then
  begin
    Result := Selection.KeyRow;
  end
  else if IsRow(Selection.HoverRow) then
  begin
    Result := Selection.HoverRow;
  end
  else if AFocused and IsRow(Selection.KeyRow) then
  begin
    Result := Selection.KeyRow;
  end;
  if (Result >= 0) and (Length(FButtons[Result]) = 0) then
  begin
    Result := -1;
  end;
end;

function TAtlasQuickActionRows.HitButton(ARow, AX, AY, AMenuWidth: Integer; out AIndex: Integer;
  out AMenu: Boolean): Boolean;
var
  mRects: TArray<TRect>;
  mIndex: Integer;
begin
  AIndex := -1;
  AMenu := False;
  Result := False;
  if not IsRow(ARow) then
  begin
    Exit;
  end;
  mRects := FRects[ARow];
  if Length(mRects) <> Length(FButtons[ARow]) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mRects) do
  begin
    if mRects[mIndex].Contains(Point(AX, AY)) then
    begin
      AIndex := mIndex;
      AMenu := (FButtons[ARow][mIndex].Action = TAtlasQuickAction.Build) and
        (AX >= mRects[mIndex].Right - AMenuWidth);
      Result := True;
      Exit;
    end;
  end;
end;

end.
