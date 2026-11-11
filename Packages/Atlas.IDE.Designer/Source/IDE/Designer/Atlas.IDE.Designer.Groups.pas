unit Atlas.IDE.Designer.Groups;

// Gruppen ohne Container im Designer (#744) in der IDE:
// - Gruppieren (Strg+G, Menü „Anordnen“) für mindestens zwei markierte
//   Steuerelemente im selben Parent; Name mit Vorschlag aus dem ersten Label
//   oder dem gemeinsamen Wortteil. Gruppe auflösen (Strg+Umschalt+G).
// - Ein Klick auf ein Mitglied wählt die ganze Gruppe (nach dem Klick über
//   IDesignNotification.SelectionChanged ergänzt). Ein einzelnes Mitglied
//   wählt Alt+Klick oder, mit designer.groups.memberClick = doubleClick, ein
//   zweiter Klick darauf. Verschieben mit Maus und Strg+Pfeil macht die IDE
//   dann für alle markierten. Ist eine Gruppe markiert, zeigt ein
//   gestrichelter Rahmen sie mit ihrem Namen.
// - Gelöschte Mitglieder fallen heraus, Umbenennungen ziehen mit; eingefügte
//   Kopien einer Gruppe werden wieder eine Gruppe.
// - Ablage wie die Auswahlsätze (#739): lokal in %LOCALAPPDATA%\Atlas\
//   designer-groups.json oder geteilt in .atlas-groups.json neben dem
//   Formular (designer.groups.storage). Die DFM bleibt unberührt.
// - „Gruppen rückgängig“ nimmt das letzte Gruppieren oder Auflösen zurück.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  DesignIntf,
  ToolsAPI,
  Atlas.Core.Designer.SelectionSets,
  Atlas.Core.Designer.Groups,
  Atlas.UI.Designer.Outlines,
  Atlas.IDE.Foundation.KeyHook;

type
  TAtlasIdeDesignerGroups = class;

  /// <summary>Strg+G und Strg+Umschalt+G, solange der Designer den Fokus hat.</summary>
  TAtlasGroupKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdeDesignerGroups;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  /// <summary>Stand vor dem letzten Gruppieren oder Auflösen.</summary>
  TAtlasGroupUndo = record
    FormFile: string;
    Groups: TArray<TAtlasSelectionSet>;
    Has: Boolean;
  end;

  /// <summary>Auswahl nach dem letzten Abgleich und zuletzt zur Gruppe ergänztes Mitglied.</summary>
  TAtlasGroupClick = record
    Selected: TArray<string>;
    Single: string;
    Tick: UInt64;
  end;

  TAtlasIdeDesignerGroups = class
  private type
    TNotification = class(TInterfacedObject, IDesignNotification)
    private
      FOwner: TAtlasIdeDesignerGroups;
    public
      procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemsModified(const ADesigner: IDesigner);
      procedure SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
      procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
      procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
    end;
  private class var
    FCurrent: TAtlasIdeDesignerGroups;
  private
    FOnMessage: TProc<string>;
    FStores: TObjectDictionary<string, TAtlasDesignerGroups>;
    FKept: TDictionary<string, Boolean>;
    /// <summary>Gesehene Komponenten mit ihrem letzten Namen (Umbenennen erkennen).</summary>
    FSeen: TDictionary<TComponent, string>;
    FInserted: TList<TComponent>;
    FNotification: TNotification;
    FNotificationRef: IDesignNotification;
    FKeys: TAtlasGroupKeys;
    FOutlines: TAtlasDesignerOutlines;
    FBusy: Boolean;
    FQueued: Boolean;
    FClick: TAtlasGroupClick;
    FUndo: TAtlasGroupUndo;
    procedure Say(const AText: string);
    function Store(const AFormFile: string): TAtlasDesignerGroups;
    procedure Save(const AFormFile: string);
    procedure KeepUndo(const AFormFile: string);
    procedure Queue;
    procedure Follow;
    procedure Reconcile(ARoot: TComponent; const AFormFile: string);
    procedure TakeCopies(ARoot: TComponent; const AFormFile: string);
    procedure ExpandSelection(const AEditor: IOTAFormEditor; ARoot: TComponent; const AFormFile: string);
    function SecondClick(const ANames: TArray<string>): Boolean;
    function Frames(ARoot: TWinControl; const AFormFile: string): TArray<TAtlasOutline>;
    procedure ShowFrames(ARoot: TComponent; const AFormFile: string);
    procedure HideFrames;
    procedure Refresh(ARoot: TComponent; const AEditor: IOTAFormEditor);
    procedure Deleted(AComponent: TComponent);
    procedure Inserted(AComponent: TComponent);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Markierte Steuerelemente gruppieren (fragt nach dem Namen).</summary>
    procedure Group;
    /// <summary>Gruppe der markierten Steuerelemente auflösen.</summary>
    procedure Ungroup;
    function CanUndo: Boolean;
    procedure Undo;
    procedure ApplyTheme;
    /// <summary>Tasten an- oder abmelden (Einstellungen, Designer gezeigt).</summary>
    procedure UpdateKeys(AWanted: Boolean);
    /// <summary>Gehört ein markiertes Steuerelement zu einer Gruppe?</summary>
    function HasGroup: Boolean;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.Types,
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Diagnostics.Deadline;

