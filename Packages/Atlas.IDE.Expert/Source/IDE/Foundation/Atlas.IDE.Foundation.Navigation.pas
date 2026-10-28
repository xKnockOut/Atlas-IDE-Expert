unit Atlas.IDE.Foundation.Navigation;

// Zu einer Stelle springen (#400, #588): Datei öffnen, Editor zeigen, Cursor setzen. Foundation des Plugins
// (A-09): bis dahin TAtlasEditorHover.GoToLocation; Ergebnisfenster, Umbenennen, Vervollständigung, Befehle
// und Unit-Suche importierten dafür den Hover. Nur im Hauptthread.

interface

type
  TAtlasIdeNavigation = class
  public
    /// <summary>Zeigt AFileName (öffnet sie nur, wenn sie noch nicht offen ist) und setzt den Cursor auf
    /// ALine/ACharacter (0-basiert).</summary>
    class procedure GoToLocation(const AFileName: string; ALine, ACharacter: Integer); static;
    /// <summary>Zeigt AFileName ohne Sprung; öffnet sie nur, wenn sie noch nicht offen ist. False, wenn die IDE sie
    /// nicht öffnen kann.</summary>
    class function ShowFile(const AFileName: string): Boolean; static;
    /// <summary>Setzt den Cursor im oberen Editor auf ALine/ACharacter (0-basiert), z. B. für den Sprung
    /// einer Code-Aktion zur Freigabe (#915).</summary>
    class procedure GoToPosition(ALine, ACharacter: Integer); static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI;

class procedure TAtlasIdeNavigation.GoToLocation(const AFileName: string; ALine, ACharacter: Integer);
var
  Actions: IOTAActionServices;
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
  Editor: IOTASourceEditor;
  View: IOTAEditView;
  Cursor: TOTAEditPos;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  // Schon offen: nur den Reiter zeigen und springen. OpenFile öffnete die Datei sonst jedes Mal neu (Doppelklick in
  // „Atlas-Prüfung“), bei Formular-Units samt Designer.
  Module := Modules.FindModule(AFileName);
  if Module = nil then
  begin
    if not Supports(BorlandIDEServices, IOTAActionServices, Actions) or not Actions.OpenFile(AFileName) then
      Exit;
    Module := Modules.FindModule(AFileName);
    if Module = nil then
      Exit;
  end;
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Editor) then
    begin
      Editor.Show;
      if Editor.EditViewCount = 0 then
        Exit;
      View := Editor.EditViews[0];
      Cursor.Line := ALine + 1;
      Cursor.Col := ACharacter + 1;
      View.CursorPos := Cursor;
      View.MoveViewToCursor;
      View.Paint;
      Exit;
    end;
end;

class function TAtlasIdeNavigation.ShowFile(const AFileName: string): Boolean;
var
  Actions: IOTAActionServices;
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
  Editor: IOTASourceEditor;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  // Wie GoToLocation: OpenFile öffnete eine offene Datei erneut, bei Formular-Units samt Designer.
  Module := Modules.FindModule(AFileName);
  if Module <> nil then
    for Index := 0 to Module.ModuleFileCount - 1 do
      if Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Editor) then
      begin
        Editor.Show;
        Exit(True);
      end;
  Result := Supports(BorlandIDEServices, IOTAActionServices, Actions) and Actions.OpenFile(AFileName);
end;

class procedure TAtlasIdeNavigation.GoToPosition(ALine, ACharacter: Integer);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Cursor: TOTAEditPos;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Exit;
  View := Editors.TopView;
  if View = nil then
    Exit;
  Cursor.Line := ALine + 1;
  Cursor.Col := ACharacter + 1;
  View.CursorPos := Cursor;
  View.MoveViewToCursor;
  View.Paint;
end;

end.
