unit Atlas.IDE.Commands.KeyMap;

// Tastenkürzel-Übersicht mit Konflikterkennung (#520) in der IDE:
// - Collect sammelt alle Belegungen: Aktionen aus INTAServices.ActionList
//   (Taste und Zweittasten, Herkunft über das Modul des OnExecute-Handlers bzw.
//   des Besitzers: Ordner der IDE = IDE, Atlas-Package = Atlas, sonst die
//   Erweiterung mit ihrem Package-Namen), die Tasten von Atlas
//   (TAtlasKeyEntry.AllFromSettings) und Tastaturbelegungen des Editors über
//   IOTAKeyboardServices.LookupKeyBinding, soweit auslesbar: Die IDE nennt je
//   Taste nur die wirksame Belegung und deren Modul, keinen Befehlsnamen.
//   Abgefragt werden die Tasten aller Einträge, die bekannten Editor-Tasten
//   (#494) und alle Kombinationen mit Strg oder Alt sowie F1–F12.
//   TAtlasKeyMap.Analyze wertet aus.
// - Fenster „Atlas – Tastenkürzel“ (nicht modal) aus Menü Atlas ›
//   „Tastenkürzel-Übersicht…“ und Befehlspalette (keys.overview, Befehl
//   Atlas.KeyOverview); Export als HTML nach
//   %LOCALAPPDATA%\Atlas\Tastenkuerzel.html, geöffnet im Browser.
// - Beim Start (keys.startupCheck) prüft Atlas nach StartDelayMs seine eigenen
//   Tasten und meldet jeden Konflikt einmal in der Meldungsansicht, mit Verweis
//   auf Übersicht und Einstellungen; was #494 beim Belegen schon gemeldet hat,
//   nicht noch einmal. Nach Package-Änderungen prüft CheckNow erneut.
// - Gemeinsame Quelle für die Einrichtung (#625, SetupKeys), die Taste eines
//   Atlas-Befehls in der Befehlspalette (#502, AtlasShortCut) und spätere
//   Einstiege (#600 Tastenkürzel-Tipps, #766 Knopf auf der Willkommensseite:
//   ShowWindow mit Suchtext).
// - Spalte „Selten per Tastatur“ (#600): Collect übernimmt je Zeile die Zählung
//   der Tastenkürzel-Tipps (TAtlasIdeShortcutTips.UsageOf), Aktionen über ihren
//   Namen, Atlas-Tasten über den Befehl der Palette.
// - Abgeschaltete Funktionen (TAtlasKeyEntry.Disabled, etwa #775 aus oder
//   „Units suchen“ aus) bekommen keine Zeile und sind kein Konflikt.
// - Strg+F12 (#777): Die IDE-Aktion „Units“, an die sich „Units suchen“ hängt
//   (TAtlasIdeUnitSearch.HookedAction), erscheint bei unitSearch.enabled und
//   unitSearch.replaceIdeDialog als Atlas-Zeile mit ihren echten Tasten, sonst
//   als Aktion der IDE (ihr Handler liegt dann zwar in Atlas, ruft aber nur
//   den Dialog der IDE).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap,
  Atlas.Core.Setup.Checklist,
  Atlas.UI.Commands.KeyMap,
  Atlas.Core.Commands.Palette;

