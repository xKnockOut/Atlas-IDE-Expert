unit Atlas.Common.Rules.Builtin.DeadCode.Tests;

// Tests der Regeln für toten Code und Zyklen (#64): uses-cycle mit
// vollständigem Pfad (nur interface als Fehler, gemischt, Option
// implementation, Schweigen ohne Projekte oder bei laufendem Index),
// unused-declaration (Rekursion, eigene Methoden eines Typs, exports,
// Attribute, deadCode.keep*, Formulardatei, Rümpfe des interface-Teils),
// unused-unit (nur das Programm nennt die Unit, Bezeichner im Programm,
// initialization, Packages), die Einstellung deadCode im Parser, die Marker
// ERWARTET-PROJEKT im Referenzprojekt und eine Zeitmessung.
// Meldung im Editor (#896): Live-Modus mit Pfad und Stellen jeder Kante,
// diagnostics.usesCycleLive und usesCycleImplementation, Selbstverweis,
// mehrere Zyklen, kürzester Pfad, Bedingung und Textänderung von „In
// implementation-uses verschieben“ (auch mit sortUses), Sprünge zu den
// Bezeichnern im interface mit „Graph zeigen“, Einstellungen im Parser und
// eine Zeitmessung mit 2000 Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeadCodeTests = class
  public
    [Test]
    procedure CycleOverImplementationWithFullPath;
    [Test]
    procedure InterfaceCycleIsError;
    [Test]
    procedure ImplementationOptionOff;
    [Test]
    procedure NoCycleNoFinding;
    [Test]
    procedure CycleSilentWithoutProjectsOrWhileIndexing;
    [Test]
    procedure UnusedDeclarations;
    [Test]
    procedure UsedDeclarationsAreSilent;
    [Test]
    procedure KeepSettingsAndFormText;
    [Test]
    procedure UnusedUnitOnlyNamedByProgram;
    [Test]
    procedure UnusedUnitExceptions;
    [Test]
    procedure LiveInterfaceCycleWithPathAndPlaces;
    [Test]
    procedure LiveImplementationCycleOnlyWhenEnabled;
    [Test]
    procedure LiveSwitchLeavesProjectCheck;
    [Test]
    procedure SelfReferenceIsError;
    [Test]
    procedure SeveralCyclesAndShortestPath;
    [Test]
    procedure MoveFixOnlyWithoutInterfaceUse;
    [Test]
    procedure MoveFixSortsLikeSortUses;
    [Test]
    procedure JumpsAndGraphWhenInterfaceNeedsUnit;
    [Test]
    procedure ParserReadsUsesCycleSettings;
    [Test]
    [Category('Benchmark')]
    procedure LiveCycleCheckOf2000Units;
    [Test]
    procedure ParserReadsDeadCode;
    [Test]
    procedure ReferenceProjectMatchesMarkers;
    [Test]
    [Category('Benchmark')]
    procedure CycleCheckOfLargeGroup;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
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
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Builtin.DeadCode;

const
  cAppFile = 'C:\P\App.dpr';

type
  TTestFile = record
    Name: string;
    Text: string;
  end;

  TScenario = record
    Files: TArray<TTestFile>;
    Projects: TArray<TRuleProject>;
    Config: string;
    Incomplete: Boolean;
    NoProjects: Boolean;
    /// <summary>Prüfung wie im Editor (#896).</summary>
    Live: Boolean;
    /// <summary>So oft zusätzlich prüfen, mit demselben Graphen (Zeitmessung beim Tippen, #896).</summary>
    Repeats: Integer;
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

function FileOf(const AUnit: string): string;
begin
  Result := 'C:\P\' + AUnit + '.pas';
end;

/// <summary>Unit AName mit den uses-Listen AInterface und AImplementation ('' = ohne) und ABody im
/// implementation-Teil.</summary>
function UnitText(const AName, AInterface, AImplementation, ABody: string): string;
begin
  Result := 'unit ' + AName + ';'#10'interface'#10;
  if AInterface <> '' then
  begin
    Result := Result + 'uses'#10'  ' + AInterface + ';'#10;
  end;
  Result := Result + 'implementation'#10;
  if AImplementation <> '' then
  begin
    Result := Result + 'uses'#10'  ' + AImplementation + ';'#10;
  end;
  Result := Result + ABody + 'end.';
end;

function Project(const AFileName: string; AKind: TRuleProjectKind; const ASources: TArray<string>): TRuleProject;
begin
  Result := Default(TRuleProject);
  Result.FileName := AFileName;
  Result.Kind := AKind;
  Result.Sources := ASources;
end;

/// <summary>Anwendung App mit den Units AUnits (Name, interface-uses, implementation-uses je Eintrag).</summary>
function Group(const AUnits: TArray<TArray<string>>): TScenario;
var
  mItem: TArray<string>;
  mSources: TArray<string>;
  mNames: string;
