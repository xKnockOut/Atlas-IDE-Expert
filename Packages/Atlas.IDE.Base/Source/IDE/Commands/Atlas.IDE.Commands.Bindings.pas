unit Atlas.IDE.Commands.Bindings;

// Tastenkürzel der Editorbefehle (#399) als eine Tastaturbindung der IDE
// (IOTAKeyboardBinding): Code-Aktionen (Alt+Enter), Auswahl erweitern
// (Strg+W) und verkleinern (Strg+Umschalt+W), Gehe zu Implementierung
// (Strg+Alt+I), Gehe zu Typdefinition (ohne Vorgabe), letzte
// Atlas-Änderung zurücknehmen (Strg+Alt+Z) und wiederherstellen
// (Strg+Alt+Umschalt+Z, #721) sowie Deklaration ⇄ Implementierung
// (Strg+Umschalt+↑/↓, #775), Unit ⇄ Testunit (#189) sowie die Liste der
// Benachrichtigungen (#601, Strg+Umschalt+Alt+N, nur solange
// notifications.enabled an ist) und die Brotkrumenleiste (#590,
// Strg+Umschalt+., nur solange editor.breadcrumbs an ist) sowie der Sprung
// zum Gegenstück (#635, Strg+Ü bzw. Strg+Umschalt+Ü zum Markieren, nur
// solange keys.jumpToMatch an ist) und Zeilen verschieben bzw. duplizieren
// (#634, Alt+↑/↓ und Umschalt+Alt+↑/↓ mit Vorrang, nur solange keys.moveLines
// an ist) sowie die Mehrfachmarken (#589, Strg+D, Alt+Umschalt+I,
// Strg+Alt+↑/↓ mit Rückfall an die IDE, nur solange editor.multiCursor an
// ist), Blockkommentar umschalten (#703, Umschalt+Alt+A, nur solange
// keys.toggleBlockComment an ist), Neue Zeile ober- oder unterhalb (#700,
// Umschalt+Enter und Strg+Alt+Enter, nur solange keys.newLineAround an
// ist) und Umschließung entfernen (#657, Strg+Umschalt+Entf, nur solange
// keys.unwrap an ist) sowie die Tasten der Module (#1455, IAtlasKeySource:
// etwa Lesezeichen samt Zifferntasten und Akkord, „Gezielt hineinspringen“).
// Jede Taste wird wie
// die der Befehlspalette vorher auf Konflikte geprüft (#494); ohne Vorrang
// bleibt eine fremde Belegung aktiv. Jede Taste läuft unter der Sicherung
// (#493) ihrer Funktion; Fehler einer Funktion schalten die Tasten der
// übrigen nicht ab. Nach geänderten Einstellungen meldet
// Rebind die Bindung neu an. Der Befehl läuft nach der Tastenverarbeitung
// (ForceQueue), nicht in der Bindung selbst. Ausnahme sind Befehle mit
// Rückfall (AddAttemptKey): Sie laufen sofort, und ohne Treffer geht die
// Taste an die nächste Bindung (krNextProc), beim Wechsel Deklaration ⇄
// Implementierung also an die Klassennavigation der IDE. F3 und Umschalt+F3
// suchen eine einzeilige Markierung vorwärts bzw. rückwärts; ohne Markierung
// bleibt es bei „Erneut suchen“ der IDE. Strg+. (HideElementKey, #628) öffnet
// das Menü „Ausblenden“ zu den Elementen der Zeile; ohne Element geht die Taste
// an die IDE (IDE Insight).
// Die Tasten der Atlas-Suche (#877, #878) und von „Units suchen“ (#777)
// kommen vom Modul Suche (#1455); F3/Umschalt+F3 hier gelten nur, wenn es sie
// nicht belegt.
// Die Tasten selbst nimmt TAtlasEditorKeyList (Atlas.IDE.Commands.KeyList) auf; die Gruppen stehen in
// Atlas.IDE.Commands.KeysEditing und Atlas.IDE.Commands.KeysNavigation.

interface

uses
  System.Classes,
  ToolsAPI,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Commands.KeyList;

