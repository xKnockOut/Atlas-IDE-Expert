unit Rules.Builtin.FeatureCycles.Tests;

// Regel architecture-feature-cycle: Meldung am uses-Eintrag, Auswertung je
// Stand des Uses-Graphen einmal, Pfade relativ zur Konfiguration. Die
// Auswertung selbst prüft Atlas.Common.Architecture.FeatureCycles.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFeatureCycleRuleTests = class
  public
    [Test]
    procedure ReportsCycleAtUsesEntry;
    [Test]
    procedure ReportsDirection;
    [Test]
    procedure KnownCycleIsSilent;
    [Test]
    procedure ExcludedPathsDoNotCount;
    [Test]
    procedure SilentWithoutPrefixesOrIncompleteProjects;
    [Test]
    procedure AnalysisSharedByKey;
    [Test]
    procedure RootAndRelativePaths;
    [Test]
    procedure RelativeFileNameKeepsExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Rules.Contract,
  Rules.Builtin.FeatureCycles,
  Atlas.Tests.RuleAssert,
  Atlas.Common.Projects.Contract.Group,
  Atlas.Common.Findings.Contract;

const
  cRoot = 'C:/Repo/';

type
  /// <summary>Uses-Graph aus festen Kanten; zählt, wie oft eine Ableitung gerechnet wird.</summary>
  TEdgeProjectFiles = class(TInterfacedObject, IProjectGroupFiles)
  private
    FEdges: TArray<TGroupUsesEdge>;
    FComplete: Boolean;
    FKeys: TArray<string>;
    FValues: TArray<IInterface>;
    FDerives: Integer;
  public
    constructor Create(const AEdges: array of string; AComplete: Boolean);
    /// <summary>Dateien relativ zum aktuellen Ordner wie beim Prüfen einzelner Dateien.</summary>
    constructor CreateRelative(const AEdges: array of string);
    constructor CreateAt(const AEdges: array of string; AComplete: Boolean; const ARoot: string);
    function Complete(out AReason: string): Boolean;
    function ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TGroupProject>;
    function NameIn(const AFileName, AName: string): TNameAnswer;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function UsesPath(const AFromUnit, AToFile: string; AInterfaceOnly: Boolean): TArray<TGroupUsesStep>;
    function UsedBy(const AFileName: string; out AUsers: TArray<TGroupUsesStep>): Boolean;
    function UsesDerived(const AKey: string; const ADerive: TGroupUsesDerive): IInterface;
    property Derives: Integer read FDerives;
  end;

/// <summary>Kanten "Quelle -> Ziel"; die Datei einer Unit ist C:/Repo/Source/&lt;Unit&gt;.pas, mit "Tests." vorn
/// C:/Repo/Tests/&lt;Unit&gt;.pas.</summary>
function FileOf(const ARoot, AUnit: string): string;
begin
  if AUnit.StartsWith('Tests.') then
  begin
    Exit(ARoot + 'Tests/' + Copy(AUnit, 7, MaxInt) + '.pas');
  end;
  Result := ARoot + 'Source/' + AUnit + '.pas';
end;

function UnitOf(const AName: string): string;
begin
  Result := AName;
  if Result.StartsWith('Tests.') then
  begin
    Result := Copy(Result, 7, MaxInt);
  end;
end;

constructor TEdgeProjectFiles.Create(const AEdges: array of string; AComplete: Boolean);
begin
  CreateAt(AEdges, AComplete, cRoot);
end;

constructor TEdgeProjectFiles.CreateRelative(const AEdges: array of string);
begin
  CreateAt(AEdges, True, '');
end;

constructor TEdgeProjectFiles.CreateAt(const AEdges: array of string; AComplete: Boolean; const ARoot: string);
var
  mEntry, mSource, mTarget: string;
  mEdge: TGroupUsesEdge;
begin
  inherited Create;
  FComplete := AComplete;
  for mEntry in AEdges do
  begin
    mSource := Trim(Copy(mEntry, 1, Pos('->', mEntry) - 1));
    mTarget := Trim(Copy(mEntry, Pos('->', mEntry) + 2, MaxInt));
    mEdge := Default(TGroupUsesEdge);
    mEdge.SourceUnit := UnitOf(mSource);
    mEdge.SourceFileName := FileOf(ARoot, mSource);
    mEdge.TargetUnit := UnitOf(mTarget);
    mEdge.TargetFileName := FileOf(ARoot, mTarget);
    FEdges := FEdges + [mEdge];
  end;
end;

function TEdgeProjectFiles.Complete(out AReason: string): Boolean;
begin
  AReason := 'busy';
  Result := FComplete;
