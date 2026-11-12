unit Atlas.IDE.Commands.ContextMenu;

// Untermenü „Atlas“ im Kontextmenü des Editors (#399). Die IDE baut dieses
// Menü bei jedem Öffnen aus registrierten Aktionslisten neu auf
// (INTAEditorLocalMenu); Atlas registriert dort eine TActionList mit einer
// Aktion „Atlas“ und den Einträgen als Untermenü (Kategorie „Atlas.Eintrag“).
// Früher hängte Atlas eigene TMenuItem direkt in „EditorLocalMenu“ ein; beim
// Neuaufbau meldete die IDE dann „Komponente … existiert bereits“.
// Untermenüs darin (BeginGroup/EndGroup): Die Gruppe ist eine Aktion der
// Kategorie „Atlas.Eintrag“. Die IDE baut nur diese eine Ebene; eine tiefere
// Kategorie hing sie flach an, die Gruppennamen standen dann als Zeilen
// zwischen rund 50 Einträgen. Die Aktionen der Einträge einer Gruppe liegen
// deshalb in einer eigenen, nicht registrierten Liste; beim Öffnen von „Atlas“
// (RootExecute) hängt Atlas.IDE.Commands.ContextSubmenus sie an den Eintrag der
// Gruppe. Eine Gruppe ohne sichtbaren Eintrag bleibt aus, ebenso eine, die
// commands.editorContextMenu.groups abwählt.
// Beim Öffnen liest TAtlasIdeMenuContext die Lage (Datei, Testunit, Formular,
// Debug-Sitzung, Befunde); Einträge mit Bedingung (Visible bzw. bei Modulen
// TAtlasMenuEntry.When) zeigen sich nur, wo sie passen. Trennlinien erscheinen
// nur zwischen sichtbaren Einträgen.
// Tastenkürzel stehen als ShortCut an der Aktion: Nur so zeichnet das Menü der
// IDE sie rechtsbündig (einen Tabulator in der Beschriftung zeichnet es nicht,
// der Text klebte am Kürzel). Dieselbe Taste belegt die Tastaturbindung von
// Atlas; erreicht ein Tastendruck beide, führt TAtlasKeyStroke den Befehl nur
// beim ersten aus. Kein OnUpdate: Die IDE ruft es im Leerlauf auch während des
// Compilierens, und eine geänderte Caption erreichte dort schon freigegebene
// Menüeinträge (Zugriffsverletzung beim Erzeugen). Beschriftung und Kürzel
// setzt UpdateVisibility (beim Registrieren und nach jeder
// Einstellungsänderung).
// Einträge mit einer Kennung der Befehlspalette melden sich bei den
// Tastenkürzel-Tipps (#600) als Aufruf per Kontextmenü.
// Einträge mit Sichtbarkeit nach Einstellung (AddWhen, etwa „Auswirkungen
// anzeigen“ nach navigation.impact, #1120) blendet UpdateVisibility aus bzw.
// ein; nie aus OnUpdate.
// Einträge der Module (#1455, TAtlasMenuPlace.EditorContext) belegen an der
// Stelle von AddModuleSlots einen festen Vorrat ausgeblendeter Aktionen: Die
// IDE kennt nur die einmal registrierte Liste, Module kommen und gehen aber.
// Einträge mit Section kommen in ein Untermenü dieses Namens
// (Atlas.Core.Commands.MenuSlots). UpdateVisibility (auch nach jeder Änderung
// der Registry) setzt Text, Kürzel und Sichtbarkeit der Plätze aus den
// Befehlen der Module; der Aufruf sucht den Befehl über seine Id neu, ein
// abgemeldetes Modul erreicht er nicht mehr.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ActnList,
  Vcl.Menus,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Commands.MenuSlots;

