unit Atlas.IDE.Designer.Structure;

// Fenster „Atlas-Struktur“ (#609, designer.structure): Knopf in der
// Designer-Leiste, der ein andockbares Fenster (TAtlasIdeDockWindow) mit
// TAtlasStructureFrame öffnet und schließt.
// - Inhalt: das Formular im aktiven Designer, seine Steuerelemente (nach
//   Parent) und seine nichtvisuellen Komponenten (ohne Elternobjekt, also
//   ohne Menüeinträge, Aktionen und Felder), als Zeilen von TAtlasStructure.
//   Verweise sind die veröffentlichten Eigenschaften vom Typ einer
//   Komponente (RTTI); Ziele in einem Datenmodul heißen „dmDaten.dsKunden“.
//   Ein Takt (300 ms) vergleicht eine Kennung aus Namen, Klassen, Eltern und
//   Verweisen und füllt bei Änderung neu; so erscheinen neue, gelöschte und
//   umbenannte Komponenten sofort, ohne eigenen Designer-Notifier.
// - Klick wählt im Designer (bei einer Verknüpfung ihr Ziel), Doppelklick
//   ruft den Komponenten-Editor (wie im Designer), Rechtsklick zeigt dessen
//   Befehle. Die Auswahl im Designer wird im Baum markiert.
// - Ziehen aus der Palette auf den Baum legt die dort gewählte nichtvisuelle
//   Komponente an einer freien Stelle am unteren Rand des Formulars an.
// - Symbole auf der Formularfläche: über den Befehl der IDE
//   „Nichtvisuelle Komponenten ausblenden“
//   (ToggleNonVisualComponentVisibilityCommand), wenn
//   designer.structureHideOnForm an ist; beim Schließen gilt wieder der
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
  Atlas.Core.Designer.Structure,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.StructureFrame,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Designer.PaletteImages;

type
  TAtlasIdeStructure = class
  public const
    cId = 'structure';
  private
    FOnMessage: TProc<string>;
    FHost: TAtlasIdeDockWindow;
    FTimer: TTimer;
    FPalette: TAtlasPaletteImages;
    FMenu: TPopupMenu;
    FMenuComponent: string;
    FSignature: string;
    FMarked: string;
    FFilter: string;
    FByKind: Boolean;
    FHidOnForm: Boolean;
    function Frame: TAtlasStructureFrame;
    function Open: Boolean;
    procedure CloseWindow;
    procedure Wire(AFrame: TAtlasStructureFrame);
    procedure Place;
    procedure Tick(Sender: TObject);
    function Items(ARoot: TComponent): TArray<TAtlasStructureItem>;
    procedure Fill(AForce: Boolean);
    procedure SyncSelection;
    function NodeImage(const ANode: TAtlasStructureNode): Integer;
    procedure SelectName(const AName: string);
    class procedure OpenName(const AName: string); static;
    procedure MenuFor(const AName: string; const APoint: TPoint);
    procedure MenuClick(Sender: TObject);
    procedure Drop;
    procedure HideOnForm(AHide: Boolean);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Knopf nach den Einstellungen; Id leer, wenn ausgeschaltet.</summary>
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick: Fenster öffnen bzw. schließen.</summary>
    procedure Toggle;
    procedure ApplyTheme;
  end;

implementation

uses
  Winapi.Windows,
  System.IniFiles,
  System.TypInfo,
  System.Actions,
  Vcl.Forms,
  Vcl.ActnList,
  Vcl.ImgList,
  Vcl.ComCtrls,
  ToolsAPI,
  PaletteAPI,
  DesignIntf,
  DesignEditors,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.Model,
  Atlas.IDE.Foundation.Settings;

const
  cTick = 300;
  cWindowWidth = 320;
  cBasePpi = 96;
  cHideAction = 'ToggleNonVisualComponentVisibilityCommand';

type
  TStructureDock = class(TInterfacedObject, INTACustomDockableForm)
  private
    FOnFrame: TProc<TCustomFrame>;
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
    property OnFrame: TProc<TCustomFrame> read FOnFrame write FOnFrame;
  end;

{ TStructureDock }

function TStructureDock.GetCaption: string;
begin
  Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StCaption);
end;

function TStructureDock.GetIdentifier: string;
begin
  Result := 'AtlasStructure';
