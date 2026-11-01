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
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Comparison;

type
  TArchitectureSection = (Overview, Central, Subsystems, Cycles, CrossLinks);

  TArchitectureReport = class
  public const
    Format = 1;
    /// <summary>Höchstzahl der Einträge je Liste in der MCP-Ausgabe.</summary>
    TextLimit = 30;
  public
    class function SectionName(ASection: TArchitectureSection): string; static;
    /// <summary>overview, central, subsystems, cycles, crossLinks (ohne Groß-/Kleinschreibung); '' = overview.</summary>
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
    /// <summary>Eigenständige HTML-Seite mit eingebetteten Daten und Skript (offline, keine externen Verweise).</summary>
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
    /// <summary>Kompakter Text eines Abschnitts für get_architecture; Listen auf ALimit gekürzt mit Gesamtzahl.</summary>
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
  Atlas.Common.Metrics.Report;

const
  LineBreak = #13#10;

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
  Index: Integer;
begin
  Result := '[';
  for Index := 0 to High(AValues) do
  begin
    if Index > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + IntToStr(AValues[Index]);
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
    Result := Result + ' (Teil von ' + ASubsystem.Parent + ')';
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
      Result := TArchitectureAnalyzer.FoundationName + ': ' + TArchitectureAnalyzer.FoundationRule +
        '; Kanten dorthin zählen nicht als Querverbindung und nicht im Zusammenhalt.';
    end;
  end;
end;

function CreatedText(const AOverview: TArchitectureOverview): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn', AOverview.Created, TFormatSettings.Invariant);
end;

function InterfaceCycleCount(const AOverview: TArchitectureOverview): Integer;
var
  Cycle: TOverviewCycle;
begin
  Result := 0;
  for Cycle in AOverview.Cycles do
  begin
    if Cycle.InterfaceOnly then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>"Units: 12 · uses-Kanten: 17 · …" für Kopf und MCP.</summary>
function Counts(const AOverview: TArchitectureOverview): string;
begin
  Result := 'Units: ' + IntToStr(Length(AOverview.Units)) + ' · uses-Kanten: ' + IntToStr(AOverview.EdgeCount) +
    ' · Teilsysteme: ' + IntToStr(Length(AOverview.Subsystems)) + ' · Zyklen: ' + IntToStr(Length(AOverview.Cycles));
  if InterfaceCycleCount(AOverview) > 0 then
  begin
    Result := Result + ' (davon nur interface: ' + IntToStr(InterfaceCycleCount(AOverview)) + ')';
  end;
  Result := Result + ' · Querverbindungen: ' + IntToStr(Length(AOverview.CrossLinks)) + ' · Ausreißer: ' +
    IntToStr(Length(AOverview.Outliers));
end;

function ScopeText(const AOverview: TArchitectureOverview): string;
begin
  if SameText(AOverview.Scope, 'project') then
  begin
    Result := 'Projekt';
  end
  else
  begin
    Result := 'Projektgruppe';
  end;
  if AOverview.IncludeLibrary then
  begin
    Result := Result + ', mit Bibliotheks-Units';
  end
  else
  begin
    Result := Result + ', ohne Bibliotheks-Units';
  end;
  if Length(AOverview.Excludes) > 0 then
  begin
    Result := Result + ', ausgeschlossen: ' + string.Join(', ', AOverview.Excludes);
  end;
  // Feinheit der Teilsysteme (#1366) nur, wenn sie von 1,0 abweicht.
  if AOverview.Grouping.ResolutionChanged then
  begin
    Result := Result + ', Feinheit γ = ' + TArchitectureGrouping.ResolutionText(AOverview.Grouping.Clamped.Resolution);
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
  Result := 'Teilsysteme an Stand vom ' + FormatDateTime('yyyy-mm-dd hh:nn', AOverview.AlignedAt,
    TFormatSettings.Invariant) + ' angeglichen (';
  if AOverview.AlignedSource = TArchitectureAnalyzer.AlignedBaseline then
  begin
    Result := Result + 'architecture.baseline';
  end
  else
  begin
    Result := Result + 'zuletzt berechneter Stand';
  end;
  if AOverview.AlignedKept = 1 then
  begin
    Result := Result + '; 1 Teilsystem behält Farbe und Namen)';
  end
  else
  begin
    Result := Result + '; ' + IntToStr(AOverview.AlignedKept) + ' Teilsysteme behalten Farbe und Namen)';
  end;
end;

class function TArchitectureReport.GroupingExplanation(const AGrouping: TArchitectureGrouping): string;
var
  mGrouping: TArchitectureGrouping;
  mSplit: string;
