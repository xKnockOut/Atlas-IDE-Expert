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
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.Search,
  Atlas.UI.Designer.TabOverlay,
  Atlas.IDE.Foundation.DesignerView,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Foundation.Settings;

const
  TickMs = 200;
  KeyPriority = 50;
  IdSearch = 'search';
  IdNonVisual = 'nonVisual';
  IdParent = 'parent';
  IdTabOrder = 'tabOrder';
  IdAlign = 'align';
  /// <summary>Aktion der IDE hinter Strg+H im Designer.</summary>
  NonVisualAction = 'ToggleNonVisualComponentVisibilityCommand';
  /// <summary>Eigenschaften für die Vorschau im Suchfenster, sofern gesetzt.</summary>
  PreviewProperties: array[0..9] of string = ('Caption', 'Text', 'Align', 'Visible', 'Enabled', 'TabOrder', 'Hint',
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
    FSearchKind: TAtlasDesignerKind;
    FSearchFields: TAtlasDesignerFields;
    FSearchGrouping: TAtlasDesignerGrouping;
    FSearchPreview: Boolean;
    FSearchBounds: TRect;
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
    procedure Place(ABar: TAtlasDesignerBar; AEditorParent: TWinControl);
    function Current(out AEditor: IOTAFormEditor; out ARoot: TComponent): Boolean;
    function Buttons: TArray<TAtlasDesignerButton>;
    procedure UpdateBars;
    procedure UpdateKeyClient;
    procedure Command(const AId: string);
    procedure ShowMenu(const AId: string; const APoint: TPoint);
    function FindNonVisualAction: TContainedAction;
    procedure ToggleNonVisual;
    procedure SelectParent;
    function Selection(const AEditor: IOTAFormEditor; ARoot: TComponent): TArray<TComponent>;
    procedure ToggleTabOrder;
    procedure UpdateOverlay;
    procedure HideOverlay;
    procedure TabBadgeClicked(const AName: string);
    procedure AlignSelection(AKind: TAtlasAlignKind);
    function AlignCaption(AKind: TAtlasAlignKind): string;
    procedure AlignMenuClick(Sender: TObject);
    function ItemsOf(ARoot: TComponent; const ADesigner: IDesigner): TArray<TAtlasDesignerItem>;
    procedure SearchAction(AAction: TAtlasComponentSearchAction; const AItem: TAtlasDesignerItem);
    procedure CloseSearch;
    procedure Later(const AAction: TProc);
    procedure Say(const AText: string);
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
    Result := TAtlasIdeStyle.ChromeColors
  else
    Result := TAtlasIdeStyle.Colors;
end;

function DesignerOf(const AEditor: IOTAFormEditor): IDesigner;
var
  mNative: INTAFormEditor;
begin
  Result := nil;
  if Supports(AEditor, INTAFormEditor, mNative) then
    Result := mNative.FormDesigner;
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
      Exit(True);
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
    Exit;
  mTopLeft := AControl.BoundsRect.TopLeft;
  if mParent <> ARoot then
  begin
    if not ARoot.ContainsControl(mParent) then
      Exit;
    mTopLeft := mParent.ClientToParent(mTopLeft, ARoot);
  end;
  Result := Rect(mTopLeft.X, mTopLeft.Y, mTopLeft.X + AControl.Width, mTopLeft.Y + AControl.Height);
end;

function ParentNameOf(AControl: TControl; ARoot: TComponent): string;
begin
  Result := '';
  if (AControl.Parent <> nil) and (AControl.Parent <> ARoot) then
    Result := AControl.Parent.Name;
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
    Exit(False);
  case mInfo^.PropType^.Kind of
    tkClass:
      begin
        mObject := GetObjectProp(AComponent, mInfo);
        if mObject is TComponent then
          AText := TComponent(mObject).Name;
      end;
    tkInteger, tkInt64, tkEnumeration, tkFloat, tkSet, tkChar, tkWChar, tkString, tkLString, tkUString, tkWString:
      AText := VarToStr(GetPropValue(AComponent, mInfo, True));
  end;
  Result := AText <> '';
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
    Exit;
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
  FSearchKind := TAtlasDesignerKind.All;
  FSearchFields := [TAtlasDesignerField.Name, TAtlasDesignerField.Caption, TAtlasDesignerField.ClassName];
  FSearchGrouping := TAtlasDesignerGrouping.Hierarchy;
  FSearchPreview := True;
  FLastAlign := TAtlasAlignKind.Lefts;
  FHost := TAtlasEditorBarHost.Create('Designer-Leiste', TAtlasFeature.DesignerBar,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateBar;
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      Place(TAtlasDesignerBar(ABar), AEditorParent);
    end);
  FHost.ShowIn := TAtlasEditorBarView.Designer;
  FAlignMenu := TPopupMenu.Create(nil);
  FKeyClient := TSearchKeyClient.Create(KeyPriority);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
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
    FOverlay.ApplyColors(TAtlasIdeStyle.Colors);
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

procedure TDesignerBarState.Place(ABar: TAtlasDesignerBar; AEditorParent: TWinControl);
begin
  if ABar.Parent = AEditorParent then
    Exit;
  // Über dem Designer: zuerst ganz oben einhängen, dann oben ausrichten.
  ABar.Top := 0;
  ABar.Align := alTop;
  ABar.Parent := AEditorParent;
end;

function TDesignerBarState.Current(out AEditor: IOTAFormEditor; out ARoot: TComponent): Boolean;
begin
  AEditor := TAtlasIdeDesignerView.CurrentFormEditor;
  ARoot := TAtlasIdeDesignerView.RootOf(AEditor);
  Result := (AEditor <> nil) and (ARoot <> nil);
end;

function TDesignerBarState.FindNonVisualAction: TContainedAction;
var
  mServices: INTAServices;
  mList: TCustomActionList;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
    Exit;
  mList := mServices.ActionList;
  // Gemerkter Index: Die Liste hat Tausende Einträge, der Takt fragt fünfmal je Sekunde.
  if (FActionIndex >= 0) and (FActionIndex < mList.ActionCount) and
    SameText(mList.Actions[FActionIndex].Name, NonVisualAction) then
    Exit(mList.Actions[FActionIndex]);
  FActionIndex := -1;
  for mIndex := 0 to mList.ActionCount - 1 do
    if SameText(mList.Actions[mIndex].Name, NonVisualAction) then
    begin
      FActionIndex := mIndex;
      Exit(mList.Actions[mIndex]);
    end;
  if not FActionLogged then
  begin
    FActionLogged := True;
    TAtlasGuard.Log('Designer-Leiste: IDE-Aktion ' + NonVisualAction + ' nicht gefunden');
  end;
end;

function TDesignerBarState.AlignCaption(AKind: TAtlasAlignKind): string;
begin
  case AKind of
    TAtlasAlignKind.Rights: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignRights);
    TAtlasAlignKind.Tops: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignTops);
    TAtlasAlignKind.Bottoms: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignBottoms);
    TAtlasAlignKind.CentersH: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignCentersH);
    TAtlasAlignKind.CentersV: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignCentersV);
    TAtlasAlignKind.CenterInParentH: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignCenterInParentH);
    TAtlasAlignKind.CenterInParentV: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignCenterInParentV);
    TAtlasAlignKind.SameWidth: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignSameWidth);
    TAtlasAlignKind.SameHeight: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignSameHeight);
    TAtlasAlignKind.SpaceH: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignSpaceH);
    TAtlasAlignKind.SpaceV: Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignSpaceV);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.DesignerAlignLefts);
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
    mHint := mHint + ' (' + ShortCutToText(TShortCut(mSettings.DesignerSearchKey)) + ')';
  Result := TArray<TAtlasDesignerButton>.Create(TAtlasDesignerButton.Create(IdSearch,
    TAtlasToolbarIcon.ComponentSearch, mHint));
  mButton := TAtlasDesignerButton.Create(IdNonVisual, TAtlasToolbarIcon.NonVisual,
    TAtlasStrings.Text(TAtlasTextId.DesignerBarNonVisualHint));
  mAction := FindNonVisualAction;
  if mAction = nil then
  begin
    mButton.Enabled := False;
    mButton.Hint := TAtlasStrings.Text(TAtlasTextId.DesignerBarNonVisualMissing);
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
        mButton.Icon := TAtlasToolbarIcon.NonVisualHidden;
    end;
  end;
  Result := Result + [mButton];
  mButton := TAtlasDesignerButton.Create(IdParent, TAtlasToolbarIcon.SelectParent,
    TAtlasStrings.Text(TAtlasTextId.DesignerBarParentHint));
  mButton.GapBefore := True;
  Result := Result + [mButton];
  if mSettings.DesignerTabOrderClick then
    mHint := TAtlasStrings.Text(TAtlasTextId.DesignerBarTabOrderClickHint)
  else
    mHint := TAtlasStrings.Text(TAtlasTextId.DesignerBarTabOrderHint);
  mButton := TAtlasDesignerButton.Create(IdTabOrder, TAtlasToolbarIcon.TabOrder, mHint);
  mButton.Pressed := FTabOrder;
  Result := Result + [mButton];
  if mSettings.DesignerAlign then
  begin
    mButton := TAtlasDesignerButton.Create(IdAlign, TAtlasToolbarIcon.AlignControls,
      TAtlasStrings.Fmt(TAtlasTextId.DesignerBarAlignHint, [AlignCaption(FLastAlign)]));
    mButton.Menu := True;
    Result := Result + [mButton];
  end;
