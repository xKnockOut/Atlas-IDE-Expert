unit Atlas.Common.Architecture.Report;

// Architekturübersicht (#1118) als Markdown, JSON, HTML-Seite und kompakter
// Text für das MCP-Werkzeug get_architecture. Alle Ausgaben lesen dieselbe
// TArchitectureOverview; Pfade relativ zu ihrem Root, Zeilen und Spalten
// ab 1.
//
// JSON (Format 1; Nummern beziehen sich auf "units" bzw. "subsystems"):
//   {"format": 1, "title": "Projekt", "created": "2026-10-23T10:00:00",
//    "generation": 7, "durationMs": 12, "scope": "projectGroup",
//    "includeLibrary": false, "excludes": ["Tests/**"],
//    "summary": {"units": 3, "edges": 2, "subsystems": 1, "cycles": 0,
//                "interfaceCycles": 0, "crossLinks": 0, "outliers": 0},
//    "units": [{"name": "A", "file": "Source/A.pas", "subsystem": 0,
//               "direct": 1, "total": 2, "uses": 0, "role": "foundation",
//               "library": false, "x": 0, "y": 0}],
//    "edges": [[0, 1, "i"], [1, 2, "m"]],            (i = interface, m = implementation)
//    "central": [0, 1],
//    "subsystems": [{"name": "Kern", "units": [0, 1], "central": 0,
//                    "inner": 2, "outer": 0, "cohesion": 1, "isolated": false,
//                    "x": 0, "y": 0, "r": 70}],
//    "outliers": [{"unit": 3, "suggested": 1, "reason": "namespace",
//                  "inside": 2, "toward": 0}],
//    "cycles": [{"interfaceOnly": true, "units": [0, 1], "component": [0, 1],
//                "edges": [{"source": 0, "target": 1, "section": "interface",
//                           "file": "A.pas", "line": 3, "character": 6}]}],
//    "crossLinks": [{"source": 0, "target": 4, "section": "implementation",
//                    "from": 0, "to": 1, "reason": "rare", "forward": 1,
//                    "backward": 0, "file": "A.pas", "line": 9, "character": 3}]}
// "file"/"line"/"character" fehlen bei Kanten ohne Fundstelle.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Layout;

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
    class function Json(const AOverview: TArchitectureOverview; const ALayout: TArchitectureLayout): string; static;
    class function Markdown(const AOverview: TArchitectureOverview): string; static;
    /// <summary>Eigenständige HTML-Seite mit eingebetteten Daten und Skript (offline, keine externen Verweise).</summary>
    class function Html(const AOverview: TArchitectureOverview): string; static;
    /// <summary>Bericht passend zur Endung von AFileName: .html/.htm HTML, sonst Markdown.</summary>
    class function ForFile(const AOverview: TArchitectureOverview; const AFileName: string): string; static;
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
    Result := 'true'
  else
    Result := 'false';
end;

