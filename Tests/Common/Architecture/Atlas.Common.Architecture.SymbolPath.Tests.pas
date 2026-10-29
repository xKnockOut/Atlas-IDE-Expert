unit Atlas.Common.Architecture.SymbolPath.Tests;

// Tests der Pfadsuche zwischen Symbolen (#1117): jede Kantenart einzeln,
// gemischter Weg über Ereignishandler, Service, Interface und Umsetzung,
// kein Weg, Mehrdeutigkeit, maxSteps, alle Wege, Abbruch, Bibliothek nicht
// als Durchgang, Sortierung bei Gleichstand, Gleichheit mit dem Weg des
// Uses-Graphen, Text und JSON, Laufzeit bei 2000 Units.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.SymbolPath;

type
  [TestFixture]
  TSymbolPathTests = class
  private
    FFiles: TDictionary<string, string>;
    FIndex: ISymbolIndex;
    FGraph: TUsesGraph;
    FLocator: TUsesLocator;
    procedure AddUnit(const AName, AText: string); overload;
    procedure AddUnit(const AName, AText: string; ALibrary: Boolean); overload;
    procedure Build;
    function Find(const ARequest: TSymbolPathRequest): TSymbolPathResult; overload;
    function Find(const AFrom, ATo: string): TSymbolPathResult; overload;
    function Request(const AFrom, ATo: string): TSymbolPathRequest;
    function Captions(const ARoute: TSymbolPathRoute): string;
    function Kinds(const ARoute: TSymbolPathRoute): string;
    procedure AddShop;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UsesEdgesFollowTheGraph;
    [Test]
    procedure ViaUsesMatchesGraphPath;
    [Test]
    procedure InheritsEdge;
    [Test]
    procedure ImplementsEdgesBothDirections;
    [Test]
    procedure HasFieldEdge;
    [Test]
    procedure ParameterAndResultEdges;
    [Test]
    procedure CallsEdge;
    [Test]
    procedure ContainsEdges;
    [Test]
    procedure MixedPathFromFormToDatabase;
    [Test]
    procedure NoPathBetweenUnrelatedUnits;
    [Test]
    procedure AmbiguousNameListsCandidates;
    [Test]
    procedure UnknownName;
    [Test]
    procedure MaxStepsLimitsSearch;
    [Test]
    procedure AllReturnsEqualRoutesInOrder;
    [Test]
    procedure AbortIsReported;
    [Test]
    procedure LibraryIsNoPassage;
    [Test]
    procedure TieBreaksByEdgeRank;
    [Test]
    procedure SameInputSameRoute;
    [Test]
    procedure ParsesVia;
    [Test]
    procedure JsonCarriesRoute;
    [Test]
    [Category('Benchmark')]
    procedure LargeGroupAnswersQuickly;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Diagnostics,
  System.JSON,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  DatenbankText =
    'unit uDatenbank;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TDatenbank = class'#10 +
    '    procedure Abfrage;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TDatenbank.Abfrage;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  RepoIntfText =
    'unit uRepoIntf;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IKundenRepo = interface'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  KundenRepoText =
    'unit uKundenRepo;'#10 +
    'interface'#10 +
    'uses uRepoIntf, uDatenbank;'#10 +
    'type'#10 +
    '  TKundenRepo = class(TInterfacedObject, IKundenRepo)'#10 +
    '    FDb: TDatenbank;'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKundenRepo.Laden;'#10 +
    'begin'#10 +
    '  FDb.Abfrage;'#10 +
    'end;'#10 +
    'end.';

  CacheRepoText =
    'unit uCacheRepo;'#10 +
    'interface'#10 +
    'uses uRepoIntf;'#10 +
    'type'#10 +
    '  TCacheRepo = class(TInterfacedObject, IKundenRepo)'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TCacheRepo.Laden;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  KundenServiceText =
    'unit uKundenService;'#10 +
    'interface'#10 +
    'uses uRepoIntf;'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  end;'#10 +
    '  TSchluessel = record'#10 +
    '  end;'#10 +
    '  TKundenService = class'#10 +
    '    FRepo: IKundenRepo;'#10 +
    '    procedure Speichern;'#10 +
    '    function Finde(AKey: TSchluessel): TKunde;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKundenService.Speichern;'#10 +
    'begin'#10 +
    '  FRepo.Laden;'#10 +
    'end;'#10 +
    'function TKundenService.Finde(AKey: TSchluessel): TKunde;'#10 +
    'begin'#10 +
    '  Result := nil;'#10 +
    'end;'#10 +
    'end.';

  KundenFormText =
    'unit uKundenForm;'#10 +
    'interface'#10 +
    'uses uKundenService;'#10 +
    'type'#10 +
    '  TKundenForm = class'#10 +
    '    procedure btnSpeichernClick(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKundenForm.btnSpeichernClick(Sender: TObject);'#10 +
    'var'#10 +
    '  Service: TKundenService;'#10 +
    'begin'#10 +
    '  Service.Speichern;'#10 +
    'end;'#10 +
    'end.';

  LoseText =
    'unit uLose;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TLose = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

