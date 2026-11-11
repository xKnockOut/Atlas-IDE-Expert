unit Atlas.IDE.Designer.SelectionBar;

// Schnellleiste über einer Mehrfachauswahl im Designer (#735,
// designer.selectionBar) in der IDE:
// - Ab zwei markierten Steuerelementen erscheint nach designer.selectionBar.
//   delayMs über dem umschließenden Rechteck (unten, wenn oben kein Platz
//   ist) ein Fenster ohne Fokus (TAtlasSelectionBarWindow). Mit mode =
//   shortcut nur auf die Taste designer.selectionBar.key.
// - Ausgeblendet, solange die linke Maustaste über dem Designer gedrückt ist
//   oder sich Lage und Größe der Auswahl ändern (Ziehen), ohne Fokus im
//   Designer (Objektinspektor) und mit dem Knopf in der Designer-Leiste.
// - Knöpfe nach designer.selectionBar.items. Werte liest und schreibt die
//   Leiste über RTTI (Font.Size, Font.Style, Font.Color, Enabled, Visible,
//   ParentFont, ParentColor, Anchors, Width, Height, Alignment vom Typ
//   TAlignment); gemeinsame und gemischte Werte bestimmt TAtlasSelectionBar.
//   Ein Knopf wirkt nur auf die Steuerelemente mit der Eigenschaft.
// - Jeder Klick ist ein Schritt: Die alten Werte merkt sich die Leiste je
//   Formulardatei, „Letzte Änderung der Schnellleiste rückgängig“ im Menü
//   am Pfeil nimmt sie schrittweise zurück.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Menus,
  Atlas.Core.Designer.SelectionBar,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.SelectionBar,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Designer.PropertyPainter;

