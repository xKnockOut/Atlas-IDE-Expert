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

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ActnList;

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
    function CaptionOf(AIndex: Integer): string;
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
    /// <summary>Registriert das Untermenü bei der IDE, einmal nach allen Add.</summary>
    procedure EnsureAll;
  end;

implementation

uses
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
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
var
  Entry: TEntry;
begin
  Entry.Id := AId;
  Entry.Caption := ACaption;
  Entry.Key := AKey;
  Entry.Proc := AProc;
  FEntries := FEntries + [Entry];
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
  end;
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
  if (Index < 0) or (Index > High(FEntries)) or not Assigned(FEntries[Index].Proc) then
  begin
    TAtlasGuard.Log(Format('Kontextmenü: Eintrag %d ohne Befehl', [Index]));
    Exit;
  end;
  if FEntries[Index].Id <> '' then
    TAtlasIdeShortcutTips.Invoked(FEntries[Index].Id);
  TAtlasGuard.Run(TAtlasFeature.EditorCommands, FEntries[Index].Proc);
end;

end.