type
  TAtlasIdeEditorKeys = class(TAtlasEditorKeyList)
  private type
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
    /// <summary>Taste eines Moduls (#1455) nach ihrem Vorrang.</summary>
    procedure AddModuleKey(const AKey: TAtlasModuleKey);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Tasten nach den Einstellungen (neu) belegen; bei Konflikt ohne Vorrang nicht (#494).</summary>
    procedure Rebind;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Commands.KeysEditing,
  Atlas.IDE.Commands.KeysNavigation;

/// <summary>Taste AId eines Moduls (#1455): sucht sie beim Drücken neu, so erreicht die Taste ein abgemeldetes
/// Modul nicht mehr (Regel 3); ohne Modul geht sie an die IDE.</summary>
function ModuleAttempt(const AId: string): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    var
      mKey: TAtlasModuleKey;
    begin
      Result := False;
      for mKey in TAtlasModuleContributions.Keys(AtlasModuleRegistry) do
      begin
        if SameText(mKey.Id, AId) then
        begin
          Exit(mKey.Attempt());
        end;
      end;
    end;
end;

/// <summary>Taste AId eines Moduls ohne Rückfall (#1455): läuft nach der Tastenverarbeitung, sucht die Taste dann
/// neu (Regel 3).</summary>
function ModuleRun(const AId: string): TProc;
begin
  Result :=
    procedure
    var
      mKey: TAtlasModuleKey;
    begin
      for mKey in TAtlasModuleContributions.Keys(AtlasModuleRegistry) do
      begin
        if SameText(mKey.Id, AId) and Assigned(mKey.Run) then
        begin
          mKey.Run();
          Exit;
        end;
      end;
    end;
end;

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
  Key: TAtlasEditorKey;
begin
  if FOwner <> nil then
  begin
    for Key in FOwner.Keys do
    begin
      BindingServices.AddKeyBinding([Key.Key], Pressed, nil);
    end;
  end;
end;

procedure TAtlasIdeEditorKeys.TBinding.Pressed(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
var
  Key: TAtlasEditorKey;
  Feature: TAtlasFeature;
  Proc: TProc;
  Attempt: TFunc<Boolean>;
  Done: Boolean;
begin
  BindingResult := krUnhandled;
  if FOwner = nil then
  begin
    Exit;
  end;
  for Key in FOwner.Keys do
  begin
    if Key.Key = KeyCode then
    begin
      Feature := Key.Feature;
      if Assigned(Key.Attempt) then
      begin
        Attempt := Key.Attempt;
        Done := False;
        TAtlasGuard.Run(Feature,
          procedure
          begin
            Done := Attempt();
          end);
        if Done then
        begin
          BindingResult := krHandled;
        end
        else
        begin
          BindingResult := krNextProc;
        end;
        Exit;
      end;
      BindingResult := krHandled;
      Proc := Key.Proc;
      // Keine Exception an die IDE (#493); erst nach der Tastenverarbeitung.
      TAtlasMainThread.ForceQueue(Feature,
        procedure
        begin
          TAtlasGuard.Run(Feature, Proc);
        end);
      Exit;
    end;
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
  begin
    FBinding.FOwner := nil;
  end;
  TAtlasIdeKeys.Unbind(FBindingIndex);
  inherited;
end;

procedure TAtlasIdeEditorKeys.AddModuleKey(const AKey: TAtlasModuleKey);
begin
  // Fehler im Modul schalten nur die Editorbefehle ab, nicht das Modul; Module sichern ihre Befehle selbst.
  if Assigned(AKey.Attempt) then
    case AKey.Priority of
      TAtlasKeyPriority.Take:
        AddPriorityAttemptKey(TAtlasFeature.EditorCommands, AKey.Key, AKey.Caption, ModuleAttempt(AKey.Id), True);
      TAtlasKeyPriority.Yield:
        AddPriorityAttemptKey(TAtlasFeature.EditorCommands, AKey.Key, AKey.Caption, ModuleAttempt(AKey.Id), False);
    else
      AddAttemptKey(TAtlasFeature.EditorCommands, AKey.Key, AKey.Caption, ModuleAttempt(AKey.Id));
    end
  else
    case AKey.Priority of
      TAtlasKeyPriority.Take:
        AddPriorityKey(TAtlasFeature.EditorCommands, AKey.Key, AKey.Caption, ModuleRun(AKey.Id), True);
      TAtlasKeyPriority.Yield:
        AddPriorityKey(TAtlasFeature.EditorCommands, AKey.Key, AKey.Caption, ModuleRun(AKey.Id), False);
    else
      AddKey(TAtlasFeature.EditorCommands, AKey.Key, AKey.Caption, ModuleRun(AKey.Id));
    end;
end;

procedure TAtlasIdeEditorKeys.Rebind;
var
  mSettings: TAtlasPluginSettings;
  mPrevious: string;
  mModuleKey: TAtlasModuleKey;
begin
  if FBinding = nil then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  mPrevious := Bound;
  Clear;
  TAtlasEditingKeys.AddBasics(Self, mSettings);
  TAtlasEditingKeys.AddChecks(Self, mSettings);
  TAtlasEditingKeys.AddTextEdits(Self, mSettings);
  // Tasten der Module (#1455), z. B. „Gezielt hineinspringen“ des Debuggers: ohne Treffer an die IDE.
  // Lesezeichen (#622, #1104) samt Akkord und Zifferntasten kommen ebenso vom Modul.
  for mModuleKey in TAtlasModuleContributions.Keys(AtlasModuleRegistry) do
  begin
    AddModuleKey(mModuleKey);
  end;
  // Nach den Tasten der Module: Belegt die Suche (#878) F3 bzw. Umschalt+F3, schließt ihr Versuch Austrittspunkte
  // und Markierungssuche mit ein; sonst gelten die Tasten aus AddSearch.
  TAtlasEditingKeys.AddSearch(Self, mSettings);
  TAtlasNavigationKeys.AddJumps(Self, mSettings);
  TAtlasNavigationKeys.AddWindows(Self, mSettings);
  TAtlasEditingKeys.AddLineEdits(Self, mSettings);
  TAtlasEditingKeys.AddCursorAndUndo(Self, mSettings);
  if (Bound = mPrevious) and ((FBindingIndex >= 0) = (Bound <> '')) then
  begin
    Exit;
  end;
  if Bound = '' then
  begin
    TAtlasIdeKeys.Unbind(FBindingIndex);
  end
  else
  begin
    TAtlasIdeKeys.Bind(FBinding, FBindingIndex);
  end;
end;

end.
