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
// - Tab-Reihenfolge (#603): Marken mit der TabOrder über den
//   Steuerelementen, Menü mit „Reihenfolge klicken“, „Nach Lesereihenfolge
//   sortieren“ und Rückgängig (TAtlasIdeDesignerTabOrder).
// - Ausrichten (experimentell, editor.designerBar.align): Menü am Pfeil,
//   Klick auf das Symbol wiederholt den letzten Befehl (TAtlasDesignerAlign).
// - Gleiche auswählen (#738, designer.selectSimilar): Menü mit Trefferzahlen
//   (TAtlasIdeDesignerSelect); Pfeil und Symbol öffnen es. Darin die
//   Auswahlsätze (#739, designer.selectionSets) samt ihren Tasten; dazu die
//   räumliche Navigation mit Alt+Pfeil (#745, designer.spatialNavigation)
//   und das Menü „Anordnen“ (#730 ff.), alles über TAtlasIdeDesignerCommands.
// - Werkzeuge mit eigenem Knopf (#734 ff.), ebenfalls über
//   TAtlasIdeDesignerCommands: Symbol schaltet, Pfeil öffnet das Menü.
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
  System.Classes,
  System.Types,
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
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.Commands,
  Atlas.IDE.Designer.SearchItems,
  Atlas.IDE.Designer.TabOrder,
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
  cIdAlign = 'align';
  /// <summary>Aktion der IDE hinter Strg+H im Designer.</summary>
  cNonVisualAction = 'ToggleNonVisualComponentVisibilityCommand';

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
    FTabOrder: TAtlasIdeDesignerTabOrder;
    FAlignMenu: TPopupMenu;
    FCommands: TAtlasIdeDesignerCommands;
    FLastAlign: TAtlasAlignKind;
    FActionIndex: Integer;
    FActionLogged: Boolean;
    procedure Tick(Sender: TObject);
    function CreateBar: TAtlasDesignerBar;
    function Buttons: TArray<TAtlasDesignerButton>;
    function NonVisualButton: TAtlasDesignerButton;
    function ToolButtons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
    procedure UpdateBars;
    procedure UpdateKeyClient;
    procedure Command(const AId: string);
    procedure ShowMenu(const AId: string; const APoint: TPoint);
    function FindNonVisualAction: TContainedAction;
    procedure ToggleNonVisual;
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

procedure SelectParent;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mDesigner: IDesigner;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
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
  if not TAtlasIdeSettings.Current.DesignerAlign or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if mDesigner = nil then
  begin
    Exit;
  end;
  mControls := SiblingControls(TAtlasDesignerAccess.Selection(mEditor, mRoot), mParent);
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
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(AItem.Name);
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
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
  Result := (mKey <> 0) and (ShortCut(AKey, AShift) = TShortCut(mKey)) and TAtlasDesignerAccess.Focused;
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
  FCommands := TAtlasIdeDesignerCommands.Create(
    procedure(AText: string)
    begin
      Say(AText);
    end);
  FTabOrder := TAtlasIdeDesignerTabOrder.Create(
    procedure(AText: string)
    begin
      Say(AText);
    end);
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
  FTabOrder.Free;
  FAlignMenu.Free;
  FCommands.Free;
  FHost.Free;
  inherited Destroy;
end;

procedure TDesignerBarState.Reset;
begin
  if not TAtlasIdeSettings.Current.EditorDesignerBar then
  begin
    FHost.Clear;
    FTabOrder.Hide;
    CloseSearch;
  end;
  UpdateKeyClient;
  ApplyTheme;
end;

procedure TDesignerBarState.ApplyTheme;
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasIdeStyle.BarColors;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasDesignerBar(ABar).ApplyColors(mColors);
    end);
  FTabOrder.ApplyTheme;
  FCommands.ApplyTheme;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable. Einordnen und Wächter: Host.</summary>
function TDesignerBarState.CreateBar: TAtlasDesignerBar;
var
  mBar: TAtlasDesignerBar;
  mHost: TAtlasEditorBarHost;
