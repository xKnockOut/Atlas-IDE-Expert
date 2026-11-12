unit Atlas.Core.Editor.CrumbCard;

// Kennzahlen-Karte an Methoden- und Typgliedern der Brotkrumenleiste (#1787),
// Kern ohne VCL und OTA:
// - Quelle sind dieselben Metriken wie Metrik-Linse und Statusleiste
//   (atlas.server.metrics, TAtlasFileMetrics); hier wird nichts gerechnet.
// - Methoden: Kopfzeile wie „Mit Signatur kopieren“ (TAtlasCrumbMenu), dazu
//   Zeilen, zyklomatische Komplexität, Verschachtelungstiefe und
//   Parameterzahl des Rumpfs (die Metriken stehen am Namen im Rumpf).
// - Typen: Kopfzeile der Deklaration, dazu Mitglieder und Vererbungstiefe aus
//   den Kennzahlen des Aufbaus und die Zeilen der Deklaration aus der
//   Gliederung.
// - Jede Zeile trägt ihre Grenze aus atlas.json; Over sagt, ob der Wert
//   darüber liegt. Fehlen die Metriken (Modul aus, Server indiziert noch,
//   Rumpf nicht gefunden), bleibt nur die Kopfzeile, Available ist False.

interface

uses
  Atlas.Core.Editor.Metrics,
  Atlas.Core.Outline.Model;

type
{$SCOPEDENUMS ON}
  TAtlasCardMetric = (Lines, Cyclomatic, Nesting, Parameters, Members, InheritanceDepth);
{$SCOPEDENUMS OFF}

  TAtlasCardRow = record
    Metric: TAtlasCardMetric;
    Value: Integer;
    /// <summary>Grenze aus atlas.json; MaxInt = keine.</summary>
    Limit: Integer;
    /// <summary>Value ist nur eine Untergrenze (Vererbungstiefe bei abgebrochener Kette).</summary>
    AtLeast: Boolean;
    function Over: Boolean;
    /// <summary>Wert als Text: „86“ bzw. „≥ 5“.</summary>
    function ValueText: string;
  end;

  TAtlasCrumbCard = record
    Title: string;
    Rows: TArray<TAtlasCardRow>;
    /// <summary>Kennzahlen gefunden; sonst nur die Kopfzeile.</summary>
    Available: Boolean;
  end;

  TAtlasCrumbCards = class
  public
    /// <summary>Hat der Knoten eine Karte (Methode, Routine, Typ)?</summary>
    class function HasCard(const ANodes: TAtlasOutlineNodes; ANode: Integer): Boolean; static;
    /// <summary>Karte für den Knoten ANode; AHasMetrics: AMetrics gehört zur Datei.</summary>
    class function Build(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ANode: Integer;
      AHasMetrics: Boolean; const AMetrics: TAtlasFileMetrics): TAtlasCrumbCard; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.CrumbMenu;

const
  cMethodMetrics: array[0..3] of TAtlasMetric = (TAtlasMetric.MethodLength, TAtlasMetric.Cyclomatic,
    TAtlasMetric.Nesting, TAtlasMetric.Parameters);
  cMethodRows: array[0..3] of TAtlasCardMetric = (TAtlasCardMetric.Lines, TAtlasCardMetric.Cyclomatic,
    TAtlasCardMetric.Nesting, TAtlasCardMetric.Parameters);

{ TAtlasCardRow }

function TAtlasCardRow.Over: Boolean;
begin
  Result := (Limit <> MaxInt) and (Value > Limit);
end;

function TAtlasCardRow.ValueText: string;
begin
  Result := IntToStr(Value);
  if AtLeast then
  begin
    Result := '≥ ' + Result;
  end;
end;

function Row(AMetric: TAtlasCardMetric; AValue, ALimit: Integer; AAtLeast: Boolean): TAtlasCardRow;
begin
  Result.Metric := AMetric;
  Result.Value := AValue;
  Result.Limit := ALimit;
  Result.AtLeast := AAtLeast;
end;