end;

procedure TDesignerBarState.UpdateBars;
var
  mButtons: TArray<TAtlasDesignerButton>;
begin
  if FHost.Count = 0 then
    Exit;
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
    TAtlasKeyHook.Add(FKeyClient)
  else
    TAtlasKeyHook.Remove(FKeyClient);
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
      FHost.Clear;
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
  if SameText(AId, IdSearch) then
    OpenSearch
  else if SameText(AId, IdNonVisual) then
    ToggleNonVisual
  else if SameText(AId, IdParent) then
    SelectParent
  else if SameText(AId, IdTabOrder) then
    ToggleTabOrder
  else if SameText(AId, IdAlign) then
    AlignSelection(FLastAlign);
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
  if not SameText(AId, IdAlign) or not Current(mEditor, mRoot) then
    Exit;
  mCount := Length(Selection(mEditor, mRoot));
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
    Say(TAtlasStrings.Text(TAtlasTextId.DesignerBarNonVisualMissing));
    Exit;
  end;
  mAction.Update;
  if (mAction is TCustomAction) and not TCustomAction(mAction).Enabled then
    Exit;
  mAction.Execute;
end;

function TDesignerBarState.Selection(const AEditor: IOTAFormEditor; ARoot: TComponent): TArray<TComponent>;
var
  mDesigner: IDesigner;
  mList: IDesignerSelections;
  mIndex: Integer;
  mItem: TPersistent;