type
  TAtlasIdeSelectionBar = class;

  /// <summary>Taste zum Einblenden im Modus shortcut, solange der Designer den Fokus hat.</summary>
  TAtlasSelectionBarKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdeSelectionBar;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  /// <summary>Alter Wert einer Eigenschaft (Pfad wie Font.Size) einer Komponente.</summary>
  TAtlasBarChange = record
    Name: string;
    Path: string;
    Value: string;
  end;

  TAtlasBarStep = record
    FileName: string;
    Changes: TArray<TAtlasBarChange>;
  end;

  TAtlasIdeSelectionBar = class
  public const
    cId = 'selectionBar';
  private
    FOnMessage: TProc<string>;
    FPainter: TAtlasIdePropertyPainter;
    FActive: Boolean;
    FWindow: TAtlasSelectionBarWindow;
    FMenu: TPopupMenu;
    FColorMenu: TPopupMenu;
    FKeys: TAtlasSelectionBarKeys;
    FSteps: TArray<TAtlasBarStep>;
    FRoot: TComponent;
    FControls: TArray<TControl>;
    FItems: TArray<TAtlasBarItem>;
    FNames: string;
    FBounds: string;
    FSince: UInt64;
    FRequested: Boolean;
    procedure Say(const AText: string);
    procedure EnsureWindow;
    function FindControls: Boolean;
    function Wanted: Boolean;
    function SelectionBounds(out AScreen, AArea: TRect): Boolean;
    function Props(const APath, AType: string): TArray<TAtlasBarProp>;
    function StateOf(AItem: TAtlasBarItem; const AProps: TArray<TAtlasBarProp>): TAtlasBarState;
    function ButtonOf(AItem: TAtlasBarItem): TAtlasBarButton;
    /// <summary>Format-Pinsel übertragen: grau, solange nichts aufgenommen ist.</summary>
    function TransferButton: TAtlasBarButton;
    procedure ShowBar;
    /// <summary>Nach einer eigenen Änderung: Auswahl neu lesen und die Leiste gleich wieder zeigen.</summary>
    procedure Refresh;
    procedure Click(AIndex: Integer; const AAt: TPoint);
    procedure Run(AItem: TAtlasBarItem; const AAt: TPoint);
    /// <summary>Wert an allen Steuerelementen mit der Eigenschaft setzen; AValueOf: neuer Wert aus dem alten.</summary>
    procedure Change(const APath, AType: string; const AValueOf: TFunc<string, string>; const ALabel: string);
    procedure ChangeTo(const APath, AType, AValue, ALabel: string);
    procedure ToggleFlag(AItem: TAtlasBarItem; const ALabel: string);
    procedure ToggleSet(AItem: TAtlasBarItem; const ALabel: string);
    procedure AskFontSize;
    procedure PopupColors(const AAt: TPoint);
    procedure ColorClick(Sender: TObject);
    procedure MenuClick(Sender: TObject);
    function CanUndo: Boolean;
    procedure Undo;
    procedure UpdateKeys;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht; APainter: Format-Pinsel des Menüs „Anordnen“ (#726)
    /// für den Knopf transfer, gehört dem Aufrufer.</summary>
    constructor Create(const AOnMessage: TProc<string>; APainter: TAtlasIdePropertyPainter);
    destructor Destroy; override;
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Knopf der Designer-Leiste: gedrückt, solange die Schnellleiste erscheinen darf.</summary>
    function Button: TAtlasDesignerButton;
    /// <summary>Klick auf das Symbol: Schnellleiste ein- oder ausschalten.</summary>
    procedure Toggle;
    /// <summary>Menü am Pfeil an APoint (Bildschirm).</summary>
    procedure Popup(const APoint: TPoint);
    /// <summary>Taste im Modus shortcut: Leiste sofort zeigen.</summary>
    procedure Request;
    /// <summary>Takt der Leiste: Auswahl verfolgen, ein- und ausblenden.</summary>
    procedure Tick;
    procedure Hide;
    procedure ApplyTheme;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.TypInfo,
  System.Variants,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.ToolStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.FitText,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  cKeyPriority = 45;
  cGap = 6;
  /// <summary>Rand um das Formular, in dem die Leiste noch stehen darf.</summary>
  cAreaMargin = 4000;
  cMaxSteps = 50;
  cMenuShow = 0;
  cMenuUndo = 1;
  cColorMore = -1;
  cStandardColors: array[0..9] of TColor = (clWindowText, clBlack, clGrayText, clGray, clMaroon, clRed, clGreen,
    clNavy, clBlue, clHighlight);
  /// <summary>Eigenschaft je Knopf (Pfad über RTTI).</summary>
  cPaths: array[TAtlasBarItem] of string = ('Font.Size', 'Font.Size', 'Font.Size', 'Font.Style', 'Font.Style',
    'Font.Color', 'Enabled', 'Visible', 'ParentFont', 'ParentColor', 'Anchors', 'Anchors', 'Anchors', 'Anchors',
    'Width', 'Height', 'Alignment', 'Alignment', 'Alignment', '', 'Width');
  /// <summary>Verlangter Typ der Eigenschaft; leer = jeder (TCheckBox.Alignment ist kein TAlignment).</summary>
  cTypes: array[TAtlasBarItem] of string = ('', '', '', '', '', '', 'Boolean', 'Boolean', 'Boolean', 'Boolean',
    'TAnchors', 'TAnchors', 'TAnchors', 'TAnchors', '', '', 'TAlignment', 'TAlignment', 'TAlignment', '', '');
  /// <summary>Element der Menge bzw. eingeschalteter Wert der Umschalter.</summary>
  cElements: array[TAtlasBarItem] of string = ('', '', '', 'fsBold', 'fsItalic', '', 'True', 'True', 'True', 'True',
    'akLeft', 'akTop', 'akRight', 'akBottom', '', '', 'taLeftJustify', 'taCenter', 'taRightJustify', '',
    '');
  cTexts: array[TAtlasBarItem] of string = ('A−', '–', 'A+', '', '', 'A', 'Enabled', 'Visible', 'ParentFont',
    'ParentColor', 'L', 'T', 'R', 'B', 'W=', 'H=', '◧', '◫', '◨', '⇉', 'Aa↔');
  cHints: array[TAtlasBarItem] of TAtlasDesignerToolTextId = (TAtlasDesignerToolTextId.BarFontSmaller,
    TAtlasDesignerToolTextId.BarFontSize, TAtlasDesignerToolTextId.BarFontLarger, TAtlasDesignerToolTextId.BarBold,
    TAtlasDesignerToolTextId.BarItalic, TAtlasDesignerToolTextId.BarFontColor, TAtlasDesignerToolTextId.BarFlag,
    TAtlasDesignerToolTextId.BarFlag, TAtlasDesignerToolTextId.BarFlag, TAtlasDesignerToolTextId.BarFlag,
    TAtlasDesignerToolTextId.BarAnchor, TAtlasDesignerToolTextId.BarAnchor, TAtlasDesignerToolTextId.BarAnchor,
    TAtlasDesignerToolTextId.BarAnchor, TAtlasDesignerToolTextId.BarSameWidth, TAtlasDesignerToolTextId.BarSameHeight,
    TAtlasDesignerToolTextId.BarAlignLeft, TAtlasDesignerToolTextId.BarAlignCenter,
    TAtlasDesignerToolTextId.BarAlignRight, TAtlasDesignerToolTextId.BarTransfer, TAtlasDesignerToolTextId.BarFitText);

function ResolveProp(AObject: TObject; const APath: string; out ATarget: TObject; out AInfo: PPropInfo): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  ATarget := AObject;
  AInfo := nil;
  mParts := APath.Split(['.']);
  for mIndex := 0 to High(mParts) do
  begin
    if ATarget = nil then
    begin
      Exit(False);
    end;
    AInfo := GetPropInfo(ATarget, mParts[mIndex]);
    if AInfo = nil then
    begin
      Exit(False);
    end;
    if mIndex < High(mParts) then
    begin
      if AInfo^.PropType^^.Kind <> tkClass then
      begin
        Exit(False);
      end;
      ATarget := GetObjectProp(ATarget, AInfo);
    end;
  end;
  Result := (ATarget <> nil) and (AInfo <> nil);
end;

/// <summary>Wert als Text; False ohne die Eigenschaft oder mit anderem Typ (AType leer = jeder).</summary>
function ReadProp(AObject: TObject; const APath, AType: string; out AValue: string): Boolean;
var
  mTarget: TObject;
  mInfo: PPropInfo;
begin
  AValue := '';
  Result := ResolveProp(AObject, APath, mTarget, mInfo) and
    ((AType = '') or SameText(string(mInfo^.PropType^^.Name), AType));
  if Result then
  begin
    AValue := VarToStr(GetPropValue(mTarget, mInfo, True));
  end;
end;

procedure WriteProp(AObject: TObject; const APath, AValue: string);
var
  mTarget: TObject;
  mInfo: PPropInfo;
begin
  if ResolveProp(AObject, APath, mTarget, mInfo) then
  begin
    SetPropValue(mTarget, mInfo, AValue);
  end;
end;

procedure SetSwatch(AItem: TMenuItem; AColor: TColor);
var
  mBitmap: TBitmap;
begin
  mBitmap := TBitmap.Create;
  try
    mBitmap.SetSize(14, 14);
    mBitmap.Canvas.Brush.Color := clGray;
    mBitmap.Canvas.FillRect(Rect(0, 0, 14, 14));
    mBitmap.Canvas.Brush.Color := AColor;
    mBitmap.Canvas.FillRect(Rect(1, 1, 13, 13));
    AItem.Bitmap := mBitmap;
  finally
    mBitmap.Free;
  end;
end;

procedure AddColor(var AColors: TArray<TColor>; AColor: TColor);
var
  mOther: TColor;
begin
  for mOther in AColors do
  begin
    if mOther = AColor then
    begin
      Exit;
    end;
  end;
  AColors := AColors + [AColor];
end;

{ TAtlasSelectionBarKeys }

function TAtlasSelectionBarKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.DesignerSelectionBar and (FOwner <> nil) and FOwner.FActive and
    SameText(mSettings.DesignerSelectionBarMode, TAtlasSelectionBar.cModeShortcut) and
    (mSettings.DesignerSelectionBarKey <> 0) and
    (ShortCut(AKey, AShift) = TShortCut(mSettings.DesignerSelectionBarKey)) and TAtlasDesignerAccess.Focused;
end;

procedure TAtlasSelectionBarKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeSelectionBar;
begin
  mOwner := FOwner;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      mOwner.Request;
    end);
