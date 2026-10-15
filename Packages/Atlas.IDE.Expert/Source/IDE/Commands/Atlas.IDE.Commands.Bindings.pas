unit Atlas.IDE.Commands.Bindings;

// Tastenkürzel der Editorbefehle (#399) als eine Tastaturbindung der IDE
// (IOTAKeyboardBinding): Code-Aktionen (Alt+Enter), Auswahl erweitern
// (Strg+W) und verkleinern (Strg+Umschalt+W), Gehe zu Implementierung
// (Strg+Alt+I), Gehe zu Typdefinition (ohne Vorgabe), letzte
// Atlas-Änderung zurücknehmen (Strg+Alt+Z) und wiederherstellen
// (Strg+Alt+Umschalt+Z, #721) sowie Deklaration ⇄ Implementierung
// (Strg+Umschalt+↑/↓, #775), Unit ⇄ Testunit (#189), Units suchen (#777,
// nur solange unitSearch.enabled an ist) und „Lesezeichen setzen…“ (#622,
// Strg+Alt+K, nur solange bookmarks.named an ist). Jede Taste wird wie
// die der Befehlspalette vorher auf Konflikte geprüft (#494); ohne Vorrang
// bleibt eine fremde Belegung aktiv. Nach geänderten Einstellungen meldet
// Rebind die Bindung neu an. Der Befehl läuft nach der Tastenverarbeitung
// (ForceQueue), nicht in der Bindung selbst. Ausnahme sind Befehle mit
// Rückfall (AddAttemptKey): Sie laufen sofort, und ohne Treffer geht die
// Taste an die nächste Bindung (krNextProc), beim Wechsel Deklaration ⇄
// Implementierung also an die Klassennavigation der IDE.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Menus,
  ToolsAPI;