begin
  Result := nil;
  mDesigner := DesignerOf(AEditor);
  if mDesigner = nil then
    Exit;
  mList := CreateSelectionList;
  mDesigner.GetSelections(mList);
  for mIndex := 0 to mList.Count - 1 do
  begin
    mItem := mList[mIndex];
    if (mItem is TComponent) and (mItem <> ARoot) and (TComponent(mItem).Owner = ARoot) then
      Result := Result + [TComponent(mItem)];
  end;
end;

procedure TDesignerBarState.SelectParent;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mDesigner: IDesigner;
begin
  if not Current(mEditor, mRoot) then
    Exit;
  mDesigner := DesignerOf(mEditor);
  mSelected := Selection(mEditor, mRoot);
  if (mDesigner = nil) or (Length(mSelected) = 0) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.DesignerBarNoSelection));
    Exit;
  end;
  if not (mSelected[0] is TControl) or (TControl(mSelected[0]).Parent = nil) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.DesignerBarNoParent));
    Exit;
  end;
  mDesigner.SelectComponent(TControl(mSelected[0]).Parent);
end;

procedure TDesignerBarState.ToggleTabOrder;
begin
  FTabOrder := not FTabOrder;
  FTabClicks.Reset;
  if FTabOrder then
    UpdateOverlay
  else
    HideOverlay;
end;

procedure TDesignerBarState.HideOverlay;
begin
  if FOverlay <> nil then
    FOverlay.HideOverlay;
end;

procedure TDesignerBarState.UpdateOverlay;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mForm: TWinControl;
  mIndex: Integer;
  mComponent: TComponent;
  mControl: TWinControl;
  mStops: TArray<TAtlasTabStop>;
  mOut: TArray<Boolean>;
  mBadges: TArray<TAtlasTabBadge>;
  mOrigin: TPoint;
  mScreen, mVisible: TRect;
  mHost: HWND;