end;

{ TAtlasIdeSelectionBar }

constructor TAtlasIdeSelectionBar.Create(const AOnMessage: TProc<string>; APainter: TAtlasIdePropertyPainter);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FPainter := APainter;
  FActive := True;
  FMenu := TPopupMenu.Create(nil);
  FColorMenu := TPopupMenu.Create(nil);
  FKeys := TAtlasSelectionBarKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
end;

destructor TAtlasIdeSelectionBar.Destroy;
begin
  TAtlasKeyHook.Remove(FKeys);
  FKeys.Free;
  FWindow.Free;
  FColorMenu.Free;
  FMenu.Free;
  inherited Destroy;
end;

class function TAtlasIdeSelectionBar.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerSelectionBar;
end;

function TAtlasIdeSelectionBar.Button: TAtlasDesignerButton;
begin
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.SelectionBar,
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarHint));
  Result.Pressed := FActive;
  Result.Menu := True;
end;

procedure TAtlasIdeSelectionBar.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeSelectionBar.EnsureWindow;
var
  mOwner: TAtlasIdeSelectionBar;
begin
  if FWindow <> nil then
  begin
    Exit;
  end;
  mOwner := Self;
  FWindow := TAtlasSelectionBarWindow.CreateBar(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  FWindow.OnClick :=
    procedure(AIndex: Integer; AAt: TPoint)
    var
      mIndex: Integer;
      mAt: TPoint;
    begin
      mIndex := AIndex;
      mAt := AAt;
      TAtlasGuard.Run(TAtlasFeature.DesignerBar,
        procedure
        begin
          mOwner.Click(mIndex, mAt);
        end);
    end;
end;

procedure TAtlasIdeSelectionBar.UpdateKeys;
begin
  if Wanted and SameText(TAtlasIdeSettings.Current.DesignerSelectionBarMode, TAtlasSelectionBar.cModeShortcut) then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
end;

function TAtlasIdeSelectionBar.Wanted: Boolean;
begin
  Result := FActive and TAtlasIdeSettings.Current.DesignerSelectionBar and TAtlasDesignerAccess.Shown;
end;

function TAtlasIdeSelectionBar.FindControls: Boolean;
var
  mEditor: IOTAFormEditor;
  mComponent: TComponent;
  mNames, mBounds: string;
begin
  FControls := nil;
  FRoot := nil;
  if not TAtlasDesignerAccess.Current(mEditor, FRoot) or not (FRoot is TWinControl) then
  begin
    FNames := '';
    Exit(False);
  end;
  mNames := mEditor.FileName;
  mBounds := '';
  for mComponent in TAtlasDesignerAccess.Selection(mEditor, FRoot) do
  begin
    if mComponent is TControl then
    begin
      FControls := FControls + [TControl(mComponent)];
      mNames := mNames + '|' + mComponent.Name;
      mBounds := mBounds + Format('|%d,%d,%d,%d', [TControl(mComponent).Left, TControl(mComponent).Top,
        TControl(mComponent).Width, TControl(mComponent).Height]);
    end;
  end;
  Result := Length(FControls) >= 2;
  if mNames <> FNames then
  begin
    // Neue Auswahl: Verzögerung von vorn, im Modus shortcut erst wieder auf Tastendruck.
    FNames := mNames;
    FBounds := mBounds;
    FSince := GetTickCount64;
    FRequested := False;
  end
  else if mBounds <> FBounds then
  begin
    // Lage oder Größe ändern sich (Ziehen): ausblenden, Verzögerung von vorn.
    FBounds := mBounds;
    FSince := GetTickCount64;
  end;
end;

function TAtlasIdeSelectionBar.SelectionBounds(out AScreen, AArea: TRect): Boolean;
var
  mOrigin: TPoint;
  mControl: TControl;
  mRect: TRect;
  mFirst: Boolean;
begin
  AScreen := TRect.Empty;
  Result := TAtlasDesignerAccess.ClientArea(TWinControl(FRoot), cAreaMargin, mOrigin, AArea);
  if not Result then
  begin
    Exit;
  end;
  mFirst := True;
  for mControl in FControls do
  begin
    mRect := TAtlasDesignerAccess.BoundsInRoot(mControl, TWinControl(FRoot));
    if mRect.IsEmpty then
    begin
      Continue;
    end;
    mRect.Offset(AArea.Left + mOrigin.X, AArea.Top + mOrigin.Y);
    if mFirst then
    begin
      AScreen := mRect;
      mFirst := False;
    end
    else
    begin
      AScreen.Union(mRect);
    end;
  end;
  Result := not mFirst;
end;

function TAtlasIdeSelectionBar.Props(const APath, AType: string): TArray<TAtlasBarProp>;
var
  mIndex: Integer;
  mValue: string;
begin
  SetLength(Result, Length(FControls));
  for mIndex := 0 to High(FControls) do
  begin
    if ReadProp(FControls[mIndex], APath, AType, mValue) then
    begin
      Result[mIndex] := TAtlasBarProp.Create(mValue);
    end
    else
    begin
      Result[mIndex] := TAtlasBarProp.Missing;
    end;
  end;
end;

function TAtlasIdeSelectionBar.StateOf(AItem: TAtlasBarItem; const AProps: TArray<TAtlasBarProp>): TAtlasBarState;
begin
  case AItem of
    TAtlasBarItem.Bold, TAtlasBarItem.Italic, TAtlasBarItem.AnchorLeft..TAtlasBarItem.AnchorBottom:
      Result := TAtlasSelectionBar.SetFlag(AProps, cElements[AItem]);
    TAtlasBarItem.Enabled..TAtlasBarItem.ParentColor, TAtlasBarItem.AlignLeft..TAtlasBarItem.AlignRight:
      Result := TAtlasSelectionBar.Flag(AProps, cElements[AItem]);
  else
    Result := TAtlasBarState.Off;
  end;
end;

function TAtlasIdeSelectionBar.TransferButton: TAtlasBarButton;
begin
  if not TAtlasIdeSettings.Current.DesignerPropertyPainter then
  begin
    Result := TAtlasBarButton.Create(cTexts[TAtlasBarItem.Transfer], TAtlasBarState.None,
      TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarTransferOff));
  end
  else if Assigned(FPainter) and FPainter.CanApply then
  begin
    Result := TAtlasBarButton.Create(cTexts[TAtlasBarItem.Transfer], TAtlasBarState.Off,
      TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarTransfer));
  end
  else
  begin
    Result := TAtlasBarButton.Create(cTexts[TAtlasBarItem.Transfer], TAtlasBarState.None,
      TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarTransferNeeds));
  end;