type
  TAtlasIdeKeyMap = class
  public const
    CommandId = 'Atlas.KeyOverview';
    /// <summary>Wartezeit nach dem Laden, bis die übrigen Packages ihre Tasten angemeldet haben.</summary>
    StartDelayMs = 3000;
    ExportFileName = 'Tastenkuerzel.html';
  private class var
    FInstance: TAtlasIdeKeyMap;
  private
    FWindow: TAtlasKeyMapWindow;
    FTimer: TTimer;
    procedure TimerTick(Sender: TObject);
    procedure Refresh;
    procedure ExportHtml;
    procedure OpenKeyConflicts;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Die laufende Übersicht oder nil.</summary>
    class function Instance: TAtlasIdeKeyMap; static;
    /// <summary>Alle Belegungen aus IDE, Atlas und anderen Erweiterungen, ausgewertet (Hauptthread).</summary>
    class function Collect: TArray<TAtlasKeyItem>; static;
    /// <summary>TAtlasKeyEntry.AllFromSettings mit den aktuellen Einstellungen; bei Strg+F12 (#777) die Taste,
    /// die die übernommene Aktion der IDE wirklich hat (0, wenn Atlas sich nicht anhängen konnte).</summary>
    class function AtlasEntries: TArray<TAtlasKeyEntry>; static;
    /// <summary>Jede Atlas-Taste mit fremder Belegung für die Einrichtung (#625); Vorrang zählt nur, wenn Atlas
    /// die Taste auch wirklich hat.</summary>
    class function SetupKeys: TArray<TAtlasSetupKey>; static;
    /// <summary>Taste eines Atlas-Befehls der Palette als Text, wenn Atlas sie belegt; sonst ''.</summary>
    class function AtlasShortCut(const ACommandId: string): string; static;
    /// <summary>Ziel des HTML-Exports.</summary>
    class function ExportFile: string; static;
    /// <summary>Fenster zeigen und neu einlesen; Suche und Filter bleiben.</summary>
    procedure ShowWindow; overload;
    /// <summary>Fenster zeigen und nach AQuery suchen (Taste oder Text).</summary>
    procedure ShowWindow(const AQuery: string); overload;
    /// <summary>Fenster zeigen, Suche leeren: alle Kürzel (Link „Alle Kürzel“ der Tastenkürzel-Tipps, #600).
    /// </summary>
    procedure ShowAll;
    /// <summary>„Tastenkürzel-Übersicht…“ in der Befehlspalette, sichtbar nach keys.overview.</summary>
    procedure RegisterCommands(const ARegistry: IAtlasCommandRegistry);
    /// <summary>Package geladen: nach StartDelayMs die eigenen Tasten prüfen (keys.startupCheck).</summary>
    procedure CheckAtStart;
    /// <summary>Eigene Tasten prüfen und neue Konflikte melden; offenes Fenster neu einlesen.</summary>
    procedure CheckNow;
    procedure ThemeChanged;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.IOUtils,
  System.Generics.Collections,
  Vcl.ActnList,
  Vcl.Menus,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Keys,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.IDE.Commands.Usage,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.IDE.UnitSearch.Commands;

const
  KeyIdPrefix = 'Atlas.Key.';
  // Reihenfolge, in der die Komposition die Tasten anmeldet (RebindKeys); bei mehreren Atlas-Belegungen
  // derselben Taste gilt die zuletzt angemeldete. 3 = Editorbefehle (eine Bindung); Strg+F12 (#777) ist keine
  // Bindung, sondern eine Aktion und bekommt ihren Platz in der Aktionsliste.
  BindOrder: array[TAtlasKeyFunction] of Integer = (1, 2, 4, 5, 6, 7, 3, 3, 3, 3, 3, 3, 3, 8, 3, 3, 3, 3, 0, 3, 3, 3,
    8, 8, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    // Mehrfachmarken (#589): Editorbefehle.
    3, 3, 3, 3, 3,
    // Atlas-Suche (#877, #878): Editorbefehle.
    3, 3, 3, 3,
    // Formatieren (#43): Editorbefehl.
    3,
    // Blockkommentar umschalten (#703): Editorbefehl.
    3,
    // Neue Zeile ober- oder unterhalb (#700): Editorbefehle.
    3, 3,
    // Umschließung entfernen (#657): Editorbefehl.
    3,
    // Fenster „Atlas-Prüfung“ (#909): Editorbefehl.
    3,
    // Abschnittsknöpfe der Editorleiste (#1101): Editorbefehle.
    3, 3,
    // Schnelle Lesezeichen (#1104): Editorbefehle.
    3, 3, 3, 3, 3,
    // Ersetzen in der Atlas-Suche (#893): Editorbefehl.
    3,
    // Gezielt hineinspringen (#836): Editorbefehl.
    3,
    // Typ des markierten Ausdrucks (#689): Editorbefehl.
    3,
    // Sicher löschen (#716): Editorbefehl.
    3,
    // Issue anlegen (#1268): Editorbefehl.
    3);

type
  /// <summary>Herkunft je Modul, einmal ermittelt.</summary>
  TOrigins = class
  private type
    TOrigin = record
      Origin: TAtlasKeyOrigin;
      Name: string;
    end;
  private
    FCache: TDictionary<HMODULE, TOrigin>;
    FIdeFolder: string;
    FAtlasModule: string;
  public
    constructor Create;
    destructor Destroy; override;
    function OfModule(AModule: HMODULE; out AName: string): TAtlasKeyOrigin;
    function OfAddress(AAddress: Pointer; out AName: string): TAtlasKeyOrigin;
  end;

