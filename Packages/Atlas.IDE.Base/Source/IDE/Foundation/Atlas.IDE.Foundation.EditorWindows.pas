unit Atlas.IDE.Foundation.EditorWindows;

// Das Editor-Steuerelement der Editorfenster der IDE (#1248). Die einzige
// Stelle, die das Steuerelement „Editor“ eines Editorfensters sucht
// (Tools/Check-WindowHosts.ps1 prüft das): zu einem Editorfenster, zu einem
// Steuerelement darin, im vordersten Editorfenster, und Fokus zurück an den
// Editor (Leiste schließen, Esc). Leisten-Hosts (TAtlasEditorBarHost) und
// Dienste nutzen es gleichermaßen. Dazu die Elternkette eines
// Steuerelements für das Protokoll, wenn eine Leiste im Editorfenster nicht
// so liegt wie erwartet.
// Nur im Hauptthread.

interface

uses
  Vcl.Controls,
  ToolsAPI;

type
  TAtlasIdeEditorWindows = class
  public const
    /// <summary>So viele Glieder nennt ParentChain höchstens.</summary>
    cMaxChainDepth = 8;
  public
    /// <summary>Editor-Steuerelement eines Editorfensters; nil, wenn es (noch) keins hat.</summary>
    class function EditorOf(const AWindow: INTAEditWindow): TWinControl; static;
    /// <summary>Editor-Steuerelement des Editorfensters, in dem AControl liegt; nil ohne.</summary>
    class function EditorIn(AControl: TControl): TWinControl; static;
    /// <summary>Editor des vordersten Editorfensters; nil ohne.</summary>
    class function TopEditor: TWinControl; static;
    /// <summary>Fokus an den Editor des Fensters, in dem AControl liegt (Leiste schließen, Esc).</summary>
    class procedure FocusEditor(AControl: TControl); static;
    /// <summary>AControl mit seinen Eltern bis zum Formular („Klasse Name &lt; …“), für das Protokoll.</summary>
    class function ParentChain(AControl: TControl): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms;

{ TAtlasIdeEditorWindows }

class function TAtlasIdeEditorWindows.EditorOf(const AWindow: INTAEditWindow): TWinControl;
var
  mEditor: TComponent;
begin
  Result := nil;
  if (AWindow = nil) or (AWindow.Form = nil) then
  begin
    Exit;
  end;
  mEditor := AWindow.Form.FindComponent('Editor');
  if (mEditor is TWinControl) and (TWinControl(mEditor).Parent <> nil) then
  begin
    Result := TWinControl(mEditor);
  end;
end;

class function TAtlasIdeEditorWindows.EditorIn(AControl: TControl): TWinControl;
var
  mForm: TCustomForm;
  mEditor: TComponent;
begin
  Result := nil;
  if AControl = nil then
  begin
    Exit;
  end;
  mForm := GetParentForm(AControl, False);
  if mForm = nil then
  begin
    Exit;
  end;
  mEditor := mForm.FindComponent('Editor');
  if mEditor is TWinControl then
  begin
    Result := TWinControl(mEditor);
  end;
end;

class function TAtlasIdeEditorWindows.TopEditor: TWinControl;
var
  mServices: INTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, INTAEditorServices, mServices) then
  begin
    Result := EditorOf(mServices.TopEditWindow);
  end;
end;

class procedure TAtlasIdeEditorWindows.FocusEditor(AControl: TControl);
var
  mForm: TCustomForm;
  mEditor: TComponent;
begin
  if AControl = nil then
  begin
    Exit;
  end;
  mForm := GetParentForm(AControl);
  if mForm = nil then
  begin
    Exit;
  end;
  mEditor := mForm.FindComponent('Editor');
  if (mEditor is TWinControl) and TWinControl(mEditor).CanFocus then
  begin
    TWinControl(mEditor).SetFocus;
  end;
end;

class function TAtlasIdeEditorWindows.ParentChain(AControl: TControl): string;
var
  mDepth: Integer;
  mControl: TControl;
begin
  Result := '';
  mDepth := 0;
  mControl := AControl;
  while (mControl <> nil) and (mDepth < cMaxChainDepth) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' < ';
    end;
    Result := Result + mControl.ClassName + ' ' + mControl.Name;
    mControl := mControl.Parent;
    Inc(mDepth);
  end;
end;

end.