function FileOf(const AName: string): string;
begin
  Result := 'C:\P\' + AName + '.pas';
end;

{ TSymbolPathTests }

procedure TSymbolPathTests.Setup;
begin
  FFiles := TDictionary<string, string>.Create;
  FIndex := TSymbolIndex.Create;
end;

procedure TSymbolPathTests.TearDown;
begin
  FLocator.Free;
  FLocator := nil;
  FGraph.Free;
  FGraph := nil;
  FIndex := nil;
  FFiles.Free;
  FFiles := nil;
end;

procedure TSymbolPathTests.AddUnit(const AName, AText: string);
begin
  AddUnit(AName, AText, False);
end;

procedure TSymbolPathTests.AddUnit(const AName, AText: string; ALibrary: Boolean);
var
  Data: TUnitIndex;
begin
  FFiles.AddOrSetValue(FileOf(AName), AText);
  Data := TIndexExtractor.ExtractText(AText, FileOf(AName), nil);
  Data.Library_ := ALibrary;
  FIndex.AddUnit(Data);
end;

procedure TSymbolPathTests.AddShop;
begin
  AddUnit('uDatenbank', DatenbankText);
  AddUnit('uRepoIntf', RepoIntfText);
  AddUnit('uKundenRepo', KundenRepoText);
  AddUnit('uCacheRepo', CacheRepoText);
  AddUnit('uKundenService', KundenServiceText);
  AddUnit('uKundenForm', KundenFormText);
  AddUnit('uLose', LoseText);
end;

procedure TSymbolPathTests.Build;
var
  Options: TUsesGraphOptions;
  Files: TDictionary<string, string>;
begin
  // Neu aufbauen (z. B. nach Find): den bisherigen Graphen und Locator freigeben.
  FreeAndNil(FLocator);
  FreeAndNil(FGraph);
  Options := TUsesGraphOptions.Default;
  Options.IncludeLibrary := True;
  FGraph := TUsesGraph.Create(FIndex.Units, Options);
  Files := FFiles;
  FLocator := TUsesLocator.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Files.TryGetValue(AFileName, AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end);
end;

function TSymbolPathTests.Request(const AFrom, ATo: string): TSymbolPathRequest;
begin
  Result := TSymbolPathRequest.Default;
  Result.From := AFrom;
  Result.To_ := ATo;
end;

function TSymbolPathTests.Find(const ARequest: TSymbolPathRequest): TSymbolPathResult;
var
  Search: TSymbolPathSearch;
  Files: TDictionary<string, string>;
begin
  if FGraph = nil then
    Build;
  Files := FFiles;
  Search := TSymbolPathSearch.Create(FIndex, FGraph, FLocator,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Files.TryGetValue(AFileName, AText);
    end, nil);
  try
    Result := Search.Find(ARequest, nil);
  finally
    Search.Free;
  end;
end;

function TSymbolPathTests.Find(const AFrom, ATo: string): TSymbolPathResult;
begin
  Result := Find(Request(AFrom, ATo));
end;

function TSymbolPathTests.Captions(const ARoute: TSymbolPathRoute): string;
var
  Node: TSymbolPathNode;
begin
  Result := '';
  for Node in ARoute.Nodes do
  begin
    if Result <> '' then
      Result := Result + ' > ';
    Result := Result + Node.Caption;
  end;
end;

function TSymbolPathTests.Kinds(const ARoute: TSymbolPathRoute): string;
var
  Step: TSymbolPathStep;
begin
  Result := '';
  for Step in ARoute.Steps do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + TSymbolPathSearch.EdgeName(Step.Kind);
  end;
end;

procedure TSymbolPathTests.UsesEdgesFollowTheGraph;
var
  Found: TSymbolPathResult;
