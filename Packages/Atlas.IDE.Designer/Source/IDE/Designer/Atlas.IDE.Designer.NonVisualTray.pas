unit Atlas.IDE.Designer.NonVisualTray;

// Leiste für nichtvisuelle Komponenten (#609, designer.nonVisualTray): Knopf
// in der Designer-Leiste, der ein andockbares Fenster (TAtlasIdeDockWindow)
// mit TAtlasNonVisualFrame öffnet und schließt.
// - Inhalt: Komponenten des Formulars im aktiven Designer, die keine
//   Steuerelemente sind und kein Elternobjekt haben (also keine Menüeinträge,
//   Aktionen und Felder), gruppiert und sortiert von TAtlasNonVisualTray.
//   Ein Takt (300 ms) vergleicht eine Kennung aus Formular, Namen und Klassen
//   und füllt bei Änderung neu; so erscheinen neue, gelöschte und umbenannte
//   Komponenten sofort, ohne eigenen Designer-Notifier.
// - Klick wählt im Designer, Doppelklick ruft den Komponenten-Editor
//   (wie im Designer), Rechtsklick zeigt dessen Befehle.
// - Ziehen aus der Palette oder Klick auf eine freie Stelle der Liste legt die
//   in der Palette gewählte nichtvisuelle Komponente an, an einer freien Stelle
//   am unteren Rand des Formulars.
// - Symbole auf der Formularfläche: über den Befehl der IDE
//   „Nichtvisuelle Komponenten ausblenden“
//   (ToggleNonVisualComponentVisibilityCommand); beim Schließen gilt wieder der
//   vorherige Zustand. Left/Top (DesignInfo) bleiben unverändert.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.Controls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.NonVisualFrame;

type
  TAtlasIdeNonVisualTray = class
  public const
    cId = 'nonVisualTray';
  private
    FOnMessage: TProc<string>;
    FTimer: TTimer;
    FImages: TImageList;
    FImageClasses: TStringList;
    FMenu: TPopupMenu;
    FMenuComponent: string;
    FSignature: string;
    FMarked: string;
    FHidOnForm: Boolean;
    function Frame: TAtlasNonVisualFrame;
    function Open: Boolean;
    procedure CloseTray;
    procedure Wire(AFrame: TAtlasNonVisualFrame);
    procedure Place;
    procedure Tick(Sender: TObject);
    procedure Fill(AForce: Boolean);
    procedure SyncSelection;
    function ImageOf(AClass: TClass): Integer;
    procedure SelectName(const AName: string);
    procedure OpenName(const AName: string);
    procedure MenuFor(const AName: string; const APoint: TPoint);
    procedure MenuClick(Sender: TObject);
    function CanDrop: Boolean;
    procedure Drop;
    procedure HideOnForm(AHide: Boolean);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Knopf nach den Einstellungen; Id leer, wenn ausgeschaltet.</summary>
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick: Leiste öffnen bzw. schließen.</summary>
    procedure Toggle;
    procedure ApplyTheme;
  end;

implementation

uses
  Winapi.Windows,
  System.IniFiles,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.ActnList,
  Vcl.ImgList,
  Vcl.ComCtrls,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Designer.NonVisual,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.Model,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.Settings;

const
  cTick = 300;
  cImageSize = 24;
  cTrayHeight = 200;
  cTrayWidth = 320;
  cBasePpi = 96;
  cHideAction = 'ToggleNonVisualComponentVisibilityCommand';
  cPositionRight = 'right';

type
  TTrayDock = class(TInterfacedObject, INTACustomDockableForm)
  public
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolbarActionList: TCustomActionList;
    function GetToolbarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
  end;

var
  // Form, Frame und Anmeldung bei der IDE; nicht im Desktop gespeichert, die Leiste öffnet der Knopf.
  Host: TAtlasIdeDockWindow;

{ TTrayDock }

function TTrayDock.GetCaption: string;
begin
  Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NvCaption);
end;

function TTrayDock.GetIdentifier: string;
begin
  Result := 'AtlasNonVisualTray';
end;

function TTrayDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasNonVisualFrame;
end;

procedure TTrayDock.FrameCreated(AFrame: TCustomFrame);
begin
  if Host <> nil then
  begin
    Host.FrameCreated(AFrame);
  end;
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
end;

function TTrayDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TTrayDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TTrayDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TTrayDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TTrayDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TTrayDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TTrayDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TTrayDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TTrayDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TTrayDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

{ Hilfen }

/// <summary>Nichtvisuelle Komponente, wie der Designer sie als Symbol zeigt.</summary>
function IsTrayComponent(AComponent, ARoot: TComponent): Boolean;
begin
  Result := (AComponent.Owner = ARoot) and not (AComponent is TControl) and not AComponent.HasParent and
    (AComponent.Name <> '');
end;

