unit Atlas.Common.Rules.Builtin.Testing.Registration.Tests;

// Tests der Regel dunitx-fixture-not-registered (#1882): Testklasse ohne Registrierung in einem Projekt, dessen
// Runner nicht über RTTI sucht, mit Korrektur (neuer initialization-Abschnitt bzw. Zeile im vorhandenen),
// Registrierung über eine Hilfsroutine, die Option registrationCalls, stille Klassen (abstrakt, generisch,
// Vorfahr), Runner mit UseRTTI (nur Klassen ohne [TestFixture], Korrektur [TestFixture]), ohne Projekte still,
// Registrierung in einer anderen Unit des Projekts und die Unit, die in keinem Testprojekt steht, samt
// Korrektur in .dpr und .dproj.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDUnitXFixtureNotRegisteredTests = class
  public
    [Test]
    procedure FixtureWithoutRegistrationGetsInitialization;
    [Test]
    procedure FixAppendsToExistingInitialization;
    [Test]
    procedure RegistrationThroughRoutineOrOption;
    [Test]
    procedure AbstractGenericAndAncestorsAreSilent;
    [Test]
    procedure RttiRunnerFindsFixtureAttribute;
    [Test]
    procedure SilentWithoutProjects;
    [Test]
    procedure RegisteredInOtherUnitOfProject;
    [Test]
    procedure UnitMissingFromTestProject;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Rules.Builtin.Testing.Registration,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

const
  cHead = 'unit Fall.Tests;'#10'interface'#10'uses'#10'  DUnitX.TestFramework;'#10'type'#10;
  /// <summary>.dpr mit einem Runner, der nicht über RTTI sucht.</summary>
  cPlainRunner = 'program Tests;'#10'uses'#10'  DUnitX.TestFramework,'#10'  Fall.Tests in ''Src\Fall.Tests.pas'';'#10 +
    'var'#10'  R: ITestRunner;'#10'begin'#10'  R := TDUnitX.CreateRunner;'#10'end.';
  /// <summary>.dpr wie die Vorlage von DUnitX: der Runner findet [TestFixture]-Klassen selbst.</summary>
  cRttiRunner = 'program Tests;'#10'uses'#10'  DUnitX.TestFramework,'#10'  Fall.Tests in ''Src\Fall.Tests.pas'';'#10 +
    'var'#10'  R: ITestRunner;'#10'begin'#10'  R := TDUnitX.CreateRunner;'#10'  R.UseRTTI := True;'#10'end.';

/// <summary>Testunit mit den Typen ATypes und dem Rest ab implementation.</summary>
function TestUnit(const ATypes, ATail: string): string;
begin
  Result := cHead + ATypes + 'implementation'#10 + ATail;
end;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message;
  end;
end;

/// <summary>Ordner der gedachten Projekte, mit Trennzeichen am Ende.</summary>
function Base: string;
begin
  Result := IncludeTrailingPathDelimiter(GetCurrentDir) + 'Fall' + PathDelim;
end;

function UnitFile: string;
begin
  Result := Base + 'Src' + PathDelim + 'Fall.Tests.pas';
end;

function MakeProject(const AFileName: string; AIsTest: Boolean; const ASources: TArray<string>): TRuleProject;
begin
  Result := Default(TRuleProject);
  Result.FileName := AFileName;
  Result.Kind := TRuleProjectKind.Application;
  Result.IsTest := AIsTest;
  Result.Sources := ASources;
end;

/// <summary>Befunde für die Unit Base + Src/Fall.Tests.pas mit den Projekten AProjects und den Dateien ATexts.
/// </summary>
function ProjectFindings(const ASource: string; const AProjects: TArray<TRuleProject>;
  const ATexts: TDictionary<string, string>; const AConfig: string): TArray<TRuleFinding>; overload;
var
  mContext: TRuleContext;
  mTexts: TDictionary<string, string>;
begin
  mTexts := ATexts;
  mContext := Default(TRuleContext);
  mContext.FileName := UnitFile;
  mContext.RelativePath := 'Src/Fall.Tests.pas';
  mContext.UnitName := 'Fall.Tests';
  mContext.Text := ASource;
  mContext.ProjectFiles := TRuleProjectFiles.Create(AProjects, nil,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mTexts.TryGetValue(AFileName, AText);
    end, nil);
  Result := TRuleAssert.ContextFindings(TDUnitXFixtureNotRegisteredRule.Create, mContext, AConfig);
