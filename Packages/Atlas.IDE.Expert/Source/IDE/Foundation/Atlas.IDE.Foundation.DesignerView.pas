unit Atlas.IDE.Foundation.DesignerView;

// Zeigt ein Editorfenster gerade den Formular-Designer statt des Code-Editors
// (#1442)? Im eingebetteten Designer liegen Editor und Designer im selben
// Editorfenster; die Leisten über dem Editor (TAtlasEditorBarHost) blenden
// sich danach ein und aus: Brotkrumen und Editorleiste nur im Code, die
// Designer-Leiste nur im Designer.
// - Formulare und Frames: Der Designer zeigt ein Editorfenster, wenn das
//   Fenster der Wurzel eines Formular-Editors (IOTAFormEditor) sichtbar ist
//   und unter dem Fenster des Editorfensters liegt. Verglichen wird über die
//   Fenster von Windows, nicht über Parent der VCL: Der eingebettete Designer
//   hängt das Formular nicht als VCL-Kind ein, GetParentForm der Wurzel ist
//   das Formular selbst (Fehler der ersten Fassung). Im Code-Reiter ist die
//   Designfläche verborgen und damit auch die Wurzel.
// - Datenmodul (Wurzel ohne Fenster): Der aktuelle Editor des aktuellen
//   Moduls (IOTAModuleServices.CurrentModule.CurrentEditor) ist der
//   Formular-Editor, und das Editorfenster ist das vorderste.
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
  private class var
    FForeignLogged: Boolean;
  private
    class function RootWindowShown(ARoot: TComponent; AWindow: THandle): Boolean; static;
    class function FormEditorShownIn(const AModule: IOTAModule; AWindow: THandle): IOTAFormEditor; static;
  public
    /// <summary>Formular-Editor, den der Designer gerade im vordersten Editorfenster zeigt; sonst nil.</summary>
    class function CurrentFormEditor: IOTAFormEditor; static;
    /// <summary>Wurzelkomponente des Formular-Editors (Formular, Frame, Datenmodul); nil ohne.</summary>
    class function RootOf(const AEditor: IOTAFormEditor): TComponent; static;
    /// <summary>Zeigt das Editorfenster mit dem Eltern-Steuerelement AEditorParent gerade den Designer?</summary>
    class function Shown(AEditorParent: TWinControl): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard;

/// <summary>Fenster des Editorfensters zu AEditorParent (das Formular der IDE, nicht das Hauptfenster); 0 ohne.
/// </summary>
function EditWindowHandle(AEditorParent: TWinControl): THandle;
var
  mForm: TCustomForm;
begin
  Result := 0;
  if AEditorParent = nil then
    Exit;
  mForm := GetParentForm(AEditorParent, False);
  if (mForm <> nil) and mForm.HandleAllocated then
    Result := mForm.Handle;
end;

function TopEditWindowHandle: THandle;
var
  mServices: INTAEditorServices;
  mWindow: INTAEditWindow;
begin
  Result := 0;
  if not Supports(BorlandIDEServices, INTAEditorServices, mServices) then
    Exit;
  mWindow := mServices.TopEditWindow;
  if (mWindow <> nil) and (mWindow.Form <> nil) and mWindow.Form.HandleAllocated then
    Result := mWindow.Form.Handle;
end;

function CurrentModule: IOTAModule;
var
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
    Result := mModules.CurrentModule;
end;

{ TAtlasIdeDesignerView }

class function TAtlasIdeDesignerView.RootWindowShown(ARoot: TComponent; AWindow: THandle): Boolean;
var
  mRoot: THandle;
  mClass: array[0..127] of Char;
begin
  Result := False;
  if (AWindow = 0) or not (ARoot is TWinControl) or not TWinControl(ARoot).HandleAllocated then
    Exit;
  mRoot := TWinControl(ARoot).Handle;
  if not IsWindowVisible(mRoot) then
    Exit;
  Result := IsChild(AWindow, mRoot);
  if Result or FForeignLogged then
    Exit;
  // Sichtbar, aber nicht in diesem Editorfenster: schwebender Designer oder ein anderes Editorfenster. Einmal
  // protokollieren, falls eine Delphi-Version den Designer anders einhängt.
  FForeignLogged := True;
  mClass[0] := #0;
  GetClassName(GetAncestor(mRoot, GA_PARENT), mClass, Length(mClass));
  TAtlasGuard.Log(Format('Designer-Ansicht: %s ist sichtbar, liegt aber nicht im Editorfenster (Elternfenster %s)',
    [ARoot.Name, string(mClass)]));
end;

class function TAtlasIdeDesignerView.FormEditorShownIn(const AModule: IOTAModule; AWindow: THandle): IOTAFormEditor;
var
  mIndex: Integer;
  mEditor: IOTAFormEditor;
begin
  Result := nil;
  if (AModule = nil) or (AWindow = 0) then
    Exit;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
    if Supports(AModule.ModuleFileEditors[mIndex], IOTAFormEditor, mEditor) and
      RootWindowShown(RootOf(mEditor), AWindow) then
      Exit(mEditor);
end;

class function TAtlasIdeDesignerView.CurrentFormEditor: IOTAFormEditor;
var
  mModule: IOTAModule;
  mEditor: IOTAEditor;
begin
  Result := nil;
  mModule := CurrentModule;
  if mModule = nil then
    Exit;
  // Formular oder Frame: sichtbar im vordersten Editorfenster.
  Result := FormEditorShownIn(mModule, TopEditWindowHandle);
  if Result <> nil then
    Exit;
  // Datenmodul: keine Wurzel mit Fenster; dann zählt der aktuelle Editor des Moduls.
  mEditor := mModule.CurrentEditor;
  if (mEditor = nil) or not Supports(mEditor, IOTAFormEditor, Result) then
    Exit(nil);
  if RootOf(Result) is TWinControl then
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
  mWindow: THandle;
  mModules: IOTAModuleServices;
  mIndex: Integer;
  mEditor: IOTAFormEditor;
begin
  Result := False;
  mWindow := EditWindowHandle(AEditorParent);
  if mWindow = 0 then
    Exit;
  // Jedes Editorfenster für sich: Ein zweites Fenster kann ein anderes Modul im Designer zeigen.
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
    for mIndex := 0 to mModules.ModuleCount - 1 do
      if FormEditorShownIn(mModules.Modules[mIndex], mWindow) <> nil then
        Exit(True);
  // Datenmodul: nur im vordersten Editorfenster.
  if mWindow <> TopEditWindowHandle then
    Exit;
  mEditor := CurrentFormEditor;
  Result := (mEditor <> nil) and not (RootOf(mEditor) is TWinControl);
end;

end.