end;

function TAtlasIdeSelectionBar.ButtonOf(AItem: TAtlasBarItem): TAtlasBarButton;
var
  mProps: TArray<TAtlasBarProp>;
  mValue: TAtlasBarValue;
  mArgument: string;
begin
  if AItem = TAtlasBarItem.Transfer then
  begin
    Exit(TransferButton);
  end;
  mProps := Props(cPaths[AItem], cTypes[AItem]);
  mValue := TAtlasSelectionBar.Combine(mProps);
  case AItem of
    TAtlasBarItem.Enabled..TAtlasBarItem.ParentColor:
      mArgument := cTexts[AItem];
    TAtlasBarItem.AnchorLeft..TAtlasBarItem.AnchorBottom:
      mArgument := cElements[AItem];
    TAtlasBarItem.SameWidth, TAtlasBarItem.SameHeight:
      mArgument := FControls[0].Name;
  else
    mArgument := '';
  end;
  Result := TAtlasBarButton.Create(cTexts[AItem], StateOf(AItem, mProps),
    TAtlasDesignerToolStrings.Fmt(cHints[AItem], [mArgument]));
  if (AItem = TAtlasBarItem.FontSize) and (mValue.State = TAtlasBarState.On) then
  begin
    Result.Text := mValue.Value;
  end
  else if AItem = TAtlasBarItem.Bold then
  begin
    Result.Text := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarBoldShort);
    Result.Style := [fsBold];
  end
  else if AItem = TAtlasBarItem.Italic then
  begin
    Result.Text := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarItalicShort);
    Result.Style := [fsItalic];
  end
  else if (AItem = TAtlasBarItem.FontColor) and (mValue.State = TAtlasBarState.On) then
  begin
    Result.Swatch := TColor(StrToIntDef(mValue.Value, clNone));
  end;
  // Ohne die Eigenschaft bei allen: grau; bei einem Teil: Tooltip „für 2 von 4“.
  if mValue.State = TAtlasBarState.None then
  begin
    Result.State := TAtlasBarState.None;
  end
  else if mValue.Partial then
  begin
    Result.Hint := TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.BarPartial,
      [Result.Hint, mValue.Count, mValue.Total]);
  end;
