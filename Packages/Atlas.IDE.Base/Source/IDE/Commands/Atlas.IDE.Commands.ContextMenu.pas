unit Atlas.IDE.Commands.ContextMenu;

// Untermenü „Atlas“ im Kontextmenü des Editors (#399). Die IDE baut dieses
// Menü bei jedem Öffnen aus registrierten Aktionslisten neu auf
// (INTAEditorLocalMenu); Atlas registriert dort eine TActionList mit einer
// Aktion „Atlas“ und den Einträgen als Untermenü (Kategorie „Atlas.Eintrag“).
// Früher hängte Atlas eigene TMenuItem direkt in „EditorLocalMenu“ ein; beim
// Neuaufbau meldete die IDE dann „Komponente … existiert bereits“.
// Untermenüs darin (BeginGroup/EndGroup): Die Gruppe ist eine Aktion der
// Kategorie „Atlas.Eintrag“, ihre Einträge folgen direkt danach mit der
// Kategorie „Atlas.Eintrag.<Index der Gruppe>“ (so verlangt es
// RegisterActionList). Alle Einträge in einer Ebene waren höher als der
// Bildschirm, das Menü war oben abgeschnitten. Eine Gruppe ohne sichtbaren
// Eintrag bleibt aus.
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
    end;
  private const
    Category = 'Atlas';
    SubCategory = 'Atlas.Eintrag';
  private
    FEntries: TArray<TEntry>;
    FActions: TActionList;
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
    procedure RunModuleSlot(AIndex: Integer);
    function IndexOfAction(AAction: TBasicAction): Integer;
    procedure ItemExecute(Sender: TObject);
    procedure RootExecute(Sender: TObject);
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
    /// <summary>Untermenü ACaption; die folgenden Einträge bis EndGroup stehen darin. Nicht verschachtelt.</summary>
    procedure BeginGroup(const ACaption: string);
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
  Vcl.Menus,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Commands.KeyStroke,
  Atlas.IDE.Commands.ShortcutTips;

constructor TAtlasIdeContextMenu.Create;
begin
  inherited Create;
  FActions := TActionList.Create(nil);
  FGroup := -1;
end;

destructor TAtlasIdeContextMenu.Destroy;
var
  Services: IOTAEditorServices;
begin
  // Vor dem Entladen abmelden, sonst greift die IDE auf freigegebene Aktionen zu.
  if FRegistered and Supports(BorlandIDEServices, IOTAEditorServices, Services) and
    (Services.GetEditorLocalMenu <> nil) then
  begin
    Services.GetEditorLocalMenu.UnregisterActionList(Category);
  end;
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

procedure TAtlasIdeContextMenu.BeginGroup(const ACaption: string);
begin
  EndGroup;
  Append(NewEntry(TEntryKind.ekGroup, ACaption));
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
  Result := SubCategory;
  if FEntries[AIndex].Parent >= 0 then
  begin
    Result := SubCategory + '.' + IntToStr(FEntries[AIndex].Parent);
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
    mItem.Visible := (mCommand.Id = '-') or TAtlasModuleContributions.IsVisible(mCommand);
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
      ActionOf(mParent).Visible := True;
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
  UpdateGroups;
  UpdateModuleSlots;
end;

procedure TAtlasIdeContextMenu.Register;
var
  Services: IOTAEditorServices;
  Root, Item: TAction;
  Index: Integer;
begin
  if FRegistered or not Supports(BorlandIDEServices, IOTAEditorServices, Services) or
    (Services.GetEditorLocalMenu = nil) then
  begin
    Exit;
  end;
  // Elternaktion zuerst, die Einträge direkt danach, die einer Gruppe direkt nach ihr (so verlangt es
  // INTAEditorLocalMenu).
  Root := TAction.Create(FActions);
  Root.ActionList := FActions;
  Root.Category := Category;
  Root.Caption := TAtlasStrings.Text(TAtlasTextId.MenuAtlas);
  Root.OnExecute := RootExecute;
  for Index := 0 to High(FEntries) do
  begin
    Item := TAction.Create(FActions);
    Item.ActionList := FActions;
    Item.Category := CategoryOf(Index);
    Item.Caption := FEntries[Index].Caption;
    FItems := FItems + [Item];
    case FEntries[Index].Kind of
      TEntryKind.ekCommand, TEntryKind.ekModuleSlot:
        Item.OnExecute := ItemExecute;
      TEntryKind.ekGroup, TEntryKind.ekModuleGroup:
        Item.OnExecute := RootExecute;
    end;
    // Plätze der Module bleiben aus, bis UpdateModuleSlots sie belegt.
    Item.Visible := not (FEntries[Index].Kind in [TEntryKind.ekModuleGroup, TEntryKind.ekModuleSlot]);
  end;
  UpdateVisibility;
  Services.GetEditorLocalMenu.RegisterActionList(FActions, Category, cEdMenuCatLast);
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

procedure TAtlasIdeContextMenu.RootExecute(Sender: TObject);
begin
  // Nur das Untermenü; ohne Handler wäre die Aktion ausgegraut.
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