function PositionOf(AComponent: TComponent): TPoint;
begin
  // DesignInfo: Left im unteren, Top im oberen Wort, wie Left/Top in der DFM.
  Result := TPoint.Create(SmallInt(LongRec(AComponent.DesignInfo).Lo), SmallInt(LongRec(AComponent.DesignInfo).Hi));
end;

function TrayItems(ARoot: TComponent): TArray<TAtlasTrayItem>;
var
  mIndex: Integer;
  mComponent: TComponent;
  mItem: TAtlasTrayItem;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    if IsTrayComponent(mComponent, ARoot) then
    begin
      mItem := Default(TAtlasTrayItem);
      mItem.Name := mComponent.Name;
      mItem.ClassChain := TAtlasDesignerAccess.ClassChain(mComponent);
      mItem.Position := PositionOf(mComponent);
      Result := Result + [mItem];
    end;
  end;
end;

function SignatureOf(ARoot: TComponent; const AItems: TArray<TAtlasTrayItem>; const AFilter: string): string;
var
  mItem: TAtlasTrayItem;
begin
  Result := ARoot.Name + '|' + AFilter;
  for mItem in AItems do
  begin
    Result := Result + '|' + mItem.Name + ':' + mItem.ClassName;
  end;
end;

function FindHideAction: TContainedAction;
var
  mServices: INTAServices;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    if SameText(mServices.ActionList.Actions[mIndex].Name, cHideAction) then
    begin
      Exit(mServices.ActionList.Actions[mIndex]);
    end;
  end;
end;

/// <summary>Klasse der in der Palette gewählten Komponente; nil ohne Auswahl oder bei einem Steuerelement.
/// </summary>
function PaletteClass: TComponentClass;
var
  mPalette: IOTAPaletteServices;
  mItem: IOTAComponentPaletteItem;
  mClass: TPersistentClass;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAPaletteServices, mPalette) or
    not Supports(mPalette.SelectedTool, IOTAComponentPaletteItem, mItem) then
  begin
    Exit;
  end;
  mClass := GetClass(mItem.ClassName);
  if (mClass <> nil) and mClass.InheritsFrom(TComponent) and not mClass.InheritsFrom(TControl) then
  begin
    Result := TComponentClass(mClass);
  end;
end;

{ TAtlasIdeNonVisualTray }

constructor TAtlasIdeNonVisualTray.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTick;
  FTimer.OnTimer := Tick;
  FImageClasses := TStringList.Create;
  FImages := TImageList.Create(nil);
  FImages.ColorDepth := cd32Bit;
  FImages.SetSize(cImageSize, cImageSize);
  FMenu := TPopupMenu.Create(nil);
end;

destructor TAtlasIdeNonVisualTray.Destroy;
begin
  FTimer.Enabled := False;
  CloseTray;
  FreeAndNil(Host);
  FTimer.Free;
  FMenu.Free;
  FImages.Free;
  FImageClasses.Free;
  inherited Destroy;
end;

function TAtlasIdeNonVisualTray.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
begin
  if not ASettings.DesignerNonVisualTray then
  begin
    CloseTray;
    Exit(Default(TAtlasDesignerButton));
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.NonVisualTray,
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NvHint));
  Result.Pressed := (Host <> nil) and Host.Shown;
end;

function TAtlasIdeNonVisualTray.Frame: TAtlasNonVisualFrame;
begin
  Result := nil;
  if (Host <> nil) and (Host.Frame is TAtlasNonVisualFrame) then
  begin
    Result := TAtlasNonVisualFrame(Host.Frame);
  end;
end;

procedure TAtlasIdeNonVisualTray.Toggle;
begin
  if (Host <> nil) and Host.Shown then
  begin
    CloseTray;
  end
  else if Open then
  begin
    HideOnForm(TAtlasIdeSettings.Current.DesignerNonVisualTrayHideOnForm);
    FTimer.Enabled := True;
  end;
end;

function TAtlasIdeNonVisualTray.Open: Boolean;
var
  mCreated: Boolean;
begin
  if Host = nil then
  begin
    Host := TAtlasIdeDockWindow.Create(TTrayDock.Create, False);
  end;
  Result := Host.Show(mCreated) and (Frame <> nil);
  if not Result then
  begin
    Exit;
  end;
  if mCreated then
  begin
    Place;
  end;
  Wire(Frame);
  FSignature := '';
  Fill(True);
end;

procedure TAtlasIdeNonVisualTray.CloseTray;
begin
  FTimer.Enabled := False;
  HideOnForm(False);
  if (Host <> nil) and Host.Shown then
  begin
    Host.Hide;
  end;
end;

