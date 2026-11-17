unit Atlas.IDE.Foundation.EditorBarPlacement;

// Wo die Leisten eines Leisten-Hosts stehen (#1248, #1442). Abgetrennt vom
// Host (TAtlasEditorBarHost), der die Leisten anlegt, beobachtet, freigibt und
// absichert; hier steht nur der Platz einer Leiste:
// - Einordnen: neben dem Editor-Bereich (DockTop bzw. DockBottom über
//   TAtlasIdeEditorBarDock), sonst über den Haken Place des Dienstes.
// - Ansicht (ShowIn): nur im Code-Editor, nur im Formular-Designer oder in
//   beiden (Vorgabe); Apply blendet eine Leiste danach ein und aus
//   (TAtlasIdeDesignerView). Bei Any gehört die Sichtbarkeit dem Dienst
//   (Suchleiste schließt sich selbst); nur die Sicherung des Hosts blendet aus.
// Nur im Hauptthread.

interface

uses
  Vcl.Controls,
  Atlas.Core.Editor.BarDock;

type
{$SCOPEDENUMS ON}
  /// <summary>Wo eine Leiste steht: im Code-Editor, im Formular-Designer oder in beiden (Vorgabe).</summary>
  TAtlasEditorBarView = (Any, Code, Designer);
{$SCOPEDENUMS OFF}

  TAtlasEditorBarPlacement = class
  public type
    /// <summary>Leiste einordnen (Parent, Align, Reihenfolge); beim Anlegen und bei jedem Ensure.</summary>
    TPlaceBar = reference to procedure(ABar: TControl; AEditorParent: TWinControl);
  private
    FPlace: TPlaceBar;
    FShowIn: TAtlasEditorBarView;
    /// <summary>Platz neben dem Editor-Bereich (DockTop, DockBottom); None = über Place.</summary>
    FDock: TAtlasBarDockPlace;
  public
    /// <summary>APlace darf nil sein, wenn DockTop bzw. DockBottom einordnen.</summary>
    constructor Create(const APlace: TPlaceBar);
    destructor Destroy; override;
    /// <summary>Leisten oben neben dem Editor-Bereich einhängen statt über Place, direkt am Editor.</summary>
    procedure DockTop;
    /// <summary>Leisten unten neben dem Editor-Bereich einhängen statt über Place; AOrder: kleiner = näher am
    /// Editor (TAtlasBarDock.cOrderNearest; Statusleiste TAtlasBarDock.cOrderStatusBar).</summary>
    procedure DockBottom(AOrder: Integer);
    /// <summary>Leiste einordnen: neben dem Editor-Bereich (DockTop, DockBottom), sonst über den Haken Place.
    /// </summary>
    procedure Place(ABar: TControl; AEditorParent: TWinControl);
    /// <summary>Soll eine Leiste im Editorfenster von AEditorParent gerade zu sehen sein? AHidden: vom Host
    /// wegen der Sicherung ausgeblendet.</summary>
    function Wanted(AEditorParent: TWinControl; AHidden: Boolean): Boolean;
    /// <summary>Leiste nach der Ansicht ein- bzw. ausblenden; bei Any unverändert.</summary>
    procedure Apply(ABar: TControl; AEditorParent: TWinControl; AHidden: Boolean);
    /// <summary>Wo die Leisten stehen (#1442); Vorgabe Any. Gilt ab dem nächsten Ensure des Hosts.</summary>
    property ShowIn: TAtlasEditorBarView read FShowIn write FShowIn;
  end;

implementation

uses
  Atlas.UI.Editor.Bar,
  Atlas.IDE.Foundation.EditorBarDock,
  Atlas.IDE.Foundation.EditorWindows,
  Atlas.IDE.Foundation.DesignerView;

{ TAtlasEditorBarPlacement }

constructor TAtlasEditorBarPlacement.Create(const APlace: TPlaceBar);
begin
  inherited Create;
  FPlace := APlace;
  FDock := TAtlasBarDockPlace.None;
end;

destructor TAtlasEditorBarPlacement.Destroy;
begin
  // Gefangene Variablen des Dienstes nicht über das Ende des Hosts halten.
  FPlace := nil;
  inherited Destroy;
end;

procedure TAtlasEditorBarPlacement.DockTop;
begin
  FDock := TAtlasBarDockPlace.Create(TAtlasBarSide.Top, TAtlasBarDock.cOrderNearest);
end;

procedure TAtlasEditorBarPlacement.DockBottom(AOrder: Integer);
begin
  FDock := TAtlasBarDockPlace.Create(TAtlasBarSide.Bottom, AOrder);
end;

procedure TAtlasEditorBarPlacement.Place(ABar: TControl; AEditorParent: TWinControl);
begin
  if FDock.Docked and (ABar is TAtlasEditorBar) then
  begin
    TAtlasEditorBar(ABar).DockOrder := FDock.Order;
    TAtlasIdeEditorBarDock.Place(TAtlasEditorBar(ABar), AEditorParent, FDock.Side);
  end
  else if Assigned(FPlace) then
  begin
    FPlace(ABar, AEditorParent);
  end;
end;

function TAtlasEditorBarPlacement.Wanted(AEditorParent: TWinControl; AHidden: Boolean): Boolean;
begin
  Result := not AHidden;
  if not Result then
  begin
    Exit;
  end;
  case FShowIn of
    TAtlasEditorBarView.Code:
      // Nicht im Designer und nicht auf der Willkommensseite (#1442).
      Result := TAtlasIdeDesignerView.CodeShown(TAtlasIdeEditorWindows.EditorIn(AEditorParent)) and
        not TAtlasIdeDesignerView.Shown(AEditorParent);
    TAtlasEditorBarView.Designer:
      Result := TAtlasIdeDesignerView.Shown(AEditorParent);
  else
    // Any: in Code und Designer.
  end;
end;

procedure TAtlasEditorBarPlacement.Apply(ABar: TControl; AEditorParent: TWinControl; AHidden: Boolean);
var
  mWanted: Boolean;
begin
  // Any: Die Sichtbarkeit gehört dem Dienst (Suchleiste schließt sich selbst); nur die Sicherung blendet aus.
  if FShowIn = TAtlasEditorBarView.Any then
  begin
    Exit;
  end;
  mWanted := Wanted(AEditorParent, AHidden);
  if ABar.Visible <> mWanted then
  begin
    ABar.Visible := mWanted;
  end;
end;

end.
