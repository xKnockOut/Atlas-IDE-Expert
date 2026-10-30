unit Atlas.IDE.Foundation.DesignerView;

// Zeigt ein Editorfenster gerade den Formular-Designer statt des Code-Editors
// (#1442)? Im eingebetteten Designer liegen Editor und Designer im selben
// Editorfenster; die Leisten über dem Editor (TAtlasEditorBarHost) blenden
// sich danach ein und aus: Brotkrumen und Editorleiste nur im Code, die
// Designer-Leiste nur im Designer.
// - Das aktuelle Modul der IDE (IOTAModuleServices.CurrentModule) zeigt den
//   Designer, wenn sein aktueller Editor ein IOTAFormEditor ist (Taste F12,
//   Reiter „Design“).
// - Zu welchem Editorfenster er gehört: Die Wurzel des Designers (Formular
//   oder Frame) liegt im eingebetteten Designer im Formular des
//   Editorfensters. Ohne sichtbare Wurzel (Datenmodul) gilt das vorderste
//   Editorfenster.
// - Ein frei schwebender Designer (eingebetteter Designer aus) liegt in einem
//   eigenen Fenster; das Editorfenster zeigt dann weiter Code.
// Nur im Hauptthread.

interface

uses
  System.Classes,
  Vcl.Controls,
  ToolsAPI;

type
  TAtlasIdeDesignerView = class
  public
    /// <summary>Formular-Editor des aktuellen Moduls, wenn er gerade angezeigt wird; sonst nil.</summary>
    class function CurrentFormEditor: IOTAFormEditor; static;
    /// <summary>Wurzelkomponente des Formular-Editors (Formular, Frame, Datenmodul); nil ohne.</summary>
    class function RootOf(const AEditor: IOTAFormEditor): TComponent; static;
    /// <summary>Zeigt das Editorfenster mit dem Eltern-Steuerelement AEditorParent gerade den Designer?</summary>
    class function Shown(AEditorParent: TWinControl): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms;

{ TAtlasIdeDesignerView }

class function TAtlasIdeDesignerView.CurrentFormEditor: IOTAFormEditor;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mEditor: IOTAEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
    Exit;
  mModule := mModules.CurrentModule;
  if mModule = nil then
    Exit;
  mEditor := mModule.CurrentEditor;
  if (mEditor = nil) or not Supports(mEditor, IOTAFormEditor, Result) then
    Result := nil;
end;

class function TAtlasIdeDesignerView.RootOf(const AEditor: IOTAFormEditor): TComponent;
var
  mComponent: INTAComponent;
begin
  Result := nil;
  if (AEditor <> nil) and Supports(AEditor.GetRootComponent, INTAComponent, mComponent) then
    Result := mComponent.GetComponent;
end;

class function TAtlasIdeDesignerView.Shown(AEditorParent: TWinControl): Boolean;
var
  mRoot: TComponent;
  mServices: INTAEditorServices;
  mWindow: INTAEditWindow;
begin
  Result := False;
  if AEditorParent = nil then
    Exit;
  mRoot := RootOf(CurrentFormEditor);
  if mRoot = nil then
    Exit;
  if mRoot is TWinControl then
  begin
    // Eingebettet: Die Wurzel liegt im Formular des Editorfensters.
    Result := TWinControl(mRoot).Showing and
      (GetParentForm(TWinControl(mRoot), True) = GetParentForm(AEditorParent, True));
    Exit;
  end;
  // Datenmodul (keine sichtbare Wurzel): das vorderste Editorfenster.
  if not Supports(BorlandIDEServices, INTAEditorServices, mServices) then
    Exit;
  mWindow := mServices.TopEditWindow;
  Result := (mWindow <> nil) and (mWindow.Form <> nil) and (mWindow.Form = GetParentForm(AEditorParent, True));
end;

end.
