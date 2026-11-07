unit Atlas.IDE.Designer.Bar;

// Designer-Leiste (#1442) in der IDE:
// - Zeigt ein Editorfenster den Formular-Designer, steht über ihm eine
//   Symbolleiste (TAtlasDesignerBar) an Stelle von Brotkrumen und
//   Editorleiste; zurück im Code ist es umgekehrt. Ein- und ausgeblendet wird
//   über den Leisten-Host (ShowIn, TAtlasIdeDesignerView), angelegt je
//   Editorfenster wie die übrigen Leisten (#1248).
// - Komponenten suchen: Fenster TAtlasComponentSearchWindow über die
//   Komponenten des Formulars im Designer, groß oder klein
//   (editor.designerBar.searchStyle). Taste editor.designerBar.searchKey
//   (Vorgabe Alt+^) nur, solange der Designer den Fokus hat: Tastaturbindungen
//   der IDE wirken nur im Code-Editor, darum über TAtlasKeyHook, angemeldet nur
//   solange ein Designer gezeigt wird.
// - Nichtvisuelle: führt die Aktion der IDE hinter Strg+H aus und zeigt ihren
//   Zustand (gedrückt = ausgeblendet). Atlas blendet nichts selbst aus.
// - Elternelement auswählen: Parent der ersten Auswahl, auf dem Formular das
//   Formular selbst.
// - Tab-Reihenfolge: Marken mit der TabOrder über jedem fokussierbaren
//   Steuerelement (TAtlasTabOrderOverlay), Sprünge gegen die
//   Lesereihenfolge in Warnfarbe (TAtlasTabOrder). Experimentell
//   (editor.designerBar.tabOrderClick): Klick auf eine Marke vergibt die
//   Reihenfolge je Elternelement neu ab 0 (TAtlasTabClicks).
// - Ausrichten (experimentell, editor.designerBar.align): Menü am Pfeil,
//   Klick auf das Symbol wiederholt den letzten Befehl (TAtlasDesignerAlign).
// - Eigene Sicherung TAtlasFeature.DesignerBar. Nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  TAtlasIdeDesignerBar = class
  public type
    THooks = record
      /// <summary>Zeile in der Meldungsansicht.</summary>
      Message: TProc<string>;
    end;
  private class var
    FState: TObject;
    FHooks: THooks;
  public
    class procedure Install(const AHooks: THooks); static;
    class procedure Uninstall; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.Types,
  System.TypInfo,
  System.Variants,
  System.Actions,
  Vcl.ActnList,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Menus,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Designer.Components,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.Search,
  Atlas.UI.Designer.TabOverlay,
  Atlas.IDE.Foundation.DesignerView,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Foundation.Settings;

const
  cTickMs = 200;
  cKeyPriority = 50;
  cIdSearch = 'search';
  cIdNonVisual = 'nonVisual';
  cIdParent = 'parent';
  cIdTabOrder = 'tabOrder';
  cIdAlign = 'align';
  /// <summary>Aktion der IDE hinter Strg+H im Designer.</summary>
  cNonVisualAction = 'ToggleNonVisualComponentVisibilityCommand';
  /// <summary>Eigenschaften für die Vorschau im Suchfenster, sofern gesetzt.</summary>
  cPreviewProperties: array[0..9] of string = ('Caption', 'Text', 'Align', 'Visible', 'Enabled', 'TabOrder', 'Hint',
    'Action', 'DataSource', 'DataField');

type
  /// <summary>Taste für „Komponenten suchen“, solange der Designer den Fokus hat.</summary>
  TSearchKeyClient = class(TAtlasKeyClient)
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  TDesignerBarState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FKeyClient: TSearchKeyClient;
    FSearch: TAtlasComponentSearchWindow;
    /// <summary>Wahl im Suchfenster bis zum Ende der Sitzung: Kind, Fields, Grouping, Preview, Bounds.</summary>
    FSearchChoice: TAtlasComponentSearchOptions;
    FOverlay: TAtlasTabOrderOverlay;
    FTabOrder: Boolean;
    FTabFile: string;
    FTabClicks: TAtlasTabClicks;
    FAlignMenu: TPopupMenu;
    FLastAlign: TAtlasAlignKind;
    FActionIndex: Integer;
    FActionLogged: Boolean;
    procedure Tick(Sender: TObject);
    function CreateBar: TAtlasDesignerBar;
    function Buttons: TArray<TAtlasDesignerButton>;
    procedure UpdateBars;
    procedure UpdateKeyClient;
    procedure Command(const AId: string);
    procedure ShowMenu(const AId: string; const APoint: TPoint);
    function FindNonVisualAction: TContainedAction;
    procedure ToggleNonVisual;
    procedure ToggleTabOrder;
    procedure UpdateOverlay;
    procedure EnsureOverlay;
    procedure HideOverlay;
    procedure TabBadgeClicked(const AName: string);
    procedure AlignMenuClick(Sender: TObject);
    function SearchOptions(const AEditor: IOTAFormEditor; ARoot: TComponent): TAtlasComponentSearchOptions;
    procedure WireSearch(AWindow: TAtlasComponentSearchWindow; ACompact: Boolean);
    procedure CloseSearch;
    procedure Later(const AAction: TProc);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    procedure ApplyTheme;
    procedure OpenSearch;
  end;