const
  cKeyPriority = 50;
  cLocalFile = 'designer-groups.json';
  cSharedFile = '.atlas-groups.json';
  cFrameGap = 4;

function Shared: Boolean;
begin
  Result := SameText(TAtlasIdeSettings.Current.DesignerGroupsStorage, TAtlasPluginSettings.cDesignerSetsShared);
end;

function StoreFile(const AFormFile: string): string;
var
  mLocal: string;
begin
  if Shared then
  begin
    Exit(TPath.Combine(ExtractFilePath(AFormFile), cSharedFile));
  end;
  mLocal := GetEnvironmentVariable('LOCALAPPDATA');
  if mLocal = '' then
  begin
    mLocal := TPath.GetTempPath;
  end;
  Result := TPath.Combine(TPath.Combine(mLocal, 'Atlas'), cLocalFile);
end;

function FormKey(const AFormFile: string): string;
begin
  Result := AFormFile;
  if Shared then
  begin
    Result := ExtractFileName(AFormFile);
  end;
end;

function Names(const AComponents: TArray<TComponent>): TArray<string>;
var
  mComponent: TComponent;
begin
  Result := nil;
  for mComponent in AComponents do
  begin
    Result := Result + [mComponent.Name];
  end;
end;

function ParentNames(const AComponents: TArray<TComponent>): TArray<string>;
var
  mComponent: TComponent;
begin
  Result := nil;
  for mComponent in AComponents do
  begin
    if not (mComponent is TControl) or (TControl(mComponent).Parent = nil) then
    begin
      Exit(nil);
    end;
    Result := Result + [TControl(mComponent).Parent.Name];
  end;
end;

/// <summary>Text des ersten Labels der Auswahl (oben links zuerst).</summary>
function FirstLabel(const AComponents: TArray<TComponent>): string;
var
  mComponent: TComponent;
  mBest: TControl;
begin
  mBest := nil;
  for mComponent in AComponents do
  begin
    if (mComponent is TCustomLabel) and ((mBest = nil) or (TControl(mComponent).Top < mBest.Top) or
      ((TControl(mComponent).Top = mBest.Top) and (TControl(mComponent).Left < mBest.Left))) then
    begin
      mBest := TControl(mComponent);
    end;
  end;
  Result := '';
  if mBest <> nil then
  begin
    Result := TLabel(mBest).Caption;
  end;
end;

function ShapeOf(AControl: TControl): TAtlasGroupShape;
begin
  Result := TAtlasGroupShape.Create(AControl.Name, AControl.ClassName, AControl.BoundsRect);
end;

function Found(ARoot: TComponent; const ANames: TArray<string>): TArray<TComponent>;
var
  mName: string;
begin
  Result := nil;
  for mName in ANames do
  begin
    if ARoot.FindComponent(mName) <> nil then
    begin
      Result := Result + [ARoot.FindComponent(mName)];
    end;
  end;
