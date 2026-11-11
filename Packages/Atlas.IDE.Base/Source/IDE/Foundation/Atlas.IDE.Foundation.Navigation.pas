unit Atlas.IDE.Foundation.Navigation;

// Zu einer Stelle springen (#400, #588): Datei öffnen, Editor zeigen, Cursor setzen. Foundation des Plugins
// (A-09): bis dahin TAtlasEditorHover.GoToLocation; Ergebnisfenster, Umbenennen, Vervollständigung, Befehle
// und Unit-Suche importierten dafür den Hover. Nur im Hauptthread.
// Ersatz-Units des Servers (atlas-ide:…, nur aus der RTTI der Packages) gibt es nicht als Datei: kein Sprung
// dorthin, die IDE legte sonst einen leeren Reiter unter diesem Namen an.

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
    /// <summary>Öffnet AFileName, markiert die ganze Zeile ALine (0-basiert) und setzt den Cursor an ihren Anfang,
    /// z. B. für den Sprung in eigenen Code nach einer Exception (#578).</summary>
    class procedure MarkLine(const AFileName: string; ALine: Integer); static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.IdeMembers;

/// <summary>Modul von AFileName; öffnet die Datei nur, wenn sie noch nicht offen ist. OpenFile öffnete sie sonst
/// jedes Mal neu (Doppelklick in „Atlas-Prüfung“), bei Formular-Units samt Designer. nil, wenn das scheitert.
/// </summary>
function OpenModule(const AFileName: string): IOTAModule;
var
  mActions: IOTAActionServices;
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if TAtlasIdeMembers.IsIdePath(AFileName) or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  Result := mModules.FindModule(AFileName);
  if (Result = nil) and Supports(BorlandIDEServices, IOTAActionServices, mActions) and
    mActions.OpenFile(AFileName) then
  begin
    Result := mModules.FindModule(AFileName);
  end;
end;

/// <summary>Erster Quelltexteditor des Moduls; nil ohne.</summary>
function SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    if Supports(AModule.ModuleFileEditors[mIndex], IOTASourceEditor, Result) then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

class procedure TAtlasIdeNavigation.GoToLocation(const AFileName: string; ALine, ACharacter: Integer);
var
  mModule: IOTAModule;
  mEditor: IOTASourceEditor;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  // Schon offen: nur den Reiter zeigen und springen.
  mModule := OpenModule(AFileName);
  if mModule = nil then
  begin
    Exit;
  end;
  mEditor := SourceEditorOf(mModule);
  if mEditor = nil then
  begin
    Exit;
  end;
  mEditor.Show;
  if mEditor.EditViewCount = 0 then
  begin
    Exit;
  end;
  mView := mEditor.EditViews[0];
  mCursor.Line := ALine + 1;
  mCursor.Col := ACharacter + 1;
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
end;

class function TAtlasIdeNavigation.ShowFile(const AFileName: string): Boolean;
var
  mActions: IOTAActionServices;
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex: Integer;
  mEditor: IOTASourceEditor;
begin
  Result := False;
  if TAtlasIdeMembers.IsIdePath(AFileName) or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  // Wie GoToLocation: OpenFile öffnete eine offene Datei erneut, bei Formular-Units samt Designer.
  mModule := mModules.FindModule(AFileName);
  if mModule <> nil then
  begin
    for mIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if Supports(mModule.ModuleFileEditors[mIndex], IOTASourceEditor, mEditor) then
      begin
        mEditor.Show;
        Exit(True);
      end;
    end;
  end;
  Result := Supports(BorlandIDEServices, IOTAActionServices, mActions) and mActions.OpenFile(AFileName);
end;

class procedure TAtlasIdeNavigation.GoToPosition(ALine, ACharacter: Integer);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Exit;
  end;
  mView := mEditors.TopView;
  if mView = nil then
  begin
    Exit;
  end;
  mCursor.Line := ALine + 1;
  mCursor.Col := ACharacter + 1;
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
end;

class procedure TAtlasIdeNavigation.MarkLine(const AFileName: string; ALine: Integer);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  GoToLocation(AFileName, ALine, 0);
  if not Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Exit;
  end;
  mView := mEditors.TopView;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, AFileName) then
  begin
    Exit;
  end;
  // Zeilenanfang markieren, Cursor an den Anfang der nächsten Zeile, Ende markieren, Cursor zurück.
  mView.Block.Style := btNonInclusive;
  mCursor.Line := ALine + 1;
  mCursor.Col := 1;
  mView.CursorPos := mCursor;
  mView.Block.BeginBlock;
  mCursor.Line := ALine + 2;
  mView.CursorPos := mCursor;
  mView.Block.EndBlock;
  mCursor.Line := ALine + 1;
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
end;

end.