begin
  mGrouping := AGrouping.Clamped;
  Result := 'Atlas bildet die Teilsysteme aus den uses-Kanten zwischen den Units, ein- und ausgehende zusammen. ' +
    'Eine Kante im interface wiegt ' + IntToStr(TArchitectureAnalyzer.InterfaceWeight) + ', eine im ' +
    'implementation-Teil ' + IntToStr(TArchitectureAnalyzer.ImplementationWeight) + '. Das Louvain-Verfahren ' +
    'fasst Units zusammen, die untereinander mehr gewichtete Kanten haben als nach außen; eine Unit liegt darum ' +
    'meist dort, wohin die meisten ihrer gewichteten Kanten gehen, und gilt als knapp zugeordnet, wenn ein anderes ' +
    'Teilsystem mindestens ' + IntToStr(TArchitectureAnalyzer.ClosePercent) + ' Prozent davon erreicht.';
  Result := Result + ' Einstellungen: Feinheit ' + TArchitectureGrouping.ResolutionText(mGrouping.Resolution);
  mSplit := '';
  if mGrouping.MaxShare > 0 then
  begin
    mSplit := 'ab ' + IntToStr(Round(mGrouping.MaxShare * 100)) + ' Prozent aller Units';
  end;
  if mGrouping.MinCohesion > 0 then
  begin
    if mSplit <> '' then
    begin
      mSplit := mSplit + ' oder ';
    end;
    mSplit := mSplit + 'unter Zusammenhalt ' + TArchitectureGrouping.ResolutionText(mGrouping.MinCohesion) + ' (ab ' +
      IntToStr(TArchitectureGrouping.LooseMinUnits) + ' Units)';
  end;
  if mSplit = '' then
  begin
    Result := Result + ' · nicht nachteilen';
  end
  else
  begin
    Result := Result + ' · nachteilen ' + mSplit;
  end;
  case mGrouping.Foundations of
    TArchitectureFoundations.Group:
      Result := Result + ' · Fundamente mitgruppiert';
    TArchitectureFoundations.Attach:
      Result := Result + ' · Fundamente angehängt';
  else
    Result := Result + ' · Fundamente getrennt (Kanten dorthin zählen nicht)';
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
    Result := mRival + ' erreicht ' + IntToStr(AAssignment.RivalSum) + ' von ' +
      IntToStr(AAssignment.OwnSum) + ', 1 Kante fehlt zum Wechsel';
  end
  else if AAssignment.Missing > 1 then
  begin
    Result := mRival + ' erreicht ' + IntToStr(AAssignment.RivalSum) + ' von ' +
      IntToStr(AAssignment.OwnSum) + ', ' + IntToStr(AAssignment.Missing) + ' Kanten fehlen zum Wechsel';
  end
  else
  begin
    Result := mRival + ' hat schon ' + IntToStr(AAssignment.RivalSum) + ' gewichtete Kanten, das ' +
      'eigene Teilsystem ' + IntToStr(AAssignment.OwnSum) + ' (Louvain wertet das ganze Teilsystem)';
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
  Result := 'Zuordnung (Kanten je Teilsystem, interface ' + IntToStr(TArchitectureAnalyzer.InterfaceWeight) +
    ', implementation ' + IntToStr(TArchitectureAnalyzer.ImplementationWeight) + '):' + LineBreak +
    '  Teilsystem | interface | impl. | Summe' + LineBreak;
  for mIndex := 0 to High(mAssignment.Rows) do
  begin
    mRow := mAssignment.Rows[mIndex];
    mLine := '  ' + SubsystemName(AOverview, mRow.Subsystem);
    if mIndex = mAssignment.Own then
    begin
      mLine := mLine + ' (eigenes)';
    end;
    mLine := mLine + ' | ' + IntToStr(mRow.Interfaces) + ' | ' + IntToStr(mRow.Implementations) + ' | ' +
      IntToStr(mRow.Sum);
    if not mRow.Counts then
    begin
      mLine := mLine + ' (zählt nicht)';
    end;
    Result := Result + mLine + LineBreak;
  end;
  if mAssignment.Close then
  begin
    Result := Result + '  knapp: ' + CloseText(AOverview, mAssignment) + LineBreak;
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
  Section: TArchitectureSection;
begin
  ASection := TArchitectureSection.Overview;
  if Trim(AText) = '' then
  begin
    Exit(True);
  end;
  for Section := Low(TArchitectureSection) to High(TArchitectureSection) do
  begin
    if SameText(Trim(AText), SectionName(Section)) then
    begin
      ASection := Section;
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
    Result := 'selten';
  end
  else
  begin
    Result := 'gegen die Hauptrichtung';
  end;
end;

class function TArchitectureReport.OutlierReasonCaption(AReason: TOverviewOutlierReason): string;
begin
  if AReason = TOverviewOutlierReason.Namespace then
  begin
    Result := 'Namensraum passt zu einem anderen Teilsystem';
  end
  else
  begin
    Result := 'mehr Kanten in ein anderes Teilsystem';
  end;
end;