begin
  if not FTabOrder or not Application.Active or not Current(mEditor, mRoot) or not (mRoot is TWinControl) or
    not TWinControl(mRoot).HandleAllocated or not IsWindowVisible(TWinControl(mRoot).Handle) then
  begin
    HideOverlay;
    Exit;
  end;
  mForm := TWinControl(mRoot);
  // Anderes Formular: Klicks zählen wieder ab 0.
  if not SameText(mEditor.FileName, FTabFile) then
  begin
    FTabFile := mEditor.FileName;
    FTabClicks.Reset;
  end;
  mStops := nil;
  for mIndex := 0 to mForm.ComponentCount - 1 do
  begin
    mComponent := mForm.Components[mIndex];
    if not (mComponent is TWinControl) or (mComponent.Name = '') then
      Continue;
    mControl := TWinControl(mComponent);
    if (mControl.Parent = nil) or not (mControl.TabStop or (csAcceptsControls in mControl.ControlStyle)) then
      Continue;
    mStops := mStops + [TAtlasTabStop.Create(mControl.Name, ParentNameOf(mControl, mForm), mControl.TabOrder,
      BoundsInRoot(mControl, mForm))];
  end;
  mOut := TAtlasTabOrder.OutOfOrder(mStops);
  // Nur der sichtbare Teil des Formulars (der Designer kann es abschneiden oder scrollen).
  mOrigin := mForm.ClientToScreen(Point(0, 0));
  mScreen := Rect(mOrigin.X, mOrigin.Y, mOrigin.X + mForm.ClientWidth, mOrigin.Y + mForm.ClientHeight);
  mHost := GetParent(mForm.Handle);
  mVisible := mScreen;
  if (mHost <> 0) and GetWindowRect(mHost, mVisible) then
    mVisible.Intersect(mScreen)
  else
    mVisible := mScreen;
  if mVisible.IsEmpty then
  begin
    HideOverlay;
    Exit;
  end;
  mBadges := nil;
  for mIndex := 0 to High(mStops) do
    mBadges := mBadges + [TAtlasTabBadge.Create(mStops[mIndex].Name, mStops[mIndex].TabOrder, mOut[mIndex],
      Point(mStops[mIndex].Bounds.Left + mScreen.Left - mVisible.Left,
      mStops[mIndex].Bounds.Top + mScreen.Top - mVisible.Top))];
  if FOverlay = nil then
  begin
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
  FOverlay.Clickable := TAtlasIdeSettings.Current.DesignerTabOrderClick;
  FOverlay.SetBadges(mBadges);
  if not FOverlay.Shown or (FOverlay.BoundsRect <> mVisible) then
    FOverlay.ShowAt(mVisible);
end;

procedure TDesignerBarState.TabBadgeClicked(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mOrder: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerTabOrderClick or not Current(mEditor, mRoot) then
    Exit;
  mComponent := mRoot.FindComponent(AName);
  mDesigner := DesignerOf(mEditor);
  if not (mComponent is TWinControl) or (mDesigner = nil) then
    Exit;
  mOrder := FTabClicks.Next(ParentNameOf(TWinControl(mComponent), mRoot));
  // Der Setter der VCL schiebt die übrigen Geschwister weiter: Der Zähler je Elternelement genügt.
  TWinControl(mComponent).TabOrder := mOrder;
  mDesigner.Modified;
  Say(TAtlasStrings.Fmt(TAtlasTextId.DesignerBarTabOrderSet, [AName, TWinControl(mComponent).TabOrder]));
  UpdateOverlay;
end;

procedure TDesignerBarState.AlignSelection(AKind: TAtlasAlignKind);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mSelected: TArray<TComponent>;
  mControls: TArray<TControl>;
  mRects, mNew: TArray<TRect>;
  mComponent: TComponent;
  mParent: TWinControl;
  mIndex: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerAlign or not Current(mEditor, mRoot) then
    Exit;
  mDesigner := DesignerOf(mEditor);
  if mDesigner = nil then
    Exit;
  mSelected := Selection(mEditor, mRoot);
  mControls := nil;
  mParent := nil;
  for mComponent in mSelected do
    if mComponent is TControl then
    begin
      if mParent = nil then
        mParent := TControl(mComponent).Parent;
      // Nur Geschwister: Lagen in verschiedenen Elternelementen sind nicht vergleichbar.
      if TControl(mComponent).Parent = mParent then
        mControls := mControls + [TControl(mComponent)];
    end;
  if (mParent = nil) or not TAtlasDesignerAlign.Applicable(AKind, Length(mControls)) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.DesignerBarAlignNeeds));
    Exit;
  end;
  SetLength(mRects, Length(mControls));
  for mIndex := 0 to High(mControls) do
    mRects[mIndex] := mControls[mIndex].BoundsRect;
  mNew := TAtlasDesignerAlign.Apply(AKind, mRects, mParent.ClientRect);
  for mIndex := 0 to High(mControls) do
    if mNew[mIndex] <> mRects[mIndex] then
      mControls[mIndex].BoundsRect := mNew[mIndex];
  mDesigner.Modified;