function State: TDesignerBarState;
begin
  Result := TDesignerBarState(TAtlasIdeDesignerBar.FState);
end;

function BarColors: TAtlasColors;
begin
  if TAtlasIdeSettings.Current.BreadcrumbsIdeColors then
  begin
    Result := TAtlasIdeStyle.ChromeColors;
  end
  else
  begin
    Result := TAtlasIdeStyle.Colors;
  end;
end;

function DesignerOf(const AEditor: IOTAFormEditor): IDesigner;
var
  mNative: INTAFormEditor;
begin
  Result := nil;
  if Supports(AEditor, INTAFormEditor, mNative) then
  begin
    Result := mNative.FormDesigner;
  end;
end;

/// <summary>Hat der Formular-Designer den Fokus (ein Steuerelement im Entwurf oder das Formular selbst)?</summary>
function DesignerFocused: Boolean;
var
  mControl: TControl;
begin
  mControl := FindControl(GetFocus);
  while mControl <> nil do
  begin
    if csDesigning in mControl.ComponentState then
    begin
      Exit(True);
    end;
    mControl := mControl.Parent;
  end;
  Result := False;
end;

/// <summary>Lage von AControl im Client von ARoot; leer, wenn ARoot kein Vorfahr ist.</summary>
function BoundsInRoot(AControl: TControl; ARoot: TWinControl): TRect;
var
  mParent: TWinControl;
  mTopLeft: TPoint;
begin
  Result := TRect.Empty;
  mParent := AControl.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  mTopLeft := AControl.BoundsRect.TopLeft;
  if mParent <> ARoot then
  begin
    if not ARoot.ContainsControl(mParent) then
    begin
      Exit;
    end;
    mTopLeft := mParent.ClientToParent(mTopLeft, ARoot);
  end;
  Result := Rect(mTopLeft.X, mTopLeft.Y, mTopLeft.X + AControl.Width, mTopLeft.Y + AControl.Height);
end;

function ParentNameOf(AControl: TControl; ARoot: TComponent): string;
begin
  Result := '';
  if (AControl.Parent <> nil) and (AControl.Parent <> ARoot) then
  begin
    Result := AControl.Parent.Name;
  end;
end;

/// <summary>Wert der Eigenschaft als Text für die Vorschau; False ohne sie oder ohne Wert.</summary>
function PropText(AComponent: TComponent; const AName: string; out AText: string): Boolean;
var
  mInfo: PPropInfo;
  mObject: TObject;
begin
  AText := '';
  mInfo := GetPropInfo(AComponent, AName);
  if mInfo = nil then
  begin
    Exit(False);
  end;
  case mInfo^.PropType^.Kind of
    tkClass:
      begin
        mObject := GetObjectProp(AComponent, mInfo);
        if mObject is TComponent then
        begin
          AText := TComponent(mObject).Name;
        end;
      end;
    tkInteger, tkInt64, tkEnumeration, tkFloat, tkSet, tkChar, tkWChar, tkString, tkLString, tkUString, tkWString:
      AText := VarToStr(GetPropValue(AComponent, mInfo, True));
  end;
  Result := AText <> '';
end;

/// <summary>Zeile im Protokoll und in der Meldungsansicht.</summary>
procedure Say(const AText: string);
begin
  TAtlasGuard.Log('Designer-Leiste: ' + AText);
  if Assigned(TAtlasIdeDesignerBar.FHooks.Message) then
  begin
    TAtlasIdeDesignerBar.FHooks.Message(AText);
  end;
end;

/// <summary>Leiste über dem Designer: zuerst ganz oben einhängen, dann oben ausrichten.</summary>
procedure PlaceBar(ABar: TAtlasDesignerBar; AEditorParent: TWinControl);
begin
  if ABar.Parent = AEditorParent then
  begin
    Exit;
  end;
  ABar.Top := 0;
  ABar.Align := alTop;
  ABar.Parent := AEditorParent;
end;

/// <summary>Formular im Designer des aktiven Editorfensters.</summary>
function CurrentDesigner(out AEditor: IOTAFormEditor; out ARoot: TComponent): Boolean;
begin
  AEditor := TAtlasIdeDesignerView.CurrentFormEditor;
  ARoot := TAtlasIdeDesignerView.RootOf(AEditor);
  Result := (AEditor <> nil) and (ARoot <> nil);
end;

function AlignCaption(AKind: TAtlasAlignKind): string;
begin
  case AKind of
    TAtlasAlignKind.Rights: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignRights);
    TAtlasAlignKind.Tops: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignTops);
    TAtlasAlignKind.Bottoms: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignBottoms);
    TAtlasAlignKind.CentersH: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignCentersH);
    TAtlasAlignKind.CentersV: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignCentersV);
    TAtlasAlignKind.CenterInParentH: Result := TAtlasDesignerStrings.Text(
      TAtlasDesignerTextId.DesignerAlignCenterInParentH);
    TAtlasAlignKind.CenterInParentV: Result := TAtlasDesignerStrings.Text(
      TAtlasDesignerTextId.DesignerAlignCenterInParentV);
    TAtlasAlignKind.SameWidth: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignSameWidth);
    TAtlasAlignKind.SameHeight: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignSameHeight);
    TAtlasAlignKind.SpaceH: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignSpaceH);
    TAtlasAlignKind.SpaceV: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignSpaceV);
  else
    Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAlignLefts);
  end;