begin
  mBar := TAtlasDesignerBar.Create(nil);
  mHost := FHost;
  mBar.ApplyColors(TAtlasIdeStyle.BarColors);
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
      mPoint: TPoint;
    begin
      mId := AId;
      // Knöpfe nur mit Menü: Auch ein Klick auf das Symbol öffnet es, unter dem Knopf.
      if FCommands.Handles(mId) then
      begin
        mPoint := mBar.ClientToScreen(Point(mBar.ButtonRect(mId).Left, mBar.ButtonRect(mId).Bottom));
        Later(
          procedure
          begin
            ShowMenu(mId, mPoint);
          end);
        Exit;
      end;
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
  Result := Result + [NonVisualButton];
  mButton := TAtlasDesignerButton.Create(cIdParent, TAtlasToolbarIcon.SelectParent,
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarParentHint));
  mButton.GapBefore := True;
  Result := Result + [mButton];
  Result := Result + [FTabOrder.Button(mSettings)] + ToolButtons(mSettings);
end;

function TDesignerBarState.NonVisualButton: TAtlasDesignerButton;
var
  mAction: TContainedAction;
begin
  Result := TAtlasDesignerButton.Create(cIdNonVisual, TAtlasToolbarIcon.NonVisual,
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNonVisualHint));
  mAction := FindNonVisualAction;
  if mAction = nil then
  begin
    Result.Enabled := False;
    Result.Hint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNonVisualMissing);
    Exit;
  end;
  mAction.Update;
  if mAction is TCustomAction then
  begin
    Result.Enabled := TCustomAction(mAction).Enabled;
    Result.Pressed := TCustomAction(mAction).Checked;
    // Wie im Mockup: ausgeblendet = durchgestrichenes Auge.
    if Result.Pressed then
    begin
      Result.Icon := TAtlasToolbarIcon.NonVisualHidden;
    end;
  end;
end;

/// <summary>Knöpfe mit Menü für die Auswahl: Gleiche auswählen, Anordnen, Ausrichten.</summary>
function TDesignerBarState.ToolButtons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
var
  mButton: TAtlasDesignerButton;
begin
  Result := FCommands.Buttons(ASettings);
  if ASettings.DesignerAlign then
  begin
    mButton := TAtlasDesignerButton.Create(cIdAlign, TAtlasToolbarIcon.AlignControls,
      TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerBarAlignHint, [AlignCaption(FLastAlign)]));
    mButton.Menu := True;
    Result := Result + [mButton];
  end;
  if Length(Result) > 0 then
  begin
    Result[0].GapBefore := True;
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
    (TAtlasIdeSettings.Current.DesignerSearchKey <> 0) and TAtlasDesignerAccess.Shown;
  if mWanted then
  begin
    TAtlasKeyHook.Add(FKeyClient);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeyClient);
  end;
  mWanted := FHost.Guard and TAtlasIdeSettings.Current.EditorDesignerBar and TAtlasDesignerAccess.Shown;
  FCommands.UpdateKeys(mWanted);
  FTabOrder.UpdateKeys(mWanted);
end;

procedure TDesignerBarState.Tick(Sender: TObject);
begin
  // Sicherung ausgelöst: Leisten weg, bis die Funktion wieder eingeschaltet ist.
  if not FHost.Guard then
  begin
    TAtlasKeyHook.Remove(FKeyClient);
    FTabOrder.Hide;
    FCommands.Hide;
    Exit;
  end;
  if not TAtlasIdeSettings.Current.EditorDesignerBar then
  begin
    TAtlasKeyHook.Remove(FKeyClient);
    FTabOrder.Hide;
    FCommands.Hide;
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
      FTabOrder.Update;
      FCommands.Tick;
    end);
end;

procedure TDesignerBarState.Command(const AId: string);
begin
  if FCommands.Execute(AId) then
  begin
    UpdateBars;
    Exit;
  end;
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
  else if SameText(AId, TAtlasIdeDesignerTabOrder.cId) then
  begin
    FTabOrder.Toggle;
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
  if FCommands.HasMenu(AId) then
  begin
    FCommands.Popup(AId, APoint);
    Exit;
  end;
  if SameText(AId, TAtlasIdeDesignerTabOrder.cId) then
  begin
    FTabOrder.Popup(APoint);
    Exit;
  end;
  if not SameText(AId, cIdAlign) or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mCount := Length(TAtlasDesignerAccess.Selection(mEditor, mRoot));
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
  mSelected := TAtlasDesignerAccess.Selection(AEditor, ARoot);
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
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSearchNoForm));
    Exit;
  end;
  // Schon offen: neu aufbauen, das Formular kann ein anderes sein.
  CloseSearch;
  mOptions := SearchOptions(mEditor, mRoot);
  mWindow := TAtlasComponentSearchWindow.CreateSearch(nil, mOptions,
    TAtlasDesignerSearchItems.ItemsOf(mRoot, TAtlasDesignerAccess.DesignerOf(mEditor)),
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
