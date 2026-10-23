unit Atlas.Common.Rules.Builtin.PublicMembers.Tests;

// Tests der Regel unused-public-member (#1102): Beispiel aus dem Issue,
// Verwendungen aus anderen Units (Aufruf, Methodenzeiger, inherited, Formular,
// String-Literal), gleichnamige Mitglieder anderer Klassen, Schweigen bei
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
  Atlas.Common.Documents.Contract,
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
  Root = 'C:\P\';
  ServiceFile = 'C:\P\Kunden.Service.pas';
  MainFile = 'C:\P\Kunden.Main.pas';
  AppFile = 'C:\P\App.dpr';
  FormFile = 'C:\P\Kunden.Main.dfm';

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
  Index: Integer;
  Entry: TTestFile;
begin
  for Index := 0 to High(Files) do
    if SameText(Files[Index].Name, AName) then
    begin
      Files[Index].Text := AText;
      Exit;
    end;
  Entry.Name := AName;
  Entry.Text := AText;
  Files := Files + [Entry];
end;

function TScenario.Text(const AName: string): string;
var
  Entry: TTestFile;
begin
  Result := '';
  for Entry in Files do
    if SameText(Entry.Name, AName) then
      Result := Entry.Text;
end;

const
  SystemText = 'unit System;'#10'interface'#10'type'#10'  TObject = class'#10'  public'#10 +
    '    procedure Free;'#10'    function MethodAddress(const AName: string): Pointer;'#10'  end;'#10 +
    '  IInterface = interface'#10'    function _AddRef: Integer;'#10'  end;'#10 +
    '  TInterfacedObject = class(TObject, IInterface)'#10'  public'#10'    function _AddRef: Integer;'#10'  end;'#10 +
    '  TCustomAttribute = class(TObject)'#10'  end;'#10 +
    'implementation'#10'procedure TObject.Free;'#10'begin'#10'end;'#10 +
    'function TObject.MethodAddress(const AName: string): Pointer;'#10'begin'#10'  Result := nil;'#10'end;'#10 +
    'function TInterfacedObject._AddRef: Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10'end.';

  ServiceText =
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
  Result.Put(AppFile, 'program App;'#10'uses'#10'  Kunden.Service, Kunden.Main;'#10'begin'#10'  Start;'#10'end.');
  Result.Put(ServiceFile, ServiceText);
  Result.Put(MainFile, MainText(ABody));
  Result.Put(FormFile, 'object Hauptfenster: THauptfenster'#10'  OnClick = KundeGeaendert'#10'end');
  Result.Projects := [Project('C:\P\App.dproj', TRuleProjectKind.Application, False,
    [AppFile, ServiceFile, MainFile], [FormFile])];
end;

function Run(const AScenario: TScenario; const ACheck: string): TArray<TRuleFinding>;
var
  Texts: TDictionary<string, string>;
  Index: ISymbolIndex;
  Entry: TTestFile;
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Unreadable: string;
  Incomplete: Boolean;
begin
  Unreadable := AScenario.Unreadable;
  Incomplete := AScenario.Incomplete;
  Texts := TDictionary<string, string>.Create;
  try
    Index := TSymbolIndex.Create;
    Index.AddUnit(TIndexExtractor.ExtractText(SystemText, 'C:\BDS\source\System.pas', nil));
    for Entry in AScenario.Files do
    begin
      Texts.AddOrSetValue(UpperCase(Entry.Name), Entry.Text);
      if not SameText(ExtractFileExt(Entry.Name), '.dfm') then
        Index.AddUnit(TIndexExtractor.ExtractText(Entry.Text, Entry.Name, nil, nil, True));
    end;
    if AScenario.Config = '' then
      Settings := TServerSettings.Default
    else
      Settings := TConfigurationParser.Parse(AScenario.Config, Issues);
    Tree := TSyntaxTreeCache.Parse(AScenario.Text(ACheck));
    try
      Context := Default(TRuleContext);
      Context.FileName := ACheck;
      Context.RelativePath := StringReplace(Copy(ACheck, Length(Root) + 1, MaxInt), '\', '/', [rfReplaceAll]);
      Context.UnitName := ChangeFileExt(ExtractFileName(ACheck), '');
      Context.Text := AScenario.Text(ACheck);
      Context.Tree := Tree;
      Context.Index := Index;
      Context.ProjectFiles := TRuleProjectFiles.Create(AScenario.Projects, Index,
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := not SameText(AFileName, Unreadable) and Texts.TryGetValue(UpperCase(AFileName), AText);
        end,
        function(out AReason: string): Boolean
        begin
          Result := not Incomplete;
          if Incomplete then
            AReason := 'Index läuft (1 von 3 Units)';
        end);
      Result := TRuleEngine.Run([TUnusedPublicMemberRule.Create], Settings, Context);
      Context.ProjectFiles := nil;
    finally
      Tree.Free;
    end;
  finally
    Texts.Free;
  end;
end;

function Messages(const AFindings: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFindings do
    Result := Result + Finding.Message + #10;
end;

procedure TUnusedPublicMemberTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Run(Scenario(''), ServiceFile);
  Assert.AreEqual(
    'Öffentliche Konstante TKundenService.MaxKunden wird im Projekt nirgends verwendet.'#10 +
    'Öffentliche Methode TKundenService.ExportiereAlsXml wird im Projekt nirgends verwendet.'#10 +
    'Öffentliche Property TKundenService.LetzterFehler wird im Projekt nirgends verwendet.'#10, Messages(Found));
  Assert.AreEqual(12, Found[1].Range.StartPos.Line);
  Assert.AreEqual(14, Found[1].Range.StartPos.Character);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, Found[1].Severity);
  Assert.AreEqual<TRuleConfidence>(TRuleConfidence.Medium, Found[1].Confidence);
  // Durchsuchter Bereich für den Befund-Hover: App.dpr, zwei Units und die Formulardatei.
  Assert.AreEqual('Durchsucht: 3 Dateien und 1 Formular der Projektgruppe', Found[1].Details);
end;

procedure TUnusedPublicMemberTests.UsesInOtherUnitsAreFound;
var
  Data: TScenario;
begin
  // Korrigierte Form: alle drei verwendet.
  Data := Scenario('  S.ExportiereAlsXml(''x'');'#10'  if S.LetzterFehler = '''' then'#10 +
    '    Writeln(TKundenService.MaxKunden);'#10);
  Assert.AreEqual('', Messages(Run(Data, ServiceFile)));
  // Methodenzeiger.
  Data := Scenario('  P := S.ExportiereAlsXml;'#10);
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
  // inherited in einem Nachfahren einer anderen Unit.
  Data := Scenario('');
  Data.Put(MainFile, 'unit Kunden.Main;'#10'interface'#10'uses'#10'  Kunden.Service;'#10'type'#10 +
    '  TSonder = class(TKundenService)'#10'  public'#10'    procedure ExportiereAlsXml(const Datei: string);'#10 +
    '  end;'#10'procedure Start;'#10'implementation'#10'procedure TSonder.ExportiereAlsXml(const Datei: string);'#10 +
    'begin'#10'  inherited ExportiereAlsXml(Datei);'#10'end;'#10'procedure Start;'#10'begin'#10 +
    '  TSonder.Create.ExportiereAlsXml(''y'');'#10'end;'#10'end.');
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('TKundenService.ExportiereAlsXml'));
  // Published-Methode ohne Formular: gemeldet.
  Data := Scenario('');
  Data.Put(FormFile, 'object Hauptfenster: THauptfenster'#10'end');
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains(
    'Published-Methode TKundenService.KundeGeaendert wird im Projekt nirgends verwendet.'));
end;

procedure TUnusedPublicMemberTests.SameNameOfOtherClassDoesNotCount;
var
  Data: TScenario;
begin
  Data := Scenario('');
  Data.Put(MainFile, 'unit Kunden.Main;'#10'interface'#10'type'#10'  TAndere = class'#10'  public'#10 +
    '    procedure ExportiereAlsXml(const Datei: string);'#10'  end;'#10'procedure Start;'#10'implementation'#10 +
    'procedure TAndere.ExportiereAlsXml(const Datei: string);'#10'begin'#10'end;'#10'procedure Start;'#10 +
    'var'#10'  A: TAndere;'#10'begin'#10'  A := TAndere.Create;'#10'  A.ExportiereAlsXml(''x'');'#10'end;'#10'end.');
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains('TKundenService.ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.RecursionIsNoUse;
var
  Data: TScenario;
begin
  Data := Scenario('');
  Data.Put(ServiceFile, StringReplace(ServiceText, 'procedure TKundenService.ExportiereAlsXml(const Datei: string);'#10 +
    'begin'#10, 'procedure TKundenService.ExportiereAlsXml(const Datei: string);'#10'begin'#10 +
    '  ExportiereAlsXml(Datei);'#10, []));
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains('TKundenService.ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.SilentWhileIndexIncomplete;
var
  Data: TScenario;
begin
  Data := Scenario('');
  Data.Incomplete := True;
  Assert.AreEqual('', Messages(Run(Data, ServiceFile)));
end;

procedure TUnusedPublicMemberTests.SilentWhenFileUnreadable;
var
  Data: TScenario;
  Found: string;
begin
  // Kommt der Name in einer nicht lesbaren Datei vor, ist keine Aussage möglich.
  Data := Scenario('  S.ExportiereAlsXml(''x'');'#10);
  Data.Unreadable := MainFile;
  Found := Messages(Run(Data, ServiceFile));
  Assert.IsFalse(Found.Contains('ExportiereAlsXml'), Found);
end;

procedure TUnusedPublicMemberTests.PackagesOnlyWithOption;
var
  Data: TScenario;
begin
  Data := Scenario('');
  Data.Projects[0].Kind := TRuleProjectKind.Package;
  Assert.AreEqual('', Messages(Run(Data, ServiceFile)));
  Data.Config := '{"rules": {"unused-public-member": {"projectKinds": ["application", "package"]}}}';
  Assert.AreEqual(3, Integer(Length(Run(Data, ServiceFile))));
  // Eine Unit in Anwendung und DLL: die DLL hat fremde Nutzer.
  Data := Scenario('');
  Data.Projects := Data.Projects + [Project('C:\P\Export.dproj', TRuleProjectKind.Library_, False,
    ['C:\P\Export.dpr', ServiceFile], nil)];
  Assert.AreEqual('', Messages(Run(Data, ServiceFile)));
end;

procedure TUnusedPublicMemberTests.SilentWithIncludeOrUnknownAncestor;
var
  Data: TScenario;
begin
  Data := Scenario('');
  Data.Put(ServiceFile, StringReplace(ServiceText, 'implementation'#10, 'implementation'#10'{$I Extra.inc}'#10, []));
  Assert.AreEqual('', Messages(Run(Data, ServiceFile)));
  Data := Scenario('');
  Data.Put(ServiceFile, StringReplace(ServiceText, 'TKundenService = class'#10, 'TKundenService = class(TUnbekannt)'#10,
    []));
  Assert.AreEqual('', Messages(Run(Data, ServiceFile)));
end;

procedure TUnusedPublicMemberTests.UnitLevelRoutinesAndConstants;
var
  Data: TScenario;
begin
  Data := Scenario('');
  Data.Put(ServiceFile, StringReplace(ServiceText, 'implementation'#10,
    'const'#10'  Version = 3;'#10'procedure Aufraeumen;'#10'implementation'#10'procedure Aufraeumen;'#10'begin'#10 +
    'end;'#10, []));
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains('Öffentliche Konstante Version wird im Projekt nirgends verwendet.'));
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains('Öffentliche Routine Aufraeumen wird im Projekt nirgends verwendet.'));
  Data.Config := '{"rules": {"unused-public-member": {"unitLevel": false}}}';
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('Aufraeumen'));
  // Start wird in der .dpr aufgerufen.
  Assert.AreEqual('', Messages(Run(Scenario(''), MainFile)));
end;

procedure TUnusedPublicMemberTests.VisibilitiesAndMemberKinds;
var
  Data: TScenario;
  Found: string;
begin
  Data := Scenario('');
  Data.Put(ServiceFile, StringReplace(ServiceText, '  published'#10,
    '    Notiz: string;'#10'  protected'#10'    procedure Pruefen;'#10'  published'#10, []));
  Found := Messages(Run(Data, ServiceFile));
  Assert.IsFalse(Found.Contains('Notiz'), 'Felder sind aus');
  Assert.IsFalse(Found.Contains('Pruefen'), 'protected ist aus');
  Data.Config := '{"rules": {"unused-public-member": {"visibilities": ["protected"], "memberKinds": ["method", "field"]}}}';
  Found := Messages(Run(Data, ServiceFile));
  Assert.AreEqual('Geschützte Methode TKundenService.Pruefen wird im Projekt nirgends verwendet.'#10, Found);
  Data.Config := '{"rules": {"unused-public-member": {"memberKinds": ["field"]}}}';
  Assert.AreEqual('Öffentliches Feld TKundenService.Notiz wird im Projekt nirgends verwendet.'#10,
    Messages(Run(Data, ServiceFile)));
end;

procedure TUnusedPublicMemberTests.ProtectedBodyIsNoCandidate;
var
  Data: TScenario;
begin
  // Die protected-Deklaration entscheidet; der Rumpf steht im Index als public und wurde früher gemeldet.
  Data := Scenario('');
  Data.Put(MainFile, 'unit Kunden.Main;'#10'interface'#10'procedure Start;'#10'implementation'#10'type'#10 +
    '  TGeraet = class'#10'  protected'#10'    procedure Stoppen; virtual;'#10'  end;'#10 +
    'procedure TGeraet.Stoppen;'#10'begin'#10'end;'#10'procedure Start;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual('', Messages(Run(Data, MainFile)));
end;

procedure TUnusedPublicMemberTests.ScopeProjectOrGroup;
var
  Data: TScenario;
begin
  // Kunden.Service gehört zu App und zu Werkzeug; nur Werkzeug ruft ExportiereAlsXml auf.
  Data := Scenario('');
  Data.Put('C:\P\Werkzeug.dpr', 'program Werkzeug;'#10'uses'#10'  Kunden.Service;'#10'var'#10'  S: TKundenService;'#10 +
    'begin'#10'  S.ExportiereAlsXml(''z'');'#10'end.');
  Data.Projects := Data.Projects + [Project('C:\P\Werkzeug.dproj', TRuleProjectKind.Application, False,
    ['C:\P\Werkzeug.dpr', ServiceFile], nil)];
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
  // Eine Anwendung der Gruppe, die die Unit nicht enthält, zählt nur mit projectGroup.
  Data.Projects[1].Sources := ['C:\P\Werkzeug.dpr'];
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
  Data.Config := '{"rules": {"unused-public-member": {"scope": "project"}}}';
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.TestsCountAsUseOption;
var
  Data: TScenario;
begin
  Data := Scenario('');
  Data.Put('C:\P\Tests\AppTests.dpr', 'program AppTests;'#10'uses'#10'  DUnitX.TestFramework, Kunden.Service;'#10 +
    'var'#10'  S: TKundenService;'#10'begin'#10'  S.ExportiereAlsXml(''t'');'#10'end.');
  Data.Projects := Data.Projects + [Project('C:\P\Tests\AppTests.dproj', TRuleProjectKind.Application, True,
    ['C:\P\Tests\AppTests.dpr', ServiceFile], nil)];
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
  Data.Config := '{"rules": {"unused-public-member": {"testsCountAsUse": false}}}';
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains(
    'Öffentliche Methode TKundenService.ExportiereAlsXml wird nur in AppTests verwendet.'));
end;

procedure TUnusedPublicMemberTests.StringLiteralsOption;
var
  Data: TScenario;
begin
  Data := Scenario('  S.MethodAddress(''ExportiereAlsXml'');'#10);
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
  Data.Config := '{"rules": {"unused-public-member": {"stringLiteralsCountAsUse": false}}}';
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.KeepAttributesAndPatterns;
var
  Data: TScenario;
begin
  Data := Scenario('');
  Data.Config := '{"rules": {"unused-public-member": {"keepPatterns": ["Exportiere*", "TKundenService.Max*"]}}}';
  Assert.AreEqual('Öffentliche Property TKundenService.LetzterFehler wird im Projekt nirgends verwendet.'#10,
    Messages(Run(Data, ServiceFile)));
  Data := Scenario('');
  Data.Put(ServiceFile, StringReplace(ServiceText, '  TKundenService = class'#10, '  [Dienst]'#10 +
    '  TKundenService = class'#10, []));
  Data.Config := '{"rules": {"unused-public-member": {"keepAttributes": ["Dienst"]}}}';
  Assert.AreEqual('', Messages(Run(Data, ServiceFile)));
end;

procedure TUnusedPublicMemberTests.OffAndExclude;
var
  Data: TScenario;
begin
  Data := Scenario('');
  Data.Config := '{"rules": {"unused-public-member": "off"}}';
  Assert.AreEqual('', Messages(Run(Data, ServiceFile)));
  Data.Config := '{"rules": {"unused-public-member": {"exclude": ["Kunden.Service.pas"]}}}';
  Assert.AreEqual('', Messages(Run(Data, ServiceFile)));
  Data.Put(ServiceFile, StringReplace(ServiceText, '    procedure ExportiereAlsXml',
    '    // lsp-ignore: unused-public-member'#10'    procedure ExportiereAlsXml', []));
  Data.Config := '';
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.PublishedWithUnreadableFormOrRegistration;
const
  Published_ = '  published'#10'    procedure KundeGeaendert(Sender: TObject);'#10;
  Extra = '  published'#10'    procedure KundeGeaendert(Sender: TObject);'#10'    procedure Aktualisiere;'#10 +
    '    property Titel: string read FFehler;'#10;
  Body = 'procedure TKundenService.KundeGeaendert(Sender: TObject);'#10'begin'#10'end;'#10;
var
  Data: TScenario;
  Found: string;
begin
  Data := Scenario('');
  Data.Put(ServiceFile, StringReplace(StringReplace(ServiceText, Published_, Extra, []), Body,
    Body + 'procedure TKundenService.Aktualisiere;'#10'begin'#10'end;'#10, []));
  Data.Config := '{"rules": {"unused-public-member": {"stringLiteralsCountAsUse": false}}}';
  Found := Messages(Run(Data, ServiceFile));
  Assert.IsTrue(Found.Contains('TKundenService.Aktualisiere'), Found);
  Assert.IsTrue(Found.Contains('TKundenService.Titel'), Found);
  // Formulardatei nicht lesbar: published-Methoden können dort Handler sein, die Property nicht.
  Data.Unreadable := FormFile;
  Found := Messages(Run(Data, ServiceFile));
  Assert.IsFalse(Found.Contains('TKundenService.Aktualisiere'), Found);
  Assert.IsTrue(Found.Contains('TKundenService.Titel'), Found);
  Data.Unreadable := '';
  // RegisterClass in einer anderen Unit: alle published-Mitglieder erreicht das Streaming.
  Data.Put(MainFile, StringReplace(MainText(''), 'end.', 'initialization'#10'  RegisterClasses([TKunde, ' +
    'TKundenService]);'#10'end.', []));
  Found := Messages(Run(Data, ServiceFile));
  Assert.IsFalse(Found.Contains('TKundenService.Aktualisiere'), Found);
  Assert.IsFalse(Found.Contains('TKundenService.Titel'), Found);
  Assert.IsTrue(Found.Contains('TKundenService.ExportiereAlsXml'), 'public bleibt gemeldet: ' + Found);
  // Ein anderer Name in der Registrierung zählt nicht.
  Data.Put(MainFile, StringReplace(MainText(''), 'end.', 'initialization'#10'  RegisterClass(TKunde);'#10 +
    'end.', []));
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains('TKundenService.Aktualisiere'));
end;

/// <summary>Ordner Tests\Referenzprojekt oberhalb der Testanwendung; '' ohne.</summary>
function ReferenceFolder: string;
var
  Directory: string;
begin
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    Result := TPath.Combine(Directory, TPath.Combine('Tests', 'Referenzprojekt'));
    if TDirectory.Exists(Result) then
      Exit;
    if ExtractFileDir(Directory) = Directory then
      Break;
    Directory := ExtractFileDir(Directory);
  end;
  Result := '';
end;

function ReadSource(const AFileName: string): string;
var
  Format: TFileFormat;
begin
  Result := TFileEncoding.Decode(TFile.ReadAllBytes(AFileName), Format);
end;

procedure TUnusedPublicMemberTests.ReferenceProjectMatchesMarkers;
const
  Marker = '// ERWARTET-PROJEKT: unused-public-member';
var
  Folder, MainFile, Source, Expected, Actual: string;
  Data: TScenario;
  Sources, Forms: TArray<string>;
  Lines: TArray<string>;
  Token: TPascalToken;
  Tree: TSyntaxTree;
  Finding: TRuleFinding;
  Index: Integer;
begin
  Folder := ReferenceFolder;
  if Folder = '' then
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  // Units von RefApp aus den in-Klauseln der .dpr, Formulare daneben.
  MainFile := TPath.Combine(Folder, 'RefApp.dpr');
  Data := Default(TScenario);
  Data.Put(MainFile, ReadSource(MainFile));
  Sources := [MainFile];
  Forms := nil;
  Tree := TSyntaxTreeCache.Parse(Data.Text(MainFile));
  try
    for Token in Tree.Tokens do
      if (Token.Kind = TPascalTokenKind.StringLiteral) and EndsText('.pas''', Token.Text) then
      begin
        Source := TPath.Combine(Folder, StringReplace(Copy(Token.Text, 2, Length(Token.Text) - 2), '\',
          PathDelim, [rfReplaceAll]));
        Sources := Sources + [Source];
        Data.Put(Source, ReadSource(Source));
        if TFile.Exists(ChangeFileExt(Source, '.dfm')) then
        begin
          Forms := Forms + [ChangeFileExt(Source, '.dfm')];
          Data.Put(ChangeFileExt(Source, '.dfm'), ReadSource(ChangeFileExt(Source, '.dfm')));
        end;
      end;
  finally
    Tree.Free;
  end;
  Data.Projects := [Project(TPath.Combine(Folder, 'RefApp.dproj'), TRuleProjectKind.Application, False, Sources,
    Forms)];
  // Erwartet: genau die markierten Zeilen, sonst nichts (jede weitere Meldung ist ein Fehlalarm).
  Expected := '';
  Actual := '';
  for Source in Sources do
  begin
    Lines := Data.Text(Source).Replace(#13#10, #10).Split([#10]);
    for Index := 0 to High(Lines) do
      if Lines[Index].Contains(Marker) then
        Expected := Expected + Format('%s:%d'#10, [ExtractFileName(Source), Index + 1]);
    if SameText(ExtractFileExt(Source), '.pas') then
      for Finding in Run(Data, Source) do
        Actual := Actual + Format('%s:%d'#10, [ExtractFileName(Source), Finding.Range.StartPos.Line + 1]);
  end;
  Assert.AreEqual(Expected, Actual);
  Assert.IsTrue(Expected <> '', 'Keine Markierungen im Referenzprojekt');
end;

procedure TUnusedPublicMemberTests.ParserChecksOptions;
var
  Issues: TArray<TConfigurationIssue>;
begin
  TConfigurationParser.Parse('{"rules": {"unused-public-member": {"visibilities": ["protected"], ' +
    '"memberKinds": ["field"], "projectKinds": ["package"], "unitLevel": false, "scope": "project", ' +
    '"testsCountAsUse": false, "stringLiteralsCountAsUse": false, "keepAttributes": ["Keep"], ' +
    '"keepPatterns": ["TPlugin.*"]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"rules": {"unused-public-member": {"visibilities": "public", ' +
    '"memberKinds": [1], "projectKinds": true, "unitLevel": "ja", "scope": 1, "testsCountAsUse": 0, ' +
    '"stringLiteralsCountAsUse": [], "keepAttributes": "Keep", "keepPatterns": {}}}}', Issues);
  Assert.AreEqual(9, Integer(Length(Issues)));
  Issues := nil;
end;

procedure TUnusedPublicMemberTests.RecheckAfterChangeInOtherUnit;
var
  Data: TScenario;
begin
  Data := Scenario('  S.ExportiereAlsXml(''x'');'#10);
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
  Data.Put(MainFile, MainText(''));
  Assert.IsTrue(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
  Data.Put(MainFile, MainText('  S.ExportiereAlsXml(''x'');'#10));
  Assert.IsFalse(Messages(Run(Data, ServiceFile)).Contains('ExportiereAlsXml'));
end;

procedure TUnusedPublicMemberTests.IgnoreFixInsertsComment;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Run(Scenario(''), ServiceFile);
  Assert.AreEqual(1, Integer(Length(Found[1].Fixes)));
  Assert.AreEqual('Als bewusst öffentlich markieren (lsp-ignore)', Found[1].Fixes[0].Title);
  Assert.AreEqual(12, Found[1].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual('    // lsp-ignore: unused-public-member'#10, Found[1].Fixes[0].Edits[0].NewText);
end;

procedure TUnusedPublicMemberTests.CheckOfLargeProject;
const
  UnitCount = 150;
var
  Data: TScenario;
  Sources: TArray<string>;
  Index: Integer;
  Name: string;
  Watch: TStopwatch;
begin
  Data := Scenario('  S.ExportiereAlsXml(''x'');'#10);
  Sources := [AppFile, ServiceFile, MainFile];
  for Index := 1 to UnitCount do
  begin
    Name := Format('C:\P\Einheit%d.pas', [Index]);
    Data.Put(Name, Format('unit Einheit%0:d;'#10'interface'#10'uses'#10'  Kunden.Service;'#10'type'#10 +
      '  TEinheit%0:d = class'#10'  public'#10'    procedure Lauf;'#10'    function Wert: Integer;'#10'  end;'#10 +
      'implementation'#10'procedure TEinheit%0:d.Lauf;'#10'var'#10'  S: TKundenService;'#10'begin'#10 +
      '  S.Lade(%0:d);'#10'end;'#10'function TEinheit%0:d.Wert: Integer;'#10'begin'#10'  Result := %0:d;'#10'end;'#10 +
      'end.', [Index]));
    Sources := Sources + [Name];
  end;
  Data.Projects[0].Sources := Sources;
  Watch := TStopwatch.StartNew;
  Run(Data, ServiceFile);
  Watch.Stop;
  System.Writeln(Format('unused-public-member: Prüfung bei %d Units in %d ms', [UnitCount + 3,
    Watch.ElapsedMilliseconds]));
  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, 'zu langsam');
end;

initialization
  TDUnitX.RegisterTestFixture(TUnusedPublicMemberTests);

end.
