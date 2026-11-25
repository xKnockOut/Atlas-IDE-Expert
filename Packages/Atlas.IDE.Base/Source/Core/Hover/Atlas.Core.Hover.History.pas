unit Atlas.Core.Hover.History;

// Verlauf im Hover-Tooltip (#588): Der erste Inhalt ist die Kurzform. Ein Klick
// auf einen Typ heftet den Tooltip an; seinen Inhalt holt der Aufrufer über den
// Fundort im Hintergrund und hängt ihn mit FinishOpen an (der Hauptthread wartet
// nie auf den Server). Zurück und Sprung auf einen Eintrag im Pfad kürzen den
// Verlauf; höchstens zehn Schritte, die ältesten fallen weg. Ein Klick auf den
// gerade angezeigten Typ erzeugt keinen neuen Eintrag. Stamp zählt jede Änderung
// der Einträge: Eine Antwort, die nach Zurück, Sprung, neuem Tooltip oder einem
// anderen Klick ankommt, verwirft FinishOpen.

interface

uses
  Atlas.Core.Hover.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Folge eines Klicks: nichts zu zeigen, schon angezeigt, Inhalt holen.</summary>
  TAtlasHoverOpenStep = (None, Shown, Fetch);
  {$SCOPEDENUMS OFF}

  /// <summary>Eintrag der Pfadzeile: Index im Verlauf, -1 für "…".</summary>
  TAtlasHoverPathItem = record
    Index: Integer;
    Caption: string;
  end;

  TAtlasHoverHistory = class
  public const
    cMaxSteps = 10;
    /// <summary>Mehr Einträge zeigt die Pfadzeile nicht; davor steht "…".</summary>
    cMaxPathShown = 4;
  private
    FItems: TArray<TAtlasHoverData>;
    FPinned: Boolean;
    FStamp: Integer;
    procedure Changed;
    function GetCurrent: TAtlasHoverData;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TAtlasHoverData;
  public
    /// <summary>Neuer Tooltip (Kurzform, nicht angeheftet).</summary>
    procedure Start(const AData: TAtlasHoverData);
    procedure Clear;
    /// <summary>Klick auf den Typ ARef: None ohne Verlauf oder Fundort; Shown bei demselben Typ (angeheftet, kein
    /// neuer Eintrag); Fetch heftet an, der Aufrufer holt den Inhalt und ruft FinishOpen mit dem jetzigen
    /// Stamp.</summary>
    function BeginOpen(const ARef: TAtlasHoverTypeRef): TAtlasHoverOpenStep;
    /// <summary>Hängt den geholten Inhalt AData zu ARef an. False, wenn nichts gefunden wurde oder sich der Verlauf
    /// seit AStamp geändert hat.</summary>
    function FinishOpen(const ARef: TAtlasHoverTypeRef; const AData: TAtlasHoverData; AStamp: Integer): Boolean;
    /// <summary>Einen Schritt zurück; False am Anfang.</summary>
    function Back: Boolean;
    /// <summary>Springt auf den Eintrag AIndex; spätere Einträge fallen weg.</summary>
    function JumpTo(AIndex: Integer): Boolean;
    function CanGoBack: Boolean;
    /// <summary>Einträge der Pfadzeile, höchstens MaxPathShown; bei mehr zuerst "…" und die letzten.</summary>
    function Path: TArray<TAtlasHoverPathItem>;
    property Current: TAtlasHoverData read GetCurrent;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TAtlasHoverData read GetItem;
    property Pinned: Boolean read FPinned write FPinned;
    /// <summary>Zählt jede Änderung der Einträge.</summary>
    property Stamp: Integer read FStamp;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasHoverHistory }

procedure TAtlasHoverHistory.Changed;
begin
  Inc(FStamp);
end;

function TAtlasHoverHistory.GetCurrent: TAtlasHoverData;
begin
  if Length(FItems) = 0 then
  begin
    Result := Default(TAtlasHoverData);
  end
  else
  begin
    Result := FItems[High(FItems)];
  end;
end;

function TAtlasHoverHistory.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TAtlasHoverHistory.GetItem(AIndex: Integer): TAtlasHoverData;
begin
  Result := FItems[AIndex];
end;

procedure TAtlasHoverHistory.Start(const AData: TAtlasHoverData);
begin
  FItems := [AData];
  FPinned := False;
  Changed;
end;

procedure TAtlasHoverHistory.Clear;
begin
  FItems := nil;
  FPinned := False;
  Changed;
end;

function TAtlasHoverHistory.BeginOpen(const ARef: TAtlasHoverTypeRef): TAtlasHoverOpenStep;
begin
  if (Length(FItems) = 0) or not ARef.HasLocation then
  begin
    Exit(TAtlasHoverOpenStep.None);
  end;
  // Angeheftet, sobald geklickt: Der Tooltip bleibt stehen, solange der Inhalt unterwegs ist.
  FPinned := True;
  // Derselbe Typ wie angezeigt: kein neuer Eintrag.
  if ARef.Key = Current.Location.Key then
  begin
    Exit(TAtlasHoverOpenStep.Shown);
  end;
  Result := TAtlasHoverOpenStep.Fetch;
end;

function TAtlasHoverHistory.FinishOpen(const ARef: TAtlasHoverTypeRef; const AData: TAtlasHoverData;
  AStamp: Integer): Boolean;
var
  mData: TAtlasHoverData;
begin
  if (AStamp <> FStamp) or (Length(FItems) = 0) or not AData.Found then
  begin
    Exit(False);
  end;
  mData := AData;
  if mData.Location.Name = '' then
  begin
    mData.Location.Name := ARef.Name;
  end;
  FItems := FItems + [mData];
  if Length(FItems) > cMaxSteps then
  begin
    Delete(FItems, 0, Length(FItems) - cMaxSteps);
  end;
  FPinned := True;
  Changed;
  Result := True;
end;

function TAtlasHoverHistory.Back: Boolean;
begin
  Result := CanGoBack;
  if Result then
  begin
    SetLength(FItems, Length(FItems) - 1);
    Changed;
  end;
end;

function TAtlasHoverHistory.JumpTo(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Length(FItems));
  if Result then
  begin
    SetLength(FItems, AIndex + 1);
    Changed;
  end;
end;

function TAtlasHoverHistory.CanGoBack: Boolean;
begin
  Result := Length(FItems) > 1;
end;

function TAtlasHoverHistory.Path: TArray<TAtlasHoverPathItem>;
var
  mFirst, mIndex: Integer;
  mItem: TAtlasHoverPathItem;
begin
  Result := nil;
  mFirst := 0;
  if Length(FItems) > cMaxPathShown then
  begin
    mFirst := Length(FItems) - cMaxPathShown + 1;
    mItem.Index := -1;
    mItem.Caption := '…';
    Result := Result + [mItem];
  end;
  for mIndex := mFirst to High(FItems) do
  begin
    mItem.Index := mIndex;
    mItem.Caption := FItems[mIndex].Title;
    Result := Result + [mItem];
  end;
end;

end.