constructor TOrigins.Create;
begin
  inherited Create;
  FCache := TDictionary<HMODULE, TOrigin>.Create;
  FIdeFolder := ExtractFilePath(ParamStr(0));
  FAtlasModule := GetModuleName(HInstance);
end;

destructor TOrigins.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TOrigins.OfModule(AModule: HMODULE; out AName: string): TAtlasKeyOrigin;
var
  Entry: TOrigin;
begin
  if not FCache.TryGetValue(AModule, Entry) then
  begin
    if AModule = 0 then
    begin
      Entry.Origin := TAtlasKeyOrigin.Ide;
      Entry.Name := TAtlasKeyMap.IdeName;
    end
    else
      Entry.Origin := TAtlasKeyMap.OriginOfModule(GetModuleName(AModule), FIdeFolder, FAtlasModule, Entry.Name);
    FCache.Add(AModule, Entry);
  end;
  AName := Entry.Name;
  Result := Entry.Origin;
end;

function TOrigins.OfAddress(AAddress: Pointer; out AName: string): TAtlasKeyOrigin;
begin
  if AAddress = nil then
    Result := OfModule(0, AName)
  else
    Result := OfModule(HMODULE(FindHInstance(AAddress)), AName);
end;

function IndexOfFunc(const AItems: TArray<TAtlasKeyItem>; AFunc: TAtlasKeyFunction): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(AItems) do
    if (AItems[Index].Origin = TAtlasKeyOrigin.Atlas) and (AItems[Index].Id = KeyIdPrefix + IntToStr(Ord(AFunc))) then
      Exit(Index);
end;

/// <summary>Die Tasten von Atlas; ohne eigene Taste (Vervollständigung über Strg+Leer der IDE) oder abgeschaltet
/// keine Zeile. Strg+F12 (#777) kommt mit den Aktionen (AddActions).</summary>
procedure AddAtlasKeys(AItems: TList<TAtlasKeyItem>; const AEntries: TArray<TAtlasKeyEntry>);
var
  Entry: TAtlasKeyEntry;
  Item: TAtlasKeyItem;
begin
  for Entry in AEntries do
  begin
    if (Entry.Key = 0) or Entry.Disabled or (TAtlasKeyMap.SourceOf(Entry.Func) = TAtlasKeySource.Action) then
      Continue;
    Item := TAtlasKeyItem.Create(Entry.Key, ShortCutToText(TShortCut(Entry.Key)),
      TAtlasKeyMapWindow.FunctionCaption(Entry.Func), TAtlasKeyOrigin.Atlas, TAtlasKeyMap.AtlasName,
      TAtlasKeyMap.ContextOf(Entry.Func), TAtlasKeyMap.SourceOf(Entry.Func), KeyIdPrefix + IntToStr(Ord(Entry.Func)),
      BindOrder[Entry.Func]);
    Item.Category := TAtlasKeyMap.AtlasName;
    Item.Func := Entry.Func;
    Item.Priority := Entry.Priority;
    if Item.Source = TAtlasKeySource.Window then
      // Abgeschaltet (Willkommensseite oder Suchfeld aus) kommt es oben gar nicht an.
      Item.Active := True
    else
      // Wie beim Belegen (#494): frei oder mit Vorrang.
      Item.Active := TAtlasKeyConflicts.ShouldBind(Entry.Key, TAtlasIdeKeys.Owner(Entry.Key), Entry.Priority);
    AItems.Add(Item);
  end;
end;

procedure AddAction(AItems: TList<TAtlasKeyItem>; AOrigins: TOrigins; AAction: TCustomAction;
  AShortCut: TShortCut; AOrder: Integer; AHooked: Boolean);
var
  Origin: TAtlasKeyOrigin;
  Name, Caption: string;
  Item: TAtlasKeyItem;
