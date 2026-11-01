unit Atlas.UI.Tracker.TileView;

// Grundlage der Kacheln des Trackers auf der Willkommensseite (#1455,
// Vertrag Atlas.IDE.Contracts.WelcomeTiles): ein Panel, das die Seite in die
// Inhaltsfläche ihres Bereichsrahmens legt. Titelzeile, Griff und Spalte
// gehören der Seite; die Kachel zeichnet nur ihren Inhalt, nennt ihre Höhe
// (BodyHeight) und meldet Änderungen der Höhe über den Host. Ohne Fenster
// misst sie keinen Text und holt UpdateContent in CreateWnd nach. Als
// Steuerelement zählt die Ansicht keine Referenzen; ihr Besitzer gibt sie frei.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.IDE.Contracts.WelcomeTiles;

type
  TAtlasTrackerTileView = class(TCustomPanel, IAtlasWelcomeTileView)
  public const
    /// <summary>Höhe ohne eigene Angabe (logische Pixel).</summary>
    DefaultBodyHeight = 120;
  private
    FHost: IAtlasWelcomeTileHost;
    FPendingUpdate: Boolean;
  protected
    procedure CreateWnd; override;
    /// <summary>Der Inhalt braucht eine andere Höhe: die Seite ordnet die Spalten neu.</summary>
    procedure HeightChanged;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Hängt die Ansicht an einem Fenster? Vorher kein Messen von Text („kein übergeordnetes Fenster“);
    /// ohne Fenster holt CreateWnd das UpdateContent nach.</summary>
    function HasWindow: Boolean;
    { IAtlasWelcomeTileView }
    function Control: TWinControl;
    function BodyHeight: Integer; virtual;
    procedure UpdateContent; virtual;
    /// <summary>Gibt die Seite mit; nil in Tests und nach dem Abmelden.</summary>
    property Host: IAtlasWelcomeTileHost read FHost write FHost;
  end;

implementation

uses
  Vcl.Forms;

{ TAtlasTrackerTileView }

constructor TAtlasTrackerTileView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ShowCaption := False;
  ParentBackground := True;
end;

function TAtlasTrackerTileView.Control: TWinControl;
begin
  Result := Self;
end;

function TAtlasTrackerTileView.BodyHeight: Integer;
begin
  Result := DefaultBodyHeight;
end;

procedure TAtlasTrackerTileView.UpdateContent;
begin
  Invalidate;
end;

procedure TAtlasTrackerTileView.HeightChanged;
begin
  if FHost <> nil then
  begin
    FHost.HeightChanged;
  end;
end;

function TAtlasTrackerTileView.HasWindow: Boolean;
var
  mControl: TWinControl;
begin
  mControl := Self;
  while mControl <> nil do
  begin
    if mControl.HandleAllocated or (mControl.ParentWindow <> 0) or (mControl is TCustomForm) then
    begin
      Exit(True);
    end;
    mControl := mControl.Parent;
  end;
  FPendingUpdate := True;
  Result := False;
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

end.
