unit Atlas.IDE.Commands.ContextMenu;

// Untermenü „Atlas“ im Kontextmenü des Editors (#399). Die IDE baut dieses
// Menü bei jedem Öffnen aus registrierten Aktionslisten neu auf
// (INTAEditorLocalMenu); Atlas registriert dort eine TActionList mit einer
// Aktion „Atlas“ und den Einträgen als Untermenü (Kategorie „Atlas.Eintrag“).
// Früher hängte Atlas eigene TMenuItem direkt in „EditorLocalMenu“ ein; beim
// Neuaufbau meldete die IDE dann „Komponente … existiert bereits“.
// Tastenkürzel stehen nur als Text hinter einem Tab in der Beschriftung, nicht
// als ShortCut: Sonst würde das Kontextmenü die Taste ein zweites Mal
// auslösen. Die Beschriftungen entstehen beim Registrieren; kein OnUpdate:
// Die IDE ruft es im Leerlauf auch während des Compilierens, und eine
// geänderte Caption erreichte dort schon freigegebene Menüeinträge
// (Zugriffsverletzung beim Erzeugen). Geänderte Tasten zeigt das Menü nach
// einem Neustart.
// Einträge mit einer Kennung der Befehlspalette melden sich bei den
// Tastenkürzel-Tipps (#600) als Aufruf per Kontextmenü.
// Einträge mit Sichtbarkeit nach Einstellung (AddWhen, etwa „Weg von hier nach …“
// nach navigation.symbolPath, #1117, oder „Auswirkungen anzeigen“ nach
// navigation.impact, #1120) blendet UpdateVisibility aus bzw. ein; aufgerufen
// beim Registrieren und nach jeder Einstellungsänderung, nie aus OnUpdate.
// Einträge der Module (#1455, TAtlasMenuPlace.EditorContext) belegen an der
// Stelle von AddModuleSlots einen festen Vorrat ausgeblendeter Aktionen: Die
// IDE kennt nur die einmal registrierte Liste, Module kommen und gehen aber.
// UpdateVisibility (auch nach jeder Änderung der Registry) setzt Text und
// Sichtbarkeit der Plätze aus den Befehlen der Module; der Aufruf sucht den
// Befehl über seine Id neu, ein abgemeldetes Modul erreicht er nicht mehr.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ActnList,
  Atlas.Core.Diagnostics.Guard;

type
  TAtlasIdeContextMenu = class
  private type
    TEntry = record
      /// <summary>Befehl der Palette für die Tastenkürzel-Tipps (#600); '' = keiner.</summary>
      Id: string;
      Caption: string;
      /// <summary>Tastenkürzel als TShortCut, 0 = keins; nil ohne Kürzel.</summary>
      Key: TFunc<Integer>;
      Proc: TProc;
      /// <summary>Sicherung (#493), unter der der Eintrag läuft.</summary>
      Feature: TAtlasFeature;
      /// <summary>Sichtbar, solange das True liefert; nil = immer.</summary>
      Visible: TFunc<Boolean>;
      /// <summary>Platz für einen Eintrag eines Moduls (Index in FModuleIds); -1 = eigener Eintrag.</summary>
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
    /// <summary>Befehls-Id je Platz der Module; '' = Platz frei.</summary>
    FModuleIds: TArray<string>;
    function CaptionOf(AIndex: Integer): string;
    procedure UpdateModuleSlots;
    procedure RunModuleSlot(ASlot: Integer);
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
    /// <summary>Plätze für Einträge der Module (#1455) an dieser Stelle; mehr Einträge, als Plätze da sind, fehlen
    /// (Protokollzeile).</summary>
    procedure AddModuleSlots(ACount: Integer);
    /// <summary>Sichtbarkeit der Einträge aus AddWhen und die Plätze der Module neu setzen (nach geänderten
    /// Einstellungen und nach jeder Änderung der Registry).</summary>
    procedure UpdateVisibility;
    /// <summary>Registriert das Untermenü bei der IDE, einmal nach allen Add.</summary>
    procedure EnsureAll;
  end;

implementation

uses
  System.Math,
  Vcl.Menus,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Commands.ShortcutTips;

constructor TAtlasIdeContextMenu.Create;
begin
  inherited Create;
  FActions := TActionList.Create(nil);
end;

destructor TAtlasIdeContextMenu.Destroy;
var
  Services: IOTAEditorServices;
