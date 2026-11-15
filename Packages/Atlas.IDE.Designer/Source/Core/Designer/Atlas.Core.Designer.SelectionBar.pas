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
// - Due: ob die Leiste jetzt stehen darf (Fokus, Modus, Verzögerung);
//   TAtlasBarTracking verfolgt dafür Namen und Grenzen der Auswahl.
// - TAtlasBarItems: Eigenschaft, Typ, Element und Beschriftung je Knopf.
// - TAtlasBarHistory: Schritte zum Rückgängigmachen je Formulardatei.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasBarItem = (FontSmaller, FontSize, FontLarger, Bold, Italic, FontColor, Enabled, Visible, ParentFont,
    ParentColor, AnchorLeft, AnchorTop, AnchorRight, AnchorBottom, SameWidth, SameHeight, AlignLeft, AlignCenter,
    AlignRight, Transfer, FitText);
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
    cModeShortcut = 'shortcut';
    cMinFontSize = 1;
    cMaxFontSize = 1638;
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
    /// <summary>Menge mit (AOn) oder ohne das Element, als „[a,b]“; Reihenfolge bleibt, ein neues Element
    /// kommt ans Ende.</summary>
    class function SetWith(const ASet, AElement: string; AOn: Boolean): string; static;
    /// <summary>Wert nach dem Klick auf einen Umschalter: an außer bei On.</summary>
    class function Target(AState: TAtlasBarState): Boolean; static;
    /// <summary>Schriftgröße um AStep Punkte, zwischen cMinFontSize und cMaxFontSize.</summary>
    class function NextFontSize(ASize, AStep: Integer): Integer; static;
    /// <summary>Leiste der Größe ASize über ASelection (Abstand AGap), sonst darunter; waagerecht in AArea.
    /// Leeres Rechteck, wenn die Auswahl nicht in AArea liegt.</summary>
    class function Place(const ASelection: TRect; const ASize: TSize; const AArea: TRect;
      AGap: Integer): TRect; static;
    /// <summary>Modus designer.selectionBar.mode = shortcut (nur auf Tastendruck)?</summary>
    class function IsShortcut(const AMode: string): Boolean; static;
    /// <summary>Darf die Leiste jetzt stehen? Nur mit Fokus im Designer; im Modus shortcut erst nach dem
    /// Tastendruck, sonst erst ADelayMs nach ASince.</summary>
    class function Due(AFocused, AShortcut, ARequested: Boolean; ANow, ASince: UInt64;
      ADelayMs: Integer): Boolean; static;
    /// <summary>Eingabe im Dialog „Schriftgröße“: ganze Zahl zwischen cMinFontSize und cMaxFontSize.</summary>
    class function TryFontSize(const AText: string; out ASize: Integer): Boolean; static;
    /// <summary>Farben des Farbmenüs: zuerst die im Formular verwendeten (AUsed), dann die üblichen
    /// (AStandard), ohne Doppelte. AUsedCount: Zahl der verwendeten vorn (Trennstrich danach).</summary>
    class function ColorChoices(const AUsed, AStandard: TArray<Integer>; out AUsedCount: Integer): TArray<Integer>;
      static;
  end;

  /// <summary>Feste Daten je Knopf: Eigenschaft (Pfad über RTTI), verlangter Typ, Element bzw. Wert und
  /// Beschriftung; Zustand des Knopfs aus den Werten der Auswahl.</summary>
  TAtlasBarItems = class
  public
    /// <summary>Pfad der Eigenschaft wie Font.Size; leer bei transfer.</summary>
    class function PathOf(AItem: TAtlasBarItem): string; static;
    /// <summary>Verlangter Typ der Eigenschaft; leer = jeder (TCheckBox.Alignment ist kein TAlignment).</summary>
    class function PropTypeOf(AItem: TAtlasBarItem): string; static;
    /// <summary>Element der Menge bzw. eingeschalteter Wert der Umschalter.</summary>
    class function ElementOf(AItem: TAtlasBarItem): string; static;
    /// <summary>Beschriftung des Knopfs.</summary>
    class function TextOf(AItem: TAtlasBarItem): string; static;
    /// <summary>Zustand des Knopfs: Mengen und Umschalter aus den Werten, alle übrigen Off.</summary>
    class function StateOf(AItem: TAtlasBarItem; const AProps: TArray<TAtlasBarProp>): TAtlasBarState; static;
    /// <summary>Argument des Tooltips: Name des Umschalters, Element des Ankers oder Name des ersten
    /// Steuerelements (gleiche Breite/Höhe wie AFirstName); sonst leer.</summary>
    class function HintArgument(AItem: TAtlasBarItem; const AFirstName: string): string; static;
  end;

  /// <summary>Verfolgte Auswahl: Schlüssel aus Namen und Grenzen, seit wann sie steht und ob die Leiste
  /// angefordert ist.</summary>
  TAtlasBarTracking = record
    Names: string;
    Bounds: string;
    Since: UInt64;
    Requested: Boolean;
    /// <summary>Neue Auswahl (ANames anders): Verzögerung von vorn und Anforderung weg. Nur andere
    /// Grenzen (Ziehen): Verzögerung von vorn.</summary>
    procedure Update(const ANames, ABounds: string; ANow: UInt64);
    /// <summary>Keine Auswahl mehr: beim nächsten Update gilt jede Auswahl als neu.</summary>
    procedure Clear;
  end;

  /// <summary>Alter Wert einer Eigenschaft (Pfad wie Font.Size) einer Komponente.</summary>
  TAtlasBarChange = record
    Name: string;
    Path: string;
    Value: string;
    class function Create(const AName, APath, AValue: string): TAtlasBarChange; static;
  end;

  /// <summary>Ein Klick der Leiste: alte Werte je Formulardatei.</summary>
  TAtlasBarStep = record
    FileName: string;
    Changes: TArray<TAtlasBarChange>;
  end;

  /// <summary>Schritte zum Rückgängigmachen, höchstens cMaxSteps (die ältesten fallen weg).</summary>
  TAtlasBarHistory = record
  public const
    cMaxSteps = 50;
  public
    Steps: TArray<TAtlasBarStep>;
    /// <summary>Schritt merken; ohne Änderungen nichts.</summary>
    procedure Push(const AStep: TAtlasBarStep);
    /// <summary>Gehört der letzte Schritt zur Formulardatei (ohne Groß-/Kleinschreibung)?</summary>
    function CanUndo(const AFileName: string): Boolean;
    /// <summary>Letzten Schritt herausnehmen; False ohne Schritt.</summary>
    function Pop(out AStep: TAtlasBarStep): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  cItemKeys: array[TAtlasBarItem] of string = ('fontSmaller', 'fontSize', 'fontLarger', 'bold', 'italic',
    'fontColor', 'enabled', 'visible', 'parentFont', 'parentColor', 'anchorLeft', 'anchorTop', 'anchorRight',
    'anchorBottom', 'sameWidth', 'sameHeight', 'alignLeft', 'alignCenter', 'alignRight', 'transfer',
    'fitText');
  cItemGroups: array[TAtlasBarItem] of Integer = (0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 4, 4);
  cItemPaths: array[TAtlasBarItem] of string = ('Font.Size', 'Font.Size', 'Font.Size', 'Font.Style', 'Font.Style',
    'Font.Color', 'Enabled', 'Visible', 'ParentFont', 'ParentColor', 'Anchors', 'Anchors', 'Anchors', 'Anchors',
    'Width', 'Height', 'Alignment', 'Alignment', 'Alignment', '', 'Width');
  cItemTypes: array[TAtlasBarItem] of string = ('', '', '', '', '', '', 'Boolean', 'Boolean', 'Boolean', 'Boolean',
    'TAnchors', 'TAnchors', 'TAnchors', 'TAnchors', '', '', 'TAlignment', 'TAlignment', 'TAlignment', '', '');
  cItemElements: array[TAtlasBarItem] of string = ('', '', '', 'fsBold', 'fsItalic', '', 'True', 'True', 'True',
    'True', 'akLeft', 'akTop', 'akRight', 'akBottom', '', '', 'taLeftJustify', 'taCenter', 'taRightJustify', '',
    '');
  cItemTexts: array[TAtlasBarItem] of string = ('A−', '–', 'A+', '', '', 'A', 'Enabled', 'Visible', 'ParentFont',
    'ParentColor', 'L', 'T', 'R', 'B', 'W=', 'H=', '◧', '◫', '◨', '⇉', 'Aa↔');

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
  for mItem := Low(TAtlasBarItem) to TAtlasBarItem.Transfer do
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