end;

function Touches(const AMembers, ASelected: TArray<string>): Boolean;
var
  mName: string;
  mMember: string;
begin
  Result := False;
  for mName in ASelected do
  begin
    for mMember in AMembers do
    begin
      Result := Result or SameText(mName, mMember);
    end;
  end;
end;

{ TAtlasGroupKeys }

function TAtlasGroupKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := TAtlasIdeSettings.Current.DesignerGroups and TAtlasDesignerAccess.Focused and (AKey = Ord('G')) and
    ((AShift = [ssCtrl]) or (AShift = [ssCtrl, ssShift]));
end;

procedure TAtlasGroupKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeDesignerGroups;
  mUngroup: Boolean;
begin
  mOwner := FOwner;
  mUngroup := ssShift in AShift;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if mUngroup then
      begin
        mOwner.Ungroup;
      end
      else
      begin
        mOwner.Group;
      end;
    end);
end;

{ TAtlasIdeDesignerGroups.TNotification }

procedure TAtlasIdeDesignerGroups.TNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if (FOwner <> nil) and (AItem is TComponent) then
  begin
    FOwner.Deleted(TComponent(AItem));
  end;
end;

procedure TAtlasIdeDesignerGroups.TNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if (FOwner <> nil) and (AItem is TComponent) then
  begin
    FOwner.Inserted(TComponent(AItem));
  end;
end;

procedure TAtlasIdeDesignerGroups.TNotification.ItemsModified(const ADesigner: IDesigner);
begin
  if FOwner <> nil then
  begin
    FOwner.Queue;
  end;
end;

procedure TAtlasIdeDesignerGroups.TNotification.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
begin
  if FOwner <> nil then
  begin
    FOwner.Queue;
  end;
end;

procedure TAtlasIdeDesignerGroups.TNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
end;

procedure TAtlasIdeDesignerGroups.TNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
begin
  if (FOwner <> nil) and (FOwner.FOutlines <> nil) then
  begin
    FOwner.FOutlines.HideOutlines;
  end;
end;

{ TAtlasIdeDesignerGroups }

constructor TAtlasIdeDesignerGroups.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FStores := TObjectDictionary<string, TAtlasDesignerGroups>.Create([doOwnsValues]);
  FKept := TDictionary<string, Boolean>.Create;
  FSeen := TDictionary<TComponent, string>.Create;
  FInserted := TList<TComponent>.Create;
  FKeys := TAtlasGroupKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
  FNotification := TNotification.Create;
  FNotification.FOwner := Self;
  FNotificationRef := FNotification;
  RegisterDesignNotification(FNotificationRef);
  FCurrent := Self;
end;

destructor TAtlasIdeDesignerGroups.Destroy;
begin
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  if FNotification <> nil then
  begin
    FNotification.FOwner := nil;
    UnregisterDesignNotification(FNotificationRef);
    FNotificationRef := nil;
  end;
  TAtlasKeyHook.Remove(FKeys);
  FKeys.Free;
  FOutlines.Free;
  FInserted.Free;
  FSeen.Free;
  FKept.Free;
  FStores.Free;
  inherited Destroy;
end;

procedure TAtlasIdeDesignerGroups.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

function TAtlasIdeDesignerGroups.Store(const AFormFile: string): TAtlasDesignerGroups;
var
  mFile: string;
  mGroups: TAtlasDesignerGroups;
begin
  mFile := UpperCase(StoreFile(AFormFile));
  if FStores.TryGetValue(mFile, Result) then
  begin
    Exit;
  end;
  mGroups := TAtlasDesignerGroups.Create;
  FStores.Add(mFile, mGroups);
  if not TAtlasDataFile.Writable(TAtlasDataFile.Load(StoreFile(AFormFile),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsKind),
    function(const AText: string): Boolean
    begin
      Result := mGroups.LoadJson(AText);
    end)) then
  begin
    FKept.AddOrSetValue(mFile, True);
  end;
  Result := mGroups;
end;