end;

function TStructureDock.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasStructureFrame;
end;

procedure TStructureDock.FrameCreated(AFrame: TCustomFrame);
begin
  if Assigned(FOnFrame) then
  begin
    FOnFrame(AFrame);
  end;
  TAtlasIdeDockWindow.ApplyIdeTheme(AFrame);
end;

function TStructureDock.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStructureDock.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TStructureDock.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TStructureDock.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStructureDock.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TStructureDock.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TStructureDock.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TStructureDock.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TStructureDock.GetEditState: TEditState;
begin
  Result := [];
end;

function TStructureDock.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

{ Hilfen }

/// <summary>Nichtvisuelle Komponente, wie der Designer sie als Symbol zeigt.</summary>
function IsNonVisual(AComponent, ARoot: TComponent): Boolean;
begin
  Result := (AComponent.Owner = ARoot) and not (AComponent is TControl) and not AComponent.HasParent and
    (AComponent.Name <> '');
end;

function PositionOf(AComponent: TComponent): TPoint;
begin
  // DesignInfo: Left im unteren, Top im oberen Wort, wie Left/Top in der DFM.
  Result := TPoint.Create(SmallInt(LongRec(AComponent.DesignInfo).Lo), SmallInt(LongRec(AComponent.DesignInfo).Hi));
end;

/// <summary>Name des Ziels eines Verweises: im eigenen Formular der Name, sonst „Besitzer.Name“.</summary>
function TargetName(AComponent, ARoot: TComponent): string;
begin
  Result := '';
  if AComponent = nil then
  begin
    Exit;
  end;
  Result := AComponent.Name;
  if (AComponent <> ARoot) and (AComponent.Owner <> ARoot) and (AComponent.Owner <> nil) and
    (AComponent.Owner.Name <> '') then
  begin
    Result := AComponent.Owner.Name + '.' + Result;
  end;
end;

/// <summary>Veröffentlichte Eigenschaften vom Typ einer Komponente, ohne Unterkomponenten (EditLabel …).
/// </summary>
function RefsOf(AComponent, ARoot: TComponent): TArray<TAtlasStructureRef>;
var
  mList: PPropList;
  mCount, mIndex: Integer;
  mProp: PPropInfo;
  mValue: TObject;
begin
  Result := nil;
  mCount := GetPropList(AComponent, mList);
  try
    for mIndex := 0 to mCount - 1 do
    begin
      mProp := mList^[mIndex];
      if (mProp^.PropType^.Kind <> tkClass) or
        not GetTypeData(mProp^.PropType^).ClassType.InheritsFrom(TComponent) then
      begin
        Continue;
      end;
      mValue := GetObjectProp(AComponent, mProp);
      if (mValue = nil) or not (csSubComponent in TComponent(mValue).ComponentStyle) then
      begin
        Result := Result + [TAtlasStructureRef.Create(string(mProp^.Name), TargetName(TComponent(mValue), ARoot))];
      end;
    end;
  finally
    FreeMem(mList);
  end;
end;

function SignatureOf(const AItems: TArray<TAtlasStructureItem>; ARoot: TComponent): string;
var
  mItem: TAtlasStructureItem;
  mRef: TAtlasStructureRef;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(ARoot.Name);
    for mItem in AItems do
    begin
      mBuilder.Append('|').Append(mItem.Name).Append(':').Append(mItem.ClassName).Append('<').Append(mItem.Parent);
      for mRef in mItem.Refs do
      begin
        mBuilder.Append(',').Append(mRef.Prop).Append('=').Append(mRef.Target);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
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

function CanDrop: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (PaletteClass <> nil) and TAtlasDesignerAccess.Current(mEditor, mRoot);
end;

/// <summary>Komponente AName im Formular ARoot, auch das Formular selbst; nil ohne sie.</summary>
function ComponentOf(ARoot: TComponent; const AName: string): TComponent;
begin
  if SameText(ARoot.Name, AName) then
  begin
    Exit(ARoot);
  end;
  Result := ARoot.FindComponent(AName);
end;

{ TAtlasIdeStructure }

constructor TAtlasIdeStructure.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTick;
  FTimer.OnTimer := Tick;
  FPalette := TAtlasPaletteImages.Create;
  FMenu := TPopupMenu.Create(nil);
