unit Atlas.Common.Rules.Builtin.PublicMembers.Tests;

// Tests der Regel unused-public-member (#1102): Beispiel aus dem Issue,
// Verwendungen aus anderen Units (Aufruf, Methodenzeiger, inherited, Formular,
// String-Literal), gleichnamige Mitglieder anderer Klassen, Typen und globale
// Variablen des interface-Teils samt deadCode.keep* (#64), Schweigen bei
// unvollständigem Index, nicht lesbaren Dateien, Packages, Include-Dateien und
// unbekannten Vorfahren, alle Optionen, off/exclude, die Neuprüfung nach einer
// Änderung in einer anderen Unit und eine Zeitmessung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnusedPublicMemberTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure UsesInOtherUnitsAreFound;
    [Test]
    procedure SameNameOfOtherClassDoesNotCount;
    [Test]
    procedure RecursionIsNoUse;
    [Test]
    procedure OtherOverloadCallIsUse;
    [Test]
    procedure SilentWhileIndexIncomplete;
    [Test]
    procedure SilentWhenFileUnreadable;
    [Test]
    procedure PackagesOnlyWithOption;
    [Test]
    procedure SilentWithIncludeOrUnknownAncestor;
    [Test]
    procedure UnitLevelRoutinesAndConstants;
    [Test]
    procedure UnitTypesAndVariables;
    [Test]
    procedure DeadCodeKeepSettings;
    [Test]
    procedure VisibilitiesAndMemberKinds;
    [Test]
    procedure ProtectedBodyIsNoCandidate;
    [Test]
    procedure ScopeProjectOrGroup;
    [Test]
    procedure TestsCountAsUseOption;
    [Test]
    procedure StringLiteralsOption;
    [Test]
    procedure KeepAttributesAndPatterns;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure PublishedWithUnreadableFormOrRegistration;
    [Test]
    procedure ParserChecksOptions;
    [Test]
    procedure RecheckAfterChangeInOtherUnit;
    [Test]
    procedure IgnoreFixInsertsComment;
    [Test]
    procedure ReferenceProjectMatchesMarkers;
    [Test]
    [Category('Benchmark')]
    procedure CheckOfLargeProject;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Rules.Builtin.PublicMembers;

const
  cRoot = 'C:\P\';
  cServiceFile = 'C:\P\Kunden.Service.pas';
  cMainFile = 'C:\P\Kunden.Main.pas';
  cAppFile = 'C:\P\App.dpr';
  cFormFile = 'C:\P\Kunden.Main.dfm';

type
  TTestFile = record
    Name: string;
    Text: string;
  end;

  /// <summary>Projekte, Dateien und Einstellungen eines Testlaufs.</summary>
  TScenario = record
    Files: TArray<TTestFile>;
    Projects: TArray<TRuleProject>;
    Config: string;
    Unreadable: string;
    Incomplete: Boolean;
    procedure Put(const AName, AText: string);
    function Text(const AName: string): string;
  end;

procedure TScenario.Put(const AName, AText: string);
var
  mIndex: Integer;
  mEntry: TTestFile;
begin
  for mIndex := 0 to High(Files) do
  begin
    if SameText(Files[mIndex].Name, AName) then
    begin
      Files[mIndex].Text := AText;
      Exit;
    end;
  end;
  mEntry.Name := AName;
  mEntry.Text := AText;
  Files := Files + [mEntry];
end;

function TScenario.Text(const AName: string): string;
var
  mEntry: TTestFile;
begin
  Result := '';
  for mEntry in Files do
  begin
    if SameText(mEntry.Name, AName) then
    begin
      Result := mEntry.Text;
    end;
  end;
end;

const
  cSystemText = 'unit System;'#10'interface'#10'type'#10'  TObject = class'#10'  public'#10 +
    '    procedure Free;'#10'    function MethodAddress(const AName: string): Pointer;'#10'  end;'#10 +
    '  IInterface = interface'#10'    function _AddRef: Integer;'#10'  end;'#10 +
    '  TInterfacedObject = class(TObject, IInterface)'#10'  public'#10'    function _AddRef: Integer;'#10'  end;'#10 +
    '  TCustomAttribute = class(TObject)'#10'  end;'#10 +
    'implementation'#10'procedure TObject.Free;'#10'begin'#10'end;'#10 +
    'function TObject.MethodAddress(const AName: string): Pointer;'#10'begin'#10'  Result := nil;'#10'end;'#10 +
    'function TInterfacedObject._AddRef: Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10'end.';

  cServiceText =
    'unit Kunden.Service;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  end;'#10 +
    '  TKundenService = class'#10 +
    '  private'#10 +
    '    FFehler: string;'#10 +
    '  public'#10 +
    '    const'#10 +
    '      MaxKunden = 5000;'#10 +
    '    function Lade(const Nr: Integer): TKunde;'#10 +
    '    procedure ExportiereAlsXml(const Datei: string);'#10 +
    '    procedure Speichere(Kunde: TKunde); virtual;'#10 +
    '    property LetzterFehler: string read FFehler;'#10 +
    '  published'#10 +
    '    procedure KundeGeaendert(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TKundenService.Lade(const Nr: Integer): TKunde;'#10 +
    'begin'#10 +
    '  Result := nil;'#10 +
    'end;'#10 +
    'procedure TKundenService.ExportiereAlsXml(const Datei: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TKundenService.Speichere(Kunde: TKunde);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TKundenService.KundeGeaendert(Sender: TObject);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