begin
  // Die Aktion „Units“ ohne Übernahme durch Atlas (#777): Der Handler liegt in Atlas, ruft aber den Dialog der IDE.
  if AHooked then
  begin
    Origin := TAtlasKeyOrigin.Ide;
    Name := TAtlasKeyMap.IdeName;
  end
  else if SameText(AAction.Category, 'Atlas') or AAction.Category.StartsWith('Atlas.', True) then
  begin
    Origin := TAtlasKeyOrigin.Atlas;
    Name := TAtlasKeyMap.AtlasName;
  end
  // Der Handler liegt im Modul dessen, der die Aktion angelegt hat; ohne Handler zählt der Besitzer.
  else if Assigned(AAction.OnExecute) then
    Origin := AOrigins.OfAddress(TMethod(AAction.OnExecute).Code, Name)
  else if AAction.Owner <> nil then
    Origin := AOrigins.OfAddress(Pointer(AAction.Owner.ClassType), Name)
  else
    Origin := AOrigins.OfAddress(Pointer(AAction.ClassType), Name);
  Caption := TAtlasCommandPalette.CleanCaption(AAction.Caption);
  if Caption = '' then
    Caption := AAction.Name;
  Item := TAtlasKeyItem.Create(Word(AShortCut), ShortCutToText(AShortCut), Caption, Origin, Name,
    TAtlasKeyMap.ContextOfCategory(AAction.Category), TAtlasKeySource.Action, AAction.Name, AOrder);
  Item.Category := AAction.Category;
  AItems.Add(Item);
end;

/// <summary>Die von „Units suchen“ übernommene Aktion „Units“ (#777) als Atlas-Taste: bewusst übernommen, also
/// mit Vorrang; Platz in der Aktionsliste wie die Aktion selbst.</summary>
procedure AddUnitSearchAction(AItems: TList<TAtlasKeyItem>; AAction: TCustomAction; AShortCut: TShortCut;
  AOrder: Integer);
const
  Func = TAtlasKeyFunction.UnitSearchIde;
var
  Item: TAtlasKeyItem;
begin
  Item := TAtlasKeyItem.Create(Word(AShortCut), ShortCutToText(AShortCut), TAtlasKeyMapWindow.FunctionCaption(Func),
    TAtlasKeyOrigin.Atlas, TAtlasKeyMap.AtlasName, TAtlasKeyMap.ContextOf(Func), TAtlasKeyMap.SourceOf(Func),
    KeyIdPrefix + IntToStr(Ord(Func)), AOrder);
  Item.Category := AAction.Category;
  Item.Func := Func;
  Item.Priority := True;
  AItems.Add(Item);
end;

/// <summary>Taste der Aktion oder, bei der übernommenen Aktion „Units“ (#777) und eingeschalteter Übernahme, die
/// Atlas-Zeile dafür.</summary>
procedure AddActionKey(AItems: TList<TAtlasKeyItem>; AOrigins: TOrigins; AAction: TCustomAction;
  AShortCut: TShortCut; AOrder: Integer; AHooked, ATakenOver: Boolean);
begin
  if AHooked and ATakenOver then
    AddUnitSearchAction(AItems, AAction, AShortCut, AOrder)
  else
    AddAction(AItems, AOrigins, AAction, AShortCut, AOrder, AHooked);
end;

procedure AddActions(AItems: TList<TAtlasKeyItem>; AOrigins: TOrigins; const AEntries: TArray<TAtlasKeyEntry>);
var
  Services: INTAServices;
  Index, Secondary: Integer;
  Action: TCustomAction;
  Key: TShortCut;
  Hooked: TBasicAction;
  Entry: TAtlasKeyEntry;
  TakenOver, IsHooked: Boolean;
begin
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  Hooked := TAtlasIdeUnitSearch.HookedAction;
  TakenOver := False;
  for Entry in AEntries do
    if Entry.Func = TAtlasKeyFunction.UnitSearchIde then
      TakenOver := not Entry.Disabled;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    if not (Services.ActionList.Actions[Index] is TCustomAction) then
      Continue;
    Action := TCustomAction(Services.ActionList.Actions[Index]);
    IsHooked := (Hooked <> nil) and (Action = Hooked);
    if Action.ShortCut <> 0 then
      AddActionKey(AItems, AOrigins, Action, Action.ShortCut, Index, IsHooked, TakenOver);
    for Secondary := 0 to Action.SecondaryShortCuts.Count - 1 do
    begin
      Key := Action.SecondaryShortCuts.ShortCuts[Secondary];
      if (Key <> 0) and (Key <> Action.ShortCut) then
        AddActionKey(AItems, AOrigins, Action, Key, Index, IsHooked, TakenOver);
    end;
  end;
end;

/// <summary>Bekannte Belegungen der Standard-Tastaturbelegung (#494), die keine Aktionen sind.</summary>
procedure AddKnownIdeKeys(AItems: TList<TAtlasKeyItem>);
var
  Known: TAtlasKeyOwner;
  Command: string;
