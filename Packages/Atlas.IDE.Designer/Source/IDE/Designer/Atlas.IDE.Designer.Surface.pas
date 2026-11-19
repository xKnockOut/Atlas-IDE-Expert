unit Atlas.IDE.Designer.Surface;

// Surface des Formular-Designers für die Werkzeuge des Moduls: zu einem
// IDesigner aus einer Benachrichtigung (Wrap), zum Designer des aktiven
// Editorfensters (Active) oder zu Designer und Formular-Editor (Make). Die
// Surface selbst (Atlas.IDE.Designer.Adapters.Surface) erzeugt die Fabrik, die
// die Komposition des Moduls mit Use setzt; ohne Fabrik gibt es keine Surface
// (nil), wie ohne Designer. Nur im Hauptthread.

interface

uses
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Designer.Contract;

type
  /// <summary>Surface zu ADesigner; AEditor darf nil sein (dann sucht das Löschen den Editor im aktiven Fenster).
  /// </summary>
  TAtlasIdeDesignSurfaceFactory = reference to function(const ADesigner: IDesigner;
    const AEditor: IOTAFormEditor): IAtlasDesignSurface;

  TAtlasIdeDesignSurfaces = class
  private class var
    FFactory: TAtlasIdeDesignSurfaceFactory;
  public
    /// <summary>Fabrik der Surface setzen; nil beim Abmelden des Moduls.</summary>
    class procedure Use(const AFactory: TAtlasIdeDesignSurfaceFactory); static;
    /// <summary>Surface zu ADesigner und AEditor (AEditor darf nil sein); nil ohne Designer oder Fabrik.</summary>
    class function Make(const ADesigner: IDesigner; const AEditor: IOTAFormEditor): IAtlasDesignSurface; static;
    /// <summary>Surface zu ADesigner aus einer Benachrichtigung; nil ohne Designer.</summary>
    class function Wrap(const ADesigner: IDesigner): IAtlasDesignSurface; static;
    /// <summary>Designer des aktiven Editorfensters; nil ohne Formular.</summary>
    class function Active: IAtlasDesignSurface; static;
  end;

implementation

uses
  System.Classes,
  Atlas.IDE.Designer.Access;

{ TAtlasIdeDesignSurfaces }

class procedure TAtlasIdeDesignSurfaces.Use(const AFactory: TAtlasIdeDesignSurfaceFactory);
begin
  FFactory := AFactory;
end;

class function TAtlasIdeDesignSurfaces.Make(const ADesigner: IDesigner;
  const AEditor: IOTAFormEditor): IAtlasDesignSurface;
begin
  Result := nil;
  if (ADesigner <> nil) and Assigned(FFactory) then
  begin
    Result := FFactory(ADesigner, AEditor);
  end;
end;

class function TAtlasIdeDesignSurfaces.Wrap(const ADesigner: IDesigner): IAtlasDesignSurface;
begin
  Result := Make(ADesigner, nil);
end;

class function TAtlasIdeDesignSurfaces.Active: IAtlasDesignSurface;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := nil;
  if TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Result := Make(TAtlasDesignerAccess.DesignerOf(mEditor), mEditor);
  end;
end;

end.