end;

/// <summary>Ausgewählte Komponenten des Formulars ARoot ohne das Formular selbst.</summary>
function SelectionOf(const AEditor: IOTAFormEditor; ARoot: TComponent): TArray<TComponent>;
var
  mDesigner: IDesigner;
  mList: IDesignerSelections;
  mIndex: Integer;
  mItem: TPersistent;
begin
  Result := nil;
  mDesigner := DesignerOf(AEditor);
  if mDesigner = nil then
  begin
    Exit;
  end;
  mList := CreateSelectionList;
  mDesigner.GetSelections(mList);
  for mIndex := 0 to mList.Count - 1 do
  begin
    mItem := mList[mIndex];
    if (mItem is TComponent) and (mItem <> ARoot) and (TComponent(mItem).Owner = ARoot) then
    begin
      Result := Result + [TComponent(mItem)];
    end;
  end;
end;

procedure SelectParent;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mDesigner: IDesigner;
begin
  if not CurrentDesigner(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := DesignerOf(mEditor);
  mSelected := SelectionOf(mEditor, mRoot);
  if (mDesigner = nil) or (Length(mSelected) = 0) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNoSelection));
    Exit;
  end;
  if not (mSelected[0] is TControl) or (TControl(mSelected[0]).Parent = nil) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNoParent));
    Exit;
  end;
  mDesigner.SelectComponent(TControl(mSelected[0]).Parent);
end;

/// <summary>Steuerelemente der Auswahl mit demselben Elternelement wie das erste: Lagen in verschiedenen
/// Elternelementen sind nicht vergleichbar.</summary>
function SiblingControls(const ASelected: TArray<TComponent>; out AParent: TWinControl): TArray<TControl>;
var
  mComponent: TComponent;
begin
  Result := nil;
  AParent := nil;
  for mComponent in ASelected do
  begin
    if not (mComponent is TControl) then
    begin
      Continue;
    end;
    if AParent = nil then
    begin
      AParent := TControl(mComponent).Parent;
    end;
    if TControl(mComponent).Parent = AParent then
    begin
      Result := Result + [TControl(mComponent)];
    end;
  end;
end;

procedure AlignSelection(AKind: TAtlasAlignKind);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mControls: TArray<TControl>;
  mRects, mNew: TArray<TRect>;
  mParent: TWinControl;
  mIndex: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerAlign or not CurrentDesigner(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := DesignerOf(mEditor);
  if mDesigner = nil then
  begin
    Exit;
  end;
  mControls := SiblingControls(SelectionOf(mEditor, mRoot), mParent);
  if (mParent = nil) or not TAtlasDesignerAlign.Applicable(AKind, Length(mControls)) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarAlignNeeds));
    Exit;
  end;
  SetLength(mRects, Length(mControls));
  for mIndex := 0 to High(mControls) do
  begin
    mRects[mIndex] := mControls[mIndex].BoundsRect;
  end;
  mNew := TAtlasDesignerAlign.Apply(AKind, mRects, mParent.ClientRect);
  for mIndex := 0 to High(mControls) do
  begin
    if mNew[mIndex] <> mRects[mIndex] then
    begin
      mControls[mIndex].BoundsRect := mNew[mIndex];
    end;
  end;
  mDesigner.Modified;
end;

/// <summary>Formular des Designers für die Marken der Tab-Reihenfolge: aktiv, mit sichtbarem Fenster.</summary>
function OverlayForm(out AEditor: IOTAFormEditor; out AForm: TWinControl): Boolean;
var
  mRoot: TComponent;
begin
  AForm := nil;
  Result := Application.Active and CurrentDesigner(AEditor, mRoot) and (mRoot is TWinControl);
  if Result then
  begin
    AForm := TWinControl(mRoot);
    Result := AForm.HandleAllocated and IsWindowVisible(AForm.Handle);
  end;
end;

/// <summary>Fokussierbare Steuerelemente und Behälter des Formulars mit Namen.</summary>
function TabStopsOf(AForm: TWinControl): TArray<TAtlasTabStop>;
var
  mIndex: Integer;
  mComponent: TComponent;
  mControl: TWinControl;
begin
  Result := nil;
  for mIndex := 0 to AForm.ComponentCount - 1 do
  begin
    mComponent := AForm.Components[mIndex];
    if not (mComponent is TWinControl) or (mComponent.Name = '') then
    begin
      Continue;
    end;
    mControl := TWinControl(mComponent);
    if (mControl.Parent = nil) or not (mControl.TabStop or (csAcceptsControls in mControl.ControlStyle)) then
    begin
      Continue;
    end;
    Result := Result + [TAtlasTabStop.Create(mControl.Name, ParentNameOf(mControl, AForm), mControl.TabOrder,
      BoundsInRoot(mControl, AForm))];
  end;
