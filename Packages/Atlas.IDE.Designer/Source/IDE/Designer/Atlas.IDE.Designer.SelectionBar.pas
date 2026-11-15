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
  Atlas.IDE.Designer.PropertyPainter,
  Atlas.IDE.Designer.Tool;

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

  /// <summary>Verfolgte Auswahl im Designer: Wurzel, Steuerelemente, Knöpfe und Stand (TAtlasBarTracking).</summary>
  TAtlasBarSelection = record
    Root: TComponent;
    Controls: TArray<TControl>;
    Items: TArray<TAtlasBarItem>;
    Tracking: TAtlasBarTracking;
  end;

  /// <summary>Menüs der Leiste: Pfeilmenü und Farbauswahl.</summary>
  TAtlasBarMenus = record
    Menu: TPopupMenu;
    ColorMenu: TPopupMenu;
  end;

  TAtlasIdeSelectionBar = class(TAtlasIdeDesignerTool)
  public const
    cId = 'selectionBar';
  private
    FPainter: TAtlasIdePropertyPainter;
    FActive: Boolean;
    FWindow: TAtlasSelectionBarWindow;
    FMenus: TAtlasBarMenus;
    FKeys: TAtlasSelectionBarKeys;
    FHistory: TAtlasBarHistory;
    FSelection: TAtlasBarSelection;
    procedure EnsureWindow;
    function FindControls: Boolean;
    function Wanted: Boolean;
    function SelectionBounds(out AScreen, AArea: TRect): Boolean;
    function Props(const APath, AType: string): TArray<TAtlasBarProp>;
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
    procedure ApplyTheme; override;
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
  cMenuShow = 0;
  cMenuUndo = 1;
  cColorMore = -1;
  cStandardColors: array[0..9] of TColor = (clWindowText, clBlack, clGrayText, clGray, clMaroon, clRed, clGreen,
    clNavy, clBlue, clHighlight);
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

{ TAtlasSelectionBarKeys }

function TAtlasSelectionBarKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.DesignerSelectionBar and (FOwner <> nil) and FOwner.FActive and
    TAtlasSelectionBar.IsShortcut(mSettings.DesignerSelectionBarMode) and
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
  inherited Create(AOnMessage);
  FPainter := APainter;
  FActive := True;
  FMenus.Menu := TPopupMenu.Create(nil);
  FMenus.ColorMenu := TPopupMenu.Create(nil);
  FKeys := TAtlasSelectionBarKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
end;

destructor TAtlasIdeSelectionBar.Destroy;
begin
  TAtlasKeyHook.Remove(FKeys);
  FKeys.Free;
  FWindow.Free;
  FMenus.ColorMenu.Free;
  FMenus.Menu.Free;
  inherited Destroy;
end;

procedure TAtlasIdeSelectionBar.ApplyTheme;
begin
  inherited ApplyTheme;
  if FWindow <> nil then
  begin
    FWindow.ApplyColors(TAtlasIdeStyle.Colors);
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

function TAtlasIdeSelectionBar.FindControls: Boolean;
var
  mEditor: IOTAFormEditor;
  mComponent: TComponent;
  mNames, mBounds: string;
begin
  FSelection.Controls := nil;
  FSelection.Root := nil;
  if not TAtlasDesignerAccess.Current(mEditor, FSelection.Root) or not (FSelection.Root is TWinControl) then
  begin
    FSelection.Tracking.Clear;
    Exit(False);
  end;
  mNames := mEditor.FileName;
  mBounds := '';
  for mComponent in TAtlasDesignerAccess.Selection(mEditor, FSelection.Root) do
  begin
    if mComponent is TControl then
    begin
      FSelection.Controls := FSelection.Controls + [TControl(mComponent)];
      mNames := mNames + '|' + mComponent.Name;
      mBounds := mBounds + Format('|%d,%d,%d,%d', [TControl(mComponent).Left, TControl(mComponent).Top,
        TControl(mComponent).Width, TControl(mComponent).Height]);
    end;
  end;
  Result := Length(FSelection.Controls) >= 2;
  FSelection.Tracking.Update(mNames, mBounds, GetTickCount64);
