unit Atlas.Common.Architecture.Report;

// Architekturübersicht (#1118) als Markdown, JSON, HTML-Seite und kompakter
// Text für das MCP-Werkzeug get_architecture. Alle Ausgaben lesen dieselbe
// TArchitectureOverview; Pfade relativ zu ihrem Root, Zeilen und Spalten
// ab 1.
//
// JSON (Format 1; Nummern beziehen sich auf "units" bzw. "subsystems"):
//   {"format": 1, "title": "Projekt", "created": "2026-10-23T10:00:00",
//    "generation": 7, "durationMs": 12, "scope": "projectGroup",
//    "includeLibrary": false,
//    "grouping": {"resolution": 1, "maxShare": 0.25, "minCohesion": 0.3,
//                 "foundations": "separate"},
//    "excludes": ["Tests/**"],
//    "summary": {"units": 3, "edges": 2, "subsystems": 1, "cycles": 0,
//                "interfaceCycles": 0, "crossLinks": 0, "outliers": 0},
//    "units": [{"name": "A", "file": "Source/A.pas", "subsystem": 0,
//               "direct": 1, "total": 2, "uses": 0, "role": "foundation",
//               "library": false, "x": 0, "y": 0,
//               "assignment": [[0, 3, 2], [1, 2, 2], [2, 1, 0, 0]],
//               "close": 3}],
//    ("assignment" und "explanation" nur mit architecture.explainAssignment,
//     #1368: je Teilsystem [Nummer, interface-Kanten, implementation-Kanten],
//     nach gewichteter Summe absteigend; vierte Stelle 0 = zählt nicht, Kanten
//     zum Fundament. "close" nur bei knapper Zuordnung: fehlende gewichtete
//     Kanten zum Wechsel.)
//    "explanation": "Atlas bildet die Teilsysteme …",
//    "aligned": {"source": "baseline", "at": "2026-10-29T14:23:00", "kept": 5},
//    ("aligned" nur, wenn Farben und Namen an einen vorigen Stand angeglichen
//     wurden, #1367: "baseline" = architecture.baseline, "last" = zuletzt
//     berechneter Stand; "at" = Zeitpunkt des Stands, "kept" = Teilsysteme,
//     die Farbe und Namen behielten.)
//    "edges": [[0, 1, "i"], [1, 2, "m"]],            (i = interface, m = implementation)
//    "central": [0, 1],
//    "subsystems": [{"name": "Kern", "units": [0, 1], "central": 0,
//                    "inner": 2, "outer": 0, "cohesion": 1, "isolated": false,
//                    "color": 0, "shade": 0, "foundation": true, "parent": "Common",
//                    "x": 0, "y": 0, "r": 70}],         ("parent" nur bei nachgeteilten, #1364;
//                                                        "foundation" nur am Teilsystem „Fundament“, #1365)
//    "outliers": [{"unit": 3, "suggested": 1, "reason": "namespace",
//                  "inside": 2, "toward": 0}],
//    "cycles": [{"interfaceOnly": true, "units": [0, 1], "component": [0, 1],
//                "edges": [{"source": 0, "target": 1, "section": "interface",
//                           "file": "A.pas", "line": 3, "character": 6}]}],
//    "crossLinks": [{"source": 0, "target": 4, "section": "implementation",
//                    "from": 0, "to": 1, "reason": "rare", "forward": 1,
//                    "backward": 0, "file": "A.pas", "line": 9, "character": 3}]}
// "file"/"line"/"character" fehlen bei Kanten ohne Fundstelle.
// Mit Vergleich (#1121) steht zusätzlich "comparison" mit den Daten aus
// TArchitectureComparer.Json da; Markdown und HTML bekommen den Abschnitt
// „Vergleich“, die HTML-Karte zeigt neue Kanten grün und entfernte rot
// gestrichelt.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Grouping,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Comparison;

type
  TArchitectureSection = (Overview, Central, Subsystems, Cycles, CrossLinks);

  TArchitectureReport = class
  public const
    cFormat = 1;
    /// <summary>Höchstzahl der Einträge je Liste in der MCP-Ausgabe.</summary>
    cTextLimit = 30;
  public
    class function SectionName(ASection: TArchitectureSection): string; static;
    /// <summary>overview, central, subsystems, cycles, crossLinks (ohne Groß-/Kleinschreibung); '' =
    /// overview.</summary>
    class function ParseSection(const AText: string; out ASection: TArchitectureSection): Boolean; static;
    /// <summary>Daten der Übersicht samt Lage der Karte (siehe Kopf der Unit).</summary>
    class function Json(const AOverview: TArchitectureOverview; const ALayout: TArchitectureLayout): string;
      overload; static;
    /// <summary>Wie oben mit "comparison" (#1121).</summary>
    class function Json(const AOverview: TArchitectureOverview; const ALayout: TArchitectureLayout;
      const AComparison: TArchitectureComparison; AFailOn: TArchitectureFailKinds): string; overload; static;
    class function Markdown(const AOverview: TArchitectureOverview): string; overload; static;
    /// <summary>Wie oben, am Ende der Abschnitt „Vergleich“ (#1121).</summary>
    class function Markdown(const AOverview: TArchitectureOverview;
      const AComparison: TArchitectureComparison): string; overload; static;
    /// <summary>Eigenständige HTML-Seite mit eingebetteten Daten und Skript (offline, keine externen
    /// Verweise).</summary>
    class function Html(const AOverview: TArchitectureOverview): string; overload; static;
    /// <summary>Wie oben mit Abschnitt „Vergleich“ und geänderten Kanten auf der Karte (#1121).</summary>
    class function Html(const AOverview: TArchitectureOverview; const AComparison: TArchitectureComparison;
      AFailOn: TArchitectureFailKinds): string; overload; static;
    /// <summary>Bericht passend zur Endung von AFileName: .html/.htm HTML, sonst Markdown.</summary>
    class function ForFile(const AOverview: TArchitectureOverview; const AFileName: string): string; overload;
      static;
    /// <summary>Wie oben mit Vergleich (#1121).</summary>
    class function ForFile(const AOverview: TArchitectureOverview; const AFileName: string;
      const AComparison: TArchitectureComparison; AFailOn: TArchitectureFailKinds): string; overload; static;
    /// <summary>Kompakter Text eines Abschnitts für get_architecture; Listen auf ALimit gekürzt mit
    /// Gesamtzahl.</summary>
    class function Text(const AOverview: TArchitectureOverview; ASection: TArchitectureSection;
      ALimit: Integer): string; static;
    /// <summary>Steckbrief einer Unit; Meldung, wenn die Unit nicht in der Übersicht steht.</summary>
    class function UnitText(const AOverview: TArchitectureOverview; const AUnitName: string): string; static;
    /// <summary>"A → B (implementation, Source/A.pas:12)".</summary>
    class function EdgeText(const AOverview: TArchitectureOverview; const AEdge: TOverviewEdge): string; static;
    /// <summary>"Source/A.pas:12:3" oder '' ohne Fundstelle.</summary>
    class function LocationText(const AOverview: TArchitectureOverview; const AEdge: TOverviewEdge): string; static;
    class function SectionCaption(AInterface: Boolean): string; static;
    class function CrossReasonCaption(AReason: TOverviewCrossReason): string; static;
    class function OutlierReasonCaption(AReason: TOverviewOutlierReason): string; static;
    /// <summary>"Zyklus nur über interface (Compilerfehler F2047)" bzw. "Zyklus über implementation".</summary>
    class function CycleCaption(const ACycle: TOverviewCycle): string; static;
    /// <summary>"A → B → A" eines Zyklus.</summary>
    class function CyclePath(const AOverview: TArchitectureOverview; const ACycle: TOverviewCycle): string; static;
    /// <summary>Wie Atlas die Teilsysteme bildet (#1368): drei Sätze und die aktiven Einstellungen AGrouping.
    /// </summary>
    class function GroupingExplanation(const AGrouping: TArchitectureGrouping): string; static;
    /// <summary>„Teilsysteme an Stand vom … angeglichen (…)“ (#1367); '' ohne Angleichung.</summary>
    class function AlignedText(const AOverview: TArchitectureOverview): string; static;
    /// <summary>"Data erreicht 6 von 8, 3 Kanten fehlen zum Wechsel"; '' bei klarer Zuordnung.</summary>
    class function CloseText(const AOverview: TArchitectureOverview; const AAssignment: TOverviewAssignment): string;
      static;
    /// <summary>Block „Zuordnung“ einer Unit (get_architecture mit unit); '' ohne explainAssignment.</summary>
    class function AssignmentText(const AOverview: TArchitectureOverview; AUnit: Integer): string; static;
  private
    class function JsonWith(const AOverview: TArchitectureOverview; const ALayout: TArchitectureLayout;
      const AExtra: string): string; static;
    class function MarkdownWith(const AOverview: TArchitectureOverview; AWithComparison: Boolean): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.MapTemplate,
  Atlas.Common.Architecture.MapTemplateEn,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TArchitectureReportText = (EdgesThereAreNotCross, CrossLinksOutliers, WithLibraryUnits,
    SubsystemsAlignedWithTheState, SubsystemKeepsColorAnd, SubsystemsKeepColorAndName, AtlasFormsTheSubsystemsFrom,
    OrText, DoNotSplit, FoundationsAttached, FoundationsSeparateEdgesThereDo, ReachesOf1EdgeShort,
    ReachesOfEdgesShortOf, AlreadyHasWeightedEdgesIts, DoesNotCount, AgainstTheMainDirection,
    CycleThroughInterfaceOnlyCompiler, CycleThroughImplementation, Outlier, OutliersOutliers,
    TotalDependentsUnitsThatAre, UnitSubsystemDirectDependentsTotal, SubsystemUnitsCentralUnitCohesion, Outliers,
    UnitInSubsystemSuggestionReason, FromToSectionSubsystemsReason, Back, TotalDependents,
    MoreSectionsCentralSubsystemsCycles, Outliers2, NoCycles, NoCrossLinks, ThereBack, CyclesNone,
    OutlierBelongsRatherToEdges, UnitIsNotInThe, SSubsystemSdirectDependentsTotalDependents, PartOf,
    UnitsUsesEdgesSubsystemsCycles, OfTheseInterfaceOnly, LastCalculatedState, FromPercentOfAllUnits,
    BelowCohesionFromUnits, AssignmentEdgesPerSubsystemInterface, NamespaceFitsAnotherSubsystem,
    MoreEdgesIntoAnotherSubsystem, CentralUnitsCentralUnits, SubsystemsSubsystems, CyclesCycles, CrossLinksCrossLinks,
    ComparisonComparison, CentralUnits, CentralUnits2, UnitsCohesion, UnitSubsystemDirectTotalUses, UnitsCohesion2,
    UsedBy, Project, ProjectGroup, WithoutLibraryUnits, Excluded, Resolution, SettingsResolution, Split,
    FoundationsGroupedToo, Own, Narrow, Rare, NarrowlyAssigned, Architecture, State, ComputingTime, Scope, Subsystems,
    Cycles, Component, CrossLinks, Forward, MoreInTotal, Subsystems2, InSuggestion, Architecture2, CrossLink,
    UsesText);