end;

/// <summary>Client des Formulars auf dem Bildschirm (AScreen) und der sichtbare Teil davon (AVisible): Der
/// Designer kann es abschneiden oder scrollen. False, wenn nichts sichtbar ist.</summary>
function VisibleArea(AForm: TWinControl; out AScreen, AVisible: TRect): Boolean;
var
  mOrigin: TPoint;
  mHost: HWND;
begin
  mOrigin := AForm.ClientToScreen(Point(0, 0));
  AScreen := Rect(mOrigin.X, mOrigin.Y, mOrigin.X + AForm.ClientWidth, mOrigin.Y + AForm.ClientHeight);
  mHost := GetParent(AForm.Handle);
  AVisible := AScreen;
  if (mHost <> 0) and GetWindowRect(mHost, AVisible) then
  begin
    AVisible.Intersect(AScreen);
  end
  else
  begin
    AVisible := AScreen;
  end;
  Result := not AVisible.IsEmpty;
end;

/// <summary>Marken im Fenster AVisible; ein Sprung gegen die Lesereihenfolge in Warnfarbe.</summary>
function BadgesOf(const AStops: TArray<TAtlasTabStop>; const AScreen, AVisible: TRect): TArray<TAtlasTabBadge>;
var
  mOut: TArray<Boolean>;
  mIndex: Integer;
begin
  mOut := TAtlasTabOrder.OutOfOrder(AStops);
  Result := nil;
  for mIndex := 0 to High(AStops) do
  begin
    Result := Result + [TAtlasTabBadge.Create(AStops[mIndex].Name, AStops[mIndex].TabOrder, mOut[mIndex],
      Point(AStops[mIndex].Bounds.Left + AScreen.Left - AVisible.Left,
      AStops[mIndex].Bounds.Top + AScreen.Top - AVisible.Top))];
  end;
end;

/// <summary>Gesetzte Eigenschaften für die Vorschau; Vorgaben zeigen nichts Neues.</summary>
function PreviewOf(AComponent: TComponent): TArray<string>;
var
  mName, mText: string;
begin
  Result := nil;
  for mName in cPreviewProperties do
  begin
    if not PropText(AComponent, mName, mText) then
    begin
      Continue;
    end;
    if (SameText(mName, 'Align') and SameText(mText, 'alNone')) or
      ((SameText(mName, 'Visible') or SameText(mName, 'Enabled')) and SameText(mText, 'True')) then
    begin
      Continue;
    end;
    Result := Result + [mName + ' = ' + mText];
  end;
end;

/// <summary>Belegte Ereignisse als „OnClick = Button1Click“.</summary>
function EventsOf(AComponent: TComponent; const ADesigner: IDesigner): TArray<string>;
var
  mProp, mCount: Integer;
  mList: PPropList;
  mMethod: TMethod;
  mText: string;
begin
  Result := nil;
  mCount := GetPropList(PTypeInfo(AComponent.ClassInfo), [tkMethod], nil);
  if mCount <= 0 then
  begin
    Exit;
  end;
  GetMem(mList, mCount * SizeOf(PPropInfo));
  try
    GetPropList(PTypeInfo(AComponent.ClassInfo), [tkMethod], mList);
    for mProp := 0 to mCount - 1 do
    begin
      mMethod := GetMethodProp(AComponent, mList^[mProp]);
      if mMethod.Code = nil then
      begin
        Continue;
      end;
      mText := ADesigner.GetMethodName(mMethod);
      if mText <> '' then
      begin
        Result := Result + [string(mList^[mProp]^.Name) + ' = ' + mText];
      end;
    end;
  finally
    FreeMem(mList);
  end;
end;

function ItemOf(AComponent, ARoot: TComponent; const ADesigner: IDesigner): TAtlasDesignerItem;
var
  mText: string;
begin
  Result := TAtlasDesignerItem.Create(AComponent.Name, AComponent.ClassName, AComponent is TControl);
  if AComponent is TControl then
  begin
    Result.Container := (AComponent is TWinControl) and (csAcceptsControls in TControl(AComponent).ControlStyle);
    Result.ParentName := ParentNameOf(TControl(AComponent), ARoot);
    if ARoot is TWinControl then
    begin
      Result.Bounds := BoundsInRoot(TControl(AComponent), TWinControl(ARoot));
    end;
  end;
  if PropText(AComponent, 'Caption', mText) or PropText(AComponent, 'Text', mText) then
  begin
    Result.Caption := mText;
  end;
  Result.Properties := Result.Properties + PreviewOf(AComponent);
  if ADesigner <> nil then
  begin
    Result.Events := Result.Events + EventsOf(AComponent, ADesigner);
  end;
end;

function ItemsOf(ARoot: TComponent; const ADesigner: IDesigner): TArray<TAtlasDesignerItem>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if ARoot.Components[mIndex].Name <> '' then
    begin
      Result := Result + [ItemOf(ARoot.Components[mIndex], ARoot, ADesigner)];
    end;
  end;
end;

/// <summary>Methode zum Ereignis OnClick, sonst zum ersten belegten Ereignis; '' ohne.</summary>
function EventMethod(const AEvents: TArray<string>): string;
var
  mEvent, mItem: string;
  mPos: Integer;