class function TArchitectureReport.CycleCaption(const ACycle: TOverviewCycle): string;
begin
  if ACycle.InterfaceOnly then
  begin
    Result := 'Zyklus nur über interface (Compilerfehler F2047)';
  end
  else
  begin
    Result := 'Zyklus über implementation';
  end;
end;

class function TArchitectureReport.CyclePath(const AOverview: TArchitectureOverview;
  const ACycle: TOverviewCycle): string;
var
  Edge: TOverviewEdge;
begin
  Result := '';
  for Edge in ACycle.Edges do
  begin
    if Result = '' then
    begin
      Result := AOverview.Units[Edge.Source].Name;
    end;
    Result := Result + ' → ' + AOverview.Units[Edge.Target].Name;
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
  Location: string;
begin
  Result := AOverview.Units[AEdge.Source].Name + ' → ' + AOverview.Units[AEdge.Target].Name + ' (' +
    SectionCaption(IsInterface(AEdge));
  Location := LocationText(AOverview, AEdge);
  if Location <> '' then
  begin
    Result := Result + ', ' + Location;
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
  Result := JsonWith(AOverview, ALayout, ',' + LineBreak + '"comparison":' + TArchitectureComparer.Json(AComparison,
    AFailOn));
end;

/// <summary>Daten der Übersicht; AExtra steht vor der schließenden Klammer (z. B. ',"comparison":…').</summary>
class function TArchitectureReport.JsonWith(const AOverview: TArchitectureOverview; const ALayout: TArchitectureLayout;
  const AExtra: string): string;
