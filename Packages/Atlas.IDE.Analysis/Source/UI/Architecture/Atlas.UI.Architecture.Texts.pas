unit Atlas.UI.Architecture.Texts;

// Texte der Architekturansicht (#1360) ohne Steuerelemente: Namen von Units und Teilsystemen, Rollen,
// Abhängigkeiten mit Fundstelle, Zeilen im Baum der Teilsysteme, Zyklen, Änderungen des Vergleichs und Hinweise
// der Statuszeile. Aufbau und Füllen der Listen stehen in Atlas.UI.Architecture.Frame.

interface

uses
  Atlas.Core.Architecture.Model;

type
  /// <summary>Texte der Architekturansicht aus dem Modell, ohne Steuerelemente.</summary>
  TAtlasArchitectureTexts = class
  public
    class function UnitCaption(const AModel: TAtlasArchitectureModel; AUnit: Integer): string; static;
    class function RoleCaption(const ARole: string): string; static;
    class function LocationCaption(const ALink: TAtlasArchLink): string; static;
    class function LinkCaption(const AModel: TAtlasArchitectureModel; const ALink: TAtlasArchLink): string; static;
    /// <summary>Zeile eines Teilsystems in Menü und Reiter: Name, Units, Zusammenhalt (Fundament ohne, #1365).
    /// </summary>
    class function SubsystemCaption(const AModel: TAtlasArchitectureModel; ASubsystem: Integer): string; static;
    /// <summary>Unit im Baum der Teilsysteme: Name, Grund des Ausreißers, knapp zugeordnet (#1368).</summary>
    class function MemberLine(const AModel: TAtlasArchitectureModel; AMember: Integer): string; static;
    class function CycleTitle(const ACycle: TAtlasArchCycle): string; static;
    /// <summary>Angaben einer Kante im Vergleich: von → nach, Abschnitt, Grund.</summary>
    class function EdgeDetail(const AChange: TAtlasArchChange): string; static;
    class function ChangeCaption(AKind: TAtlasArchChangeKind; const AChange: TAtlasArchChange): string; static;
    /// <summary>Zeile über dem Baum „Vergleich“: gegen welchen Stand, Fehler oder Hinweis.</summary>
    class function ComparisonInfo(const AComparison: TAtlasArchComparison): string; static;
    /// <summary>Angleichung an einen vorigen Stand (#1367) und Vergleich als Zusatz der Statuszeile.</summary>
    class function StatusNotes(const AModel: TAtlasArchitectureModel): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Architecture.Assignment,
  Atlas.UI.Analysis.Strings;

class function TAtlasArchitectureTexts.UnitCaption(const AModel: TAtlasArchitectureModel; AUnit: Integer): string;
begin
  Result := '';
  if (AUnit >= 0) and (AUnit <= High(AModel.Units)) then
  begin
    Result := AModel.Units[AUnit].Name;
  end;
end;

class function TAtlasArchitectureTexts.RoleCaption(const ARole: string): string;
begin
  Result := '';
  if ARole = 'foundation' then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRoleFoundation);
  end
  else if ARole = 'hub' then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureRoleHub);
  end;
end;

class function TAtlasArchitectureTexts.LocationCaption(const ALink: TAtlasArchLink): string;
begin
  Result := '';
  if (ALink.FileName <> '') and (ALink.Line > 0) then
  begin
    Result := Format('%s:%d', [ALink.FileName, ALink.Line]);
  end;
end;

class function TAtlasArchitectureTexts.LinkCaption(const AModel: TAtlasArchitectureModel;
  const ALink: TAtlasArchLink): string;
var
  mSection, mLocation: string;
begin
  mSection := 'implementation';
  if ALink.Interface_ then
  begin
    mSection := 'interface';
  end;
  mLocation := LocationCaption(ALink);
  if mLocation <> '' then
  begin
    mSection := mSection + ', ' + mLocation;
  end;
  Result := Format('%s → %s (%s)', [UnitCaption(AModel, ALink.Source), UnitCaption(AModel, ALink.Target), mSection]);
end;

/// <summary>Zeile eines Teilsystems in Menü und Reiter: Name, Units, Zusammenhalt (Fundament ohne, #1365).</summary>
class function TAtlasArchitectureTexts.SubsystemCaption(const AModel: TAtlasArchitectureModel;
  ASubsystem: Integer): string;
var
  mSubsystem: TAtlasArchSubsystem;
begin
  mSubsystem := AModel.Subsystems[ASubsystem];
  if mSubsystem.Foundation then
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureFoundationLine,
      [mSubsystem.Name, Length(mSubsystem.Units)]);
  end
  else
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSubsystemLine,
      [mSubsystem.Name, Length(mSubsystem.Units), Round(mSubsystem.Cohesion * 100)]);
  end;
end;

/// <summary>Unit im Baum der Teilsysteme: Name, Grund des Ausreißers, knapp zugeordnet (#1368).</summary>
class function TAtlasArchitectureTexts.MemberLine(const AModel: TAtlasArchitectureModel; AMember: Integer): string;
var
  mOutlier: Integer;
  mText: TAtlasAnalysisTextId;