end;

function TDesignerBarState.ItemsOf(ARoot: TComponent; const ADesigner: IDesigner): TArray<TAtlasDesignerItem>;
var
  mIndex, mProp, mCount: Integer;
  mComponent: TComponent;
  mItem: TAtlasDesignerItem;
  mName, mText: string;
  mList: PPropList;
  mMethod: TMethod;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    if mComponent.Name = '' then
      Continue;
    mItem := TAtlasDesignerItem.Create(mComponent.Name, mComponent.ClassName, mComponent is TControl);
    if mComponent is TControl then
    begin
      mItem.Container := (mComponent is TWinControl) and
        (csAcceptsControls in TControl(mComponent).ControlStyle);
      mItem.ParentName := ParentNameOf(TControl(mComponent), ARoot);
      if ARoot is TWinControl then
        mItem.Bounds := BoundsInRoot(TControl(mComponent), TWinControl(ARoot));
    end;
    if PropText(mComponent, 'Caption', mText) or PropText(mComponent, 'Text', mText) then
      mItem.Caption := mText;
    for mName in PreviewProperties do
      if PropText(mComponent, mName, mText) then
      begin
        // Vorgaben zeigen nichts Neues.
        if (SameText(mName, 'Align') and SameText(mText, 'alNone')) or
          ((SameText(mName, 'Visible') or SameText(mName, 'Enabled')) and SameText(mText, 'True')) then
          Continue;
        mItem.Properties := mItem.Properties + [mName + ' = ' + mText];
      end;
    if ADesigner <> nil then
    begin
      mCount := GetPropList(PTypeInfo(mComponent.ClassInfo), [tkMethod], nil);
      if mCount > 0 then
      begin
        GetMem(mList, mCount * SizeOf(PPropInfo));
        try
          GetPropList(PTypeInfo(mComponent.ClassInfo), [tkMethod], mList);
          for mProp := 0 to mCount - 1 do
          begin
            mMethod := GetMethodProp(mComponent, mList^[mProp]);
            if mMethod.Code = nil then
              Continue;
            mText := ADesigner.GetMethodName(mMethod);
            if mText <> '' then
              mItem.Events := mItem.Events + [string(mList^[mProp]^.Name) + ' = ' + mText];
          end;
        finally
          FreeMem(mList);
        end;
      end;
    end;
    Result := Result + [mItem];
  end;
end;

procedure TDesignerBarState.OpenSearch;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mOptions: TAtlasComponentSearchOptions;
  mSelected: TArray<TComponent>;
  mArea: TRect;
  mWindow: TAtlasComponentSearchWindow;