begin
  AddShop;
  Found := Find('uKundenForm', 'uRepoIntf');
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(Found.Status));
  Assert.AreEqual('uKundenForm > uKundenService > uRepoIntf', Captions(Found.Routes[0]));
  Assert.AreEqual('uses uses', Kinds(Found.Routes[0]));
  // Fundstelle ist der uses-Eintrag (Zeile 3, Spalte 6 im Editor).
  Assert.AreEqual(FileOf('uKundenForm'), Found.Routes[0].Steps[0].FileName);
  Assert.AreEqual(2, Found.Routes[0].Steps[0].Position.Line);
  Assert.AreEqual(5, Found.Routes[0].Steps[0].Position.Character);
end;

procedure TSymbolPathTests.ViaUsesMatchesGraphPath;
var
  Search: TSymbolPathRequest;
  Found: TSymbolPathResult;
  Edges: TUsesEdges;
  Expected: string;
begin
  AddShop;
  Search := Request('uKundenForm', 'uDatenbank');
  Search.Via := [TSymbolPathEdgeKind.Uses_];
  Found := Find(Search);
  // uKundenService verwendet uDatenbank nicht: über uses allein gibt es keinen Weg, wie im Uses-Graphen.
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(Found.Status));
  Assert.AreEqual(0, Integer(Length(FGraph.Path(FGraph.IndexOf('uKundenForm'), FGraph.IndexOf('uDatenbank'),
    AllUsesSections))));
  Search := Request('uKundenRepo', 'uDatenbank');
  Search.Via := [TSymbolPathEdgeKind.Uses_];
  Found := Find(Search);
  Edges := FGraph.Path(FGraph.IndexOf('uKundenRepo'), FGraph.IndexOf('uDatenbank'), AllUsesSections);
  Expected := StringReplace(FGraph.Describe(Edges), ' → ', ' > ', [rfReplaceAll]);
  Assert.AreEqual(Expected, Captions(Found.Routes[0]));
end;

procedure TSymbolPathTests.InheritsEdge;
var
  Found: TSymbolPathResult;
begin
  AddUnit('uBasis', 'unit uBasis;'#10'interface'#10'type'#10'  TBasis = class'#10'  end;'#10 +
    '  TAbgeleitet = class(TBasis)'#10'  end;'#10'implementation'#10'end.');
  Found := Find('TAbgeleitet', 'TBasis');
  Assert.AreEqual('TAbgeleitet > TBasis', Captions(Found.Routes[0]));
  Assert.AreEqual('inherits', Kinds(Found.Routes[0]));
  Assert.AreEqual(5, Found.Routes[0].Steps[0].Position.Line);
  // Gegen die Vererbung gibt es keinen Weg.
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(Find('TBasis', 'TAbgeleitet').Status));
end;

procedure TSymbolPathTests.ImplementsEdgesBothDirections;
var
  Found: TSymbolPathResult;
begin
  AddShop;
  Found := Find('TKundenRepo', 'IKundenRepo');
  Assert.AreEqual('implements', Kinds(Found.Routes[0]));
  Assert.IsFalse(Found.Routes[0].Steps[0].Reverse);
  Assert.IsFalse(Found.Routes[0].Steps[0].Inferred);
  Assert.AreEqual('setzt um', TSymbolPathSearch.StepCaption(Found.Routes[0].Steps[0], Found.Routes[0].Nodes[0]));
  // Interface → Umsetzung: zwei Klassen setzen IKundenRepo um, die Kante ist erschlossen.
  Found := Find('IKundenRepo', 'TCacheRepo');
  Assert.AreEqual('IKundenRepo > TCacheRepo', Captions(Found.Routes[0]));
  Assert.IsTrue(Found.Routes[0].Steps[0].Reverse);
  Assert.IsTrue(Found.Routes[0].Steps[0].Inferred);
  Assert.AreEqual('umgesetzt von', TSymbolPathSearch.StepCaption(Found.Routes[0].Steps[0],
    Found.Routes[0].Nodes[0]));
  // Je Methode: Interface-Methode → Methode der Klasse.
  Found := Find('IKundenRepo.Laden', 'TKundenRepo.Laden');
  Assert.AreEqual('implements', Kinds(Found.Routes[0]));
  Assert.IsTrue(Found.Routes[0].Steps[0].Inferred);
  Found := Find('TKundenRepo.Laden', 'IKundenRepo.Laden');
  Assert.AreEqual('implements', Kinds(Found.Routes[0]));
  Assert.IsFalse(Found.Routes[0].Steps[0].Inferred);