procedure TAtlasIdeNonVisualTray.Wire(AFrame: TAtlasNonVisualFrame);
begin
  AFrame.List.SmallImages := FImages;
  AFrame.OnSelect :=
    procedure(AName: string)
    begin
      SelectName(AName);
    end;
  AFrame.OnOpen :=
    procedure(AName: string)
    begin
      OpenName(AName);
    end;
  AFrame.OnMenu :=
    procedure(AName: string; APoint: TPoint)
    begin
      MenuFor(AName, APoint);
    end;
  AFrame.OnCanDrop := CanDrop;
  AFrame.OnDrop := Drop;
  AFrame.OnFilter :=
    procedure(AText: string)
    begin
      Fill(True);
    end;
end;

procedure TAtlasIdeNonVisualTray.Place;
var
  mEditors: INTAEditorServices;
  mEdit: TRect;
  mForm: TCustomForm;
  mPpi: Integer;
begin
  mForm := Host.Form;
  if (mForm = nil) or (mForm.Parent <> nil) or not Supports(BorlandIDEServices, INTAEditorServices, mEditors) or
    (mEditors.TopEditWindow = nil) or (mEditors.TopEditWindow.Form = nil) then
  begin
    Exit;
  end;
  mEdit := mEditors.TopEditWindow.Form.BoundsRect;
  mPpi := mForm.CurrentPPI;
  // Schwebend am Rand des Editorfensters; danach dockt man sie wie jedes Fenster der IDE an.
  if SameText(TAtlasIdeSettings.Current.DesignerNonVisualTrayPosition, cPositionRight) then
  begin
    mForm.SetBounds(mEdit.Right - MulDiv(cTrayWidth, mPpi, cBasePpi), mEdit.Top,
      MulDiv(cTrayWidth, mPpi, cBasePpi), mEdit.Height);
  end
  else
  begin
    mForm.SetBounds(mEdit.Left, mEdit.Bottom - MulDiv(cTrayHeight, mPpi, cBasePpi), mEdit.Width,
      MulDiv(cTrayHeight, mPpi, cBasePpi));
  end;
end;

procedure TAtlasIdeNonVisualTray.Tick(Sender: TObject);
begin
  if (Host = nil) or not Host.Shown then
  begin
    // Mit dem X geschlossen: vorherigen Zustand der Formularfläche wiederherstellen.
    CloseTray;
    Exit;
  end;
  Fill(False);
  SyncSelection;
end;

procedure TAtlasIdeNonVisualTray.Fill(AForce: Boolean);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mFrame: TAtlasNonVisualFrame;
  mItems: TArray<TAtlasTrayItem>;
  mSignature: string;
begin
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mItems := nil;
  mSignature := '';
  if TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    mItems := TrayItems(mRoot);
    mSignature := SignatureOf(mRoot, mItems, mFrame.FilterText);
  end;
  if not AForce and (mSignature = FSignature) then
  begin
    Exit;
  end;
  FSignature := mSignature;
  FMarked := '';
  mFrame.ShowRows(TAtlasNonVisualTray.Rows(mItems, mFrame.FilterText),
    function(AItem: TAtlasTrayItem): Integer
    begin
      Result := ImageOf(mRoot.FindComponent(AItem.Name).ClassType);
    end);
end;

procedure TAtlasIdeNonVisualTray.SyncSelection;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mName: string;
begin
  mName := '';
  if TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
    if (Length(mSelected) = 1) and IsTrayComponent(mSelected[0], mRoot) then
    begin
      mName := mSelected[0].Name;
    end;
  end;
  if (mName <> FMarked) and (Frame <> nil) then
  begin
    FMarked := mName;
    Frame.MarkName(mName);
  end;
end;

function TAtlasIdeNonVisualTray.ImageOf(AClass: TClass): Integer;
var
  mIndex: Integer;
  mClass: TClass;
  mBitmap: TBitmap;
  mInstance: HMODULE;
begin
  mIndex := FImageClasses.IndexOf(AClass.ClassName);
  if mIndex >= 0 then
  begin
    Exit(Integer(FImageClasses.Objects[mIndex]));
  end;
  Result := -1;
  // Symbol der Palette: Bitmap-Ressource mit dem Klassennamen im Package der Klasse, sonst der Vorfahr.
  mClass := AClass;
  while (Result < 0) and (mClass <> nil) and (mClass <> TComponent) do
  begin
    mInstance := FindClassHInstance(mClass);
    if (mInstance <> 0) and (FindResource(mInstance, PChar(UpperCase(mClass.ClassName)), RT_BITMAP) <> 0) then
    begin
      mBitmap := TBitmap.Create;
      try
        mBitmap.LoadFromResourceName(mInstance, UpperCase(mClass.ClassName));
        Result := FImages.AddMasked(mBitmap, mBitmap.Canvas.Pixels[0, mBitmap.Height - 1]);
      finally
        mBitmap.Free;
      end;
    end;
    mClass := mClass.ClassParent;
  end;
  FImageClasses.AddObject(AClass.ClassName, TObject(Result));