const
  cTexts: array[TArchitectureReportText] of TAtlasText = (
    (De: ': %s; Kanten dorthin zählen nicht als Querverbindung und nicht im Zusammenhalt.';
     En: ': %s; edges there are not cross links and do not count for cohesion.'),
    (De: ' · Querverbindungen: %s · Ausreißer: '; En: ' · Cross links: %s · Outliers: '),
    (De: ', mit Bibliotheks-Units'; En: ', with library units'),
    (De: 'Teilsysteme an Stand vom %s angeglichen ('; En: 'Subsystems aligned with the state of %s ('),
    (De: '; 1 Teilsystem behält Farbe und Namen)'; En: '; 1 subsystem keeps color and name)'),
    (De: '; %s Teilsysteme behalten Farbe und Namen)'; En: '; %s subsystems keep color and name)'),
    (De: 'Atlas bildet die Teilsysteme aus den uses-Kanten zwischen den Units, ein- und ausgehende zusammen. Eine ' +
      'Kante im interface wiegt %s, eine im implementation-Teil %s. Das Louvain-Verfahren fasst Units zusammen, die ' +
      'untereinander mehr gewichtete Kanten haben als nach außen; eine Unit liegt darum meist dort, wohin die ' +
      'meisten ihrer gewichteten Kanten gehen, und gilt als knapp zugeordnet, wenn ein anderes Teilsystem mindestens ' +
      '%s Prozent davon erreicht.';
     En: 'Atlas forms the subsystems from the uses edges between the units, incoming and outgoing together. An edge ' +
      'in the interface weighs %s, one in the implementation part %s. The Louvain method groups units that have more ' +
      'weighted edges among each other than to the outside, so a unit usually lies where most of its weighted edges ' +
      'lead, and counts as close when another subsystem reaches at least %s percent of that.'),
    (De: ' oder '; En: ' or '),
    (De: ' · nicht nachteilen'; En: ' · do not split'),
    (De: ' · Fundamente angehängt'; En: ' · foundations attached'),
    (De: ' · Fundamente getrennt (Kanten dorthin zählen nicht)';
     En: ' · foundations separate (edges there do not count)'),
    (De: ' erreicht %s von %s, 1 Kante fehlt zum Wechsel'; En: ' reaches %s of %s, 1 edge short of a move'),
    (De: ' erreicht %s von %s, %s Kanten fehlen zum Wechsel'; En: ' reaches %s of %s, %s edges short of a move'),
    (De: ' hat schon %s gewichtete Kanten, das eigene Teilsystem %s (Louvain wertet das ganze Teilsystem)';
     En: ' already has %s weighted edges, its own subsystem %s (Louvain weighs the whole subsystem)'),
    (De: ' (zählt nicht)'; En: ' (does not count)'),
    (De: 'gegen die Hauptrichtung'; En: 'against the main direction'),
    (De: 'Zyklus nur über interface (Compilerfehler F2047)';
     En: 'Cycle through interface only (compiler error F2047)'),
    (De: 'Zyklus über implementation'; En: 'Cycle through implementation'),
    (De: ' (Ausreißer)'; En: ' (outlier)'),
    (De: '- [Ausreißer](#ausreißer)'; En: '- [Outliers](#outliers)'),
    (De: '„gesamt abhängig“: Units, die neu übersetzt werden, wenn sich das interface der Unit ändert.';
     En: '“total dependents”: units that are recompiled when the interface of the unit changes.'),
    (De: '| # | Unit | Teilsystem | direkt abhängig | gesamt abhängig | verwendet | Rolle |';
     En: '| # | Unit | Subsystem | direct dependents | total dependents | uses | Role |'),
    (De: '| Teilsystem | Units | zentrale Unit | Zusammenhalt | Kanten innen | Kanten nach außen |';
     En: '| Subsystem | Units | central unit | Cohesion | inner edges | outgoing edges |'),
    (De: '## Ausreißer'; En: '## Outliers'),
    (De: '| Unit | in Teilsystem | Vorschlag | Grund | Kanten im eigenen | Kanten zum Vorschlag |';
     En: '| Unit | in subsystem | Suggestion | Reason | edges in own | edges to suggestion |'),
    (De: '| Von | Nach | Abschnitt | Teilsysteme | Grund | Fundstelle |';
     En: '| From | To | Section | Subsystems | Reason | Location |'),
    (De: ' zurück) | '; En: ' back) | '),
    (De: '  %s: %s gesamt abhängig'; En: '  %s: %s total dependents'),
    (De: 'Weitere Abschnitte: central, subsystems, cycles, crossLinks; unit für einen Steckbrief.';
     En: 'More sections: central, subsystems, cycles, crossLinks; unit for a profile.'),
    (De: 'Ausreißer:'; En: 'Outliers:'),
    (De: 'Keine Zyklen.'; En: 'No cycles.'),
    (De: 'Keine Querverbindungen.'; En: 'No cross links.'),
    (De: ' %s → %s, %s (%s hin, %s zurück)'; En: ' %s → %s, %s (%s there, %s back)'),
    (De: 'Zyklen: keine'; En: 'Cycles: none'),
    (De: 'Ausreißer: gehört eher zu %s (%s; %s Kanten im eigenen, %s zum Vorschlag)';
     En: 'Outlier: belongs rather to %s (%s; %s edges in own, %s to suggestion)'),
    (De: 'Unit "%s" ist nicht in der Architekturübersicht (nicht im Umfang, ausgeschlossen oder Bibliotheks-Unit).';
     En: 'Unit "%s" is not in the architecture overview (out of scope, excluded or library unit).'),
    (De: ' (%s)%sTeilsystem: %s%sdirekt abhängig: %s · gesamt abhängig: %s · verwendet: ';
     En: ' (%s)%sSubsystem: %s%sdirect dependents: %s · total dependents: %s · uses: '),
    (De: ' (Teil von %s)'; En: ' (part of %s)'),
    (De: 'Units: %s · uses-Kanten: %s · Teilsysteme: %s · Zyklen: ';
     En: 'Units: %s · uses edges: %s · subsystems: %s · cycles: '),
    (De: ' (davon nur interface: %s)'; En: ' (of these interface only: %s)'),
    (De: 'zuletzt berechneter Stand'; En: 'last calculated state'),
    (De: 'ab %s Prozent aller Units'; En: 'from %s percent of all units'),
    (De: 'unter Zusammenhalt %s (ab %s Units)'; En: 'below cohesion %s (from %s units)'),
    (De: 'Zuordnung (Kanten je Teilsystem, interface %s, implementation %s):%s  Teilsystem | interface | impl. | ' +
      'Summe';
     En: 'Assignment (edges per subsystem, interface %s, implementation %s):%s  Subsystem | interface | impl. | ' +
      'sum'),
    (De: 'Namensraum passt zu einem anderen Teilsystem'; En: 'Namespace fits another subsystem'),
    (De: 'mehr Kanten in ein anderes Teilsystem'; En: 'more edges into another subsystem'),
    (De: '- [Zentrale Units](#zentrale-units)'; En: '- [Central units](#central-units)'),
    (De: '- [Teilsysteme](#teilsysteme)'; En: '- [Subsystems](#subsystems)'),
    (De: '- [Zyklen](#zyklen)'; En: '- [Cycles](#cycles)'),
    (De: '- [Querverbindungen](#querverbindungen)'; En: '- [Cross links](#cross-links)'),
    (De: '- [Vergleich](#vergleich)'; En: '- [Comparison](#comparison)'),
    (De: '## Zentrale Units'; En: '## Central units'),
    (De: 'Zentrale Units:'; En: 'Central units:'),
    (De: '  %s: %s Units, Zusammenhalt '; En: '  %s: %s units, cohesion '),
    (De: 'Unit | Teilsystem | direkt | gesamt | verwendet | Rolle';
     En: 'Unit | Subsystem | direct | total | uses | Role'),
    (De: ': %s Units, Zusammenhalt %s%s  '; En: ': %s units, cohesion %s%s  '),
    (De: 'verwendet von: '; En: 'used by: '),
    (De: 'Projekt'; En: 'Project'),
    (De: 'Projektgruppe'; En: 'Project group'),
    (De: ', ohne Bibliotheks-Units'; En: ', without library units'),
    (De: ', ausgeschlossen: '; En: ', excluded: '),
    (De: ', Feinheit γ = '; En: ', resolution γ = '),
    (De: ' Einstellungen: Feinheit '; En: ' Settings: resolution '),
    (De: ' · nachteilen '; En: ' · split '),
    (De: ' · Fundamente mitgruppiert'; En: ' · foundations grouped too'),
    (De: ' (eigenes)'; En: ' (own)'),
    (De: '  knapp: '; En: '  narrow: '),
    (De: 'selten'; En: 'rare'),
    (De: 'Knapp zugeordnet:'; En: 'Narrowly assigned:'),
    (De: '# Architektur: '; En: '# Architecture: '),
    (De: 'Stand '; En: 'State '),
    (De: ' · Rechendauer '; En: ' · computing time '),
    (De: 'Umfang: '; En: 'Scope: '),
    (De: '## Teilsysteme'; En: '## Subsystems'),
    (De: '## Zyklen'; En: '## Cycles'),
    (De: '- Komponente: '; En: '- Component: '),
    (De: '## Querverbindungen'; En: '## Cross links'),
    (De: ' hin, '; En: ' forward, '),
    (De: '… %s weitere (insgesamt %s)'; En: '… %s more (%s in total)'),
    (De: 'Teilsysteme:'; En: 'Subsystems:'),
    (De: '  %s in %s, Vorschlag %s (%s)'; En: '  %s in %s, suggestion %s (%s)'),
    (De: 'Architektur %s (%s)'; En: 'Architecture %s (%s)'),
    (De: 'Querverbindung: '; En: 'Cross link: '),
    (De: 'verwendet: '; En: 'uses: '));