end;

procedure TSymbolPathTests.HasFieldEdge;
var
  Found: TSymbolPathResult;
begin
  AddShop;
  Found := Find('TKundenRepo', 'TDatenbank');
  Assert.AreEqual('TKundenRepo > TDatenbank', Captions(Found.Routes[0]));
  Assert.AreEqual('hasField', Kinds(Found.Routes[0]));
  // Fundstelle ist das Feld FDb.
  Assert.AreEqual(5, Found.Routes[0].Steps[0].Position.Line);
  Assert.AreEqual('hat Feld', TSymbolPathSearch.StepCaption(Found.Routes[0].Steps[0], Found.Routes[0].Nodes[0]));
  // Vom Feld selbst zum Typ.
  Found := Find('TKundenRepo.FDb', 'TDatenbank');
  Assert.AreEqual('TKundenRepo.FDb: TDatenbank > TDatenbank', Captions(Found.Routes[0]));
  Assert.AreEqual('vom Typ', TSymbolPathSearch.StepCaption(Found.Routes[0].Steps[0], Found.Routes[0].Nodes[0]));
end;

procedure TSymbolPathTests.ParameterAndResultEdges;
var
  Found: TSymbolPathResult;
begin
  AddShop;
  Found := Find('TKundenService.Finde', 'TSchluessel');
  Assert.AreEqual('parameter', Kinds(Found.Routes[0]));
  Found := Find('TKundenService.Finde', 'TKunde');
  Assert.AreEqual('result', Kinds(Found.Routes[0]));
  Assert.AreEqual('Ergebnis vom Typ', TSymbolPathSearch.StepCaption(Found.Routes[0].Steps[0],
    Found.Routes[0].Nodes[0]));
end;

procedure TSymbolPathTests.CallsEdge;
var
  Found: TSymbolPathResult;
  Search: TSymbolPathRequest;
begin
  AddShop;
  Found := Find('TKundenRepo.Laden', 'TDatenbank.Abfrage');
  Assert.AreEqual('TKundenRepo.Laden > TDatenbank.Abfrage', Captions(Found.Routes[0]));
  Assert.AreEqual('calls', Kinds(Found.Routes[0]));
  // Fundstelle ist die Aufrufstelle im Rumpf.
  Assert.AreEqual(FileOf('uKundenRepo'), Found.Routes[0].Steps[0].FileName);
  Assert.AreEqual(11, Found.Routes[0].Steps[0].Position.Line);
  // Ohne calls in via kein Weg.
  Search := Request('TKundenRepo.Laden', 'TDatenbank.Abfrage');
  Search.Via := AllSymbolPathEdges - [TSymbolPathEdgeKind.Calls];
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(Find(Search).Status));
  // Rückwärts über den Verwendungsindex: Wer ruft Abfrage auf?
  Found := Find('uKundenRepo', 'TDatenbank.Abfrage');
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(Found.Status));
end;

procedure TSymbolPathTests.ContainsEdges;
var
  Found: TSymbolPathResult;
begin
  AddShop;
  Found := Find('uDatenbank', 'TDatenbank');
  Assert.AreEqual('contains', Kinds(Found.Routes[0]));
  Found := Find('TDatenbank', 'TDatenbank.Abfrage');
  Assert.AreEqual('contains', Kinds(Found.Routes[0]));
  Assert.AreEqual('enthält', TSymbolPathSearch.StepCaption(Found.Routes[0].Steps[0], Found.Routes[0].Nodes[0]));
end;

procedure TSymbolPathTests.MixedPathFromFormToDatabase;
var
  Found: TSymbolPathResult;
  Text: string;