begin
  Result := Default(TScenario);
  mSources := [cAppFile];
  mNames := '';
  for mItem in AUnits do
  begin
    Result.Put(FileOf(mItem[0]), UnitText(mItem[0], mItem[1], mItem[2], ''));
    mSources := mSources + [FileOf(mItem[0])];
    if mNames <> '' then
    begin
      mNames := mNames + ', ';
    end;
    mNames := mNames + mItem[0];
  end;
  Result.Put(cAppFile, 'program App;'#10'uses'#10'  ' + mNames + ';'#10'begin'#10'end.');
  Result.Projects := [Project('C:\P\App.dproj', TRuleProjectKind.Application, mSources)];
end;

var
  // Dauer der letzten Prüfung in Run ohne Aufbau von Index und Graph (Zeitmessung #896).
  LastCheckMs: Int64;

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
  for mEntry in AScenario.Files do
  begin
    ATexts.AddOrSetValue(UpperCase(mEntry.Name), mEntry.Text);
    if not SameText(ExtractFileExt(mEntry.Name), '.dfm') then
    begin
      Result.AddUnit(TIndexExtractor.ExtractText(mEntry.Text, mEntry.Name, nil, nil, True));
    end;
  end;
end;

/// <summary>Projektdateien des Szenarios; AIncomplete meldet einen laufenden Index.</summary>
function ScenarioProjectFiles(const AScenario: TScenario; const AIndex: ISymbolIndex;
  const ATexts: TDictionary<string, string>; AIncomplete: Boolean): IRuleProjectFiles;
begin
  Result := TRuleProjectFiles.Create(AScenario.Projects, AIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ATexts.TryGetValue(UpperCase(AFileName), AText);
    end,
    function(out AReason: string): Boolean
    begin
      Result := not AIncomplete;
      if AIncomplete then
      begin
        AReason := 'Index läuft';
      end;
    end);
end;

function Run(const AScenario: TScenario; const ACheck: string): TArray<TRuleFinding>;
var
  mWatch: TStopwatch;
  mRound: Integer;
  mTexts: TDictionary<string, string>;
  mIndex: ISymbolIndex;
  mSettings: TServerSettings;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mIncomplete: Boolean;
begin
  Result := nil;
  mIncomplete := AScenario.Incomplete;
  mTexts := TDictionary<string, string>.Create;
  try
    mIndex := IndexScenario(AScenario, mTexts);
    mSettings := ScenarioSettings(AScenario.Config);
    mTree := TSyntaxTreeCache.Parse(AScenario.Text(ACheck));
    try
      mContext := Default(TRuleContext);
      mContext.FileName := ACheck;
      mContext.RelativePath := ExtractFileName(ACheck);
      mContext.UnitName := ChangeFileExt(ExtractFileName(ACheck), '');
      mContext.Text := AScenario.Text(ACheck);
      mContext.Tree := mTree;
      mContext.Index := mIndex;
      mContext.FormText := AScenario.Text(ChangeFileExt(ACheck, '.dfm'));
      mContext.Live := AScenario.Live;
      if not AScenario.NoProjects then
      begin
        mContext.ProjectFiles := ScenarioProjectFiles(AScenario, mIndex, mTexts, mIncomplete);
      end;
      for mRound := 0 to AScenario.Repeats do
      begin
        mWatch := TStopwatch.StartNew;
        Result := TRuleEngine.Run([TUsesCycleRule.Create, TUnusedDeclarationRule.Create, TUnusedUnitRule.Create],
          mSettings, mContext);
        LastCheckMs := mWatch.ElapsedMilliseconds;
      end;
      mContext.ProjectFiles := nil;
    finally
      mTree.Free;
    end;
  finally
    mTexts.Free;
  end;
end;

/// <summary>Meldungen der Regel ARule, je Zeile eine.</summary>
function Messages(const AFindings: TArray<TRuleFinding>; const ARule: string): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFindings do
  begin
    if SameText(mFinding.RuleId, ARule) then
    begin
      Result := Result + mFinding.Message + #10;
    end;
  end;
end;

procedure TDeadCodeTests.CycleOverImplementationWithFullPath;
var
  mData: TScenario;
  mFound: TArray<TRuleFinding>;
begin
  // A -> B (implementation), B -> C (interface), C -> A (implementation).
  mData := Group([TArray<string>.Create('A', '', 'B'), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', '', 'A')]);
  mFound := Run(mData, FileOf('A'));
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → C → A (über implementation-uses)'#10,
    Messages(mFound, cUsesCycleRuleId));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Warning, mFound[0].Severity);
  // Am uses-Eintrag "B" in A (Zeile 4, Spalte 2).
  Assert.AreEqual(4, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Character);
  Assert.AreEqual('Mindestens eine Kante liegt im implementation-Teil: Der Compiler erlaubt den Zyklus.'#13#10 +
    'A → B (implementation)'#13#10'B → C (interface)'#13#10'C → A (implementation)',
    StringReplace(mFound[0].Details, sLineBreak, #13#10, [rfReplaceAll]));
  // Jede Unit des Zyklus meldet ihren Teil.
  Assert.AreEqual('Zirkuläre Unit-Referenz: B → C → A → B (über implementation-uses)'#10,
    Messages(Run(mData, FileOf('B')), cUsesCycleRuleId));
end;

procedure TDeadCodeTests.InterfaceCycleIsError;
var
  mData: TScenario;
  mFound: TArray<TRuleFinding>;
begin
  mData := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', 'A', '')]);
  mFound := Run(mData, FileOf('C'));
  Assert.AreEqual('Zirkuläre Unit-Referenz: C → A → B → C (wie F2047)'#10, Messages(mFound, cUsesCycleRuleId));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, mFound[0].Severity);
  Assert.IsTrue(StartsText('Alle Kanten liegen im interface-Teil', mFound[0].Details), mFound[0].Details);
  // Kürzester Weg: Mit einer zusätzlichen Abkürzung A -> C über implementation bleibt der interface-Zyklus
  // maßgeblich, weil er ein Compilerfehler ist.
  mData.Put(FileOf('A'), UnitText('A', 'B', 'C', ''));
  Assert.AreEqual('Zirkuläre Unit-Referenz: C → A → B → C (wie F2047)'#10,
    Messages(Run(mData, FileOf('C')), cUsesCycleRuleId));
end;

procedure TDeadCodeTests.ImplementationOptionOff;
var
  mData: TScenario;
begin
  mData := Group([TArray<string>.Create('A', '', 'B'), TArray<string>.Create('B', '', 'A')]);
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (über implementation-uses)'#10,
    Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
  mData.Config := '{"rules": {"uses-cycle": {"implementation": false}}}';
  Assert.AreEqual('', Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
  // Ein Zyklus nur über interface bleibt.
  mData.Put(FileOf('A'), UnitText('A', 'B', '', ''));
  mData.Put(FileOf('B'), UnitText('B', 'A', '', ''));
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (wie F2047)'#10,
    Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
  // off schaltet die Regel ganz ab.
  mData.Config := '{"rules": {"uses-cycle": "off"}}';
  Assert.AreEqual('', Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
end;

procedure TDeadCodeTests.NoCycleNoFinding;
var
  mData: TScenario;
begin
  mData := Group([TArray<string>.Create('A', 'B', 'C'), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', '', '')]);
  Assert.AreEqual('', Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
  Assert.AreEqual('', Messages(Run(mData, FileOf('C')), cUsesCycleRuleId));
end;

procedure TDeadCodeTests.CycleSilentWithoutProjectsOrWhileIndexing;
var
  mData: TScenario;
begin
  mData := Group([TArray<string>.Create('A', '', 'B'), TArray<string>.Create('B', '', 'A')]);
  mData.Incomplete := True;
  Assert.AreEqual('', Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
  mData.Incomplete := False;
  mData.NoProjects := True;
  Assert.AreEqual('', Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
end;

const
  cDeclarationsText =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'procedure Start;'#10 +
    'implementation'#10 +
    'type'#10 +
    '  THelfer = class'#10 +
    '    function Kopie: THelfer;'#10 +
    '  end;'#10 +
    '  TFarbe = (Rot, Gruen);'#10 +
    'const'#10 +
    '  Grenze = 10;'#10 +
    '  Genutzt = 5;'#10 +
    'var'#10 +
    '  Zaehler: Integer;'#10 +
    'function THelfer.Kopie: THelfer;'#10 +
    'begin'#10 +
    '  Result := THelfer.Create;'#10 +
    'end;'#10 +
    'procedure Rekursiv(N: Integer);'#10 +
    'begin'#10 +
    '  if N > 0 then'#10 +
    '    Rekursiv(N - 1);'#10 +
    'end;'#10 +
    'procedure Genutzte;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Start;'#10 +
    'var'#10 +
    '  F: TFarbe;'#10 +
    'begin'#10 +
    '  Genutzte;'#10 +
    '  F := Rot;'#10 +
    '  Writeln(Genutzt, Ord(F));'#10 +
    'end;'#10 +
    'end.';

procedure TDeadCodeTests.UnusedDeclarations;
var
  mData: TScenario;
  mFound: TArray<TRuleFinding>;
begin
  mData := Default(TScenario);
  mData.Put(FileOf('Werkzeug'), cDeclarationsText);
  mData.NoProjects := True;
  mFound := Run(mData, FileOf('Werkzeug'));
  Assert.AreEqual(
    'Typ THelfer wird nirgends verwendet.'#10 +
    'Konstante Grenze wird nirgends verwendet.'#10 +
    'Globale Variable Zaehler wird nirgends verwendet.'#10 +
    'Routine Rekursiv wird nirgends verwendet.'#10, Messages(mFound, cUnusedDeclarationRuleId));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, mFound[0].Severity);
  Assert.AreEqual(5, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Character);
  // Korrektur: als bewusst vorhanden markieren.
  Assert.AreEqual('  // lsp-ignore: unused-declaration'#10, mFound[0].Fixes[0].Edits[0].NewText);
  mData.Config := '{"rules": {"unused-declaration": "off"}}';
  Assert.AreEqual('', Messages(Run(mData, FileOf('Werkzeug')), cUnusedDeclarationRuleId));
end;

procedure TDeadCodeTests.UsedDeclarationsAreSilent;
var
  mData: TScenario;
begin
  mData := Default(TScenario);
  mData.NoProjects := True;
  // exports, forward-Deklaration mit Aufruf, Attributklasse in Kurzform, Rumpf einer interface-Routine.
  mData.Put(FileOf('Werkzeug'),
    'library Werkzeug;'#10 +
    'type'#10 +
    '  BehaltenAttribute = class(TCustomAttribute)'#10 +
    '  end;'#10 +
    '  [Behalten]'#10 +
    '  TMarkiert = class'#10 +
    '  end;'#10 +
    'procedure Spaeter; forward;'#10 +
    'function Exportiert: Integer; stdcall;'#10 +
    'begin'#10 +
    '  Spaeter;'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    'procedure Spaeter;'#10 +
    'begin'#10 +
    'end;'#10 +
    'exports'#10 +
    '  Exportiert;'#10 +
    'begin'#10 +
    'end.');
  Assert.AreEqual('', Messages(Run(mData, FileOf('Werkzeug')), cUnusedDeclarationRuleId));
  // Rümpfe von interface-Routinen gehören zu unused-public-member.
  mData.Put(FileOf('Werkzeug'), UnitText('Werkzeug', '', '', 'procedure Start;'#10'begin'#10'end;'#10));
  mData.Put(FileOf('Werkzeug'), StringReplace(mData.Text(FileOf('Werkzeug')), 'implementation',
    'procedure Start;'#10'implementation', []));
  Assert.AreEqual('', Messages(Run(mData, FileOf('Werkzeug')), cUnusedDeclarationRuleId));
end;

procedure TDeadCodeTests.KeepSettingsAndFormText;
var
  mData: TScenario;
  mText: string;
begin
  mText := UnitText('Werkzeug', '', '', 'procedure KlickHandler;'#10'begin'#10'end;'#10 +
    'procedure Pruefe;'#10'begin'#10'end;'#10);
  mData := Default(TScenario);
  mData.NoProjects := True;
  mData.Put(FileOf('Werkzeug'), mText);
  Assert.AreEqual('Routine KlickHandler wird nirgends verwendet.'#10'Routine Pruefe wird nirgends verwendet.'#10,
    Messages(Run(mData, FileOf('Werkzeug')), cUnusedDeclarationRuleId));
  mData.Config := '{"deadCode": {"keepPatterns": ["*Handler"]}}';
  Assert.AreEqual('Routine Pruefe wird nirgends verwendet.'#10,
    Messages(Run(mData, FileOf('Werkzeug')), cUnusedDeclarationRuleId));
  // Name in der Formulardatei.
  mData.Put(ChangeFileExt(FileOf('Werkzeug'), '.dfm'), 'object F: TF'#10'  OnClick = Pruefe'#10'end');
  Assert.AreEqual('', Messages(Run(mData, FileOf('Werkzeug')), cUnusedDeclarationRuleId));
end;

procedure TDeadCodeTests.UnusedUnitOnlyNamedByProgram;
var
  mData: TScenario;
  mFound: TArray<TRuleFinding>;
begin
  mData := Group([TArray<string>.Create('Haupt', 'Dienst', ''), TArray<string>.Create('Dienst', '', ''),
    TArray<string>.Create('Waise', '', '')]);
  // Haupt deklariert Start, das Programm ruft es auf.
  mData.Put(FileOf('Haupt'), 'unit Haupt;'#10'interface'#10'uses'#10'  Dienst;'#10'procedure Start;'#10 +
    'implementation'#10'procedure Start;'#10'begin'#10'end;'#10'end.');
  mData.Put(cAppFile, 'program App;'#10'uses'#10'  Haupt, Dienst, Waise;'#10'begin'#10'  Start;'#10'end.');
  mFound := Run(mData, FileOf('Waise'));
  Assert.AreEqual('Unit Waise wird von keiner anderen Unit verwendet; nur App.dpr nennt sie im uses.'#10,
    Messages(mFound, cUnusedUnitRuleId));
  Assert.AreEqual(0, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(5, mFound[0].Range.StartPos.Character);
  Assert.AreEqual<TRuleConfidence>(TRuleConfidence.Medium, mFound[0].Confidence);
  Assert.AreEqual('', Messages(Run(mData, FileOf('Haupt')), cUnusedUnitRuleId));
  Assert.AreEqual('', Messages(Run(mData, FileOf('Dienst')), cUnusedUnitRuleId));
  // Ganz ohne uses-Eintrag.
  mData.Put(cAppFile, 'program App;'#10'uses'#10'  Haupt, Dienst;'#10'begin'#10'  Start;'#10'end.');
  Assert.AreEqual('Unit Waise wird von keiner Unit und keinem Programm verwendet.'#10,
    Messages(Run(mData, FileOf('Waise')), cUnusedUnitRuleId));
end;

procedure TDeadCodeTests.UnusedUnitExceptions;
var
  mData: TScenario;
begin
  mData := Group([TArray<string>.Create('Waise', '', '')]);
  Assert.AreNotEqual('', Messages(Run(mData, FileOf('Waise')), cUnusedUnitRuleId));
  // initialization-Teil: Registrierung beim Start.
  mData.Put(FileOf('Waise'), 'unit Waise;'#10'interface'#10'implementation'#10'initialization'#10'end.');
  Assert.AreEqual('', Messages(Run(mData, FileOf('Waise')), cUnusedUnitRuleId));
  // Testklasse ohne Registrierung: DUnitX findet [TestFixture] per RTTI.
  mData.Put(FileOf('Waise'), 'unit Waise;'#10'interface'#10'type'#10'  [TestFixture]'#10'  TWaiseTests = class'#10 +
    '  public'#10'    [Test]'#10'    procedure Laeuft;'#10'  end;'#10'implementation'#10 +
    'procedure TWaiseTests.Laeuft;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual('', Messages(Run(mData, FileOf('Waise')), cUnusedUnitRuleId));
  // [Test] allein macht keine Testklasse.
  mData.Put(FileOf('Waise'), 'unit Waise;'#10'interface'#10'type'#10'  TWaise = class'#10'  public'#10 +
    '    [Test]'#10'    procedure Laeuft;'#10'  end;'#10'implementation'#10 +
    'procedure TWaise.Laeuft;'#10'begin'#10'end;'#10'end.');
  Assert.AreNotEqual('', Messages(Run(mData, FileOf('Waise')), cUnusedUnitRuleId));
  // Package: Nutzer außerhalb der Gruppe; mit projectKinds gemeldet.
  mData := Group([TArray<string>.Create('Waise', '', '')]);
  mData.Projects[0].Kind := TRuleProjectKind.Package;
  Assert.AreEqual('', Messages(Run(mData, FileOf('Waise')), cUnusedUnitRuleId));
  mData.Config := '{"rules": {"unused-unit": {"projectKinds": ["package"]}}}';
  Assert.AreNotEqual('', Messages(Run(mData, FileOf('Waise')), cUnusedUnitRuleId));
  // Index läuft, ohne Projekte.
  mData := Group([TArray<string>.Create('Waise', '', '')]);
  mData.Incomplete := True;
  Assert.AreEqual('', Messages(Run(mData, FileOf('Waise')), cUnusedUnitRuleId));
  mData.Incomplete := False;
  mData.NoProjects := True;
  Assert.AreEqual('', Messages(Run(mData, FileOf('Waise')), cUnusedUnitRuleId));
end;

/// <summary>Der erste Treffer der Regel uses-cycle; Default ohne.</summary>
function CycleFinding(const AFindings: TArray<TRuleFinding>): TRuleFinding;
var
  mFinding: TRuleFinding;
begin
  for mFinding in AFindings do
  begin
    if SameText(mFinding.RuleId, cUsesCycleRuleId) then
    begin
      Exit(mFinding);
    end;
  end;
  Result := Default(TRuleFinding);
end;

/// <summary>"Unit@Datei:Zeile:Zeichen" je Stelle, durch Leerzeichen getrennt.</summary>
function PlacesText(const AFinding: TRuleFinding): string;
var
  mRelated: TRuleRelated;
begin
  Result := '';
  for mRelated in AFinding.Related do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + Format('%s@%s:%d:%d', [mRelated.Message, ExtractFileName(mRelated.FileName),
      mRelated.Range.StartPos.Line, mRelated.Range.StartPos.Character]);
  end;
end;

/// <summary>Titel der Korrekturen, je Zeile einer.</summary>
function FixTitles(const AFinding: TRuleFinding): string;
var
  mFix: TRuleFix;
begin
  Result := '';
  for mFix in AFinding.Fixes do
  begin
    Result := Result + mFix.Title + #10;
  end;
end;

procedure TDeadCodeTests.LiveInterfaceCycleWithPathAndPlaces;
var
  mData: TScenario;
  mFound: TRuleFinding;
begin
  // Wie im Referenzprojekt: uA -> uB -> uC, dann uA im interface-uses von uC ergänzt.
  mData := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', 'A', '')]);
  mData.Live := True;
  mFound := CycleFinding(Run(mData, FileOf('C')));
  Assert.AreEqual('Zirkuläre Unit-Referenz: C → A → B → C (wie F2047)', mFound.Message);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, mFound.Severity);
  Assert.AreEqual(3, mFound.Range.StartPos.Line);
  Assert.AreEqual(2, mFound.Range.StartPos.Character);
  // Jede Unit des Pfads mit ihrem uses-Eintrag: die eigene am Eintrag in B, dann jede Kante.
  Assert.AreEqual('C@B.pas:3:2 A@C.pas:3:2 B@A.pas:3:2 C@B.pas:3:2', PlacesText(mFound));
  // Ungespeicherter Stand einer anderen offenen Unit: Ohne B -> C gibt es keinen Zyklus mehr.
  mData.Put(FileOf('B'), UnitText('B', '', '', ''));
  Assert.AreEqual('', Messages(Run(mData, FileOf('C')), cUsesCycleRuleId));
end;

procedure TDeadCodeTests.LiveImplementationCycleOnlyWhenEnabled;
var
  mData: TScenario;
  mFound: TRuleFinding;
begin
  mData := Group([TArray<string>.Create('A', '', 'B'), TArray<string>.Create('B', '', 'A')]);
  mData.Live := True;
  Assert.AreEqual('', Messages(Run(mData, FileOf('A')), cUsesCycleRuleId), 'im Editor erlaubt und still');
  mData.Config := '{"diagnostics": {"usesCycleImplementation": true}}';
  mFound := CycleFinding(Run(mData, FileOf('A')));
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (über implementation-uses)', mFound.Message);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, mFound.Severity);
  // Ein Eintrag im implementation-uses lässt sich nicht weiter verschieben: nur „Graph zeigen“.
  Assert.AreEqual('Graph zeigen (Unit-Beziehungen)'#10, FixTitles(mFound));
  Assert.IsTrue(mFound.Fixes[0].ShowsUnitRelations);
  // Projektweit (#64) bleibt es eine Warnung.
  mData.Live := False;
  mData.Config := '';
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Warning, CycleFinding(Run(mData, FileOf('A'))).Severity);
end;

procedure TDeadCodeTests.LiveSwitchLeavesProjectCheck;
var
  mData: TScenario;
begin
  mData := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'A', '')]);
  mData.Config := '{"diagnostics": {"usesCycleLive": false}}';
  mData.Live := True;
  Assert.AreEqual('', Messages(Run(mData, FileOf('A')), cUsesCycleRuleId), 'keine Meldung beim Tippen');
  mData.Live := False;
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (wie F2047)'#10,
    Messages(Run(mData, FileOf('A')), cUsesCycleRuleId),
    'die projektweite Prüfung bleibt');
end;

procedure TDeadCodeTests.SelfReferenceIsError;
var
  mData: TScenario;
  mFound: TRuleFinding;
  mFixed: string;
begin
  mData := Group([TArray<string>.Create('A', 'A', '')]);
  mData.NoProjects := True;
  mFound := CycleFinding(Run(mData, FileOf('A')));
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → A (wie F2092)', mFound.Message);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, mFound.Severity);
  Assert.AreEqual('Eintrag entfernen'#10, FixTitles(mFound));
  mFixed := TChangeSignature.ApplyEdits(mData.Text(FileOf('A')), mFound.Fixes[0].Edits);
  Assert.AreEqual(0, Pos('uses', mFixed), mFixed);
  // Auch mit Projekten nur eine Meldung, nicht noch eine über den Graphen.
  mData.NoProjects := False;
  mData.Live := True;
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → A (wie F2092)'#10,
    Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
end;

procedure TDeadCodeTests.SeveralCyclesAndShortestPath;
var
  mData: TScenario;
begin
  mData := Group([TArray<string>.Create('A', 'B, C', ''), TArray<string>.Create('B', 'A', ''),
    TArray<string>.Create('C', 'A', '')]);
  mData.Live := True;
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (wie F2047)'#10 +
    'Zirkuläre Unit-Referenz: A → C → A (wie F2047)'#10,
    Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
  // B -> D -> E -> A ist länger als B -> C -> A, obwohl D zuerst im uses steht.
  mData := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'D, C', ''),
    TArray<string>.Create('C', 'A', ''), TArray<string>.Create('D', 'E', ''), TArray<string>.Create('E', 'A', '')]);
  mData.Live := True;
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → C → A (wie F2047)'#10,
    Messages(Run(mData, FileOf('A')), cUsesCycleRuleId));
end;

procedure TDeadCodeTests.MoveFixOnlyWithoutInterfaceUse;
var
  mData: TScenario;
  mFound: TRuleFinding;
  mFixed: string;
begin
  mData := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', 'A', 'B')]);
  mData.Live := True;
  mFound := CycleFinding(Run(mData, FileOf('C')));
  Assert.AreEqual('In implementation-uses verschieben'#10, FixTitles(mFound));
  mFixed := TChangeSignature.ApplyEdits(mData.Text(FileOf('C')), mFound.Fixes[0].Edits);
  Assert.AreEqual('unit C;'#10'interface'#10#10'implementation'#10'uses'#10'  B,'#10'  A;'#10'end.', mFixed);
  // Die Korrektur beseitigt die Meldung.
  mData.Put(FileOf('C'), mFixed);
  Assert.AreEqual('', Messages(Run(mData, FileOf('C')), cUsesCycleRuleId));
end;

procedure TDeadCodeTests.MoveFixSortsLikeSortUses;
var
  mData: TScenario;
  mFound: TRuleFinding;
begin
  mData := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', 'A', 'X'), TArray<string>.Create('X', '', '')]);
  mData.Live := True;
  mData.Config := '{"sortUses": true}';
  mFound := CycleFinding(Run(mData, FileOf('C')));
  Assert.AreEqual('unit C;'#10'interface'#10#10'implementation'#10'uses'#10'  A,'#10'  X;'#10'end.',
    TChangeSignature.ApplyEdits(mData.Text(FileOf('C')), mFound.Fixes[0].Edits));
  Assert.AreEqual(1, Integer(Length(mFound.Fixes[0].Edits)), 'eine kleinste Ersetzung');
end;

procedure TDeadCodeTests.JumpsAndGraphWhenInterfaceNeedsUnit;
var
  mData: TScenario;
  mFound: TRuleFinding;
begin
  mData := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', '')]);
  mData.Put(FileOf('A'), 'unit A;'#10'interface'#10'uses'#10'  B;'#10'type'#10'  TA = class end;'#10 +
    'implementation'#10'end.');
  mData.Put(FileOf('C'), 'unit C;'#10'interface'#10'uses'#10'  A;'#10'type'#10'  TC = class(TA) end;'#10 +
    'implementation'#10'end.');
  mData.Projects[0].Sources := mData.Projects[0].Sources + [FileOf('C')];
  mData.Live := True;
  mFound := CycleFinding(Run(mData, FileOf('C')));
  Assert.AreEqual('Zirkuläre Unit-Referenz: C → A → B → C (wie F2047)', mFound.Message);
  Assert.AreEqual('Zu TA springen (Zeile 6, braucht A im interface)'#10'Graph zeigen (Unit-Beziehungen)'#10,
    FixTitles(mFound));
  Assert.IsTrue(mFound.Fixes[0].HasJump);
  Assert.AreEqual(5, mFound.Fixes[0].JumpTo.Line);
  Assert.AreEqual(13, mFound.Fixes[0].JumpTo.Character);
  Assert.IsTrue(mFound.Fixes[1].ShowsUnitRelations);
  Assert.IsTrue(Pos('Im interface-Teil gebraucht: TA (Zeile 6)', mFound.Details) > 0, mFound.Details);
end;

procedure TDeadCodeTests.ParserReadsUsesCycleSettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := TServerSettings.Default;
  Assert.IsTrue(mSettings.DiagnosticsUsesCycleLive);
  Assert.IsFalse(mSettings.DiagnosticsUsesCycleImplementation);
  mSettings := TConfigurationParser.Parse('{"diagnostics": {"usesCycleLive": false, "usesCycleImplementation": true}}',
    mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.DiagnosticsUsesCycleLive);
  Assert.IsTrue(mSettings.DiagnosticsUsesCycleImplementation);
  mSettings := TConfigurationParser.Parse('{"diagnostics": {"usesCycleLive": "nein"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(mSettings.DiagnosticsUsesCycleLive);
  mIssues := nil;
end;

procedure TDeadCodeTests.LiveCycleCheckOf2000Units;
const
  cUnitCount = 2000;
var
  mUnits: TArray<TArray<string>>;
  mIndex: Integer;
  mData: TScenario;
  mWatch: TStopwatch;
begin
  // Projektgruppe wie #501: Kette E1 -> … -> E2000 über interface, E2000 schließt den Kreis; dazu je Unit
  // ein Eintrag im implementation-uses, der keinen Zyklus bildet.
  mUnits := nil;
  for mIndex := 1 to cUnitCount do
  begin
    mUnits := mUnits + [TArray<string>.Create(Format('E%d', [mIndex]), Format('E%d', [mIndex mod cUnitCount + 1]),
      Format('E%d', [(mIndex + 1) mod cUnitCount + 1]))];
  end;
  mData := Group(mUnits);
  mData.Live := True;
  // Beim Tippen steht der Graph schon (inkrementell, #268): gemessen wird die zweite Prüfung.
  mData.Repeats := 1;
  mWatch := TStopwatch.StartNew;
  Assert.AreEqual(1, Integer(Length(Run(mData, FileOf('E1')))));
  mWatch.Stop;
  System.Writeln(Format('uses-cycle live: Prüfung bei %d Units in %d ms (mit Aufbau von Index und Graph %d ms)',
    [cUnitCount, LastCheckMs, mWatch.ElapsedMilliseconds]));
  Assert.IsTrue(LastCheckMs < 200, 'zu langsam für die Prüfung beim Tippen');
end;

procedure TDeadCodeTests.ParserReadsDeadCode;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.Parse('{"deadCode": {"keepAttributes": ["JsonName"], ' +
    '"keepPatterns": ["*Handler", "T*Plugin"]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('JsonName', string.Join(',', mSettings.DeadCodeKeepAttributes));
  Assert.AreEqual('*Handler,T*Plugin', string.Join(',', mSettings.DeadCodeKeepPatterns));
  mSettings := TServerSettings.Default;
  Assert.AreEqual(0, Integer(Length(mSettings.DeadCodeKeepAttributes)));
  TConfigurationParser.Parse('{"deadCode": {"keepAttributes": "JsonName", "keepPatterns": [1], "x": 1}}', mIssues);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  TConfigurationParser.Parse('{"deadCode": [], "rules": {"uses-cycle": {"implementation": "ja"}, ' +
    '"unused-unit": {"projectKinds": "package"}}}', mIssues);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  mIssues := nil;
end;

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

/// <summary>RefApp.dpr und die Units aus ihren in-Klauseln, alle in AData abgelegt.</summary>
function RefAppSources(const AFolder: string; var AData: TScenario): TArray<string>;
var
  mMainFile, mSource: string;
  mTree: TSyntaxTree;
  mToken: TPascalToken;
begin
  mMainFile := TPath.Combine(AFolder, 'RefApp.dpr');
  AData.Put(mMainFile, ReadSource(mMainFile));
  Result := [mMainFile];
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
      end;
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Die mit „ERWARTET-PROJEKT: Regel“ markierten Zeilen von ASource, je Regel aus ARules.</summary>
function ExpectedMarkers(const ASource, AText: string; const ARules: array of string): string;
var
  mLines: TArray<string>;
  mRule: string;
  mIndex: Integer;
begin
  Result := '';
  mLines := AText.Replace(#13#10, #10).Split([#10]);
  for mRule in ARules do
  begin
    for mIndex := 0 to High(mLines) do
    begin
      if mLines[mIndex].Contains('// ERWARTET-PROJEKT: ' + mRule) then
      begin
        Result := Result + Format('%s:%d %s'#10, [ExtractFileName(ASource), mIndex + 1, mRule]);
      end;
    end;
  end;
end;

/// <summary>Treffer der Regeln aus ARules in ASource; APaths sammelt die Meldungen von uses-cycle.</summary>
function ActualFindings(const AData: TScenario; const ASource: string; const ARules: array of string;
  var APaths: string): string;
var
  mRule: string;
  mFinding: TRuleFinding;
begin
  Result := '';
  for mRule in ARules do
  begin
    for mFinding in Run(AData, ASource) do
    begin
      if SameText(mFinding.RuleId, mRule) then
      begin
        Result := Result + Format('%s:%d %s'#10, [ExtractFileName(ASource), mFinding.Range.StartPos.Line + 1,
          mRule]);
        if mRule = cUsesCycleRuleId then
        begin
          APaths := APaths + mFinding.Message + #10;
        end;
      end;
    end;
  end;
end;

procedure TDeadCodeTests.ReferenceProjectMatchesMarkers;
const
  cRules: array[0..1] of string = (cUsesCycleRuleId, cUnusedUnitRuleId);
var
  mFolder, mSource, mExpected, mActual, mPaths: string;
  mData: TScenario;
  mSources: TArray<string>;
begin
  mFolder := ReferenceFolder;
  if mFolder = '' then
  begin
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  end;
  // Units von RefApp aus den in-Klauseln der .dpr.
  mData := Default(TScenario);
  mSources := RefAppSources(mFolder, mData);
  mData.Projects := [Project(TPath.Combine(mFolder, 'RefApp.dproj'), TRuleProjectKind.Application, mSources)];
  // Erwartet: genau die markierten Zeilen je Regel, sonst nichts.
  mExpected := '';
  mActual := '';
  mPaths := '';
  for mSource in mSources do
  begin
    mExpected := mExpected + ExpectedMarkers(mSource, mData.Text(mSource), cRules);
    if SameText(ExtractFileExt(mSource), '.pas') then
    begin
      mActual := mActual + ActualFindings(mData, mSource, cRules, mPaths);
    end;
  end;
  Assert.AreEqual(mExpected, mActual);
  Assert.IsTrue(Pos('uses-cycle', mExpected) > 0, 'Kein Zyklus im Referenzprojekt markiert');
  // Vollständiger Pfad über implementation-uses.
  Assert.IsTrue(Pos('Zirkuläre Unit-Referenz: Ref.Formulare.Detail → Ref.Formulare.Haupt → Ref.Formulare.Detail ' +
    '(über implementation-uses)', mPaths) > 0, mPaths);
end;

procedure TDeadCodeTests.CycleCheckOfLargeGroup;
const
  cUnitCount = 400;
var
  mUnits: TArray<TArray<string>>;
  mIndex: Integer;
  mData: TScenario;
  mWatch: TStopwatch;
begin
  // Kette E1 -> E2 -> … -> E400 über implementation, E400 schließt den Kreis.
  mUnits := nil;
  for mIndex := 1 to cUnitCount do
  begin
    mUnits := mUnits + [TArray<string>.Create(Format('E%d', [mIndex]), '', Format('E%d', [mIndex mod cUnitCount + 1]))];
  end;
  mData := Group(mUnits);
  mWatch := TStopwatch.StartNew;
  Assert.AreEqual(1, Integer(Length(Run(mData, FileOf('E1')))));
  mWatch.Stop;
  System.Writeln(Format('uses-cycle: Prüfung bei %d Units in %d ms', [cUnitCount, mWatch.ElapsedMilliseconds]));
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 5000, 'zu langsam');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeadCodeTests);

end.
