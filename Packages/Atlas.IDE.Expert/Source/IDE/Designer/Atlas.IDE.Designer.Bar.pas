unit Atlas.IDE.Designer.Bar;

// Designer-Leiste (#1442) in der IDE:
// - Zeigt ein Editorfenster den Formular-Designer, steht über ihm eine Leiste
//   (TAtlasDesignerBar) an Stelle von Brotkrumen und Editorleiste; zurück im
//   Code ist es umgekehrt. Ein- und ausgeblendet wird über den Leisten-Host
//   (ShowIn, TAtlasIdeDesignerView), angelegt je Editorfenster wie die
//   übrigen Leisten (#1248).
// - Suche: Teilwortsuche über die Komponentennamen des Formulars
//   (TAtlasDesignerSearch). Der beste Treffer wird im Designer ausgewählt und
//   damit im Objektinspektor gezeigt; Enter, ↓ und „›“ schalten weiter,
//   Umschalt+Enter, ↑ und „‹“ zurück. Eine ausgeblendete Komponente wird
//   beim Auswählen wieder eingeblendet.
// - Ausblenden nur in der Anzeige (TAtlasDesignerHidden, je Formulardatei):
//   Steuerelemente über csNoDesignVisible, das nicht gespeichert wird;
//   Symbole nichtvisueller Komponenten über ihr Fenster im Designer.
//   Ausgerichtete Steuerelemente (Align), Kinder eines Elternteils mit
//   AutoSize und Kinder von Flow- und Grid-Panel bleiben sichtbar: Ohne sie
//   ordnete die VCL die Nachbarn neu an, und die .dfm änderte sich.
//   Atlas setzt csNoDesignVisible nur zurück, wo es selbst es gesetzt hat
//   (TTabSheet mit TabVisible = False setzt es auch).
// - Leiste aus (editor.designerBar), Sicherung ausgelöst oder Abbau: alles
//   wieder einblenden.
// - Eigene Sicherung TAtlasFeature.DesignerBar.
// Nur im Hauptthread.

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
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Menus,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Designer.Components,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Foundation.DesignerView,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  TickMs = 200;
  /// <summary>Größer ist kein Symbol einer nichtvisuellen Komponente (logische Pixel, mit Beschriftung).</summary>
  MaxIconSize = 160;