begin
  Result := AModel.Units[AMember].Name;
  mOutlier := AModel.OutlierOf(AMember);
  if mOutlier >= 0 then
  begin
    mText := TAtlasAnalysisTextId.ArchitectureOutlierEdges;
    if AModel.Outliers[mOutlier].Reason = 'namespace' then
    begin
      mText := TAtlasAnalysisTextId.ArchitectureOutlierNamespace;
    end;
    Result := Result + ' — ' + TAtlasAnalysisStrings.Fmt(mText,
      [AModel.SubsystemName(AModel.Outliers[mOutlier].Suggested)]);
  end;
  if TAtlasArchitectureAssignment.CloseMark(AModel, AMember) <> '' then
  begin
    Result := Result + ' — ' + TAtlasArchitectureAssignment.CloseMark(AModel, AMember);
  end;
end;

class function TAtlasArchitectureTexts.CycleTitle(const ACycle: TAtlasArchCycle): string;
begin
  if ACycle.InterfaceOnly then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCycleInterface);
  end
  else
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCycleImplementation);
  end;
end;

/// <summary>Angaben einer Kante im Vergleich: von → nach, Abschnitt, Grund.</summary>
class function TAtlasArchitectureTexts.EdgeDetail(const AChange: TAtlasArchChange): string;
begin
  Result := AChange.From + ' → ' + AChange.To_;
  if AChange.Section <> '' then
  begin
    Result := Result + ', ' + AChange.Section;
  end;
  if AChange.Reason = 'rare' then
  begin
    Result := Result + ', ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureReasonRare);
  end
  else if AChange.Reason <> '' then
  begin
    Result := Result + ', ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureReasonAgainst);
  end;
end;

class function TAtlasArchitectureTexts.ChangeCaption(AKind: TAtlasArchChangeKind;
  const AChange: TAtlasArchChange): string;
begin
  Result := AChange.Text;
  case AKind of
    TAtlasArchChangeKind.NewCycles, TAtlasArchChangeKind.RemovedCycles:
      if AChange.Section = 'interface' then
      begin
        Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCycleInterface) + ': ' + Result;
      end
      else
      begin
        Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureCycleImplementation) + ': ' + Result;
      end;
    TAtlasArchChangeKind.Growth:
      Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureGrowthLine,
        [AChange.Text, AChange.From, AChange.To_]);
    TAtlasArchChangeKind.Moves:
      Result := Result + ' (' + AChange.From + ' → ' + AChange.To_ + ')';
    TAtlasArchChangeKind.NewCrossLinks, TAtlasArchChangeKind.RemovedCrossLinks, TAtlasArchChangeKind.NewEdges,
    TAtlasArchChangeKind.RemovedEdges:
      Result := Result + ' (' + EdgeDetail(AChange) + ')';
    TAtlasArchChangeKind.NewUnits, TAtlasArchChangeKind.RemovedUnits: ;
  end;
end;

/// <summary>Zeile über dem Baum „Vergleich“: gegen welchen Stand, Fehler oder Hinweis.</summary>
class function TAtlasArchitectureTexts.ComparisonInfo(const AComparison: TAtlasArchComparison): string;
begin
  if AComparison.Error <> '' then
  begin
    Exit(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonError, [AComparison.Error]));
  end;
  if not AComparison.Present then
  begin
    Exit(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoComparison));
  end;
  Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonInfo,
    [ExtractFileName(AComparison.Baseline), AComparison.BaselineTitle, AComparison.BaselineUnits,
    AComparison.BaselineEdges, AComparison.Count]);
  if Length(AComparison.Failed) > 0 then
  begin
    Result := Result + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonFailed,
      [string.Join(', ', AComparison.Failed)]);
  end;
  // Verschiedene Feinheit (#1366): Teilsystemwechsel können allein daher kommen.
  if AComparison.ResolutionDiffers then
  begin
    Result := Result + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonResolution,
      [TAtlasArchResolution.Text(AComparison.BaselineResolution, FormatSettings),
      TAtlasArchResolution.Text(AComparison.Resolution, FormatSettings)]);
  end;
end;

/// <summary>Angleichung an einen vorigen Stand (#1367) und Vergleich als Zusatz der Statuszeile.</summary>
class function TAtlasArchitectureTexts.StatusNotes(const AModel: TAtlasArchitectureModel): string;
begin
  Result := '';
  if Length(AModel.Excludes) > 0 then
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatusExcludes,
      [string.Join(', ', AModel.Excludes)]);
  end;
  if AModel.AlignedSource = 'baseline' then
  begin
    Result := Result + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatusAlignedBaseline,
      [AModel.AlignedText]);
  end
  else if AModel.AlignedSource <> '' then
  begin
    Result := Result + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatusAlignedLast,
      [AModel.AlignedText]);
  end;
  if AModel.Comparison.Present then
  begin
    Result := Result + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureStatusComparison,
      [AModel.Comparison.Count]);
  end
  else if AModel.Comparison.Error <> '' then
  begin
    Result := Result + ' · ' + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureComparisonError,
      [AModel.Comparison.Error]);
  end;
end;

end.