begin
  AddShop;
  Found := Find('TKundenForm', 'TDatenbank');
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(Found.Status));
  Assert.AreEqual('TKundenForm > TKundenForm.btnSpeichernClick > TKundenService.Speichern > IKundenRepo.Laden > ' +
    'TKundenRepo.Laden > TDatenbank.Abfrage', Captions(Found.Routes[0]));
  Assert.AreEqual('contains calls calls implements calls', Kinds(Found.Routes[0]));
  // Zwei Umsetzungen von IKundenRepo: der Schritt zur Umsetzung ist erschlossen.
  Assert.IsTrue(Found.Routes[0].Steps[3].Inferred);
  // Zeilen: Aufruf in btnSpeichernClick (Zeile 13), FRepo.Laden (Zeile 17), FDb.Abfrage (Zeile 12).
  Assert.AreEqual(12, Found.Routes[0].Steps[1].Position.Line);
  Assert.AreEqual(16, Found.Routes[0].Steps[2].Position.Line);
  Assert.AreEqual(11, Found.Routes[0].Steps[4].Position.Line);
  Text := TSymbolPathSearch.Text(Found, 'C:\P');
  Assert.IsTrue(StartsStr('Kürzester Weg (5 Schritte', Text), Text);
  Assert.IsTrue(ContainsStr(Text, 'umgesetzt von     [erschlossen] uKundenRepo.pas:7'), Text);
  Assert.IsTrue(ContainsStr(Text, 'ruft auf          uKundenForm.pas:13'), Text);
  Assert.IsTrue(ContainsStr(Text, 'gehört zu TDatenbank'), Text);
  Assert.IsTrue(ContainsStr(Text, 'Durchsucht: '), Text);
end;

procedure TSymbolPathTests.NoPathBetweenUnrelatedUnits;
var
  Found: TSymbolPathResult;
begin
  AddShop;
  Found := Find('uLose', 'uDatenbank');
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(Found.Status));
  Assert.IsTrue(StartsStr('Kein Weg in höchstens 8 Schritten.', TSymbolPathSearch.Text(Found, '')));
  Assert.AreEqual(0, Integer(Length(Found.Routes)));
end;

procedure TSymbolPathTests.AmbiguousNameListsCandidates;
var
  Found: TSymbolPathResult;
  Text: string;
begin
  AddShop;
  Found := Find('Laden', 'TDatenbank');
  Assert.AreEqual(Ord(TSymbolPathStatus.Ambiguous), Ord(Found.Status));
  Assert.AreEqual('Laden', Found.Subject);
  Assert.AreEqual(3, Integer(Length(Found.Candidates)));
  Assert.AreEqual(0, Integer(Length(Found.Routes)));
  Text := TSymbolPathSearch.Text(Found, 'C:\P');
  Assert.IsTrue(StartsStr('"Laden" ist mehrdeutig (3 Treffer):', Text), Text);
  Assert.IsTrue(ContainsStr(Text, 'TKundenRepo.Laden  uKundenRepo.pas:7'), Text);
  // Qualifiziert ist der Name eindeutig.
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(Find('TKundenRepo.Laden', 'TDatenbank').Status));
end;

procedure TSymbolPathTests.UnknownName;
var
  Found: TSymbolPathResult;
begin
  AddShop;
  Found := Find('TGibtEsNicht', 'TDatenbank');
  Assert.AreEqual(Ord(TSymbolPathStatus.NotFound), Ord(Found.Status));
  Assert.AreEqual('Kein Symbol und keine Unit "TGibtEsNicht" im Index.', TSymbolPathSearch.Text(Found, ''));
end;

procedure TSymbolPathTests.MaxStepsLimitsSearch;
var
  Search: TSymbolPathRequest;
  Found: TSymbolPathResult;
begin
  AddShop;
  Search := Request('TKundenForm', 'TDatenbank');
  Search.MaxSteps := 4;
  Found := Find(Search);
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(Found.Status));
  Assert.IsTrue(StartsStr('Kein Weg in höchstens 4 Schritten.', TSymbolPathSearch.Text(Found, '')));
  Search.MaxSteps := 5;
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(Find(Search).Status));
  // Höchstens 16.
  Search.MaxSteps := 99;
  Assert.AreEqual(TSymbolPathRequest.MaxStepsLimit, Find(Search).MaxSteps);
end;

procedure TSymbolPathTests.AllReturnsEqualRoutesInOrder;
var
  Search: TSymbolPathRequest;
  Found: TSymbolPathResult;