end;

procedure TAtlasIdeSelectionBar.ShowBar;
var
  mButtons: TArray<TAtlasBarButton>;
  mIndex: Integer;
  mSelection, mArea: TRect;
begin
  FItems := TAtlasSelectionBar.ParseItems(TAtlasIdeSettings.Current.DesignerSelectionBarItems);
  if (Length(FItems) = 0) or not SelectionBounds(mSelection, mArea) then
  begin
    Hide;
    Exit;
  end;
  SetLength(mButtons, Length(FItems));
  for mIndex := 0 to High(FItems) do
  begin
    mButtons[mIndex] := ButtonOf(FItems[mIndex]);
    mButtons[mIndex].Separated := (mIndex > 0) and
      (TAtlasSelectionBar.GroupOf(FItems[mIndex]) <> TAtlasSelectionBar.GroupOf(FItems[mIndex - 1]));
  end;
  EnsureWindow;
  FWindow.SetButtons(mButtons);
  FWindow.ShowAt(TAtlasSelectionBar.Place(mSelection, FWindow.BarSize, mArea, FWindow.S(cGap)));
end;

procedure TAtlasIdeSelectionBar.Refresh;
begin
  if FindControls then
  begin
    FSince := 0;
    FRequested := True;
    ShowBar;
  end
  else
  begin
    Hide;
  end;
