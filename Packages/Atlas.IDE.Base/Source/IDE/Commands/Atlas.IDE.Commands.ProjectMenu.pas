unit Atlas.IDE.Commands.ProjectMenu;

// Untermenü „Atlas“ im Kontextmenü der Projektverwaltung (#1817,
// commands.projectContextMenu). Die IDE fragt bei jedem Rechtsklick die
// angemeldeten IOTAProjectMenuItemCreatorNotifier nach Einträgen
// (IOTAProjectManagerMenu) und gibt sie nach dem Menü wieder frei; anders als
// im Editor gibt es deshalb keinen Vorrat fester Plätze.
// - Beim Aufbau kennt die IDE nur die Art der gewählten Knoten (IdentList:
//   Datei, Ordner, Projekt) und das Projekt; Atlas legt daraus eine ungeklärte
//   Auswahl in TAtlasProjectContext (Atlas.Core.Commands.ProjectSelection),
//   fragt Text und Sichtbarkeit der Befehle und lässt Einträge, die nicht
//   passen, weg (statt sie grau zu zeigen).
// - Beim Ausführen nennt MenuContextList je Knoten Kennung und Projekt; daraus
//   wird die Auswahl geklärt (Units der Dateien, Ordner und Projekte) und liegt
//   während des Befehls in TAtlasProjectContext.
// - Einträge: „Mit Atlas prüfen“ von Base, danach die Einträge der Module mit
//   TAtlasMenuPlace.ProjectContext (Section = Untermenü, Trennlinien „-“, wie
//   im Kontextmenü des Editors verteilt von Atlas.Core.Commands.MenuSlots). Der
//   Befehl wird beim Klick über seine Id neu gesucht: Ein abgemeldetes Modul
//   erreicht er nicht mehr (Regel 3).
// - Name und Verb jedes Eintrags sind gültige Komponentennamen
//   (TAtlasMenuSlots.MenuName): Die IDE übernimmt Name als TMenuItem.Name, ein
//   Punkt darin ließ jeden Rechtsklick in der Projektverwaltung scheitern.
// - Uninstall meldet den Notifier ab; danach baut die IDE kein Atlas-Menü
//   mehr, und ein noch offenes Menü ruft nichts mehr auf.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils;

type
  TAtlasIdeProjectMenu = class
  public
    /// <summary>Beim Projektmanager anmelden. ACheck prüft die Units der Auswahl („Mit Atlas prüfen“),
    /// ACheckVisible sagt, ob es den Eintrag gibt.</summary>
    class procedure Install(const ACheck: TProc<TArray<string>>; const ACheckVisible: TFunc<Boolean>); static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
  end;

implementation

uses
  System.Classes,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Commands.MenuSlots,
  Atlas.Core.Commands.ProjectSelection,
  Atlas.UI.Commands.Strings,
  Atlas.IDE.Foundation.Settings;

const
  // Name und Verb: nur Buchstaben und Ziffern (Komponentenname, siehe oben).
  cRootVerb = 'AtlasProjectMenu';
  cItemVerb = 'AtlasProjectMenuItem';
  cGroupVerb = 'AtlasProjectMenuGroup';
  cCheckId = 'Atlas.ProjectCheck';
  // Weit unten im Menü, nach den Einträgen der IDE; die Abstände lassen Platz für Einträge darunter.
  cRootPosition = 9000000;
  cPositionStep = 10;