end;

function TEdgeProjectFiles.ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TGroupProject>;
begin
  Result := nil;
end;

function TEdgeProjectFiles.NameIn(const AFileName, AName: string): TNameAnswer;
begin
  Result := TNameAnswer.Unknown;
end;

function TEdgeProjectFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function TEdgeProjectFiles.UsesPath(const AFromUnit, AToFile: string;
  AInterfaceOnly: Boolean): TArray<TGroupUsesStep>;
begin
  Result := nil;
end;

function TEdgeProjectFiles.UsedBy(const AFileName: string; out AUsers: TArray<TGroupUsesStep>): Boolean;
begin
  AUsers := nil;
  Result := False;
end;

function TEdgeProjectFiles.UsesDerived(const AKey: string; const ADerive: TGroupUsesDerive): IInterface;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FKeys) do
  begin
    if FKeys[mIndex] = AKey then
    begin
      Exit(FValues[mIndex]);
    end;
  end;
  Inc(FDerives);
  Result := ADerive(FEdges);
  FKeys := FKeys + [AKey];
  SetLength(FValues, Length(FValues) + 1);
  FValues[High(FValues)] := Result;
end;

const
  cConfig = '{ "rules": { "architecture-feature-cycle": { "severity": "warning", "prefixes": ["Atlas.Core"]%s } } }';
  cLspSource =
    'unit Atlas.Core.Lsp.Session;'#10 +
    'interface'#10 +
    'uses System.SysUtils, Atlas.Core.Hover.Contract;'#10 +
    'implementation'#10 +
    'uses Atlas.Core.Files.Entries;'#10 +
    'end.';
  cCycleEdges: array[0..2] of string = (
    'Atlas.Core.Lsp.Session -> Atlas.Core.Hover.Contract',
    'Atlas.Core.Lsp.Session -> Atlas.Core.Files.Entries',
    'Atlas.Core.Hover.View -> Atlas.Core.Lsp.Contract');

function RunAt(const AFiles: IProjectGroupFiles; const AOptions, ARoot: string): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.RelativePath := 'Source/Atlas.Core.Lsp.Session.pas';
  mContext.FileName := ARoot + mContext.RelativePath;
  mContext.UnitName := 'Atlas.Core.Lsp.Session';
  mContext.Text := cLspSource;
  mContext.ProjectFiles := AFiles;
  Result := TRuleAssert.ContextFindings(TFeatureCycleRule.Create, mContext, Format(cConfig, [AOptions]));
end;

function Run(const AFiles: IProjectGroupFiles; const AOptions: string): TArray<TRuleFinding>;
begin
  Result := RunAt(AFiles, AOptions, cRoot);
end;

{ TFeatureCycleRuleTests }

procedure TFeatureCycleRuleTests.ReportsCycleAtUsesEntry;
var
  mFiles: IProjectGroupFiles;
  mFindings: TArray<TRuleFinding>;
begin
  mFiles := TEdgeProjectFiles.Create(cCycleEdges, True);
  mFindings := Run(mFiles, '');
  Assert.AreEqual(1, Integer(Length(mFindings)), 'nur der Eintrag im Zyklus');
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(22, mFindings[0].Range.StartPos.Character);
  Assert.IsTrue(Pos('Atlas.Core: Hover, Lsp', mFindings[0].Message) > 0, mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(TFeatureCycleRule.cRuleId, mFindings[0].RuleId);
  mFindings := nil;
end;

procedure TFeatureCycleRuleTests.ReportsDirection;
var
  mFiles: IProjectGroupFiles;
  mFindings: TArray<TRuleFinding>;
begin
  mFiles := TEdgeProjectFiles.Create(['Atlas.Core.Lsp.Session -> Atlas.Core.Files.Entries'], True);
  mFindings := Run(mFiles, ', "directions": ["Atlas.Core: Lsp < Files"]');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Line, 'implementation-uses zählt');
  Assert.IsTrue(Pos('Atlas.Core: Lsp < Files', mFindings[0].Message) > 0, mFindings[0].Message);
  mFindings := Run(mFiles, ', "directions": ["Atlas.Core: Lsp < Files"], ' +
    '"knownEdges": ["Atlas.Core.Lsp.Session -> Atlas.Core.Files.Entries"]');
  Assert.AreEqual(0, Integer(Length(mFindings)), 'bekannte Kante');
  mFindings := nil;
end;

procedure TFeatureCycleRuleTests.KnownCycleIsSilent;
var
  mFiles: IProjectGroupFiles;