procedure TAtlasIdeDesignerGroups.Save(const AFormFile: string);
var
  mGroups: TAtlasDesignerGroups;
begin
  mGroups := Store(AFormFile);
  if not mGroups.Changed or FKept.ContainsKey(UpperCase(StoreFile(AFormFile))) then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(StoreFile(AFormFile), mGroups.ToJson);
    mGroups.Changed := False;
  except
    on E: Exception do
    begin
      TAtlasDataFile.ReportNotWritten(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsKind), E);
    end;
  end;
end;

procedure TAtlasIdeDesignerGroups.KeepUndo(const AFormFile: string);
begin
  FUndo.FormFile := AFormFile;
  FUndo.Groups := Store(AFormFile).GroupsOf(FormKey(AFormFile));
  FUndo.Has := True;
end;

procedure TAtlasIdeDesignerGroups.Deleted(AComponent: TComponent);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  FSeen.Remove(AComponent);
  FInserted.Remove(AComponent);
  if TAtlasIdeSettings.Current.DesignerGroups and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    (AComponent.Owner = mRoot) then
  begin
    Store(mEditor.FileName).ComponentDeleted(FormKey(mEditor.FileName), AComponent.Name);
    Save(mEditor.FileName);
  end;
end;

procedure TAtlasIdeDesignerGroups.Inserted(AComponent: TComponent);
begin
  if not FBusy and TAtlasIdeSettings.Current.DesignerGroups and (AComponent is TControl) then
  begin
    FInserted.Add(AComponent);
  end;
end;

procedure TAtlasIdeDesignerGroups.Queue;
var
  mOwner: TAtlasIdeDesignerGroups;
begin
  if FBusy or FQueued or not TAtlasIdeSettings.Current.DesignerGroups then
  begin
    Exit;
  end;
  // Erst nach dem Klick bzw. Einfügen: dann steht die Auswahl der IDE fest.
  FQueued := True;
  mOwner := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
    procedure
    begin
      if FCurrent = mOwner then
      begin
        mOwner.FQueued := False;
        TAtlasGuard.Run(TAtlasFeature.DesignerBar,
          procedure
          begin
            mOwner.Follow;
          end);
      end;
    end);
end;

procedure TAtlasIdeDesignerGroups.Follow;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    FInserted.Clear;
    Exit;
  end;
  Reconcile(mRoot, mEditor.FileName);
  TakeCopies(mRoot, mEditor.FileName);
  ExpandSelection(mEditor, mRoot, mEditor.FileName);
  Refresh(mRoot, mEditor);
end;

procedure TAtlasIdeDesignerGroups.Reconcile(ARoot: TComponent; const AFormFile: string);
var
  mIndex: Integer;
  mComponent: TComponent;
  mOld: string;
  mGroups: TAtlasDesignerGroups;
begin
  mGroups := Store(AFormFile);
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    if FSeen.TryGetValue(mComponent, mOld) and not SameText(mOld, mComponent.Name) then
    begin
      mGroups.ComponentRenamed(FormKey(AFormFile), mOld, mComponent.Name);
    end;
    FSeen.AddOrSetValue(mComponent, mComponent.Name);
  end;
  Save(AFormFile);
end;

procedure TAtlasIdeDesignerGroups.TakeCopies(ARoot: TComponent; const AFormFile: string);
var
  mNew: TArray<TAtlasGroupShape>;
  mShapes: TArray<TArray<TAtlasGroupShape>>;
  mGroup: TAtlasSelectionSet;
  mOne: TArray<TAtlasGroupShape>;
  mComponent: TComponent;
  mGroups: TAtlasDesignerGroups;
begin
  if FInserted.Count < TAtlasDesignerGroups.cMinMembers then
  begin
    FInserted.Clear;
    Exit;
  end;
  mNew := nil;
  for mComponent in FInserted do
  begin
    mNew := mNew + [ShapeOf(TControl(mComponent))];
  end;
  FInserted.Clear;
  mGroups := Store(AFormFile);
  mShapes := nil;
  for mGroup in mGroups.GroupsOf(FormKey(AFormFile)) do
  begin
    mOne := nil;
    for mComponent in Found(ARoot, mGroup.Members) do
    begin
      if mComponent is TControl then
      begin
        mOne := mOne + [ShapeOf(TControl(mComponent))];
      end;
    end;
    mShapes := mShapes + [mOne];
  end;
  if mGroups.AddCopy(FormKey(AFormFile), mShapes, mNew) >= 0 then
  begin
    Save(AFormFile);
  end;
