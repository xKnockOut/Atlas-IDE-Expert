unit Atlas.Common.Rules.Builtin.DuplicateBodies.Tests;

// Tests der Regel duplicate-routine-body: Kopie in einer anderen Unit, Schweigen ohne Projekt, bei unvollständigem
// Index, für Kopien in derselben Unit und unter minLines, aus im Profil standard, und der Katalog der Rümpfe: ein
// Verzeichnis je Projektgruppe, das alle Units teilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDuplicateRoutineBodyTests = class
  public
    /// <summary>Einmal-Belegungen (gemeinsamer Katalog, Regelwerk) vorwegnehmen; sie gehören nicht in die
    /// Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReportsCopyInOtherUnit;
    [Test]
    procedure NamesFurtherCopies;
    [Test]
    procedure SilentForCopiesInSameUnit;
    [Test]
    procedure SilentWithoutProjectOrWhileIndexing;
    [Test]
    procedure MinLinesOption;
    [Test]
    procedure OffInStandardProfile;
    [Test]
    procedure CatalogKeepsIndexForSameFiles;
    [Test]
    procedure CatalogReadsEachFileOncePerGroup;
    [Test]
    procedure CatalogIgnoresOrderOfFiles;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Metrics.DuplicateBodies,
  Atlas.Common.Metrics.DuplicateCatalog,
  Atlas.Common.Rules.Builtin.DuplicateBodies;

const
  cFileA = 'C:\P\Einheit.A.pas';
  cFileB = 'C:\P\Einheit.B.pas';
  cFileC = 'C:\P\Einheit.C.pas';
  cBody = 'begin'#10'  if A > 0 then'#10'  begin'#10'    Inc(B);'#10'    Writeln(''x'');'#10'  end;'#10'end;'#10;
  cOn = '{"rules": {"duplicate-routine-body": "hint"}}';

type
  /// <summary>Projektgruppe aus Texten im Speicher; zählt, wie oft jede Datei gelesen wird. ProjectsOf nennt wie
  /// der Server die angefragte Datei zuerst, die Reihenfolge hängt also von der geprüften Unit ab.</summary>
  TFakeProjectFiles = class(TInterfacedObject, IRuleProjectFiles)
  private
    FTexts: TDictionary<string, string>;
    FReads: TDictionary<string, Integer>;
    FComplete: Boolean;
  public
    constructor Create(AComplete: Boolean);
    destructor Destroy; override;
    procedure Put(const AFileName, AText: string);
    function ReadsOf(const AFileName: string): Integer;
    function Complete(out AReason: string): Boolean;
    function ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TRuleProject>;
    function NameIn(const AFileName, AName: string): TRuleNameAnswer;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function UsesPath(const AFromUnit, AToFile: string; AInterfaceOnly: Boolean): TArray<TRuleUsesStep>;
    function UsedBy(const AFileName: string; out AUsers: TArray<TRuleUsesStep>): Boolean;
  end;

constructor TFakeProjectFiles.Create(AComplete: Boolean);
begin
  inherited Create;
  FComplete := AComplete;
  FTexts := TDictionary<string, string>.Create;
  FReads := TDictionary<string, Integer>.Create;
end;

destructor TFakeProjectFiles.Destroy;
begin
  FReads.Free;
  FTexts.Free;
  inherited Destroy;
end;

procedure TFakeProjectFiles.Put(const AFileName, AText: string);
begin
  FTexts.AddOrSetValue(UpperCase(AFileName), AText);
end;

function TFakeProjectFiles.ReadsOf(const AFileName: string): Integer;
var
  mCount: Integer;
begin
  Result := 0;
  if FReads.TryGetValue(UpperCase(AFileName), mCount) then
  begin
    Result := mCount;
  end;
end;

function TFakeProjectFiles.Complete(out AReason: string): Boolean;
begin
  AReason := '';
  Result := FComplete;
  if not FComplete then
  begin
    AReason := 'Index läuft';
  end;
