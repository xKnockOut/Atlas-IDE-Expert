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
// - Code (CodeShown): Das Steuerelement des Editors ist sichtbar und nicht
//   verdeckt. Die Willkommensseite der IDE und der Designer liegen im selben
//   Editorfenster über bzw. statt dem Editor; dort sind Brotkrumen und
//   Editorleiste fehl am Platz (#1442). Verdeckt heißt: Geht man von der Mitte
//   des Editors aus durch die Kindfenster des Editorfensters (Z-Reihenfolge),
//   landet man nicht beim Editor.
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
    FCoveredLogged: Boolean;
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
    /// <summary>Zeigt das Editorfenster mit dem Editor-Steuerelement AEditor (TAtlasEditorBarHost.EditorIn) gerade
    /// den Code-Editor (sichtbar, nicht von Willkommensseite oder Designer verdeckt)?</summary>
    class function CodeShown(AEditor: TWinControl): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
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
  begin
    Exit;
  end;
  mForm := GetParentForm(AEditorParent, False);
  if (mForm <> nil) and mForm.HandleAllocated then
  begin
    Result := mForm.Handle;
  end;
end;

function TopEditWindowHandle: THandle;
var
  mServices: INTAEditorServices;
  mWindow: INTAEditWindow;
begin
  Result := 0;
  if not Supports(BorlandIDEServices, INTAEditorServices, mServices) then
  begin
    Exit;
  end;
  mWindow := mServices.TopEditWindow;
  if (mWindow <> nil) and (mWindow.Form <> nil) and mWindow.Form.HandleAllocated then
  begin
    Result := mWindow.Form.Handle;
  end;
end;

function CurrentModule: IOTAModule;
var
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Result := mModules.CurrentModule;
  end;
end;

{ TAtlasIdeDesignerView }

class function TAtlasIdeDesignerView.RootWindowShown(ARoot: TComponent; AWindow: THandle): Boolean;
var
  mRoot: THandle;
  mClass: array[0..127] of Char;
begin
  Result := False;
  if (AWindow = 0) or not (ARoot is TWinControl) or not TWinControl(ARoot).HandleAllocated then
  begin
    Exit;
  end;
  mRoot := TWinControl(ARoot).Handle;
  if not IsWindowVisible(mRoot) then
  begin
    Exit;
  end;
  Result := IsChild(AWindow, mRoot);
  if Result or FForeignLogged then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    if Supports(AModule.ModuleFileEditors[mIndex], IOTAFormEditor, mEditor) and
      RootWindowShown(RootOf(mEditor), AWindow) then
    begin
      Exit(mEditor);
    end;
  end;
end;

class function TAtlasIdeDesignerView.CurrentFormEditor: IOTAFormEditor;
var
  mModule: IOTAModule;
  mEditor: IOTAEditor;
begin
  Result := nil;
  mModule := CurrentModule;
  if mModule = nil then
  begin
    Exit;
  end;
  // Formular oder Frame: sichtbar im vordersten Editorfenster.
  Result := FormEditorShownIn(mModule, TopEditWindowHandle);
  if Result <> nil then
  begin
    Exit;
  end;
  // Datenmodul: keine Wurzel mit Fenster; dann zählt der aktuelle Editor des Moduls.
  mEditor := mModule.CurrentEditor;
  if (mEditor = nil) or not Supports(mEditor, IOTAFormEditor, Result) then
  begin
    Exit(nil);
  end;
  if RootOf(Result) is TWinControl then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeDesignerView.RootOf(const AEditor: IOTAFormEditor): TComponent;
var
  mComponent: INTAComponent;
begin
  Result := nil;
  if (AEditor <> nil) and Supports(AEditor.GetRootComponent, INTAComponent, mComponent) then
  begin
    Result := mComponent.GetComponent;
  end;
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
  begin
    Exit;
  end;
  // Jedes Editorfenster für sich: Ein zweites Fenster kann ein anderes Modul im Designer zeigen.
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    for mIndex := 0 to mModules.ModuleCount - 1 do
    begin
      if FormEditorShownIn(mModules.Modules[mIndex], mWindow) <> nil then
      begin
        Exit(True);
      end;
    end;
  end;
  // Datenmodul: nur im vordersten Editorfenster.
  if mWindow <> TopEditWindowHandle then
  begin
    Exit;
  end;
  mEditor := CurrentFormEditor;
  Result := (mEditor <> nil) and not (RootOf(mEditor) is TWinControl);
end;

class function TAtlasIdeDesignerView.CodeShown(AEditor: TWinControl): Boolean;
var
  mForm: TCustomForm;
  mHandle, mWindow, mChild: THandle;
  mRect: TRect;
  mPoint: TPoint;
  mClass: array[0..127] of Char;
  mControl: TWinControl;
begin
  Result := False;
  if (AEditor = nil) or not AEditor.HandleAllocated then
  begin
    Exit;
  end;
  mForm := GetParentForm(AEditor, False);
  if (mForm = nil) or not mForm.HandleAllocated then
  begin
    Exit;
  end;
  mHandle := AEditor.Handle;
  if not IsWindowVisible(mHandle) or not GetWindowRect(mHandle, mRect) or (mRect.Width <= 0) or
    (mRect.Height <= 0) then
  begin
    Exit;
  end;
  // Von der Mitte des Editors aus abwärts durch die Kindfenster: Liegt etwas darüber, endet der Weg dort.
  mPoint := mRect.CenterPoint;
  mWindow := mForm.Handle;
  while True do
  begin
    if (mWindow = mHandle) or IsChild(mHandle, mWindow) then
    begin
      Exit(True);
    end;
    // Eigene Fenster von Atlas über dem Editor (Definition einblenden, Minimap …) verdecken ihn nicht.
    mControl := FindControl(mWindow);
    if (mControl <> nil) and mControl.ClassName.StartsWith('TAtlas') then
    begin
      Exit(True);
    end;
    if (mWindow <> mForm.Handle) and not IsChild(mWindow, mHandle) then
    begin
      Break;
    end;
    mPoint := mRect.CenterPoint;
    ScreenToClient(mWindow, mPoint);
    mChild := ChildWindowFromPointEx(mWindow, mPoint, CWP_SKIPINVISIBLE or CWP_SKIPTRANSPARENT);
    if (mChild = 0) or (mChild = mWindow) then
    begin
      Break;
    end;
    mWindow := mChild;
  end;
  if not FCoveredLogged then
  begin
    FCoveredLogged := True;
    mClass[0] := #0;
    GetClassName(mWindow, mClass, Length(mClass));
    TAtlasGuard.Log(Format('Code-Ansicht: Editor ist verdeckt (Fenster der Klasse %s), Code-Leisten aus',
      [string(mClass)]));
  end;
end;

end.
