unit Argus.Core.Hover.History;

// Verlauf im Hover-Tooltip (#588): Der erste Inhalt ist die Kurzform. Ein Klick
// auf einen Typ holt dessen Inhalt (über den Fundort), hängt ihn an und heftet
// den Tooltip an. Zurück und Sprung auf einen Eintrag im Pfad kürzen den
// Verlauf; höchstens zehn Schritte, die ältesten fallen weg. Ein Klick auf den
// gerade angezeigten Typ erzeugt keinen neuen Eintrag.

interface

uses
  Argus.Core.Hover.Contract;

type
  /// <summary>Holt den Inhalt zum Typ ARef; False, wenn der Server nichts liefert.</summary>
  TArgusHoverFetch = reference to function(const ARef: TArgusHoverTypeRef; out AData: TArgusHoverData): Boolean;

  /// <summary>Eintrag der Pfadzeile: Index im Verlauf, -1 für "…".</summary>
  TArgusHoverPathItem = record
    Index: Integer;
    Caption: string;
  end;

  TArgusHoverHistory = class
  public const
    MaxSteps = 10;
    /// <summary>Mehr Einträge zeigt die Pfadzeile nicht; davor steht "…".</summary>
    MaxPathShown = 4;
  private
    FItems: TArray<TArgusHoverData>;
    FPinned: Boolean;
    FFetch: TArgusHoverFetch;
    function GetCurrent: TArgusHoverData;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TArgusHoverData;
  public
    constructor Create(const AFetch: TArgusHoverFetch);
    /// <summary>Neuer Tooltip (Kurzform, nicht angeheftet).</summary>
    procedure Start(const AData: TArgusHoverData);
    procedure Clear;
    /// <summary>Zeigt den Typ ARef: holt ihn, hängt ihn an und heftet an. False, wenn nichts zu zeigen ist;
    /// bei demselben Typ True ohne neuen Eintrag.</summary>
    function Open(const ARef: TArgusHoverTypeRef): Boolean;
    /// <summary>Einen Schritt zurück; False am Anfang.</summary>
    function Back: Boolean;
    /// <summary>Springt auf den Eintrag AIndex; spätere Einträge fallen weg.</summary>
    function JumpTo(AIndex: Integer): Boolean;
    function CanGoBack: Boolean;
    /// <summary>Einträge der Pfadzeile; bei mehr als MaxPathShown zuerst "…".</summary>
    function Path: TArray<TArgusHoverPathItem>;
    property Current: TArgusHoverData read GetCurrent;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TArgusHoverData read GetItem;
    property Pinned: Boolean read FPinned write FPinned;
  end;

implementation

uses
  System.SysUtils;

constructor TArgusHoverHistory.Create(const AFetch: TArgusHoverFetch);
begin
  inherited Create;
  FFetch := AFetch;
end;

procedure TArgusHoverHistory.Start(const AData: TArgusHoverData);
begin
  FItems := [AData];
  FPinned := False;
end;

procedure TArgusHoverHistory.Clear;
begin
  FItems := nil;
  FPinned := False;
end;

function TArgusHoverHistory.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TArgusHoverHistory.GetCurrent: TArgusHoverData;
begin
  if Length(FItems) = 0 then
    Result := Default(TArgusHoverData)
  else
    Result := FItems[High(FItems)];
end;

function TArgusHoverHistory.GetItem(AIndex: Integer): TArgusHoverData;
begin
  Result := FItems[AIndex];
end;

function TArgusHoverHistory.Open(const ARef: TArgusHoverTypeRef): Boolean;
var
  Data: TArgusHoverData;
begin
  if Length(FItems) = 0 then
    Exit(False);
  // Derselbe Typ wie angezeigt: kein neuer Eintrag.
  if ARef.HasLocation and (ARef.Key = Current.Location.Key) then
  begin
    FPinned := True;
    Exit(True);
  end;
  if not (Assigned(FFetch) and FFetch(ARef, Data) and Data.Found) then
    Exit(False);
  if Data.Location.Name = '' then
    Data.Location.Name := ARef.Name;
  FItems := FItems + [Data];
  if Length(FItems) > MaxSteps then
    Delete(FItems, 0, Length(FItems) - MaxSteps);
  FPinned := True;
  Result := True;
end;

function TArgusHoverHistory.CanGoBack: Boolean;
begin
  Result := Length(FItems) > 1;
end;

function TArgusHoverHistory.Back: Boolean;
begin
  Result := CanGoBack;
  if Result then
    SetLength(FItems, Length(FItems) - 1);
end;

function TArgusHoverHistory.JumpTo(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Length(FItems));
  if Result then
    SetLength(FItems, AIndex + 1);
end;

function TArgusHoverHistory.Path: TArray<TArgusHoverPathItem>;
var
  First, Index: Integer;
  Item: TArgusHoverPathItem;
begin
  Result := nil;
  First := 0;
  if Length(FItems) > MaxPathShown then
  begin
    First := Length(FItems) - MaxPathShown;
    Item.Index := -1;
    Item.Caption := '…';
    Result := Result + [Item];
  end;
  for Index := First to High(FItems) do
  begin
    Item.Index := Index;
    Item.Caption := FItems[Index].Title;
    Result := Result + [Item];
  end;
end;

end.