begin
  // Vor dem Entladen abmelden, sonst greift die IDE auf freigegebene Aktionen zu.
  if FRegistered and Supports(BorlandIDEServices, IOTAEditorServices, Services) and
    (Services.GetEditorLocalMenu <> nil) then
    Services.GetEditorLocalMenu.UnregisterActionList(Category);
  FActions.Free;
  inherited;
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
  Entry: TEntry;
begin
  Entry.Id := AId;
  Entry.Caption := ACaption;
  Entry.Key := AKey;
  Entry.Proc := AProc;
  Entry.Feature := AFeature;
  Entry.Visible := AVisible;
  Entry.Slot := -1;
  FEntries := FEntries + [Entry];
end;

procedure TAtlasIdeContextMenu.AddModuleSlots(ACount: Integer);
var
  mEntry: TEntry;
  mIndex: Integer;
begin
  for mIndex := 0 to ACount - 1 do
  begin
    mEntry := Default(TEntry);
    mEntry.Feature := TAtlasFeature.EditorCommands;
    mEntry.Slot := Length(FModuleIds);
    FModuleIds := FModuleIds + [''];
    FEntries := FEntries + [mEntry];
  end;
end;

procedure TAtlasIdeContextMenu.RunModuleSlot(ASlot: Integer);
var
  mCommand: TAtlasModuleCommand;
begin
  // Befehl neu suchen: Seit dem Belegen kann sich das Modul abgemeldet haben (Regel 3).
  if (ASlot > High(FModuleIds)) or (FModuleIds[ASlot] = '') or (FModuleIds[ASlot] = '-') or
    not TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, FModuleIds[ASlot], mCommand) or
    not Assigned(mCommand.Run) then
  begin
    TAtlasGuard.Log(Format('Kontextmenü: Platz %d ohne Befehl eines Moduls', [ASlot]));
    Exit;
  end;
  TAtlasIdeShortcutTips.Invoked(mCommand.Id);
  TAtlasGuard.Run(TAtlasFeature.EditorCommands, mCommand.Run);
end;

procedure TAtlasIdeContextMenu.UpdateModuleSlots;
var
  mCommands: TArray<TAtlasModuleCommand>;
  mVisible: TArray<Boolean>;
  mEntry: TAtlasMenuEntry;
  mCommand: TAtlasModuleCommand;
  mIndex, mSlot, mKey, mLast: Integer;
  mCaption: string;
  mSeen: Boolean;
begin
  if Length(FModuleIds) = 0 then
    Exit;
  mCommands := nil;
  for mEntry in TAtlasModuleContributions.MenuEntries(AtlasModuleRegistry, TAtlasMenuPlace.EditorContext) do
    if mEntry.CommandId = '-' then
    begin
      mCommand := Default(TAtlasModuleCommand);
      mCommand.Id := '-';
      mCommand.Caption := '-';
      mCommands := mCommands + [mCommand];
    end
    else if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mEntry.CommandId, mCommand) then
      mCommands := mCommands + [mCommand];
  if Length(mCommands) > Length(FModuleIds) then
    TAtlasGuard.Log(Format('Kontextmenü: %d Einträge der Module, nur %d Plätze',
      [Length(mCommands), Length(FModuleIds)]));
  // Sichtbarkeit: Befehle nach Visible, Trennlinien nur zwischen sichtbaren Befehlen.
  SetLength(mVisible, Length(mCommands));
  mSeen := False;
  mLast := -1;
  for mIndex := 0 to High(mCommands) do
    if mCommands[mIndex].Id = '-' then
    begin
      mVisible[mIndex] := False;
      if mSeen then
        mLast := mIndex;
    end
    else
    begin
      mVisible[mIndex] := TAtlasModuleContributions.IsVisible(mCommands[mIndex]);
      if mVisible[mIndex] then
      begin
        if mLast >= 0 then
          mVisible[mLast] := True;
        mLast := -1;
        mSeen := True;
      end;
    end;
  for mIndex := 0 to Min(High(FEntries), High(FItems)) do
  begin
    mSlot := FEntries[mIndex].Slot;
    if (mSlot < 0) or not (FItems[mIndex] is TAction) then
      Continue;
    if mSlot > High(mCommands) then
    begin
      FModuleIds[mSlot] := '';
      TAction(FItems[mIndex]).Visible := False;
      Continue;
    end;
    mCommand := mCommands[mSlot];
    FModuleIds[mSlot] := mCommand.Id;
    mCaption := mCommand.Caption;
    if Assigned(mCommand.Key) then
    begin
      mKey := mCommand.Key();
      if mKey <> 0 then
        mCaption := mCaption + #9 + ShortCutToText(TShortCut(mKey));
    end;
    TAction(FItems[mIndex]).Caption := mCaption;
    TAction(FItems[mIndex]).Visible := mVisible[mSlot];
  end;