function JsonInts(const AValues: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '[';
  for Index := 0 to High(AValues) do
  begin
    if Index > 0 then
      Result := Result + ',';
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
    Result := AOverview.Subsystems[ASubsystem].Name
  else
    Result := '';
end;

function CreatedText(const AOverview: TArchitectureOverview): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn', AOverview.Created);
end;

function InterfaceCycleCount(const AOverview: TArchitectureOverview): Integer;
var
  Cycle: TOverviewCycle;
begin
  Result := 0;
  for Cycle in AOverview.Cycles do
    if Cycle.InterfaceOnly then
      Inc(Result);
end;

/// <summary>"Units: 12 · uses-Kanten: 17 · …" für Kopf und MCP.</summary>
function Counts(const AOverview: TArchitectureOverview): string;
begin
  Result := 'Units: ' + IntToStr(Length(AOverview.Units)) + ' · uses-Kanten: ' + IntToStr(AOverview.EdgeCount) +
    ' · Teilsysteme: ' + IntToStr(Length(AOverview.Subsystems)) + ' · Zyklen: ' + IntToStr(Length(AOverview.Cycles));
  if InterfaceCycleCount(AOverview) > 0 then
    Result := Result + ' (davon nur interface: ' + IntToStr(InterfaceCycleCount(AOverview)) + ')';
  Result := Result + ' · Querverbindungen: ' + IntToStr(Length(AOverview.CrossLinks)) + ' · Ausreißer: ' +
    IntToStr(Length(AOverview.Outliers));
end;

function ScopeText(const AOverview: TArchitectureOverview): string;
begin
  if SameText(AOverview.Scope, 'project') then
    Result := 'Projekt'
  else
    Result := 'Projektgruppe';
  if AOverview.IncludeLibrary then
    Result := Result + ', mit Bibliotheks-Units'
  else
    Result := Result + ', ohne Bibliotheks-Units';
  if Length(AOverview.Excludes) > 0 then
    Result := Result + ', ausgeschlossen: ' + string.Join(', ', AOverview.Excludes);
end;

{ TArchitectureReport }

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
    Exit(True);
  for Section := Low(TArchitectureSection) to High(TArchitectureSection) do
    if SameText(Trim(AText), SectionName(Section)) then
    begin
      ASection := Section;
      Exit(True);
    end;
  Result := False;
end;

class function TArchitectureReport.SectionCaption(AInterface: Boolean): string;
begin
  if AInterface then
    Result := 'interface'
  else
    Result := 'implementation';
end;

class function TArchitectureReport.CrossReasonCaption(AReason: TOverviewCrossReason): string;
begin
  if AReason = TOverviewCrossReason.Rare then
    Result := 'selten'
  else
    Result := 'gegen die Hauptrichtung';
end;

class function TArchitectureReport.OutlierReasonCaption(AReason: TOverviewOutlierReason): string;
begin
  if AReason = TOverviewOutlierReason.Namespace then
    Result := 'Namensraum passt zu einem anderen Teilsystem'
  else
    Result := 'mehr Kanten in ein anderes Teilsystem';
end;

class function TArchitectureReport.CycleCaption(const ACycle: TOverviewCycle): string;
begin
  if ACycle.InterfaceOnly then
    Result := 'Zyklus nur über interface (Compilerfehler F2047)'
  else
    Result := 'Zyklus über implementation';
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
      Result := AOverview.Units[Edge.Source].Name;
    Result := Result + ' → ' + AOverview.Units[Edge.Target].Name;
  end;
end;

class function TArchitectureReport.LocationText(const AOverview: TArchitectureOverview;
  const AEdge: TOverviewEdge): string;
begin
  if not AEdge.Located then
    Exit('');
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
    Result := Result + ', ' + Location;
  Result := Result + ')';
end;

function EdgeJson(const AOverview: TArchitectureOverview; const AEdge: TOverviewEdge): string;
begin
  Result := '"source":' + IntToStr(AEdge.Source) + ',"target":' + IntToStr(AEdge.Target) + ',"section":' +
    JsonText(TArchitectureReport.SectionCaption(IsInterface(AEdge)));
  if AEdge.Located then
    Result := Result + ',"file":' + JsonText(AOverview.RelativePath(AEdge.Location.FileName)) + ',"line":' +
      IntToStr(AEdge.Location.Range.StartPos.Line + 1) + ',"character":' +
      IntToStr(AEdge.Location.Range.StartPos.Character + 1);
end;

class function TArchitectureReport.Json(const AOverview: TArchitectureOverview;
  const ALayout: TArchitectureLayout): string;
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
      .Append(',"created":').Append(JsonText(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', AOverview.Created)))
      .Append(',"generation":').Append(IntToStr(AOverview.Generation))
      .Append(',"durationMs":').Append(IntToStr(AOverview.DurationMs))
      .Append(',"scope":').Append(JsonText(AOverview.Scope))
      .Append(',"includeLibrary":').Append(JsonBool(AOverview.IncludeLibrary))
      .Append(',"excludes":[');
    for Index := 0 to High(AOverview.Excludes) do
    begin
      if Index > 0 then
        Builder.Append(',');
      Builder.Append(JsonText(AOverview.Excludes[Index]));
    end;
    Builder.Append('],"summary":{"units":').Append(Length(AOverview.Units))
      .Append(',"edges":').Append(AOverview.EdgeCount)
      .Append(',"subsystems":').Append(Length(AOverview.Subsystems))
      .Append(',"cycles":').Append(Length(AOverview.Cycles))
      .Append(',"interfaceCycles":').Append(InterfaceCycleCount(AOverview))
      .Append(',"crossLinks":').Append(Length(AOverview.CrossLinks))
      .Append(',"outliers":').Append(Length(AOverview.Outliers)).Append('}');
    Builder.Append(',"units":[');
    for Index := 0 to High(AOverview.Units) do
    begin
      Item := AOverview.Units[Index];
      if Index > 0 then
        Builder.Append(',');
      Builder.Append(LineBreak).Append('{"name":').Append(JsonText(Item.Name))
        .Append(',"file":').Append(JsonText(AOverview.RelativePath(Item.FileName)))
        .Append(',"subsystem":').Append(Item.Subsystem)
        .Append(',"direct":').Append(Item.Direct)
        .Append(',"total":').Append(Item.Total)
        .Append(',"uses":').Append(Item.Uses_)
        .Append(',"role":').Append(JsonText(RoleName(Item.Role)))
        .Append(',"library":').Append(JsonBool(Item.Library_));
      if Index < Length(ALayout.Units) then
        Builder.Append(',"x":').Append(JsonNumber(ALayout.Units[Index].X))
          .Append(',"y":').Append(JsonNumber(ALayout.Units[Index].Y));
      Builder.Append('}');
    end;
    Builder.Append('],"edges":[');
    for Index := 0 to High(AOverview.Edges) do
    begin
      Edge := AOverview.Edges[Index];
      if Index > 0 then
        Builder.Append(',');
      if Index mod 20 = 0 then
        Builder.Append(LineBreak);
      if IsInterface(Edge) then
        Kind := 'i'
      else
        Kind := 'm';
      Builder.Append('[').Append(Edge.Source).Append(',').Append(Edge.Target).Append(',"').Append(Kind).Append('"]');
    end;
    Builder.Append('],"central":').Append(JsonInts(AOverview.Central));
    Builder.Append(',"subsystems":[');
    for Index := 0 to High(AOverview.Subsystems) do
    begin
      Subsystem := AOverview.Subsystems[Index];
      if Index > 0 then
        Builder.Append(',');
      Builder.Append(LineBreak).Append('{"name":').Append(JsonText(Subsystem.Name))
        .Append(',"units":').Append(JsonInts(Subsystem.Units))
        .Append(',"central":').Append(Subsystem.Central)
        .Append(',"inner":').Append(Subsystem.InnerEdges)
        .Append(',"outer":').Append(Subsystem.OuterEdges)
        .Append(',"cohesion":').Append(JsonNumber(Subsystem.Cohesion))
        .Append(',"isolated":').Append(JsonBool(Subsystem.Isolated));
      if Index < Length(ALayout.Subsystems) then
        Builder.Append(',"x":').Append(JsonNumber(ALayout.Subsystems[Index].X))
          .Append(',"y":').Append(JsonNumber(ALayout.Subsystems[Index].Y))
          .Append(',"r":').Append(JsonNumber(ALayout.Subsystems[Index].Radius));
      Builder.Append('}');
    end;
    Builder.Append('],"outliers":[');
    for Index := 0 to High(AOverview.Outliers) do
    begin
      Outlier := AOverview.Outliers[Index];
      if Index > 0 then
        Builder.Append(',');
      Builder.Append(LineBreak).Append('{"unit":').Append(Outlier.Unit_)
        .Append(',"suggested":').Append(Outlier.Suggested)
        .Append(',"reason":');
      if Outlier.Reason = TOverviewOutlierReason.Namespace then
        Builder.Append('"namespace"')
      else
        Builder.Append('"edges"');
      Builder.Append(',"inside":').Append(Outlier.Inside).Append(',"toward":').Append(Outlier.Toward).Append('}');
    end;
    Builder.Append('],"cycles":[');
    for Index := 0 to High(AOverview.Cycles) do
    begin
      Cycle := AOverview.Cycles[Index];
      if Index > 0 then
        Builder.Append(',');
      Builder.Append(LineBreak).Append('{"interfaceOnly":').Append(JsonBool(Cycle.InterfaceOnly))
        .Append(',"units":').Append(JsonInts(Cycle.Units))
        .Append(',"component":').Append(JsonInts(Cycle.Component))
        .Append(',"edges":[');
      for Inner := 0 to High(Cycle.Edges) do
      begin
        if Inner > 0 then
          Builder.Append(',');
        Builder.Append('{').Append(EdgeJson(AOverview, Cycle.Edges[Inner])).Append('}');
      end;
      Builder.Append(']}');
    end;
    Builder.Append('],"crossLinks":[');
    for Index := 0 to High(AOverview.CrossLinks) do
    begin
      Link := AOverview.CrossLinks[Index];
      if Index > 0 then
        Builder.Append(',');
      Builder.Append(LineBreak).Append('{').Append(EdgeJson(AOverview, Link.Edge))
        .Append(',"from":').Append(Link.FromSubsystem)
        .Append(',"to":').Append(Link.ToSubsystem)
        .Append(',"reason":');
      if Link.Reason = TOverviewCrossReason.Rare then
        Builder.Append('"rare"')
      else
        Builder.Append('"againstDirection"');
      Builder.Append(',"forward":').Append(Link.Forward).Append(',"backward":').Append(Link.Backward).Append('}');
    end;
    Builder.Append(']}');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TArchitectureReport.Markdown(const AOverview: TArchitectureOverview): string;
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
    Builder.Append('- [Zentrale Units](#zentrale-units)').Append(LineBreak)
      .Append('- [Teilsysteme](#teilsysteme)').Append(LineBreak)
      .Append('- [Ausreißer](#ausreißer)').Append(LineBreak)
      .Append('- [Zyklen](#zyklen)').Append(LineBreak)
      .Append('- [Querverbindungen](#querverbindungen)').Append(LineBreak).Append(LineBreak);

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
      Builder.Append('| ').Append(Cell(Subsystem.Name)).Append(' | ').Append(Length(Subsystem.Units)).Append(' | ');
      if Subsystem.Central >= 0 then
        Builder.Append(Cell(AOverview.Units[Subsystem.Central].Name));
      Builder.Append(' | ').Append(Percent(Subsystem.Cohesion)).Append(' | ').Append(Subsystem.InnerEdges)
        .Append(' | ').Append(Subsystem.OuterEdges).Append(' |').Append(LineBreak);
    end;
    Builder.Append(LineBreak);
    for Index := 0 to High(AOverview.Subsystems) do
    begin
      Subsystem := AOverview.Subsystems[Index];
      Builder.Append('### ').Append(Subsystem.Name).Append(LineBreak).Append(LineBreak);
      Names := '';
      for Member in Subsystem.Units do
      begin
        if Names <> '' then
          Names := Names + ', ';
        Names := Names + AOverview.Units[Member].Name;
        if AOverview.Profile(Member).Outlier >= 0 then
          Names := Names + ' (Ausreißer)';
      end;
      Builder.Append(Names).Append(LineBreak).Append(LineBreak);
    end;

    Builder.Append('## Ausreißer').Append(LineBreak).Append(LineBreak);
    if Length(AOverview.Outliers) = 0 then
      Builder.Append('Keine.').Append(LineBreak).Append(LineBreak)
    else
    begin
      Builder.Append('| Unit | in Teilsystem | Vorschlag | Grund | Kanten im eigenen | Kanten zum Vorschlag |')
        .Append(LineBreak);
      Builder.Append('|---|---|---|---|---|---|').Append(LineBreak);
      for Outlier in AOverview.Outliers do
        Builder.Append('| ').Append(Cell(AOverview.Units[Outlier.Unit_].Name)).Append(' | ')
          .Append(Cell(SubsystemName(AOverview, AOverview.Units[Outlier.Unit_].Subsystem))).Append(' | ')
          .Append(Cell(SubsystemName(AOverview, Outlier.Suggested))).Append(' | ')
          .Append(OutlierReasonCaption(Outlier.Reason)).Append(' | ').Append(Outlier.Inside).Append(' | ')
          .Append(Outlier.Toward).Append(' |').Append(LineBreak);
      Builder.Append(LineBreak);
    end;

    Builder.Append('## Zyklen').Append(LineBreak).Append(LineBreak);
    if Length(AOverview.Cycles) = 0 then
      Builder.Append('Keine.').Append(LineBreak).Append(LineBreak);
    Number := 0;
    for Cycle in AOverview.Cycles do
    begin
      Inc(Number);
      Builder.Append('### ').Append(Number).Append('. ').Append(CycleCaption(Cycle)).Append(LineBreak).Append(LineBreak);
      Builder.Append(CyclePath(AOverview, Cycle)).Append(LineBreak).Append(LineBreak);
      for Edge in Cycle.Edges do
        Builder.Append('- ').Append(EdgeText(AOverview, Edge)).Append(LineBreak);
      if Length(Cycle.Component) > Length(Cycle.Units) then
      begin
        Names := '';
        for Member in Cycle.Component do
        begin
          if Names <> '' then
            Names := Names + ', ';
          Names := Names + AOverview.Units[Member].Name;
        end;
        Builder.Append('- Komponente: ').Append(Names).Append(LineBreak);
      end;
      Builder.Append(LineBreak);
    end;

    Builder.Append('## Querverbindungen').Append(LineBreak).Append(LineBreak);
    if Length(AOverview.CrossLinks) = 0 then
      Builder.Append('Keine.').Append(LineBreak)
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

class function TArchitectureReport.Html(const AOverview: TArchitectureOverview): string;
var
  Data: string;
begin
  // In einem <script> darf "</" nicht vorkommen (schlösse das Element); \/ ist in JSON gleichwertig.
  Data := StringReplace(Json(AOverview, TArchitectureLayouter.Compute(AOverview)), '</', '<\/', [rfReplaceAll]);
  Result := StringReplace(ArchitectureMapHtml, '{{TITLE}}', HtmlEscape(AOverview.Title), [rfReplaceAll]);
  Result := StringReplace(Result, '{{DATA}}', Data, []);
end;

class function TArchitectureReport.ForFile(const AOverview: TArchitectureOverview; const AFileName: string): string;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  if (Extension = '.html') or (Extension = '.htm') then
    Result := Html(AOverview)
  else
    Result := Markdown(AOverview);
end;

function Limited(const AText: string; ACount, ALimit: Integer): string;
begin
  Result := AText;
  if ACount > ALimit then
    Result := Result + '… ' + IntToStr(ACount - ALimit) + ' weitere (insgesamt ' + IntToStr(ACount) + ')' + LineBreak;
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
          Result := Result + '  ' + Subsystem.Name + ': ' + IntToStr(Length(Subsystem.Units)) + ' Units, Zusammenhalt ' +
            Percent(Subsystem.Cohesion) + LineBreak;
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
            Line := Line + ' | ' + TArchitectureAnalyzer.RoleCaption(Item.Role);
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
              Names := Names + ', ';
            Names := Names + AOverview.Units[Subsystem.Units[Member]].Name;
          end;
          if Length(Subsystem.Units) > 10 then
            Names := Names + ' … (' + IntToStr(Length(Subsystem.Units)) + ')';
          Result := Result + Subsystem.Name + ': ' + IntToStr(Length(Subsystem.Units)) + ' Units, Zusammenhalt ' +
            Percent(Subsystem.Cohesion) + LineBreak + '  ' + Names + LineBreak;
        end;
        Result := Limited(Result, Length(AOverview.Subsystems), ALimit);
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
          Result := Result + 'Keine Zyklen.' + LineBreak;
        for Index := 0 to Min(High(AOverview.Cycles), ALimit - 1) do
        begin
          Cycle := AOverview.Cycles[Index];
          Result := Result + IntToStr(Index + 1) + '. ' + CycleCaption(Cycle) + ': ' + CyclePath(AOverview, Cycle) +
            LineBreak;
          for Member := 0 to High(Cycle.Edges) do
            Result := Result + '  ' + EdgeText(AOverview, Cycle.Edges[Member]) + LineBreak;
        end;
        Result := Limited(Result, Length(AOverview.Cycles), ALimit);
      end;
    TArchitectureSection.CrossLinks:
      begin
        Result := Result + LineBreak;
        if Length(AOverview.CrossLinks) = 0 then
          Result := Result + 'Keine Querverbindungen.' + LineBreak;
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
    Exit('Unit "' + AUnitName + '" ist nicht in der Architekturübersicht (nicht im Umfang, ausgeschlossen oder ' +
      'Bibliotheks-Unit).');
  Unit_ := AOverview.Units[Index];
  Profile := AOverview.Profile(Index);
  Result := Unit_.Name + ' (' + AOverview.RelativePath(Unit_.FileName) + ')' + LineBreak +
    'Teilsystem: ' + SubsystemName(AOverview, Unit_.Subsystem) + LineBreak +
    'direkt abhängig: ' + IntToStr(Unit_.Direct) + ' · gesamt abhängig: ' + IntToStr(Unit_.Total) + ' · verwendet: ' +
    IntToStr(Unit_.Uses_);
  if Unit_.Role <> TOverviewUnitRole.None then
    Result := Result + ' · ' + TArchitectureAnalyzer.RoleCaption(Unit_.Role);
  Result := Result + LineBreak;
  Names := '';
  for Item in Profile.DependsOn do
  begin
    if Names <> '' then
      Names := Names + ', ';
    Names := Names + AOverview.Units[Item].Name;
  end;
  Result := Result + 'verwendet: ' + Names + LineBreak;
  Names := '';
  for Item in Profile.UsedBy do
  begin
    if Names <> '' then
      Names := Names + ', ';
    Names := Names + AOverview.Units[Item].Name;
  end;
  Result := Result + 'verwendet von: ' + Names + LineBreak;
  if Length(Profile.Cycles) = 0 then
    Result := Result + 'Zyklen: keine' + LineBreak
  else
    for Item in Profile.Cycles do
      Result := Result + CycleCaption(AOverview.Cycles[Item]) + ': ' + CyclePath(AOverview, AOverview.Cycles[Item]) +
        LineBreak;
  for Item in Profile.CrossLinks do
    Result := Result + 'Querverbindung: ' + EdgeText(AOverview, AOverview.CrossLinks[Item].Edge) + LineBreak;
  if Profile.Outlier >= 0 then
  begin
    Outlier := AOverview.Outliers[Profile.Outlier];
    Result := Result + 'Ausreißer: gehört eher zu ' + SubsystemName(AOverview, Outlier.Suggested) + ' (' +
      OutlierReasonCaption(Outlier.Reason) + '; ' + IntToStr(Outlier.Inside) + ' Kanten im eigenen, ' +
      IntToStr(Outlier.Toward) + ' zum Vorschlag)' + LineBreak;
  end;
end;

end.
