unit Atlas.Core.Editor.BarDock;

// Reihenfolge der Leisten, die Atlas über bzw. unter dem Bereich des Editors
// einhängt (Brotkrumenleiste der Datenbindung, Statusleiste, Designer-Leiste).
// Sie stehen nicht im Eltern-Steuerelement des Editors („EditorPanel“),
// sondern eine Ebene höher daneben: Im Designer reicht die Designfläche über
// das ganze EditorPanel und lag samt Bildlaufleisten über Leisten darin.
// Daneben stehen dort die Steuerelemente der IDE (Reiter oben, Statuszeile
// unten); die VCL ordnet gleich ausgerichtete Geschwister nach ihrer Lage:
// alTop nach Top (kleiner = weiter oben), alBottom nach der Unterkante
// Top + Height (größer = weiter unten). Gleichstände entscheidet die VCL je
// nach Aufrufer, darum vergibt dieser Kern nur verschiedene Werte.
// - Order: kleiner = näher am Editor. Eigene Leisten stehen direkt am Editor,
//   in Order, und zwischen Editor und allen fremden Steuerelementen derselben
//   Seite.
// - Ordered prüft das, Tops rechnet die Top-Werte, die die VCL beim nächsten
//   Ausrichten in genau diese Reihenfolge bringt; fremde bleiben unverändert.
// Reine Rechnung ohne VCL.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Seite des Editors: oben (alTop) oder unten (alBottom).</summary>
  TAtlasBarSide = (Top, Bottom);
{$SCOPEDENUMS OFF}

  /// <summary>Ein gleich ausgerichtetes Geschwister: eigene Leiste (Own, mit Order) oder fremdes Steuerelement.
  /// </summary>
  TAtlasBarDockItem = record
    Own: Boolean;
    /// <summary>Kleiner = näher am Editor; nur für eigene.</summary>
    Order: Integer;
    Top: Integer;
    Height: Integer;
    class function Create(AOwn: Boolean; AOrder, ATop, AHeight: Integer): TAtlasBarDockItem; static;
  end;

  /// <summary>Platz einer Art von Leisten neben dem Editor: Seite und Order; Order -1 = nicht dort.</summary>
  TAtlasBarDockPlace = record
    Side: TAtlasBarSide;
    Order: Integer;
    class function None: TAtlasBarDockPlace; static;
    class function Create(ASide: TAtlasBarSide; AOrder: Integer): TAtlasBarDockPlace; static;
    function Docked: Boolean;
  end;

  TAtlasBarDock = record
  public const
    /// <summary>Order der Statusleiste: unten am weitesten vom Editor, direkt über der Statuszeile der IDE.
    /// Leisten der Module wählen kleinere Werte.</summary>
    cOrderStatusBar = 100;
    /// <summary>Order einer Leiste direkt am Editor.</summary>
    cOrderNearest = 0;
  public
    /// <summary>Stehen die eigenen Leisten in Order direkt am Editor, vor allen fremden?</summary>
    class function Ordered(ASide: TAtlasBarSide; const AItems: TArray<TAtlasBarDockItem>): Boolean; static;
    /// <summary>Top je Eintrag (gleiche Indizes), mit dem die VCL die eigenen Leisten in Order direkt an den
    /// Editor stellt; fremde behalten ihr Top. AClientHeight: Höhe des Eltern-Steuerelements.</summary>
    class function Tops(ASide: TAtlasBarSide; const AItems: TArray<TAtlasBarDockItem>;
      AClientHeight: Integer): TArray<Integer>; static;
  end;

implementation

uses
  System.Math;

{ Hilfen }

/// <summary>Lagewert, nach dem die VCL ordnet: alTop Top, alBottom die Unterkante.</summary>
function Key(ASide: TAtlasBarSide; const AItem: TAtlasBarDockItem): Integer;
begin
  Result := AItem.Top;
  if ASide = TAtlasBarSide.Bottom then
  begin
    Result := AItem.Top + AItem.Height;
  end;
end;

/// <summary>Steht ein Eintrag mit Lagewert AKey weiter vom Editor weg als einer mit AThan?</summary>
function Farther(ASide: TAtlasBarSide; AKey, AThan: Integer): Boolean;
begin
  Result := AKey > AThan;
  if ASide = TAtlasBarSide.Top then
  begin
    Result := AKey < AThan;
  end;
end;

/// <summary>Indizes der eigenen Leisten, vom Editor weg geordnet (Order, bei Gleichstand Index).</summary>
function OwnByOrder(const AItems: TArray<TAtlasBarDockItem>): TArray<Integer>;
var
  mIndex, mPos, mCount: Integer;