type
  TAtlasIdeContextMenu = class
  private type
    /// <summary>Befehl, Trennlinie, Untermenü, Untermenü der Module, Platz eines Moduleintrags.</summary>
    TEntryKind = (ekCommand, ekSeparator, ekGroup, ekModuleGroup, ekModuleSlot);
    TEntry = record
      Kind: TEntryKind;
      /// <summary>Befehl der Palette für die Tastenkürzel-Tipps (#600); '' = keiner. Bei Plätzen der Module die Id
      /// des belegenden Befehls.</summary>
      Id: string;
      Caption: string;
      /// <summary>Tastenkürzel als TShortCut, 0 = keins; nil ohne Kürzel.</summary>
      Key: TFunc<Integer>;
      Proc: TProc;
      /// <summary>Sicherung (#493), unter der der Eintrag läuft.</summary>
      Feature: TAtlasFeature;
      /// <summary>Sichtbar, solange das True liefert; nil = immer.</summary>
      Visible: TFunc<Boolean>;
      /// <summary>Index der Gruppe in FEntries; -1 = direkt im Untermenü Atlas.</summary>
      Parent: Integer;
      /// <summary>Plätze der Module: Untermenü der Module (-1 = direkt im Untermenü Atlas) und Platz darin.</summary>
      ModuleGroup: Integer;
      Slot: Integer;
      /// <summary>Gruppen: Kennung für commands.editorContextMenu.groups ('' = immer) und Zahl hinter dem Namen
      /// (nil = keine).</summary>
      GroupKey: string;
      Count: TFunc<Integer>;
    end;
  private const
    cCategory = 'Atlas';
    cSubCategory = 'Atlas.Eintrag';
  private
    FEntries: TArray<TEntry>;
    FActions: TActionList;
    /// <summary>Aktionen der Einträge in Gruppen; nicht bei der IDE registriert (gehören FActions).</summary>
    FSubActions: TActionList;
    FRoot: TAction;
    /// <summary>Ersatz, wenn die IDE das Öffnen von „Atlas“ nicht meldet: Gruppe als eigenes Menü.</summary>
    FGroupPopup: TPopupMenu;
    /// <summary>Aktion je Eintrag (gleicher Index wie FEntries); die IDE überschreibt Tag.</summary>
    FItems: TArray<TBasicAction>;
    FRegistered: Boolean;
    /// <summary>Offene Gruppe (Index in FEntries); -1 = keine.</summary>
    FGroup: Integer;
    /// <summary>Form des Vorrats für Module: Plätze direkt, Untermenüs und Plätze je Untermenü.</summary>
    FModuleTop, FModuleGroups, FModuleGroupSize: Integer;
    procedure Append(const AEntry: TEntry);
    function NewEntry(AKind: TEntryKind; const ACaption: string): TEntry;
    function KeyOf(AIndex: Integer): Integer;
    function CategoryOf(AIndex: Integer): string;
    function ActionOf(AIndex: Integer): TAction;
    procedure ApplyModuleSlot(AIndex: Integer; const ALayout: TAtlasSlotLayout;
      const ACommands: TArray<TAtlasModuleCommand>);
    procedure UpdateModuleSlots;
    procedure UpdateGroups;
    procedure UpdateSeparators(AParent: Integer);
    function IsLine(AIndex: Integer): Boolean;
    function ChildActions(AParent: Integer): TArray<TBasicAction>;
    procedure FillGroups(ARootItem: TMenuItem);
    procedure RunModuleSlot(AIndex: Integer);
    function IndexOfAction(AAction: TBasicAction): Integer;
    procedure ItemExecute(Sender: TObject);
    procedure RootExecute(Sender: TObject);
    procedure GroupExecute(Sender: TObject);
    procedure Register;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Eintrag anhängen; ACaption '-' ist ein Trennstrich. AKey darf nil sein.</summary>
    procedure Add(const ACaption: string; const AKey: TFunc<Integer>; const AProc: TProc); overload;
    /// <summary>Wie oben, mit dem Befehl der Palette (AId), der sich beim Aufruf bei den Tastenkürzel-Tipps meldet.
    /// </summary>
    procedure Add(const AId, ACaption: string; const AKey: TFunc<Integer>; const AProc: TProc); overload;
    /// <summary>Wie Add, unter der Sicherung AFeature statt der der Editorbefehle: Fehler anderer Einträge schalten
    /// ihn nicht ab. Eigener Name statt Überladung: anonyme Methoden als Argument vertragen keine Überladungen.
    /// </summary>
    procedure AddGuarded(AFeature: TAtlasFeature; const AId, ACaption: string; const AKey: TFunc<Integer>;
      const AProc: TProc);
    /// <summary>Wie AddGuarded, nur sichtbar, solange AVisible True liefert (geprüft beim Registrieren und in
    /// UpdateVisibility).</summary>
    procedure AddWhen(AFeature: TAtlasFeature; const AId, ACaption: string; const AKey: TFunc<Integer>;
      const AProc: TProc; const AVisible: TFunc<Boolean>);
    /// <summary>Untermenü ACaption; die folgenden Einträge bis EndGroup stehen darin. Nicht verschachtelt. AKey ist
    /// die Kennung für commands.editorContextMenu.groups ('' = immer gezeigt), ACount liefert die Zahl hinter dem
    /// Namen (nil bzw. 0 = keine).</summary>
    procedure BeginGroup(const ACaption, AKey: string; const ACount: TFunc<Integer>);
    procedure EndGroup;
    /// <summary>Plätze für Einträge der Module (#1455) an dieser Stelle (nicht in einer Gruppe): AGroupCount
    /// Untermenüs mit je AGroupSize Plätzen, danach ATopCount Plätze direkt im Untermenü Atlas. Mehr Einträge, als
    /// Plätze da sind, fehlen (Protokollzeile).</summary>
    procedure AddModuleSlots(ATopCount, AGroupCount, AGroupSize: Integer);
    /// <summary>Sichtbarkeit und Kürzel der Einträge, Gruppen und Plätze der Module neu setzen (nach geänderten
    /// Einstellungen und nach jeder Änderung der Registry).</summary>
    procedure UpdateVisibility;
    /// <summary>Registriert das Untermenü bei der IDE, einmal nach allen Add.</summary>
    procedure EnsureAll;
  end;