end;

procedure TAtlasIdeSelectionBar.Tick;
var
  mSettings: TAtlasPluginSettings;
  mShortcut: Boolean;
begin
  UpdateKeys;
  if not Wanted or not FindControls then
  begin
    Hide;
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  mShortcut := SameText(mSettings.DesignerSelectionBarMode, TAtlasSelectionBar.cModeShortcut);
  // Ziehen oder Größe ändern im Designer, Fokus im Objektinspektor: weg.
  if ((FWindow = nil) or not FWindow.MouseOver) and (GetKeyState(VK_LBUTTON) < 0) then
  begin
    FSince := GetTickCount64;
    Hide;
    Exit;
  end;
  if not TAtlasDesignerAccess.Focused or (mShortcut and not FRequested) or
    (not mShortcut and (GetTickCount64 - FSince < UInt64(mSettings.DesignerSelectionBarDelayMs))) then
  begin
    Hide;
    Exit;
  end;
  ShowBar;
end;

procedure TAtlasIdeSelectionBar.Request;
begin
  if Wanted then
  begin
    Refresh;
  end;
end;

procedure TAtlasIdeSelectionBar.Hide;
begin
  if FWindow <> nil then
  begin
    FWindow.HideBar;
  end;
end;

procedure TAtlasIdeSelectionBar.ApplyTheme;
begin
  if FWindow <> nil then
  begin
    FWindow.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

procedure TAtlasIdeSelectionBar.Toggle;
begin
  FActive := not FActive;
  if FActive then
  begin
    Tick;
  end
  else
  begin
    Hide;
    UpdateKeys;
  end;
end;

procedure TAtlasIdeSelectionBar.Click(AIndex: Integer; const AAt: TPoint);
begin
  if (AIndex < 0) or (AIndex > High(FItems)) or not FindControls then
  begin
    Exit;
  end;
  Run(FItems[AIndex], AAt);
end;

procedure TAtlasIdeSelectionBar.Run(AItem: TAtlasBarItem; const AAt: TPoint);
var
  mLabel: string;
  mStep: Integer;
begin
  mLabel := ButtonOf(AItem).Hint;
  case AItem of
    TAtlasBarItem.FontSmaller, TAtlasBarItem.FontLarger:
      begin
        mStep := IfThen(AItem = TAtlasBarItem.FontLarger, 1, -1);
        Change(cPaths[AItem], '',
          function(AOld: string): string
          begin
            Result := IntToStr(TAtlasSelectionBar.NextFontSize(StrToIntDef(AOld, 8), mStep));
          end, mLabel);
      end;
    TAtlasBarItem.FontSize:
      AskFontSize;
    TAtlasBarItem.FontColor:
      PopupColors(AAt);
    TAtlasBarItem.Bold, TAtlasBarItem.Italic, TAtlasBarItem.AnchorLeft..TAtlasBarItem.AnchorBottom:
      ToggleSet(AItem, mLabel);
    TAtlasBarItem.Enabled..TAtlasBarItem.ParentColor:
      ToggleFlag(AItem, mLabel);
    TAtlasBarItem.SameWidth:
      ChangeTo(cPaths[AItem], '', IntToStr(FControls[0].Width), mLabel);
    TAtlasBarItem.SameHeight:
      ChangeTo(cPaths[AItem], '', IntToStr(FControls[0].Height), mLabel);
    TAtlasBarItem.AlignLeft..TAtlasBarItem.AlignRight:
      ChangeTo(cPaths[AItem], cTypes[AItem], cElements[AItem], mLabel);
    TAtlasBarItem.FitText:
      TAtlasIdeFitText.Execute(FOnMessage);
    TAtlasBarItem.Transfer:
      FPainter.Execute(TAtlasPaintCommand.Apply);
  end;
  Refresh;