type
  TControlAccess = class(TControl);

  /// <summary>Was in einem Formular ausgeblendet ist und was Atlas dafür gesetzt hat.</summary>
  TFormState = class
  public
    Hidden: TAtlasDesignerHidden;
    /// <summary>Steuerelemente, an denen Atlas csNoDesignVisible gesetzt hat (Namen klein).</summary>
    Applied: TDictionary<string, Boolean>;
    /// <summary>Ausgeblendete Symbolfenster nichtvisueller Komponenten (Namen klein).</summary>
    Icons: TDictionary<string, HWND>;
    constructor Create;
    destructor Destroy; override;
  end;

  TDesignerBarState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FForms: TObjectDictionary<string, TFormState>;
    FMenu: TPopupMenu;
    FFile: string;
    FPattern: string;
    FHits: TArray<string>;
    FHitIndex: Integer;
    FKept: Integer;
    FIconLogged: Boolean;
    procedure Tick(Sender: TObject);
    function CreateBar(AEditorParent: TWinControl): TAtlasDesignerBar;
    procedure Place(ABar: TAtlasDesignerBar; AEditorParent: TWinControl);
    function Current(out AEditor: IOTAFormEditor; out ARoot: TComponent): Boolean;
    function StateOf(const AFileName: string): TFormState;
    function ItemsOf(ARoot: TComponent): TArray<TAtlasDesignerItem>;
    procedure Apply(ARoot: TComponent; AState: TFormState);
    procedure Restore(ARoot: TComponent; AState: TFormState);
    procedure RestoreAll;
    function Restorable: Boolean;
    procedure SetControlHidden(AControl: TControl; AHidden: Boolean);
    function IconWindow(ARoot: TWinControl; AComponent: TComponent): HWND;
    procedure Search(const APattern: string);
    procedure Step(ADelta: Integer);
    procedure Select(const AName: string);
    procedure ShowMenu(const APoint: TPoint);
    procedure ShowAll;
    procedure Change(const AAction: TProc<TFormState, TArray<TComponent>>);
    function Selection(const AEditor: IOTAFormEditor; ARoot: TComponent): TArray<TComponent>;
    procedure UpdateBars;
    procedure Later(const AAction: TProc);
    procedure Say(const AText: string);
    procedure MenuHideSelection(Sender: TObject);
    procedure MenuHideClass(Sender: TObject);
    procedure MenuNonVisual(Sender: TObject);
    procedure MenuShowClass(Sender: TObject);
    procedure MenuShowAll(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    procedure ApplyTheme;
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

function Key(const AText: string): string;
begin
  Result := LowerCase(AText);
end;

function DesignerOf(const AEditor: IOTAFormEditor): IDesigner;
var
  mNative: INTAFormEditor;
begin
  Result := nil;
  if Supports(AEditor, INTAFormEditor, mNative) then
    Result := mNative.FormDesigner;
end;

/// <summary>Bliebe die .dfm unverändert, wenn AControl im Designer fehlt? '' = ja, sonst der Grund.</summary>
function KeepReason(AControl: TControl): string;
begin
  Result := '';
  if AControl.Align <> alNone then
    Result := 'Align'
  else if AControl.Parent = nil then
    Result := 'ohne Elternteil'
  else if TControlAccess(AControl.Parent).AutoSize then
    Result := 'AutoSize des Elternteils'
  else if (AControl.Parent is TCustomFlowPanel) or (AControl.Parent is TCustomGridPanel) then
    Result := 'Flow-/Grid-Panel';
end;

{ TFormState }

constructor TFormState.Create;
begin
  inherited Create;
  Hidden := TAtlasDesignerHidden.Create;
  Applied := TDictionary<string, Boolean>.Create;
  Icons := TDictionary<string, HWND>.Create;
end;

destructor TFormState.Destroy;
begin
  Icons.Free;
  Applied.Free;
  Hidden.Free;
  inherited Destroy;
end;

{ TDesignerBarState }

constructor TDesignerBarState.Create;
begin
  inherited Create;
  FForms := TObjectDictionary<string, TFormState>.Create([doOwnsValues]);
  FHitIndex := -1;
  FHost := TAtlasEditorBarHost.Create('Designer-Leiste', TAtlasFeature.DesignerBar,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateBar(AEditorParent);
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      Place(TAtlasDesignerBar(ABar), AEditorParent);
    end);
  FHost.ShowIn := TAtlasEditorBarView.Designer;
  FMenu := TPopupMenu.Create(nil);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TDesignerBarState.Destroy;
begin
  FTimer.Free;
  // Nichts bleibt ausgeblendet, wenn Atlas geht.
  try
    RestoreAll;
  except
    on E: Exception do
      TAtlasGuard.Log('Designer-Leiste: beim Abbau nicht alles eingeblendet: ' + TAtlasGuard.SafeMessage(E.Message));
  end;
  FMenu.Free;
  FHost.Free;
  FForms.Free;
  inherited Destroy;
end;

procedure TDesignerBarState.Reset;
begin
  if not TAtlasIdeSettings.Current.EditorDesignerBar then
  begin
    RestoreAll;
    FHost.Clear;
  end;
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
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable. Einordnen und Wächter: Host.</summary>
function TDesignerBarState.CreateBar(AEditorParent: TWinControl): TAtlasDesignerBar;
var
  mBar: TAtlasDesignerBar;
  mHost: TAtlasEditorBarHost;
begin
  mBar := TAtlasDesignerBar.Create(nil);
  mHost := FHost;
  mBar.ApplyColors(BarColors);
  mBar.SetTexts(TAtlasStrings.Text(TAtlasTextId.DesignerBarSearchHint),
    TAtlasStrings.Text(TAtlasTextId.DesignerBarHits), TAtlasStrings.Text(TAtlasTextId.DesignerBarNoHit),
    TAtlasStrings.Text(TAtlasTextId.DesignerBarHide), TAtlasStrings.Text(TAtlasTextId.DesignerBarShowAll),
    TAtlasStrings.Text(TAtlasTextId.DesignerBarPrevHint), TAtlasStrings.Text(TAtlasTextId.DesignerBarNextHint),
    TAtlasStrings.Text(TAtlasTextId.DesignerBarHiddenHint));
  mBar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      mHost.Disabled(ASender);
    end;
  mBar.OnSearch :=
    procedure(AText: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.DesignerBar,
        procedure
        begin
          Search(AText);
        end);
    end;
  mBar.OnStep :=
    procedure(ADelta: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.DesignerBar,
        procedure
        begin
          Step(ADelta);
        end);
    end;
  mBar.OnHideMenu :=
    procedure(APoint: TPoint)
    var
      mPoint: TPoint;
    begin
      mPoint := APoint;
      // Nach dem Klick: Die IDE holt den Fokus in den Designer; das Menü erst danach.
      Later(
        procedure
        begin
          ShowMenu(mPoint);
        end);
    end;
  mBar.OnShowAll :=
    procedure
    begin
      Later(
        procedure
        begin
          ShowAll;
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

function TDesignerBarState.StateOf(const AFileName: string): TFormState;
begin
  if not FForms.TryGetValue(Key(AFileName), Result) then
  begin
    Result := TFormState.Create;
    FForms.Add(Key(AFileName), Result);
  end;
end;

function TDesignerBarState.ItemsOf(ARoot: TComponent): TArray<TAtlasDesignerItem>;
var
  mIndex: Integer;
  mComponent: TComponent;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    if mComponent.Name <> '' then
      Result := Result + [TAtlasDesignerItem.Create(mComponent.Name, mComponent.ClassName, mComponent is TControl)];
  end;
end;

procedure TDesignerBarState.SetControlHidden(AControl: TControl; AHidden: Boolean);
begin
  if AHidden = (csNoDesignVisible in AControl.ControlStyle) then
    Exit;
  if AHidden then
    AControl.ControlStyle := AControl.ControlStyle + [csNoDesignVisible]
  else
    AControl.ControlStyle := AControl.ControlStyle - [csNoDesignVisible];
  // Fenster zeigen bzw. verbergen; gezeichnete Steuerelemente zeichnet das Elternteil.
  if AControl is TWinControl then
    TWinControl(AControl).UpdateControlState;
  if AControl.Parent <> nil then
    AControl.Parent.Invalidate;
end;

function TDesignerBarState.IconWindow(ARoot: TWinControl; AComponent: TComponent): HWND;
var
  mPoint: TPoint;
  mControl: TWinControl;
  mRect: TRect;
  mClass: array[0..127] of Char;
  mLimit: Integer;
begin
  Result := 0;
  if not ARoot.HandleAllocated then
    Exit;
  // DesignInfo: links oben des Symbols im Formular (LoWord x, HiWord y).
  mPoint := Point(SmallInt(LongRec(AComponent.DesignInfo).Lo) + 2, SmallInt(LongRec(AComponent.DesignInfo).Hi) + 2);
  Result := ChildWindowFromPointEx(ARoot.Handle, mPoint, CWP_SKIPINVISIBLE);
  if (Result = 0) or (Result = ARoot.Handle) then
    Exit(0);
  // Ein Steuerelement des Formulars ist kein Symbol.
  mControl := FindControl(Result);
  if (mControl <> nil) and (mControl.Owner = ARoot) then
    Exit(0);
  mLimit := MulDiv(MaxIconSize, ARoot.CurrentPPI, 96);
  if not GetWindowRect(Result, mRect) or (mRect.Width > mLimit) or (mRect.Height > mLimit) then
    Exit(0);
  if not FIconLogged then
  begin
    FIconLogged := True;
    mClass[0] := #0;
    GetClassName(Result, mClass, Length(mClass));
    TAtlasGuard.Log(Format('Designer-Leiste: Symbol von %s ist ein Fenster der Klasse %s (%d × %d)',
      [AComponent.Name, string(mClass), mRect.Width, mRect.Height]));
  end;
end;

procedure TDesignerBarState.Apply(ARoot: TComponent; AState: TFormState);
var
  mIndex: Integer;
  mComponent: TComponent;
  mName: string;
  mWanted: Boolean;
  mWindow: HWND;
begin
  FKept := 0;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    if mComponent.Name = '' then
      Continue;
    mName := Key(mComponent.Name);
    mWanted := AState.Hidden.IsHidden(TAtlasDesignerItem.Create(mComponent.Name, mComponent.ClassName,
      mComponent is TControl));
    if mComponent is TControl then
    begin
      if mWanted and (KeepReason(TControl(mComponent)) <> '') then
      begin
        Inc(FKept);
        mWanted := False;
      end;
      if mWanted then
      begin
        if not AState.Applied.ContainsKey(mName) and (csNoDesignVisible in TControl(mComponent).ControlStyle) then
          Continue;
        SetControlHidden(TControl(mComponent), True);
        AState.Applied.AddOrSetValue(mName, True);
      end
      else if AState.Applied.ContainsKey(mName) then
      begin
        SetControlHidden(TControl(mComponent), False);
        AState.Applied.Remove(mName);
      end;
      Continue;
    end;
    // Nichtvisuell: Symbol im Designer (nur auf Formularen und Frames).
    if not (ARoot is TWinControl) then
      Continue;
    if mWanted then
    begin
      if not AState.Icons.TryGetValue(mName, mWindow) or not IsWindow(mWindow) then
      begin
        mWindow := IconWindow(TWinControl(ARoot), mComponent);
        if mWindow = 0 then
          Continue;
        AState.Icons.AddOrSetValue(mName, mWindow);
      end;
      // Der Designer zeigt Symbole beim Verschieben und Neuzeichnen wieder: jeden Takt prüfen.
      if IsWindowVisible(mWindow) then
        ShowWindow(mWindow, SW_HIDE);
    end
    else if AState.Icons.TryGetValue(mName, mWindow) then
    begin
      if IsWindow(mWindow) then
        ShowWindow(mWindow, SW_SHOWNA);
      AState.Icons.Remove(mName);
    end;
  end;
end;

procedure TDesignerBarState.Restore(ARoot: TComponent; AState: TFormState);
begin
  AState.Hidden.ShowAll;
  if ARoot <> nil then
    Apply(ARoot, AState);
  AState.Applied.Clear;
  AState.Icons.Clear;
end;

procedure TDesignerBarState.RestoreAll;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mEditor: IOTAFormEditor;
  mModuleIndex, mFileIndex: Integer;
  mState: TFormState;
begin
  // Nichts ausgeblendet: die Module nicht anfassen. Beim Beenden der IDE sind sie schon im Abbau, und
  // ModuleFileEditors löste in coreide eine Zugriffsverletzung aus.
  if not Restorable then
  begin
    FPattern := '';
    FHits := nil;
    FHitIndex := -1;
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
    for mModuleIndex := 0 to mModules.ModuleCount - 1 do
    begin
      mModule := mModules.Modules[mModuleIndex];
      for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
        if Supports(mModule.ModuleFileEditors[mFileIndex], IOTAFormEditor, mEditor) and
          FForms.TryGetValue(Key(mEditor.FileName), mState) then
          Restore(TAtlasIdeDesignerView.RootOf(mEditor), mState);
    end;
  FForms.Clear;
  FPattern := '';
  FHits := nil;
  FHitIndex := -1;
end;

/// <summary>Hat Atlas in einem Formular etwas ausgeblendet oder gesetzt, das zurück muss?</summary>
function TDesignerBarState.Restorable: Boolean;
var
  mState: TFormState;
begin
  for mState in FForms.Values do
    if mState.Hidden.Any or (mState.Applied.Count > 0) or (mState.Icons.Count > 0) then
      Exit(True);
  Result := False;
end;

procedure TDesignerBarState.UpdateBars;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mHidden: Integer;
  mIndex, mCount: Integer;
  mState: TFormState;
begin
  mHidden := 0;
  // TryGetValue statt StateOf: Anzeigen legt keinen Zustand an.
  if Current(mEditor, mRoot) and FForms.TryGetValue(Key(mEditor.FileName), mState) then
    mHidden := mState.Hidden.CountIn(ItemsOf(mRoot));
  mIndex := FHitIndex;
  mCount := Length(FHits);
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasDesignerBar(ABar).SetHiddenCount(mHidden);
      TAtlasDesignerBar(ABar).SetHits(mIndex, mCount);
    end);
end;

procedure TDesignerBarState.Tick(Sender: TObject);
begin
  // Sicherung ausgelöst: Leisten weg und alles wieder sichtbar, bis die Funktion wieder eingeschaltet ist.
  if not FHost.Guard then
  begin
    if Restorable then
      RestoreAll;
    Exit;
  end;
  if not TAtlasIdeSettings.Current.EditorDesignerBar then
  begin
    if Restorable then
      RestoreAll;
    if FHost.Count > 0 then
      FHost.Clear;
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    var
      mEditor: IOTAFormEditor;
      mRoot: TComponent;
      mState: TFormState;
    begin
      FHost.Ensure;
      if not Current(mEditor, mRoot) then
        Exit;
      if not SameText(mEditor.FileName, FFile) then
      begin
        // Anderes Formular: Treffer neu suchen, das Suchwort bleibt.
        FFile := mEditor.FileName;
        FHits := TArray<string>.Create();
        FHitIndex := -1;
        if FPattern <> '' then
          Search(FPattern);
      end;
      if FForms.TryGetValue(Key(FFile), mState) then
        Apply(mRoot, mState);
      UpdateBars;
    end);