begin
  Result := '';
  if Length(AEvents) = 0 then
  begin
    Exit;
  end;
  mEvent := AEvents[0];
  for mItem in AEvents do
  begin
    if mItem.StartsWith('OnClick ', True) then
    begin
      mEvent := mItem;
    end;
  end;
  mPos := Pos(' = ', mEvent);
  if mPos > 0 then
  begin
    Result := Copy(mEvent, mPos + 3, MaxInt);
  end;
end;

procedure SearchAction(AAction: TAtlasComponentSearchAction; const AItem: TAtlasDesignerItem);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mMethod: string;
begin
  if not CurrentDesigner(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(AItem.Name);
  mDesigner := DesignerOf(mEditor);
  // Umbenannt oder gelöscht, seit das Fenster offen ist.
  if (mComponent = nil) or (mDesigner = nil) then
  begin
    Exit;
  end;
  if AAction = TAtlasComponentSearchAction.Select then
  begin
    mDesigner.SelectComponent(mComponent);
  end
  else if AAction = TAtlasComponentSearchAction.Event then
  begin
    mMethod := EventMethod(AItem.Events);
    if mMethod = '' then
    begin
      Exit;
    end;
    mDesigner.SelectComponent(mComponent);
    if mDesigner.MethodExists(mMethod) then
    begin
      mDesigner.ShowMethod(mMethod);
    end;
  end;
end;

{ TSearchKeyClient }

function TSearchKeyClient.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mKey: Integer;
begin
  mKey := TAtlasIdeSettings.Current.DesignerSearchKey;
  Result := (mKey <> 0) and (ShortCut(AKey, AShift) = TShortCut(mKey)) and DesignerFocused;
end;

procedure TSearchKeyClient.HandleKey(AKey: Word; AShift: TShiftState);
begin
  if TAtlasIdeDesignerBar.FState = nil then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      State.OpenSearch;
    end);
end;

{ TDesignerBarState }

constructor TDesignerBarState.Create;
begin
  inherited Create;
  FTabClicks := TAtlasTabClicks.Create;
  FActionIndex := -1;
  FSearchChoice := Default(TAtlasComponentSearchOptions);
  FSearchChoice.Kind := TAtlasDesignerKind.All;
  FSearchChoice.Fields := [TAtlasDesignerField.Name, TAtlasDesignerField.Caption, TAtlasDesignerField.ClassName];
  FSearchChoice.Grouping := TAtlasDesignerGrouping.Hierarchy;
  FSearchChoice.Preview := True;
  FLastAlign := TAtlasAlignKind.Lefts;
  FHost := TAtlasEditorBarHost.Create('Designer-Leiste', TAtlasFeature.DesignerBar,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateBar;
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      PlaceBar(TAtlasDesignerBar(ABar), AEditorParent);
    end);
  FHost.ShowIn := TAtlasEditorBarView.Designer;
  FAlignMenu := TPopupMenu.Create(nil);
  FKeyClient := TSearchKeyClient.Create(cKeyPriority);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TDesignerBarState.Destroy;
begin
  FTimer.Free;
  TAtlasKeyHook.Remove(FKeyClient);
  FKeyClient.Free;
  CloseSearch;
  FOverlay.Free;
  FAlignMenu.Free;
  FHost.Free;
  FTabClicks.Free;
  inherited Destroy;
end;

procedure TDesignerBarState.Reset;
begin
  if not TAtlasIdeSettings.Current.EditorDesignerBar then
  begin
    FHost.Clear;
    HideOverlay;
    CloseSearch;
  end;
  UpdateKeyClient;
  ApplyTheme;
end;

procedure TDesignerBarState.ApplyTheme;
var
  mColors: TAtlasColors;
begin
  mColors := BarColors;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasDesignerBar(ABar).ApplyColors(mColors);
    end);
  if FOverlay <> nil then
  begin
    FOverlay.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable. Einordnen und Wächter: Host.</summary>
function TDesignerBarState.CreateBar: TAtlasDesignerBar;
var
  mBar: TAtlasDesignerBar;
  mHost: TAtlasEditorBarHost;
begin
  mBar := TAtlasDesignerBar.Create(nil);
  mHost := FHost;
  mBar.ApplyColors(BarColors);
  mBar.SetButtons(Buttons);
  mBar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      mHost.Disabled(ASender);
    end;
  mBar.OnCommand :=
    procedure(AId: string)
    var
      mId: string;
    begin
      mId := AId;
      // Nach dem Klick: Die IDE holt den Fokus in den Designer; erst danach wirken.
      Later(
        procedure
        begin
          Command(mId);
        end);
    end;
  mBar.OnMenu :=
    procedure(AId: string; APoint: TPoint)
    var
      mId: string;
      mPoint: TPoint;
    begin
      mId := AId;
      mPoint := APoint;
      Later(
        procedure
        begin
          ShowMenu(mId, mPoint);
        end);
    end;
  Result := mBar;
end;