begin
  SetLength(Result, Length(AItems));
  mCount := 0;
  for mIndex := 0 to High(AItems) do
  begin
    if not AItems[mIndex].Own then
    begin
      Continue;
    end;
    // Einfügen: stabil nach Order, bei Gleichstand nach Index.
    mPos := mCount;
    while (mPos > 0) and (AItems[Result[mPos - 1]].Order > AItems[mIndex].Order) do
    begin
      Result[mPos] := Result[mPos - 1];
      Dec(mPos);
    end;
    Result[mPos] := mIndex;
    Inc(mCount);
  end;
  SetLength(Result, mCount);
end;

{ TAtlasBarDockPlace }

class function TAtlasBarDockPlace.None: TAtlasBarDockPlace;
begin
  Result := Create(TAtlasBarSide.Top, -1);
end;

class function TAtlasBarDockPlace.Create(ASide: TAtlasBarSide; AOrder: Integer): TAtlasBarDockPlace;
begin
  Result := Default(TAtlasBarDockPlace);
  Result.Side := ASide;
  Result.Order := AOrder;
end;

function TAtlasBarDockPlace.Docked: Boolean;
begin
  Result := Order >= 0;
end;

{ TAtlasBarDockItem }

class function TAtlasBarDockItem.Create(AOwn: Boolean; AOrder, ATop, AHeight: Integer): TAtlasBarDockItem;
begin
  Result := Default(TAtlasBarDockItem);
  Result.Own := AOwn;
  Result.Order := AOrder;
  Result.Top := ATop;
  Result.Height := AHeight;
end;

{ TAtlasBarDock }

class function TAtlasBarDock.Ordered(ASide: TAtlasBarSide; const AItems: TArray<TAtlasBarDockItem>): Boolean;
var
  mOwn: TArray<Integer>;
  mIndex, mKey: Integer;
begin
  mOwn := OwnByOrder(AItems);
  Result := True;
  for mIndex := 1 to High(mOwn) do
  begin
    Result := Result and Farther(ASide, Key(ASide, AItems[mOwn[mIndex]]), Key(ASide, AItems[mOwn[mIndex - 1]]));
  end;
  if not Result or (Length(mOwn) = 0) then
  begin
    Exit;
  end;
  // Die vom Editor fernste eigene Leiste steht noch vor jedem fremden Steuerelement.
  mKey := Key(ASide, AItems[mOwn[High(mOwn)]]);
  for mIndex := 0 to High(AItems) do
  begin
    Result := Result and (AItems[mIndex].Own or Farther(ASide, Key(ASide, AItems[mIndex]), mKey));
  end;
end;

class function TAtlasBarDock.Tops(ASide: TAtlasBarSide; const AItems: TArray<TAtlasBarDockItem>;
  AClientHeight: Integer): TArray<Integer>;
var
  mOwn: TArray<Integer>;
  mIndex, mLimit, mCount: Integer;
  mHasForeign: Boolean;
begin
  SetLength(Result, Length(AItems));
  mHasForeign := False;
  mLimit := 0;
  for mIndex := 0 to High(AItems) do
  begin
    Result[mIndex] := AItems[mIndex].Top;
    if AItems[mIndex].Own then
    begin
      Continue;
    end;
    // Grenze: oben das unterste fremde Top, unten die oberste fremde Unterkante.
    if not mHasForeign then
    begin
      mLimit := Key(ASide, AItems[mIndex]);
    end
    else if ASide = TAtlasBarSide.Top then
    begin
      mLimit := Max(mLimit, Key(ASide, AItems[mIndex]));
    end
    else
    begin
      mLimit := Min(mLimit, Key(ASide, AItems[mIndex]));
    end;
    mHasForeign := True;
  end;
  mOwn := OwnByOrder(AItems);
  mCount := Length(mOwn);
  if not mHasForeign then
  begin
    // Ohne fremde: oben vor 0, unten hinter die Höhe des Eltern-Steuerelements.
    mLimit := -1;
    if ASide = TAtlasBarSide.Bottom then
    begin
      mLimit := AClientHeight + mCount + 1;
    end;
  end;
  for mIndex := 0 to mCount - 1 do
  begin
    if ASide = TAtlasBarSide.Top then
    begin
      // Fernste zuerst direkt hinter die Grenze, die nächste am Editor zuletzt.
      Result[mOwn[mIndex]] := mLimit + mCount - mIndex;
    end
    else
    begin
      // Unterkante knapp über der Grenze, nach Order steigend.
      Result[mOwn[mIndex]] := mLimit - (mCount - mIndex) - AItems[mOwn[mIndex]].Height;
    end;
  end;
end;

end.
