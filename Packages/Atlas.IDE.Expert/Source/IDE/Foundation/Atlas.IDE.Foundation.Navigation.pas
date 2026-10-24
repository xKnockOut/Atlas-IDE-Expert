unit Atlas.IDE.Foundation.Navigation;

// Zu einer Stelle springen (#400, #588): Datei öffnen, Editor zeigen, Cursor setzen. Foundation des Plugins
// (A-09): bis dahin TAtlasEditorHover.GoToLocation; Ergebnisfenster, Umbenennen, Vervollständigung, Befehle
// und Unit-Suche importierten dafür den Hover. Nur im Hauptthread.

interface

type
  TAtlasIdeNavigation = class
  public
    /// <summary>Öffnet AFileName und setzt den Cursor auf ALine/ACharacter (0-basiert).</summary>
    class procedure GoToLocation(const AFileName: string; ALine, ACharacter: Integer); static;
    /// <summary>Setzt den Cursor im oberen Editor auf ALine/ACharacter (0-basiert), z. B. für den Sprung
    /// einer Code-Aktion zur Freigabe (#915).</summary>
    class procedure GoToPosition(ALine, ACharacter: Integer); static;
    /// <summary>Öffnet AFileName, markiert die ganze Zeile ALine (0-basiert) und setzt den Cursor an ihren Anfang,
    /// z. B. für den Sprung in eigenen Code nach einer Exception (#578).</summary>
    class procedure MarkLine(const AFileName: string; ALine: Integer); static;
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
  if not Supports(BorlandIDEServices, IOTAActionServices, Actions) or not Actions.OpenFile(AFileName) or
    not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Module := Modules.FindModule(AFileName);
  if Module = nil then
    Exit;
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

class procedure TAtlasIdeNavigation.MarkLine(const AFileName: string; ALine: Integer);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Cursor: TOTAEditPos;
begin
  GoToLocation(AFileName, ALine, 0);
  if not Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Exit;
  View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, AFileName) then
    Exit;
  // Zeilenanfang markieren, Cursor an den Anfang der nächsten Zeile, Ende markieren, Cursor zurück.
  View.Block.Style := btNonInclusive;
  Cursor.Line := ALine + 1;
  Cursor.Col := 1;
  View.CursorPos := Cursor;
  View.Block.BeginBlock;
  Cursor.Line := ALine + 2;
  View.CursorPos := Cursor;
  View.Block.EndBlock;
  Cursor.Line := ALine + 1;
  View.CursorPos := Cursor;
  View.MoveViewToCursor;
  View.Paint;
end;

end.