end;

procedure TDesignerBarState.Search(const APattern: string);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mItems: TArray<TAtlasDesignerItem>;
  mIndex: Integer;
begin
  FPattern := APattern;
  FHits := nil;
  FHitIndex := -1;
  if Current(mEditor, mRoot) and (APattern <> '') then
  begin
    mItems := ItemsOf(mRoot);
    for mIndex in TAtlasDesignerSearch.Find(mItems, APattern) do
      FHits := FHits + [mItems[mIndex].Name];
    if Length(FHits) > 0 then
    begin
      FHitIndex := 0;
      Select(FHits[0]);
    end;
  end;
  UpdateBars;
end;

procedure TDesignerBarState.Step(ADelta: Integer);
begin
  if FPattern = '' then
    Exit;
  FHitIndex := TAtlasDesignerSearch.Step(FHitIndex, Length(FHits), ADelta);
  if FHitIndex >= 0 then
    Select(FHits[FHitIndex]);
  UpdateBars;
end;

procedure TDesignerBarState.Select(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mState: TFormState;
begin
  if not Current(mEditor, mRoot) then
    Exit;
  mComponent := mRoot.FindComponent(AName);
  mDesigner := DesignerOf(mEditor);
  // Umbenannt oder gelöscht seit der Suche: neu suchen.
  if (mComponent = nil) or (mDesigner = nil) then
    Exit;
  // Eine ausgeblendete Komponente zeigt sich, sobald sie gewählt wird.
  if FForms.TryGetValue(Key(mEditor.FileName), mState) and
    mState.Hidden.IsHidden(TAtlasDesignerItem.Create(mComponent.Name, mComponent.ClassName, mComponent is TControl))
  then
  begin
    mState.Hidden.ShowName(mComponent.Name);
    Apply(mRoot, mState);
  end;
  mDesigner.SelectComponent(mComponent);
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

/// <summary>Ausgeblendetes ändern, anwenden und die Auswahl lösen (sonst stünden Griffe um Unsichtbares).</summary>
procedure TDesignerBarState.Change(const AAction: TProc<TFormState, TArray<TComponent>>);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mState: TFormState;
  mDesigner: IDesigner;
begin
  if not Current(mEditor, mRoot) then
    Exit;
  mState := StateOf(mEditor.FileName);
  AAction(mState, Selection(mEditor, mRoot));
  Apply(mRoot, mState);
  mDesigner := DesignerOf(mEditor);
  if mDesigner <> nil then
    mDesigner.SelectComponent(mRoot);
  if FKept > 0 then
    Say(TAtlasStrings.Fmt(TAtlasTextId.DesignerBarKeptAligned, [FKept]));
  UpdateBars;
end;

procedure TDesignerBarState.ShowMenu(const APoint: TPoint);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mState: TFormState;
  mItem: TMenuItem;
  mClass: string;
begin
  if not Current(mEditor, mRoot) then
    Exit;
  mSelected := Selection(mEditor, mRoot);
  mState := StateOf(mEditor.FileName);
  FMenu.Items.Clear;
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasStrings.Text(TAtlasTextId.DesignerBarHideSelection);
  mItem.Enabled := Length(mSelected) > 0;
  mItem.OnClick := MenuHideSelection;
  FMenu.Items.Add(mItem);
  if Length(mSelected) > 0 then
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.DesignerBarHideClass, [mSelected[0].ClassName]);
    mItem.Hint := mSelected[0].ClassName;
    mItem.OnClick := MenuHideClass;
    FMenu.Items.Add(mItem);
  end;
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasStrings.Text(TAtlasTextId.DesignerBarHideNonVisual);
  mItem.Checked := mState.Hidden.NonVisual;
  mItem.OnClick := MenuNonVisual;
  FMenu.Items.Add(mItem);
  for mClass in mState.Hidden.HiddenClasses do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.DesignerBarShowClass, [mClass]);
    mItem.Hint := mClass;
    mItem.OnClick := MenuShowClass;
    FMenu.Items.Add(mItem);
  end;
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := '-';
  FMenu.Items.Add(mItem);
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.DesignerBarShowAll, [mState.Hidden.CountIn(ItemsOf(mRoot))]);
  mItem.Enabled := mState.Hidden.Any;
  mItem.OnClick := MenuShowAll;
  FMenu.Items.Add(mItem);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TDesignerBarState.MenuHideSelection(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      Change(
        procedure(AState: TFormState; ASelected: TArray<TComponent>)
        var
          mComponent: TComponent;
        begin
          if Length(ASelected) = 0 then
          begin
            Say(TAtlasStrings.Text(TAtlasTextId.DesignerBarNoSelection));
            Exit;
          end;
          for mComponent in ASelected do
            AState.Hidden.HideName(mComponent.Name);
        end);
    end);
end;

procedure TDesignerBarState.MenuHideClass(Sender: TObject);
var
  mClass: string;
begin
  mClass := TMenuItem(Sender).Hint;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      Change(
        procedure(AState: TFormState; ASelected: TArray<TComponent>)
        begin
          AState.Hidden.HideClass(mClass);
        end);
    end);
end;

procedure TDesignerBarState.MenuNonVisual(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      Change(
        procedure(AState: TFormState; ASelected: TArray<TComponent>)
        begin
          AState.Hidden.NonVisual := not AState.Hidden.NonVisual;
        end);
    end);
end;

procedure TDesignerBarState.MenuShowClass(Sender: TObject);
var
  mClass: string;
begin
  mClass := TMenuItem(Sender).Hint;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      Change(
        procedure(AState: TFormState; ASelected: TArray<TComponent>)
        begin
          AState.Hidden.ShowClass(mClass);
        end);
    end);
end;

procedure TDesignerBarState.MenuShowAll(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      ShowAll;
    end);
end;

procedure TDesignerBarState.ShowAll;
begin
  Change(
    procedure(AState: TFormState; ASelected: TArray<TComponent>)
    begin
      AState.Hidden.ShowAll;
    end);
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