end;

procedure TAtlasIdeContextMenu.UpdateVisibility;
var
  Index: Integer;
begin
  for Index := 0 to Min(High(FEntries), High(FItems)) do
    if Assigned(FEntries[Index].Visible) and (FItems[Index] is TAction) then
      TAction(FItems[Index]).Visible := FEntries[Index].Visible();
  UpdateModuleSlots;
end;

function TAtlasIdeContextMenu.CaptionOf(AIndex: Integer): string;
var
  Key: Integer;
begin
  Result := FEntries[AIndex].Caption;
  if not Assigned(FEntries[AIndex].Key) then
    Exit;
  Key := FEntries[AIndex].Key();
  if Key <> 0 then
    Result := Result + #9 + ShortCutToText(TShortCut(Key));
end;

procedure TAtlasIdeContextMenu.Register;
var
  Services: IOTAEditorServices;
  Root, Item: TAction;
  Index: Integer;
begin
  if FRegistered or not Supports(BorlandIDEServices, IOTAEditorServices, Services) or
    (Services.GetEditorLocalMenu = nil) then
    Exit;
  // Elternaktion zuerst, die Einträge direkt danach (so verlangt es INTAEditorLocalMenu).
  Root := TAction.Create(FActions);
  Root.ActionList := FActions;
  Root.Category := Category;
  Root.Caption := TAtlasStrings.Text(TAtlasTextId.MenuAtlas);
  Root.OnExecute := RootExecute;
  for Index := 0 to High(FEntries) do
  begin
    Item := TAction.Create(FActions);
    Item.ActionList := FActions;
    Item.Category := SubCategory;
    Item.Caption := CaptionOf(Index);
    FItems := FItems + [Item];
    if FEntries[Index].Caption <> '-' then
    begin
      Item.OnExecute := ItemExecute;
    end;
    // Plätze der Module bleiben aus, bis UpdateModuleSlots sie belegt.
    if FEntries[Index].Slot >= 0 then
      Item.Visible := False;
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

procedure TAtlasIdeContextMenu.ItemExecute(Sender: TObject);
var
  Index: Integer;
  Action: TBasicAction;
begin
  // Die IDE kann statt unserer Aktion einen eigenen Menüeintrag melden; dessen Tag ist nicht unserer.
  // Maßgeblich ist die eigene Aktion (aus FActions), sonst die verknüpfte des Menüeintrags.
  Action := nil;
  if (Sender is TBasicAction) and (TBasicAction(Sender).Owner = FActions) then
    Action := TBasicAction(Sender)
  else if (Sender is TMenuItem) and (TMenuItem(Sender).Action <> nil) and
    (TMenuItem(Sender).Action.Owner = FActions) then
    Action := TMenuItem(Sender).Action;
  if Action = nil then
  begin
    if Sender = nil then
      TAtlasGuard.Log('Kontextmenü: Aufruf ohne Absender')
    else
      TAtlasGuard.Log('Kontextmenü: unbekannter Absender ' + Sender.ClassName);
    Exit;
  end;
  // Nicht über Tag: Die IDE setzt ihn beim Einbinden ins Kontextmenü selbst (Protokoll: „Eintrag 30“).
  Index := High(FItems);
  while (Index >= 0) and (FItems[Index] <> Action) do
    Dec(Index);
  if (Index >= 0) and (Index <= High(FEntries)) and (FEntries[Index].Slot >= 0) then
  begin
    RunModuleSlot(FEntries[Index].Slot);
    Exit;
  end;
  if (Index < 0) or (Index > High(FEntries)) or not Assigned(FEntries[Index].Proc) then
  begin
    TAtlasGuard.Log(Format('Kontextmenü: Eintrag %d ohne Befehl', [Index]));
    Exit;
  end;
  if FEntries[Index].Id <> '' then
    TAtlasIdeShortcutTips.Invoked(FEntries[Index].Id);
  TAtlasGuard.Run(FEntries[Index].Feature, FEntries[Index].Proc);
end;

end.