class function TAtlasSelectionBar.IsShortcut(const AMode: string): Boolean;
begin
  Result := SameText(AMode, cModeShortcut);
end;

class function TAtlasSelectionBar.Due(AFocused, AShortcut, ARequested: Boolean; ANow, ASince: UInt64;
  ADelayMs: Integer): Boolean;
begin
  if not AFocused then
  begin
    Exit(False);
  end;
  if AShortcut then
  begin
    Exit(ARequested);
  end;
  Result := (ANow < ASince) or (ANow - ASince >= UInt64(Max(ADelayMs, 0)));
end;

class function TAtlasSelectionBar.TryFontSize(const AText: string; out ASize: Integer): Boolean;
begin
  Result := TryStrToInt(Trim(AText), ASize) and (ASize >= cMinFontSize) and (ASize <= cMaxFontSize);
end;

procedure AddColor(var AColors: TArray<Integer>; AColor: Integer);
var
  mOther: Integer;
begin
  for mOther in AColors do
  begin
    if mOther = AColor then
    begin
      Exit;
    end;
  end;
  SetLength(AColors, Length(AColors) + 1);
  AColors[High(AColors)] := AColor;
end;

class function TAtlasSelectionBar.ColorChoices(const AUsed, AStandard: TArray<Integer>;
  out AUsedCount: Integer): TArray<Integer>;