end;

destructor TAtlasIdeStructure.Destroy;
begin
  FTimer.Enabled := False;
  CloseWindow;
  FreeAndNil(FHost);
  FTimer.Free;
  FMenu.Free;
  FPalette.Free;
  inherited Destroy;
end;

function TAtlasIdeStructure.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
begin
  if not ASettings.DesignerStructure then
  begin
    CloseWindow;
    Exit(Default(TAtlasDesignerButton));
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.Structure,
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StHint));
  Result.Pressed := (FHost <> nil) and FHost.Shown;
end;

function TAtlasIdeStructure.Frame: TAtlasStructureFrame;
begin
  Result := nil;
  if (FHost <> nil) and (FHost.Frame is TAtlasStructureFrame) then
  begin
    Result := TAtlasStructureFrame(FHost.Frame);
  end;
end;

procedure TAtlasIdeStructure.Toggle;
begin
  if (FHost <> nil) and FHost.Shown then
  begin
    CloseWindow;
  end
  else if Open then
  begin
    HideOnForm(TAtlasIdeSettings.Current.DesignerStructureHideOnForm);
    FTimer.Enabled := True;
  end;
end;

function TAtlasIdeStructure.Open: Boolean;
var
  mDock: TStructureDock;
  mCreated: Boolean;
begin
  if FHost = nil then
  begin
    mDock := TStructureDock.Create;
    FHost := TAtlasIdeDockWindow.Create(mDock, False);
    mDock.OnFrame :=
      procedure(AFrame: TCustomFrame)
      begin
        FHost.FrameCreated(AFrame);
      end;
  end;
  Result := FHost.Show(mCreated) and (Frame <> nil);
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

procedure TAtlasIdeStructure.CloseWindow;
begin
  FTimer.Enabled := False;
  HideOnForm(False);
  if (FHost <> nil) and FHost.Shown then
  begin
    FHost.Hide;
  end;
end;

procedure TAtlasIdeStructure.Wire(AFrame: TAtlasStructureFrame);
begin
  AFrame.Images := FPalette.Images;
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
  AFrame.OnChanged :=
    procedure(AFilter: string; AByKind: Boolean)
    begin
      FFilter := AFilter;
      FByKind := AByKind;
      Fill(True);
    end;
end;

procedure TAtlasIdeStructure.Place;
var
  mEditors: INTAEditorServices;
  mEdit: TRect;
  mForm: TCustomForm;
  mWidth: Integer;
begin
  mForm := FHost.Form;
  if (mForm = nil) or (mForm.Parent <> nil) then
  begin
    // Schon angedockt: dort lassen.
    Exit;
  end;
  if not Supports(BorlandIDEServices, INTAEditorServices, mEditors) or (mEditors.TopEditWindow = nil) or
    (mEditors.TopEditWindow.Form = nil) then
  begin
    Exit;
  end;
  mEdit := mEditors.TopEditWindow.Form.BoundsRect;
  mWidth := MulDiv(cWindowWidth, mForm.CurrentPPI, cBasePpi);
  // Schwebend am rechten Rand des Editorfensters; danach dockt man es wie jedes Fenster der IDE an.
  mForm.SetBounds(mEdit.Right - mWidth, mEdit.Top, mWidth, mEdit.Height);
end;

procedure TAtlasIdeStructure.Tick(Sender: TObject);
begin
  if (FHost = nil) or not FHost.Shown then
  begin
    // Mit dem X geschlossen: vorherigen Zustand der Formularfläche wiederherstellen.
    CloseWindow;
    Exit;
  end;
  Fill(False);
  SyncSelection;
end;

function TAtlasIdeStructure.Items(ARoot: TComponent): TArray<TAtlasStructureItem>;
var
  mIndex: Integer;
  mComponent: TComponent;
  mItem: TAtlasStructureItem;