begin
  mFiles := TEdgeProjectFiles.Create(cCycleEdges, True);
  Assert.AreEqual(0, Integer(Length(Run(mFiles, ', "known": ["Atlas.Core: Lsp, Hover, Problems"]'))),
    'Zyklus innerhalb eines Eintrags');
end;

procedure TFeatureCycleRuleTests.ExcludedPathsDoNotCount;
var
  mFiles: IProjectGroupFiles;
begin
  mFiles := TEdgeProjectFiles.Create(['Atlas.Core.Lsp.Session -> Atlas.Core.Hover.Contract',
    'Tests.Atlas.Core.Hover.TestSupport -> Atlas.Core.Lsp.Session'], True);
  Assert.AreEqual(1, Integer(Length(Run(mFiles, ''))), 'ohne exclude');
  mFiles := TEdgeProjectFiles.Create(['Atlas.Core.Lsp.Session -> Atlas.Core.Hover.Contract',
    'Tests.Atlas.Core.Hover.TestSupport -> Atlas.Core.Lsp.Session'], True);
  Assert.AreEqual(0, Integer(Length(Run(mFiles, ', "exclude": ["Tests/**"]'))), 'Pfad relativ zur Konfiguration');
end;

procedure TFeatureCycleRuleTests.SilentWithoutPrefixesOrIncompleteProjects;
var
  mFiles: IProjectGroupFiles;
  mContext: TRuleContext;
begin
  mFiles := TEdgeProjectFiles.Create(cCycleEdges, False);
  Assert.AreEqual(0, Integer(Length(Run(mFiles, ''))), 'Projekte noch nicht geladen');
  mContext := Default(TRuleContext);
  mContext.RelativePath := 'Source/Atlas.Core.Lsp.Session.pas';
  mContext.FileName := cRoot + mContext.RelativePath;
  mContext.Text := cLspSource;
  mContext.ProjectFiles := TEdgeProjectFiles.Create(cCycleEdges, True);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFeatureCycleRule.Create, mContext,
    '{ "rules": { "architecture-feature-cycle": "warning" } }'))), 'ohne prefixes');
  mContext.ProjectFiles := nil;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFeatureCycleRule.Create, mContext,
    Format(cConfig, [''])))), 'ohne Projekte');
  mContext := Default(TRuleContext);
end;

procedure TFeatureCycleRuleTests.AnalysisSharedByKey;
var
  mFiles: TEdgeProjectFiles;
  mHold: IProjectGroupFiles;
begin
  mFiles := TEdgeProjectFiles.Create(cCycleEdges, True);
  mHold := mFiles;
  Run(mHold, '');
  Run(mHold, '');
  Assert.AreEqual(1, mFiles.Derives, 'eine Auswertung für dieselben Optionen');
  Run(mHold, ', "known": ["Atlas.Core: Hover, Lsp"]');
  Assert.AreEqual(2, mFiles.Derives, 'andere Optionen, eigene Auswertung');
end;

procedure TFeatureCycleRuleTests.RootAndRelativePaths;
begin
  Assert.AreEqual('C:/Repo/', TFeatureCycleRule.RootOf('C:\Repo\Source\A.pas', 'Source/A.pas'));
  Assert.AreEqual('', TFeatureCycleRule.RootOf('C:\Repo\Source\A.pas', 'Other/A.pas'));
  Assert.AreEqual('', TFeatureCycleRule.RootOf('C:\Repo\Source\A.pas', ''));
  Assert.AreEqual('Tests/X.pas', TFeatureCycleRule.RelativeTo('C:/Repo/', 'c:\repo\Tests\X.pas'));
  Assert.AreEqual('', TFeatureCycleRule.RelativeTo('C:/Repo/', 'D:\Other\X.pas'));
  Assert.AreEqual('', TFeatureCycleRule.RelativeTo('', 'D:\Other\X.pas'));
end;

procedure TFeatureCycleRuleTests.RelativeFileNameKeepsExclude;
var
  mFiles: IProjectGroupFiles;
begin
  // Einzelne Datei prüfen: Datei und Kanten relativ zum aktuellen Ordner, der Ordner der Konfiguration.
  mFiles := TEdgeProjectFiles.CreateRelative(['Atlas.Core.Lsp.Session -> Atlas.Core.Hover.Contract',
    'Tests.Atlas.Core.Hover.TestSupport -> Atlas.Core.Lsp.Session']);
  Assert.AreEqual(0, Integer(Length(RunAt(mFiles, ', "exclude": ["Tests/**"]', ''))), 'Tests bleiben ausgenommen');
end;

initialization
  TDUnitX.RegisterTestFixture(TFeatureCycleRuleTests);

end.
