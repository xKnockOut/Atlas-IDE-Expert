unit Atlas.Core.Designer.SelectionBar;

// Schnellleiste über einer Mehrfachauswahl im Designer (#735), ohne VCL und
// Windows:
// - Knöpfe (TAtlasBarItem) mit Schlüsseln für designer.selectionBar.items;
//   ParseItems liest Auswahl und Reihenfolge, Unbekanntes fällt weg.
// - Combine fasst die Werte einer Eigenschaft über alle markierten
//   Komponenten zusammen: gemeinsam, gemischt oder bei keiner vorhanden, mit
//   der Zahl der Komponenten, die sie haben („für 3 von 4“).
// - Flag/SetFlag ergeben den Zustand eines Umschalters (an, aus, gemischt)
//   für einen Wert bzw. ein Element einer Menge (Font.Style, Anchors);
//   SetWith schaltet ein Element in einer Menge.
// - NextFontSize: Schriftgröße in Punktschritten.
// - Place: Lage der Leiste über (sonst unter) dem umschließenden Rechteck.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasBarItem = (FontSmaller, FontSize, FontLarger, Bold, Italic, FontColor, Enabled, Visible, ParentFont,
    ParentColor, AnchorLeft, AnchorTop, AnchorRight, AnchorBottom, SameWidth, SameHeight, AlignLeft, AlignCenter,
    AlignRight, FitText);
  /// <summary>None: keine markierte Komponente hat die Eigenschaft.</summary>
  TAtlasBarState = (None, Off, On, Mixed);
{$SCOPEDENUMS OFF}

  /// <summary>Wert einer Eigenschaft an einer Komponente; Present = False: hat sie nicht.</summary>
  TAtlasBarProp = record
    Present: Boolean;
    Value: string;
    class function Create(const AValue: string): TAtlasBarProp; static;
    class function Missing: TAtlasBarProp; static;
  end;

  TAtlasBarValue = record
    /// <summary>None (keine hat sie), On (alle gleich) oder Mixed.</summary>
    State: TAtlasBarState;
    /// <summary>Gemeinsamer Wert; leer bei Mixed oder None.</summary>
    Value: string;
    /// <summary>Komponenten mit der Eigenschaft.</summary>
    Count: Integer;
    /// <summary>Alle Komponenten.</summary>
    Total: Integer;
    /// <summary>Haben nicht alle die Eigenschaft (Tooltip „für Count von Total“)?</summary>
    function Partial: Boolean;
  end;

  TAtlasSelectionBar = class
  public const
    cModeAuto = 'auto';
    cModeShortcut = 'shortcut';
    cMinFontSize = 1;
    cMaxFontSize = 1638;
    cMaxDelay = 5000;
  public
    /// <summary>Schlüssel des Knopfs in designer.selectionBar.items.</summary>
    class function KeyOf(AItem: TAtlasBarItem): string; static;
    /// <summary>Knopf zum Schlüssel; False bei Unbekanntem.</summary>
    class function TryItemOf(const AKey: string; out AItem: TAtlasBarItem): Boolean; static;
    /// <summary>Vorgabe für items: alle außer den optionalen (FitText).</summary>
    class function DefaultItems: string; static;
    /// <summary>Knöpfe aus „fontSmaller, bold, …“ in dieser Reihenfolge, ohne Doppelte und Unbekanntes.</summary>
    class function ParseItems(const AText: string): TArray<TAtlasBarItem>; static;
    /// <summary>Gruppe des Knopfs (Schrift, Zustand, Layout, Text, Weitere): Trennstrich bei Wechsel.</summary>
    class function GroupOf(AItem: TAtlasBarItem): Integer; static;
    /// <summary>Werte zusammenfassen (Vergleich ohne Groß-/Kleinschreibung).</summary>
    class function Combine(const AProps: TArray<TAtlasBarProp>): TAtlasBarValue; static;
    /// <summary>Umschalter: On, wenn alle mit der Eigenschaft AOn haben, Off, wenn keine, sonst Mixed.</summary>
    class function Flag(const AProps: TArray<TAtlasBarProp>; const AOn: string): TAtlasBarState; static;
    /// <summary>Wie Flag für ein Element einer Menge („[fsBold,fsItalic]“).</summary>
    class function SetFlag(const AProps: TArray<TAtlasBarProp>; const AElement: string): TAtlasBarState; static;
    /// <summary>Enthält die Menge („[a,b]“ oder „a,b“) das Element?</summary>
    class function SetHas(const ASet, AElement: string): Boolean; static;
    /// <summary>Menge mit (AOn) oder ohne das Element, als „[a,b]“; Reihenfolge bleibt, ein neues Element kommt ans Ende.</summary>
    class function SetWith(const ASet, AElement: string; AOn: Boolean): string; static;
    /// <summary>Wert nach dem Klick auf einen Umschalter: an außer bei On.</summary>
    class function Target(AState: TAtlasBarState): Boolean; static;
    /// <summary>Schriftgröße um AStep Punkte, zwischen cMinFontSize und cMaxFontSize.</summary>
    class function NextFontSize(ASize, AStep: Integer): Integer; static;
    /// <summary>Leiste der Größe ASize über ASelection (Abstand AGap), sonst darunter; waagerecht in AArea.
    /// Leeres Rechteck, wenn die Auswahl nicht in AArea liegt.</summary>
    class function Place(const ASelection: TRect; const ASize: TSize; const AArea: TRect;
      AGap: Integer): TRect; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  cItemKeys: array[TAtlasBarItem] of string = ('fontSmaller', 'fontSize', 'fontLarger', 'bold', 'italic',
    'fontColor', 'enabled', 'visible', 'parentFont', 'parentColor', 'anchorLeft', 'anchorTop', 'anchorRight',
    'anchorBottom', 'sameWidth', 'sameHeight', 'alignLeft', 'alignCenter', 'alignRight', 'fitText');
  cItemGroups: array[TAtlasBarItem] of Integer = (0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 4);