var
  Builder: TStringBuilder;
  Index, Inner: Integer;
  Item: TOverviewUnit;
  Edge: TOverviewEdge;
  Subsystem: TOverviewSubsystem;
  Outlier: TOverviewOutlier;
  Cycle: TOverviewCycle;
  Link: TOverviewCrossLink;
  Kind: string;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('{"format":').Append(Format).Append(',"title":').Append(JsonText(AOverview.Title))
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
    for Index := 0 to High(AOverview.Excludes) do
    begin
      if Index > 0 then
      begin
        Builder.Append(',');
      end;
      Builder.Append(JsonText(AOverview.Excludes[Index]));
    end;
    Builder.Append('],"summary":{"units":').Append(Length(AOverview.Units))
      .Append(',"edges":').Append(AOverview.EdgeCount)
      .Append(',"subsystems":').Append(Length(AOverview.Subsystems))
      .Append(',"cycles":').Append(Length(AOverview.Cycles))
      .Append(',"interfaceCycles":').Append(InterfaceCycleCount(AOverview))
      .Append(',"crossLinks":').Append(Length(AOverview.CrossLinks))
      .Append(',"outliers":').Append(Length(AOverview.Outliers)).Append('}');
    if AOverview.ShowsAssignment then
    begin
      Builder.Append(',"explanation":').Append(JsonText(GroupingExplanation(AOverview.Grouping)));
    end;
    if AOverview.IsAligned then
    begin
      Builder.Append(',"aligned":{"source":').Append(JsonText(AOverview.AlignedSource))
        .Append(',"at":')
        .Append(JsonText(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', AOverview.AlignedAt, TFormatSettings.Invariant)))
        .Append(',"kept":').Append(AOverview.AlignedKept).Append('}');
    end;
    Builder.Append(',"units":[');
    for Index := 0 to High(AOverview.Units) do
    begin
      Item := AOverview.Units[Index];
      if Index > 0 then
      begin
        Builder.Append(',');
      end;
      Builder.Append(LineBreak).Append('{"name":').Append(JsonText(Item.Name))
        .Append(',"file":').Append(JsonText(AOverview.RelativePath(Item.FileName)))
        .Append(',"subsystem":').Append(Item.Subsystem)
        .Append(',"direct":').Append(Item.Direct)
        .Append(',"total":').Append(Item.Total)
        .Append(',"uses":').Append(Item.Uses_)
        .Append(',"role":').Append(JsonText(RoleName(Item.Role)))
        .Append(',"library":').Append(JsonBool(Item.Library_));
      if Index < Length(ALayout.Units) then
      begin
        Builder.Append(',"x":').Append(JsonNumber(ALayout.Units[Index].X))
          .Append(',"y":').Append(JsonNumber(ALayout.Units[Index].Y));
      end;
      if AOverview.ShowsAssignment then
      begin
        AppendAssignment(Builder, AOverview.Assignments[Index]);
      end;
      Builder.Append('}');
    end;
    Builder.Append('],"edges":[');
    for Index := 0 to High(AOverview.Edges) do
    begin
      Edge := AOverview.Edges[Index];
      if Index > 0 then
      begin
        Builder.Append(',');
      end;
      if Index mod 20 = 0 then
      begin
        Builder.Append(LineBreak);
      end;
      if IsInterface(Edge) then
      begin
        Kind := 'i';
      end
      else
      begin
        Kind := 'm';
      end;
      Builder.Append('[').Append(Edge.Source).Append(',').Append(Edge.Target).Append(',"').Append(Kind).Append('"]');
    end;
    Builder.Append('],"central":').Append(JsonInts(AOverview.Central));
    Builder.Append(',"subsystems":[');
    for Index := 0 to High(AOverview.Subsystems) do
    begin
      Subsystem := AOverview.Subsystems[Index];
      if Index > 0 then
      begin
        Builder.Append(',');
      end;
      Builder.Append(LineBreak).Append('{"name":').Append(JsonText(Subsystem.Name))
        .Append(',"units":').Append(JsonInts(Subsystem.Units))
        .Append(',"central":').Append(Subsystem.Central)
        .Append(',"inner":').Append(Subsystem.InnerEdges)
        .Append(',"outer":').Append(Subsystem.OuterEdges)
        .Append(',"cohesion":').Append(JsonNumber(Subsystem.Cohesion))
        .Append(',"isolated":').Append(JsonBool(Subsystem.Isolated))
        .Append(',"color":').Append(Subsystem.ColorSlot)
        .Append(',"shade":').Append(Subsystem.Shade);
      if Subsystem.Foundation then
      begin
        Builder.Append(',"foundation":true');
      end;
      if Subsystem.Parent <> '' then
      begin
        Builder.Append(',"parent":').Append(JsonText(Subsystem.Parent));
      end;
      if Index < Length(ALayout.Subsystems) then
      begin
        Builder.Append(',"x":').Append(JsonNumber(ALayout.Subsystems[Index].X))
          .Append(',"y":').Append(JsonNumber(ALayout.Subsystems[Index].Y))
          .Append(',"r":').Append(JsonNumber(ALayout.Subsystems[Index].Radius));
      end;
      Builder.Append('}');
    end;
    Builder.Append('],"outliers":[');
    for Index := 0 to High(AOverview.Outliers) do
    begin
      Outlier := AOverview.Outliers[Index];
      if Index > 0 then
      begin
        Builder.Append(',');
      end;
      Builder.Append(LineBreak).Append('{"unit":').Append(Outlier.Unit_)
        .Append(',"suggested":').Append(Outlier.Suggested)
        .Append(',"reason":');
      if Outlier.Reason = TOverviewOutlierReason.Namespace then
      begin
        Builder.Append('"namespace"');
      end
      else
      begin
        Builder.Append('"edges"');
      end;
      Builder.Append(',"inside":').Append(Outlier.Inside).Append(',"toward":').Append(Outlier.Toward).Append('}');
    end;
    Builder.Append('],"cycles":[');
    for Index := 0 to High(AOverview.Cycles) do
    begin
      Cycle := AOverview.Cycles[Index];
      if Index > 0 then
      begin
        Builder.Append(',');
      end;
      Builder.Append(LineBreak).Append('{"interfaceOnly":').Append(JsonBool(Cycle.InterfaceOnly))
        .Append(',"units":').Append(JsonInts(Cycle.Units))
        .Append(',"component":').Append(JsonInts(Cycle.Component))
        .Append(',"edges":[');
      for Inner := 0 to High(Cycle.Edges) do
      begin
        if Inner > 0 then
        begin
          Builder.Append(',');
        end;
        Builder.Append('{').Append(EdgeJson(AOverview, Cycle.Edges[Inner])).Append('}');
      end;
      Builder.Append(']}');
    end;
    Builder.Append('],"crossLinks":[');
    for Index := 0 to High(AOverview.CrossLinks) do
    begin
      Link := AOverview.CrossLinks[Index];
      if Index > 0 then
      begin
        Builder.Append(',');
      end;
      Builder.Append(LineBreak).Append('{').Append(EdgeJson(AOverview, Link.Edge))
        .Append(',"from":').Append(Link.FromSubsystem)
        .Append(',"to":').Append(Link.ToSubsystem)
        .Append(',"reason":');
      if Link.Reason = TOverviewCrossReason.Rare then
      begin
        Builder.Append('"rare"');
      end
      else
      begin
        Builder.Append('"againstDirection"');
      end;
      Builder.Append(',"forward":').Append(Link.Forward).Append(',"backward":').Append(Link.Backward).Append('}');
    end;
    Builder.Append(']').Append(AExtra).Append('}');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TArchitectureReport.Markdown(const AOverview: TArchitectureOverview): string;
begin
  Result := MarkdownWith(AOverview, False);
end;

class function TArchitectureReport.Markdown(const AOverview: TArchitectureOverview;
  const AComparison: TArchitectureComparison): string;
begin
  Result := MarkdownWith(AOverview, True) + LineBreak + TArchitectureComparer.Markdown(AComparison);
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
      ABuilder.Append('Knapp zugeordnet:').Append(LineBreak).Append(LineBreak);
    end;
    mFirst := False;
    ABuilder.Append('- ').Append(AOverview.Units[mMember].Name).Append(': ')
      .Append(TArchitectureReport.CloseText(AOverview, mAssignment)).Append(LineBreak);
  end;
  if not mFirst then
  begin
    ABuilder.Append(LineBreak);
  end;
end;

class function TArchitectureReport.MarkdownWith(const AOverview: TArchitectureOverview;
  AWithComparison: Boolean): string;
var
  Builder: TStringBuilder;
  Index, Member, Number: Integer;
  Item: TOverviewUnit;
  Subsystem: TOverviewSubsystem;
  Outlier: TOverviewOutlier;
  Cycle: TOverviewCycle;
  Edge: TOverviewEdge;
  Link: TOverviewCrossLink;
  Location, Names: string;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('# Architektur: ').Append(AOverview.Title).Append(LineBreak).Append(LineBreak);
    Builder.Append('Stand ').Append(CreatedText(AOverview)).Append(' · Index-Generation ')
      .Append(IntToStr(AOverview.Generation)).Append(' · Rechendauer ').Append(IntToStr(AOverview.DurationMs))
      .Append(' ms').Append(LineBreak).Append(LineBreak);
    Builder.Append(Counts(AOverview)).Append(LineBreak).Append(LineBreak);
    Builder.Append('Umfang: ').Append(ScopeText(AOverview)).Append(LineBreak).Append(LineBreak);
    if AOverview.IsAligned then
    begin
      Builder.Append(AlignedText(AOverview)).Append(LineBreak).Append(LineBreak);
    end;
    Builder.Append('- [Zentrale Units](#zentrale-units)').Append(LineBreak)
      .Append('- [Teilsysteme](#teilsysteme)').Append(LineBreak)
      .Append('- [Ausreißer](#ausreißer)').Append(LineBreak)
      .Append('- [Zyklen](#zyklen)').Append(LineBreak)
      .Append('- [Querverbindungen](#querverbindungen)').Append(LineBreak);
    if AWithComparison then
    begin
      Builder.Append('- [Vergleich](#vergleich)').Append(LineBreak);
    end;
    Builder.Append(LineBreak);

    Builder.Append('## Zentrale Units').Append(LineBreak).Append(LineBreak);
    Builder.Append('„gesamt abhängig“: Units, die neu übersetzt werden, wenn sich das interface der Unit ändert.')
      .Append(LineBreak).Append(LineBreak);
    Builder.Append('| # | Unit | Teilsystem | direkt abhängig | gesamt abhängig | verwendet | Rolle |').Append(LineBreak);
    Builder.Append('|---|---|---|---|---|---|---|').Append(LineBreak);
    for Index := 0 to High(AOverview.Central) do
    begin
      Item := AOverview.Units[AOverview.Central[Index]];
      Builder.Append('| ').Append(Index + 1).Append(' | ').Append(Cell(Item.Name)).Append(' | ')
        .Append(Cell(SubsystemName(AOverview, Item.Subsystem))).Append(' | ').Append(Item.Direct).Append(' | ')
        .Append(Item.Total).Append(' | ').Append(Item.Uses_).Append(' | ')
        .Append(TArchitectureAnalyzer.RoleCaption(Item.Role)).Append(' |').Append(LineBreak);
    end;
    Builder.Append(LineBreak);

    Builder.Append('## Teilsysteme').Append(LineBreak).Append(LineBreak);
    Builder.Append('| Teilsystem | Units | zentrale Unit | Zusammenhalt | Kanten innen | Kanten nach außen |')
      .Append(LineBreak);
    Builder.Append('|---|---|---|---|---|---|').Append(LineBreak);
    for Subsystem in AOverview.Subsystems do
    begin
      Builder.Append('| ').Append(Cell(SubsystemCaption(Subsystem))).Append(' | ').Append(Length(Subsystem.Units))
        .Append(' | ');
      if Subsystem.Central >= 0 then
      begin
        Builder.Append(Cell(AOverview.Units[Subsystem.Central].Name));
      end;
      Builder.Append(' | ').Append(CohesionText(Subsystem)).Append(' | ').Append(Subsystem.InnerEdges)
        .Append(' | ').Append(Subsystem.OuterEdges).Append(' |').Append(LineBreak);
    end;
    Builder.Append(LineBreak);
    if FoundationNote(AOverview) <> '' then
    begin
      Builder.Append(FoundationNote(AOverview)).Append(LineBreak).Append(LineBreak);
    end;
    // Wonach die Teilsysteme gebildet werden (#1368).
    if AOverview.ShowsAssignment then
    begin
      Builder.Append(GroupingExplanation(AOverview.Grouping)).Append(LineBreak).Append(LineBreak);
    end;
    for Index := 0 to High(AOverview.Subsystems) do
    begin
      Subsystem := AOverview.Subsystems[Index];
      Builder.Append('### ').Append(SubsystemCaption(Subsystem)).Append(LineBreak).Append(LineBreak);
      Names := '';
      for Member in Subsystem.Units do
      begin
        if Names <> '' then
        begin
          Names := Names + ', ';
        end;
        Names := Names + AOverview.Units[Member].Name;
        if AOverview.Profile(Member).Outlier >= 0 then
        begin
          Names := Names + ' (Ausreißer)';
        end;
      end;
      Builder.Append(Names).Append(LineBreak).Append(LineBreak);
      if AOverview.ShowsAssignment then
      begin
        AppendCloseUnits(Builder, AOverview, Subsystem);
      end;
    end;

    Builder.Append('## Ausreißer').Append(LineBreak).Append(LineBreak);
    if Length(AOverview.Outliers) = 0 then
    begin
      Builder.Append('Keine.').Append(LineBreak).Append(LineBreak);
    end
    else
    begin
      Builder.Append('| Unit | in Teilsystem | Vorschlag | Grund | Kanten im eigenen | Kanten zum Vorschlag |')
        .Append(LineBreak);
      Builder.Append('|---|---|---|---|---|---|').Append(LineBreak);
      for Outlier in AOverview.Outliers do
      begin
        Builder.Append('| ').Append(Cell(AOverview.Units[Outlier.Unit_].Name)).Append(' | ')
          .Append(Cell(SubsystemName(AOverview, AOverview.Units[Outlier.Unit_].Subsystem))).Append(' | ')
          .Append(Cell(SubsystemName(AOverview, Outlier.Suggested))).Append(' | ')
          .Append(OutlierReasonCaption(Outlier.Reason)).Append(' | ').Append(Outlier.Inside).Append(' | ')
          .Append(Outlier.Toward).Append(' |').Append(LineBreak);
      end;
      Builder.Append(LineBreak);
    end;

    Builder.Append('## Zyklen').Append(LineBreak).Append(LineBreak);
    if Length(AOverview.Cycles) = 0 then
    begin
      Builder.Append('Keine.').Append(LineBreak).Append(LineBreak);
    end;
    Number := 0;
    for Cycle in AOverview.Cycles do
    begin
      Inc(Number);
      Builder.Append('### ').Append(Number).Append('. ').Append(CycleCaption(Cycle)).Append(LineBreak).Append(LineBreak);
      Builder.Append(CyclePath(AOverview, Cycle)).Append(LineBreak).Append(LineBreak);
      for Edge in Cycle.Edges do
      begin
        Builder.Append('- ').Append(EdgeText(AOverview, Edge)).Append(LineBreak);
      end;
      if Length(Cycle.Component) > Length(Cycle.Units) then
      begin
        Names := '';
        for Member in Cycle.Component do
        begin
          if Names <> '' then
          begin
            Names := Names + ', ';
          end;
          Names := Names + AOverview.Units[Member].Name;
        end;
        Builder.Append('- Komponente: ').Append(Names).Append(LineBreak);
      end;
      Builder.Append(LineBreak);
    end;

    Builder.Append('## Querverbindungen').Append(LineBreak).Append(LineBreak);
    if Length(AOverview.CrossLinks) = 0 then
    begin
      Builder.Append('Keine.').Append(LineBreak);
    end
    else
    begin
      Builder.Append('| Von | Nach | Abschnitt | Teilsysteme | Grund | Fundstelle |').Append(LineBreak);
      Builder.Append('|---|---|---|---|---|---|').Append(LineBreak);
      for Link in AOverview.CrossLinks do
      begin
        Location := LocationText(AOverview, Link.Edge);
        Builder.Append('| ').Append(Cell(AOverview.Units[Link.Edge.Source].Name)).Append(' | ')
          .Append(Cell(AOverview.Units[Link.Edge.Target].Name)).Append(' | ')
          .Append(SectionCaption(IsInterface(Link.Edge))).Append(' | ')
          .Append(Cell(SubsystemName(AOverview, Link.FromSubsystem) + ' → ' + SubsystemName(AOverview,
            Link.ToSubsystem))).Append(' | ')
          .Append(CrossReasonCaption(Link.Reason)).Append(' (').Append(Link.Forward).Append(' hin, ')
          .Append(Link.Backward).Append(' zurück) | ').Append(Cell(Location)).Append(' |').Append(LineBreak);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function HtmlEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function Page(const ATitle, AData: string): string;
begin
  // In einem <script> darf "</" nicht vorkommen (schlösse das Element); \/ ist in JSON gleichwertig.
  Result := StringReplace(ArchitectureMapHtml, '{{TITLE}}', HtmlEscape(ATitle), [rfReplaceAll]);
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
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.html') or (Extension = '.htm');
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
    Result := Result + '… ' + IntToStr(ACount - ALimit) + ' weitere (insgesamt ' + IntToStr(ACount) + ')' + LineBreak;
  end;
end;

class function TArchitectureReport.Text(const AOverview: TArchitectureOverview; ASection: TArchitectureSection;
  ALimit: Integer): string;
var
  Index, Member: Integer;
  Item: TOverviewUnit;
  Subsystem: TOverviewSubsystem;
  Line, Names: string;
  Cycle: TOverviewCycle;
  Link: TOverviewCrossLink;
  Outlier: TOverviewOutlier;
begin
  ALimit := Max(ALimit, 1);
  Result := 'Architektur ' + AOverview.Title + ' (' + ScopeText(AOverview) + ')' + LineBreak + Counts(AOverview) +
    LineBreak;
  if AOverview.IsAligned then
  begin
    Result := Result + AlignedText(AOverview) + LineBreak;
  end;
  case ASection of
    TArchitectureSection.Overview:
      begin
        Result := Result + LineBreak + 'Zentrale Units:' + LineBreak;
        for Index := 0 to Min(High(AOverview.Central), 4) do
        begin
          Item := AOverview.Units[AOverview.Central[Index]];
          Result := Result + '  ' + Item.Name + ': ' + IntToStr(Item.Total) + ' gesamt abhängig' + LineBreak;
        end;
        Result := Result + 'Teilsysteme:' + LineBreak;
        for Index := 0 to Min(High(AOverview.Subsystems), ALimit - 1) do
        begin
          Subsystem := AOverview.Subsystems[Index];
          Result := Result + '  ' + SubsystemCaption(Subsystem) + ': ' + IntToStr(Length(Subsystem.Units)) +
            ' Units, Zusammenhalt ' + CohesionText(Subsystem) + LineBreak;
        end;
        Result := Limited(Result, Length(AOverview.Subsystems), ALimit);
        Result := Result + 'Weitere Abschnitte: central, subsystems, cycles, crossLinks; unit für einen Steckbrief.';
      end;
    TArchitectureSection.Central:
      begin
        Result := Result + LineBreak + 'Unit | Teilsystem | direkt | gesamt | verwendet | Rolle' + LineBreak;
        for Index := 0 to Min(High(AOverview.Central), ALimit - 1) do
        begin
          Item := AOverview.Units[AOverview.Central[Index]];
          Line := Item.Name + ' | ' + SubsystemName(AOverview, Item.Subsystem) + ' | ' + IntToStr(Item.Direct) + ' | ' +
            IntToStr(Item.Total) + ' | ' + IntToStr(Item.Uses_);
          if Item.Role <> TOverviewUnitRole.None then
          begin
            Line := Line + ' | ' + TArchitectureAnalyzer.RoleCaption(Item.Role);
          end;
          Result := Result + Line + LineBreak;
        end;
        Result := Limited(Result, Length(AOverview.Central), ALimit);
      end;
    TArchitectureSection.Subsystems:
      begin
        Result := Result + LineBreak;
        for Index := 0 to Min(High(AOverview.Subsystems), ALimit - 1) do
        begin
          Subsystem := AOverview.Subsystems[Index];
          Names := '';
          for Member := 0 to Min(High(Subsystem.Units), 9) do
          begin
            if Names <> '' then
            begin
              Names := Names + ', ';
            end;
            Names := Names + AOverview.Units[Subsystem.Units[Member]].Name;
          end;
          if Length(Subsystem.Units) > 10 then
          begin
            Names := Names + ' … (' + IntToStr(Length(Subsystem.Units)) + ')';
          end;
          Result := Result + SubsystemCaption(Subsystem) + ': ' + IntToStr(Length(Subsystem.Units)) +
            ' Units, Zusammenhalt ' + CohesionText(Subsystem) + LineBreak + '  ' + Names + LineBreak;
        end;
        Result := Limited(Result, Length(AOverview.Subsystems), ALimit);
        if FoundationNote(AOverview) <> '' then
        begin
          Result := Result + FoundationNote(AOverview) + LineBreak;
        end;
        if Length(AOverview.Outliers) > 0 then
        begin
          Result := Result + 'Ausreißer:' + LineBreak;
          for Index := 0 to Min(High(AOverview.Outliers), ALimit - 1) do
          begin
            Outlier := AOverview.Outliers[Index];
            Result := Result + '  ' + AOverview.Units[Outlier.Unit_].Name + ' in ' +
              SubsystemName(AOverview, AOverview.Units[Outlier.Unit_].Subsystem) + ', Vorschlag ' +
              SubsystemName(AOverview, Outlier.Suggested) + ' (' + OutlierReasonCaption(Outlier.Reason) + ')' + LineBreak;
          end;
          Result := Limited(Result, Length(AOverview.Outliers), ALimit);
        end;
      end;
    TArchitectureSection.Cycles:
      begin
        Result := Result + LineBreak;
        if Length(AOverview.Cycles) = 0 then
        begin
          Result := Result + 'Keine Zyklen.' + LineBreak;
        end;
        for Index := 0 to Min(High(AOverview.Cycles), ALimit - 1) do
        begin
          Cycle := AOverview.Cycles[Index];
          Result := Result + IntToStr(Index + 1) + '. ' + CycleCaption(Cycle) + ': ' + CyclePath(AOverview, Cycle) +
            LineBreak;
          for Member := 0 to High(Cycle.Edges) do
          begin
            Result := Result + '  ' + EdgeText(AOverview, Cycle.Edges[Member]) + LineBreak;
          end;
        end;
        Result := Limited(Result, Length(AOverview.Cycles), ALimit);
      end;
    TArchitectureSection.CrossLinks:
      begin
        Result := Result + LineBreak;
        if Length(AOverview.CrossLinks) = 0 then
        begin
          Result := Result + 'Keine Querverbindungen.' + LineBreak;
        end;
        for Index := 0 to Min(High(AOverview.CrossLinks), ALimit - 1) do
        begin
          Link := AOverview.CrossLinks[Index];
          Result := Result + EdgeText(AOverview, Link.Edge) + ' ' + SubsystemName(AOverview, Link.FromSubsystem) +
            ' → ' + SubsystemName(AOverview, Link.ToSubsystem) + ', ' + CrossReasonCaption(Link.Reason) + ' (' +
            IntToStr(Link.Forward) + ' hin, ' + IntToStr(Link.Backward) + ' zurück)' + LineBreak;
        end;
        Result := Limited(Result, Length(AOverview.CrossLinks), ALimit);
      end;
  end;
end;

class function TArchitectureReport.UnitText(const AOverview: TArchitectureOverview; const AUnitName: string): string;
var
  Index, Item: Integer;
  Profile: TOverviewProfile;
  Unit_: TOverviewUnit;
  Names: string;
  Outlier: TOverviewOutlier;
begin
  Index := AOverview.IndexOf(AUnitName);
  if Index < 0 then
  begin
    Exit('Unit "' + AUnitName + '" ist nicht in der Architekturübersicht (nicht im Umfang, ausgeschlossen oder ' +
      'Bibliotheks-Unit).');
  end;
  Unit_ := AOverview.Units[Index];
  Profile := AOverview.Profile(Index);
  Result := Unit_.Name + ' (' + AOverview.RelativePath(Unit_.FileName) + ')' + LineBreak +
    'Teilsystem: ' + SubsystemName(AOverview, Unit_.Subsystem) + LineBreak +
    'direkt abhängig: ' + IntToStr(Unit_.Direct) + ' · gesamt abhängig: ' + IntToStr(Unit_.Total) + ' · verwendet: ' +
    IntToStr(Unit_.Uses_);
  if Unit_.Role <> TOverviewUnitRole.None then
  begin
    Result := Result + ' · ' + TArchitectureAnalyzer.RoleCaption(Unit_.Role);
  end;
  Result := Result + LineBreak;
  Names := '';
  for Item in Profile.DependsOn do
  begin
    if Names <> '' then
    begin
      Names := Names + ', ';
    end;
    Names := Names + AOverview.Units[Item].Name;
  end;
  Result := Result + 'verwendet: ' + Names + LineBreak;
  Names := '';
  for Item in Profile.UsedBy do
  begin
    if Names <> '' then
    begin
      Names := Names + ', ';
    end;
    Names := Names + AOverview.Units[Item].Name;
  end;
  Result := Result + 'verwendet von: ' + Names + LineBreak;
  if Length(Profile.Cycles) = 0 then
  begin
    Result := Result + 'Zyklen: keine' + LineBreak;
  end
  else
  begin
    for Item in Profile.Cycles do
    begin
      Result := Result + CycleCaption(AOverview.Cycles[Item]) + ': ' + CyclePath(AOverview, AOverview.Cycles[Item]) +
        LineBreak;
    end;
  end;
  for Item in Profile.CrossLinks do
  begin
    Result := Result + 'Querverbindung: ' + EdgeText(AOverview, AOverview.CrossLinks[Item].Edge) + LineBreak;
  end;
  if Profile.Outlier >= 0 then
  begin
    Outlier := AOverview.Outliers[Profile.Outlier];
    Result := Result + 'Ausreißer: gehört eher zu ' + SubsystemName(AOverview, Outlier.Suggested) + ' (' +
      OutlierReasonCaption(Outlier.Reason) + '; ' + IntToStr(Outlier.Inside) + ' Kanten im eigenen, ' +
      IntToStr(Outlier.Toward) + ' zum Vorschlag)' + LineBreak;
  end;
  Result := Result + AssignmentText(AOverview, Index);
end;

end.