end;

function TAtlasIdeSelectionBar.Wanted: Boolean;
begin
  Result := FActive and TAtlasIdeSettings.Current.DesignerSelectionBar and TAtlasDesignerAccess.Shown;
end;

function TAtlasIdeSelectionBar.SelectionBounds(out AScreen, AArea: TRect): Boolean;
var
  mOrigin: TPoint;
  mControl: TControl;
  mRect: TRect;
  mFirst: Boolean;
begin
  AScreen := TRect.Empty;
  Result := TAtlasDesignerAccess.ClientArea(TWinControl(FSelection.Root), cAreaMargin, mOrigin, AArea);
  if not Result then
  begin
    Exit;
  end;
  mFirst := True;
  for mControl in FSelection.Controls do
  begin
    mRect := TAtlasDesignerAccess.BoundsInRoot(mControl, TWinControl(FSelection.Root));
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
  SetLength(Result, Length(FSelection.Controls));
  for mIndex := 0 to High(FSelection.Controls) do
  begin
    if ReadProp(FSelection.Controls[mIndex], APath, AType, mValue) then
    begin
      Result[mIndex] := TAtlasBarProp.Create(mValue);
    end
    else
    begin
      Result[mIndex] := TAtlasBarProp.Missing;
    end;
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
  mProps := Props(TAtlasBarItems.PathOf(AItem), TAtlasBarItems.PropTypeOf(AItem));
  mValue := TAtlasSelectionBar.Combine(mProps);
  mArgument := TAtlasBarItems.HintArgument(AItem, FSelection.Controls[0].Name);
  Result := TAtlasBarButton.Create(TAtlasBarItems.TextOf(AItem), TAtlasBarItems.StateOf(AItem, mProps),
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

function TAtlasIdeSelectionBar.TransferButton: TAtlasBarButton;
begin
  if not TAtlasIdeSettings.Current.DesignerPropertyPainter then
  begin
    Result := TAtlasBarButton.Create(TAtlasBarItems.TextOf(TAtlasBarItem.Transfer), TAtlasBarState.None,
      TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarTransferOff));
  end
  else if Assigned(FPainter) and FPainter.CanApply then
  begin
    Result := TAtlasBarButton.Create(TAtlasBarItems.TextOf(TAtlasBarItem.Transfer), TAtlasBarState.Off,
      TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarTransfer));
  end
  else
  begin
    Result := TAtlasBarButton.Create(TAtlasBarItems.TextOf(TAtlasBarItem.Transfer), TAtlasBarState.None,
      TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarTransferNeeds));
  end;
end;

procedure TAtlasIdeSelectionBar.ShowBar;
var
  mButtons: TArray<TAtlasBarButton>;
  mIndex: Integer;
  mSelection, mArea: TRect;
begin
  FSelection.Items := TAtlasSelectionBar.ParseItems(TAtlasIdeSettings.Current.DesignerSelectionBarItems);
  if (Length(FSelection.Items) = 0) or not SelectionBounds(mSelection, mArea) then
  begin
    Hide;
    Exit;
  end;
  SetLength(mButtons, Length(FSelection.Items));
  for mIndex := 0 to High(FSelection.Items) do
  begin
    mButtons[mIndex] := ButtonOf(FSelection.Items[mIndex]);
    mButtons[mIndex].Separated := (mIndex > 0) and (TAtlasSelectionBar.GroupOf(FSelection.Items[mIndex]) <>
      TAtlasSelectionBar.GroupOf(FSelection.Items[mIndex - 1]));
  end;
  EnsureWindow;
  FWindow.SetButtons(mButtons);
  FWindow.ShowAt(TAtlasSelectionBar.Place(mSelection, FWindow.BarSize, mArea, FWindow.S(cGap)));
end;