type
  /// <summary>Ein Eintrag; die IDE gibt ihn nach dem Menü frei. Ohne CommandId: Untermenü.</summary>
  TProjectMenuItem = class(TNotifierObject, IOTALocalMenu, IOTAProjectManagerMenu)
  private
    FCaption: string;
    FName: string;
    FParent: string;
    FVerb: string;
    FPosition: Integer;
    FHelpContext: Integer;
    FChecked: Boolean;
    FEnabled: Boolean;
    FMultiSelectable: Boolean;
    FCommandId: string;
  public
    constructor Create(const ACaption, AVerb, AParent, ACommandId: string; APosition: Integer);
    function GetCaption: string;
    function GetChecked: Boolean;
    function GetEnabled: Boolean;
    function GetHelpContext: Integer;
    function GetName: string;
    function GetParent: string;
    function GetPosition: Integer;
    function GetVerb: string;
    procedure SetCaption(const Value: string);
    procedure SetChecked(Value: Boolean);
    procedure SetEnabled(Value: Boolean);
    procedure SetHelpContext(Value: Integer);
    procedure SetName(const Value: string);
    procedure SetParent(const Value: string);
    procedure SetPosition(Value: Integer);
    procedure SetVerb(const Value: string);
    function GetIsMultiSelectable: Boolean;
    procedure SetIsMultiSelectable(Value: Boolean);
    procedure Execute(const MenuContextList: IInterfaceList); overload;
    function PreExecute(const MenuContextList: IInterfaceList): Boolean;
    function PostExecute(const MenuContextList: IInterfaceList): Boolean;
  end;

  TProjectMenuCreator = class(TNotifierObject, IOTANotifier, IOTAProjectMenuItemCreatorNotifier)
  public
    procedure AddMenu(const Project: IOTAProject; const IdentList: TStrings;
      const ProjectManagerMenuList: IInterfaceList; IsMultiSelect: Boolean);
  end;

  /// <summary>Ein Eintrag des Untermenüs vor der Verteilung: Befehl mit Text und Sichtbarkeit, Section.</summary>
  TProjectEntry = record
    Id: string;
    Caption: string;
    Section: string;
    Visible: Boolean;
  end;

var
  GNotifier: Integer = -1;
  GCheck: TProc<TArray<string>>;
  GCheckVisible: TFunc<Boolean>;

function Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.ProjectContextMenu and
    not TAtlasGuard.Disabled(TAtlasFeature.EditorCommands);
end;

/// <summary>Dateien des Projekts (Units, Formulare, Ressourcen) aus der Projektverwaltung.</summary>
function FilesOf(const AProject: IOTAProject): TArray<string>;
var
  mIndex, mCount: Integer;
  mInfo: IOTAModuleInfo;
  mFileName: string;
begin
  Result := nil;
  if AProject = nil then
  begin
    Exit;
  end;
  // Einmal in voller Größe anlegen: Projekte mit über 2000 Dateien, Anhängen je Datei kopierte jedes Mal alles.
  SetLength(Result, AProject.GetModuleCount);
  mCount := 0;
  for mIndex := 0 to High(Result) do
  begin
    mInfo := AProject.GetModule(mIndex);
    if mInfo = nil then
    begin
      Continue;
    end;
    mFileName := mInfo.FileName;
    if mFileName <> '' then
    begin
      Result[mCount] := mFileName;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

function ProjectFileOf(const AProject: IOTAProject): string;
begin
  Result := '';
  if AProject <> nil then
  begin
    Result := AProject.FileName;
  end;
end;

/// <summary>Auswahl beim Aufbau: Arten aus den Kennungen der IDE; stehen dort schon Dateinamen, gleich geklärt.
/// </summary>
function MenuSelection(const AProject: IOTAProject; const AIdents: TStrings; AMultiple: Boolean):
  TAtlasProjectSelection;
var
  mIdent: string;
  mKinds: TAtlasProjectNodeKinds;
  mPaths: TArray<string>;