begin
  if not Current(mEditor, mRoot) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.DesignerSearchNoForm));
    Exit;
  end;
  // Schon offen: neu aufbauen, das Formular kann ein anderes sein.
  CloseSearch;
  mDesigner := DesignerOf(mEditor);
  mOptions := Default(TAtlasComponentSearchOptions);
  mOptions.Compact := SameText(TAtlasIdeSettings.Current.DesignerSearchStyle,
    TAtlasPluginSettings.DesignerSearchPopup);
  mOptions.FormName := mRoot.Name;
  if mRoot is TWinControl then
    mOptions.FormBounds := Rect(0, 0, TWinControl(mRoot).ClientWidth, TWinControl(mRoot).ClientHeight);
  mOptions.Kind := FSearchKind;
  mOptions.Fields := FSearchFields;
  mOptions.Grouping := FSearchGrouping;
  mOptions.Preview := FSearchPreview;
  mOptions.Bounds := FSearchBounds;
  mSelected := Selection(mEditor, mRoot);
  if Length(mSelected) > 0 then
    mOptions.Current := mSelected[0].Name;
  mWindow := TAtlasComponentSearchWindow.CreateSearch(nil, mOptions, ItemsOf(mRoot, mDesigner),
    TAtlasIdeStyle.Colors);
  FSearch := mWindow;
  mWindow.OnAction :=
    procedure(AAction: TAtlasComponentSearchAction; const AItem: TAtlasDesignerItem)
    var
      mItem: TAtlasDesignerItem;
    begin
      mItem := AItem;
      if TAtlasIdeDesignerBar.FState = nil then
        Exit;
      TAtlasGuard.Run(TAtlasFeature.DesignerBar,
        procedure
        begin
          State.SearchAction(AAction, mItem);
        end);
    end;
  mWindow.OnClosed :=
    procedure
    begin
      if (TAtlasIdeDesignerBar.FState = nil) or (State.FSearch <> mWindow) then
        Exit;
      // Wahl merken bis zum Ende der Sitzung.
      State.FSearchKind := mWindow.Kind;
      State.FSearchFields := mWindow.Fields;
      if not mOptions.Compact then
      begin
        State.FSearchGrouping := mWindow.Grouping;
        State.FSearchPreview := mWindow.PreviewVisible;
        State.FSearchBounds := mWindow.BoundsRect;
      end;
      State.FSearch := nil;
    end;
  mArea := Screen.WorkAreaRect;
  if mRoot is TWinControl then
    mArea := Screen.MonitorFromWindow(TWinControl(mRoot).Handle).WorkareaRect;
  mWindow.ShowOver(mArea);
end;

procedure TDesignerBarState.CloseSearch;
var
  mWindow: TAtlasComponentSearchWindow;
begin
  if FSearch = nil then
    Exit;
  mWindow := FSearch;
  FSearch := nil;
  mWindow.OnClosed := nil;
  mWindow.OnAction := nil;
  mWindow.Free;
end;

procedure TDesignerBarState.SearchAction(AAction: TAtlasComponentSearchAction; const AItem: TAtlasDesignerItem);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mEvent, mMethod: string;
  mPos: Integer;
begin
  if not Current(mEditor, mRoot) then
    Exit;
  mComponent := mRoot.FindComponent(AItem.Name);
  mDesigner := DesignerOf(mEditor);
  // Umbenannt oder gelöscht, seit das Fenster offen ist.
  if (mComponent = nil) or (mDesigner = nil) then
    Exit;
  if AAction = TAtlasComponentSearchAction.Select then
  begin
    mDesigner.SelectComponent(mComponent);
    Exit;
  end;
  if (AAction <> TAtlasComponentSearchAction.Event) or (Length(AItem.Events) = 0) then
    Exit;
  // OnClick, sonst das erste belegte Ereignis.
  mEvent := AItem.Events[0];
  for mMethod in AItem.Events do
    if mMethod.StartsWith('OnClick ', True) then
      mEvent := mMethod;
  mPos := Pos(' = ', mEvent);
  if mPos = 0 then
    Exit;
  mMethod := Copy(mEvent, mPos + 3, MaxInt);
  mDesigner.SelectComponent(mComponent);
  if mDesigner.MethodExists(mMethod) then
    mDesigner.ShowMethod(mMethod);
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
        Exit;
      TAtlasGuard.Run(TAtlasFeature.DesignerBar, mAction);
    end);
end;

procedure TDesignerBarState.Say(const AText: string);
begin
  TAtlasGuard.Log('Designer-Leiste: ' + AText);
  if Assigned(TAtlasIdeDesignerBar.FHooks.Message) then
    TAtlasIdeDesignerBar.FHooks.Message(AText);
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
    State.Reset;
end;

class procedure TAtlasIdeDesignerBar.ThemeChanged;
begin
  if FState <> nil then
    State.ApplyTheme;
end;

end.