end;

procedure TAtlasIdeNonVisualTray.SelectName(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(AName);
  if mComponent <> nil then
  begin
    FMarked := AName;
    TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mComponent]);
  end;
end;

procedure TAtlasIdeNonVisualTray.OpenName(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(AName);
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if (mComponent = nil) or (mDesigner = nil) then
  begin
    Exit;
  end;
  // Wie Doppelklick im Designer: Standardbefehl des Komponenten-Editors.
  mDesigner.Edit(mComponent);
end;

procedure TAtlasIdeNonVisualTray.MenuFor(const AName: string; const APoint: TPoint);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mComponentEditor: IComponentEditor;
  mIndex: Integer;
  mItem: TMenuItem;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(AName);
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if (mComponent = nil) or (mDesigner = nil) then
  begin
    Exit;
  end;
  SelectName(AName);
  mComponentEditor := GetComponentEditor(mComponent, mDesigner);
  if (mComponentEditor = nil) or (mComponentEditor.GetVerbCount = 0) then
  begin
    Exit;
  end;
  FMenuComponent := AName;
  FMenu.Items.Clear;
  for mIndex := 0 to mComponentEditor.GetVerbCount - 1 do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := mComponentEditor.GetVerb(mIndex);
    mItem.Tag := mIndex;
    mItem.OnClick := MenuClick;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeNonVisualTray.MenuClick(Sender: TObject);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mComponentEditor: IComponentEditor;
begin
  if not (Sender is TMenuItem) or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(FMenuComponent);
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if (mComponent = nil) or (mDesigner = nil) then
  begin
    Exit;
  end;
  mComponentEditor := GetComponentEditor(mComponent, mDesigner);
  if (mComponentEditor <> nil) and (TMenuItem(Sender).Tag < mComponentEditor.GetVerbCount) then
  begin
    mComponentEditor.ExecuteVerb(TMenuItem(Sender).Tag);
  end;
end;

function TAtlasIdeNonVisualTray.CanDrop: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (PaletteClass <> nil) and TAtlasDesignerAccess.Current(mEditor, mRoot);
end;

procedure TAtlasIdeNonVisualTray.Drop;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mClass: TComponentClass;
  mCreated: IOTAComponent;
  mComponent: TComponent;
  mPoint: TPoint;
  mOccupied: TArray<TPoint>;
  mItem: TAtlasTrayItem;
begin
  mClass := PaletteClass;
  if (mClass = nil) or not TAtlasDesignerAccess.Current(mEditor, mRoot) or not (mRoot is TWinControl) then
  begin
    Exit;
  end;
  mOccupied := nil;
  for mItem in TrayItems(mRoot) do
  begin
    mOccupied := mOccupied + [mItem.Position];
  end;
  mPoint := TAtlasNonVisualTray.FreePosition(mOccupied, TAtlasDesignerModel.ClientOf(TWinControl(mRoot)));
  try
    mCreated := mEditor.CreateComponent(mEditor.GetRootComponent, mClass.ClassName, mPoint.X, mPoint.Y, 0, 0);
  except
    on E: Exception do
    begin
      FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.NvCreateFailed, [mClass.ClassName, E.Message]));
      raise;
    end;
  end;
  if (mCreated = nil) or not (TObject(mCreated.GetComponentHandle) is TComponent) then
  begin
    Exit;
  end;
  mComponent := TComponent(mCreated.GetComponentHandle);
  // Lage in Pixeln der DFM, unabhängig davon, wie CreateComponent X/Y deutet.
  mComponent.DesignInfo := MakeLong(Word(mPoint.X), Word(mPoint.Y));
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.NvCreated, [mComponent.Name]));
  Fill(True);
  SelectName(mComponent.Name);
end;

procedure TAtlasIdeNonVisualTray.HideOnForm(AHide: Boolean);
var
  mAction: TContainedAction;
begin
  if AHide = FHidOnForm then
  begin
    Exit;
  end;
  mAction := FindHideAction;
  if not (mAction is TCustomAction) then
  begin
    if AHide then
    begin
      FOnMessage(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NvHideMissing));
    end;
    Exit;
  end;
  mAction.Update;
  // Checked = ausgeblendet. Schon ausgeblendet: nichts tun und beim Schließen nichts zurückstellen.
  if AHide and not TCustomAction(mAction).Checked then
  begin
    mAction.Execute;
    FHidOnForm := True;
  end
  else if not AHide then
  begin
    if TCustomAction(mAction).Checked then
    begin
      mAction.Execute;
    end;
    FHidOnForm := False;
  end;
end;

procedure TAtlasIdeNonVisualTray.ApplyTheme;
begin
  if Frame <> nil then
  begin
    TAtlasIdeDockWindow.ApplyIdeTheme(Frame);
  end;
end;

end.