end;

function TFakeProjectFiles.ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TRuleProject>;
var
  mProject: TRuleProject;
  mKey: string;
begin
  mProject := Default(TRuleProject);
  mProject.FileName := 'C:\P\App.dproj';
  mProject.Kind := TRuleProjectKind.Application;
  if FTexts.ContainsKey(UpperCase(AFileName)) then
  begin
    mProject.Sources := mProject.Sources + [UpperCase(AFileName)];
  end;
  for mKey in FTexts.Keys do
  begin
    if mKey <> UpperCase(AFileName) then
    begin
      mProject.Sources := mProject.Sources + [mKey];
    end;
  end;
  Result := [mProject];
end;

function TFakeProjectFiles.NameIn(const AFileName, AName: string): TRuleNameAnswer;
begin
  Result := TRuleNameAnswer.Unknown;
end;

function TFakeProjectFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  FReads.AddOrSetValue(UpperCase(AFileName), ReadsOf(AFileName) + 1);
  Result := FTexts.TryGetValue(UpperCase(AFileName), AText);
end;

function TFakeProjectFiles.UsesPath(const AFromUnit, AToFile: string;
  AInterfaceOnly: Boolean): TArray<TRuleUsesStep>;
begin
  Result := nil;
end;

function TFakeProjectFiles.UsedBy(const AFileName: string; out AUsers: TArray<TRuleUsesStep>): Boolean;
begin
  AUsers := nil;
  Result := False;
end;

function UnitText(const AName, ARoutines: string): string;
begin
  Result := 'unit ' + AName + ';'#10'interface'#10'implementation'#10 + ARoutines + 'end.'#10;
end;

function SettingsOf(const AConfig: string): TServerSettings;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  if AConfig = '' then
  begin
    Result := TServerSettings.Default;
  end
  else
  begin
    Result := TConfigurationParser.Parse(AConfig, mIssues);
  end;
end;

/// <summary>Prüft AFileName aus AFiles (nil = ohne Projekt) mit der atlas.json AConfig.</summary>
function Run(const AFiles: IRuleProjectFiles; const AFileName, AText, AConfig: string): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    mContext := Default(TRuleContext);
    mContext.FileName := AFileName;
    mContext.RelativePath := ExtractFileName(AFileName);
    mContext.UnitName := ChangeFileExt(ExtractFileName(AFileName), '');
    mContext.Text := AText;
    mContext.Tree := mTree;
    mContext.ProjectFiles := AFiles;
    Result := TRuleEngine.Run([TDuplicateRoutineBodyRule.Create], SettingsOf(AConfig), mContext);
    mContext.ProjectFiles := nil;
  finally
    mTree.Free;
  end;
end;

procedure Fill(const AFiles: TFakeProjectFiles; const ATexts: array of string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATexts) div 2 do
  begin
    AFiles.Put(ATexts[2 * mIndex], ATexts[2 * mIndex + 1]);
  end;
end;

function Group(const ATexts: array of string; AComplete: Boolean): IRuleProjectFiles;
var
  mFiles: TFakeProjectFiles;
begin
  mFiles := TFakeProjectFiles.Create(AComplete);
  Result := mFiles;
  Fill(mFiles, ATexts);
end;

{ TDuplicateRoutineBodyTests }

procedure TDuplicateRoutineBodyTests.WarmUpFirstUse;
begin
  // Nur der erste Test der Fixture leckt: einmal ungemessen vorweg.
  try
    ReportsCopyInOtherUnit;
  finally
    TearDown;
  end;
end;

procedure TDuplicateRoutineBodyTests.TearDown;
begin
  TDuplicateBodyCatalog.Shared.Clear;
end;

procedure TDuplicateRoutineBodyTests.ReportsCopyInOtherUnit;
var
  mTextA: string;
  mFound: TArray<TRuleFinding>;