implementation

uses
  System.Math,
  Winapi.Windows,
  ToolsAPI,
  Atlas.UI.Commands.Strings,
  Atlas.Core.Commands.MenuContext,
  Atlas.IDE.Commands.MenuContext,
  Atlas.IDE.Commands.ContextSubmenus,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Commands.KeyStroke,
  Atlas.IDE.Commands.ShortcutTips;

constructor TAtlasIdeContextMenu.Create;
begin
  inherited Create;
  FActions := TActionList.Create(nil);
  FSubActions := TActionList.Create(nil);
  FGroup := -1;
end;

destructor TAtlasIdeContextMenu.Destroy;
var
  mServices: IOTAEditorServices;
begin
  // Vor dem Entladen abmelden, sonst greift die IDE auf freigegebene Aktionen zu.
  if FRegistered and Supports(BorlandIDEServices, IOTAEditorServices, mServices) and
    (mServices.GetEditorLocalMenu <> nil) then
  begin
    mServices.GetEditorLocalMenu.UnregisterActionList(cCategory);
  end;
  FGroupPopup.Free;
  // Die Aktionen der Gruppen gehören FActions; FSubActions gibt sie zuerst frei, FActions danach den Rest.
  FSubActions.Free;
  FActions.Free;
  inherited;
end;

function TAtlasIdeContextMenu.NewEntry(AKind: TEntryKind; const ACaption: string): TEntry;
begin
  Result := Default(TEntry);
  Result.Kind := AKind;
  Result.Caption := ACaption;
  Result.Feature := TAtlasFeature.EditorCommands;
  Result.Parent := FGroup;
  Result.ModuleGroup := -1;
  Result.Slot := -1;
end;

procedure TAtlasIdeContextMenu.Append(const AEntry: TEntry);
begin
  FEntries := FEntries + [AEntry];
end;

procedure TAtlasIdeContextMenu.Add(const ACaption: string; const AKey: TFunc<Integer>; const AProc: TProc);
begin
  Add('', ACaption, AKey, AProc);
end;

procedure TAtlasIdeContextMenu.Add(const AId, ACaption: string; const AKey: TFunc<Integer>; const AProc: TProc);
begin
  AddGuarded(TAtlasFeature.EditorCommands, AId, ACaption, AKey, AProc);
end;

procedure TAtlasIdeContextMenu.AddGuarded(AFeature: TAtlasFeature; const AId, ACaption: string;
  const AKey: TFunc<Integer>; const AProc: TProc);