/// <summary>Unit Kunden.Main mit der Routine Start; ABody steht in Start, S ist ein TKundenService.</summary>
function MainText(const ABody: string): string;
begin
  Result := 'unit Kunden.Main;'#10'interface'#10'uses'#10'  Kunden.Service;'#10'procedure Start;'#10 +
    'implementation'#10'procedure Start;'#10'var'#10'  S: TKundenService;'#10'begin'#10 +
    '  S := TKundenService.Create;'#10'  S.Lade(1);'#10 + ABody + 'end;'#10'end.';
end;

function Project(const AFileName: string; AKind: TRuleProjectKind; AIsTest: Boolean;
  const ASources, AForms: TArray<string>): TRuleProject;
begin
  Result := Default(TRuleProject);
  Result.FileName := AFileName;
  Result.Kind := AKind;
  Result.IsTest := AIsTest;
  Result.Sources := ASources;
  Result.Forms := AForms;
end;

/// <summary>Anwendung App mit Kunden.Service, Kunden.Main und Formular; ABody in Start.</summary>
function Scenario(const ABody: string): TScenario;
begin
  Result := Default(TScenario);
  Result.Put(cAppFile, 'program App;'#10'uses'#10'  Kunden.Service, Kunden.Main;'#10'begin'#10'  Start;'#10'end.');
  Result.Put(cServiceFile, cServiceText);
  Result.Put(cMainFile, MainText(ABody));
  Result.Put(cFormFile, 'object Hauptfenster: THauptfenster'#10'  OnClick = KundeGeaendert'#10'end');
  Result.Projects := [Project('C:\P\App.dproj', TRuleProjectKind.Application, False,
    [cAppFile, cServiceFile, cMainFile], [cFormFile])];
end;

/// <summary>Vorgaben oder die atlas.json des Szenarios.</summary>
function ScenarioSettings(const AConfig: string): TServerSettings;
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

/// <summary>Index über die Units des Szenarios; ATexts nimmt alle Dateien nach Namen auf.</summary>
function IndexScenario(const AScenario: TScenario; const ATexts: TDictionary<string, string>): ISymbolIndex;
var
  mEntry: TTestFile;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(cSystemText, 'C:\BDS\source\System.pas', nil));
  for mEntry in AScenario.Files do
  begin
    ATexts.AddOrSetValue(UpperCase(mEntry.Name), mEntry.Text);
    if not SameText(ExtractFileExt(mEntry.Name), '.dfm') then
    begin
      Result.AddUnit(TIndexExtractor.ExtractText(mEntry.Text, mEntry.Name, nil, nil, True));
    end;
  end;
end;

function Run(const AScenario: TScenario; const ACheck: string): TArray<TRuleFinding>;
var
  mTexts: TDictionary<string, string>;
  mIndex: ISymbolIndex;
  mSettings: TServerSettings;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mUnreadable: string;
  mIncomplete: Boolean;
begin
  mUnreadable := AScenario.Unreadable;
  mIncomplete := AScenario.Incomplete;
  mTexts := TDictionary<string, string>.Create;
  try
    mIndex := IndexScenario(AScenario, mTexts);
    mSettings := ScenarioSettings(AScenario.Config);
    mTree := TSyntaxTreeCache.Parse(AScenario.Text(ACheck));
    try
      mContext := Default(TRuleContext);
      mContext.FileName := ACheck;
      mContext.RelativePath := StringReplace(Copy(ACheck, Length(cRoot) + 1, MaxInt), '\', '/', [rfReplaceAll]);
      mContext.UnitName := ChangeFileExt(ExtractFileName(ACheck), '');
      mContext.Text := AScenario.Text(ACheck);
      mContext.Tree := mTree;
      mContext.Index := mIndex;
      mContext.ProjectFiles := TRuleProjectFiles.Create(AScenario.Projects, mIndex,
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := not SameText(AFileName, mUnreadable) and mTexts.TryGetValue(UpperCase(AFileName), AText);
        end,
        function(out AReason: string): Boolean
        begin
          Result := not mIncomplete;
          if mIncomplete then
          begin
            AReason := 'Index läuft (1 von 3 Units)';
          end;
        end);
      Result := TRuleEngine.Run([TUnusedPublicMemberRule.Create], mSettings, mContext);
      mContext.ProjectFiles := nil;
    finally
      mTree.Free;
    end;
  finally
    mTexts.Free;
  end;
end;

function Messages(const AFindings: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFindings do
  begin
    Result := Result + mFinding.Message + #10;
  end;
end;

procedure TUnusedPublicMemberTests.IssueExample;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Run(Scenario(''), cServiceFile);
  Assert.AreEqual(
    'Öffentliche Konstante TKundenService.MaxKunden wird im Projekt nirgends verwendet.'#10 +
    'Öffentliche Methode TKundenService.ExportiereAlsXml wird im Projekt nirgends verwendet.'#10 +
    'Öffentliche Property TKundenService.LetzterFehler wird im Projekt nirgends verwendet.'#10, Messages(mFound));
  Assert.AreEqual(12, mFound[1].Range.StartPos.Line);
  Assert.AreEqual(14, mFound[1].Range.StartPos.Character);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, mFound[1].Severity);
  Assert.AreEqual<TRuleConfidence>(TRuleConfidence.Medium, mFound[1].Confidence);
  // Durchsuchter Bereich für den Befund-Hover: App.dpr, zwei Units und die Formulardatei.
  Assert.AreEqual('Durchsucht: 3 Dateien und 1 Formular der Projektgruppe', mFound[1].Details);
end;

procedure TUnusedPublicMemberTests.UsesInOtherUnitsAreFound;
var
  mData: TScenario;
begin
  // Korrigierte Form: alle drei verwendet.
  mData := Scenario('  S.ExportiereAlsXml(''x'');'#10'  if S.LetzterFehler = '''' then'#10 +
    '    Writeln(TKundenService.MaxKunden);'#10);
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
  // Methodenzeiger.
  mData := Scenario('  P := S.ExportiereAlsXml;'#10);
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
  // inherited in einem Nachfahren einer anderen Unit.
  mData := Scenario('');
  mData.Put(cMainFile, 'unit Kunden.Main;'#10'interface'#10'uses'#10'  Kunden.Service;'#10'type'#10 +
    '  TSonder = class(TKundenService)'#10'  public'#10'    procedure ExportiereAlsXml(const Datei: string);'#10 +
    '  end;'#10'procedure Start;'#10'implementation'#10'procedure TSonder.ExportiereAlsXml(const Datei: string);'#10 +
    'begin'#10'  inherited ExportiereAlsXml(Datei);'#10'end;'#10'procedure Start;'#10'begin'#10 +
    '  TSonder.Create.ExportiereAlsXml(''y'');'#10'end;'#10'end.');
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('TKundenService.ExportiereAlsXml'));
  // Published-Methode ohne Formular: gemeldet.
  mData := Scenario('');
  mData.Put(cFormFile, 'object Hauptfenster: THauptfenster'#10'end');
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains(
    'Published-Methode TKundenService.KundeGeaendert wird im Projekt nirgends verwendet.'));
end;

procedure TUnusedPublicMemberTests.SameNameOfOtherClassDoesNotCount;
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Put(cMainFile, 'unit Kunden.Main;'#10'interface'#10'type'#10'  TAndere = class'#10'  public'#10 +
    '    procedure ExportiereAlsXml(const Datei: string);'#10'  end;'#10'procedure Start;'#10'implementation'#10 +
    'procedure TAndere.ExportiereAlsXml(const Datei: string);'#10'begin'#10'end;'#10'procedure Start;'#10 +
    'var'#10'  A: TAndere;'#10'begin'#10'  A := TAndere.Create;'#10'  A.ExportiereAlsXml(''x'');'#10'end;'#10'end.');
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains('TKundenService.ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.RecursionIsNoUse;
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Put(cServiceFile, StringReplace(cServiceText, 'procedure TKundenService.ExportiereAlsXml(const Datei: string);'#10 +
    'begin'#10, 'procedure TKundenService.ExportiereAlsXml(const Datei: string);'#10'begin'#10 +
    '  ExportiereAlsXml(Datei);'#10, []));
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains('TKundenService.ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.OtherOverloadCallIsUse;
var
  mData: TScenario;
  mFound: string;
begin
  // Die Überladung mit Datei ruft die mit Datei und Format auf: Das ist eine Verwendung, kein eigener Rumpf.
  mData := Scenario('  S.Drucke(''x'');'#10);
  mData.Put(cServiceFile, StringReplace(StringReplace(cServiceText,
    '  published'#10, '    procedure Drucke(const Datei: string); overload;'#10 +
    '    procedure Drucke(const Datei: string; Format: Integer); overload;'#10'  published'#10, []),
    'procedure TKundenService.Speichere(', 'procedure TKundenService.Drucke(const Datei: string);'#10 +
    'begin'#10'  Drucke(Datei, 0);'#10'end;'#10 +
    'procedure TKundenService.Drucke(const Datei: string; Format: Integer);'#10'begin'#10'end;'#10 +
    'procedure TKundenService.Speichere(', []));
  mFound := Messages(Run(mData, cServiceFile));
  Assert.IsFalse(mFound.Contains('TKundenService.Drucke'), mFound);
  // Ohne Aufruf von außen bleibt die äußere Überladung unbenutzt; ihr eigener Rumpf zählt nicht.
  mData.Put(cMainFile, MainText(''));
  mFound := Messages(Run(mData, cServiceFile));
  Assert.IsTrue(mFound.Contains('TKundenService.Drucke'), mFound);
end;

procedure TUnusedPublicMemberTests.SilentWhileIndexIncomplete;
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Incomplete := True;
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
end;

procedure TUnusedPublicMemberTests.SilentWhenFileUnreadable;
var
  mData: TScenario;
  mFound: string;
begin
  // Kommt der Name in einer nicht lesbaren Datei vor, ist keine Aussage möglich.
  mData := Scenario('  S.ExportiereAlsXml(''x'');'#10);
  mData.Unreadable := cMainFile;
  mFound := Messages(Run(mData, cServiceFile));
  Assert.IsFalse(mFound.Contains('ExportiereAlsXml'), mFound);
end;

procedure TUnusedPublicMemberTests.PackagesOnlyWithOption;
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Projects[0].Kind := TRuleProjectKind.Package;
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
  mData.Config := '{"rules": {"unused-public-member": {"projectKinds": ["application", "package"]}}}';
  Assert.AreEqual(3, Integer(Length(Run(mData, cServiceFile))));
  // Eine Unit in Anwendung und DLL: die DLL hat fremde Nutzer.
  mData := Scenario('');
  mData.Projects := mData.Projects + [Project('C:\P\Export.dproj', TRuleProjectKind.Library_, False,
    ['C:\P\Export.dpr', cServiceFile], nil)];
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
end;

procedure TUnusedPublicMemberTests.SilentWithIncludeOrUnknownAncestor;
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Put(cServiceFile, StringReplace(cServiceText, 'implementation'#10, 'implementation'#10'{$I Extra.inc}'#10, []));
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
  mData := Scenario('');
  mData.Put(cServiceFile, StringReplace(cServiceText, 'TKundenService = class'#10, 'TKundenService = class(TUnbekannt)'#10,
    []));
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
end;

procedure TUnusedPublicMemberTests.UnitLevelRoutinesAndConstants;
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Put(cServiceFile, StringReplace(cServiceText, 'implementation'#10,
    'const'#10'  Version = 3;'#10'procedure Aufraeumen;'#10'implementation'#10'procedure Aufraeumen;'#10'begin'#10 +
    'end;'#10, []));
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains('Öffentliche Konstante Version wird im Projekt nirgends verwendet.'));
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains('Öffentliche Routine Aufraeumen wird im Projekt nirgends verwendet.'));
  mData.Config := '{"rules": {"unused-public-member": {"unitLevel": false}}}';
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('Aufraeumen'));
  // Start wird in der .dpr aufgerufen.
  Assert.AreEqual('', Messages(Run(Scenario(''), cMainFile)));
end;

procedure TUnusedPublicMemberTests.VisibilitiesAndMemberKinds;
var
  mData: TScenario;
  mFound: string;
begin
  mData := Scenario('');
  mData.Put(cServiceFile, StringReplace(cServiceText, '  published'#10,
    '    Notiz: string;'#10'  protected'#10'    procedure Pruefen;'#10'  published'#10, []));
  mFound := Messages(Run(mData, cServiceFile));
  Assert.IsFalse(mFound.Contains('Notiz'), 'Felder sind aus');
  Assert.IsFalse(mFound.Contains('Pruefen'), 'protected ist aus');
  mData.Config := '{"rules": {"unused-public-member": {"visibilities": ["protected"], "memberKinds": ["method", "field"]}}}';
  mFound := Messages(Run(mData, cServiceFile));
  Assert.AreEqual('Geschützte Methode TKundenService.Pruefen wird im Projekt nirgends verwendet.'#10, mFound);
  mData.Config := '{"rules": {"unused-public-member": {"memberKinds": ["field"]}}}';
  Assert.AreEqual('Öffentliches Feld TKundenService.Notiz wird im Projekt nirgends verwendet.'#10,
    Messages(Run(mData, cServiceFile)));
end;

procedure TUnusedPublicMemberTests.ProtectedBodyIsNoCandidate;
var
  mData: TScenario;
begin
  // Die protected-Deklaration entscheidet; der Rumpf steht im Index als public und wurde früher gemeldet.
  mData := Scenario('');
  mData.Put(cMainFile, 'unit Kunden.Main;'#10'interface'#10'procedure Start;'#10'implementation'#10'type'#10 +
    '  TGeraet = class'#10'  protected'#10'    procedure Stoppen; virtual;'#10'  end;'#10 +
    'procedure TGeraet.Stoppen;'#10'begin'#10'end;'#10'procedure Start;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual('', Messages(Run(mData, cMainFile)));
end;

procedure TUnusedPublicMemberTests.ScopeProjectOrGroup;
var
  mData: TScenario;
begin
  // Kunden.Service gehört zu App und zu Werkzeug; nur Werkzeug ruft ExportiereAlsXml auf.
  mData := Scenario('');
  mData.Put('C:\P\Werkzeug.dpr', 'program Werkzeug;'#10'uses'#10'  Kunden.Service;'#10'var'#10'  S: TKundenService;'#10 +
    'begin'#10'  S.ExportiereAlsXml(''z'');'#10'end.');
  mData.Projects := mData.Projects + [Project('C:\P\Werkzeug.dproj', TRuleProjectKind.Application, False,
    ['C:\P\Werkzeug.dpr', cServiceFile], nil)];
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
  // Eine Anwendung der Gruppe, die die Unit nicht enthält, zählt nur mit projectGroup.
  mData.Projects[1].Sources := ['C:\P\Werkzeug.dpr'];
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
  mData.Config := '{"rules": {"unused-public-member": {"scope": "project"}}}';
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.TestsCountAsUseOption;
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Put('C:\P\Tests\AppTests.dpr', 'program AppTests;'#10'uses'#10'  DUnitX.TestFramework, Kunden.Service;'#10 +
    'var'#10'  S: TKundenService;'#10'begin'#10'  S.ExportiereAlsXml(''t'');'#10'end.');
  mData.Projects := mData.Projects + [Project('C:\P\Tests\AppTests.dproj', TRuleProjectKind.Application, True,
    ['C:\P\Tests\AppTests.dpr', cServiceFile], nil)];
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
  mData.Config := '{"rules": {"unused-public-member": {"testsCountAsUse": false}}}';
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains(
    'Öffentliche Methode TKundenService.ExportiereAlsXml wird nur in AppTests verwendet.'));
end;

procedure TUnusedPublicMemberTests.StringLiteralsOption;
var
  mData: TScenario;
begin
  mData := Scenario('  S.MethodAddress(''ExportiereAlsXml'');'#10);
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
  mData.Config := '{"rules": {"unused-public-member": {"stringLiteralsCountAsUse": false}}}';
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.KeepAttributesAndPatterns;
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Config := '{"rules": {"unused-public-member": {"keepPatterns": ["Exportiere*", "TKundenService.Max*"]}}}';
  Assert.AreEqual('Öffentliche Property TKundenService.LetzterFehler wird im Projekt nirgends verwendet.'#10,
    Messages(Run(mData, cServiceFile)));
  mData := Scenario('');
  mData.Put(cServiceFile, StringReplace(cServiceText, '  TKundenService = class'#10, '  [Dienst]'#10 +
    '  TKundenService = class'#10, []));
  mData.Config := '{"rules": {"unused-public-member": {"keepAttributes": ["Dienst"]}}}';
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
end;

procedure TUnusedPublicMemberTests.OffAndExclude;
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Config := '{"rules": {"unused-public-member": "off"}}';
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
  mData.Config := '{"rules": {"unused-public-member": {"exclude": ["Kunden.Service.pas"]}}}';
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
  mData.Put(cServiceFile, StringReplace(cServiceText, '    procedure ExportiereAlsXml',
    '    // lsp-ignore: unused-public-member'#10'    procedure ExportiereAlsXml', []));
  mData.Config := '';
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.PublishedWithUnreadableFormOrRegistration;
const
  cPublished_ = '  published'#10'    procedure KundeGeaendert(Sender: TObject);'#10;
  cExtra = '  published'#10'    procedure KundeGeaendert(Sender: TObject);'#10'    procedure Aktualisiere;'#10 +
    '    property Titel: string read FFehler;'#10;
  cBody = 'procedure TKundenService.KundeGeaendert(Sender: TObject);'#10'begin'#10'end;'#10;
var
  mData: TScenario;
  mFound: string;
begin
  mData := Scenario('');
  mData.Put(cServiceFile, StringReplace(StringReplace(cServiceText, cPublished_, cExtra, []), cBody,
    cBody + 'procedure TKundenService.Aktualisiere;'#10'begin'#10'end;'#10, []));
  mData.Config := '{"rules": {"unused-public-member": {"stringLiteralsCountAsUse": false}}}';
  mFound := Messages(Run(mData, cServiceFile));
  Assert.IsTrue(mFound.Contains('TKundenService.Aktualisiere'), mFound);
  Assert.IsTrue(mFound.Contains('TKundenService.Titel'), mFound);
  // Formulardatei nicht lesbar: published-Methoden können dort Handler sein, die Property nicht.
  mData.Unreadable := cFormFile;
  mFound := Messages(Run(mData, cServiceFile));
  Assert.IsFalse(mFound.Contains('TKundenService.Aktualisiere'), mFound);
  Assert.IsTrue(mFound.Contains('TKundenService.Titel'), mFound);
  mData.Unreadable := '';
  // RegisterClass in einer anderen Unit: alle published-Mitglieder erreicht das Streaming.
  mData.Put(cMainFile, StringReplace(MainText(''), 'end.', 'initialization'#10'  RegisterClasses([TKunde, ' +
    'TKundenService]);'#10'end.', []));
  mFound := Messages(Run(mData, cServiceFile));
  Assert.IsFalse(mFound.Contains('TKundenService.Aktualisiere'), mFound);
  Assert.IsFalse(mFound.Contains('TKundenService.Titel'), mFound);
  Assert.IsTrue(mFound.Contains('TKundenService.ExportiereAlsXml'), 'public bleibt gemeldet: ' + mFound);
  // Ein anderer Name in der Registrierung zählt nicht.
  mData.Put(cMainFile, StringReplace(MainText(''), 'end.', 'initialization'#10'  RegisterClass(TKunde);'#10 +
    'end.', []));
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains('TKundenService.Aktualisiere'));
end;

/// <summary>Ordner Tests\Referenzprojekt oberhalb der Testanwendung; '' ohne.</summary>
function ReferenceFolder: string;
var
  mDirectory: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    Result := TPath.Combine(mDirectory, TPath.Combine('Tests', 'Referenzprojekt'));
    if TDirectory.Exists(Result) then
    begin
      Exit;
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  Result := '';
end;

function ReadSource(const AFileName: string): string;
var
  mFormat: TFileFormat;
begin
  Result := TFileEncoding.Decode(TFile.ReadAllBytes(AFileName), mFormat);
end;

/// <summary>RefApp.dpr, die Units aus ihren in-Klauseln und deren Formulare, alle in AData abgelegt; AForms sind
/// die Formulardateien.</summary>
function RefAppSources(const AFolder: string; var AData: TScenario; out AForms: TArray<string>): TArray<string>;
var
  mMainFile, mSource: string;
  mTree: TSyntaxTree;
  mToken: TPascalToken;
begin
  mMainFile := TPath.Combine(AFolder, 'RefApp.dpr');
  AData.Put(mMainFile, ReadSource(mMainFile));
  Result := [mMainFile];
  AForms := nil;
  mTree := TSyntaxTreeCache.Parse(AData.Text(mMainFile));
  try
    for mToken in mTree.Tokens do
    begin
      if (mToken.Kind = TPascalTokenKind.StringLiteral) and EndsText('.pas''', mToken.Text) then
      begin
        mSource := TPath.Combine(AFolder, StringReplace(Copy(mToken.Text, 2, Length(mToken.Text) - 2), '\',
          PathDelim, [rfReplaceAll]));
        Result := Result + [mSource];
        AData.Put(mSource, ReadSource(mSource));
        if TFile.Exists(ChangeFileExt(mSource, '.dfm')) then
        begin
          AForms := AForms + [ChangeFileExt(mSource, '.dfm')];
          AData.Put(ChangeFileExt(mSource, '.dfm'), ReadSource(ChangeFileExt(mSource, '.dfm')));
        end;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Zeilen von ASource mit AMarker als „Datei:Zeile“.</summary>
function MarkedLines(const ASource, AText, AMarker: string): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mLines := AText.Replace(#13#10, #10).Split([#10]);
  for mIndex := 0 to High(mLines) do
  begin
    if mLines[mIndex].Contains(AMarker) then
    begin
      Result := Result + Format('%s:%d'#10, [ExtractFileName(ASource), mIndex + 1]);
    end;
  end;
end;

/// <summary>Treffer in ASource als „Datei:Zeile“.</summary>
function FoundLines(const AData: TScenario; const ASource: string): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in Run(AData, ASource) do
  begin
    Result := Result + Format('%s:%d'#10, [ExtractFileName(ASource), mFinding.Range.StartPos.Line + 1]);
  end;
end;

procedure TUnusedPublicMemberTests.ReferenceProjectMatchesMarkers;
const
  cMarker = '// ERWARTET-PROJEKT: unused-public-member';
var
  mFolder, mSource, mExpected, mActual: string;
  mData: TScenario;
  mSources, mForms: TArray<string>;
begin
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  end;
  // Units von RefApp aus den in-Klauseln der .dpr, Formulare daneben.
  mData := Default(TScenario);
  mSources := RefAppSources(mFolder, mData, mForms);
  mData.Projects := [Project(TPath.Combine(mFolder, 'RefApp.dproj'), TRuleProjectKind.Application, False, mSources,
    mForms)];
  // TPluginAufruf trägt [Schnittstelle]: Mit deadCode.keepAttributes gilt Melden als verwendet (#64).
  mData.Config := '{"deadCode": {"keepAttributes": ["Schnittstelle"]}}';
  // Erwartet: genau die markierten Zeilen, sonst nichts (jede weitere Meldung ist ein Fehlalarm).
  mExpected := '';
  mActual := '';
  for mSource in mSources do
  begin
    mExpected := mExpected + MarkedLines(mSource, mData.Text(mSource), cMarker);
    if SameText(ExtractFileExt(mSource), '.pas') then
    begin
      mActual := mActual + FoundLines(mData, mSource);
    end;
  end;
  Assert.AreEqual(mExpected, mActual);
  Assert.AreNotEqual('', mExpected, 'Keine Markierungen im Referenzprojekt');
end;

procedure TUnusedPublicMemberTests.UnitTypesAndVariables;
const
  cTypesFile = 'C:\P\Kunden.Typen.pas';
var
  mData: TScenario;
begin
  mData := Scenario('');
  mData.Put(cTypesFile,
    'unit Kunden.Typen;'#10'interface'#10'type'#10 +
    '  TUngenutzt = class'#10'  public'#10'    function Kopie: TUngenutzt;'#10'  end;'#10 +
    '  TFarbe = (Rot, Gruen);'#10 +
    '  BehaltenAttribute = class(TCustomAttribute)'#10'  end;'#10 +
    '  [Behalten]'#10'  TMarkiert = class'#10'  end;'#10 +
    '  TRegistriert = class'#10'  end;'#10 +
    '  TGenutzt = record'#10'  end;'#10 +
    'var'#10'  Zaehler: Integer;'#10'  Genutzt: Integer;'#10 +
    'implementation'#10 +
    'function TUngenutzt.Kopie: TUngenutzt;'#10'begin'#10'  Result := TUngenutzt.Create;'#10'end;'#10 +
    'initialization'#10'  RegisterClass(TRegistriert);'#10'end.');
  mData.Put(cMainFile, 'unit Kunden.Main;'#10'interface'#10'uses'#10'  Kunden.Service, Kunden.Typen;'#10 +
    'procedure Start;'#10'implementation'#10'procedure Start;'#10'var'#10'  G: TGenutzt;'#10'begin'#10 +
    '  Genutzt := 1;'#10'end;'#10'end.');
  mData.Projects[0].Sources := mData.Projects[0].Sources + [cTypesFile];
  // Eigene Deklaration und eigene Methoden zählen nicht; Attribut, Kurzform [Behalten] und RegisterClass schon.
  Assert.AreEqual(
    'Öffentlicher Typ TUngenutzt wird im Projekt nirgends verwendet.'#10 +
    'Öffentliche Methode TUngenutzt.Kopie wird im Projekt nirgends verwendet.'#10 +
    'Öffentlicher Typ TFarbe wird im Projekt nirgends verwendet.'#10 +
    'Globale Variable Zaehler wird im Projekt nirgends verwendet.'#10, Messages(Run(mData, cTypesFile)));
  // unitKinds: nur Routinen und Konstanten wie vor #64.
  mData.Config := '{"rules": {"unused-public-member": {"unitKinds": ["routine", "constant"]}}}';
  Assert.AreEqual('Öffentliche Methode TUngenutzt.Kopie wird im Projekt nirgends verwendet.'#10,
    Messages(Run(mData, cTypesFile)));
  // memberKinds wirkt nicht mehr auf die Unit-Ebene.
  mData.Config := '{"rules": {"unused-public-member": {"memberKinds": ["property"]}}}';
  Assert.AreEqual(
    'Öffentlicher Typ TUngenutzt wird im Projekt nirgends verwendet.'#10 +
    'Öffentlicher Typ TFarbe wird im Projekt nirgends verwendet.'#10 +
    'Globale Variable Zaehler wird im Projekt nirgends verwendet.'#10, Messages(Run(mData, cTypesFile)));
end;

procedure TUnusedPublicMemberTests.DeadCodeKeepSettings;
var
  mData: TScenario;
begin
  mData := Scenario('');
  // deadCode.keepPatterns aus den Einstellungen und keepPatterns der Regel gelten zusammen.
  mData.Config := '{"deadCode": {"keepPatterns": ["*Xml"]}, "rules": {"unused-public-member": ' +
    '{"keepPatterns": ["MaxKunden"]}}}';
  Assert.AreEqual('Öffentliche Property TKundenService.LetzterFehler wird im Projekt nirgends verwendet.'#10,
    Messages(Run(mData, cServiceFile)));
  // deadCode.keepAttributes: alle Mitglieder eines Typs mit dem Attribut.
  mData.Put(cServiceFile, StringReplace(cServiceText, '  TKundenService = class', '  [Api]'#10'  TKundenService = class',
    []));
  mData.Config := '{"deadCode": {"keepAttributes": ["Api"]}}';
  Assert.AreEqual('', Messages(Run(mData, cServiceFile)));
end;

procedure TUnusedPublicMemberTests.ParserChecksOptions;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  TConfigurationParser.Parse('{"rules": {"unused-public-member": {"visibilities": ["protected"], ' +
    '"memberKinds": ["field"], "projectKinds": ["package"], "unitLevel": false, "scope": "project", ' +
    '"testsCountAsUse": false, "stringLiteralsCountAsUse": false, "keepAttributes": ["Keep"], ' +
    '"keepPatterns": ["TPlugin.*"]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  TConfigurationParser.Parse('{"rules": {"unused-public-member": {"visibilities": "public", ' +
    '"memberKinds": [1], "projectKinds": true, "unitLevel": "ja", "scope": 1, "testsCountAsUse": 0, ' +
    '"stringLiteralsCountAsUse": [], "keepAttributes": "Keep", "keepPatterns": {}}}}', mIssues);
  Assert.AreEqual(9, Integer(Length(mIssues)));
  mIssues := nil;
end;

procedure TUnusedPublicMemberTests.RecheckAfterChangeInOtherUnit;
var
  mData: TScenario;
begin
  mData := Scenario('  S.ExportiereAlsXml(''x'');'#10);
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
  mData.Put(cMainFile, MainText(''));
  Assert.IsTrue(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
  mData.Put(cMainFile, MainText('  S.ExportiereAlsXml(''x'');'#10));
  Assert.IsFalse(Messages(Run(mData, cServiceFile)).Contains('ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.IgnoreFixInsertsComment;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Run(Scenario(''), cServiceFile);
  Assert.AreEqual(1, Integer(Length(mFound[1].Fixes)));
  Assert.AreEqual('Als bewusst öffentlich markieren (lsp-ignore)', mFound[1].Fixes[0].Title);
  Assert.AreEqual(12, mFound[1].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual('    // lsp-ignore: unused-public-member'#10, mFound[1].Fixes[0].Edits[0].NewText);
end;

procedure TUnusedPublicMemberTests.CheckOfLargeProject;
const
  cUnitCount = 150;
var
  mData: TScenario;
  mSources: TArray<string>;
  mIndex: Integer;
  mName: string;
  mWatch: TStopwatch;
begin
  mData := Scenario('  S.ExportiereAlsXml(''x'');'#10);
  mSources := [cAppFile, cServiceFile, cMainFile];
  for mIndex := 1 to cUnitCount do
  begin
    mName := Format('C:\P\Einheit%d.pas', [mIndex]);
    mData.Put(mName, Format('unit Einheit%0:d;'#10'interface'#10'uses'#10'  Kunden.Service;'#10'type'#10 +
      '  TEinheit%0:d = class'#10'  public'#10'    procedure Lauf;'#10'    function Wert: Integer;'#10'  end;'#10 +
      'implementation'#10'procedure TEinheit%0:d.Lauf;'#10'var'#10'  S: TKundenService;'#10'begin'#10 +
      '  S.Lade(%0:d);'#10'end;'#10'function TEinheit%0:d.Wert: Integer;'#10'begin'#10'  Result := %0:d;'#10'end;'#10 +
      'end.', [mIndex]));
    mSources := mSources + [mName];
  end;
  mData.Projects[0].Sources := mSources;
  mWatch := TStopwatch.StartNew;
  Run(mData, cServiceFile);
  mWatch.Stop;
  System.Writeln(Format('unused-public-member: Prüfung bei %d Units in %d ms', [cUnitCount + 3,
    mWatch.ElapsedMilliseconds]));
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 5000, 'zu langsam');
end;

initialization
  TDUnitX.RegisterTestFixture(TUnusedPublicMemberTests);

end.
