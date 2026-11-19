unit Atlas.IDE.Foundation.EditorTabs;

// Reiter des obersten Editorfensters der IDE: Die Open Tools API nennt keine Reihenfolge der Reiter. Das
// Editorfenster führt sie in einem Steuerelement „TabControl“ (TTabSet-Abkömmling) mit der veröffentlichten
// Eigenschaft „Tabs“; deren Beschriftungen ordnet TAtlasEditorTabOrder den offenen Dateien zu. Genutzt von
// „Fortsetzen“ der Willkommensseite und vom IDE-Zustand für KI-Assistenten (#2050). Nur im Hauptthread.

interface

type
  TAtlasEditorTabs = class
  public
    /// <summary>Beschriftungen der Reiter des obersten Editorfensters in ihrer Reihenfolge; leer ohne.</summary>
    class function Captions: TArray<string>; static;
    /// <summary>AFiles in der Reihenfolge der Reiter (siehe Captions); ohne Reiter unverändert.</summary>
    class function Ordered(const AFiles: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Editor.TabOrder;

/// <summary>Beschriftungen eines Reiter-Steuerelements (veröffentlichte Eigenschaft „Tabs“ als TStrings).</summary>
function TabsOf(AComponent: TComponent): TArray<string>;
var
  mValue: TObject;
begin
  Result := nil;
  if (AComponent = nil) or not IsPublishedProp(AComponent, 'Tabs') or
    (PropType(AComponent, 'Tabs') <> tkClass) then
  begin
    Exit;
  end;
  mValue := GetObjectProp(AComponent, 'Tabs');
  if mValue is TStrings then
  begin
    Result := TStrings(mValue).ToStringArray;
  end;
end;

/// <summary>Formular des obersten Editorfensters; nil ohne.</summary>
function EditForm: TCustomForm;
var
  mServices: INTAEditorServices;
  mWindow: INTAEditWindow;
begin
  Result := nil;
  if Supports(BorlandIDEServices, INTAEditorServices, mServices) then
  begin
    mWindow := mServices.TopEditWindow;
    if mWindow <> nil then
    begin
      Result := mWindow.Form;
    end;
  end;
end;

class function TAtlasEditorTabs.Captions: TArray<string>;
var
  mForm: TCustomForm;
  mIndex: Integer;
begin
  Result := nil;
  mForm := EditForm;
  if mForm = nil then
  begin
    Exit;
  end;
  Result := TabsOf(mForm.FindComponent('TabControl'));
  mIndex := 0;
  while (Length(Result) = 0) and (mIndex < mForm.ComponentCount) do
  begin
    Result := TabsOf(mForm.Components[mIndex]);
    Inc(mIndex);
  end;
end;

class function TAtlasEditorTabs.Ordered(const AFiles: TArray<string>): TArray<string>;
begin
  Result := TAtlasEditorTabOrder.Order(AFiles, Captions);
end;

end.
