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
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Builtin.DeadCode;

const
  AppFile = 'C:\P\App.dpr';

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
    Result := Result + 'uses'#10'  ' + AInterface + ';'#10;
  Result := Result + 'implementation'#10;
  if AImplementation <> '' then
    Result := Result + 'uses'#10'  ' + AImplementation + ';'#10;
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
  Item: TArray<string>;
  Sources: TArray<string>;
  Names: string;
begin
  Result := Default(TScenario);
  Sources := [AppFile];
  Names := '';
  for Item in AUnits do
  begin
    Result.Put(FileOf(Item[0]), UnitText(Item[0], Item[1], Item[2], ''));
    Sources := Sources + [FileOf(Item[0])];
    if Names <> '' then
      Names := Names + ', ';
    Names := Names + Item[0];
  end;
  Result.Put(AppFile, 'program App;'#10'uses'#10'  ' + Names + ';'#10'begin'#10'end.');
  Result.Projects := [Project('C:\P\App.dproj', TRuleProjectKind.Application, Sources)];
end;

var
  // Dauer der letzten Prüfung in Run ohne Aufbau von Index und Graph (Zeitmessung #896).
  LastCheckMs: Int64;

function Run(const AScenario: TScenario; const ACheck: string): TArray<TRuleFinding>;
var
  Watch: TStopwatch;
  Round: Integer;
  Texts: TDictionary<string, string>;
  Index: ISymbolIndex;
  Entry: TTestFile;
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Incomplete: Boolean;
begin
  Incomplete := AScenario.Incomplete;
  Texts := TDictionary<string, string>.Create;
  try
    Index := TSymbolIndex.Create;
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
      Context.RelativePath := ExtractFileName(ACheck);
      Context.UnitName := ChangeFileExt(ExtractFileName(ACheck), '');
      Context.Text := AScenario.Text(ACheck);
      Context.Tree := Tree;
      Context.Index := Index;
      Context.FormText := AScenario.Text(ChangeFileExt(ACheck, '.dfm'));
      Context.Live := AScenario.Live;
      if not AScenario.NoProjects then
        Context.ProjectFiles := TRuleProjectFiles.Create(AScenario.Projects, Index,
          function(const AFileName: string; out AText: string): Boolean
          begin
            Result := Texts.TryGetValue(UpperCase(AFileName), AText);
          end,
          function(out AReason: string): Boolean
          begin
            Result := not Incomplete;
            if Incomplete then
              AReason := 'Index läuft';
          end);
      for Round := 0 to AScenario.Repeats do
      begin
        Watch := TStopwatch.StartNew;
        Result := TRuleEngine.Run([TUsesCycleRule.Create, TUnusedDeclarationRule.Create, TUnusedUnitRule.Create],
          Settings, Context);
        LastCheckMs := Watch.ElapsedMilliseconds;
      end;
      Context.ProjectFiles := nil;
    finally
      Tree.Free;
    end;
  finally
    Texts.Free;
  end;
end;

/// <summary>Meldungen der Regel ARule, je Zeile eine.</summary>
function Messages(const AFindings: TArray<TRuleFinding>; const ARule: string): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFindings do
    if SameText(Finding.RuleId, ARule) then
      Result := Result + Finding.Message + #10;
end;

procedure TDeadCodeTests.CycleOverImplementationWithFullPath;
var
  Data: TScenario;
  Found: TArray<TRuleFinding>;
begin
  // A -> B (implementation), B -> C (interface), C -> A (implementation).
  Data := Group([TArray<string>.Create('A', '', 'B'), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', '', 'A')]);
  Found := Run(Data, FileOf('A'));
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → C → A (über implementation-uses)'#10,
    Messages(Found, UsesCycleRuleId));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Warning, Found[0].Severity);
  // Am uses-Eintrag "B" in A (Zeile 4, Spalte 2).
  Assert.AreEqual(4, Found[0].Range.StartPos.Line);
  Assert.AreEqual(2, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Mindestens eine Kante liegt im implementation-Teil: Der Compiler erlaubt den Zyklus.'#13#10 +
    'A → B (implementation)'#13#10'B → C (interface)'#13#10'C → A (implementation)',
    StringReplace(Found[0].Details, sLineBreak, #13#10, [rfReplaceAll]));
  // Jede Unit des Zyklus meldet ihren Teil.
  Assert.AreEqual('Zirkuläre Unit-Referenz: B → C → A → B (über implementation-uses)'#10,
    Messages(Run(Data, FileOf('B')), UsesCycleRuleId));
end;

procedure TDeadCodeTests.InterfaceCycleIsError;
var
  Data: TScenario;
  Found: TArray<TRuleFinding>;
begin
  Data := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', 'A', '')]);
  Found := Run(Data, FileOf('C'));
  Assert.AreEqual('Zirkuläre Unit-Referenz: C → A → B → C (wie F2047)'#10, Messages(Found, UsesCycleRuleId));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, Found[0].Severity);
  Assert.IsTrue(StartsText('Alle Kanten liegen im interface-Teil', Found[0].Details), Found[0].Details);
  // Kürzester Weg: Mit einer zusätzlichen Abkürzung A -> C über implementation bleibt der interface-Zyklus
  // maßgeblich, weil er ein Compilerfehler ist.
  Data.Put(FileOf('A'), UnitText('A', 'B', 'C', ''));
  Assert.AreEqual('Zirkuläre Unit-Referenz: C → A → B → C (wie F2047)'#10,
    Messages(Run(Data, FileOf('C')), UsesCycleRuleId));
end;

procedure TDeadCodeTests.ImplementationOptionOff;
var
  Data: TScenario;
begin
  Data := Group([TArray<string>.Create('A', '', 'B'), TArray<string>.Create('B', '', 'A')]);
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (über implementation-uses)'#10,
    Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
  Data.Config := '{"rules": {"uses-cycle": {"implementation": false}}}';
  Assert.AreEqual('', Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
  // Ein Zyklus nur über interface bleibt.
  Data.Put(FileOf('A'), UnitText('A', 'B', '', ''));
  Data.Put(FileOf('B'), UnitText('B', 'A', '', ''));
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (wie F2047)'#10,
    Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
  // off schaltet die Regel ganz ab.
  Data.Config := '{"rules": {"uses-cycle": "off"}}';
  Assert.AreEqual('', Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
end;

procedure TDeadCodeTests.NoCycleNoFinding;
var
  Data: TScenario;
begin
  Data := Group([TArray<string>.Create('A', 'B', 'C'), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', '', '')]);
  Assert.AreEqual('', Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
  Assert.AreEqual('', Messages(Run(Data, FileOf('C')), UsesCycleRuleId));
end;

procedure TDeadCodeTests.CycleSilentWithoutProjectsOrWhileIndexing;
var
  Data: TScenario;
begin
  Data := Group([TArray<string>.Create('A', '', 'B'), TArray<string>.Create('B', '', 'A')]);
  Data.Incomplete := True;
  Assert.AreEqual('', Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
  Data.Incomplete := False;
  Data.NoProjects := True;
  Assert.AreEqual('', Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
end;

const
  DeclarationsText =
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
  Data: TScenario;
  Found: TArray<TRuleFinding>;
begin
  Data := Default(TScenario);
  Data.Put(FileOf('Werkzeug'), DeclarationsText);
  Data.NoProjects := True;
  Found := Run(Data, FileOf('Werkzeug'));
  Assert.AreEqual(
    'Typ THelfer wird nirgends verwendet.'#10 +
    'Konstante Grenze wird nirgends verwendet.'#10 +
    'Globale Variable Zaehler wird nirgends verwendet.'#10 +
    'Routine Rekursiv wird nirgends verwendet.'#10, Messages(Found, UnusedDeclarationRuleId));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, Found[0].Severity);
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(2, Found[0].Range.StartPos.Character);
  // Korrektur: als bewusst vorhanden markieren.
  Assert.AreEqual('  // lsp-ignore: unused-declaration'#10, Found[0].Fixes[0].Edits[0].NewText);
  Data.Config := '{"rules": {"unused-declaration": "off"}}';
  Assert.AreEqual('', Messages(Run(Data, FileOf('Werkzeug')), UnusedDeclarationRuleId));
end;

procedure TDeadCodeTests.UsedDeclarationsAreSilent;
var
  Data: TScenario;
begin
  Data := Default(TScenario);
  Data.NoProjects := True;
  // exports, forward-Deklaration mit Aufruf, Attributklasse in Kurzform, Rumpf einer interface-Routine.
  Data.Put(FileOf('Werkzeug'),
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
  Assert.AreEqual('', Messages(Run(Data, FileOf('Werkzeug')), UnusedDeclarationRuleId));
  // Rümpfe von interface-Routinen gehören zu unused-public-member.
  Data.Put(FileOf('Werkzeug'), UnitText('Werkzeug', '', '', 'procedure Start;'#10'begin'#10'end;'#10));
  Data.Put(FileOf('Werkzeug'), StringReplace(Data.Text(FileOf('Werkzeug')), 'implementation',
    'procedure Start;'#10'implementation', []));
  Assert.AreEqual('', Messages(Run(Data, FileOf('Werkzeug')), UnusedDeclarationRuleId));
end;

procedure TDeadCodeTests.KeepSettingsAndFormText;
var
  Data: TScenario;
  Text: string;
begin
  Text := UnitText('Werkzeug', '', '', 'procedure KlickHandler;'#10'begin'#10'end;'#10 +
    'procedure Pruefe;'#10'begin'#10'end;'#10);
  Data := Default(TScenario);
  Data.NoProjects := True;
  Data.Put(FileOf('Werkzeug'), Text);
  Assert.AreEqual('Routine KlickHandler wird nirgends verwendet.'#10'Routine Pruefe wird nirgends verwendet.'#10,
    Messages(Run(Data, FileOf('Werkzeug')), UnusedDeclarationRuleId));
  Data.Config := '{"deadCode": {"keepPatterns": ["*Handler"]}}';
  Assert.AreEqual('Routine Pruefe wird nirgends verwendet.'#10,
    Messages(Run(Data, FileOf('Werkzeug')), UnusedDeclarationRuleId));
  // Name in der Formulardatei.
  Data.Put(ChangeFileExt(FileOf('Werkzeug'), '.dfm'), 'object F: TF'#10'  OnClick = Pruefe'#10'end');
  Assert.AreEqual('', Messages(Run(Data, FileOf('Werkzeug')), UnusedDeclarationRuleId));
end;

procedure TDeadCodeTests.UnusedUnitOnlyNamedByProgram;
var
  Data: TScenario;
  Found: TArray<TRuleFinding>;
begin
  Data := Group([TArray<string>.Create('Haupt', 'Dienst', ''), TArray<string>.Create('Dienst', '', ''),
    TArray<string>.Create('Waise', '', '')]);
  // Haupt deklariert Start, das Programm ruft es auf.
  Data.Put(FileOf('Haupt'), 'unit Haupt;'#10'interface'#10'uses'#10'  Dienst;'#10'procedure Start;'#10 +
    'implementation'#10'procedure Start;'#10'begin'#10'end;'#10'end.');
  Data.Put(AppFile, 'program App;'#10'uses'#10'  Haupt, Dienst, Waise;'#10'begin'#10'  Start;'#10'end.');
  Found := Run(Data, FileOf('Waise'));
  Assert.AreEqual('Unit Waise wird von keiner anderen Unit verwendet; nur App.dpr nennt sie im uses.'#10,
    Messages(Found, UnusedUnitRuleId));
  Assert.AreEqual(0, Found[0].Range.StartPos.Line);
  Assert.AreEqual(5, Found[0].Range.StartPos.Character);
  Assert.AreEqual<TRuleConfidence>(TRuleConfidence.Medium, Found[0].Confidence);
  Assert.AreEqual('', Messages(Run(Data, FileOf('Haupt')), UnusedUnitRuleId));
  Assert.AreEqual('', Messages(Run(Data, FileOf('Dienst')), UnusedUnitRuleId));
  // Ganz ohne uses-Eintrag.
  Data.Put(AppFile, 'program App;'#10'uses'#10'  Haupt, Dienst;'#10'begin'#10'  Start;'#10'end.');
  Assert.AreEqual('Unit Waise wird von keiner Unit und keinem Programm verwendet.'#10,
    Messages(Run(Data, FileOf('Waise')), UnusedUnitRuleId));
end;

procedure TDeadCodeTests.UnusedUnitExceptions;
var
  Data: TScenario;
begin
  Data := Group([TArray<string>.Create('Waise', '', '')]);
  Assert.AreNotEqual('', Messages(Run(Data, FileOf('Waise')), UnusedUnitRuleId));
  // initialization-Teil: Registrierung beim Start.
  Data.Put(FileOf('Waise'), 'unit Waise;'#10'interface'#10'implementation'#10'initialization'#10'end.');
  Assert.AreEqual('', Messages(Run(Data, FileOf('Waise')), UnusedUnitRuleId));
  // Package: Nutzer außerhalb der Gruppe; mit projectKinds gemeldet.
  Data := Group([TArray<string>.Create('Waise', '', '')]);
  Data.Projects[0].Kind := TRuleProjectKind.Package;
  Assert.AreEqual('', Messages(Run(Data, FileOf('Waise')), UnusedUnitRuleId));
  Data.Config := '{"rules": {"unused-unit": {"projectKinds": ["package"]}}}';
  Assert.AreNotEqual('', Messages(Run(Data, FileOf('Waise')), UnusedUnitRuleId));
  // Index läuft, ohne Projekte.
  Data := Group([TArray<string>.Create('Waise', '', '')]);
  Data.Incomplete := True;
  Assert.AreEqual('', Messages(Run(Data, FileOf('Waise')), UnusedUnitRuleId));
  Data.Incomplete := False;
  Data.NoProjects := True;
  Assert.AreEqual('', Messages(Run(Data, FileOf('Waise')), UnusedUnitRuleId));
end;

/// <summary>Der erste Treffer der Regel uses-cycle; Default ohne.</summary>
function CycleFinding(const AFindings: TArray<TRuleFinding>): TRuleFinding;
var
  Finding: TRuleFinding;
begin
  for Finding in AFindings do
    if SameText(Finding.RuleId, UsesCycleRuleId) then
      Exit(Finding);
  Result := Default(TRuleFinding);
end;

/// <summary>"Unit@Datei:Zeile:Zeichen" je Stelle, durch Leerzeichen getrennt.</summary>
function PlacesText(const AFinding: TRuleFinding): string;
var
  Related: TRuleRelated;
begin
  Result := '';
  for Related in AFinding.Related do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Format('%s@%s:%d:%d', [Related.Message, ExtractFileName(Related.FileName),
      Related.Range.StartPos.Line, Related.Range.StartPos.Character]);
  end;
end;

/// <summary>Titel der Korrekturen, je Zeile einer.</summary>
function FixTitles(const AFinding: TRuleFinding): string;
var
  Fix: TRuleFix;
begin
  Result := '';
  for Fix in AFinding.Fixes do
    Result := Result + Fix.Title + #10;
end;

procedure TDeadCodeTests.LiveInterfaceCycleWithPathAndPlaces;
var
  Data: TScenario;
  Found: TRuleFinding;
begin
  // Wie im Referenzprojekt: uA -> uB -> uC, dann uA im interface-uses von uC ergänzt.
  Data := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', 'A', '')]);
  Data.Live := True;
  Found := CycleFinding(Run(Data, FileOf('C')));
  Assert.AreEqual('Zirkuläre Unit-Referenz: C → A → B → C (wie F2047)', Found.Message);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, Found.Severity);
  Assert.AreEqual(3, Found.Range.StartPos.Line);
  Assert.AreEqual(2, Found.Range.StartPos.Character);
  // Jede Unit des Pfads mit ihrem uses-Eintrag: die eigene am Eintrag in B, dann jede Kante.
  Assert.AreEqual('C@B.pas:3:2 A@C.pas:3:2 B@A.pas:3:2 C@B.pas:3:2', PlacesText(Found));
  // Ungespeicherter Stand einer anderen offenen Unit: Ohne B -> C gibt es keinen Zyklus mehr.
  Data.Put(FileOf('B'), UnitText('B', '', '', ''));
  Assert.AreEqual('', Messages(Run(Data, FileOf('C')), UsesCycleRuleId));
end;

procedure TDeadCodeTests.LiveImplementationCycleOnlyWhenEnabled;
var
  Data: TScenario;
  Found: TRuleFinding;
begin
  Data := Group([TArray<string>.Create('A', '', 'B'), TArray<string>.Create('B', '', 'A')]);
  Data.Live := True;
  Assert.AreEqual('', Messages(Run(Data, FileOf('A')), UsesCycleRuleId), 'im Editor erlaubt und still');
  Data.Config := '{"diagnostics": {"usesCycleImplementation": true}}';
  Found := CycleFinding(Run(Data, FileOf('A')));
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (über implementation-uses)', Found.Message);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, Found.Severity);
  // Ein Eintrag im implementation-uses lässt sich nicht weiter verschieben: nur „Graph zeigen“.
  Assert.AreEqual('Graph zeigen (Unit-Beziehungen)'#10, FixTitles(Found));
  Assert.IsTrue(Found.Fixes[0].ShowsUnitRelations);
  // Projektweit (#64) bleibt es eine Warnung.
  Data.Live := False;
  Data.Config := '';
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Warning, CycleFinding(Run(Data, FileOf('A'))).Severity);
end;

procedure TDeadCodeTests.LiveSwitchLeavesProjectCheck;
var
  Data: TScenario;
begin
  Data := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'A', '')]);
  Data.Config := '{"diagnostics": {"usesCycleLive": false}}';
  Data.Live := True;
  Assert.AreEqual('', Messages(Run(Data, FileOf('A')), UsesCycleRuleId), 'keine Meldung beim Tippen');
  Data.Live := False;
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (wie F2047)'#10,
    Messages(Run(Data, FileOf('A')), UsesCycleRuleId),
    'die projektweite Prüfung bleibt');
end;

procedure TDeadCodeTests.SelfReferenceIsError;
var
  Data: TScenario;
  Found: TRuleFinding;
  Fixed: string;
begin
  Data := Group([TArray<string>.Create('A', 'A', '')]);
  Data.NoProjects := True;
  Found := CycleFinding(Run(Data, FileOf('A')));
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → A (wie F2092)', Found.Message);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, Found.Severity);
  Assert.AreEqual('Eintrag entfernen'#10, FixTitles(Found));
  Fixed := TChangeSignature.ApplyEdits(Data.Text(FileOf('A')), Found.Fixes[0].Edits);
  Assert.AreEqual(0, Pos('uses', Fixed), Fixed);
  // Auch mit Projekten nur eine Meldung, nicht noch eine über den Graphen.
  Data.NoProjects := False;
  Data.Live := True;
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → A (wie F2092)'#10,
    Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
end;

procedure TDeadCodeTests.SeveralCyclesAndShortestPath;
var
  Data: TScenario;
begin
  Data := Group([TArray<string>.Create('A', 'B, C', ''), TArray<string>.Create('B', 'A', ''),
    TArray<string>.Create('C', 'A', '')]);
  Data.Live := True;
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → A (wie F2047)'#10 +
    'Zirkuläre Unit-Referenz: A → C → A (wie F2047)'#10,
    Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
  // B -> D -> E -> A ist länger als B -> C -> A, obwohl D zuerst im uses steht.
  Data := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'D, C', ''),
    TArray<string>.Create('C', 'A', ''), TArray<string>.Create('D', 'E', ''), TArray<string>.Create('E', 'A', '')]);
  Data.Live := True;
  Assert.AreEqual('Zirkuläre Unit-Referenz: A → B → C → A (wie F2047)'#10,
    Messages(Run(Data, FileOf('A')), UsesCycleRuleId));
end;

procedure TDeadCodeTests.MoveFixOnlyWithoutInterfaceUse;
var
  Data: TScenario;
  Found: TRuleFinding;
  Fixed: string;
begin
  Data := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', 'A', 'B')]);
  Data.Live := True;
  Found := CycleFinding(Run(Data, FileOf('C')));
  Assert.AreEqual('In implementation-uses verschieben'#10, FixTitles(Found));
  Fixed := TChangeSignature.ApplyEdits(Data.Text(FileOf('C')), Found.Fixes[0].Edits);
  Assert.AreEqual('unit C;'#10'interface'#10#10'implementation'#10'uses'#10'  B,'#10'  A;'#10'end.', Fixed);
  // Die Korrektur beseitigt die Meldung.
  Data.Put(FileOf('C'), Fixed);
  Assert.AreEqual('', Messages(Run(Data, FileOf('C')), UsesCycleRuleId));
end;

procedure TDeadCodeTests.MoveFixSortsLikeSortUses;
var
  Data: TScenario;
  Found: TRuleFinding;
begin
  Data := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', ''),
    TArray<string>.Create('C', 'A', 'X'), TArray<string>.Create('X', '', '')]);
  Data.Live := True;
  Data.Config := '{"sortUses": true}';
  Found := CycleFinding(Run(Data, FileOf('C')));
  Assert.AreEqual('unit C;'#10'interface'#10#10'implementation'#10'uses'#10'  A,'#10'  X;'#10'end.',
    TChangeSignature.ApplyEdits(Data.Text(FileOf('C')), Found.Fixes[0].Edits));
  Assert.AreEqual(1, Integer(Length(Found.Fixes[0].Edits)), 'eine kleinste Ersetzung');
end;

procedure TDeadCodeTests.JumpsAndGraphWhenInterfaceNeedsUnit;
var
  Data: TScenario;
  Found: TRuleFinding;
begin
  Data := Group([TArray<string>.Create('A', 'B', ''), TArray<string>.Create('B', 'C', '')]);
  Data.Put(FileOf('A'), 'unit A;'#10'interface'#10'uses'#10'  B;'#10'type'#10'  TA = class end;'#10 +
    'implementation'#10'end.');
  Data.Put(FileOf('C'), 'unit C;'#10'interface'#10'uses'#10'  A;'#10'type'#10'  TC = class(TA) end;'#10 +
    'implementation'#10'end.');
  Data.Projects[0].Sources := Data.Projects[0].Sources + [FileOf('C')];
  Data.Live := True;
  Found := CycleFinding(Run(Data, FileOf('C')));
  Assert.AreEqual('Zirkuläre Unit-Referenz: C → A → B → C (wie F2047)', Found.Message);
  Assert.AreEqual('Zu TA springen (Zeile 6, braucht A im interface)'#10'Graph zeigen (Unit-Beziehungen)'#10,
    FixTitles(Found));
  Assert.IsTrue(Found.Fixes[0].HasJump);
  Assert.AreEqual(5, Found.Fixes[0].JumpTo.Line);
  Assert.AreEqual(13, Found.Fixes[0].JumpTo.Character);
  Assert.IsTrue(Found.Fixes[1].ShowsUnitRelations);
  Assert.IsTrue(Pos('Im interface-Teil gebraucht: TA (Zeile 6)', Found.Details) > 0, Found.Details);
end;

procedure TDeadCodeTests.ParserReadsUsesCycleSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := TServerSettings.Default;
  Assert.IsTrue(Settings.DiagnosticsUsesCycleLive);
  Assert.IsFalse(Settings.DiagnosticsUsesCycleImplementation);
  Settings := TConfigurationParser.Parse('{"diagnostics": {"usesCycleLive": false, "usesCycleImplementation": true}}',
    Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.DiagnosticsUsesCycleLive);
  Assert.IsTrue(Settings.DiagnosticsUsesCycleImplementation);
  Settings := TConfigurationParser.Parse('{"diagnostics": {"usesCycleLive": "nein"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsTrue(Settings.DiagnosticsUsesCycleLive);
  Issues := nil;
end;

procedure TDeadCodeTests.LiveCycleCheckOf2000Units;
const
  UnitCount = 2000;
var
  Units: TArray<TArray<string>>;
  Index: Integer;
  Data: TScenario;
  Watch: TStopwatch;
begin
  // Projektgruppe wie #501: Kette E1 -> … -> E2000 über interface, E2000 schließt den Kreis; dazu je Unit
  // ein Eintrag im implementation-uses, der keinen Zyklus bildet.
  Units := nil;
  for Index := 1 to UnitCount do
    Units := Units + [TArray<string>.Create(Format('E%d', [Index]), Format('E%d', [Index mod UnitCount + 1]),
      Format('E%d', [(Index + 1) mod UnitCount + 1]))];
  Data := Group(Units);
  Data.Live := True;
  // Beim Tippen steht der Graph schon (inkrementell, #268): gemessen wird die zweite Prüfung.
  Data.Repeats := 1;
  Watch := TStopwatch.StartNew;
  Assert.AreEqual(1, Integer(Length(Run(Data, FileOf('E1')))));
  Watch.Stop;
  System.Writeln(Format('uses-cycle live: Prüfung bei %d Units in %d ms (mit Aufbau von Index und Graph %d ms)',
    [UnitCount, LastCheckMs, Watch.ElapsedMilliseconds]));
  Assert.IsTrue(LastCheckMs < 200, 'zu langsam für die Prüfung beim Tippen');
end;

procedure TDeadCodeTests.ParserReadsDeadCode;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Settings := TConfigurationParser.Parse('{"deadCode": {"keepAttributes": ["JsonName"], ' +
    '"keepPatterns": ["*Handler", "T*Plugin"]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('JsonName', string.Join(',', Settings.DeadCodeKeepAttributes));
  Assert.AreEqual('*Handler,T*Plugin', string.Join(',', Settings.DeadCodeKeepPatterns));
  Settings := TServerSettings.Default;
  Assert.AreEqual(0, Integer(Length(Settings.DeadCodeKeepAttributes)));
  TConfigurationParser.Parse('{"deadCode": {"keepAttributes": "JsonName", "keepPatterns": [1], "x": 1}}', Issues);
  Assert.AreEqual(3, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"deadCode": [], "rules": {"uses-cycle": {"implementation": "ja"}, ' +
    '"unused-unit": {"projectKinds": "package"}}}', Issues);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Issues := nil;
end;

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

procedure TDeadCodeTests.ReferenceProjectMatchesMarkers;
const
  Rules: array[0..1] of string = (UsesCycleRuleId, UnusedUnitRuleId);
var
  Folder, MainFile, Source, Expected, Actual, Rule, Paths: string;
  Data: TScenario;
  Sources: TArray<string>;
  Lines: TArray<string>;
  Token: TPascalToken;
  Tree: TSyntaxTree;
  Finding: TRuleFinding;
  Index: Integer;
begin
  Folder := ReferenceFolder;
  if Folder = '' then
    Assert.Pass('Referenzprojekt nicht gefunden; Prüfung übersprungen');
  // Units von RefApp aus den in-Klauseln der .dpr.
  MainFile := TPath.Combine(Folder, 'RefApp.dpr');
  Data := Default(TScenario);
  Data.Put(MainFile, ReadSource(MainFile));
  Sources := [MainFile];
  Tree := TSyntaxTreeCache.Parse(Data.Text(MainFile));
  try
    for Token in Tree.Tokens do
      if (Token.Kind = TPascalTokenKind.StringLiteral) and EndsText('.pas''', Token.Text) then
      begin
        Source := TPath.Combine(Folder, StringReplace(Copy(Token.Text, 2, Length(Token.Text) - 2), '\',
          PathDelim, [rfReplaceAll]));
        Sources := Sources + [Source];
        Data.Put(Source, ReadSource(Source));
      end;
  finally
    Tree.Free;
  end;
  Data.Projects := [Project(TPath.Combine(Folder, 'RefApp.dproj'), TRuleProjectKind.Application, Sources)];
  // Erwartet: genau die markierten Zeilen je Regel, sonst nichts.
  Expected := '';
  Actual := '';
  Paths := '';
  for Source in Sources do
  begin
    Lines := Data.Text(Source).Replace(#13#10, #10).Split([#10]);
    for Rule in Rules do
      for Index := 0 to High(Lines) do
        if Lines[Index].Contains('// ERWARTET-PROJEKT: ' + Rule) then
          Expected := Expected + Format('%s:%d %s'#10, [ExtractFileName(Source), Index + 1, Rule]);
    if SameText(ExtractFileExt(Source), '.pas') then
    begin
      for Rule in Rules do
        for Finding in Run(Data, Source) do
          if SameText(Finding.RuleId, Rule) then
          begin
            Actual := Actual + Format('%s:%d %s'#10, [ExtractFileName(Source), Finding.Range.StartPos.Line + 1, Rule]);
            if Rule = UsesCycleRuleId then
              Paths := Paths + Finding.Message + #10;
          end;
    end;
  end;
  Assert.AreEqual(Expected, Actual);
  Assert.IsTrue(Pos('uses-cycle', Expected) > 0, 'Kein Zyklus im Referenzprojekt markiert');
  // Vollständiger Pfad über implementation-uses.
  Assert.IsTrue(Pos('Zirkuläre Unit-Referenz: Ref.Formulare.Detail → Ref.Formulare.Haupt → Ref.Formulare.Detail ' +
    '(über implementation-uses)', Paths) > 0, Paths);
end;

procedure TDeadCodeTests.CycleCheckOfLargeGroup;
const
  UnitCount = 400;
var
  Units: TArray<TArray<string>>;
  Index: Integer;
  Data: TScenario;
  Watch: TStopwatch;
begin
  // Kette E1 -> E2 -> … -> E400 über implementation, E400 schließt den Kreis.
  Units := nil;
  for Index := 1 to UnitCount do
    Units := Units + [TArray<string>.Create(Format('E%d', [Index]), '', Format('E%d', [Index mod UnitCount + 1]))];
  Data := Group(Units);
  Watch := TStopwatch.StartNew;
  Assert.AreEqual(1, Integer(Length(Run(Data, FileOf('E1')))));
  Watch.Stop;
  System.Writeln(Format('uses-cycle: Prüfung bei %d Units in %d ms', [UnitCount, Watch.ElapsedMilliseconds]));
  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, 'zu langsam');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeadCodeTests);

end.