{ TAtlasBarProp }

class function TAtlasBarProp.Create(const AValue: string): TAtlasBarProp;
begin
  Result.Present := True;
  Result.Value := AValue;
end;

class function TAtlasBarProp.Missing: TAtlasBarProp;
begin
  Result.Present := False;
  Result.Value := '';
end;

{ TAtlasBarValue }

function TAtlasBarValue.Partial: Boolean;
begin
  Result := (Count > 0) and (Count < Total);
end;

{ TAtlasSelectionBar }

class function TAtlasSelectionBar.KeyOf(AItem: TAtlasBarItem): string;
begin
  Result := cItemKeys[AItem];
end;

class function TAtlasSelectionBar.TryItemOf(const AKey: string; out AItem: TAtlasBarItem): Boolean;
var
  mItem: TAtlasBarItem;
begin
  for mItem := Low(TAtlasBarItem) to High(TAtlasBarItem) do
  begin
    if SameText(cItemKeys[mItem], Trim(AKey)) then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  AItem := TAtlasBarItem.FontSmaller;
  Result := False;
end;

class function TAtlasSelectionBar.DefaultItems: string;
var
  mItem: TAtlasBarItem;
begin
  Result := '';
  for mItem := Low(TAtlasBarItem) to TAtlasBarItem.AlignRight do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + cItemKeys[mItem];
  end;
end;

class function TAtlasSelectionBar.ParseItems(const AText: string): TArray<TAtlasBarItem>;
var
  mPart: string;
  mItem, mSeen: TAtlasBarItem;
  mKnown: Boolean;
begin
  Result := nil;
  for mPart in AText.Split([',', ';', ' ']) do
  begin
    if not TryItemOf(mPart, mItem) then
    begin
      Continue;
    end;
    mKnown := False;
    for mSeen in Result do
    begin
      mKnown := mKnown or (mSeen = mItem);
    end;
    if not mKnown then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasSelectionBar.GroupOf(AItem: TAtlasBarItem): Integer;
begin
  Result := cItemGroups[AItem];
end;

class function TAtlasSelectionBar.Combine(const AProps: TArray<TAtlasBarProp>): TAtlasBarValue;
var
  mProp: TAtlasBarProp;
begin
  Result.State := TAtlasBarState.None;
  Result.Value := '';
  Result.Count := 0;
  Result.Total := Length(AProps);
  for mProp in AProps do
  begin
    if not mProp.Present then
    begin
      Continue;
    end;
    Inc(Result.Count);
    if Result.Count = 1 then
    begin
      Result.State := TAtlasBarState.On;
      Result.Value := mProp.Value;
    end
    else if (Result.State = TAtlasBarState.On) and not SameText(Result.Value, mProp.Value) then
    begin
      Result.State := TAtlasBarState.Mixed;
      Result.Value := '';
    end;
  end;