begin
  for Known in TAtlasKeyConflicts.KnownIdeKeys do
  begin
    Command := Known.Owner;
    if Command.StartsWith('IDE: ') then
      Command := Copy(Command, 6, MaxInt);
    AItems.Add(TAtlasKeyItem.Create(Known.ShortCut, ShortCutToText(TShortCut(Known.ShortCut)), Command,
      TAtlasKeyOrigin.Ide, TAtlasKeyMap.IdeName, TAtlasKeyContext.Editor, TAtlasKeySource.Binding,
      'Editor.' + IntToStr(Known.ShortCut), 0));
  end;
end;

/// <summary>Abzufragende Tasten: alle Einträge, dazu Strg/Alt mit Buchstaben, Ziffern, Leer und Enter sowie
/// F1–F12 mit jeder Umschaltung.</summary>
function ProbeKeys(const AItems: TArray<TAtlasKeyItem>): TArray<Word>;
const
  Modifiers: array[0..5] of Word = (TAtlasKeyMap.scCtrl, TAtlasKeyMap.scCtrl or TAtlasKeyMap.scShift,
    TAtlasKeyMap.scCtrl or TAtlasKeyMap.scAlt, TAtlasKeyMap.scCtrl or TAtlasKeyMap.scAlt or TAtlasKeyMap.scShift,
    TAtlasKeyMap.scAlt, TAtlasKeyMap.scAlt or TAtlasKeyMap.scShift);
var
  Seen: TDictionary<Word, Boolean>;
  Item: TAtlasKeyItem;
  Modifier: Word;
  Key: Integer;

  procedure Add(AKey: Word);
  begin
    if (AKey <> 0) and not Seen.ContainsKey(AKey) then
    begin
      Seen.Add(AKey, True);
      Result := Result + [AKey];
    end;
  end;

begin
  Result := nil;
  Seen := TDictionary<Word, Boolean>.Create;
  try
    for Item in AItems do
      Add(Item.ShortCut);
    for Modifier in Modifiers do
    begin
      for Key := Ord('A') to Ord('Z') do
        Add(Modifier or Word(Key));
      for Key := Ord('0') to Ord('9') do
        Add(Modifier or Word(Key));
      Add(Modifier or $20);
      Add(Modifier or $0D);
    end;
    for Key := $70 to $7B do
    begin
      Add(Word(Key));
      Add(TAtlasKeyMap.scShift or Word(Key));
      for Modifier in Modifiers do
        Add(Modifier or Word(Key));
    end;
  finally
    Seen.Free;
  end;
end;

/// <summary>Wirksame Tastaturbelegung des Editors für AKey: Code ihres Handlers; False ohne.</summary>
function LookupBinding(const AKeyboard: IOTAKeyboardServices; AKey: Word; out ACode: Pointer): Boolean;
var
  Binding: TKeyBindingRec;
begin
  ACode := nil;
  Binding := Default(TKeyBindingRec);
  try
    Result := AKeyboard.LookupKeyBinding([TShortCut(AKey)], Binding);
  except
    // Eine Taste, die die IDE nicht auflösen kann, zählt als frei.
    Result := False;
  end;
  if Result then
    ACode := TMethod(Binding.KeyProc).Code;
  Result := Result and (ACode <> nil);
end;

/// <summary>Tastaturbelegungen des Editors, soweit die IDE sie nennt: je Taste die wirksame mit ihrem Modul.
/// Atlas-Belegungen markieren die Atlas-Zeile als wirksam; Belegungen der IDE nur, wenn sie eine Taste von Atlas
/// oder einer Erweiterung treffen; Belegungen anderer Erweiterungen immer.</summary>
procedure AddBindings(AItems: TList<TAtlasKeyItem>; AOrigins: TOrigins);
var
  Keyboard: IOTAKeyboardServices;
  Key: Word;
  Code: Pointer;
  Origin: TAtlasKeyOrigin;
  Name: string;
  Index, Found, Count, Order: Integer;
  Shared: Boolean;
  Item: TAtlasKeyItem;
