unit Atlas.Common.Rules.Builtin.FeatureCycles;

// Regel architecture-feature-cycle: kein Zyklus zwischen Features desselben
// Präfixes, keine Kante gegen eine Richtung (Auswertung in
// Atlas.Common.Architecture.FeatureCycles, Optionen dort beschrieben):
//   "rules": { "architecture-feature-cycle": { "severity": "warning",
//     "prefixes": ["Atlas.Common", "Atlas.Core"], "exclude": ["Tests/**"],
//     "known": ["Atlas.Core: Lsp, Problems"],
//     "directions": ["Atlas.Common: Lsp | Rules | Editing | Semantics | Mcp"],
//     "knownEdges": ["Atlas.Common.Rules.Engine -> Atlas.Common.Lsp.Session"] } }
//
// - Gemeldet wird am uses-Eintrag der geprüften Unit, der einen unbekannten
//   Zyklus schließt oder gegen eine Richtung verstößt. Ohne "prefixes" oder
//   ohne vollständig geladene Projekte schweigt die Regel.
// - Die Auswertung läuft über den ganzen Uses-Graphen; sie wird je Stand des
//   Graphen einmal gerechnet und von allen Dateien geteilt.
// - Veraltete Einträge in "known" und "knownEdges" gehören zu keiner Datei:
//   Sie meldet Tools/Check-PackageDependencies.ps1.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TFeatureCycleRule = class(TInterfacedObject, IRule)
  public const
    cRuleId = 'architecture-feature-cycle';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Pfad von AFileName relativ zu ARoot mit "/"; '' außerhalb von ARoot.</summary>
    class function RelativeTo(const ARoot, AFileName: string): string; static;
    /// <summary>Ordner der Konfiguration aus absolutem und relativem Pfad der geprüften Datei; '' wenn unbekannt.
    /// </summary>
    class function RootOf(const AFileName, ARelativePath: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Architecture.FeatureCycles,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TFeatureCycleText = (Title, Cycle, Direction);

const
  cTexts: array[TFeatureCycleText] of TAtlasText = (
    (De: 'uses-Eintrag schließt einen Zyklus zwischen Features oder verletzt eine Richtung';
     En: 'uses entry closes a cycle between features or violates a direction'),
    (De: '%s -> %s schließt einen Zyklus zwischen den Features %s; Kante entfernen oder Typen in das untere ' +
      'Feature verschieben';
     En: '%s -> %s closes a cycle between the features %s; remove the edge or move types to the lower feature'),
    (De: '%s darf %s nicht verwenden (Richtung "%s")'; En: '%s must not use %s (direction "%s")'));

{$SCOPEDENUMS OFF}

function Slashed(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

{ TFeatureCycleRule }

function TFeatureCycleRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cRuleId, TRuleSeverity.Warning, cTexts[TFeatureCycleText.Title].Text);
end;

class function TFeatureCycleRule.RootOf(const AFileName, ARelativePath: string): string;
var
  mFile, mRelative: string;
begin
  mFile := Slashed(AFileName);
  mRelative := Slashed(ARelativePath);
  if (mRelative = '') or (Length(mFile) <= Length(mRelative)) or
    not SameText(Copy(mFile, Length(mFile) - Length(mRelative) + 1, MaxInt), mRelative) then
  begin
    Exit('');
  end;
  Result := Copy(mFile, 1, Length(mFile) - Length(mRelative));
end;

class function TFeatureCycleRule.RelativeTo(const ARoot, AFileName: string): string;
var
  mFile: string;
begin
  mFile := Slashed(AFileName);
  if (ARoot = '') or not SameText(Copy(mFile, 1, Length(ARoot)), ARoot) then
  begin
    Exit('');
  end;
  Result := Copy(mFile, Length(ARoot) + 1, MaxInt);
end;

/// <summary>Auswertung des ganzen Graphen; je Optionen und Wurzel einmal je Stand des Graphen. Pfade werden vor dem
/// Vergleich mit ARoot vollständig (Prüfen einzelner Dateien gibt sie relativ zum aktuellen Ordner).</summary>
function Analysis(const AContext: TRuleContext; const AOptions: TFeatureCycleOptions;
  const ARoot: string): IFeatureCycles;
var
  mOptions: TFeatureCycleOptions;
  mRoot: string;
begin
  mOptions := AOptions;
  mRoot := ARoot;
  Supports(AContext.ProjectFiles.UsesDerived(TFeatureCycleRule.cRuleId + #0 + ARoot + #0 + AContext.Options,
    function(const AEdges: TArray<TRuleUsesEdge>): IInterface
    var
      Edges: TArray<TFeatureEdge>;
      Index: Integer;
    begin
      SetLength(Edges, Length(AEdges));
      for Index := 0 to High(AEdges) do
      begin
        Edges[Index] := TFeatureEdge.Create(AEdges[Index].SourceUnit,
          TFeatureCycleRule.RelativeTo(mRoot, ExpandFileName(AEdges[Index].SourceFileName)), AEdges[Index].TargetUnit,
          TFeatureCycleRule.RelativeTo(mRoot, ExpandFileName(AEdges[Index].TargetFileName)));
      end;
      Result := TFeatureCycles.Analyze(mOptions, Edges);
    end), IFeatureCycles, Result);
end;

function Excluded(const AOptions: TFeatureCycleOptions; const ARelativePath: string): Boolean;
var
  mPattern: string;
begin
  for mPattern in AOptions.Exclude do
  begin
    if (ARelativePath <> '') and MatchesGlob(mPattern, ARelativePath) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TFeatureCycleRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mOptions: TFeatureCycleOptions;
  mAnalysis: IFeatureCycles;
  mOwnName, mPrefix, mFeature, mDetail, mReason: string;
  mUsed: TUsesReference;
  mVerdict: TFeatureVerdict;
begin
  if (AContext.Tree = nil) or (AContext.ProjectFiles = nil) then
  begin
    Exit;
  end;
  mOptions := TFeatureCycleOptions.Parse(AContext.Options);
  if (mOptions.Prefixes = nil) or Excluded(mOptions, Slashed(AContext.RelativePath)) or
    TUsesClauses.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Exit;
  end;
  mOwnName := TUsesClauses.OwnName(AContext.Tree.Tokens);
  if mOwnName = '' then
  begin
    mOwnName := AContext.UnitName;
  end;
  if not TFeatureCycles.FeatureOf(mOwnName, mOptions.Prefixes, mPrefix, mFeature) or
    not AContext.ProjectFiles.Complete(mReason) then
  begin
    Exit;
  end;
  mAnalysis := Analysis(AContext, mOptions, RootOf(ExpandFileName(AContext.FileName), AContext.RelativePath));
  if mAnalysis = nil then
  begin
    Exit;
  end;
  for mUsed in TUsesClauses.References(AContext.Tree.Tokens) do
  begin
    if mUsed.List = TUsesListKind.ContainsList then
    begin
      Continue;
    end;
    mVerdict := mAnalysis.Verdict(mOwnName, mUsed.Name, mDetail);
    if mVerdict = TFeatureVerdict.Cycle then
    begin
      AReport.Add(mUsed.Range, cTexts[TFeatureCycleText.Cycle].Fmt([mOwnName, mUsed.Name, mDetail]));
    end
    else if mVerdict = TFeatureVerdict.Direction then
    begin
      AReport.Add(mUsed.Range, cTexts[TFeatureCycleText.Direction].Fmt([mOwnName, mUsed.Name, mDetail]));
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.FeatureCycles', cTexts);

end.