const
  cLineBreak = #13#10;

function JsonText(const AText: string): string;
begin
  Result := TMetricsReport.JsonString(AText);
end;

function JsonNumber(AValue: Double): string;
begin
  Result := FormatFloat('0.###', AValue, TFormatSettings.Invariant);
end;

function JsonBool(AValue: Boolean): string;
begin
  if AValue then
  begin
    Result := 'true';
  end
  else
  begin
    Result := 'false';
  end;
end;

function JsonInts(const AValues: TArray<Integer>): string;
var
  mIndex: Integer;
begin
  Result := '[';
  for mIndex := 0 to High(AValues) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + IntToStr(AValues[mIndex]);
  end;
  Result := Result + ']';
end;

function Cell(const AText: string): string;
begin
  Result := StringReplace(AText, '|', '\|', [rfReplaceAll]);
end;

function Percent(AValue: Double): string;
begin
  Result := IntToStr(Round(AValue * 100)) + ' %';
end;

function IsInterface(const AEdge: TOverviewEdge): Boolean;
begin
  Result := AEdge.Section = TUsesSection.Interface_;
end;

function RoleName(ARole: TOverviewUnitRole): string;
begin
  case ARole of
    TOverviewUnitRole.Foundation:
      Result := 'foundation';
    TOverviewUnitRole.Hub:
      Result := 'hub';
  else
    Result := '';
  end;
end;