end;

procedure TAtlasIdeSelectionBar.Change(const APath, AType: string; const AValueOf: TFunc<string, string>;
  const ALabel: string);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mControl: TControl;
  mOld, mNew: string;
  mChange: TAtlasBarChange;
  mStep: TAtlasBarStep;
  mCount: Integer;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mStep.FileName := mEditor.FileName;
  mStep.Changes := nil;
  mCount := 0;
  for mControl in FControls do
  begin
    if not ReadProp(mControl, APath, AType, mOld) then
    begin
      Continue;
    end;
    mNew := AValueOf(mOld);
    if mNew = mOld then
    begin
      Continue;
    end;
    mChange.Name := mControl.Name;
    mChange.Path := APath;
    mChange.Value := mOld;
    mStep.Changes := mStep.Changes + [mChange];
    WriteProp(mControl, APath, mNew);
    Inc(mCount);
  end;
  if mCount = 0 then
  begin
    Exit;
  end;
  FSteps := FSteps + [mStep];
  if Length(FSteps) > cMaxSteps then
  begin
    Delete(FSteps, 0, 1);
  end;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  Say(TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.BarDone, [ALabel, mCount]));
end;

procedure TAtlasIdeSelectionBar.ChangeTo(const APath, AType, AValue, ALabel: string);
var
  mValue: string;
begin
  mValue := AValue;
  Change(APath, AType,
    function(AOld: string): string
    begin
      // Gleicher Wert bleibt als Text des Steuerelements stehen (kein Schritt).
      Result := mValue;
      if SameText(AOld, mValue) then
      begin
        Result := AOld;
      end;
    end, ALabel);
end;

procedure TAtlasIdeSelectionBar.ToggleFlag(AItem: TAtlasBarItem; const ALabel: string);
var
  mTarget: Boolean;
begin
  mTarget := TAtlasSelectionBar.Target(StateOf(AItem, Props(cPaths[AItem], cTypes[AItem])));
  ChangeTo(cPaths[AItem], cTypes[AItem], BoolToStr(mTarget, True), ALabel);
end;

procedure TAtlasIdeSelectionBar.ToggleSet(AItem: TAtlasBarItem; const ALabel: string);
var
  mTarget: Boolean;
  mElement: string;
begin
  mTarget := TAtlasSelectionBar.Target(StateOf(AItem, Props(cPaths[AItem], cTypes[AItem])));
  mElement := cElements[AItem];
  Change(cPaths[AItem], cTypes[AItem],
    function(AOld: string): string
    begin
      Result := AOld;
      if TAtlasSelectionBar.SetHas(AOld, mElement) <> mTarget then
      begin
        Result := TAtlasSelectionBar.SetWith(AOld, mElement, mTarget);
      end;
    end, ALabel);
end;

procedure TAtlasIdeSelectionBar.AskFontSize;
var
  mText: string;
  mSize: Integer;
  mValue: TAtlasBarValue;
begin
  mValue := TAtlasSelectionBar.Combine(Props('Font.Size', ''));
  mText := mValue.Value;
  if not InputQuery(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarSizeTitle),
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarSizePrompt), mText) then
  begin
    Exit;
  end;
  if not TryStrToInt(Trim(mText), mSize) or (mSize < TAtlasSelectionBar.cMinFontSize) or
    (mSize > TAtlasSelectionBar.cMaxFontSize) then
  begin
    Say(TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.BarSizeInvalid,
      [mText, TAtlasSelectionBar.cMinFontSize, TAtlasSelectionBar.cMaxFontSize]));
    Exit;
  end;
  ChangeTo('Font.Size', '', IntToStr(mSize), TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarSizeTitle));
end;