begin
  mTextA := UnitText('Einheit.A', 'procedure TA.Show;'#10 + cBody);
  mFound := Run(Group([cFileA, mTextA, cFileB, UnitText('Einheit.B', 'procedure TB.Show;'#10 + cBody)], True), cFileA,
    mTextA, cOn);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('duplicate-routine-body', mFound[0].RuleId);
  Assert.Contains(mFound[0].Message, 'TB.Show');
  Assert.Contains(mFound[0].Message, 'Einheit.B.pas');
  Assert.AreEqual(3, mFound[0].Range.StartPos.Line, 'am Kopf der Routine');
  Assert.Contains(mFound[0].Details, cFileB.ToUpper);
end;

procedure TDuplicateRoutineBodyTests.NamesFurtherCopies;
var
  mTextA: string;
  mFound: TArray<TRuleFinding>;
begin
  mTextA := UnitText('Einheit.A', 'procedure P;'#10 + cBody);
  mFound := Run(Group([cFileA, mTextA, cFileB, UnitText('Einheit.B', 'procedure Q;'#10 + cBody), cFileC,
    UnitText('Einheit.C', 'procedure R;'#10 + cBody)], True), cFileA, mTextA, cOn);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.Contains(mFound[0].Message, ' 1 ');
  Assert.AreEqual(2, Integer(Length(mFound[0].Details.Split([#10]))));
end;

procedure TDuplicateRoutineBodyTests.SilentForCopiesInSameUnit;
var
  mTextA: string;
begin
  mTextA := UnitText('Einheit.A', 'procedure P;'#10 + cBody + 'procedure Q;'#10 + cBody);
  Assert.AreEqual(0, Integer(Length(Run(Group([cFileA, mTextA, cFileB, UnitText('Einheit.B', '')], True), cFileA,
    mTextA, cOn))));
end;

procedure TDuplicateRoutineBodyTests.SilentWithoutProjectOrWhileIndexing;
var
  mTextA, mTextB: string;
begin
  mTextA := UnitText('Einheit.A', 'procedure P;'#10 + cBody);
  mTextB := UnitText('Einheit.B', 'procedure Q;'#10 + cBody);
  Assert.AreEqual(0, Integer(Length(Run(nil, cFileA, mTextA, cOn))), 'ohne Projekt');
  Assert.AreEqual(0, Integer(Length(Run(Group([cFileA, mTextA, cFileB, mTextB], False), cFileA, mTextA, cOn))),
    'Index unvollständig');
end;

procedure TDuplicateRoutineBodyTests.MinLinesOption;
var
  mTextA: string;
  mFiles: IRuleProjectFiles;
begin
  mTextA := UnitText('Einheit.A', 'procedure P;'#10 + cBody);
  mFiles := Group([cFileA, mTextA, cFileB, UnitText('Einheit.B', 'procedure Q;'#10 + cBody)], True);
  Assert.AreEqual(0, Integer(Length(Run(mFiles, cFileA, mTextA,
    '{"rules": {"duplicate-routine-body": {"severity": "hint", "minLines": 8}}}'))));
  Assert.AreEqual(1, Integer(Length(Run(mFiles, cFileA, mTextA,
    '{"rules": {"duplicate-routine-body": {"severity": "hint", "minLines": 7}}}'))));
end;

procedure TDuplicateRoutineBodyTests.OffInStandardProfile;
var
  mTextA: string;
begin
  mTextA := UnitText('Einheit.A', 'procedure P;'#10 + cBody);
  Assert.AreEqual(0, Integer(Length(Run(Group([cFileA, mTextA, cFileB, UnitText('Einheit.B', 'procedure Q;'#10 +
    cBody)], True), cFileA, mTextA, ''))));
end;

procedure TDuplicateRoutineBodyTests.CatalogKeepsIndexForSameFiles;
var
  mReads: Integer;
  mFirst, mSecond: IDuplicateBodyIndex;
  mHash: string;
begin
  mReads := 0;
  mHash := TDuplicateBodies.ForText(UnitText('X', 'procedure P;'#10 + cBody))[0].Hash;
  mFirst := TDuplicateBodyCatalog.Shared.IndexOf([cFileA, cFileB, 'C:\P\Form.dfm'],
    function(const AFileName: string; out AText: string): Boolean
    begin
      Inc(mReads);
      AText := UnitText('X', 'procedure P;'#10 + cBody);
      Result := True;
    end);
  Assert.AreEqual(2, mFirst.FileCount, 'nur Quelltexte');
  Assert.AreEqual(2, Integer(Length(mFirst.Copies(mHash))));
  mSecond := TDuplicateBodyCatalog.Shared.IndexOf([cFileA, cFileB, 'C:\P\Form.dfm'], nil);
  Assert.AreEqual(2, mReads, 'dasselbe Verzeichnis, nichts neu gelesen');
  Assert.AreEqual(2, mSecond.FileCount);
  mFirst := nil;
  mSecond := nil;
  mHash := '';
end;

procedure TDuplicateRoutineBodyTests.CatalogReadsEachFileOncePerGroup;
var
  mFake: TFakeProjectFiles;
  mFiles: IRuleProjectFiles;
  mTextA, mTextB, mTextC: string;
begin
  mTextA := UnitText('Einheit.A', 'procedure P;'#10 + cBody);
  mTextB := UnitText('Einheit.B', 'procedure Q;'#10 + cBody);
  mTextC := UnitText('Einheit.C', '');
  mFake := TFakeProjectFiles.Create(True);
  mFiles := mFake;
  Fill(mFake, [cFileA, mTextA, cFileB, mTextB, cFileC, mTextC]);
  Assert.AreEqual(1, Integer(Length(Run(mFiles, cFileA, mTextA, cOn))), 'A hat die Kopie in B');
  Assert.AreEqual(1, Integer(Length(Run(mFiles, cFileB, mTextB, cOn))), 'B hat die Kopie in A');
  Assert.AreEqual(0, Integer(Length(Run(mFiles, cFileC, mTextC, cOn))), 'C ohne Kopie');
  Assert.AreEqual(1, mFake.ReadsOf(cFileA), 'A einmal gelesen');
  Assert.AreEqual(1, mFake.ReadsOf(cFileB), 'B einmal gelesen');
  Assert.AreEqual(1, mFake.ReadsOf(cFileC), 'C einmal gelesen');
  mFiles := nil;
end;

procedure TDuplicateRoutineBodyTests.CatalogIgnoresOrderOfFiles;
var
  mReads: Integer;
  mFirst, mSecond: IDuplicateBodyIndex;
  mHash: string;
  mCopies: TArray<TDuplicateBodyMember>;
begin
  mReads := 0;
  mHash := TDuplicateBodies.ForText(UnitText('X', 'procedure P;'#10 + cBody))[0].Hash;
  mFirst := TDuplicateBodyCatalog.Shared.IndexOf([cFileB, cFileA],
    function(const AFileName: string; out AText: string): Boolean
    begin
      Inc(mReads);
      AText := UnitText('X', 'procedure P;'#10 + cBody);
      Result := True;
    end);
  mSecond := TDuplicateBodyCatalog.Shared.IndexOf([cFileA, cFileB], nil);
  Assert.AreEqual(2, mReads, 'dieselben Dateien in anderer Folge: dasselbe Verzeichnis');
  Assert.IsTrue(mFirst = mSecond, 'dasselbe Verzeichnis');
  mCopies := mSecond.Copies(mHash);
  Assert.AreEqual(2, Integer(Length(mCopies)));
  Assert.AreEqual(cFileA, mCopies[0].Path, 'Fassungen nach Pfad sortiert');
  mFirst := nil;
  mSecond := nil;
  mHash := '';
  mCopies := nil;
end;

end.