type
  TAtlasIdeEditorKeys = class
  private type
    TKey = record
      Key: Word;
      Proc: TProc;
      /// <summary>Statt Proc: sofort ausführen; False gibt die Taste an die nächste Bindung weiter.</summary>
      Attempt: TFunc<Boolean>;
    end;

    TBinding = class(TNotifierObject, IOTAKeyboardBinding)
    private
      FOwner: TAtlasIdeEditorKeys;
      procedure Pressed(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
    public
      function GetBindingType: TBindingType;
      function GetDisplayName: string;
      function GetName: string;
      procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    end;
  private
    FBinding: TBinding;
    // Hält das Binding am Leben: Abmelden gibt die Referenz der IDE frei, Rebind meldet es neu an.
    FBindingRef: IOTAKeyboardBinding;
    FBindingIndex: Integer;
    FKeys: TArray<TKey>;
    FBound: string;
    procedure AddKey(AKey: Integer; const AWhat: string; const AProc: TProc);
    procedure AddAttemptKey(AKey: Integer; const AWhat: string; const AAttempt: TFunc<Boolean>);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Tasten nach den Einstellungen (neu) belegen; bei Konflikt ohne Vorrang nicht (#494).</summary>
    procedure Rebind;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Commands.Keys,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.UnitSearch.Commands,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Bookmarks.Service;

{ TAtlasIdeEditorKeys.TBinding }

function TAtlasIdeEditorKeys.TBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TAtlasIdeEditorKeys.TBinding.GetDisplayName: string;
begin
  Result := 'Atlas-Editorbefehle';
end;

function TAtlasIdeEditorKeys.TBinding.GetName: string;
begin
  Result := 'Atlas.EditorCommands';
end;

procedure TAtlasIdeEditorKeys.TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
var
  Key: TKey;
begin
  if FOwner <> nil then
    for Key in FOwner.FKeys do
      BindingServices.AddKeyBinding([Key.Key], Pressed, nil);
end;

procedure TAtlasIdeEditorKeys.TBinding.Pressed(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
var
  Key: TKey;
  Proc: TProc;
  Attempt: TFunc<Boolean>;
  Done: Boolean;
begin
  BindingResult := krUnhandled;
  if FOwner = nil then
    Exit;
  for Key in FOwner.FKeys do
    if Key.Key = KeyCode then
    begin
      if Assigned(Key.Attempt) then
      begin
        Attempt := Key.Attempt;
        Done := False;
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            Done := Attempt();
          end);
        if Done then
          BindingResult := krHandled
        else
          BindingResult := krNextProc;
        Exit;
      end;
      BindingResult := krHandled;
      Proc := Key.Proc;
      // Keine Exception an die IDE (#493); erst nach der Tastenverarbeitung.
      TThread.ForceQueue(nil,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.EditorCommands, Proc);
        end);
      Exit;
    end;
end;

{ TAtlasIdeEditorKeys }

constructor TAtlasIdeEditorKeys.Create;
var
  Keyboard: IOTAKeyboardServices;
begin
  inherited Create;
  FBindingIndex := -1;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    FBinding := TBinding.Create;
    FBindingRef := FBinding;
    FBinding.FOwner := Self;
    Rebind;
  end;
end;

destructor TAtlasIdeEditorKeys.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  if FBinding <> nil then
    FBinding.FOwner := nil;
  TAtlasIdeKeys.Unbind(FBindingIndex);
  inherited;
end;

procedure TAtlasIdeEditorKeys.AddKey(AKey: Integer; const AWhat: string; const AProc: TProc);
var
  Key: TKey;
begin
  if not TAtlasIdeKeys.Decide(Word(AKey), TAtlasIdeSettings.Current.EditorKeysPriority, AWhat) then
    Exit;
  Key.Key := Word(AKey);
  Key.Proc := AProc;
  Key.Attempt := nil;
  FKeys := FKeys + [Key];
  FBound := FBound + IntToStr(AKey) + ';';
end;

procedure TAtlasIdeEditorKeys.AddAttemptKey(AKey: Integer; const AWhat: string; const AAttempt: TFunc<Boolean>);
var
  Existing, Key: TKey;
begin
  // Dieselbe Taste zweimal (beide Felder gleich belegt) nur einmal binden.
  for Existing in FKeys do
    if Existing.Key = Word(AKey) then
      Exit;
  if not TAtlasIdeKeys.Decide(Word(AKey), TAtlasIdeSettings.Current.EditorKeysPriority, AWhat) then
    Exit;
  Key.Key := Word(AKey);
  Key.Proc := nil;
  Key.Attempt := AAttempt;
  FKeys := FKeys + [Key];
  FBound := FBound + IntToStr(AKey) + ';';
end;

procedure TAtlasIdeEditorKeys.Rebind;
var
  Settings: TAtlasPluginSettings;
  Previous: string;
begin
  if FBinding = nil then
    Exit;
  Settings := TAtlasIdeSettings.Current;
  Previous := FBound;
  FKeys := nil;
  FBound := '';
  AddKey(Settings.ActionsKey, TAtlasStrings.Text(TAtlasTextId.EditorActions),
    procedure
    begin
      TAtlasIdeEditorCommands.CodeActions;
    end);
  AddKey(Settings.ExpandKey, TAtlasStrings.Text(TAtlasTextId.EditorExpand),
    procedure
    begin
      TAtlasIdeEditorCommands.ExpandSelection;
    end);
  AddKey(Settings.ShrinkKey, TAtlasStrings.Text(TAtlasTextId.EditorShrink),
    procedure
    begin
      TAtlasIdeEditorCommands.ShrinkSelection;
    end);
  AddKey(Settings.ImplementationKey, TAtlasStrings.Text(TAtlasTextId.MenuImplementations),
    procedure
    begin
      TAtlasIdeResults.FindImplementations;
    end);
  AddKey(Settings.TypeDefinitionKey, TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition),
    procedure
    begin
      TAtlasIdeEditorCommands.GoToTypeDefinition;
    end);
  // Deklaration ⇄ Implementierung (#775): aus = Taste bleibt bei der Klassennavigation der IDE.
  if Settings.MethodToggle then
  begin
    AddAttemptKey(Settings.MethodToggleUpKey, TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle),
      function: Boolean
      begin
        Result := TAtlasIdeEditorCommands.TryToggleMethod;
      end);
    AddAttemptKey(Settings.MethodToggleDownKey, TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle),
      function: Boolean
      begin
        Result := TAtlasIdeEditorCommands.TryToggleMethod;
      end);
  end;
  AddKey(Settings.TestUnitKey, TAtlasStrings.Text(TAtlasTextId.EditorTestUnit),
    procedure
    begin
      TAtlasIdeEditorCommands.SwitchTestUnit;
    end);
  // Units suchen (#777): aus = keine eigene Taste (die IDE behält Strg+F12 für ihren Dialog).
  if Settings.UnitSearchEnabled then
    AddKey(Settings.UnitSearchKey, TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle),
      procedure
      begin
        TAtlasIdeUnitSearch.Show;
      end);
  // Benannte Lesezeichen (#622): aus = keine Taste, die IDE-Lesezeichen bleiben unberührt.
  if Settings.BookmarksNamed then
    AddKey(Settings.BookmarkKey, TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd),
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Bookmarks,
          procedure
          begin
            TAtlasIdeBookmarks.AddBookmark;
          end);
      end);
  AddKey(Settings.UndoKey, TAtlasStrings.Text(TAtlasTextId.UndoMenu),
    procedure
    begin
      TAtlasIdeUndo.UndoLast;
    end);
  AddKey(Settings.RedoKey, TAtlasStrings.Text(TAtlasTextId.RedoMenu),
    procedure
    begin
      TAtlasIdeUndo.RedoLast;
    end);
  if (FBound = Previous) and ((FBindingIndex >= 0) = (FBound <> '')) then
    Exit;
  if FBound = '' then
    TAtlasIdeKeys.Unbind(FBindingIndex)
  else
    TAtlasIdeKeys.Bind(FBinding, FBindingIndex);
end;

end.