end;

class function TAtlasSelectionBar.Flag(const AProps: TArray<TAtlasBarProp>; const AOn: string): TAtlasBarState;
var
  mProp: TAtlasBarProp;
  mOn, mOff: Integer;
begin
  mOn := 0;
  mOff := 0;
  for mProp in AProps do
  begin
    if mProp.Present and SameText(mProp.Value, AOn) then
    begin
      Inc(mOn);
    end
    else if mProp.Present then
    begin
      Inc(mOff);
    end;
  end;
  if mOn + mOff = 0 then
  begin
    Result := TAtlasBarState.None;
  end
  else if mOff = 0 then
  begin
    Result := TAtlasBarState.On;
  end
  else if mOn = 0 then
  begin
    Result := TAtlasBarState.Off;
  end
  else
  begin
    Result := TAtlasBarState.Mixed;
  end;
end;

class function TAtlasSelectionBar.SetFlag(const AProps: TArray<TAtlasBarProp>;
  const AElement: string): TAtlasBarState;
var
  mFlags: TArray<TAtlasBarProp>;
  mIndex: Integer;
begin
  SetLength(mFlags, Length(AProps));
  for mIndex := 0 to High(AProps) do
  begin
    mFlags[mIndex] := AProps[mIndex];
    if AProps[mIndex].Present then
    begin
      mFlags[mIndex].Value := BoolToStr(SetHas(AProps[mIndex].Value, AElement), True);
    end;
  end;
  Result := Flag(mFlags, BoolToStr(True, True));
end;

function SetElements(const ASet: string): TArray<string>;
var
  mPart: string;
begin
  Result := nil;
  for mPart in ASet.Trim.TrimLeft(['[']).TrimRight([']']).Split([',']) do
  begin
    if Trim(mPart) <> '' then
    begin
      Result := Result + [Trim(mPart)];
    end;
  end;
end;

class function TAtlasSelectionBar.SetHas(const ASet, AElement: string): Boolean;
var
  mPart: string;
begin
  for mPart in SetElements(ASet) do
  begin
    if SameText(mPart, AElement) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasSelectionBar.SetWith(const ASet, AElement: string; AOn: Boolean): string;
var
  mParts: TArray<string>;
  mPart: string;
  mFound: Boolean;
begin
  mParts := nil;
  mFound := False;
  for mPart in SetElements(ASet) do
  begin
    if not SameText(mPart, AElement) then
    begin
      mParts := mParts + [mPart];
    end
    else if AOn and not mFound then
    begin
      mParts := mParts + [mPart];
      mFound := True;
    end;
  end;
  if AOn and not mFound then
  begin
    mParts := mParts + [AElement];
  end;
  Result := '[' + string.Join(',', mParts) + ']';
end;

class function TAtlasSelectionBar.Target(AState: TAtlasBarState): Boolean;
begin
  Result := AState <> TAtlasBarState.On;
end;

class function TAtlasSelectionBar.NextFontSize(ASize, AStep: Integer): Integer;
begin
  Result := EnsureRange(Max(ASize, cMinFontSize) + AStep, cMinFontSize, cMaxFontSize);
end;

class function TAtlasSelectionBar.Place(const ASelection: TRect; const ASize: TSize; const AArea: TRect;
  AGap: Integer): TRect;
var
  mLeft, mTop: Integer;
begin
  if (ASelection.Right <= AArea.Left) or (ASelection.Left >= AArea.Right) or
    (ASelection.Bottom <= AArea.Top) or (ASelection.Top >= AArea.Bottom) then
  begin
    Exit(Rect(0, 0, 0, 0));
  end;
  mLeft := EnsureRange(ASelection.Left, AArea.Left, Max(AArea.Left, AArea.Right - ASize.cx));
  mTop := ASelection.Top - AGap - ASize.cy;
  if mTop < AArea.Top then
  begin
    mTop := Min(ASelection.Bottom + AGap, Max(AArea.Top, AArea.Bottom - ASize.cy));
  end;
  Result := Rect(mLeft, mTop, mLeft + ASize.cx, mTop + ASize.cy);
end;

end.
