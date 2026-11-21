unit Atlas.UI.Tracker.TileView;

// Grundlage der Kacheln des Trackers auf der Willkommensseite (#1455): ein
// Panel, das die Seite in die Inhaltsfläche ihres Bereichsrahmens legt.
// Titelzeile, Griff und Spalte gehören der Seite; die Kachel zeichnet nur
// ihren Inhalt, nennt ihre Höhe (BodyHeight) und meldet Änderungen der Höhe
// über OnHeightChanged. Den Vertrag Atlas.IDE.Contracts.WelcomeTiles setzt
// Atlas.IDE.Tracker.Adapters.Tiles darauf um (UI kennt Atlas.IDE nicht). Ohne Fenster
// misst sie keinen Text und holt UpdateContent in CreateWnd nach.

interface

uses
  System.Classes,
  Vcl.Controls,
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Foundation.Contract;

type
  TAtlasTrackerTileView = class(TCustomPanel)
  public const
    /// <summary>Höhe ohne eigene Angabe (logische Pixel).</summary>
    cDefaultBodyHeight = 120;
  private
    FOnHeightChanged: TProc;
    FPendingUpdate: Boolean;
  protected
    procedure CreateWnd; override;
    /// <summary>Der Inhalt braucht eine andere Höhe: meldet OnHeightChanged.</summary>
    procedure HeightChanged;
    /// <summary>Neue Quelle ASource: Inhalt neu (UpdateContent), dann ASource.Shown, wenn gesetzt.</summary>
    procedure SourceChanged(const ASource: IAtlasShownSource);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Hängt die Ansicht an einem Fenster? Vorher kein Messen von Text („kein übergeordnetes Fenster“);
    /// ohne Fenster holt CreateWnd das UpdateContent nach.</summary>
    function HasWindow: Boolean;
    /// <summary>Höhe des Inhalts in Pixeln bei der aktuellen Skalierung.</summary>
    function BodyHeight: Integer; virtual;
    /// <summary>Inhalt neu lesen und zeichnen.</summary>
    procedure UpdateContent; virtual;
    /// <summary>Die Seite ordnet daraufhin die Spalten neu; nil in Tests.</summary>
    property OnHeightChanged: TProc read FOnHeightChanged write FOnHeightChanged;
  end;

implementation

uses
  Atlas.Core.Foundation.Calls,
  Atlas.UI.Foundation.Controls;

{ TAtlasTrackerTileView }

constructor TAtlasTrackerTileView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ShowCaption := False;
  ParentBackground := True;
end;

procedure TAtlasTrackerTileView.CreateWnd;
begin
  inherited CreateWnd;
  if FPendingUpdate then
  begin
    FPendingUpdate := False;
    UpdateContent;
  end;
end;

procedure TAtlasTrackerTileView.HeightChanged;
begin
  if Assigned(FOnHeightChanged) then
  begin
    FOnHeightChanged();
  end;
end;

function TAtlasTrackerTileView.HasWindow: Boolean;
begin
  Result := TAtlasControls.WindowOrPending(Self, FPendingUpdate);
end;

function TAtlasTrackerTileView.BodyHeight: Integer;
begin
  Result := cDefaultBodyHeight;
end;

procedure TAtlasTrackerTileView.UpdateContent;
begin
  Invalidate;
end;

procedure TAtlasTrackerTileView.SourceChanged(const ASource: IAtlasShownSource);
begin
  TAtlasCalls.ShowSource(ASource, UpdateContent);
end;

end.
