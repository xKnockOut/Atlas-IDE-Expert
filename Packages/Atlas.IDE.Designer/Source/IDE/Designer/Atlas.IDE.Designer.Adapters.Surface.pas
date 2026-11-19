unit Atlas.IDE.Designer.Adapters.Surface;

// IAtlasDesignSurface (Atlas.Core.Designer.Contract) über den Formular-Designer
// der IDE: IDesigner für Formular, Anlegen und Handler, der Formular-Editor
// (IOTAFormEditor) für das Löschen samt Feld in der Klasse. Erzeugt nur die
// Komposition des Moduls; die Werkzeuge holen die Surface über
// TAtlasIdeDesignSurfaces (Atlas.IDE.Designer.Surface). Nur im Hauptthread.

interface

uses
  System.Classes,
  System.TypInfo,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Designer.Contract;

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
  Atlas.IDE.Foundation.DesignerView;

{ TAtlasIdeDesignSurface }

constructor TAtlasIdeDesignSurface.Create(const ADesigner: IDesigner; const AEditor: IOTAFormEditor);
begin
  inherited Create;
  FDesigner := ADesigner;
  FEditor := AEditor;
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