begin
  AddWhen(AFeature, AId, ACaption, AKey, AProc, nil);
end;

procedure TAtlasIdeContextMenu.AddWhen(AFeature: TAtlasFeature; const AId, ACaption: string;
  const AKey: TFunc<Integer>; const AProc: TProc; const AVisible: TFunc<Boolean>);
var
  mEntry: TEntry;
begin
  mEntry := NewEntry(TEntryKind.ekCommand, ACaption);
  if ACaption = '-' then
  begin
    mEntry.Kind := TEntryKind.ekSeparator;
  end;
  mEntry.Id := AId;
  mEntry.Key := AKey;
  mEntry.Proc := AProc;
  mEntry.Feature := AFeature;
  mEntry.Visible := AVisible;
  Append(mEntry);
end;

procedure TAtlasIdeContextMenu.BeginGroup(const ACaption, AKey: string; const ACount: TFunc<Integer>);
var
  mEntry: TEntry;
begin
  EndGroup;
  mEntry := NewEntry(TEntryKind.ekGroup, ACaption);
  mEntry.GroupKey := AKey;
  mEntry.Count := ACount;
  Append(mEntry);
  FGroup := High(FEntries);
end;

procedure TAtlasIdeContextMenu.EndGroup;
begin
  FGroup := -1;
end;

procedure TAtlasIdeContextMenu.AddModuleSlots(ATopCount, AGroupCount, AGroupSize: Integer);
var
  mEntry: TEntry;
  mGroup, mSlot, mParent: Integer;
begin
  EndGroup;
  FModuleTop := ATopCount;
  FModuleGroups := AGroupCount;
  FModuleGroupSize := AGroupSize;
  for mGroup := 0 to AGroupCount - 1 do
  begin
    mEntry := NewEntry(TEntryKind.ekModuleGroup, '');
    mEntry.ModuleGroup := mGroup;
    Append(mEntry);
    mParent := High(FEntries);
    for mSlot := 0 to AGroupSize - 1 do
    begin
      mEntry := NewEntry(TEntryKind.ekModuleSlot, '');
      mEntry.Parent := mParent;
      mEntry.ModuleGroup := mGroup;
      mEntry.Slot := mSlot;
      Append(mEntry);
    end;
  end;
  for mSlot := 0 to ATopCount - 1 do
  begin
    mEntry := NewEntry(TEntryKind.ekModuleSlot, '');
    mEntry.Slot := mSlot;
    Append(mEntry);
  end;
end;

function TAtlasIdeContextMenu.ActionOf(AIndex: Integer): TAction;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FItems)) and (FItems[AIndex] is TAction) then
  begin
    Result := TAction(FItems[AIndex]);
  end;
end;

function TAtlasIdeContextMenu.KeyOf(AIndex: Integer): Integer;
begin
  Result := 0;
  if Assigned(FEntries[AIndex].Key) then
  begin
    Result := FEntries[AIndex].Key();
  end;
end;

function TAtlasIdeContextMenu.CategoryOf(AIndex: Integer): string;
begin
  Result := cSubCategory;
  if FEntries[AIndex].Parent >= 0 then
  begin
    Result := cSubCategory + '.' + IntToStr(FEntries[AIndex].Parent);
  end;
end;

procedure TAtlasIdeContextMenu.RunModuleSlot(AIndex: Integer);
var
  mCommand: TAtlasModuleCommand;
begin
  // Befehl neu suchen: Seit dem Belegen kann sich das Modul abgemeldet haben (Regel 3).
  if (FEntries[AIndex].Id = '') or (FEntries[AIndex].Id = '-') or
    not TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, FEntries[AIndex].Id, mCommand) or
    not Assigned(mCommand.Run) then
  begin
    TAtlasGuard.Log(Format('Kontextmenü: Platz %d ohne Befehl eines Moduls', [AIndex]));
    Exit;
  end;
  TAtlasIdeShortcutTips.Invoked(mCommand.Id);
  TAtlasGuard.Run(TAtlasFeature.EditorCommands, mCommand.Run);
end;