begin
  Result := nil;
  FPalette.Forget;
  for mIndex := -1 to ARoot.ComponentCount - 1 do
  begin
    if mIndex < 0 then
    begin
      mComponent := ARoot;
    end
    else
    begin
      mComponent := ARoot.Components[mIndex];
    end;
    if not (mComponent is TControl) and not IsNonVisual(mComponent, ARoot) then
    begin
      Continue;
    end;
    mItem := Default(TAtlasStructureItem);
    mItem.Name := mComponent.Name;
    mItem.ClassChain := TAtlasDesignerAccess.ClassChain(mComponent);
    // Das Formular ist die Wurzel des Baums, auch als Datenmodul.
    mItem.IsControl := (mComponent is TControl) or (mComponent = ARoot);
    if mItem.IsControl and (mComponent <> ARoot) then
    begin
      mItem.Parent := TargetName(TControl(mComponent).Parent, ARoot);
    end;
    mItem.Position := PositionOf(mComponent);
    mItem.Refs := RefsOf(mComponent, ARoot);
    FPalette.Remember(mComponent.ClassType);
    Result := Result + [mItem];
  end;
end;

procedure TAtlasIdeStructure.Fill(AForce: Boolean);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mFrame: TAtlasStructureFrame;
  mItems: TArray<TAtlasStructureItem>;
  mSignature, mRootName: string;
begin
  mFrame := Frame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mItems := nil;
  mSignature := '';
  mRootName := '';
  if TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    mItems := Items(mRoot);
    mSignature := SignatureOf(mItems, mRoot);
    mRootName := mRoot.Name;
  end;
  if not AForce and (mSignature = FSignature) then
  begin
    Exit;
  end;
  FSignature := mSignature;
  FMarked := '';
  mFrame.ShowNodes(TAtlasStructure.Nodes(mItems, mRootName, FByKind, FFilter),
    function(ANode: TAtlasStructureNode): Integer
    begin
      Result := NodeImage(ANode);
    end);
end;

function TAtlasIdeStructure.NodeImage(const ANode: TAtlasStructureNode): Integer;
begin
  Result := FPalette.IndexOfName(ANode.ClassName);
end;

procedure TAtlasIdeStructure.SyncSelection;
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
    if Length(mSelected) = 1 then
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

procedure TAtlasIdeStructure.SelectName(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := ComponentOf(mRoot, AName);
  if mComponent <> nil then
  begin
    FMarked := mComponent.Name;
    TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mComponent]);
  end;
end;

class procedure TAtlasIdeStructure.OpenName(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := ComponentOf(mRoot, AName);
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if (mComponent = nil) or (mDesigner = nil) then
  begin
    Exit;
  end;
  // Wie Doppelklick im Designer: Standardbefehl des Komponenten-Editors.
  mDesigner.Edit(mComponent);
end;

procedure TAtlasIdeStructure.MenuFor(const AName: string; const APoint: TPoint);
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
  mComponent := ComponentOf(mRoot, AName);
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

procedure TAtlasIdeStructure.MenuClick(Sender: TObject);
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
  mComponent := ComponentOf(mRoot, FMenuComponent);
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

procedure TAtlasIdeStructure.Drop;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mClass: TComponentClass;
  mCreated: IOTAComponent;
  mComponent: TComponent;
  mPoint: TPoint;
  mOccupied: TArray<TPoint>;
  mItem: TAtlasStructureItem;
begin
  mClass := PaletteClass;
  if (mClass = nil) or not TAtlasDesignerAccess.Current(mEditor, mRoot) or not (mRoot is TWinControl) then
  begin
    Exit;
  end;
  mOccupied := nil;
  for mItem in Items(mRoot) do
  begin
    if not mItem.IsControl then
    begin
      mOccupied := mOccupied + [mItem.Position];
    end;
  end;
  mPoint := TAtlasStructure.FreePosition(mOccupied, TAtlasDesignerModel.ClientOf(TWinControl(mRoot)));
  try
    mCreated := mEditor.CreateComponent(mEditor.GetRootComponent, mClass.ClassName, mPoint.X, mPoint.Y, 0, 0);
  except
    on E: Exception do
    begin
      FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.StCreateFailed,
        [mClass.ClassName, E.Message]));
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
  FOnMessage(TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.StCreated, [mComponent.Name]));
  Fill(True);
  SelectName(mComponent.Name);
end;

procedure TAtlasIdeStructure.HideOnForm(AHide: Boolean);
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
      FOnMessage(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StHideMissing));
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

procedure TAtlasIdeStructure.ApplyTheme;
begin
  if Frame <> nil then
  begin
    TAtlasIdeDockWindow.ApplyIdeTheme(Frame);
  end;
end;

end.