begin
  if not Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
    Exit;
  Order := 100;
  for Key in ProbeKeys(AItems.ToArray) do
  begin
    if not LookupBinding(Keyboard, Key, Code) then
      Continue;
    Origin := AOrigins.OfAddress(Code, Name);
    Inc(Order);
    case Origin of
      TAtlasKeyOrigin.Atlas:
        begin
          // Nur eindeutig zuzuordnen, wenn genau eine Atlas-Belegung diese Taste hat.
          Found := -1;
          Count := 0;
          for Index := 0 to AItems.Count - 1 do
            if (AItems[Index].Origin = TAtlasKeyOrigin.Atlas) and (AItems[Index].Source = TAtlasKeySource.Binding) and
              (AItems[Index].ShortCut = Key) then
            begin
              Found := Index;
              Inc(Count);
            end;
          if Count = 1 then
          begin
            Item := AItems[Found];
            Item.Effective := True;
            Item.Active := True;
            AItems[Found] := Item;
          end;
        end;
      TAtlasKeyOrigin.Ide:
        begin
          Found := -1;
          Shared := False;
          for Index := 0 to AItems.Count - 1 do
            if AItems[Index].ShortCut = Key then
            begin
              if (AItems[Index].Origin = TAtlasKeyOrigin.Ide) and (AItems[Index].Source = TAtlasKeySource.Binding) then
                Found := Index;
              if AItems[Index].Origin <> TAtlasKeyOrigin.Ide then
                Shared := True;
            end;
          if Found >= 0 then
          begin
            Item := AItems[Found];
            Item.Effective := True;
            AItems[Found] := Item;
          end
          else if Shared then
          begin
            Item := TAtlasKeyItem.Create(Key, ShortCutToText(TShortCut(Key)),
              TAtlasStrings.Text(TAtlasTextId.KeyMapEditorBinding), TAtlasKeyOrigin.Ide, TAtlasKeyMap.IdeName,
              TAtlasKeyContext.Editor, TAtlasKeySource.Binding, 'Editor.' + IntToStr(Key), Order);
            Item.Effective := True;
            AItems.Add(Item);
          end;
        end;
    else
      begin
        Item := TAtlasKeyItem.Create(Key, ShortCutToText(TShortCut(Key)),
          TAtlasStrings.Text(TAtlasTextId.KeyMapEditorBinding), Origin, Name, TAtlasKeyContext.Editor,
          TAtlasKeySource.Binding, 'Editor.' + IntToStr(Key), Order);
        Item.Effective := True;
        AItems.Add(Item);
      end;
    end;
  end;
end;

/// <summary>Zählung je Befehl aus der gemeinsamen Zählung (#600, #757); ohne sie bleibt sie 0.</summary>
procedure AddUsage(var AItems: TArray<TAtlasKeyItem>);
var
  Index: Integer;
  Id: string;
  Entry: TAtlasCommandUsageEntry;
begin
  if TAtlasIdeCommandUsage.Instance = nil then
    Exit;
  for Index := 0 to High(AItems) do
  begin
    case AItems[Index].Source of
      TAtlasKeySource.Action:
        // Strg+F12 für „Units suchen“ (#777) zählt beim Befehl der Palette.
        if (AItems[Index].Origin = TAtlasKeyOrigin.Atlas) and AItems[Index].Id.StartsWith(KeyIdPrefix) then
          Id := TAtlasShortcutTips.AtlasCommandId(AItems[Index].Func)
        else
          Id := AItems[Index].Id;
      TAtlasKeySource.Binding:
        if AItems[Index].Origin = TAtlasKeyOrigin.Atlas then
          Id := TAtlasShortcutTips.AtlasCommandId(AItems[Index].Func)
        else
          Id := '';
    else
      Id := '';
    end;
    if (Id <> '') and TAtlasIdeShortcutTips.UsageOf(Id, Entry) then
    begin
      AItems[Index].MouseUses := Entry.Mouse;
      AItems[Index].KeyUses := Entry.Keyboard;
    end;
  end;
end;

{ TAtlasIdeKeyMap }

constructor TAtlasIdeKeyMap.Create;
begin
  inherited Create;
  FInstance := Self;
end;

destructor TAtlasIdeKeyMap.Destroy;
begin
  if FInstance = Self then
    FInstance := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FWindow);
  inherited;
end;

class function TAtlasIdeKeyMap.Instance: TAtlasIdeKeyMap;
begin
  Result := FInstance;
end;

class function TAtlasIdeKeyMap.AtlasEntries: TArray<TAtlasKeyEntry>;
var
  Index: Integer;
  Hooked: TBasicAction;