/// <summary>Einträge der Module im Kontextmenü in ihrer Reihenfolge; Trennlinien als Befehl „-“. AItems trägt je
/// Befehl Section und Sichtbarkeit für die Verteilung auf die Plätze.</summary>
function ModuleMenuCommands(out AItems: TArray<TAtlasSlotItem>): TArray<TAtlasModuleCommand>;
var
  mEntry: TAtlasMenuEntry;
  mCommand: TAtlasModuleCommand;
  mItem: TAtlasSlotItem;
begin
  Result := nil;
  AItems := nil;
  for mEntry in TAtlasModuleContributions.MenuEntries(AtlasModuleRegistry, TAtlasMenuPlace.EditorContext) do
  begin
    mCommand := Default(TAtlasModuleCommand);
    mCommand.Id := '-';
    mCommand.Caption := '-';
    if (mEntry.CommandId <> '-') and
      not TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mEntry.CommandId, mCommand) then
    begin
      Continue;
    end;
    mItem := Default(TAtlasSlotItem);
    mItem.Id := mCommand.Id;
    mItem.Section := mEntry.Section;
    // Abgewählte Untermenüs (commands.editorContextMenu.groups) und Einträge, die nicht zur Lage passen, fehlen.
    mItem.Visible := ((mCommand.Id = '-') or TAtlasModuleContributions.IsVisible(mCommand)) and
      TAtlasIdeMenuContext.GroupShown(mEntry.Group) and TAtlasIdeMenuContext.Applies(mEntry.When);
    Result := Result + [mCommand];
    AItems := AItems + [mItem];
  end;
end;

/// <summary>Tastenkürzel eines Modulbefehls; 0 ohne.</summary>
function ModuleKey(const ACommand: TAtlasModuleCommand): Integer;
begin
  Result := 0;
  if Assigned(ACommand.Key) then
  begin
    Result := ACommand.Key();
  end;
end;

procedure TAtlasIdeContextMenu.ApplyModuleSlot(AIndex: Integer; const ALayout: TAtlasSlotLayout;
  const ACommands: TArray<TAtlasModuleCommand>);
var
  mList: TAtlasSlotList;
  mAction: TAction;
  mItem: Integer;
begin
  mAction := ActionOf(AIndex);
  mList := ALayout.Top;
  if FEntries[AIndex].ModuleGroup >= 0 then
  begin
    mList := ALayout.Groups[FEntries[AIndex].ModuleGroup];
  end;
  if FEntries[AIndex].Kind = TEntryKind.ekModuleGroup then
  begin
    mAction.Caption := mList.Caption;
    mAction.Visible := mList.Shown;
    Exit;
  end;
  mItem := mList.Items[FEntries[AIndex].Slot];
  FEntries[AIndex].Id := '';
  mAction.ShortCut := 0;
  mAction.Visible := mList.Visible[FEntries[AIndex].Slot];
  if mItem < 0 then
  begin
    Exit;
  end;
  FEntries[AIndex].Id := ACommands[mItem].Id;
  mAction.Caption := ACommands[mItem].Caption;
  mAction.ShortCut := TShortCut(ModuleKey(ACommands[mItem]));
end;

procedure TAtlasIdeContextMenu.UpdateModuleSlots;
var
  mCommands: TArray<TAtlasModuleCommand>;
  mItems: TArray<TAtlasSlotItem>;
  mLayout: TAtlasSlotLayout;
  mIndex: Integer;
begin
  if FModuleTop + FModuleGroups = 0 then
  begin
    Exit;
  end;
  mCommands := ModuleMenuCommands(mItems);
  mLayout := TAtlasMenuSlots.Layout(mItems, FModuleTop, FModuleGroups, FModuleGroupSize);
  if mLayout.Missing > 0 then
  begin
    TAtlasGuard.Log(Format('Kontextmenü: %d Einträge der Module ohne Platz', [mLayout.Missing]));
  end;
  for mIndex := 0 to Min(High(FEntries), High(FItems)) do
  begin
    if (FEntries[mIndex].Kind in [TEntryKind.ekModuleGroup, TEntryKind.ekModuleSlot]) and
      (ActionOf(mIndex) <> nil) then
    begin
      ApplyModuleSlot(mIndex, mLayout, mCommands);
    end;
  end;