end;

function ProjectFindings(const ASource: string; const AProjects: TArray<TRuleProject>; const ATexts: TDictionary<string,
  string>): TArray<TRuleFinding>; overload;
begin
  Result := ProjectFindings(ASource, AProjects, ATexts, '');
end;

/// <summary>Befunde mit einem Testprojekt Tests.dproj, das die Unit enthält, und der .dpr ADpr.</summary>
function Findings(const ASource, ADpr: string; const AConfig: string): TArray<TRuleFinding>; overload;
var
  mTexts: TDictionary<string, string>;
begin
  mTexts := TDictionary<string, string>.Create;
  try
    mTexts.Add(Base + 'Tests.dpr', ADpr);
    Result := ProjectFindings(ASource, [MakeProject(Base + 'Tests.dproj', True, [Base + 'Tests.dpr', UnitFile])],
      mTexts, AConfig);
  finally
    mTexts.Free;
  end;
end;

function Findings(const ASource, ADpr: string): TArray<TRuleFinding>; overload;
begin
  Result := Findings(ASource, ADpr, '');
end;

{ TDUnitXFixtureNotRegisteredTests }

procedure TDUnitXFixtureNotRegisteredTests.FixtureWithoutRegistrationGetsInitialization;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := TestUnit('  [TestFixture]'#10'  TRechnerTests = class'#10'  end;'#10, 'end.');
  mFound := Findings(mSource, cPlainRunner);
  Assert.AreEqual('6: TRechnerTests wird nie registriert: DUnitX kennt die Klasse nicht, ihre Tests laufen nie.',
    Messages(mFound));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual(TestUnit('  [TestFixture]'#10'  TRechnerTests = class'#10'  end;'#10, 'initialization'#10 +
    '  TDUnitX.RegisterTestFixture(TRechnerTests);'#10#10'end.'), TChangeSignature.ApplyEdits(mSource,
    mFound[0].Fixes[0].Edits));
  // Mit finalization kommt initialization davor.
  mSource := TestUnit('  [TestFixture]'#10'  TRechnerTests = class'#10'  end;'#10, 'finalization'#10'end.');
  Assert.AreEqual(TestUnit('  [TestFixture]'#10'  TRechnerTests = class'#10'  end;'#10, 'initialization'#10 +
    '  TDUnitX.RegisterTestFixture(TRechnerTests);'#10#10'finalization'#10'end.'),
    TChangeSignature.ApplyEdits(mSource, Findings(mSource, cPlainRunner)[0].Fixes[0].Edits));
end;

procedure TDUnitXFixtureNotRegisteredTests.FixAppendsToExistingInitialization;
var
  mTypes, mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mTypes := '  [TestFixture]'#10'  TA = class'#10'  end;'#10'  [TestFixture(''B'')]'#10'  TB = class'#10'  end;'#10;
  mSource := TestUnit(mTypes, 'initialization'#10'  TDUnitX.RegisterTestFixture(TA);'#10'end.');
  mFound := Findings(mSource, cPlainRunner);
  Assert.AreEqual('9: TB wird nie registriert: DUnitX kennt die Klasse nicht, ihre Tests laufen nie.',
    Messages(mFound));
  Assert.AreEqual(TestUnit(mTypes, 'initialization'#10'  TDUnitX.RegisterTestFixture(TA);'#10 +
    '  TDUnitX.RegisterTestFixture(TB);'#10'end.'), TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits));
  // Letzte Anweisung ohne Semikolon.
  mSource := TestUnit(mTypes, 'initialization'#10'  TDUnitX.RegisterTestFixture(TA)'#10'end.');
  Assert.AreEqual(TestUnit(mTypes, 'initialization'#10'  TDUnitX.RegisterTestFixture(TA);'#10 +
    '  TDUnitX.RegisterTestFixture(TB);'#10'end.'), TChangeSignature.ApplyEdits(mSource,
    Findings(mSource, cPlainRunner)[0].Fixes[0].Edits));
end;

procedure TDUnitXFixtureNotRegisteredTests.RegistrationThroughRoutineOrOption;
var
  mTypes: string;
begin
  mTypes := '  [TestFixture]'#10'  TA = class'#10'  end;'#10'  [TestFixture]'#10'  TB = class'#10'  end;'#10;
  // Eigene Hilfsroutine, die zwei Ebenen tief registriert.
  Assert.AreEqual('', Messages(Findings(TestUnit(mTypes, 'procedure Alle(const AKlassen: array of TClass);'#10 +
    'begin'#10'end;'#10'procedure Innen;'#10'begin'#10'  Alle([TA, TB]);'#10'end;'#10 +
    'procedure Registriere;'#10'begin'#10'  Innen;'#10'end;'#10'initialization'#10'  Registriere;'#10'end.'),
    cPlainRunner)));
  // Eigene Registrierfunktion, die alle Klassen findet.
  Assert.AreEqual('', Messages(Findings(TestUnit(mTypes, 'initialization'#10'  TTestSuche.RegistriereAlle;'#10 +
    'end.'), cPlainRunner,
    '{"rules": {"dunitx-fixture-not-registered": {"registrationCalls": ["TTestSuche.RegistriereAlle"]}}}')));
  Assert.AreEqual(2, Integer(Length(Findings(TestUnit(mTypes, 'initialization'#10'  TTestSuche.RegistriereAlle;'#10 +
    'end.'), cPlainRunner))));
end;

procedure TDUnitXFixtureNotRegisteredTests.AbstractGenericAndAncestorsAreSilent;
begin
  Assert.AreEqual('', Messages(Findings(TestUnit('  [TestFixture]'#10'  TBasis = class abstract'#10'  end;'#10 +
    '  [TestFixture]'#10'  TListe<T> = class'#10'  end;'#10'  [TestFixture]'#10'  TVorfahr = class'#10'  end;'#10 +
    '  [TestFixture]'#10'  TKind = class(TVorfahr)'#10'  end;'#10,
    'initialization'#10'  TDUnitX.RegisterTestFixture(TKind);'#10'end.'), cPlainRunner)));
  // Keine Testunit.
  Assert.AreEqual('', Messages(Findings(StringReplace(TestUnit('  [TestFixture]'#10'  TA = class'#10'  end;'#10,
    'end.'), 'DUnitX.TestFramework', 'System.Classes', []), cPlainRunner)));
end;

procedure TDUnitXFixtureNotRegisteredTests.RttiRunnerFindsFixtureAttribute;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  // [TestFixture] genügt, wenn der Runner über RTTI sucht (Vorlage von DUnitX) oder die .dpr keinen anlegt.
  mSource := TestUnit('  [TestFixture]'#10'  TA = class'#10'  end;'#10, 'end.');
  Assert.AreEqual('', Messages(Findings(mSource, cRttiRunner)));
  Assert.AreEqual('', Messages(Findings(mSource, 'program Tests;'#10'begin'#10'  RunRegisteredTests;'#10'end.')));
  // Ohne [TestFixture] findet RTTI die Klasse nicht.
  mSource := TestUnit('  TA = class'#10'  public'#10'    [Test]'#10'    procedure Eins;'#10'  end;'#10,
    'procedure TA.Eins;'#10'begin'#10'end;'#10'end.');
  mFound := Findings(mSource, cRttiRunner);
  Assert.AreEqual('5: TA hat weder [TestFixture] noch eine Registrierung: DUnitX findet die Klasse nicht, ihre ' +
    'Tests laufen nie.', Messages(mFound));
  Assert.AreEqual(2, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual(StringReplace(mSource, '  TA = class', '  [TestFixture]'#10'  TA = class', []),
    TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits));
  Assert.IsTrue(mFound[0].Fixes[1].Alternative);
end;

procedure TDUnitXFixtureNotRegisteredTests.SilentWithoutProjects;
begin
  // Ohne Projekte ist offen, ob der Runner über RTTI sucht.
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TDUnitXFixtureNotRegisteredRule.Create,
    TestUnit('  [TestFixture]'#10'  TA = class'#10'  end;'#10, 'end.'), '', 'Fall.Tests.pas')));
end;

procedure TDUnitXFixtureNotRegisteredTests.RegisteredInOtherUnitOfProject;
var
  mSource: string;
  mTexts: TDictionary<string, string>;
  mProject: TRuleProject;
begin
  mSource := TestUnit('  [TestFixture]'#10'  TA = class'#10'  end;'#10, 'end.');
  mTexts := TDictionary<string, string>.Create;
  try
    mProject := MakeProject(Base + 'Tests.dproj', True, [Base + 'Tests.dpr', UnitFile, Base + 'Registrierung.pas']);
    mTexts.Add(Base + 'Tests.dpr', cPlainRunner);
    mTexts.Add(Base + 'Registrierung.pas', 'unit Registrierung;'#10'interface'#10'implementation'#10'uses'#10 +
      '  Fall.Tests;'#10'initialization'#10'  TDUnitX.RegisterTestFixture(TA);'#10'end.');
    Assert.AreEqual('', Messages(ProjectFindings(mSource, [mProject], mTexts)));
    mTexts.AddOrSetValue(Base + 'Registrierung.pas', 'unit Registrierung;'#10'interface'#10'implementation'#10'end.');
    Assert.AreEqual(1, Integer(Length(ProjectFindings(mSource, [mProject], mTexts))));
  finally
    mTexts.Free;
  end;
end;

procedure TDUnitXFixtureNotRegisteredTests.UnitMissingFromTestProject;
var
  mSource, mDpr, mDproj: string;
  mTexts: TDictionary<string, string>;
  mFound: TArray<TRuleFinding>;
  mOther: TRuleFileEdits;
begin
  mSource := TestUnit('  [TestFixture]'#10'  TA = class'#10'  end;'#10, 'initialization'#10 +
    '  TDUnitX.RegisterTestFixture(TA);'#10'end.');
  mDpr := 'program Tests;'#10'uses'#10'  DUnitX.TestFramework,'#10'  Alt.Tests in ''Alt.Tests.pas'';'#10 +
    'begin'#10'end.';
  mDproj := '<Project>'#10'    <ItemGroup>'#10'        <DelphiCompile Include="Tests.dpr"/>'#10 +
    '        <DCCReference Include="Alt.Tests.pas"/>'#10'    </ItemGroup>'#10'</Project>';
  mTexts := TDictionary<string, string>.Create;
  try
    mTexts.Add(Base + 'Tests.dpr', mDpr);
    mTexts.Add(Base + 'Tests.dproj', mDproj);
    mFound := ProjectFindings(mSource, [MakeProject(Base + 'App.dproj', False, [Base + 'App.dpr']),
      MakeProject(Base + 'Tests.dproj', True, [Base + 'Tests.dpr', Base + 'Alt.Tests.pas'])], mTexts);
    Assert.AreEqual('6: Die Unit steht in keinem Testprojekt (Tests.dproj): Ihre Tests laufen nie.',
      Messages(mFound));
    Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
    Assert.AreEqual(2, Integer(Length(mFound[0].Fixes[0].OtherFiles)));
    mOther := mFound[0].Fixes[0].OtherFiles[0];
    Assert.AreEqual(Base + 'Tests.dpr', mOther.FileName);
    Assert.AreEqual(StringReplace(mDpr, '''Alt.Tests.pas''', '''Alt.Tests.pas'','#10 +
      '  Fall.Tests in ''Src\Fall.Tests.pas''', []), TChangeSignature.ApplyEdits(mDpr, mOther.Edits));
    mOther := mFound[0].Fixes[0].OtherFiles[1];
    Assert.AreEqual(StringReplace(mDproj, '"Alt.Tests.pas"/>'#10, '"Alt.Tests.pas"/>'#10 +
      '        <DCCReference Include="Src\Fall.Tests.pas"/>'#10, []), TChangeSignature.ApplyEdits(mDproj,
      mOther.Edits));
    // Zwei Testprojekte: Meldung ohne Korrektur.
    mFound := ProjectFindings(mSource, [MakeProject(Base + 'Tests.dproj', True, [Base + 'Tests.dpr']),
      MakeProject(Base + 'Mehr.dproj', True, [Base + 'Mehr.dpr'])], mTexts);
    Assert.AreEqual('6: Die Unit steht in keinem Testprojekt (Tests.dproj, Mehr.dproj): Ihre Tests laufen nie.',
      Messages(mFound));
    Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
    // Ohne Testprojekt in der Gruppe: still.
    Assert.AreEqual('', Messages(ProjectFindings(mSource, [MakeProject(Base + 'App.dproj', False,
      [Base + 'App.dpr'])], mTexts)));
  finally
    mTexts.Free;
  end;
  mOther := Default(TRuleFileEdits);
end;

procedure TDUnitXFixtureNotRegisteredTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    mFound := mFound or (mRule.Descriptor.Id = cDUnitXFixtureNotRegisteredRuleId);
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TDUnitXFixtureNotRegisteredTests);

end.