end;

procedure TAtlasIdeDesignerGroups.ExpandSelection(const AEditor: IOTAFormEditor; ARoot: TComponent;
  const AFormFile: string);
var
  mNames: TArray<string>;
  mExpanded: TArray<string>;
  mDesigner: IDesigner;
begin
  mNames := Names(TAtlasDesignerAccess.Selection(AEditor, ARoot));
  if (Length(mNames) = 0) or (GetKeyState(VK_MENU) < 0) or SecondClick(mNames) then
  begin
    Exit;
  end;
  mExpanded := Store(AFormFile).Expand(FormKey(AFormFile), mNames);
  mDesigner := TAtlasDesignerAccess.DesignerOf(AEditor);
  if (Length(mExpanded) <= Length(mNames)) or (mDesigner = nil) then
  begin
    Exit;
  end;
  if Length(mNames) = 1 then
  begin
    FClick.Single := mNames[0];
    FClick.Tick := TAtlasTicks.Now;
  end;
  FBusy := True;
  try
    TAtlasDesignerAccess.Select(mDesigner, ARoot, Found(ARoot, mExpanded));
  finally
    FBusy := False;
  end;
end;

function TAtlasIdeDesignerGroups.SecondClick(const ANames: TArray<string>): Boolean;
begin
  // designer.groups.memberClick = doubleClick: das zuletzt zur Gruppe ergänzte
  // Mitglied noch einmal angeklickt wählt es allein.
  Result := SameText(TAtlasIdeSettings.Current.DesignerGroupsMemberClick,
    TAtlasPluginSettings.cDesignerGroupsDoubleClick) and
    (Length(ANames) = 1) and SameText(ANames[0], FClick.Single) and
    (TAtlasTicks.Since(FClick.Tick) <= GetDoubleClickTime);
  if Result then
  begin
    FClick.Single := '';
  end;
end;

function TAtlasIdeDesignerGroups.Frames(ARoot: TWinControl; const AFormFile: string): TArray<TAtlasOutline>;
var
  mGroups: TArray<TAtlasSelectionSet>;
  mSelected: TArray<string>;
  mIndex: Integer;
  mArea: TRect;
  mComponent: TComponent;
begin
  Result := nil;
  mSelected := FClick.Selected;
  mGroups := Store(AFormFile).GroupsOf(FormKey(AFormFile));
  for mIndex := 0 to High(mGroups) do
  begin
    if not Touches(mGroups[mIndex].Members, mSelected) then
    begin
      Continue;
    end;
    mArea := TRect.Empty;
    for mComponent in Found(ARoot, mGroups[mIndex].Members) do
    begin
      if mComponent is TControl then
      begin
        mArea.Union(TAtlasDesignerAccess.BoundsInRoot(TControl(mComponent), ARoot));
      end;
    end;
    if not mArea.IsEmpty then
    begin
      mArea.Inflate(cFrameGap, cFrameGap);
      Result := Result + [TAtlasOutline.Create(mArea, mGroups[mIndex].Name, False)];
    end;
  end;
end;

procedure TAtlasIdeDesignerGroups.ShowFrames(ARoot: TComponent; const AFormFile: string);
var
  mOutlines: TArray<TAtlasOutline>;
  mShifted: TArray<TAtlasOutline>;
  mOutline: TAtlasOutline;
  mArea: TRect;