end;

procedure TAtlasIdeContextMenu.UpdateGroups;
var
  mIndex, mParent: Integer;
begin
  // Gruppen nur mit mindestens einem sichtbaren Befehl.
  for mIndex := 0 to Min(High(FEntries), High(FItems)) do
  begin
    if (FEntries[mIndex].Kind = TEntryKind.ekGroup) and (ActionOf(mIndex) <> nil) then
    begin
      ActionOf(mIndex).Visible := False;
    end;
  end;
  for mIndex := 0 to Min(High(FEntries), High(FItems)) do
  begin
    mParent := FEntries[mIndex].Parent;
    if (FEntries[mIndex].Kind = TEntryKind.ekCommand) and (mParent >= 0) and (ActionOf(mParent) <> nil) and
      (ActionOf(mIndex) <> nil) and ActionOf(mIndex).Visible then
    begin
      ActionOf(mParent).Visible := TAtlasIdeMenuContext.GroupShown(FEntries[mParent].GroupKey);
    end;
  end;
  // Zahl hinter dem Namen, etwa „Befunde (3)“.
  for mIndex := 0 to Min(High(FEntries), High(FItems)) do
  begin
    if (FEntries[mIndex].Kind = TEntryKind.ekGroup) and Assigned(FEntries[mIndex].Count) and
      (ActionOf(mIndex) <> nil) then
    begin
      ActionOf(mIndex).Caption := TAtlasMenuContextRules.CountedCaption(FEntries[mIndex].Caption,
        FEntries[mIndex].Count());
    end;
  end;
end;

function TAtlasIdeContextMenu.IsLine(AIndex: Integer): Boolean;
begin
  Result := (FEntries[AIndex].Kind = TEntryKind.ekSeparator) or
    ((FEntries[AIndex].Kind = TEntryKind.ekModuleSlot) and (ActionOf(AIndex) <> nil) and
    (ActionOf(AIndex).Caption = '-'));
end;

procedure TAtlasIdeContextMenu.UpdateSeparators(AParent: Integer);
var
  mIndexes: TArray<Integer>;
  mIsLine, mVisible, mShown: TArray<Boolean>;
  mIndex, mAt: Integer;
begin
  // Plätze in Untermenüs der Module ordnet schon TAtlasMenuSlots; hier die oberste Ebene und die Gruppen von Base.
  for mIndex := 0 to Min(High(FEntries), High(FItems)) do
  begin
    if (FEntries[mIndex].Parent = AParent) and (ActionOf(mIndex) <> nil) then
    begin
      mIndexes := mIndexes + [mIndex];
      mIsLine := mIsLine + [IsLine(mIndex)];
      mVisible := mVisible + [ActionOf(mIndex).Visible];
    end;
  end;
  mShown := TAtlasMenuContextRules.Separators(mIsLine, mVisible);
  for mAt := 0 to High(mIndexes) do
  begin
    if mIsLine[mAt] then
    begin
      ActionOf(mIndexes[mAt]).Visible := mShown[mAt];
    end;
  end;
end;

function TAtlasIdeContextMenu.ChildActions(AParent: Integer): TArray<TBasicAction>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to Min(High(FEntries), High(FItems)) do
  begin
    if FEntries[mIndex].Parent = AParent then
    begin
      Result := Result + [FItems[mIndex]];
    end;
  end;
end;

procedure TAtlasIdeContextMenu.FillGroups(ARootItem: TMenuItem);
var
  mChild, mIndex: Integer;
  mItem: TMenuItem;
begin
  for mChild := 0 to ARootItem.Count - 1 do
  begin
    mItem := ARootItem.Items[mChild];
    mIndex := IndexOfAction(mItem.Action);
    if (mIndex >= 0) and (FEntries[mIndex].Kind in [TEntryKind.ekGroup, TEntryKind.ekModuleGroup]) then
    begin
      TAtlasIdeContextSubmenus.Fill(mItem, ChildActions(mIndex));
    end;
  end;
end;

procedure TAtlasIdeContextMenu.UpdateVisibility;
var
  mIndex: Integer;