procedure TAtlasIdeSelectionBar.Refresh;
begin
  if FindControls then
  begin
    FSelection.Tracking.Since := 0;
    FSelection.Tracking.Requested := True;
    ShowBar;
  end
  else
  begin
    Hide;
  end;
end;

procedure TAtlasIdeSelectionBar.Click(AIndex: Integer; const AAt: TPoint);
begin
  if (AIndex < 0) or (AIndex > High(FSelection.Items)) or not FindControls then
  begin
    Exit;
  end;
  Run(FSelection.Items[AIndex], AAt);
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
        Change(TAtlasBarItems.PathOf(AItem), '',
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
      ChangeTo(TAtlasBarItems.PathOf(AItem), '', IntToStr(FSelection.Controls[0].Width), mLabel);
    TAtlasBarItem.SameHeight:
      ChangeTo(TAtlasBarItems.PathOf(AItem), '', IntToStr(FSelection.Controls[0].Height), mLabel);
    TAtlasBarItem.AlignLeft..TAtlasBarItem.AlignRight:
      ChangeTo(TAtlasBarItems.PathOf(AItem), TAtlasBarItems.PropTypeOf(AItem), TAtlasBarItems.ElementOf(AItem),
        mLabel);
    TAtlasBarItem.FitText:
      TAtlasIdeFitText.Execute(OnMessage);
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
  mStep: TAtlasBarStep;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mStep.FileName := mEditor.FileName;
  mStep.Changes := nil;
  for mControl in FSelection.Controls do
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
    mStep.Changes := mStep.Changes + [TAtlasBarChange.Create(mControl.Name, APath, mOld)];
    WriteProp(mControl, APath, mNew);
  end;
  if Length(mStep.Changes) = 0 then
  begin
    Exit;
  end;
  FHistory.Push(mStep);
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  Say(TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.BarDone, [ALabel, Length(mStep.Changes)]));
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
  mTarget := TAtlasSelectionBar.Target(TAtlasBarItems.StateOf(AItem,
    Props(TAtlasBarItems.PathOf(AItem), TAtlasBarItems.PropTypeOf(AItem))));
  ChangeTo(TAtlasBarItems.PathOf(AItem), TAtlasBarItems.PropTypeOf(AItem), BoolToStr(mTarget, True), ALabel);
end;

procedure TAtlasIdeSelectionBar.ToggleSet(AItem: TAtlasBarItem; const ALabel: string);
var
  mTarget: Boolean;
  mElement: string;
begin
  mTarget := TAtlasSelectionBar.Target(TAtlasBarItems.StateOf(AItem,
    Props(TAtlasBarItems.PathOf(AItem), TAtlasBarItems.PropTypeOf(AItem))));
  mElement := TAtlasBarItems.ElementOf(AItem);
  Change(TAtlasBarItems.PathOf(AItem), TAtlasBarItems.PropTypeOf(AItem),
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
  // Wie nach der Farbauswahl: Auswahl neu ermitteln, die gemerkten Controls können inzwischen freigegeben sein.
  if not FindControls then
  begin
    Exit;
  end;
  if not TAtlasSelectionBar.TryFontSize(mText, mSize) then
  begin
    Say(TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.BarSizeInvalid,
      [mText, TAtlasSelectionBar.cMinFontSize, TAtlasSelectionBar.cMaxFontSize]));
    Exit;
  end;
  ChangeTo('Font.Size', '', IntToStr(mSize), TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarSizeTitle));
end;

procedure TAtlasIdeSelectionBar.PopupColors(const AAt: TPoint);
var
  mUsedColors, mStandard, mColors: TArray<Integer>;
  mIndex, mUsed: Integer;
  mValue: string;
  mItem: TMenuItem;
