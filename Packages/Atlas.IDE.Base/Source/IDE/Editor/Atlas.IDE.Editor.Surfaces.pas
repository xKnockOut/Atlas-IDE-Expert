unit Atlas.IDE.Editor.Surfaces;

// Ansicht der IDE als IAtlasEditSurface (Atlas.Core.Editor.EditSurface) für verknüpftes Bearbeiten und
// Mehrfachcursor. Den Adapter (Atlas.IDE.Editor.Adapters.EditSurface) setzt die Kompositionswurzel ein. Nur im
// Hauptthread.

interface

uses
  ToolsAPI,
  Atlas.Plugin.Editor.Contract;

type
  /// <summary>Puffer der Ansicht AView (AView und ihr Puffer nicht nil).</summary>
  TAtlasEditSurfaceFactory = reference to function(const AView: IOTAEditView): IAtlasEditSurface;

  TAtlasIdeEditSurfaces = class
  private class var
    FFactory: TAtlasEditSurfaceFactory;
  public
    /// <summary>Puffer der Ansicht AView; nil ohne Ansicht, Puffer oder Fabrik.</summary>
    class function Wrap(const AView: IOTAEditView): IAtlasEditSurface; static;
    /// <summary>Legt den Adapter an; setzt die Kompositionswurzel.</summary>
    class property Factory: TAtlasEditSurfaceFactory read FFactory write FFactory;
  end;

implementation

{ TAtlasIdeEditSurfaces }

class function TAtlasIdeEditSurfaces.Wrap(const AView: IOTAEditView): IAtlasEditSurface;
begin
  Result := nil;
  if Assigned(FFactory) and (AView <> nil) and (AView.Buffer <> nil) then
  begin
    Result := FFactory(AView);
  end;
end;

end.