function TDesignerBarState.FindNonVisualAction: TContainedAction;
var
  mServices: INTAServices;
  mList: TCustomActionList;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  mList := mServices.ActionList;
  // Gemerkter Index: Die Liste hat Tausende Einträge, der Takt fragt fünfmal je Sekunde.
  if (FActionIndex >= 0) and (FActionIndex < mList.ActionCount) and
    SameText(mList.Actions[FActionIndex].Name, cNonVisualAction) then
  begin
    Exit(mList.Actions[FActionIndex]);
  end;
  FActionIndex := -1;
  for mIndex := 0 to mList.ActionCount - 1 do
  begin
    if SameText(mList.Actions[mIndex].Name, cNonVisualAction) then
    begin
      FActionIndex := mIndex;
      Exit(mList.Actions[mIndex]);
    end;
  end;
  if not FActionLogged then
  begin
    FActionLogged := True;
    TAtlasGuard.Log('Designer-Leiste: IDE-Aktion ' + cNonVisualAction + ' nicht gefunden');
  end;
end;

function TDesignerBarState.Buttons: TArray<TAtlasDesignerButton>;
var
  mSettings: TAtlasPluginSettings;
  mButton: TAtlasDesignerButton;
  mAction: TContainedAction;
  mHint: string;
begin
  mSettings := TAtlasIdeSettings.Current;
  mHint := TAtlasStrings.Text(TAtlasTextId.DesignerBarSearchHint);
  if mSettings.DesignerSearchKey <> 0 then
  begin
    mHint := mHint + ' (' + ShortCutToText(TShortCut(mSettings.DesignerSearchKey)) + ')';
  end;
  Result := TArray<TAtlasDesignerButton>.Create(TAtlasDesignerButton.Create(cIdSearch,
    TAtlasToolbarIcon.ComponentSearch, mHint));
  mButton := TAtlasDesignerButton.Create(cIdNonVisual, TAtlasToolbarIcon.NonVisual,
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNonVisualHint));
  mAction := FindNonVisualAction;
  if mAction = nil then
  begin
    mButton.Enabled := False;
    mButton.Hint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNonVisualMissing);
  end
  else
  begin
    mAction.Update;
    if mAction is TCustomAction then
    begin
      mButton.Enabled := TCustomAction(mAction).Enabled;
      mButton.Pressed := TCustomAction(mAction).Checked;
      // Wie im Mockup: ausgeblendet = durchgestrichenes Auge.
      if mButton.Pressed then
      begin
        mButton.Icon := TAtlasToolbarIcon.NonVisualHidden;
      end;
    end;
  end;
  Result := Result + [mButton];
  mButton := TAtlasDesignerButton.Create(cIdParent, TAtlasToolbarIcon.SelectParent,
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarParentHint));
  mButton.GapBefore := True;
  Result := Result + [mButton];
  if mSettings.DesignerTabOrderClick then
  begin
    mHint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarTabOrderClickHint);
  end
  else
  begin
    mHint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarTabOrderHint);
  end;
  mButton := TAtlasDesignerButton.Create(cIdTabOrder, TAtlasToolbarIcon.TabOrder, mHint);
  mButton.Pressed := FTabOrder;
  Result := Result + [mButton];
  if mSettings.DesignerAlign then
  begin
    mButton := TAtlasDesignerButton.Create(cIdAlign, TAtlasToolbarIcon.AlignControls,
      TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerBarAlignHint, [AlignCaption(FLastAlign)]));
    mButton.Menu := True;
    Result := Result + [mButton];
  end;
end;

procedure TDesignerBarState.UpdateBars;
var
  mButtons: TArray<TAtlasDesignerButton>;
begin
  if FHost.Count = 0 then
  begin
    Exit;
  end;
  mButtons := Buttons;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasDesignerBar(ABar).SetButtons(mButtons);
    end);
end;

procedure TDesignerBarState.UpdateKeyClient;
var
  mWanted: Boolean;
begin
  // Nur angemeldet, solange ein Designer gezeigt wird: sonst berührt Atlas keine Taste (TAtlasKeyHook).
  mWanted := FHost.Guard and TAtlasIdeSettings.Current.EditorDesignerBar and
    (TAtlasIdeSettings.Current.DesignerSearchKey <> 0) and (TAtlasIdeDesignerView.CurrentFormEditor <> nil);
  if mWanted then
  begin
    TAtlasKeyHook.Add(FKeyClient);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeyClient);
  end;
end;

procedure TDesignerBarState.Tick(Sender: TObject);
begin
  // Sicherung ausgelöst: Leisten weg, bis die Funktion wieder eingeschaltet ist.
  if not FHost.Guard then
  begin
    TAtlasKeyHook.Remove(FKeyClient);
    HideOverlay;
    Exit;
  end;
  if not TAtlasIdeSettings.Current.EditorDesignerBar then
  begin
    TAtlasKeyHook.Remove(FKeyClient);
    HideOverlay;
    if FHost.Count > 0 then
    begin
      FHost.Clear;
    end;
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      FHost.Ensure;
      UpdateKeyClient;
      UpdateBars;
      UpdateOverlay;
    end);
end;