begin
  for mIndex := 0 to Min(High(FEntries), High(FItems)) do
  begin
    if (FEntries[mIndex].Kind <> TEntryKind.ekCommand) or (ActionOf(mIndex) = nil) then
    begin
      Continue;
    end;
    ActionOf(mIndex).ShortCut := TShortCut(KeyOf(mIndex));
    if Assigned(FEntries[mIndex].Visible) then
    begin
      ActionOf(mIndex).Visible := FEntries[mIndex].Visible();
    end;
  end;
  UpdateModuleSlots;
  UpdateGroups;
  for mIndex := -1 to High(FEntries) do
  begin
    if (mIndex < 0) or (FEntries[mIndex].Kind = TEntryKind.ekGroup) then
    begin
      UpdateSeparators(mIndex);
    end;
  end;
end;

procedure TAtlasIdeContextMenu.Register;
var
  mServices: IOTAEditorServices;
  mRoot, mItem: TAction;
  mIndex: Integer;
begin
  if FRegistered or not Supports(BorlandIDEServices, IOTAEditorServices, mServices) or
    (mServices.GetEditorLocalMenu = nil) then
  begin
    Exit;
  end;
  // Elternaktion zuerst, die Einträge direkt danach, die einer Gruppe direkt nach ihr (so verlangt es
  // INTAEditorLocalMenu).
  mRoot := TAction.Create(FActions);
  mRoot.ActionList := FActions;
  mRoot.Category := cCategory;
  mRoot.Caption := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.MenuAtlas);
  mRoot.OnExecute := RootExecute;
  FRoot := mRoot;
  for mIndex := 0 to High(FEntries) do
  begin
    // Einträge in Gruppen nicht in der registrierten Liste: Die IDE baut nur eine Ebene (siehe oben).
    mItem := TAction.Create(FActions);
    mItem.ActionList := FActions;
    if FEntries[mIndex].Parent >= 0 then
    begin
      mItem.ActionList := FSubActions;
    end;
    mItem.Category := CategoryOf(mIndex);
    mItem.Caption := FEntries[mIndex].Caption;
    FItems := FItems + [mItem];
    case FEntries[mIndex].Kind of
      TEntryKind.ekCommand, TEntryKind.ekModuleSlot:
        mItem.OnExecute := ItemExecute;
      TEntryKind.ekGroup, TEntryKind.ekModuleGroup:
        mItem.OnExecute := GroupExecute;
    end;
    // Plätze der Module bleiben aus, bis UpdateModuleSlots sie belegt.
    mItem.Visible := not (FEntries[mIndex].Kind in [TEntryKind.ekModuleGroup, TEntryKind.ekModuleSlot]);
  end;
  UpdateVisibility;
  mServices.GetEditorLocalMenu.RegisterActionList(FActions, cCategory, cEdMenuCatLast);
  FRegistered := True;
end;

procedure TAtlasIdeContextMenu.EnsureAll;
begin
  try
    Register;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

/// <summary>Die eigene Aktion hinter Sender (aus AOwner), sonst die verknüpfte des Menüeintrags; nil, wenn keine.
/// </summary>
function OwnAction(Sender: TObject; AOwner: TComponent): TBasicAction;
begin
  Result := nil;
  if (Sender is TBasicAction) and (TBasicAction(Sender).Owner = AOwner) then
  begin
    Result := TBasicAction(Sender);
  end
  else if (Sender is TMenuItem) and (TMenuItem(Sender).Action <> nil) and
    (TMenuItem(Sender).Action.Owner = AOwner) then
  begin
    Result := TMenuItem(Sender).Action;
  end;
end;

/// <summary>Protokolliert einen Aufruf, hinter dem keine eigene Aktion steht.</summary>
procedure LogUnknownSender(Sender: TObject);
begin
  if Sender = nil then
  begin
    TAtlasGuard.Log('Kontextmenü: Aufruf ohne Absender');
  end
  else
  begin
    TAtlasGuard.Log('Kontextmenü: unbekannter Absender ' + Sender.ClassName);
  end;
end;

