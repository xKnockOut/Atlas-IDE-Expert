unit Atlas.IDE.Designer.Surface;

// IAtlasDesignSurface über den Formular-Designer der IDE: IDesigner für
// Formular, Anlegen und Handler, der Formular-Editor (IOTAFormEditor) für
// das Löschen samt Feld in der Klasse. Dazu der Designer des aktiven
// Editorfensters als Surface (Active). Nur im Hauptthread.

interface

uses
  System.Classes,
  System.TypInfo,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Designer.Surface;

type
  TAtlasIdeDesignSurface = class(TInterfacedObject, IAtlasDesignSurface)
  private
    FDesigner: IDesigner;
    FEditor: IOTAFormEditor;
    /// <summary>Formular-Editor zum Formular dieses Designers; nil, wenn er nicht im aktiven Fenster steht.</summary>
    function Editor: IOTAFormEditor;
  public
    /// <summary>AEditor darf nil sein: Dann sucht Delete den Editor im aktiven Fenster.</summary>
    constructor Create(const ADesigner: IDesigner; const AEditor: IOTAFormEditor);
    /// <summary>Surface zu ADesigner aus einer Benachrichtigung; nil ohne Designer.</summary>
    class function Wrap(const ADesigner: IDesigner): IAtlasDesignSurface; static;
    /// <summary>Designer des aktiven Editorfensters; nil ohne Formular.</summary>
    class function Active: IAtlasDesignSurface; static;
    function Root: TComponent;
    procedure Modified;
    function DeleteComponent(const AKey: string): Boolean;
    function CreateComponent(AClass: TComponentClass; AParent: TComponent): TComponent;
    function MethodExists(const AName: string): Boolean;
    function CreateMethod(const AName: string; ATypeData: PTypeData): TMethod;
    function MethodName(const AMethod: TMethod): string;
  end;

implementation

uses
  Atlas.IDE.Foundation.DesignerView,
  Atlas.IDE.Designer.Access;

{ TAtlasIdeDesignSurface }

constructor TAtlasIdeDesignSurface.Create(const ADesigner: IDesigner; const AEditor: IOTAFormEditor);
begin
  inherited Create;
  FDesigner := ADesigner;
  FEditor := AEditor;
end;

class function TAtlasIdeDesignSurface.Wrap(const ADesigner: IDesigner): IAtlasDesignSurface;
begin
  Result := nil;
  if ADesigner <> nil then
  begin
    Result := TAtlasIdeDesignSurface.Create(ADesigner, nil);
  end;
end;

class function TAtlasIdeDesignSurface.Active: IAtlasDesignSurface;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
begin
  Result := nil;
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if mDesigner <> nil then
  begin
    Result := TAtlasIdeDesignSurface.Create(mDesigner, mEditor);
  end;
end;

function TAtlasIdeDesignSurface.Editor: IOTAFormEditor;
begin
  Result := FEditor;
  if Result = nil then
  begin
    Result := TAtlasIdeDesignerView.CurrentFormEditor;
    if (Result <> nil) and (TAtlasIdeDesignerView.RootOf(Result) <> Root) then
    begin
      Result := nil;
    end;
  end;
end;

function TAtlasIdeDesignSurface.Root: TComponent;
begin
  Result := FDesigner.Root;
end;

procedure TAtlasIdeDesignSurface.Modified;
begin
  FDesigner.Modified;
end;

function TAtlasIdeDesignSurface.DeleteComponent(const AKey: string): Boolean;
var
  mEditor: IOTAFormEditor;
  mComponent: IOTAComponent;
begin
  mEditor := Editor;
  Result := False;
  if mEditor <> nil then
  begin
    mComponent := mEditor.FindComponent(AKey);
    Result := (mComponent <> nil) and mComponent.Delete;
  end;
end;

function TAtlasIdeDesignSurface.CreateComponent(AClass: TComponentClass; AParent: TComponent): TComponent;
begin
  Result := FDesigner.CreateComponent(AClass, AParent, 0, 0, 0, 0);
end;

function TAtlasIdeDesignSurface.MethodExists(const AName: string): Boolean;
begin
  Result := FDesigner.MethodExists(AName);
end;

function TAtlasIdeDesignSurface.CreateMethod(const AName: string; ATypeData: PTypeData): TMethod;
begin
  Result := FDesigner.CreateMethod(AName, ATypeData);
end;

function TAtlasIdeDesignSurface.MethodName(const AMethod: TMethod): string;
begin
  Result := FDesigner.GetMethodName(AMethod);
end;

end.