begin
  AddUnit('uZiel', 'unit uZiel;'#10'interface'#10'implementation'#10'end.');
  AddUnit('uB', 'unit uB;'#10'interface'#10'uses uZiel;'#10'implementation'#10'end.');
  AddUnit('uA', 'unit uA;'#10'interface'#10'uses uZiel;'#10'implementation'#10'end.');
  AddUnit('uStart', 'unit uStart;'#10'interface'#10'uses uB, uA;'#10'implementation'#10'end.');
  Search := Request('uStart', 'uZiel');
  Found := Find(Search);
  Assert.AreEqual(1, Integer(Length(Found.Routes)));
  Assert.AreEqual(2, Found.RouteCount);
  // Reihenfolge im uses wie TUsesGraph.Path: uB steht vor uA.
  Assert.AreEqual('uStart > uB > uZiel', Captions(Found.Routes[0]));
  Search.All := True;
  Found := Find(Search);
  Assert.AreEqual(2, Integer(Length(Found.Routes)));
  Assert.AreEqual('uStart > uA > uZiel', Captions(Found.Routes[1]));
  Assert.IsTrue(ContainsStr(TSymbolPathSearch.Text(Found, ''), 'Weg 2:'));
end;

procedure TSymbolPathTests.AbortIsReported;
var
  Search: TSymbolPathRequest;
  Found: TSymbolPathResult;
  Engine: TSymbolPathSearch;
begin
  AddShop;
  Search := Request('TKundenForm', 'TDatenbank');
  Search.MaxNodes := 3;
  Found := Find(Search);
  Assert.AreEqual(Ord(TSymbolPathStatus.Aborted), Ord(Found.Status));
  Assert.AreEqual('Knotengrenze', Found.AbortReason);
  Assert.IsTrue(StartsStr('Kein Weg gefunden in ', TSymbolPathSearch.Text(Found, '')));
  Assert.IsTrue(ContainsStr(TSymbolPathSearch.Text(Found, ''), 'abgebrochen'));
  // Abbruch von außen (MCP-Cancel).
  Build;
  Engine := TSymbolPathSearch.Create(FIndex, FGraph, FLocator, nil, nil);
  try
    Found := Engine.Find(Request('uKundenForm', 'uDatenbank'),
      function: Boolean
      begin
        Result := True;
      end);
  finally
    Engine.Free;
  end;
  Assert.AreEqual(Ord(TSymbolPathStatus.Aborted), Ord(Found.Status));
  Assert.AreEqual('abgebrochen', Found.AbortReason);
end;

procedure TSymbolPathTests.LibraryIsNoPassage;
var
  Search: TSymbolPathRequest;
  Found: TSymbolPathResult;
begin
  AddUnit('uZiel', 'unit uZiel;'#10'interface'#10'type'#10'  TZiel = class'#10'  end;'#10'implementation'#10'end.');
  AddUnit('uLib', 'unit uLib;'#10'interface'#10'uses uZiel;'#10'type'#10'  TLibBasis = class'#10 +
    '    FZiel: TZiel;'#10'  end;'#10'implementation'#10'end.', True);
  AddUnit('uApp', 'unit uApp;'#10'interface'#10'uses uLib;'#10'type'#10'  TApp = class(TLibBasis)'#10 +
    '  end;'#10'implementation'#10'end.');
  // Bibliothek als Ziel ja …
  Found := Find('TApp', 'TLibBasis');
  Assert.AreEqual('inherits', Kinds(Found.Routes[0]));
  // … als Durchgang nein.
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(Find('TApp', 'TZiel').Status));
  Search := Request('TApp', 'TZiel');
  Search.ThroughLibrary := True;
  Found := Find(Search);
  Assert.AreEqual('TApp > TLibBasis > TZiel', Captions(Found.Routes[0]));
end;

procedure TSymbolPathTests.TieBreaksByEdgeRank;
var
  Search: TSymbolPathRequest;
  Found: TSymbolPathResult;
begin
  AddUnit('uGleich', 'unit uGleich;'#10'interface'#10'type'#10'  TY = class'#10'  end;'#10 +
    '  TX = class(TY)'#10'    FY: TY;'#10'  end;'#10'implementation'#10'end.');
  Search := Request('TX', 'TY');
  Search.All := True;
  Found := Find(Search);
  Assert.AreEqual(2, Integer(Length(Found.Routes)));
  // inherits steht in der Rangfolge vor hasField.
  Assert.AreEqual('inherits', Kinds(Found.Routes[0]));
  Assert.AreEqual('hasField', Kinds(Found.Routes[1]));
end;

procedure TSymbolPathTests.SameInputSameRoute;
var
  First: string;
  Run: Integer;
  Found: TSymbolPathResult;
begin
  AddShop;
  First := Captions(Find('TKundenForm', 'TDatenbank').Routes[0]);
  for Run := 1 to 3 do
  begin
    FreeAndNil(FLocator);
    FreeAndNil(FGraph);
    Found := Find('TKundenForm', 'TDatenbank');
    Assert.AreEqual(First, Captions(Found.Routes[0]));
  end;
end;

procedure TSymbolPathTests.ParsesVia;
var
  Kind, Parsed: TSymbolPathEdgeKind;
  Library_: Boolean;
begin
  Assert.IsTrue(TSymbolPathSearch.TryParseEdge('hasField', Kind, Library_));
  Assert.AreEqual(Ord(TSymbolPathEdgeKind.HasField), Ord(Kind));
  Assert.IsFalse(Library_);
  Assert.IsTrue(TSymbolPathSearch.TryParseEdge('library', Kind, Library_));
  Assert.IsTrue(Library_);
  Assert.IsFalse(TSymbolPathSearch.TryParseEdge('foo', Kind, Library_));
  for Kind := Low(TSymbolPathEdgeKind) to High(TSymbolPathEdgeKind) do
  begin
    Assert.IsTrue(TSymbolPathSearch.TryParseEdge(TSymbolPathSearch.EdgeName(Kind), Parsed, Library_));
    Assert.AreEqual(Ord(Kind), Ord(Parsed));
  end;
end;

procedure TSymbolPathTests.JsonCarriesRoute;
var
  Found: TSymbolPathResult;
  Json: TJSONObject;
  Route: TJSONObject;
begin
  AddShop;
  Found := Find('TKundenRepo', 'TDatenbank');
  Json := TSymbolPathSearch.ToJson(Found);
  try
    Assert.AreEqual('found', Json.GetValue('status').Value);
    Route := (Json.GetValue('routes') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual(2, (Route.GetValue('nodes') as TJSONArray).Count);
    Assert.AreEqual('hasField', ((Route.GetValue('steps') as TJSONArray).Items[0] as TJSONObject)
      .GetValue('kind').Value);
    Assert.AreEqual(5, (((Route.GetValue('steps') as TJSONArray).Items[0] as TJSONObject)
      .GetValue('line') as TJSONNumber).AsInt);
    Assert.AreEqual('TDatenbank', (Json.GetValue('target') as TJSONObject).GetValue('caption').Value);
  finally
    Json.Free;
  end;
end;

procedure TSymbolPathTests.LargeGroupAnswersQuickly;
var
  Index, Layer: Integer;
  Name, UsesText: string;
  Watch: TStopwatch;
  Found: TSymbolPathResult;
begin
  // 2000 Units in 250 Schichten zu 8; jede verwendet die 8 der nächsten Schicht und deklariert einen Typ mit
  // Feld auf einen Typ der nächsten Schicht.
  for Index := 0 to 1999 do
  begin
    Layer := Index div 8;
    Name := Format('U%.4d', [Index]);
    UsesText := '';
    if Layer < 249 then
      UsesText := Format('uses U%.4d, U%.4d, U%.4d, U%.4d, U%.4d, U%.4d, U%.4d, U%.4d;'#10,
        [(Layer + 1) * 8, (Layer + 1) * 8 + 1, (Layer + 1) * 8 + 2, (Layer + 1) * 8 + 3, (Layer + 1) * 8 + 4,
        (Layer + 1) * 8 + 5, (Layer + 1) * 8 + 6, (Layer + 1) * 8 + 7]);
    AddUnit(Name, 'unit ' + Name + ';'#10'interface'#10 + UsesText + 'type'#10'  T' + Name + ' = class'#10 +
      IfThen(Layer < 249, Format('    FNext: TU%.4d;'#10, [(Layer + 1) * 8 + Index mod 8]), '') +
      '    procedure Arbeite;'#10'  end;'#10'implementation'#10'procedure T' + Name + '.Arbeite;'#10'begin'#10 +
      'end;'#10'end.');
  end;
  Build;
  Watch := TStopwatch.StartNew;
  Found := Find('U0000', Format('U%.4d', [8 * 8 + 3]));
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(Found.Status));
  Assert.AreEqual(8, Integer(Length(Found.Routes[0].Steps)));
  Found := Find('TU0000', Format('TU%.4d', [8 * 8]));
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(Found.Status));
  Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, Format('%d ms', [Watch.ElapsedMilliseconds]));
end;

initialization
  TDUnitX.RegisterTestFixture(TSymbolPathTests);

end.
