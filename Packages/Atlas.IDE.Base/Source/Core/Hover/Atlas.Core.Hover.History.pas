unit Atlas.Core.Hover.History;

// Verlauf im Hover-Tooltip (#588): Der erste Inhalt ist die Kurzform. Ein Klick
// auf einen Typ holt dessen Inhalt (über den Fundort), hängt ihn an und heftet
// den Tooltip an. Zurück und Sprung auf einen Eintrag im Pfad kürzen den
// Verlauf; höchstens zehn Schritte, die ältesten fallen weg. Ein Klick auf den
// gerade angezeigten Typ erzeugt keinen neuen Eintrag.

interface

uses
  Atlas.Core.Hover.Contract;

type
  /// <summary>Holt den Inhalt zum Typ ARef; False, wenn der Server nichts liefert.</summary>
  TAtlasHoverFetch = reference to function(const ARef: TAtlasHoverTypeRef; out AData: TAtlasHoverData): Boolean;

  /// <summary>Eintrag der Pfadzeile: Index im Verlauf, -1 für "…".</summary>
  TAtlasHoverPathItem = record
    Index: Integer;
    Caption: string;
  end;

  TAtlasHoverHistory = class
  public const
    MaxSteps = 10;
    /// <summary>Mehr Einträge zeigt die Pfadzeile nicht; davor steht "…".</summary>
    MaxPathShown = 4;
  private
    FItems: TArray<TAtlasHoverData>;
    FPinned: Boolean;
    FFetch: TAtlasHoverFetch;
    function GetCurrent: TAtlasHoverData;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TAtlasHoverData;
  public
    constructor Create(const AFetch: TAtlasHoverFetch);
    /// <summary>Neuer Tooltip (Kurzform, nicht angeheftet).</summary>
    procedure Start(const AData: TAtlasHoverData);
    procedure Clear;
    /// <summary>Zeigt den Typ ARef: holt ihn, hängt ihn an und heftet an. False, wenn nichts zu zeigen ist;
    /// bei demselben Typ True ohne neuen Eintrag.</summary>
    function Open(const ARef: TAtlasHoverTypeRef): Boolean;
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
  end;

implementation

uses
  System.SysUtils;

constructor TAtlasHoverHistory.Create(const AFetch: TAtlasHoverFetch);
begin
  inherited Create;
  FFetch := AFetch;
end;

procedure TAtlasHoverHistory.Start(const AData: TAtlasHoverData);
begin
  FItems := [AData];
  FPinned := False;
end;

procedure TAtlasHoverHistory.Clear;
begin
  FItems := nil;
  FPinned := False;
end;

function TAtlasHoverHistory.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TAtlasHoverHistory.GetCurrent: TAtlasHoverData;
begin
  if Length(FItems) = 0 then
    Result := Default(TAtlasHoverData)
  else
    Result := FItems[High(FItems)];
end;

function TAtlasHoverHistory.GetItem(AIndex: Integer): TAtlasHoverData;
begin
  Result := FItems[AIndex];
end;

function TAtlasHoverHistory.Open(const ARef: TAtlasHoverTypeRef): Boolean;
var
  Data: TAtlasHoverData;
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

function TAtlasHoverHistory.CanGoBack: Boolean;
begin
  Result := Length(FItems) > 1;
end;

function TAtlasHoverHistory.Back: Boolean;
begin
  Result := CanGoBack;
  if Result then
    SetLength(FItems, Length(FItems) - 1);
end;

function TAtlasHoverHistory.JumpTo(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Length(FItems));
  if Result then
    SetLength(FItems, AIndex + 1);
end;

function TAtlasHoverHistory.Path: TArray<TAtlasHoverPathItem>;
var
  First, Index: Integer;
  Item: TAtlasHoverPathItem;
begin
  Result := nil;
  First := 0;
  if Length(FItems) > MaxPathShown then
  begin
    First := Length(FItems) - MaxPathShown + 1;
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
