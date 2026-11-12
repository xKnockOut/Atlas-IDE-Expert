unit Atlas.IDE.Commands.MenuContext;

// Lage beim Öffnen des Untermenüs „Atlas“ im Kontextmenü des Editors
// (TAtlasMenuContext, Regeln in Atlas.Core.Commands.MenuContext): Datei und
// Text der obersten Editoransicht, ob ihr Modul ein Formular hat, ob ein
// Prozess debuggt wird, Zahl der Befunde der Datei. Refresh liest sie beim
// Öffnen des Menüs neu (nie im Leerlauf). Solange sie nie gelesen wurde oder
// das Lesen scheiterte, gilt sie als unbekannt und alle Einträge bleiben
// sichtbar.
// Die Einstellungen commands.editorContextMenu.contextual (nur passende
// Einträge) und commands.editorContextMenu.groups (gezeigte Untermenüs) fragt
// das Kontextmenü hier ab.

interface

uses
  Atlas.Core.Modules.Contract;

type
  TAtlasIdeMenuContext = class
  private class var
    FContext: TAtlasMenuContext;
    FKnown: Boolean;
  public
    /// <summary>Lage aus der IDE neu lesen; bei einem Fehler unbekannt.</summary>
    class procedure Refresh; static;
    /// <summary>Zuletzt gelesene Lage.</summary>
    class function Current: TAtlasMenuContext; static;
    /// <summary>Passt ein Eintrag mit der Bedingung AWhen? Ohne Lage oder mit abgeschalteter Einstellung immer.
    /// </summary>
    class function Applies(const AWhen: TAtlasMenuWhen): Boolean; static;
    /// <summary>Zeigt commands.editorContextMenu.groups das Untermenü mit der Kennung AKey?</summary>
    class function GroupShown(const AKey: string): Boolean; static;
    /// <summary>Zahl der Befunde der Datei, wenn nur Passendes gezeigt wird und die Lage bekannt ist; sonst 0.
    /// </summary>
    class function ProblemCount: Integer; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Commands.MenuContext,
  Atlas.Core.Settings.ContextMenuGroups,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Commands.EditorContext;

/// <summary>Hat das Modul ein Formular (DFM bzw. FMX im Designer)?</summary>
function ModuleHasForm(const AModule: IOTAModule): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if AModule = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    if Supports(AModule.ModuleFileEditors[mIndex], IOTAFormEditor) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Wird gerade ein Prozess debuggt?</summary>
function Debugging: Boolean;
var
  mDebugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) and (mDebugger.ProcessCount > 0);
end;

/// <summary>Zahl der Befunde von AFileName; 0 ohne Quelle.</summary>
function ProblemsOf(const AFileName: string): Integer;
begin
  Result := 0;
  if (AFileName <> '') and Assigned(TAtlasEditorCommandContext.OnProblemsOf) then
  begin
    Result := Length(TAtlasEditorCommandContext.OnProblemsOf(AFileName));
  end;
end;

{ TAtlasIdeMenuContext }

class procedure TAtlasIdeMenuContext.Refresh;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mFileName, mText: string;
  mForm: Boolean;
begin
  FKnown := False;
  try
    mFileName := '';
    mText := '';
    mForm := False;
    if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
    begin
      mView := mEditors.TopView;
    end;
    if (mView <> nil) and (mView.Buffer <> nil) then
    begin
      mFileName := mView.Buffer.FileName;
      mText := TAtlasEditorBuffer.Text(mView.Buffer);
      mForm := ModuleHasForm(mView.Buffer.Module);
    end;
    FContext := TAtlasMenuContextRules.Read(mFileName, mText, mForm, Debugging, ProblemsOf(mFileName));
    FKnown := True;
  except
    on E: Exception do
      TAtlasGuard.Log('Context menu: cannot read the editor state: ' + E.Message);
  end;
end;

class function TAtlasIdeMenuContext.Current: TAtlasMenuContext;
begin
  Result := FContext;
end;

class function TAtlasIdeMenuContext.Applies(const AWhen: TAtlasMenuWhen): Boolean;
begin
  Result := TAtlasMenuContextRules.Applies(FKnown, TAtlasIdeSettings.Current.EditorContextMenuContextual, AWhen,
    FContext);
end;

class function TAtlasIdeMenuContext.GroupShown(const AKey: string): Boolean;
begin
  Result := TAtlasContextMenuGroupNames.Shown(TAtlasIdeSettings.Current.EditorContextMenuGroups, AKey);
end;

class function TAtlasIdeMenuContext.ProblemCount: Integer;
begin
  Result := 0;
  if FKnown and TAtlasIdeSettings.Current.EditorContextMenuContextual then
  begin
    Result := FContext.ProblemCount;
  end;
end;

end.