begin
  Result := TAtlasKeyEntry.AllFromSettings(TAtlasIdeSettings.Current);
  Hooked := TAtlasIdeUnitSearch.HookedAction;
  for Index := 0 to High(Result) do
    if Result[Index].Func = TAtlasKeyFunction.UnitSearchIde then
    begin
      if Hooked is TCustomAction then
        Result[Index].Key := Word(TCustomAction(Hooked).ShortCut)
      else
        Result[Index].Key := 0;
    end;
end;

class function TAtlasIdeKeyMap.Collect: TArray<TAtlasKeyItem>;
var
  Origins: TOrigins;
  Items: TList<TAtlasKeyItem>;
  Entries: TArray<TAtlasKeyEntry>;
begin
  Entries := AtlasEntries;
  // Liste statt Anhängen ans Array: Die IDE hat weit über tausend Aktionen.
  Items := TList<TAtlasKeyItem>.Create;
  Origins := TOrigins.Create;
  try
    AddAtlasKeys(Items, Entries);
    AddActions(Items, Origins, Entries);
    AddKnownIdeKeys(Items);
    AddBindings(Items, Origins);
    Result := Items.ToArray;
  finally
    Origins.Free;
    Items.Free;
  end;
  TAtlasKeyMap.Analyze(Result);
  AddUsage(Result);
end;

class function TAtlasIdeKeyMap.SetupKeys: TArray<TAtlasSetupKey>;
var
  Items: TArray<TAtlasKeyItem>;
  Entry, Current: TAtlasKeyEntry;
  Index, Partner: Integer;
  Text, Owner: string;
begin
  Result := nil;
  Items := Collect;
  for Entry in AtlasEntries do
  begin
    Text := '';
    if Entry.Key <> 0 then
      Text := ShortCutToText(TShortCut(Entry.Key));
    Owner := '';
    Current := Entry;
    Index := IndexOfFunc(Items, Entry.Func);
    if (Index >= 0) and Items[Index].Conflict then
    begin
      Partner := TAtlasKeyMap.PartnerOf(Items, Index);
      if Partner >= 0 then
        Owner := Items[Partner].Holder;
      Current.Priority := Entry.Priority and Items[Index].Wins;
    end;
    Result := Result + [TAtlasSetupKey.Create(Current, Text, Owner)];
  end;
end;

class function TAtlasIdeKeyMap.AtlasShortCut(const ACommandId: string): string;
var
  Entry: TAtlasKeyEntry;
begin
  Result := '';
  if ACommandId = '' then
    Exit;
  // Mehrere Tasten für einen Befehl (#775, #777): die erste, die Atlas hält.
  for Entry in AtlasEntries do
    if (Entry.Key <> 0) and not Entry.Disabled and SameText(TAtlasKeyMap.CommandIdOf(Entry.Func), ACommandId) and
      TAtlasKeyConflicts.ShouldBind(Entry.Key, TAtlasIdeKeys.Owner(Entry.Key), Entry.Priority) then
      Exit(ShortCutToText(TShortCut(Entry.Key)));
end;

class function TAtlasIdeKeyMap.ExportFile: string;
var
  Folder: string;
begin
  Folder := GetEnvironmentVariable('LOCALAPPDATA');
  if Folder = '' then
    Folder := TPath.GetTempPath;
  Result := TPath.Combine(TPath.Combine(Folder, 'Atlas'), ExportFileName);
end;

procedure TAtlasIdeKeyMap.Refresh;
begin
  if FWindow <> nil then
    FWindow.SetItems(Collect);
end;

procedure TAtlasIdeKeyMap.ShowWindow;
begin
  ShowWindow('');
end;

procedure TAtlasIdeKeyMap.ShowWindow(const AQuery: string);
begin
  if FWindow = nil then
  begin
    FWindow := TAtlasKeyMapWindow.CreateKeyMap(nil, TAtlasIdeStyle.Colors);
    if Application.MainForm <> nil then
    begin
      FWindow.PopupMode := pmExplicit;
      FWindow.PopupParent := Application.MainForm;
    end;
    FWindow.OnExport :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Settings,
          procedure
          begin
            if FInstance <> nil then
              FInstance.ExportHtml;
          end);
      end;
    FWindow.OnSettings :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Settings,
          procedure
          begin
            if FInstance <> nil then
              FInstance.OpenKeyConflicts;
          end);
      end;
    FWindow.OnRefresh :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Settings,
          procedure
          begin
            if FInstance <> nil then
              FInstance.Refresh;
          end);
      end;
  end;
  FWindow.SetColors(TAtlasIdeStyle.Colors);
  Refresh;
  if AQuery <> '' then
    FWindow.SetQuery(AQuery);
  FWindow.Show;
  FWindow.BringToFront;