begin
  mKinds := [];
  mPaths := nil;
  for mIdent in AIdents do
  begin
    if mIdent = sFileContainer then
    begin
      // Datei unbekannter Art: kann eine Unit sein.
      Include(mKinds, TAtlasProjectNodeKind.SourceFile);
    end
    else if mIdent = sDirectoryContainer then
    begin
      Include(mKinds, TAtlasProjectNodeKind.Folder);
    end
    else if mIdent = sProjectContainer then
    begin
      Include(mKinds, TAtlasProjectNodeKind.Project);
    end
    else if mIdent.Contains(PathDelim) then
    begin
      mPaths := mPaths + [mIdent];
    end;
  end;
  if Length(mPaths) > 0 then
  begin
    Exit(TAtlasProjectSelection.Resolve(mPaths, ProjectFileOf(AProject), FilesOf(AProject)));
  end;
  Result := TAtlasProjectSelection.OfKinds(mKinds, AMultiple, ProjectFileOf(AProject), FilesOf(AProject));
end;

/// <summary>Geklärte Auswahl aus den Knoten beim Ausführen; Knoten verschiedener Projekte zusammen.</summary>
function ExecuteSelection(const AContexts: IInterfaceList): TAtlasProjectSelection;
var
  mIndex: Integer;
  mContext: IOTAProjectMenuContext;
  mPart: TAtlasProjectSelection;
  mProject: IOTAProject;
  mFiles: TArray<string>;
begin
  mProject := nil;
  mFiles := nil;
  Result := Default(TAtlasProjectSelection);
  Result.Resolved := True;
  if AContexts = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AContexts.Count - 1 do
  begin
    if Supports(AContexts[mIndex], IOTAProjectMenuContext, mContext) then
    begin
      // Dateien je Projekt nur einmal lesen, auch wenn viele Knoten desselben Projekts gewählt sind.
      if (mFiles = nil) or (mContext.GetProject <> mProject) then
      begin
        mProject := mContext.GetProject;
        mFiles := FilesOf(mProject);
      end;
      mPart := TAtlasProjectSelection.Resolve([mContext.GetIdent], ProjectFileOf(mProject), mFiles);
      Result := TAtlasProjectSelection.Merge(Result, mPart);
    end;
  end;
end;

/// <summary>Einträge in Reihenfolge: „Mit Atlas prüfen“, dann die der Module. Läuft im Kontext der Auswahl.
/// </summary>
function Entries: TArray<TProjectEntry>;
var
  mEntry: TAtlasMenuEntry;
  mCommand: TAtlasModuleCommand;
  mItem: TProjectEntry;
begin
  mItem := Default(TProjectEntry);
  mItem.Id := cCheckId;
  mItem.Caption := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.ProjectMenuCheck);
  mItem.Visible := Assigned(GCheck) and Assigned(GCheckVisible) and GCheckVisible() and
    TAtlasProjectContext.Current.HasUnits;
  Result := [mItem];
  for mEntry in TAtlasModuleContributions.MenuEntries(AtlasModuleRegistry, TAtlasMenuPlace.ProjectContext) do
  begin
    mItem := Default(TProjectEntry);
    mItem.Id := '-';
    mItem.Section := mEntry.Section;
    if mEntry.CommandId <> '-' then
    begin
      if not TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mEntry.CommandId, mCommand) then
      begin
        Continue;
      end;
      mItem.Id := mCommand.Id;
      mItem.Caption := mCommand.Caption;
      mItem.Visible := TAtlasModuleContributions.IsVisible(mCommand);
    end;
    Result := Result + [mItem];
  end;
end;

/// <summary>Einträge auf das Untermenü verteilen; AParent ist das Verb von Atlas bzw. einer Gruppe.</summary>
procedure AddList(const AList: TAtlasSlotList; const AEntries: TArray<TProjectEntry>; const AParent: string;
  const AMenus: IInterfaceList; var APosition: Integer);
var
  mSlot, mItem: Integer;
  mCaption: string;
begin
  for mSlot := 0 to High(AList.Items) do
  begin
    mItem := AList.Items[mSlot];
    if (mItem < 0) or not AList.Visible[mSlot] then
    begin
      Continue;
    end;
    Inc(APosition, cPositionStep);
    mCaption := AEntries[mItem].Caption;
    if AEntries[mItem].Id = '-' then
    begin
      mCaption := '-';
    end;
    AMenus.Add(TProjectMenuItem.Create(mCaption, TAtlasMenuSlots.MenuName(cItemVerb, APosition), AParent,
      AEntries[mItem].Id, APosition));
  end;