var
  mColor: Integer;
begin
  Result := nil;
  for mColor in AUsed do
  begin
    AddColor(Result, mColor);
  end;
  AUsedCount := Length(Result);
  for mColor in AStandard do
  begin
    AddColor(Result, mColor);
  end;
end;

{ TAtlasBarItems }

class function TAtlasBarItems.PathOf(AItem: TAtlasBarItem): string;
begin
  Result := cItemPaths[AItem];
end;

class function TAtlasBarItems.PropTypeOf(AItem: TAtlasBarItem): string;
begin
  Result := cItemTypes[AItem];
end;

class function TAtlasBarItems.ElementOf(AItem: TAtlasBarItem): string;
begin
  Result := cItemElements[AItem];
end;

class function TAtlasBarItems.TextOf(AItem: TAtlasBarItem): string;
begin
  Result := cItemTexts[AItem];
end;

class function TAtlasBarItems.StateOf(AItem: TAtlasBarItem; const AProps: TArray<TAtlasBarProp>): TAtlasBarState;
begin
  case AItem of
    TAtlasBarItem.Bold, TAtlasBarItem.Italic, TAtlasBarItem.AnchorLeft..TAtlasBarItem.AnchorBottom:
      Result := TAtlasSelectionBar.SetFlag(AProps, cItemElements[AItem]);
    TAtlasBarItem.Enabled..TAtlasBarItem.ParentColor, TAtlasBarItem.AlignLeft..TAtlasBarItem.AlignRight:
      Result := TAtlasSelectionBar.Flag(AProps, cItemElements[AItem]);
  else
    Result := TAtlasBarState.Off;
  end;
end;

class function TAtlasBarItems.HintArgument(AItem: TAtlasBarItem; const AFirstName: string): string;
begin
  case AItem of
    TAtlasBarItem.Enabled..TAtlasBarItem.ParentColor:
      Result := cItemTexts[AItem];
    TAtlasBarItem.AnchorLeft..TAtlasBarItem.AnchorBottom:
      Result := cItemElements[AItem];
    TAtlasBarItem.SameWidth, TAtlasBarItem.SameHeight:
      Result := AFirstName;
  else
    Result := '';
  end;
end;

{ TAtlasBarTracking }

procedure TAtlasBarTracking.Update(const ANames, ABounds: string; ANow: UInt64);
begin
  if ANames <> Names then
  begin
    Names := ANames;
    Bounds := ABounds;
    Since := ANow;
    Requested := False;
  end
  else if ABounds <> Bounds then
  begin
    Bounds := ABounds;
    Since := ANow;
  end;
end;

procedure TAtlasBarTracking.Clear;
begin
  Names := '';
end;

{ TAtlasBarChange }

class function TAtlasBarChange.Create(const AName, APath, AValue: string): TAtlasBarChange;
begin
  Result.Name := AName;
  Result.Path := APath;
  Result.Value := AValue;
end;

{ TAtlasBarHistory }

procedure TAtlasBarHistory.Push(const AStep: TAtlasBarStep);
begin
  if Length(AStep.Changes) = 0 then
  begin
    Exit;
  end;
  SetLength(Steps, Length(Steps) + 1);
  Steps[High(Steps)] := AStep;
  if Length(Steps) > cMaxSteps then
  begin
    Delete(Steps, 0, Length(Steps) - cMaxSteps);
  end;
end;

function TAtlasBarHistory.CanUndo(const AFileName: string): Boolean;
begin
  Result := (Length(Steps) > 0) and SameText(Steps[High(Steps)].FileName, AFileName);
end;

function TAtlasBarHistory.Pop(out AStep: TAtlasBarStep): Boolean;
begin
  Result := Length(Steps) > 0;
  if Result then
  begin
    AStep := Steps[High(Steps)];
    SetLength(Steps, Length(Steps) - 1);
  end;
end;

end.
