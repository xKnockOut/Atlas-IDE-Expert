unit Atlas.IDE.Outline.CrumbCard;

// Kennzahlen-Karte der Brotkrumenleiste (#1787): baut aus Gliederung, Zeilen
// und Metriken der Datei die Karte (TAtlasCrumbCards) und zeigt sie als
// Tooltip (TAtlasCrumbCardTip). Die Metriken kommen über einen Haken aus dem
// Abruf von Base; die Karte fragt nichts selbst. Abgetrennt vom Stand der
// Brotkrumen (TBreadcrumbsState). Nur im Hauptthread.

interface

uses
  System.Types,
  Atlas.Core.Editor.Metrics,
  Atlas.IDE.Outline.CrumbLists,
  Atlas.UI.Popup.CrumbCard;

type
  /// <summary>Letzte Metriken der Datei AFileName; False ohne.</summary>
  TAtlasCrumbMetricsFunc = reference to function(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean;

  TAtlasIdeCrumbCard = class
  private
    /// <summary>Tooltip der Karte; erst beim ersten Zeigen angelegt.</summary>
    FTip: TAtlasCrumbCardTip;
  public
    destructor Destroy; override;
    /// <summary>Hat der Knoten ANode der Gliederung aus ASource eine Karte (Methode, Routine, Typ)?</summary>
    class function HasCard(const ASource: TAtlasCrumbSource; ANode: Integer): Boolean; static;
    /// <summary>Karte für ANode an APoint (Bildschirm); ohne Metriken (AMetrics fehlt oder liefert False) nur die
    /// Kopfzeile.</summary>
    procedure Show(const ASource: TAtlasCrumbSource; ANode: Integer; const AMetrics: TAtlasCrumbMetricsFunc;
      const APoint: TPoint);
    procedure Hide;
  end;

implementation

uses
  Atlas.Core.Editor.CrumbCard,
  Atlas.IDE.Foundation.EditorStyle;

{ TAtlasIdeCrumbCard }

destructor TAtlasIdeCrumbCard.Destroy;
begin
  FTip.Free;
  inherited Destroy;
end;

class function TAtlasIdeCrumbCard.HasCard(const ASource: TAtlasCrumbSource; ANode: Integer): Boolean;
begin
  Result := TAtlasCrumbCards.HasCard(ASource.Nodes, ANode);
end;

procedure TAtlasIdeCrumbCard.Show(const ASource: TAtlasCrumbSource; ANode: Integer;
  const AMetrics: TAtlasCrumbMetricsFunc; const APoint: TPoint);
var
  mMetrics: TAtlasFileMetrics;
  mHasMetrics: Boolean;
begin
  mMetrics := Default(TAtlasFileMetrics);
  mHasMetrics := Assigned(AMetrics) and AMetrics(ASource.FileName, mMetrics);
  if FTip = nil then
  begin
    FTip := TAtlasCrumbCardTip.Create(nil);
  end;
  FTip.Colors := TAtlasIdeStyle.Colors;
  FTip.ShowCard(TAtlasCrumbCards.Build(ASource.Nodes, ASource.Lines, ANode, mHasMetrics, mMetrics), APoint);
end;

procedure TAtlasIdeCrumbCard.Hide;
begin
  // HidePopup tut bei verdeckter Karte nichts.
  if FTip <> nil then
  begin
    FTip.HidePopup;
  end;
end;

end.