begin
  mOutlines := nil;
  if ARoot is TWinControl then
  begin
    mOutlines := Frames(TWinControl(ARoot), AFormFile);
  end;
  if Length(mOutlines) = 0 then
  begin
    HideFrames;
    Exit;
  end;
  mArea := mOutlines[0].Bounds;
  for mOutline in mOutlines do
  begin
    mArea.Union(mOutline.Bounds);
  end;
  mShifted := nil;
  for mOutline in mOutlines do
  begin
    mShifted := mShifted + [TAtlasOutline.Create(Rect(mOutline.Bounds.Left - mArea.Left,
      mOutline.Bounds.Top - mArea.Top, mOutline.Bounds.Right - mArea.Left, mOutline.Bounds.Bottom - mArea.Top),
      mOutline.Name, False)];
  end;
  if FOutlines = nil then
  begin
    FOutlines := TAtlasDesignerOutlines.CreateOutlines(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  end;
  mArea.Offset(TWinControl(ARoot).ClientOrigin);
  FOutlines.ShowOutlines(mArea, mShifted);
end;

procedure TAtlasIdeDesignerGroups.HideFrames;
begin
  if FOutlines <> nil then
  begin
    FOutlines.HideOutlines;
  end;
end;

procedure TAtlasIdeDesignerGroups.Group;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mName: string;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  if (Length(mSelected) < TAtlasDesignerGroups.cMinMembers) or
    not TAtlasDesignerGroups.SameParent(ParentNames(mSelected)) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsNeedTwo));
    Exit;
  end;
  mName := TAtlasDesignerGroups.SuggestName(Names(mSelected), FirstLabel(mSelected));
  if not InputQuery(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsTitle),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsPrompt), mName) or (Trim(mName) = '') then
  begin
    Exit;
  end;
  KeepUndo(mEditor.FileName);
  Store(mEditor.FileName).Add(FormKey(mEditor.FileName), Trim(mName), Names(mSelected));
  Save(mEditor.FileName);
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerGroupsMade, [Trim(mName), Length(mSelected)]));
  Refresh(mRoot, mEditor);
end;

procedure TAtlasIdeDesignerGroups.Ungroup;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mName: string;
  mGroups: TAtlasDesignerGroups;
  mDone: Boolean;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  KeepUndo(mEditor.FileName);
  mGroups := Store(mEditor.FileName);
  mDone := False;
  for mName in Names(TAtlasDesignerAccess.Selection(mEditor, mRoot)) do
  begin
    mDone := mGroups.Ungroup(FormKey(mEditor.FileName), mName) or mDone;
  end;
  if not mDone then
  begin
    FUndo.Has := False;
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsNone));
    Exit;
  end;
  Save(mEditor.FileName);
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsUngrouped));
  Refresh(mRoot, mEditor);
end;

procedure TAtlasIdeDesignerGroups.Refresh(ARoot: TComponent; const AEditor: IOTAFormEditor);
begin
  FClick.Selected := Names(TAtlasDesignerAccess.Selection(AEditor, ARoot));
  ShowFrames(ARoot, AEditor.FileName);
end;

function TAtlasIdeDesignerGroups.CanUndo: Boolean;
begin
  Result := FUndo.Has;
end;

procedure TAtlasIdeDesignerGroups.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  if not FUndo.Has then
  begin
    Exit;
  end;
  FUndo.Has := False;
  Store(FUndo.FormFile).Restore(FormKey(FUndo.FormFile), FUndo.Groups);
  Save(FUndo.FormFile);
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGroupsUndone));
  if TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Refresh(mRoot, mEditor);
  end;
end;

procedure TAtlasIdeDesignerGroups.ApplyTheme;
begin
  if FOutlines <> nil then
  begin
    FOutlines.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

procedure TAtlasIdeDesignerGroups.UpdateKeys(AWanted: Boolean);
begin
  if AWanted and TAtlasIdeSettings.Current.DesignerGroups then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
    HideFrames;
  end;
end;

function TAtlasIdeDesignerGroups.HasGroup: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mName: string;
begin
  Result := False;
  if TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    for mName in Names(TAtlasDesignerAccess.Selection(mEditor, mRoot)) do
    begin
      Result := Result or (Store(mEditor.FileName).IndexOf(FormKey(mEditor.FileName), mName) >= 0);
    end;
  end;
end;

end.
