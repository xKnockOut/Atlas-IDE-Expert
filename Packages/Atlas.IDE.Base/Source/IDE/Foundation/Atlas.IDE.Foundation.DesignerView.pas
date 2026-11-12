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
    /// <summary>CodeShown und das Editorfenster von AEditor zeigt nicht den Designer: Leisten und Anfragen, die nur
    /// zum Code gehören. False bei AEditor = nil.</summary>
    class function CodeInFront(AEditor: TWinControl): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Text.LogMarks;

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
    [TLogMarks.Name(ARoot.Name), string(mClass)]));
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

/// <summary>Sichtbarer Editor mit Formular: dessen Rechteck auf dem Bildschirm.</summary>
function EditorArea(AEditor: TWinControl; out AForm: TCustomForm; out ARect: TRect): Boolean;
begin
  Result := False;
  AForm := nil;
  ARect := TRect.Empty;
  if (AEditor = nil) or not AEditor.HandleAllocated then
  begin
    Exit;
  end;
  AForm := GetParentForm(AEditor, False);
  Result := (AForm <> nil) and AForm.HandleAllocated and IsWindowVisible(AEditor.Handle) and
    GetWindowRect(AEditor.Handle, ARect) and (ARect.Width > 0) and (ARect.Height > 0);
end;

/// <summary>Von der Mitte des Editors aus abwärts durch die Kindfenster von AForm: True, wenn der Weg den Editor
/// erreicht; sonst ist AWindow das verdeckende Fenster.</summary>
function ReachesEditor(AForm, AEditor: THandle; const ARect: TRect; out AWindow: THandle): Boolean;
var
  mPoint: TPoint;
  mChild: THandle;
  mControl: TWinControl;
begin
  Result := False;
  AWindow := AForm;
  while not Result do
  begin
    // Eigene Fenster von Atlas über dem Editor (Definition einblenden, Minimap …) verdecken ihn nicht.
    mControl := FindControl(AWindow);
    Result := (AWindow = AEditor) or IsChild(AEditor, AWindow) or
      ((mControl <> nil) and mControl.ClassName.StartsWith('TAtlas'));
    if Result or ((AWindow <> AForm) and not IsChild(AWindow, AEditor)) then
    begin
      Break;
    end;
    mPoint := ARect.CenterPoint;
    ScreenToClient(AWindow, mPoint);
    mChild := ChildWindowFromPointEx(AWindow, mPoint, CWP_SKIPINVISIBLE or CWP_SKIPTRANSPARENT);
    if (mChild = 0) or (mChild = AWindow) then
    begin
      Break;
    end;
    AWindow := mChild;
  end;
end;

class function TAtlasIdeDesignerView.CodeInFront(AEditor: TWinControl): Boolean;
begin
  Result := (AEditor <> nil) and CodeShown(AEditor) and not Shown(AEditor.Parent);
end;

class function TAtlasIdeDesignerView.CodeShown(AEditor: TWinControl): Boolean;
var
  mForm: TCustomForm;
  mWindow: THandle;
  mRect: TRect;
  mClass: array[0..127] of Char;
begin
  if not EditorArea(AEditor, mForm, mRect) then
  begin
    Exit(False);
  end;
  Result := ReachesEditor(mForm.Handle, AEditor.Handle, mRect, mWindow);
  if Result or FCoveredLogged then
  begin
    Exit;
  end;
  FCoveredLogged := True;
  mClass[0] := #0;
  GetClassName(mWindow, mClass, Length(mClass));
  TAtlasGuard.Log(Format('Code-Ansicht: Editor ist verdeckt (Fenster der Klasse %s), Code-Leisten aus',
    [string(mClass)]));
end;

end.
