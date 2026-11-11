unit Atlas.IDE.Designer.Access;

// Zugriff des Moduls Designer auf den Formular-Designer der IDE (#1442,
// #738): aktiver Designer und sein Formular, Auswahl lesen und setzen, Lage
// und Elternelement von Steuerelementen, Eigenschaften als Text und der
// Formulartext samt Handlernamen (TAtlasFormText). Gemeinsam für Leiste,
// Suche, Auswahl- und Anordnen-Befehle. Nur im Hauptthread.

interface

uses
  System.Types,
  System.Classes,
  Vcl.Controls,
  ToolsAPI,
  DesignIntf;

type
  TAtlasDesignerAccess = class
  public
    class function DesignerOf(const AEditor: IOTAFormEditor): IDesigner; static;
    /// <summary>Zeigt das aktive Editorfenster einen Formular-Designer?</summary>
    class function Shown: Boolean; static;
    /// <summary>Formular im Designer des aktiven Editorfensters.</summary>
    class function Current(out AEditor: IOTAFormEditor; out ARoot: TComponent): Boolean; static;
    /// <summary>Ausgewählte Komponenten des Formulars ARoot ohne das Formular selbst.</summary>
    class function Selection(const AEditor: IOTAFormEditor; ARoot: TComponent): TArray<TComponent>; static;
    /// <summary>Setzt die Auswahl im Designer; leer wählt das Formular.</summary>
    class procedure Select(const ADesigner: IDesigner; ARoot: TComponent;
      const AComponents: TArray<TComponent>); static;
    /// <summary>Lage von AControl im Client von ARoot; leer, wenn ARoot kein Vorfahr ist.</summary>
    class function BoundsInRoot(AControl: TControl; ARoot: TWinControl): TRect; static;
    /// <summary>Name des Elternelements; '' direkt auf dem Formular.</summary>
    class function ParentNameOf(AControl: TControl; ARoot: TComponent): string; static;
    /// <summary>Wert der Eigenschaft als Text; False ohne sie oder ohne Wert.</summary>
    class function PropText(AComponent: TComponent; const AName: string; out AText: string): Boolean; static;
    /// <summary>Klasse von AComponent und ihre Vorfahren bis TComponent.</summary>
    class function ClassChain(AComponent: TComponent): TArray<string>; static;
    /// <summary>Formulartext wie beim Speichern, mit den Handlernamen des Designers.</summary>
    class function FormText(ARoot: TComponent; const ADesigner: IDesigner): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  System.Variants,
  Atlas.Core.Forms.Text,
  Atlas.IDE.Foundation.DesignerView;

class function TAtlasDesignerAccess.DesignerOf(const AEditor: IOTAFormEditor): IDesigner;
var
  mNative: INTAFormEditor;
begin
  Result := nil;
  if Supports(AEditor, INTAFormEditor, mNative) then
  begin
    Result := mNative.FormDesigner;
  end;
end;

class function TAtlasDesignerAccess.Shown: Boolean;
begin
  Result := TAtlasIdeDesignerView.CurrentFormEditor <> nil;
end;

class function TAtlasDesignerAccess.Current(out AEditor: IOTAFormEditor; out ARoot: TComponent): Boolean;
begin
  AEditor := TAtlasIdeDesignerView.CurrentFormEditor;
  ARoot := TAtlasIdeDesignerView.RootOf(AEditor);
  Result := (AEditor <> nil) and (ARoot <> nil);
end;

class function TAtlasDesignerAccess.Selection(const AEditor: IOTAFormEditor;
  ARoot: TComponent): TArray<TComponent>;
var
  mDesigner: IDesigner;
  mList: IDesignerSelections;
  mIndex: Integer;
  mItem: TPersistent;
begin
  Result := nil;
  mDesigner := DesignerOf(AEditor);
  if mDesigner = nil then
  begin
    Exit;
  end;
  mList := CreateSelectionList;
  mDesigner.GetSelections(mList);
  for mIndex := 0 to mList.Count - 1 do
  begin
    mItem := mList[mIndex];
    if (mItem is TComponent) and (mItem <> ARoot) and (TComponent(mItem).Owner = ARoot) then
    begin
      Result := Result + [TComponent(mItem)];
    end;
  end;
end;

class procedure TAtlasDesignerAccess.Select(const ADesigner: IDesigner; ARoot: TComponent;
  const AComponents: TArray<TComponent>);
var
  mList: IDesignerSelections;
  mComponent: TComponent;
begin
  if Length(AComponents) = 0 then
  begin
    ADesigner.SelectComponent(ARoot);
    Exit;
  end;
  mList := CreateSelectionList;
  for mComponent in AComponents do
  begin
    mList.Add(mComponent);
  end;
  ADesigner.SetSelections(mList);
end;

class function TAtlasDesignerAccess.BoundsInRoot(AControl: TControl; ARoot: TWinControl): TRect;
var
  mParent: TWinControl;
  mTopLeft: TPoint;
begin
  Result := TRect.Empty;
  mParent := AControl.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  mTopLeft := AControl.BoundsRect.TopLeft;
  if mParent <> ARoot then
  begin
    if not ARoot.ContainsControl(mParent) then
    begin
      Exit;
    end;
    mTopLeft := mParent.ClientToParent(mTopLeft, ARoot);
  end;
  Result := Rect(mTopLeft.X, mTopLeft.Y, mTopLeft.X + AControl.Width, mTopLeft.Y + AControl.Height);
end;

class function TAtlasDesignerAccess.ParentNameOf(AControl: TControl; ARoot: TComponent): string;
begin
  Result := '';
  if (AControl.Parent <> nil) and (AControl.Parent <> ARoot) then
  begin
    Result := AControl.Parent.Name;
  end;
end;

class function TAtlasDesignerAccess.PropText(AComponent: TComponent; const AName: string;
  out AText: string): Boolean;
var
  mInfo: PPropInfo;
  mObject: TObject;
begin
  AText := '';
  mInfo := GetPropInfo(AComponent, AName);
  if mInfo = nil then
  begin
    Exit(False);
  end;
  case mInfo^.PropType^.Kind of
    tkClass:
      begin
        mObject := GetObjectProp(AComponent, mInfo);
        if mObject is TComponent then
        begin
          AText := TComponent(mObject).Name;
        end;
      end;
    tkInteger, tkInt64, tkEnumeration, tkFloat, tkSet, tkChar, tkWChar, tkString, tkLString, tkUString, tkWString:
      AText := VarToStr(GetPropValue(AComponent, mInfo, True));
  end;
  Result := AText <> '';
end;

class function TAtlasDesignerAccess.ClassChain(AComponent: TComponent): TArray<string>;
var
  mClass: TClass;
begin
  Result := nil;
  mClass := AComponent.ClassType;
  while (mClass <> nil) and (mClass <> TPersistent) do
  begin
    Result := Result + [mClass.ClassName];
    mClass := mClass.ClassParent;
  end;
end;

class function TAtlasDesignerAccess.FormText(ARoot: TComponent; const ADesigner: IDesigner): string;
var
  mDesigner: IDesigner;
begin
  mDesigner := ADesigner;
  Result := TAtlasFormText.Write(ARoot,
    function(AMethod: TMethod): string
    begin
      Result := '';
      if mDesigner <> nil then
      begin
        Result := mDesigner.GetMethodName(AMethod);
      end;
    end);
end;

end.