end;

function AnyShown(const ALayout: TAtlasSlotLayout): Boolean;
var
  mGroup: TAtlasSlotList;
begin
  Result := ALayout.Top.Shown;
  for mGroup in ALayout.Groups do
  begin
    Result := Result or mGroup.Shown;
  end;
end;

procedure AddEntries(const AMenus: IInterfaceList);
var
  mEntries: TArray<TProjectEntry>;
  mItems: TArray<TAtlasSlotItem>;
  mLayout: TAtlasSlotLayout;
  mIndex, mPosition: Integer;
  mVerb: string;
begin
  mEntries := Entries;
  SetLength(mItems, Length(mEntries));
  for mIndex := 0 to High(mEntries) do
  begin
    mItems[mIndex].Id := mEntries[mIndex].Id;
    mItems[mIndex].Section := mEntries[mIndex].Section;
    mItems[mIndex].Visible := mEntries[mIndex].Visible;
  end;
  // Die IDE baut das Menü jedes Mal neu: so viele Plätze wie Einträge.
  mLayout := TAtlasMenuSlots.Layout(mItems, Length(mItems), Length(mItems), Length(mItems));
  if not AnyShown(mLayout) then
  begin
    Exit;
  end;
  mPosition := cRootPosition;
  AMenus.Add(TProjectMenuItem.Create('Atlas', cRootVerb, '', '', mPosition));
  AddList(mLayout.Top, mEntries, cRootVerb, AMenus, mPosition);
  for mIndex := 0 to High(mLayout.Groups) do
  begin
    if not mLayout.Groups[mIndex].Shown then
    begin
      Continue;
    end;
    Inc(mPosition, cPositionStep);
    mVerb := TAtlasMenuSlots.MenuName(cGroupVerb, mIndex);
    AMenus.Add(TProjectMenuItem.Create(mLayout.Groups[mIndex].Caption, mVerb, cRootVerb, '', mPosition));
    AddList(mLayout.Groups[mIndex], mEntries, mVerb, AMenus, mPosition);
  end;
end;

procedure RunCommand(const AId: string; const ASelection: TAtlasProjectSelection);
var
  mCommand: TAtlasModuleCommand;
begin
  if AId = cCheckId then
  begin
    if Assigned(GCheck) and ASelection.HasUnits then
    begin
      GCheck(ASelection.Units);
    end;
    Exit;
  end;
  // Neu suchen: Seit dem Aufbau des Menüs kann sich das Modul abgemeldet haben (Regel 3).
  if not TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, AId, mCommand) or not Assigned(mCommand.Run) then
  begin
    TAtlasGuard.Log('Project manager: command ' + AId + ' is gone');
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.EditorCommands, mCommand.Run);
end;

{ TProjectMenuItem }

constructor TProjectMenuItem.Create(const ACaption, AVerb, AParent, ACommandId: string; APosition: Integer);
begin
  inherited Create;
  FCaption := ACaption;
  FName := AVerb;
  FVerb := AVerb;
  FParent := AParent;
  FCommandId := ACommandId;
  FPosition := APosition;
  FEnabled := True;
  FMultiSelectable := True;
end;

function TProjectMenuItem.GetCaption: string;
begin
  Result := FCaption;
end;

function TProjectMenuItem.GetChecked: Boolean;
begin
  Result := FChecked;
end;

function TProjectMenuItem.GetEnabled: Boolean;
begin
  Result := FEnabled;
end;

function TProjectMenuItem.GetHelpContext: Integer;
begin
  Result := FHelpContext;
end;

function TProjectMenuItem.GetName: string;
begin
  Result := FName;
end;

function TProjectMenuItem.GetParent: string;
begin
  Result := FParent;
end;