/// <summary>Der Menüeintrag hinter ASender (er selbst oder der, über den die Aktion gerade läuft); nil, wenn keiner.
/// </summary>
function MenuItemOf(ASender: TObject): TMenuItem;
begin
  Result := nil;
  if ASender is TMenuItem then
  begin
    Result := TMenuItem(ASender);
  end
  else if (ASender is TBasicAction) and (TBasicAction(ASender).ActionComponent is TMenuItem) then
  begin
    Result := TMenuItem(TBasicAction(ASender).ActionComponent);
  end;
end;

procedure TAtlasIdeContextMenu.RootExecute(Sender: TObject);
var
  mRootItem: TMenuItem;
begin
  // Die VCL ruft beim Öffnen eines Untermenüs den Klick seines Eintrags (TMenu.DispatchPopup), hier also beim
  // Öffnen von „Atlas“: Lage lesen, Sichtbarkeit setzen, Untermenüs füllen. Ohne Handler wäre die Aktion
  // ausgegraut.
  if (FRoot = nil) or (OwnAction(Sender, FActions) <> FRoot) then
  begin
    Exit;
  end;
  TAtlasIdeMenuContext.Refresh;
  UpdateVisibility;
  mRootItem := MenuItemOf(Sender);
  if mRootItem <> nil then
  begin
    FillGroups(mRootItem);
  end;
end;

procedure TAtlasIdeContextMenu.GroupExecute(Sender: TObject);
var
  mItem: TMenuItem;
  mIndex: Integer;
begin
  // Mit Einträgen öffnet sich gerade das Untermenü; ohne (die IDE hat das Öffnen von „Atlas“ nicht gemeldet)
  // zeigt ein Klick die Gruppe als eigenes Menü an der Maus.
  mItem := MenuItemOf(Sender);
  if (mItem <> nil) and (mItem.Count > 0) then
  begin
    Exit;
  end;
  mIndex := IndexOfAction(OwnAction(Sender, FActions));
  if (mIndex < 0) or not (FEntries[mIndex].Kind in [TEntryKind.ekGroup, TEntryKind.ekModuleGroup]) then
  begin
    Exit;
  end;
  TAtlasIdeMenuContext.Refresh;
  UpdateVisibility;
  TAtlasIdeContextSubmenus.Popup(FGroupPopup, ChildActions(mIndex));
end;

function TAtlasIdeContextMenu.IndexOfAction(AAction: TBasicAction): Integer;
begin
  // Nicht über Tag: Die IDE setzt ihn beim Einbinden ins Kontextmenü selbst (Protokoll: „Eintrag 30“).
  Result := Min(High(FItems), High(FEntries));
  while (Result >= 0) and (FItems[Result] <> AAction) do
  begin
    Dec(Result);
  end;
end;

procedure TAtlasIdeContextMenu.ItemExecute(Sender: TObject);
var
  mIndex: Integer;
  mAction: TBasicAction;
begin
  // Die IDE kann statt unserer Aktion einen eigenen Menüeintrag melden; dessen Tag ist nicht unserer.
  // Maßgeblich ist die eigene Aktion (aus FActions), sonst die verknüpfte des Menüeintrags.
  mAction := OwnAction(Sender, FActions);
  if mAction = nil then
  begin
    LogUnknownSender(Sender);
    Exit;
  end;
  mIndex := IndexOfAction(mAction);
  // Hat die Tastaturbindung denselben Tastendruck schon ausgeführt, nicht ein zweites Mal.
  if (mAction is TAction) and not TAtlasKeyStroke.Claim(TAction(mAction).ShortCut, Cardinal(GetMessageTime)) then
  begin
    Exit;
  end;
  if (mIndex >= 0) and (FEntries[mIndex].Kind = TEntryKind.ekModuleSlot) then
  begin
    RunModuleSlot(mIndex);
    Exit;
  end;
  if (mIndex < 0) or not Assigned(FEntries[mIndex].Proc) then
  begin
    TAtlasGuard.Log(Format('Kontextmenü: Eintrag %d ohne Befehl', [mIndex]));
    Exit;
  end;
  if FEntries[mIndex].Id <> '' then
  begin
    TAtlasIdeShortcutTips.Invoked(FEntries[mIndex].Id);
  end;
  TAtlasGuard.Run(FEntries[mIndex].Feature, FEntries[mIndex].Proc);
end;

end.