procedure TDesignerBarState.Command(const AId: string);
begin
  if SameText(AId, cIdSearch) then
  begin
    OpenSearch;
  end
  else if SameText(AId, cIdNonVisual) then
  begin
    ToggleNonVisual;
  end
  else if SameText(AId, cIdParent) then
  begin
    SelectParent;
  end
  else if SameText(AId, cIdTabOrder) then
  begin
    ToggleTabOrder;
  end
  else if SameText(AId, cIdAlign) then
  begin
    AlignSelection(FLastAlign);
  end;
  UpdateBars;
end;

procedure TDesignerBarState.ShowMenu(const AId: string; const APoint: TPoint);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mKind: TAtlasAlignKind;
  mItem: TMenuItem;
  mCount: Integer;
begin
  if not SameText(AId, cIdAlign) or not CurrentDesigner(mEditor, mRoot) then
  begin
    Exit;
  end;
  mCount := Length(SelectionOf(mEditor, mRoot));
  FAlignMenu.Items.Clear;
  for mKind := Low(TAtlasAlignKind) to High(TAtlasAlignKind) do
  begin
    // Gruppen: Kanten, Mitten, im Elternelement, Größe, Abstände.
    if mKind in [TAtlasAlignKind.CentersH, TAtlasAlignKind.CenterInParentH, TAtlasAlignKind.SameWidth,
      TAtlasAlignKind.SpaceH] then
    begin
      mItem := TMenuItem.Create(FAlignMenu);
      mItem.Caption := '-';
      FAlignMenu.Items.Add(mItem);
    end;
    mItem := TMenuItem.Create(FAlignMenu);
    mItem.Caption := AlignCaption(mKind);
    mItem.Tag := Ord(mKind);
    mItem.Enabled := TAtlasDesignerAlign.Applicable(mKind, mCount);
    mItem.Checked := mKind = FLastAlign;
    mItem.OnClick := AlignMenuClick;
    FAlignMenu.Items.Add(mItem);
  end;
  FAlignMenu.Popup(APoint.X, APoint.Y);
end;

procedure TDesignerBarState.AlignMenuClick(Sender: TObject);
var
  mKind: TAtlasAlignKind;
begin
  mKind := TAtlasAlignKind(TMenuItem(Sender).Tag);
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      FLastAlign := mKind;
      AlignSelection(mKind);
      UpdateBars;
    end);
end;

procedure TDesignerBarState.ToggleNonVisual;
var
  mAction: TContainedAction;
begin
  mAction := FindNonVisualAction;
  if mAction = nil then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNonVisualMissing));
    Exit;
  end;
  mAction.Update;
  if (mAction is TCustomAction) and not TCustomAction(mAction).Enabled then
  begin
    Exit;
  end;
  mAction.Execute;
end;

procedure TDesignerBarState.ToggleTabOrder;
begin
  FTabOrder := not FTabOrder;
  FTabClicks.Reset;
  if FTabOrder then
  begin
    UpdateOverlay;
  end
  else
  begin
    HideOverlay;
  end;
end;

procedure TDesignerBarState.HideOverlay;
begin
  if FOverlay <> nil then
  begin
    FOverlay.HideOverlay;
  end;
end;

procedure TDesignerBarState.UpdateOverlay;
var
  mEditor: IOTAFormEditor;
  mForm: TWinControl;
  mScreen, mVisible: TRect;
  mStops: TArray<TAtlasTabStop>;
begin
  if not FTabOrder or not OverlayForm(mEditor, mForm) then
  begin
    HideOverlay;
    Exit;
  end;
  // Anderes Formular: Klicks zählen wieder ab 0.
  if not SameText(mEditor.FileName, FTabFile) then
  begin
    FTabFile := mEditor.FileName;
    FTabClicks.Reset;
  end;
  mStops := TabStopsOf(mForm);
  if not VisibleArea(mForm, mScreen, mVisible) then
  begin
    HideOverlay;
    Exit;
  end;
  EnsureOverlay;
  FOverlay.Clickable := TAtlasIdeSettings.Current.DesignerTabOrderClick;
  FOverlay.SetBadges(BadgesOf(mStops, mScreen, mVisible));
  if not FOverlay.Shown or (FOverlay.BoundsRect <> mVisible) then
  begin
    FOverlay.ShowAt(mVisible);
  end;
end;