end;

procedure TAtlasIdeKeyMap.ShowAll;
begin
  ShowWindow;
  if FWindow <> nil then
    FWindow.SetQuery('');
end;

procedure TAtlasIdeKeyMap.ExportHtml;
var
  FileName, Html: string;
begin
  if FWindow = nil then
    Exit;
  FileName := ExportFile;
  try
    Html := FWindow.ExportHtml(FormatDateTime('ddddd t', Now));
    ForceDirectories(ExtractFileDir(FileName));
    TFile.WriteAllText(FileName, Html, TEncoding.UTF8);
    ShellExecute(0, 'open', PChar(FileName), nil, nil, SW_SHOWNORMAL);
    // Anonym: nur die Anzahl, kein Pfad.
    TAtlasGuard.Log(Format('Tastenkürzel-Übersicht exportiert: %d Zeilen (#520)', [Length(FWindow.Shown)]));
  except
    on E: Exception do
      TAtlasIdeKeys.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.KeyMapExportFailed, [E.ClassName]));
  end;
end;

procedure TAtlasIdeKeyMap.OpenKeyConflicts;
var
  Options: IOTAEnvironmentOptions140;
  Services: IOTAServices;
begin
  // Seite „Atlas.Tastenkonflikte“ (#494) unter Tools › Optionen; danach neu einlesen.
  if Supports(BorlandIDEServices, IOTAServices, Services) and
    Supports(Services.GetEnvironmentOptions, IOTAEnvironmentOptions140, Options) then
    Options.EditOptions('', 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.KeysTitle));
  Refresh;
end;

procedure TAtlasIdeKeyMap.RegisterCommands(const ARegistry: IAtlasCommandRegistry);
var
  Run: TProc;
  Visible: TFunc<Boolean>;
begin
  // Typisierte Variablen: Delphi wählt die Überladung mit anonymen Methoden sonst nicht (E2250).
  Run :=
    procedure
    begin
      if FInstance <> nil then
        FInstance.ShowWindow;
    end;
  Visible :=
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.KeyOverview;
    end;
  ARegistry.RegisterCommand(CommandId, TAtlasStrings.Text(TAtlasTextId.KeyMapMenu), '', Run, Visible);
end;

procedure TAtlasIdeKeyMap.CheckAtStart;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.OnTimer := TimerTick;
  end;
  FTimer.Interval := StartDelayMs;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeKeyMap.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      if FInstance <> nil then
        FInstance.CheckNow;
    end);
end;

procedure TAtlasIdeKeyMap.CheckNow;
var
  Items: TArray<TAtlasKeyItem>;
  Conflicts: TArray<Integer>;
  Index, Partner: Integer;
  Winner: string;
begin
  if (FWindow <> nil) and FWindow.Visible then
    Refresh;
  if not TAtlasIdeSettings.Current.KeyStartupCheck then
    Exit;
  Items := Collect;
  Conflicts := TAtlasKeyMap.AtlasConflicts(Items);
  // Anonym: nur Zahlen.
  TAtlasGuard.Log(Format('Tastenkürzel: %d Belegungen, %d mit Konflikt, %d Atlas-Tasten betroffen (#520)',
    [Length(Items), TAtlasKeyMap.ConflictCount(Items), Length(Conflicts)]));
  for Index in Conflicts do
  begin
    // Was #494 beim Belegen gemeldet hat, nicht noch einmal.
    if TAtlasIdeKeys.Reported(Items[Index].ShortCut) then
      Continue;
    Partner := TAtlasKeyMap.PartnerOf(Items, Index);
    if Partner < 0 then
      Continue;
    if Items[Index].Winner >= 0 then
      Winner := Items[Items[Index].Winner].Holder
    else
      Winner := TAtlasStrings.Text(TAtlasTextId.KeyMapNobody);
    TAtlasIdeKeys.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.KeyMapStartConflict,
      [Items[Index].KeyText, Items[Index].Command, Items[Partner].Holder, Winner]));
    TAtlasIdeKeys.MarkReported(Items[Index].ShortCut);
  end;
end;

procedure TAtlasIdeKeyMap.ThemeChanged;
begin
  if FWindow <> nil then
    FWindow.SetColors(TAtlasIdeStyle.Colors);
end;

end.