begin
  // Oben die im Formular verwendeten Schriftfarben, darunter die üblichen.
  mUsedColors := nil;
  for mIndex := 0 to FSelection.Root.ComponentCount - 1 do
  begin
    if ReadProp(FSelection.Root.Components[mIndex], 'Font.Color', '', mValue) then
    begin
      mUsedColors := mUsedColors + [Integer(StrToIntDef(mValue, clWindowText))];
    end;
  end;
  SetLength(mStandard, Length(cStandardColors));
  for mIndex := 0 to High(cStandardColors) do
  begin
    mStandard[mIndex] := cStandardColors[mIndex];
  end;
  mColors := TAtlasSelectionBar.ColorChoices(mUsedColors, mStandard, mUsed);
  FMenus.ColorMenu.Items.Clear;
  for mIndex := 0 to High(mColors) do
  begin
    if (mIndex = mUsed) and (mUsed > 0) then
    begin
      FMenus.ColorMenu.Items.Add(NewLine);
    end;
    mItem := TMenuItem.Create(FMenus.ColorMenu);
    mItem.Caption := ColorToString(TColor(mColors[mIndex]));
    mItem.Tag := mColors[mIndex];
    SetSwatch(mItem, TColor(mColors[mIndex]));
    mItem.OnClick := ColorClick;
    FMenus.ColorMenu.Items.Add(mItem);
  end;
  FMenus.ColorMenu.Items.Add(NewLine);
  mItem := TMenuItem.Create(FMenus.ColorMenu);
  mItem.Caption := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarColorMore);
  mItem.Tag := cColorMore;
  mItem.OnClick := ColorClick;
  FMenus.ColorMenu.Items.Add(mItem);
  FMenus.ColorMenu.Popup(AAt.X, AAt.Y);
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

function TAtlasIdeSelectionBar.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := TAtlasDesignerAccess.Current(mEditor, mRoot) and FHistory.CanUndo(mEditor.FileName);
end;

procedure TAtlasIdeSelectionBar.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mStep: TAtlasBarStep;
  mIndex: Integer;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) or not FHistory.Pop(mStep) then
  begin
    Exit;
  end;
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

procedure TAtlasIdeSelectionBar.UpdateKeys;
begin
  if Wanted and TAtlasSelectionBar.IsShortcut(TAtlasIdeSettings.Current.DesignerSelectionBarMode) then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
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

procedure TAtlasIdeSelectionBar.Popup(const APoint: TPoint);
var
  mItem: TMenuItem;
begin
  FMenus.Menu.Items.Clear;
  mItem := TMenuItem.Create(FMenus.Menu);
  mItem.Caption := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarShow);
  mItem.Checked := FActive;
  mItem.Tag := cMenuShow;
  mItem.OnClick := MenuClick;
  FMenus.Menu.Items.Add(mItem);
  mItem := TMenuItem.Create(FMenus.Menu);
  mItem.Caption := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.BarUndo);
  mItem.Enabled := CanUndo;
  mItem.Tag := cMenuUndo;
  mItem.OnClick := MenuClick;
  FMenus.Menu.Items.Add(mItem);
  FMenus.Menu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeSelectionBar.Request;
begin
  if Wanted then
  begin
    Refresh;
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
  mShortcut := TAtlasSelectionBar.IsShortcut(mSettings.DesignerSelectionBarMode);
  // Ziehen oder Größe ändern im Designer, Fokus im Objektinspektor: weg.
  if ((FWindow = nil) or not FWindow.MouseOver) and (GetKeyState(VK_LBUTTON) < 0) then
  begin
    FSelection.Tracking.Since := GetTickCount64;
    Hide;
    Exit;
  end;
  if not TAtlasSelectionBar.Due(TAtlasDesignerAccess.Focused, mShortcut, FSelection.Tracking.Requested,
    GetTickCount64, FSelection.Tracking.Since, mSettings.DesignerSelectionBarDelayMs) then
  begin
    Hide;
    Exit;
  end;
  ShowBar;
end;

procedure TAtlasIdeSelectionBar.Hide;
begin
  if FWindow <> nil then
  begin
    FWindow.HideBar;
  end;
end;

end.