function IsRoutine(const ANode: TAtlasOutlineNode): Boolean;
begin
  Result := ANode.Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine];
end;

{ TAtlasCrumbCards }

class function TAtlasCrumbCards.HasCard(const ANodes: TAtlasOutlineNodes; ANode: Integer): Boolean;
begin
  Result := (ANode >= 0) and (ANode <= High(ANodes)) and (IsRoutine(ANodes[ANode]) or
    (ANodes[ANode].Category = TAtlasOutlineCategory.TypeDecl));
end;

procedure MethodCard(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ANode: Integer;
  AHasMetrics: Boolean; const AMetrics: TAtlasFileMetrics; var ACard: TAtlasCrumbCard);
var
  mBody, mIndex, mRow: Integer;
begin
  ACard.Title := TAtlasCrumbMenu.SignatureOf(ANodes, ALines, ANode);
  if ACard.Title = '' then
  begin
    ACard.Title := TAtlasBreadcrumbs.QualifiedName(ANodes, ANode);
  end;
  // Die Metriken stehen am Namen im Rumpf.
  mBody := TAtlasBreadcrumbs.Target(ANodes, ANode, True);
  if not AHasMetrics or (mBody < 0) then
  begin
    Exit;
  end;
  mIndex := AMetrics.IndexAt(ANodes[mBody].NameLine);
  if mIndex < 0 then
  begin
    Exit;
  end;
  ACard.Available := True;
  for mRow := 0 to High(cMethodRows) do
  begin
    ACard.Rows := ACard.Rows + [Row(cMethodRows[mRow], AMetrics.Methods[mIndex].Values[cMethodMetrics[mRow]],
      AMetrics.Limits[cMethodMetrics[mRow]], False)];
  end;
end;

procedure TypeCard(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ANode: Integer;
  AHasMetrics: Boolean; const AMetrics: TAtlasFileMetrics; var ACard: TAtlasCrumbCard);
var
  mNode: TAtlasOutlineNode;
  mItem: TAtlasStructureItem;
begin
  mNode := ANodes[ANode];
  ACard.Title := mNode.Name;
  if (mNode.NameLine >= 0) and (mNode.NameLine <= High(ALines)) then
  begin
    ACard.Title := Trim(ALines[mNode.NameLine]);
  end;
  if not AHasMetrics then
  begin
    Exit;
  end;
  for mItem in AMetrics.StructuresAt(mNode.NameLine) do
  begin
    case mItem.Kind of
      TAtlasStructureMetric.ClassSize:
        ACard.Rows := ACard.Rows + [Row(TAtlasCardMetric.Members, mItem.Value, mItem.Limit, False)];
      TAtlasStructureMetric.InheritanceDepth:
        ACard.Rows := ACard.Rows + [Row(TAtlasCardMetric.InheritanceDepth, mItem.Value, mItem.Limit,
          mItem.AtLeast)];
      TAtlasStructureMetric.UnitLength, TAtlasStructureMetric.UsesCount:
        // Gehören zur Unit, nicht zum Typ.
        ;
    end;
  end;
  ACard.Available := Length(ACard.Rows) > 0;
  if ACard.Available then
  begin
    // Zeilen der Deklaration aus der Gliederung, ohne Grenze.
    ACard.Rows := [Row(TAtlasCardMetric.Lines, mNode.EndLine - mNode.StartLine + 1, MaxInt, False)] + ACard.Rows;
  end;
end;

class function TAtlasCrumbCards.Build(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ANode: Integer; AHasMetrics: Boolean; const AMetrics: TAtlasFileMetrics): TAtlasCrumbCard;
begin
  Result := Default(TAtlasCrumbCard);
  if not HasCard(ANodes, ANode) then
  begin
    Exit;
  end;
  if IsRoutine(ANodes[ANode]) then
  begin
    MethodCard(ANodes, ALines, ANode, AHasMetrics, AMetrics, Result);
  end
  else
  begin
    TypeCard(ANodes, ALines, ANode, AHasMetrics, AMetrics, Result);
  end;
end;

end.