procedure TDesignerBarState.EnsureOverlay;
begin
  if FOverlay <> nil then
  begin
    Exit;
  end;
  FOverlay := TAtlasTabOrderOverlay.CreateOverlay(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  FOverlay.OnBadgeClick :=
    procedure(AName: string)
    var
      mName: string;
    begin
      mName := AName;
      TAtlasGuard.Run(TAtlasFeature.DesignerBar,
        procedure
        begin
          TabBadgeClicked(mName);
        end);
    end;
end;

procedure TDesignerBarState.TabBadgeClicked(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mOrder: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerTabOrderClick or not CurrentDesigner(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(AName);
  mDesigner := DesignerOf(mEditor);
  if not (mComponent is TWinControl) or (mDesigner = nil) then
  begin
    Exit;
  end;
  mOrder := FTabClicks.Next(ParentNameOf(TWinControl(mComponent), mRoot));
  // Der Setter der VCL schiebt die übrigen Geschwister weiter: Der Zähler je Elternelement genügt.
  TWinControl(mComponent).TabOrder := mOrder;
  mDesigner.Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerBarTabOrderSet,
    [AName, TWinControl(mComponent).TabOrder]));
  UpdateOverlay;
end;

/// <summary>Optionen des Suchfensters: Formular, gemerkte Wahl und die erste Auswahl im Designer.</summary>
function TDesignerBarState.SearchOptions(const AEditor: IOTAFormEditor;
  ARoot: TComponent): TAtlasComponentSearchOptions;
var
  mSelected: TArray<TComponent>;
begin
  Result := FSearchChoice;
  Result.Compact := SameText(TAtlasIdeSettings.Current.DesignerSearchStyle,
    TAtlasPluginSettings.cDesignerSearchPopup);
  Result.FormName := ARoot.Name;
  Result.FormBounds := TRect.Empty;
  if ARoot is TWinControl then
  begin
    Result.FormBounds := Rect(0, 0, TWinControl(ARoot).ClientWidth, TWinControl(ARoot).ClientHeight);
  end;
  Result.Current := '';
  mSelected := SelectionOf(AEditor, ARoot);
  if Length(mSelected) > 0 then
  begin
    Result.Current := mSelected[0].Name;
  end;
end;

/// <summary>Eigene Methode, damit die anonymen Methoden nur das Fenster und ACompact fangen.</summary>
procedure TDesignerBarState.WireSearch(AWindow: TAtlasComponentSearchWindow; ACompact: Boolean);
var
  mWindow: TAtlasComponentSearchWindow;
  mCompact: Boolean;
begin
  mWindow := AWindow;
  mCompact := ACompact;
  mWindow.OnAction :=
    procedure(AAction: TAtlasComponentSearchAction; const AItem: TAtlasDesignerItem)
    var
      mItem: TAtlasDesignerItem;
    begin
      mItem := AItem;
      if TAtlasIdeDesignerBar.FState = nil then
      begin
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.DesignerBar,
        procedure
        begin
          SearchAction(AAction, mItem);
        end);
    end;
  mWindow.OnClosed :=
    procedure
    begin
      if (TAtlasIdeDesignerBar.FState = nil) or (State.FSearch <> mWindow) then
      begin
        Exit;
      end;
      // Wahl merken bis zum Ende der Sitzung.
      State.FSearchChoice.Kind := mWindow.Kind;
      State.FSearchChoice.Fields := mWindow.Fields;
      if not mCompact then
      begin
        State.FSearchChoice.Grouping := mWindow.Grouping;
        State.FSearchChoice.Preview := mWindow.PreviewVisible;
        State.FSearchChoice.Bounds := mWindow.BoundsRect;
      end;
      State.FSearch := nil;
    end;
end;

procedure TDesignerBarState.OpenSearch;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mOptions: TAtlasComponentSearchOptions;
  mArea: TRect;
  mWindow: TAtlasComponentSearchWindow;
begin
  if not CurrentDesigner(mEditor, mRoot) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchNoForm));
    Exit;
  end;
  // Schon offen: neu aufbauen, das Formular kann ein anderes sein.
  CloseSearch;
  mOptions := SearchOptions(mEditor, mRoot);
  mWindow := TAtlasComponentSearchWindow.CreateSearch(nil, mOptions, ItemsOf(mRoot, DesignerOf(mEditor)),
    TAtlasIdeStyle.Colors);
  FSearch := mWindow;
  WireSearch(mWindow, mOptions.Compact);
  mArea := Screen.WorkAreaRect;
  if mRoot is TWinControl then
  begin
    mArea := Screen.MonitorFromWindow(TWinControl(mRoot).Handle).WorkareaRect;
  end;
  mWindow.ShowOver(mArea);
end;

procedure TDesignerBarState.CloseSearch;
var
  mWindow: TAtlasComponentSearchWindow;
begin
  if FSearch = nil then
  begin
    Exit;
  end;
  mWindow := FSearch;
  FSearch := nil;
  mWindow.OnClosed := nil;
  mWindow.OnAction := nil;
  mWindow.Free;
end;

procedure TDesignerBarState.Later(const AAction: TProc);
var
  mOwner: TDesignerBarState;
  mAction: TProc;
begin
  mOwner := Self;
  mAction := AAction;
  TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
    procedure
    begin
      if TAtlasIdeDesignerBar.FState <> mOwner then
      begin
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.DesignerBar, mAction);
    end);
end;

{ TAtlasIdeDesignerBar }

class procedure TAtlasIdeDesignerBar.Install(const AHooks: THooks);
begin
  FreeAndNil(FState);
  FHooks := AHooks;
  FState := TDesignerBarState.Create;
end;

class procedure TAtlasIdeDesignerBar.Uninstall;
begin
  FreeAndNil(FState);
  FHooks := Default(THooks);
end;

class procedure TAtlasIdeDesignerBar.ApplySettings;
begin
  if FState <> nil then
  begin
    State.Reset;
  end;
end;

class procedure TAtlasIdeDesignerBar.ThemeChanged;
begin
  if FState <> nil then
  begin
    State.ApplyTheme;
  end;
end;

end.
