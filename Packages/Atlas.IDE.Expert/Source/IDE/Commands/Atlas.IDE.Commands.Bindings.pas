unit Atlas.IDE.Commands.Bindings;

// Tastenkürzel der Editorbefehle (#399) als eine Tastaturbindung der IDE
// (IOTAKeyboardBinding): Code-Aktionen (Alt+Enter), Auswahl erweitern
// (Strg+W) und verkleinern (Strg+Umschalt+W), Gehe zu Implementierung
// (Strg+Alt+I), Gehe zu Typdefinition (ohne Vorgabe) sowie letzte
// Atlas-Änderung zurücknehmen (Strg+Alt+Z) und wiederherstellen
// (Strg+Alt+Umschalt+Z, #721). Jede Taste wird wie
// die der Befehlspalette vorher auf Konflikte geprüft (#494); ohne Vorrang
// bleibt eine fremde Belegung aktiv. Nach geänderten Einstellungen meldet
// Rebind die Bindung neu an. Der Befehl läuft nach der Tastenverarbeitung
// (ForceQueue), nicht in der Bindung selbst.

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
  Atlas.IDE.Undo.Changes;

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
begin
  BindingResult := krUnhandled;
  if FOwner = nil then
    Exit;
  for Key in FOwner.FKeys do
    if Key.Key = KeyCode then
    begin
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