procedure TAtlasIdeSelectionBar.PopupColors(const AAt: TPoint);
var
  mColors: TArray<TColor>;
  mIndex, mUsed: Integer;
  mValue: string;
  mColor: TColor;
  mItem: TMenuItem;
begin
  mColors := nil;
  // Oben die im Formular verwendeten Schriftfarben, darunter die üblichen.
  for mIndex := 0 to FRoot.ComponentCount - 1 do
  begin
    if ReadProp(FRoot.Components[mIndex], 'Font.Color', '', mValue) then
    begin
      AddColor(mColors, TColor(StrToIntDef(mValue, clWindowText)));
    end;
  end;
  mUsed := Length(mColors);
  for mColor in cStandardColors do
  begin
    AddColor(mColors, mColor);
  end;
  FColorMenu.Items.Clear;
  for mIndex := 0 to High(mColors) do
  begin
    if (mIndex = mUsed) and (mUsed > 0) then
    begin
      FColorMenu.Items.Add(NewLine);
    end;
    mItem := TMenuItem.Create(FColorMenu);
    mItem.Caption := ColorToString(mColors[mIndex]);
    mItem.Tag := mColors[mIndex];
    SetSwatch(mItem, mColors[mIndex]);
    mItem.OnClick := ColorClick;
    FColorMenu.Items.Add(mItem);
  end;
  FColorMenu.Items.Add(NewLine);
  mItem := TMenuItem.Create(FColorMenu);
  mItem.Caption := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarColorMore);
  mItem.Tag := cColorMore;
  mItem.OnClick := ColorClick;
  FColorMenu.Items.Add(mItem);
  FColorMenu.Popup(AAt.X, AAt.Y);
end;

procedure TAtlasIdeSelectionBar.ColorClick(Sender: TObject);
var
  mTag: NativeInt;
  mOwner: TAtlasIdeSelectionBar;
begin
  mTag := TMenuItem(Sender).Tag;
  mOwner := Self;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    var
      mDialog: TColorDialog;
      mColor: TColor;
    begin
      mColor := TColor(mTag);
      if mTag = cColorMore then
      begin
        mDialog := TColorDialog.Create(nil);
        try
          mDialog.Options := [cdFullOpen];
          if not mDialog.Execute then
          begin
            Exit;
          end;
          mColor := mDialog.Color;
        finally
          mDialog.Free;
        end;
      end;
      if not mOwner.FindControls then
      begin
        Exit;
      end;
      mOwner.ChangeTo('Font.Color', '', IntToStr(mColor),
        TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarFontColor));
      mOwner.Refresh;
    end);
end;

function TAtlasIdeSelectionBar.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (Length(FSteps) > 0) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(FSteps[High(FSteps)].FileName, mEditor.FileName);
end;

procedure TAtlasIdeSelectionBar.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mStep: TAtlasBarStep;
  mIndex: Integer;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mStep := FSteps[High(FSteps)];
  SetLength(FSteps, Length(FSteps) - 1);
  for mIndex := High(mStep.Changes) downto 0 do
  begin
    mComponent := mRoot.FindComponent(mStep.Changes[mIndex].Name);
    if mComponent <> nil then
    begin
      WriteProp(mComponent, mStep.Changes[mIndex].Path, mStep.Changes[mIndex].Value);
    end;
  end;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  Say(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarUndone));
  if (FWindow <> nil) and FWindow.Shown then
  begin
    Refresh;
  end;
end;

procedure TAtlasIdeSelectionBar.Popup(const APoint: TPoint);
var
  mItem: TMenuItem;
begin
  FMenu.Items.Clear;
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarShow);
  mItem.Checked := FActive;
  mItem.Tag := cMenuShow;
  mItem.OnClick := MenuClick;
  FMenu.Items.Add(mItem);
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarUndo);
  mItem.Enabled := CanUndo;
  mItem.Tag := cMenuUndo;
  mItem.OnClick := MenuClick;
  FMenu.Items.Add(mItem);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeSelectionBar.MenuClick(Sender: TObject);
var
  mTag: NativeInt;
  mOwner: TAtlasIdeSelectionBar;
begin
  mTag := TMenuItem(Sender).Tag;
  mOwner := Self;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if mTag = cMenuShow then
      begin
        mOwner.Toggle;
      end
      else
      begin
        mOwner.Undo;
      end;
    end);
end;

end.