function SubsystemName(const AOverview: TArchitectureOverview; ASubsystem: Integer): string;
begin
  if (ASubsystem >= 0) and (ASubsystem < Length(AOverview.Subsystems)) then
  begin
    Result := AOverview.Subsystems[ASubsystem].Name;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Name mit dem ursprünglichen Teilsystem, wenn es nachgeteilt wurde (#1364): "Lsp (Teil von Common)".
/// </summary>
function SubsystemCaption(const ASubsystem: TOverviewSubsystem): string;
begin
  Result := ASubsystem.Name;
  if ASubsystem.Parent <> '' then
  begin
    Result := Result + cTexts[TArchitectureReportText.PartOf].Fmt([ASubsystem.Parent]);
  end;
end;

/// <summary>Zusammenhalt in Prozent; „–“ beim Teilsystem „Fundament“ (#1365).</summary>
function CohesionText(const ASubsystem: TOverviewSubsystem): string;
begin
  if ASubsystem.Foundation then
  begin
    Result := '–';
  end
  else
  begin
    Result := Percent(ASubsystem.Cohesion);
  end;
end;

/// <summary>Hinweis, nach welcher Regel das Teilsystem „Fundament“ entstand; '' ohne Fundament.</summary>
function FoundationNote(const AOverview: TArchitectureOverview): string;
var
  mSubsystem: TOverviewSubsystem;
begin
  Result := '';
  for mSubsystem in AOverview.Subsystems do
  begin
    if mSubsystem.Foundation then
    begin
      Result := TArchitectureAnalyzer.cFoundationName + cTexts[TArchitectureReportText.EdgesThereAreNotCross].Fmt([
        TArchitectureAnalyzer.FoundationRule]);
    end;
  end;
end;

function CreatedText(const AOverview: TArchitectureOverview): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn', AOverview.Created, TFormatSettings.Invariant);
end;

function InterfaceCycleCount(const AOverview: TArchitectureOverview): Integer;
var
  mCycle: TOverviewCycle;
begin
  Result := 0;
  for mCycle in AOverview.Cycles do
  begin
    if mCycle.InterfaceOnly then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>"Units: 12 · uses-Kanten: 17 · …" für Kopf und MCP.</summary>
function Counts(const AOverview: TArchitectureOverview): string;
begin
  Result := cTexts[TArchitectureReportText.UnitsUsesEdgesSubsystemsCycles].Fmt([IntToStr(Length(AOverview.Units)),
    IntToStr(AOverview.EdgeCount), IntToStr(Length(AOverview.Subsystems))]) + IntToStr(Length(AOverview.Cycles));
  if InterfaceCycleCount(AOverview) > 0 then
  begin
    Result := Result + cTexts[TArchitectureReportText.OfTheseInterfaceOnly].Fmt([
      IntToStr(InterfaceCycleCount(AOverview))]);
  end;
  Result := Result + cTexts[TArchitectureReportText.CrossLinksOutliers].Fmt([IntToStr(Length(AOverview.CrossLinks))]) +
    IntToStr(Length(AOverview.Outliers));
end;

function ScopeText(const AOverview: TArchitectureOverview): string;
begin
  if SameText(AOverview.Scope, 'project') then
  begin
    Result := cTexts[TArchitectureReportText.Project].Text;
  end
  else
  begin
    Result := cTexts[TArchitectureReportText.ProjectGroup].Text;
  end;
  if AOverview.IncludeLibrary then
  begin
    Result := Result + cTexts[TArchitectureReportText.WithLibraryUnits].Text;
  end
  else
  begin
    Result := Result + cTexts[TArchitectureReportText.WithoutLibraryUnits].Text;
  end;
  if Length(AOverview.Excludes) > 0 then
  begin
    Result := Result + cTexts[TArchitectureReportText.Excluded].Text + string.Join(', ', AOverview.Excludes);
  end;
  // Feinheit der Teilsysteme (#1366) nur, wenn sie von 1,0 abweicht.
  if AOverview.Grouping.ResolutionChanged then
  begin
    Result := Result + cTexts[TArchitectureReportText.Resolution].Text +
      TArchitectureGrouping.ResolutionText(AOverview.Grouping.Clamped.Resolution);
  end;
end;

{ TArchitectureReport }

class function TArchitectureReport.AlignedText(const AOverview: TArchitectureOverview): string;
begin
  Result := '';
  if not AOverview.IsAligned then
  begin
    Exit;
  end;
  Result := cTexts[TArchitectureReportText.SubsystemsAlignedWithTheState].Fmt([FormatDateTime('yyyy-mm-dd hh:nn',
    AOverview.AlignedAt,
    TFormatSettings.Invariant)]);
  if AOverview.AlignedSource = TArchitectureAnalyzer.cAlignedBaseline then
  begin
    Result := Result + 'architecture.baseline';
  end
  else
  begin
    Result := Result + cTexts[TArchitectureReportText.LastCalculatedState].Text;
  end;
  if AOverview.AlignedKept = 1 then
  begin
    Result := Result + cTexts[TArchitectureReportText.SubsystemKeepsColorAnd].Text;
  end
  else
  begin
    Result := Result + cTexts[TArchitectureReportText.SubsystemsKeepColorAndName].Fmt([
      IntToStr(AOverview.AlignedKept)]);
  end;
end;

class function TArchitectureReport.GroupingExplanation(const AGrouping: TArchitectureGrouping): string;
var
  mGrouping: TArchitectureGrouping;
  mSplit: string;
begin
  mGrouping := AGrouping.Clamped;
  Result := cTexts[TArchitectureReportText.AtlasFormsTheSubsystemsFrom].Fmt([
    IntToStr(TArchitectureAnalyzer.cInterfaceWeight), IntToStr(TArchitectureAnalyzer.cImplementationWeight),
    IntToStr(TArchitectureAnalyzer.cClosePercent)]);
  Result := Result + cTexts[TArchitectureReportText.SettingsResolution].Text +
    TArchitectureGrouping.ResolutionText(mGrouping.Resolution);
  mSplit := '';
  if mGrouping.MaxShare > 0 then
  begin
    mSplit := cTexts[TArchitectureReportText.FromPercentOfAllUnits].Fmt([IntToStr(Round(mGrouping.MaxShare * 100))]);
  end;
  if mGrouping.MinCohesion > 0 then
  begin
    if mSplit <> '' then
    begin
      mSplit := mSplit + cTexts[TArchitectureReportText.OrText].Text;
    end;
    mSplit := mSplit + cTexts[TArchitectureReportText.BelowCohesionFromUnits].Fmt([
      TArchitectureGrouping.ResolutionText(mGrouping.MinCohesion), IntToStr(TArchitectureGrouping.cLooseMinUnits)]);
  end;
  if mSplit = '' then
  begin
    Result := Result + cTexts[TArchitectureReportText.DoNotSplit].Text;
  end
  else
  begin
    Result := Result + cTexts[TArchitectureReportText.Split].Text + mSplit;
  end;
  case mGrouping.Foundations of
    TArchitectureFoundations.Group:
      Result := Result + cTexts[TArchitectureReportText.FoundationsGroupedToo].Text;
    TArchitectureFoundations.Attach:
      Result := Result + cTexts[TArchitectureReportText.FoundationsAttached].Text;
  else
    Result := Result + cTexts[TArchitectureReportText.FoundationsSeparateEdgesThereDo].Text;
  end;
  Result := Result + '.';
end;

class function TArchitectureReport.CloseText(const AOverview: TArchitectureOverview;
  const AAssignment: TOverviewAssignment): string;
var
  mRival: string;
begin
  if not AAssignment.Close then
  begin
    Exit('');
  end;
  mRival := SubsystemName(AOverview, AAssignment.Rows[AAssignment.Rival].Subsystem);
  if AAssignment.Missing = 1 then
  begin
    Result := mRival + cTexts[TArchitectureReportText.ReachesOf1EdgeShort].Fmt([IntToStr(AAssignment.RivalSum),
      IntToStr(AAssignment.OwnSum)]);
  end
  else if AAssignment.Missing > 1 then
  begin
    Result := mRival + cTexts[TArchitectureReportText.ReachesOfEdgesShortOf].Fmt([IntToStr(AAssignment.RivalSum),
      IntToStr(AAssignment.OwnSum), IntToStr(AAssignment.Missing)]);
  end
  else
  begin
    Result := mRival + cTexts[TArchitectureReportText.AlreadyHasWeightedEdgesIts].Fmt([IntToStr(AAssignment.RivalSum),
      IntToStr(AAssignment.OwnSum)]);
  end;
end;

class function TArchitectureReport.AssignmentText(const AOverview: TArchitectureOverview; AUnit: Integer): string;
var
  mAssignment: TOverviewAssignment;
  mIndex: Integer;
  mRow: TOverviewAssignmentRow;
  mLine: string;
begin
  Result := '';
  if not AOverview.ShowsAssignment then
  begin
    Exit;
  end;
  mAssignment := AOverview.Assignment(AUnit);
  if mAssignment.Own < 0 then
  begin
    Exit;
  end;
  Result := cTexts[TArchitectureReportText.AssignmentEdgesPerSubsystemInterface].Fmt([
    IntToStr(TArchitectureAnalyzer.cInterfaceWeight), IntToStr(TArchitectureAnalyzer.cImplementationWeight),
    cLineBreak]) + cLineBreak;
  for mIndex := 0 to High(mAssignment.Rows) do
  begin
    mRow := mAssignment.Rows[mIndex];
    mLine := '  ' + SubsystemName(AOverview, mRow.Subsystem);
    if mIndex = mAssignment.Own then
    begin
      mLine := mLine + cTexts[TArchitectureReportText.Own].Text;
    end;
    mLine := mLine + ' | ' + IntToStr(mRow.Interfaces) + ' | ' + IntToStr(mRow.Implementations) + ' | ' +
      IntToStr(mRow.Sum);
    if not mRow.Counts then
    begin
      mLine := mLine + cTexts[TArchitectureReportText.DoesNotCount].Text;
    end;
    Result := Result + mLine + cLineBreak;
  end;
  if mAssignment.Close then
  begin
    Result := Result + cTexts[TArchitectureReportText.Narrow].Text + CloseText(AOverview, mAssignment) + cLineBreak;
  end;
end;

class function TArchitectureReport.SectionName(ASection: TArchitectureSection): string;
begin
  case ASection of
    TArchitectureSection.Central:
      Result := 'central';
    TArchitectureSection.Subsystems:
      Result := 'subsystems';
    TArchitectureSection.Cycles:
      Result := 'cycles';
    TArchitectureSection.CrossLinks:
      Result := 'crossLinks';
  else
    Result := 'overview';
  end;
end;

class function TArchitectureReport.ParseSection(const AText: string; out ASection: TArchitectureSection): Boolean;
var
  mSection: TArchitectureSection;
begin
  ASection := TArchitectureSection.Overview;
  if Trim(AText) = '' then
  begin
    Exit(True);
  end;
  for mSection := Low(TArchitectureSection) to High(TArchitectureSection) do
  begin
    if SameText(Trim(AText), SectionName(mSection)) then
    begin
      ASection := mSection;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TArchitectureReport.SectionCaption(AInterface: Boolean): string;
begin
  if AInterface then
  begin
    Result := 'interface';
  end
  else
  begin
    Result := 'implementation';
  end;
end;

class function TArchitectureReport.CrossReasonCaption(AReason: TOverviewCrossReason): string;
begin
  if AReason = TOverviewCrossReason.Rare then
  begin
    Result := cTexts[TArchitectureReportText.Rare].Text;
  end
  else
  begin
    Result := cTexts[TArchitectureReportText.AgainstTheMainDirection].Text;
  end;
end;

class function TArchitectureReport.OutlierReasonCaption(AReason: TOverviewOutlierReason): string;
begin
  if AReason = TOverviewOutlierReason.Namespace then
  begin
    Result := cTexts[TArchitectureReportText.NamespaceFitsAnotherSubsystem].Text;
  end
  else
  begin
    Result := cTexts[TArchitectureReportText.MoreEdgesIntoAnotherSubsystem].Text;
  end;
end;

class function TArchitectureReport.CycleCaption(const ACycle: TOverviewCycle): string;
begin
  if ACycle.InterfaceOnly then
  begin
    Result := cTexts[TArchitectureReportText.CycleThroughInterfaceOnlyCompiler].Text;
  end
  else
  begin
    Result := cTexts[TArchitectureReportText.CycleThroughImplementation].Text;
  end;
end;

class function TArchitectureReport.CyclePath(const AOverview: TArchitectureOverview;
  const ACycle: TOverviewCycle): string;
var
  mEdge: TOverviewEdge;
begin
  Result := '';
  for mEdge in ACycle.Edges do
  begin
    if Result = '' then
    begin
      Result := AOverview.Units[mEdge.Source].Name;
    end;
    Result := Result + ' → ' + AOverview.Units[mEdge.Target].Name;
  end;
end;

class function TArchitectureReport.LocationText(const AOverview: TArchitectureOverview;
  const AEdge: TOverviewEdge): string;
begin
  if not AEdge.Located then
  begin
    Exit('');
  end;
  Result := AOverview.RelativePath(AEdge.Location.FileName) + ':' + IntToStr(AEdge.Location.Range.StartPos.Line + 1) +
    ':' + IntToStr(AEdge.Location.Range.StartPos.Character + 1);
end;

class function TArchitectureReport.EdgeText(const AOverview: TArchitectureOverview; const AEdge: TOverviewEdge): string;
var
  mLocation: string;
begin
  Result := AOverview.Units[AEdge.Source].Name + ' → ' + AOverview.Units[AEdge.Target].Name + ' (' +
    SectionCaption(IsInterface(AEdge));
  mLocation := LocationText(AOverview, AEdge);
  if mLocation <> '' then
  begin
    Result := Result + ', ' + mLocation;
  end;
  Result := Result + ')';
end;

/// <summary>"assignment" und "close" einer Unit (#1368, siehe Kopf der Unit).</summary>
procedure AppendAssignment(ABuilder: TStringBuilder; const AAssignment: TOverviewAssignment);
var
  mIndex: Integer;
  mRow: TOverviewAssignmentRow;
begin
  ABuilder.Append(',"assignment":[');
  for mIndex := 0 to High(AAssignment.Rows) do
  begin
    mRow := AAssignment.Rows[mIndex];
    if mIndex > 0 then
    begin
      ABuilder.Append(',');
    end;
    ABuilder.Append('[').Append(mRow.Subsystem).Append(',').Append(mRow.Interfaces).Append(',')
      .Append(mRow.Implementations);
    if not mRow.Counts then
    begin
      ABuilder.Append(',0');
    end;
    ABuilder.Append(']');
  end;
  ABuilder.Append(']');
  if AAssignment.Close then
  begin
    ABuilder.Append(',"close":').Append(AAssignment.Missing);
  end;
end;

function EdgeJson(const AOverview: TArchitectureOverview; const AEdge: TOverviewEdge): string;
begin
  Result := '"source":' + IntToStr(AEdge.Source) + ',"target":' + IntToStr(AEdge.Target) + ',"section":' +
    JsonText(TArchitectureReport.SectionCaption(IsInterface(AEdge)));
  if AEdge.Located then
  begin
    Result := Result + ',"file":' + JsonText(AOverview.RelativePath(AEdge.Location.FileName)) + ',"line":' +
      IntToStr(AEdge.Location.Range.StartPos.Line + 1) + ',"character":' +
      IntToStr(AEdge.Location.Range.StartPos.Character + 1);
  end;
end;

class function TArchitectureReport.Json(const AOverview: TArchitectureOverview;
  const ALayout: TArchitectureLayout): string;
begin
  Result := JsonWith(AOverview, ALayout, '');
end;

class function TArchitectureReport.Json(const AOverview: TArchitectureOverview; const ALayout: TArchitectureLayout;
  const AComparison: TArchitectureComparison; AFailOn: TArchitectureFailKinds): string;
begin
  Result := JsonWith(AOverview, ALayout, ',' + cLineBreak + '"comparison":' + TArchitectureComparer.Json(AComparison,
    AFailOn));
end;

/// <summary>Komma vor jedem Listeneintrag außer dem ersten.</summary>
procedure AppendComma(ABuilder: TStringBuilder; AIndex: Integer);
begin
  if AIndex > 0 then
  begin
    ABuilder.Append(',');
  end;
end;

procedure AppendJsonHeader(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mIndex: Integer;
begin
  ABuilder.Append('{"format":').Append(TArchitectureReport.cFormat).Append(',"title":').Append(JsonText(AOverview.Title))
    .Append(',"created":')
    .Append(JsonText(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', AOverview.Created, TFormatSettings.Invariant)))
    .Append(',"generation":').Append(IntToStr(AOverview.Generation))
    .Append(',"durationMs":').Append(IntToStr(AOverview.DurationMs))
    .Append(',"scope":').Append(JsonText(AOverview.Scope))
    .Append(',"includeLibrary":').Append(JsonBool(AOverview.IncludeLibrary))
    .Append(',"grouping":{"resolution":').Append(JsonNumber(AOverview.Grouping.Clamped.Resolution))
    .Append(',"maxShare":').Append(JsonNumber(AOverview.Grouping.Clamped.MaxShare))
    .Append(',"minCohesion":').Append(JsonNumber(AOverview.Grouping.Clamped.MinCohesion))
    .Append(',"foundations":').Append(JsonText(TArchitectureGrouping.FoundationsText(AOverview.Grouping.Foundations)))
    .Append('}')
    .Append(',"excludes":[');
  for mIndex := 0 to High(AOverview.Excludes) do
  begin
    AppendComma(ABuilder, mIndex);
    ABuilder.Append(JsonText(AOverview.Excludes[mIndex]));
  end;
  ABuilder.Append('],"summary":{"units":').Append(Length(AOverview.Units))
    .Append(',"edges":').Append(AOverview.EdgeCount)
    .Append(',"subsystems":').Append(Length(AOverview.Subsystems))
    .Append(',"cycles":').Append(Length(AOverview.Cycles))
    .Append(',"interfaceCycles":').Append(InterfaceCycleCount(AOverview))
    .Append(',"crossLinks":').Append(Length(AOverview.CrossLinks))
    .Append(',"outliers":').Append(Length(AOverview.Outliers)).Append('}');
  if AOverview.ShowsAssignment then
  begin
    ABuilder.Append(',"explanation":').Append(JsonText(TArchitectureReport.GroupingExplanation(AOverview.Grouping)));
  end;
  if AOverview.IsAligned then
  begin
    ABuilder.Append(',"aligned":{"source":').Append(JsonText(AOverview.AlignedSource))
      .Append(',"at":')
      .Append(JsonText(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', AOverview.AlignedAt, TFormatSettings.Invariant)))
      .Append(',"kept":').Append(AOverview.AlignedKept).Append('}');
  end;
end;

procedure AppendJsonUnits(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview;
  const ALayout: TArchitectureLayout);
var
  mIndex: Integer;
  mItem: TOverviewUnit;
begin
  ABuilder.Append(',"units":[');
  for mIndex := 0 to High(AOverview.Units) do
  begin
    mItem := AOverview.Units[mIndex];
    AppendComma(ABuilder, mIndex);
    ABuilder.Append(cLineBreak).Append('{"name":').Append(JsonText(mItem.Name))
      .Append(',"file":').Append(JsonText(AOverview.RelativePath(mItem.FileName)))
      .Append(',"subsystem":').Append(mItem.Subsystem)
      .Append(',"direct":').Append(mItem.Direct)
      .Append(',"total":').Append(mItem.Total)
      .Append(',"uses":').Append(mItem.Uses_)
      .Append(',"role":').Append(JsonText(RoleName(mItem.Role)))
      .Append(',"library":').Append(JsonBool(mItem.Library_));
    if mIndex < Length(ALayout.Units) then
    begin
      ABuilder.Append(',"x":').Append(JsonNumber(ALayout.Units[mIndex].X))
        .Append(',"y":').Append(JsonNumber(ALayout.Units[mIndex].Y));
    end;
    if AOverview.ShowsAssignment then
    begin
      AppendAssignment(ABuilder, AOverview.Assignments[mIndex]);
    end;
    ABuilder.Append('}');
  end;
  ABuilder.Append(']');
end;

procedure AppendJsonEdges(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mIndex: Integer;
  mEdge: TOverviewEdge;
  mKind: string;
begin
  ABuilder.Append(',"edges":[');
  for mIndex := 0 to High(AOverview.Edges) do
  begin
    mEdge := AOverview.Edges[mIndex];
    AppendComma(ABuilder, mIndex);
    if mIndex mod 20 = 0 then
    begin
      ABuilder.Append(cLineBreak);
    end;
    if IsInterface(mEdge) then
    begin
      mKind := 'i';
    end
    else
    begin
      mKind := 'm';
    end;
    ABuilder.Append('[').Append(mEdge.Source).Append(',').Append(mEdge.Target).Append(',"').Append(mKind).Append('"]');
  end;
  ABuilder.Append('],"central":').Append(JsonInts(AOverview.Central));
end;

procedure AppendJsonSubsystem(ABuilder: TStringBuilder; const ASubsystem: TOverviewSubsystem);
begin
  ABuilder.Append(cLineBreak).Append('{"name":').Append(JsonText(ASubsystem.Name))
    .Append(',"units":').Append(JsonInts(ASubsystem.Units))
    .Append(',"central":').Append(ASubsystem.Central)
    .Append(',"inner":').Append(ASubsystem.InnerEdges)
    .Append(',"outer":').Append(ASubsystem.OuterEdges)
    .Append(',"cohesion":').Append(JsonNumber(ASubsystem.Cohesion))
    .Append(',"isolated":').Append(JsonBool(ASubsystem.Isolated))
    .Append(',"color":').Append(ASubsystem.ColorSlot)
    .Append(',"shade":').Append(ASubsystem.Shade);
  if ASubsystem.Foundation then
  begin
    ABuilder.Append(',"foundation":true');
  end;
  if ASubsystem.Parent <> '' then
  begin
    ABuilder.Append(',"parent":').Append(JsonText(ASubsystem.Parent));
  end;
end;

procedure AppendJsonSubsystems(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview;
  const ALayout: TArchitectureLayout);
var
  mIndex: Integer;
begin
  ABuilder.Append(',"subsystems":[');
  for mIndex := 0 to High(AOverview.Subsystems) do
  begin
    AppendComma(ABuilder, mIndex);
    AppendJsonSubsystem(ABuilder, AOverview.Subsystems[mIndex]);
    if mIndex < Length(ALayout.Subsystems) then
    begin
      ABuilder.Append(',"x":').Append(JsonNumber(ALayout.Subsystems[mIndex].X))
        .Append(',"y":').Append(JsonNumber(ALayout.Subsystems[mIndex].Y))
        .Append(',"r":').Append(JsonNumber(ALayout.Subsystems[mIndex].Radius));
    end;
    ABuilder.Append('}');
  end;
  ABuilder.Append(']');
end;

procedure AppendJsonOutliers(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mIndex: Integer;
  mOutlier: TOverviewOutlier;
begin
  ABuilder.Append(',"outliers":[');
  for mIndex := 0 to High(AOverview.Outliers) do
  begin
    mOutlier := AOverview.Outliers[mIndex];
    AppendComma(ABuilder, mIndex);
    ABuilder.Append(cLineBreak).Append('{"unit":').Append(mOutlier.Unit_)
      .Append(',"suggested":').Append(mOutlier.Suggested)
      .Append(',"reason":');
    if mOutlier.Reason = TOverviewOutlierReason.Namespace then
    begin
      ABuilder.Append('"namespace"');
    end
    else
    begin
      ABuilder.Append('"edges"');
    end;
    ABuilder.Append(',"inside":').Append(mOutlier.Inside).Append(',"toward":').Append(mOutlier.Toward).Append('}');
  end;
  ABuilder.Append(']');
end;

procedure AppendJsonCycles(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mIndex, mInner: Integer;
  mCycle: TOverviewCycle;
begin
  ABuilder.Append(',"cycles":[');
  for mIndex := 0 to High(AOverview.Cycles) do
  begin
    mCycle := AOverview.Cycles[mIndex];
    AppendComma(ABuilder, mIndex);
    ABuilder.Append(cLineBreak).Append('{"interfaceOnly":').Append(JsonBool(mCycle.InterfaceOnly))
      .Append(',"units":').Append(JsonInts(mCycle.Units))
      .Append(',"component":').Append(JsonInts(mCycle.Component))
      .Append(',"edges":[');
    for mInner := 0 to High(mCycle.Edges) do
    begin
      AppendComma(ABuilder, mInner);
      ABuilder.Append('{').Append(EdgeJson(AOverview, mCycle.Edges[mInner])).Append('}');
    end;
    ABuilder.Append(']}');
  end;
  ABuilder.Append(']');
end;

procedure AppendJsonCrossLinks(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mIndex: Integer;
  mLink: TOverviewCrossLink;
begin
  ABuilder.Append(',"crossLinks":[');
  for mIndex := 0 to High(AOverview.CrossLinks) do
  begin
    mLink := AOverview.CrossLinks[mIndex];
    AppendComma(ABuilder, mIndex);
    ABuilder.Append(cLineBreak).Append('{').Append(EdgeJson(AOverview, mLink.Edge))
      .Append(',"from":').Append(mLink.FromSubsystem)
      .Append(',"to":').Append(mLink.ToSubsystem)
      .Append(',"reason":');
    if mLink.Reason = TOverviewCrossReason.Rare then
    begin
      ABuilder.Append('"rare"');
    end
    else
    begin
      ABuilder.Append('"againstDirection"');
    end;
    ABuilder.Append(',"forward":').Append(mLink.Forward).Append(',"backward":').Append(mLink.Backward).Append('}');
  end;
  ABuilder.Append(']');
end;

/// <summary>Daten der Übersicht; AExtra steht vor der schließenden Klammer (z. B. ',"comparison":…').</summary>
class function TArchitectureReport.JsonWith(const AOverview: TArchitectureOverview; const ALayout: TArchitectureLayout;
  const AExtra: string): string;
var
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    AppendJsonHeader(mBuilder, AOverview);
    AppendJsonUnits(mBuilder, AOverview, ALayout);
    AppendJsonEdges(mBuilder, AOverview);
    AppendJsonSubsystems(mBuilder, AOverview, ALayout);
    AppendJsonOutliers(mBuilder, AOverview);
    AppendJsonCycles(mBuilder, AOverview);
    AppendJsonCrossLinks(mBuilder, AOverview);
    mBuilder.Append(AExtra).Append('}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TArchitectureReport.Markdown(const AOverview: TArchitectureOverview): string;
begin
  Result := MarkdownWith(AOverview, False);
end;

class function TArchitectureReport.Markdown(const AOverview: TArchitectureOverview;
  const AComparison: TArchitectureComparison): string;
begin
  Result := MarkdownWith(AOverview, True) + cLineBreak + TArchitectureComparer.Markdown(AComparison);
end;

/// <summary>Liste der knapp zugeordneten Units eines Teilsystems (#1368); nichts ohne solche.</summary>
procedure AppendCloseUnits(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview;
  const ASubsystem: TOverviewSubsystem);
var
  mMember: Integer;
  mAssignment: TOverviewAssignment;
  mFirst: Boolean;
begin
  mFirst := True;
  for mMember in ASubsystem.Units do
  begin
    mAssignment := AOverview.Assignment(mMember);
    if not mAssignment.Close then
    begin
      Continue;
    end;
    if mFirst then
    begin
      ABuilder.Append(cTexts[TArchitectureReportText.NarrowlyAssigned].Text).Append(cLineBreak).Append(cLineBreak);
    end;
    mFirst := False;
    ABuilder.Append('- ').Append(AOverview.Units[mMember].Name).Append(': ')
      .Append(TArchitectureReport.CloseText(AOverview, mAssignment)).Append(cLineBreak);
  end;
  if not mFirst then
  begin
    ABuilder.Append(cLineBreak);
  end;
end;

/// <summary>Namen der Units AMembers, durch Komma getrennt; AMarkOutliers hängt „(Ausreißer)“ an.</summary>
function UnitNameList(const AOverview: TArchitectureOverview; const AMembers: TArray<Integer>;
  AMarkOutliers: Boolean): string;
var
  mMember: Integer;
begin
  Result := '';
  for mMember in AMembers do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + AOverview.Units[mMember].Name;
    if AMarkOutliers and (AOverview.Profile(mMember).Outlier >= 0) then
    begin
      Result := Result + cTexts[TArchitectureReportText.Outlier].Text;
    end;
  end;
end;

procedure AppendMarkdownHeader(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview;
  AWithComparison: Boolean);
begin
  ABuilder.Append(cTexts[TArchitectureReportText.Architecture].Text).Append(AOverview.Title).Append(cLineBreak)
    .Append(cLineBreak);
  ABuilder.Append(cTexts[TArchitectureReportText.State].Text).Append(CreatedText(AOverview))
    .Append(' · Index-Generation ')
    .Append(IntToStr(AOverview.Generation)).Append(cTexts[TArchitectureReportText.ComputingTime].Text)
    .Append(IntToStr(AOverview.DurationMs))
    .Append(' ms').Append(cLineBreak).Append(cLineBreak);
  ABuilder.Append(Counts(AOverview)).Append(cLineBreak).Append(cLineBreak);
  ABuilder.Append(cTexts[TArchitectureReportText.Scope].Text).Append(ScopeText(AOverview)).Append(cLineBreak)
    .Append(cLineBreak);
  if AOverview.IsAligned then
  begin
    ABuilder.Append(TArchitectureReport.AlignedText(AOverview)).Append(cLineBreak).Append(cLineBreak);
  end;
  ABuilder.Append(cTexts[TArchitectureReportText.CentralUnitsCentralUnits].Text).Append(cLineBreak)
    .Append(cTexts[TArchitectureReportText.SubsystemsSubsystems].Text).Append(cLineBreak)
    .Append(cTexts[TArchitectureReportText.OutliersOutliers].Text).Append(cLineBreak)
    .Append(cTexts[TArchitectureReportText.CyclesCycles].Text).Append(cLineBreak)
    .Append(cTexts[TArchitectureReportText.CrossLinksCrossLinks].Text).Append(cLineBreak);
  if AWithComparison then
  begin
    ABuilder.Append(cTexts[TArchitectureReportText.ComparisonComparison].Text).Append(cLineBreak);
  end;
  ABuilder.Append(cLineBreak);
end;

procedure AppendMarkdownCentral(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mIndex: Integer;
  mItem: TOverviewUnit;
begin
  ABuilder.Append(cTexts[TArchitectureReportText.CentralUnits].Text).Append(cLineBreak).Append(cLineBreak);
  ABuilder.Append(cTexts[TArchitectureReportText.TotalDependentsUnitsThatAre].Text)
    .Append(cLineBreak).Append(cLineBreak);
  ABuilder.Append(cTexts[TArchitectureReportText.UnitSubsystemDirectDependentsTotal].Text).Append(cLineBreak);
  ABuilder.Append('|---|---|---|---|---|---|---|').Append(cLineBreak);
  for mIndex := 0 to High(AOverview.Central) do
  begin
    mItem := AOverview.Units[AOverview.Central[mIndex]];
    ABuilder.Append('| ').Append(mIndex + 1).Append(' | ').Append(Cell(mItem.Name)).Append(' | ')
      .Append(Cell(SubsystemName(AOverview, mItem.Subsystem))).Append(' | ').Append(mItem.Direct).Append(' | ')
      .Append(mItem.Total).Append(' | ').Append(mItem.Uses_).Append(' | ')
      .Append(TArchitectureAnalyzer.RoleCaption(mItem.Role)).Append(' |').Append(cLineBreak);
  end;
  ABuilder.Append(cLineBreak);
end;

procedure AppendMarkdownSubsystems(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mSubsystem: TOverviewSubsystem;
begin
  ABuilder.Append(cTexts[TArchitectureReportText.Subsystems].Text).Append(cLineBreak).Append(cLineBreak);
  ABuilder.Append(cTexts[TArchitectureReportText.SubsystemUnitsCentralUnitCohesion].Text)
    .Append(cLineBreak);
  ABuilder.Append('|---|---|---|---|---|---|').Append(cLineBreak);
  for mSubsystem in AOverview.Subsystems do
  begin
    ABuilder.Append('| ').Append(Cell(SubsystemCaption(mSubsystem))).Append(' | ').Append(Length(mSubsystem.Units))
      .Append(' | ');
    if mSubsystem.Central >= 0 then
    begin
      ABuilder.Append(Cell(AOverview.Units[mSubsystem.Central].Name));
    end;
    ABuilder.Append(' | ').Append(CohesionText(mSubsystem)).Append(' | ').Append(mSubsystem.InnerEdges)
      .Append(' | ').Append(mSubsystem.OuterEdges).Append(' |').Append(cLineBreak);
  end;
  ABuilder.Append(cLineBreak);
  if FoundationNote(AOverview) <> '' then
  begin
    ABuilder.Append(FoundationNote(AOverview)).Append(cLineBreak).Append(cLineBreak);
  end;
  // Wonach die Teilsysteme gebildet werden (#1368).
  if AOverview.ShowsAssignment then
  begin
    ABuilder.Append(TArchitectureReport.GroupingExplanation(AOverview.Grouping)).Append(cLineBreak).Append(cLineBreak);
  end;
  for mSubsystem in AOverview.Subsystems do
  begin
    ABuilder.Append('### ').Append(SubsystemCaption(mSubsystem)).Append(cLineBreak).Append(cLineBreak);
    ABuilder.Append(UnitNameList(AOverview, mSubsystem.Units, True)).Append(cLineBreak).Append(cLineBreak);
    if AOverview.ShowsAssignment then
    begin
      AppendCloseUnits(ABuilder, AOverview, mSubsystem);
    end;
  end;
end;

procedure AppendMarkdownOutliers(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mOutlier: TOverviewOutlier;
begin
  ABuilder.Append(cTexts[TArchitectureReportText.Outliers].Text).Append(cLineBreak).Append(cLineBreak);
  if Length(AOverview.Outliers) = 0 then
  begin
    ABuilder.Append('Keine.').Append(cLineBreak).Append(cLineBreak);
    Exit;
  end;
  ABuilder.Append(cTexts[TArchitectureReportText.UnitInSubsystemSuggestionReason].Text)
    .Append(cLineBreak);
  ABuilder.Append('|---|---|---|---|---|---|').Append(cLineBreak);
  for mOutlier in AOverview.Outliers do
  begin
    ABuilder.Append('| ').Append(Cell(AOverview.Units[mOutlier.Unit_].Name)).Append(' | ')
      .Append(Cell(SubsystemName(AOverview, AOverview.Units[mOutlier.Unit_].Subsystem))).Append(' | ')
      .Append(Cell(SubsystemName(AOverview, mOutlier.Suggested))).Append(' | ')
      .Append(TArchitectureReport.OutlierReasonCaption(mOutlier.Reason)).Append(' | ').Append(mOutlier.Inside)
      .Append(' | ').Append(mOutlier.Toward).Append(' |').Append(cLineBreak);
  end;
  ABuilder.Append(cLineBreak);
end;

procedure AppendMarkdownCycles(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mNumber: Integer;
  mCycle: TOverviewCycle;
  mEdge: TOverviewEdge;
begin
  ABuilder.Append(cTexts[TArchitectureReportText.Cycles].Text).Append(cLineBreak).Append(cLineBreak);
  if Length(AOverview.Cycles) = 0 then
  begin
    ABuilder.Append('Keine.').Append(cLineBreak).Append(cLineBreak);
  end;
  mNumber := 0;
  for mCycle in AOverview.Cycles do
  begin
    Inc(mNumber);
    ABuilder.Append('### ').Append(mNumber).Append('. ').Append(TArchitectureReport.CycleCaption(mCycle))
      .Append(cLineBreak).Append(cLineBreak);
    ABuilder.Append(TArchitectureReport.CyclePath(AOverview, mCycle)).Append(cLineBreak).Append(cLineBreak);
    for mEdge in mCycle.Edges do
    begin
      ABuilder.Append('- ').Append(TArchitectureReport.EdgeText(AOverview, mEdge)).Append(cLineBreak);
    end;
    if Length(mCycle.Component) > Length(mCycle.Units) then
    begin
      ABuilder.Append(cTexts[TArchitectureReportText.Component].Text).Append(UnitNameList(AOverview, mCycle.Component,
        False)).Append(cLineBreak);
    end;
    ABuilder.Append(cLineBreak);
  end;
end;

procedure AppendMarkdownCrossLinks(ABuilder: TStringBuilder; const AOverview: TArchitectureOverview);
var
  mLink: TOverviewCrossLink;
begin
  ABuilder.Append(cTexts[TArchitectureReportText.CrossLinks].Text).Append(cLineBreak).Append(cLineBreak);
  if Length(AOverview.CrossLinks) = 0 then
  begin
    ABuilder.Append('Keine.').Append(cLineBreak);
    Exit;
  end;
  ABuilder.Append(cTexts[TArchitectureReportText.FromToSectionSubsystemsReason].Text).Append(cLineBreak);
  ABuilder.Append('|---|---|---|---|---|---|').Append(cLineBreak);
  for mLink in AOverview.CrossLinks do
  begin
    ABuilder.Append('| ').Append(Cell(AOverview.Units[mLink.Edge.Source].Name)).Append(' | ')
      .Append(Cell(AOverview.Units[mLink.Edge.Target].Name)).Append(' | ')
      .Append(TArchitectureReport.SectionCaption(IsInterface(mLink.Edge))).Append(' | ')
      .Append(Cell(SubsystemName(AOverview, mLink.FromSubsystem) + ' → ' + SubsystemName(AOverview,
        mLink.ToSubsystem))).Append(' | ')
      .Append(TArchitectureReport.CrossReasonCaption(mLink.Reason)).Append(' (').Append(mLink.Forward)
      .Append(cTexts[TArchitectureReportText.Forward].Text).Append(mLink.Backward)
      .Append(cTexts[TArchitectureReportText.Back].Text)
      .Append(Cell(TArchitectureReport.LocationText(AOverview, mLink.Edge))).Append(' |').Append(cLineBreak);
  end;
end;

class function TArchitectureReport.MarkdownWith(const AOverview: TArchitectureOverview;
  AWithComparison: Boolean): string;
var
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    AppendMarkdownHeader(mBuilder, AOverview, AWithComparison);
    AppendMarkdownCentral(mBuilder, AOverview);
    AppendMarkdownSubsystems(mBuilder, AOverview);
    AppendMarkdownOutliers(mBuilder, AOverview);
    AppendMarkdownCycles(mBuilder, AOverview);
    AppendMarkdownCrossLinks(mBuilder, AOverview);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function HtmlEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

/// <summary>Vorlage der Karte in der Sprache der Servertexte (#1458).</summary>
function MapTemplate: string;
begin
  if TAtlasLocale.Language = TTextLanguage.English then
  begin
    Result := ArchitectureMapHtmlEn;
  end
  else
  begin
    Result := ArchitectureMapHtml;
  end;
end;

function Page(const ATitle, AData: string): string;
begin
  // In einem <script> darf "</" nicht vorkommen (schlösse das Element); \/ ist in JSON gleichwertig.
  Result := StringReplace(MapTemplate, '{{TITLE}}', HtmlEscape(ATitle), [rfReplaceAll]);
  Result := StringReplace(Result, '{{DATA}}', StringReplace(AData, '</', '<\/', [rfReplaceAll]), []);
end;

class function TArchitectureReport.Html(const AOverview: TArchitectureOverview): string;
begin
  Result := Page(AOverview.Title, Json(AOverview, TArchitectureLayouter.Compute(AOverview)));
end;

class function TArchitectureReport.Html(const AOverview: TArchitectureOverview;
  const AComparison: TArchitectureComparison; AFailOn: TArchitectureFailKinds): string;
begin
  Result := Page(AOverview.Title, Json(AOverview, TArchitectureLayouter.Compute(AOverview), AComparison, AFailOn));
end;

function IsHtmlFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.html') or (mExtension = '.htm');
end;

class function TArchitectureReport.ForFile(const AOverview: TArchitectureOverview; const AFileName: string): string;
begin
  if IsHtmlFile(AFileName) then
  begin
    Result := Html(AOverview);
  end
  else
  begin
    Result := Markdown(AOverview);
  end;
end;

class function TArchitectureReport.ForFile(const AOverview: TArchitectureOverview; const AFileName: string;
  const AComparison: TArchitectureComparison; AFailOn: TArchitectureFailKinds): string;
begin
  if IsHtmlFile(AFileName) then
  begin
    Result := Html(AOverview, AComparison, AFailOn);
  end
  else
  begin
    Result := Markdown(AOverview, AComparison);
  end;
end;

function Limited(const AText: string; ACount, ALimit: Integer): string;
begin
  Result := AText;
  if ACount > ALimit then
  begin
    Result := Result + cTexts[TArchitectureReportText.MoreInTotal].Fmt([IntToStr(ACount - ALimit), IntToStr(ACount)]) +
      cLineBreak;
  end;
end;

function OverviewText(const AOverview: TArchitectureOverview; ALimit: Integer): string;
var
  mIndex: Integer;
  mItem: TOverviewUnit;
  mSubsystem: TOverviewSubsystem;
begin
  Result := cLineBreak + cTexts[TArchitectureReportText.CentralUnits2].Text + cLineBreak;
  for mIndex := 0 to Min(High(AOverview.Central), 4) do
  begin
    mItem := AOverview.Units[AOverview.Central[mIndex]];
    Result := Result + cTexts[TArchitectureReportText.TotalDependents].Fmt([mItem.Name, IntToStr(mItem.Total)]) +
      cLineBreak;
  end;
  Result := Result + cTexts[TArchitectureReportText.Subsystems2].Text + cLineBreak;
  for mIndex := 0 to Min(High(AOverview.Subsystems), ALimit - 1) do
  begin
    mSubsystem := AOverview.Subsystems[mIndex];
    Result := Result + cTexts[TArchitectureReportText.UnitsCohesion].Fmt([SubsystemCaption(mSubsystem),
      IntToStr(Length(mSubsystem.Units))]) + CohesionText(mSubsystem) + cLineBreak;
  end;
  Result := Limited(Result, Length(AOverview.Subsystems), ALimit);
  Result := Result + cTexts[TArchitectureReportText.MoreSectionsCentralSubsystemsCycles].Text;
end;

function CentralText(const AOverview: TArchitectureOverview; ALimit: Integer): string;
var
  mIndex: Integer;
  mItem: TOverviewUnit;
  mLine: string;
begin
  Result := cLineBreak + cTexts[TArchitectureReportText.UnitSubsystemDirectTotalUses].Text + cLineBreak;
  for mIndex := 0 to Min(High(AOverview.Central), ALimit - 1) do
  begin
    mItem := AOverview.Units[AOverview.Central[mIndex]];
    mLine := mItem.Name + ' | ' + SubsystemName(AOverview, mItem.Subsystem) + ' | ' + IntToStr(mItem.Direct) +
      ' | ' + IntToStr(mItem.Total) + ' | ' + IntToStr(mItem.Uses_);
    if mItem.Role <> TOverviewUnitRole.None then
    begin
      mLine := mLine + ' | ' + TArchitectureAnalyzer.RoleCaption(mItem.Role);
    end;
    Result := Result + mLine + cLineBreak;
  end;
  Result := Limited(Result, Length(AOverview.Central), ALimit);
end;

/// <summary>Höchstens zehn Unit-Namen, dahinter die Gesamtzahl.</summary>
function ShortUnitList(const AOverview: TArchitectureOverview; const AMembers: TArray<Integer>): string;
begin
  Result := UnitNameList(AOverview, Copy(AMembers, 0, 10), False);
  if Length(AMembers) > 10 then
  begin
    Result := Result + ' … (' + IntToStr(Length(AMembers)) + ')';
  end;
end;

function OutliersText(const AOverview: TArchitectureOverview; ALimit: Integer): string;
var
  mIndex: Integer;
  mOutlier: TOverviewOutlier;
begin
  Result := '';
  if Length(AOverview.Outliers) = 0 then
  begin
    Exit;
  end;
  Result := cTexts[TArchitectureReportText.Outliers2].Text + cLineBreak;
  for mIndex := 0 to Min(High(AOverview.Outliers), ALimit - 1) do
  begin
    mOutlier := AOverview.Outliers[mIndex];
    Result := Result + cTexts[TArchitectureReportText.InSuggestion].Fmt([AOverview.Units[mOutlier.Unit_].Name,
      SubsystemName(AOverview, AOverview.Units[mOutlier.Unit_].Subsystem), SubsystemName(AOverview,
      mOutlier.Suggested), TArchitectureReport.OutlierReasonCaption(mOutlier.Reason)]) + cLineBreak;
  end;
  Result := Limited(Result, Length(AOverview.Outliers), ALimit);
end;

function SubsystemsText(const AOverview: TArchitectureOverview; ALimit: Integer): string;
var
  mIndex: Integer;
  mSubsystem: TOverviewSubsystem;
begin
  Result := cLineBreak;
  for mIndex := 0 to Min(High(AOverview.Subsystems), ALimit - 1) do
  begin
    mSubsystem := AOverview.Subsystems[mIndex];
    Result := Result + SubsystemCaption(mSubsystem) + cTexts[TArchitectureReportText.UnitsCohesion2].Fmt([
      IntToStr(Length(mSubsystem.Units)), CohesionText(mSubsystem), cLineBreak]) +
      ShortUnitList(AOverview, mSubsystem.Units) + cLineBreak;
  end;
  Result := Limited(Result, Length(AOverview.Subsystems), ALimit);
  if FoundationNote(AOverview) <> '' then
  begin
    Result := Result + FoundationNote(AOverview) + cLineBreak;
  end;
  Result := Result + OutliersText(AOverview, ALimit);
end;

function CyclesText(const AOverview: TArchitectureOverview; ALimit: Integer): string;
var
  mIndex, mMember: Integer;
  mCycle: TOverviewCycle;
begin
  Result := cLineBreak;
  if Length(AOverview.Cycles) = 0 then
  begin
    Result := Result + cTexts[TArchitectureReportText.NoCycles].Text + cLineBreak;
  end;
  for mIndex := 0 to Min(High(AOverview.Cycles), ALimit - 1) do
  begin
    mCycle := AOverview.Cycles[mIndex];
    Result := Result + IntToStr(mIndex + 1) + '. ' + TArchitectureReport.CycleCaption(mCycle) + ': ' +
      TArchitectureReport.CyclePath(AOverview, mCycle) + cLineBreak;
    for mMember := 0 to High(mCycle.Edges) do
    begin
      Result := Result + '  ' + TArchitectureReport.EdgeText(AOverview, mCycle.Edges[mMember]) + cLineBreak;
    end;
  end;
  Result := Limited(Result, Length(AOverview.Cycles), ALimit);
end;

function CrossLinksText(const AOverview: TArchitectureOverview; ALimit: Integer): string;
var
  mIndex: Integer;
  mLink: TOverviewCrossLink;
begin
  Result := cLineBreak;
  if Length(AOverview.CrossLinks) = 0 then
  begin
    Result := Result + cTexts[TArchitectureReportText.NoCrossLinks].Text + cLineBreak;
  end;
  for mIndex := 0 to Min(High(AOverview.CrossLinks), ALimit - 1) do
  begin
    mLink := AOverview.CrossLinks[mIndex];
    Result := Result + TArchitectureReport.EdgeText(AOverview, mLink.Edge) +
      cTexts[TArchitectureReportText.ThereBack].Fmt([SubsystemName(AOverview, mLink.FromSubsystem),
      SubsystemName(AOverview, mLink.ToSubsystem), TArchitectureReport.CrossReasonCaption(mLink.Reason),
      IntToStr(mLink.Forward), IntToStr(mLink.Backward)]) + cLineBreak;
  end;
  Result := Limited(Result, Length(AOverview.CrossLinks), ALimit);
end;

class function TArchitectureReport.Text(const AOverview: TArchitectureOverview; ASection: TArchitectureSection;
  ALimit: Integer): string;
var
  mLimit: Integer;
begin
  mLimit := Max(ALimit, 1);
  Result := cTexts[TArchitectureReportText.Architecture2].Fmt([AOverview.Title, ScopeText(AOverview)]) + cLineBreak +
    Counts(AOverview) +
    cLineBreak;
  if AOverview.IsAligned then
  begin
    Result := Result + AlignedText(AOverview) + cLineBreak;
  end;
  case ASection of
    TArchitectureSection.Overview:
      Result := Result + OverviewText(AOverview, mLimit);
    TArchitectureSection.Central:
      Result := Result + CentralText(AOverview, mLimit);
    TArchitectureSection.Subsystems:
      Result := Result + SubsystemsText(AOverview, mLimit);
    TArchitectureSection.Cycles:
      Result := Result + CyclesText(AOverview, mLimit);
    TArchitectureSection.CrossLinks:
      Result := Result + CrossLinksText(AOverview, mLimit);
  end;
end;

/// <summary>Zyklen, Querverbindungen und Ausreißer-Hinweis aus dem Steckbrief einer Unit.</summary>
function ProfileFindings(const AOverview: TArchitectureOverview; const AProfile: TOverviewProfile): string;
var
  mItem: Integer;
  mOutlier: TOverviewOutlier;
begin
  Result := '';
  if Length(AProfile.Cycles) = 0 then
  begin
    Result := cTexts[TArchitectureReportText.CyclesNone].Text + cLineBreak;
  end;
  for mItem in AProfile.Cycles do
  begin
    Result := Result + TArchitectureReport.CycleCaption(AOverview.Cycles[mItem]) + ': ' +
      TArchitectureReport.CyclePath(AOverview, AOverview.Cycles[mItem]) + cLineBreak;
  end;
  for mItem in AProfile.CrossLinks do
  begin
    Result := Result + cTexts[TArchitectureReportText.CrossLink].Text + TArchitectureReport.EdgeText(AOverview,
      AOverview.CrossLinks[mItem].Edge) +
      cLineBreak;
  end;
  if AProfile.Outlier >= 0 then
  begin
    mOutlier := AOverview.Outliers[AProfile.Outlier];
    Result := Result + cTexts[TArchitectureReportText.OutlierBelongsRatherToEdges].Fmt([SubsystemName(AOverview,
      mOutlier.Suggested), TArchitectureReport.OutlierReasonCaption(mOutlier.Reason), IntToStr(mOutlier.Inside),
      IntToStr(mOutlier.Toward)]) + cLineBreak;
  end;
end;

class function TArchitectureReport.UnitText(const AOverview: TArchitectureOverview; const AUnitName: string): string;
var
  mIndex: Integer;
  mProfile: TOverviewProfile;
  mUnit: TOverviewUnit;
begin
  mIndex := AOverview.IndexOf(AUnitName);
  if mIndex < 0 then
  begin
    Exit(cTexts[TArchitectureReportText.UnitIsNotInThe].Fmt([AUnitName]));
  end;
  mUnit := AOverview.Units[mIndex];
  mProfile := AOverview.Profile(mIndex);
  Result := mUnit.Name + cTexts[TArchitectureReportText.SSubsystemSdirectDependentsTotalDependents].Fmt([
    AOverview.RelativePath(mUnit.FileName), cLineBreak, SubsystemName(AOverview, mUnit.Subsystem), cLineBreak,
    IntToStr(mUnit.Direct), IntToStr(mUnit.Total)]) +
    IntToStr(mUnit.Uses_);
  if mUnit.Role <> TOverviewUnitRole.None then
  begin
    Result := Result + ' · ' + TArchitectureAnalyzer.RoleCaption(mUnit.Role);
  end;
  Result := Result + cLineBreak;
  Result := Result + cTexts[TArchitectureReportText.UsesText].Text + UnitNameList(AOverview, mProfile.DependsOn,
    False) + cLineBreak;
  Result := Result + cTexts[TArchitectureReportText.UsedBy].Text + UnitNameList(AOverview, mProfile.UsedBy, False) +
    cLineBreak;
  Result := Result + ProfileFindings(AOverview, mProfile);
  Result := Result + AssignmentText(AOverview, mIndex);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Architecture.Report', cTexts);

end.