function TProjectMenuItem.GetPosition: Integer;
begin
  Result := FPosition;
end;

function TProjectMenuItem.GetVerb: string;
begin
  Result := FVerb;
end;

procedure TProjectMenuItem.SetCaption(const Value: string);
begin
  FCaption := Value;
end;

procedure TProjectMenuItem.SetChecked(Value: Boolean);
begin
  FChecked := Value;
end;

procedure TProjectMenuItem.SetEnabled(Value: Boolean);
begin
  FEnabled := Value;
end;

procedure TProjectMenuItem.SetHelpContext(Value: Integer);
begin
  FHelpContext := Value;
end;

procedure TProjectMenuItem.SetName(const Value: string);
begin
  FName := Value;
end;

procedure TProjectMenuItem.SetParent(const Value: string);
begin
  FParent := Value;
end;

procedure TProjectMenuItem.SetPosition(Value: Integer);
begin
  FPosition := Value;
end;

procedure TProjectMenuItem.SetVerb(const Value: string);
begin
  FVerb := Value;
end;

function TProjectMenuItem.GetIsMultiSelectable: Boolean;
begin
  Result := FMultiSelectable;
end;

procedure TProjectMenuItem.SetIsMultiSelectable(Value: Boolean);
begin
  FMultiSelectable := Value;
end;

procedure TProjectMenuItem.Execute(const MenuContextList: IInterfaceList);
var
  mSelection: TAtlasProjectSelection;
begin
  // Untermenü, Trennlinie oder schon abgemeldet: nichts.
  if (FCommandId = '') or (FCommandId = '-') or (GNotifier < 0) then
  begin
    Exit;
  end;
  try
    mSelection := ExecuteSelection(MenuContextList);
    TAtlasProjectContext.Enter(mSelection);
    try
      RunCommand(FCommandId, mSelection);
    finally
      TAtlasProjectContext.Leave;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

function TProjectMenuItem.PreExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result := True;
end;

function TProjectMenuItem.PostExecute(const MenuContextList: IInterfaceList): Boolean;
begin
  Result := True;
end;

{ TProjectMenuCreator }

procedure TProjectMenuCreator.AddMenu(const Project: IOTAProject; const IdentList: TStrings;
  const ProjectManagerMenuList: IInterfaceList; IsMultiSelect: Boolean);
begin
  if (GNotifier < 0) or (ProjectManagerMenuList = nil) or (IdentList = nil) or not Wanted then
  begin
    Exit;
  end;
  try
    TAtlasProjectContext.Enter(MenuSelection(Project, IdentList, IsMultiSelect));
    try
      AddEntries(ProjectManagerMenuList);
    finally
      TAtlasProjectContext.Leave;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

{ TAtlasIdeProjectMenu }

class procedure TAtlasIdeProjectMenu.Install(const ACheck: TProc<TArray<string>>;
  const ACheckVisible: TFunc<Boolean>);
var
  mManager: IOTAProjectManager;
begin
  if GNotifier >= 0 then
  begin
    Exit;
  end;
  GCheck := ACheck;
  GCheckVisible := ACheckVisible;
  if Supports(BorlandIDEServices, IOTAProjectManager, mManager) then
  begin
    GNotifier := mManager.AddMenuItemCreatorNotifier(TProjectMenuCreator.Create);
  end;
end;

class procedure TAtlasIdeProjectMenu.Uninstall;
var
  mManager: IOTAProjectManager;
  mIndex: Integer;
begin
  mIndex := GNotifier;
  GNotifier := -1;
  GCheck := nil;
  GCheckVisible := nil;
  if (mIndex >= 0) and Supports(BorlandIDEServices, IOTAProjectManager, mManager) then
  begin
    mManager.RemoveMenuItemCreatorNotifier(mIndex);
  end;
end;

class function TAtlasIdeProjectMenu.Installed: Boolean;
begin
  Result := GNotifier >= 0;
end;

end.
