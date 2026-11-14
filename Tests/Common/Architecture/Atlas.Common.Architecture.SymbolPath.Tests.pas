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
  cDatenbankText =
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

  cRepoIntfText =
    'unit uRepoIntf;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IKundenRepo = interface'#10 +
    '    procedure Laden;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cKundenRepoText =
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

  cCacheRepoText =
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

  cKundenServiceText =
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

  cKundenFormText =
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

  cLoseText =
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
  mData: TUnitIndex;
begin
  FFiles.AddOrSetValue(FileOf(AName), AText);
  mData := TIndexExtractor.ExtractText(AText, FileOf(AName), nil);
  mData.Library_ := ALibrary;
  FIndex.AddUnit(mData);
end;

procedure TSymbolPathTests.AddShop;
begin
  AddUnit('uDatenbank', cDatenbankText);
  AddUnit('uRepoIntf', cRepoIntfText);
  AddUnit('uKundenRepo', cKundenRepoText);
  AddUnit('uCacheRepo', cCacheRepoText);
  AddUnit('uKundenService', cKundenServiceText);
  AddUnit('uKundenForm', cKundenFormText);
  AddUnit('uLose', cLoseText);
end;

procedure TSymbolPathTests.Build;
var
  mOptions: TUsesGraphOptions;
  mFiles: TDictionary<string, string>;
begin
  // Neu aufbauen (z. B. nach Find): den bisherigen Graphen und Locator freigeben.
  FreeAndNil(FLocator);
  FreeAndNil(FGraph);
  mOptions := TUsesGraphOptions.Default;
  mOptions.IncludeLibrary := True;
  FGraph := TUsesGraph.Create(FIndex.Units, mOptions);
  mFiles := FFiles;
  FLocator := TUsesLocator.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mFiles.TryGetValue(AFileName, AText);
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
  mSearch: TSymbolPathSearch;
  mFiles: TDictionary<string, string>;
begin
  if FGraph = nil then
  begin
    Build;
  end;
  mFiles := FFiles;
  mSearch := TSymbolPathSearch.Create(FIndex, FGraph, FLocator,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mFiles.TryGetValue(AFileName, AText);
    end, nil);
  try
    Result := mSearch.Find(ARequest, nil);
  finally
    mSearch.Free;
  end;
end;

function TSymbolPathTests.Find(const AFrom, ATo: string): TSymbolPathResult;
begin
  Result := Find(Request(AFrom, ATo));
end;

function TSymbolPathTests.Captions(const ARoute: TSymbolPathRoute): string;
var
  mNode: TSymbolPathNode;
begin
  Result := '';
  for mNode in ARoute.Nodes do
  begin
    if Result <> '' then
    begin
      Result := Result + ' > ';
    end;
    Result := Result + mNode.Caption;
  end;
end;

function TSymbolPathTests.Kinds(const ARoute: TSymbolPathRoute): string;
var
  mStep: TSymbolPathStep;
begin
  Result := '';
  for mStep in ARoute.Steps do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + TSymbolPathSearch.EdgeName(mStep.Kind);
  end;
end;

procedure TSymbolPathTests.UsesEdgesFollowTheGraph;
var
  mFound: TSymbolPathResult;
begin
  AddShop;
  mFound := Find('uKundenForm', 'uRepoIntf');
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(mFound.Status));
  Assert.AreEqual('uKundenForm > uKundenService > uRepoIntf', Captions(mFound.Routes[0]));
  Assert.AreEqual('uses uses', Kinds(mFound.Routes[0]));
  // Fundstelle ist der uses-Eintrag (Zeile 3, Spalte 6 im Editor).
  Assert.AreEqual(FileOf('uKundenForm'), mFound.Routes[0].Steps[0].FileName);
  Assert.AreEqual(2, mFound.Routes[0].Steps[0].Position.Line);
  Assert.AreEqual(5, mFound.Routes[0].Steps[0].Position.Character);
end;

procedure TSymbolPathTests.ViaUsesMatchesGraphPath;
var
  mSearch: TSymbolPathRequest;
  mFound: TSymbolPathResult;
  mEdges: TUsesEdges;
  mExpected: string;
begin
  AddShop;
  mSearch := Request('uKundenForm', 'uDatenbank');
  mSearch.Via := [TSymbolPathEdgeKind.Uses_];
  mFound := Find(mSearch);
  // uKundenService verwendet uDatenbank nicht: über uses allein gibt es keinen Weg, wie im Uses-Graphen.
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(mFound.Status));
  Assert.AreEqual(0, Integer(Length(FGraph.Path(FGraph.IndexOf('uKundenForm'), FGraph.IndexOf('uDatenbank'),
    cAllUsesSections))));
  mSearch := Request('uKundenRepo', 'uDatenbank');
  mSearch.Via := [TSymbolPathEdgeKind.Uses_];
  mFound := Find(mSearch);
  mEdges := FGraph.Path(FGraph.IndexOf('uKundenRepo'), FGraph.IndexOf('uDatenbank'), cAllUsesSections);
  mExpected := StringReplace(FGraph.Describe(mEdges), ' → ', ' > ', [rfReplaceAll]);
  Assert.AreEqual(mExpected, Captions(mFound.Routes[0]));
end;

procedure TSymbolPathTests.InheritsEdge;
var
  mFound: TSymbolPathResult;
begin
  AddUnit('uBasis', 'unit uBasis;'#10'interface'#10'type'#10'  TBasis = class'#10'  end;'#10 +
    '  TAbgeleitet = class(TBasis)'#10'  end;'#10'implementation'#10'end.');
  mFound := Find('TAbgeleitet', 'TBasis');
  Assert.AreEqual('TAbgeleitet > TBasis', Captions(mFound.Routes[0]));
  Assert.AreEqual('inherits', Kinds(mFound.Routes[0]));
  Assert.AreEqual(5, mFound.Routes[0].Steps[0].Position.Line);
  // Gegen die Vererbung gibt es keinen Weg.
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(Find('TBasis', 'TAbgeleitet').Status));
end;

procedure TSymbolPathTests.ImplementsEdgesBothDirections;
var
  mFound: TSymbolPathResult;
begin
  AddShop;
  mFound := Find('TKundenRepo', 'IKundenRepo');
  Assert.AreEqual('implements', Kinds(mFound.Routes[0]));
  Assert.IsFalse(mFound.Routes[0].Steps[0].Reverse);
  Assert.IsFalse(mFound.Routes[0].Steps[0].Inferred);
  Assert.AreEqual('setzt um', TSymbolPathSearch.StepCaption(mFound.Routes[0].Steps[0], mFound.Routes[0].Nodes[0]));
  // Interface → Umsetzung: zwei Klassen setzen IKundenRepo um, die Kante ist erschlossen.
  mFound := Find('IKundenRepo', 'TCacheRepo');
  Assert.AreEqual('IKundenRepo > TCacheRepo', Captions(mFound.Routes[0]));
  Assert.IsTrue(mFound.Routes[0].Steps[0].Reverse);
  Assert.IsTrue(mFound.Routes[0].Steps[0].Inferred);
  Assert.AreEqual('umgesetzt von', TSymbolPathSearch.StepCaption(mFound.Routes[0].Steps[0],
    mFound.Routes[0].Nodes[0]));
  // Je Methode: Interface-Methode → Methode der Klasse.
  mFound := Find('IKundenRepo.Laden', 'TKundenRepo.Laden');
  Assert.AreEqual('implements', Kinds(mFound.Routes[0]));
  Assert.IsTrue(mFound.Routes[0].Steps[0].Inferred);
  mFound := Find('TKundenRepo.Laden', 'IKundenRepo.Laden');
  Assert.AreEqual('implements', Kinds(mFound.Routes[0]));
  Assert.IsFalse(mFound.Routes[0].Steps[0].Inferred);
end;

procedure TSymbolPathTests.HasFieldEdge;
var
  mFound: TSymbolPathResult;
begin
  AddShop;
  mFound := Find('TKundenRepo', 'TDatenbank');
  Assert.AreEqual('TKundenRepo > TDatenbank', Captions(mFound.Routes[0]));
  Assert.AreEqual('hasField', Kinds(mFound.Routes[0]));
  // Fundstelle ist das Feld FDb.
  Assert.AreEqual(5, mFound.Routes[0].Steps[0].Position.Line);
  Assert.AreEqual('hat Feld', TSymbolPathSearch.StepCaption(mFound.Routes[0].Steps[0], mFound.Routes[0].Nodes[0]));
  // Vom Feld selbst zum Typ.
  mFound := Find('TKundenRepo.FDb', 'TDatenbank');
  Assert.AreEqual('TKundenRepo.FDb: TDatenbank > TDatenbank', Captions(mFound.Routes[0]));
  Assert.AreEqual('vom Typ', TSymbolPathSearch.StepCaption(mFound.Routes[0].Steps[0], mFound.Routes[0].Nodes[0]));
end;

procedure TSymbolPathTests.ParameterAndResultEdges;
var
  mFound: TSymbolPathResult;
begin
  AddShop;
  mFound := Find('TKundenService.Finde', 'TSchluessel');
  Assert.AreEqual('parameter', Kinds(mFound.Routes[0]));
  mFound := Find('TKundenService.Finde', 'TKunde');
  Assert.AreEqual('result', Kinds(mFound.Routes[0]));
  Assert.AreEqual('Ergebnis vom Typ', TSymbolPathSearch.StepCaption(mFound.Routes[0].Steps[0],
    mFound.Routes[0].Nodes[0]));
end;

procedure TSymbolPathTests.CallsEdge;
var
  mFound: TSymbolPathResult;
  mSearch: TSymbolPathRequest;
begin
  AddShop;
  mFound := Find('TKundenRepo.Laden', 'TDatenbank.Abfrage');
  Assert.AreEqual('TKundenRepo.Laden > TDatenbank.Abfrage', Captions(mFound.Routes[0]));
  Assert.AreEqual('calls', Kinds(mFound.Routes[0]));
  // Fundstelle ist die Aufrufstelle im Rumpf.
  Assert.AreEqual(FileOf('uKundenRepo'), mFound.Routes[0].Steps[0].FileName);
  Assert.AreEqual(11, mFound.Routes[0].Steps[0].Position.Line);
  // Ohne calls in via kein Weg.
  mSearch := Request('TKundenRepo.Laden', 'TDatenbank.Abfrage');
  mSearch.Via := cAllSymbolPathEdges - [TSymbolPathEdgeKind.Calls];
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(Find(mSearch).Status));
  // Rückwärts über den Verwendungsindex: Wer ruft Abfrage auf?
  mFound := Find('uKundenRepo', 'TDatenbank.Abfrage');
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(mFound.Status));
end;

procedure TSymbolPathTests.ContainsEdges;
var
  mFound: TSymbolPathResult;
begin
  AddShop;
  mFound := Find('uDatenbank', 'TDatenbank');
  Assert.AreEqual('contains', Kinds(mFound.Routes[0]));
  mFound := Find('TDatenbank', 'TDatenbank.Abfrage');
  Assert.AreEqual('contains', Kinds(mFound.Routes[0]));
  Assert.AreEqual('enthält', TSymbolPathSearch.StepCaption(mFound.Routes[0].Steps[0], mFound.Routes[0].Nodes[0]));
end;

procedure TSymbolPathTests.MixedPathFromFormToDatabase;
var
  mFound: TSymbolPathResult;
  mText: string;
begin
  AddShop;
  mFound := Find('TKundenForm', 'TDatenbank');
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(mFound.Status));
  Assert.AreEqual('TKundenForm > TKundenForm.btnSpeichernClick > TKundenService.Speichern > IKundenRepo.Laden > ' +
    'TKundenRepo.Laden > TDatenbank.Abfrage', Captions(mFound.Routes[0]));
  Assert.AreEqual('contains calls calls implements calls', Kinds(mFound.Routes[0]));
  // Zwei Umsetzungen von IKundenRepo: der Schritt zur Umsetzung ist erschlossen.
  Assert.IsTrue(mFound.Routes[0].Steps[3].Inferred);
  // Zeilen: Aufruf in btnSpeichernClick (Zeile 13), FRepo.Laden (Zeile 17), FDb.Abfrage (Zeile 12).
  Assert.AreEqual(12, mFound.Routes[0].Steps[1].Position.Line);
  Assert.AreEqual(16, mFound.Routes[0].Steps[2].Position.Line);
  Assert.AreEqual(11, mFound.Routes[0].Steps[4].Position.Line);
  mText := TSymbolPathSearch.Text(mFound, 'C:\P');
  Assert.IsTrue(StartsStr('Kürzester Weg (5 Schritte', mText), mText);
  Assert.IsTrue(ContainsStr(mText, 'umgesetzt von     [erschlossen] uKundenRepo.pas:7'), mText);
  Assert.IsTrue(ContainsStr(mText, 'ruft auf          uKundenForm.pas:13'), mText);
  Assert.IsTrue(ContainsStr(mText, 'gehört zu TDatenbank'), mText);
  Assert.IsTrue(ContainsStr(mText, 'Durchsucht: '), mText);
end;

procedure TSymbolPathTests.NoPathBetweenUnrelatedUnits;
var
  mFound: TSymbolPathResult;
begin
  AddShop;
  mFound := Find('uLose', 'uDatenbank');
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(mFound.Status));
  Assert.IsTrue(StartsStr('Kein Weg in höchstens 8 Schritten.', TSymbolPathSearch.Text(mFound, '')));
  Assert.AreEqual(0, Integer(Length(mFound.Routes)));
end;

procedure TSymbolPathTests.AmbiguousNameListsCandidates;
var
  mFound: TSymbolPathResult;
  mText: string;
begin
  AddShop;
  mFound := Find('Laden', 'TDatenbank');
  Assert.AreEqual(Ord(TSymbolPathStatus.Ambiguous), Ord(mFound.Status));
  Assert.AreEqual('Laden', mFound.Subject);
  Assert.AreEqual(3, Integer(Length(mFound.Candidates)));
  Assert.AreEqual(0, Integer(Length(mFound.Routes)));
  mText := TSymbolPathSearch.Text(mFound, 'C:\P');
  Assert.IsTrue(StartsStr('"Laden" ist mehrdeutig (3 Treffer):', mText), mText);
  Assert.IsTrue(ContainsStr(mText, 'TKundenRepo.Laden  uKundenRepo.pas:7'), mText);
  // Qualifiziert ist der Name eindeutig.
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(Find('TKundenRepo.Laden', 'TDatenbank').Status));
end;

procedure TSymbolPathTests.UnknownName;
var
  mFound: TSymbolPathResult;
begin
  AddShop;
  mFound := Find('TGibtEsNicht', 'TDatenbank');
  Assert.AreEqual(Ord(TSymbolPathStatus.NotFound), Ord(mFound.Status));
  Assert.AreEqual('Kein Symbol und keine Unit "TGibtEsNicht" im Index.', TSymbolPathSearch.Text(mFound, ''));
end;

procedure TSymbolPathTests.MaxStepsLimitsSearch;
var
  mSearch: TSymbolPathRequest;
  mFound: TSymbolPathResult;
begin
  AddShop;
  mSearch := Request('TKundenForm', 'TDatenbank');
  mSearch.MaxSteps := 4;
  mFound := Find(mSearch);
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(mFound.Status));
  Assert.IsTrue(StartsStr('Kein Weg in höchstens 4 Schritten.', TSymbolPathSearch.Text(mFound, '')));
  mSearch.MaxSteps := 5;
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(Find(mSearch).Status));
  // Höchstens 16.
  mSearch.MaxSteps := 99;
  Assert.AreEqual(TSymbolPathRequest.cMaxStepsLimit, Find(mSearch).MaxSteps);
end;

procedure TSymbolPathTests.AllReturnsEqualRoutesInOrder;
var
  mSearch: TSymbolPathRequest;
  mFound: TSymbolPathResult;
begin
  AddUnit('uZiel', 'unit uZiel;'#10'interface'#10'implementation'#10'end.');
  AddUnit('uB', 'unit uB;'#10'interface'#10'uses uZiel;'#10'implementation'#10'end.');
  AddUnit('uA', 'unit uA;'#10'interface'#10'uses uZiel;'#10'implementation'#10'end.');
  AddUnit('uStart', 'unit uStart;'#10'interface'#10'uses uB, uA;'#10'implementation'#10'end.');
  mSearch := Request('uStart', 'uZiel');
  mFound := Find(mSearch);
  Assert.AreEqual(1, Integer(Length(mFound.Routes)));
  Assert.AreEqual(2, mFound.RouteCount);
  // Reihenfolge im uses wie TUsesGraph.Path: uB steht vor uA.
  Assert.AreEqual('uStart > uB > uZiel', Captions(mFound.Routes[0]));
  mSearch.All := True;
  mFound := Find(mSearch);
  Assert.AreEqual(2, Integer(Length(mFound.Routes)));
  Assert.AreEqual('uStart > uA > uZiel', Captions(mFound.Routes[1]));
  Assert.IsTrue(ContainsStr(TSymbolPathSearch.Text(mFound, ''), 'Weg 2:'));
end;

procedure TSymbolPathTests.AbortIsReported;
var
  mSearch: TSymbolPathRequest;
  mFound: TSymbolPathResult;
  mEngine: TSymbolPathSearch;
begin
  AddShop;
  mSearch := Request('TKundenForm', 'TDatenbank');
  mSearch.MaxNodes := 3;
  mFound := Find(mSearch);
  Assert.AreEqual(Ord(TSymbolPathStatus.Aborted), Ord(mFound.Status));
  Assert.AreEqual('Knotengrenze', mFound.AbortReason);
  Assert.IsTrue(StartsStr('Kein Weg gefunden in ', TSymbolPathSearch.Text(mFound, '')));
  Assert.IsTrue(ContainsStr(TSymbolPathSearch.Text(mFound, ''), 'abgebrochen'));
  // Abbruch von außen (MCP-Cancel).
  Build;
  mEngine := TSymbolPathSearch.Create(FIndex, FGraph, FLocator, nil, nil);
  try
    mFound := mEngine.Find(Request('uKundenForm', 'uDatenbank'),
      function: Boolean
      begin
        Result := True;
      end);
  finally
    mEngine.Free;
  end;
  Assert.AreEqual(Ord(TSymbolPathStatus.Aborted), Ord(mFound.Status));
  Assert.AreEqual('abgebrochen', mFound.AbortReason);
end;

procedure TSymbolPathTests.LibraryIsNoPassage;
var
  mSearch: TSymbolPathRequest;
  mFound: TSymbolPathResult;
begin
  AddUnit('uZiel', 'unit uZiel;'#10'interface'#10'type'#10'  TZiel = class'#10'  end;'#10'implementation'#10'end.');
  AddUnit('uLib', 'unit uLib;'#10'interface'#10'uses uZiel;'#10'type'#10'  TLibBasis = class'#10 +
    '    FZiel: TZiel;'#10'  end;'#10'implementation'#10'end.', True);
  AddUnit('uApp', 'unit uApp;'#10'interface'#10'uses uLib;'#10'type'#10'  TApp = class(TLibBasis)'#10 +
    '  end;'#10'implementation'#10'end.');
  // Bibliothek als Ziel ja …
  mFound := Find('TApp', 'TLibBasis');
  Assert.AreEqual('inherits', Kinds(mFound.Routes[0]));
  // … als Durchgang nein.
  Assert.AreEqual(Ord(TSymbolPathStatus.NoPath), Ord(Find('TApp', 'TZiel').Status));
  mSearch := Request('TApp', 'TZiel');
  mSearch.ThroughLibrary := True;
  mFound := Find(mSearch);
  Assert.AreEqual('TApp > TLibBasis > TZiel', Captions(mFound.Routes[0]));
end;

procedure TSymbolPathTests.TieBreaksByEdgeRank;
var
  mSearch: TSymbolPathRequest;
  mFound: TSymbolPathResult;
begin
  AddUnit('uGleich', 'unit uGleich;'#10'interface'#10'type'#10'  TY = class'#10'  end;'#10 +
    '  TX = class(TY)'#10'    FY: TY;'#10'  end;'#10'implementation'#10'end.');
  mSearch := Request('TX', 'TY');
  mSearch.All := True;
  mFound := Find(mSearch);
  Assert.AreEqual(2, Integer(Length(mFound.Routes)));
  // inherits steht in der Rangfolge vor hasField.
  Assert.AreEqual('inherits', Kinds(mFound.Routes[0]));
  Assert.AreEqual('hasField', Kinds(mFound.Routes[1]));
end;

procedure TSymbolPathTests.SameInputSameRoute;
var
  mFirst: string;
  mRun: Integer;
  mFound: TSymbolPathResult;
begin
  AddShop;
  mFirst := Captions(Find('TKundenForm', 'TDatenbank').Routes[0]);
  for mRun := 1 to 3 do
  begin
    FreeAndNil(FLocator);
    FreeAndNil(FGraph);
    mFound := Find('TKundenForm', 'TDatenbank');
    Assert.AreEqual(mFirst, Captions(mFound.Routes[0]));
  end;
end;

procedure TSymbolPathTests.ParsesVia;
var
  mKind, mParsed: TSymbolPathEdgeKind;
  mLibrary_: Boolean;
begin
  Assert.IsTrue(TSymbolPathSearch.TryParseEdge('hasField', mKind, mLibrary_));
  Assert.AreEqual(Ord(TSymbolPathEdgeKind.HasField), Ord(mKind));
  Assert.IsFalse(mLibrary_);
  Assert.IsTrue(TSymbolPathSearch.TryParseEdge('library', mKind, mLibrary_));
  Assert.IsTrue(mLibrary_);
  Assert.IsFalse(TSymbolPathSearch.TryParseEdge('foo', mKind, mLibrary_));
  for mKind := Low(TSymbolPathEdgeKind) to High(TSymbolPathEdgeKind) do
  begin
    Assert.IsTrue(TSymbolPathSearch.TryParseEdge(TSymbolPathSearch.EdgeName(mKind), mParsed, mLibrary_));
    Assert.AreEqual(Ord(mKind), Ord(mParsed));
  end;
end;

procedure TSymbolPathTests.JsonCarriesRoute;
var
  mFound: TSymbolPathResult;
  mJson: TJSONObject;
  mRoute: TJSONObject;
begin
  AddShop;
  mFound := Find('TKundenRepo', 'TDatenbank');
  mJson := TSymbolPathSearch.ToJson(mFound);
  try
    Assert.AreEqual('found', mJson.GetValue('status').Value);
    mRoute := (mJson.GetValue('routes') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual(2, (mRoute.GetValue('nodes') as TJSONArray).Count);
    Assert.AreEqual('hasField', ((mRoute.GetValue('steps') as TJSONArray).Items[0] as TJSONObject)
      .GetValue('kind').Value);
    Assert.AreEqual(5, (((mRoute.GetValue('steps') as TJSONArray).Items[0] as TJSONObject)
      .GetValue('line') as TJSONNumber).AsInt);
    Assert.AreEqual('TDatenbank', (mJson.GetValue('target') as TJSONObject).GetValue('caption').Value);
  finally
    mJson.Free;
  end;
end;

procedure TSymbolPathTests.LargeGroupAnswersQuickly;
var
  mIndex, mLayer: Integer;
  mName, mUsesText: string;
  mWatch: TStopwatch;
  mFound: TSymbolPathResult;
begin
  // 2000 Units in 250 Schichten zu 8; jede verwendet die 8 der nächsten Schicht und deklariert einen Typ mit
  // Feld auf einen Typ der nächsten Schicht.
  for mIndex := 0 to 1999 do
  begin
    mLayer := mIndex div 8;
    mName := Format('U%.4d', [mIndex]);
    mUsesText := '';
    if mLayer < 249 then
    begin
      mUsesText := Format('uses U%.4d, U%.4d, U%.4d, U%.4d, U%.4d, U%.4d, U%.4d, U%.4d;'#10,
        [(mLayer + 1) * 8, (mLayer + 1) * 8 + 1, (mLayer + 1) * 8 + 2, (mLayer + 1) * 8 + 3, (mLayer + 1) * 8 + 4,
        (mLayer + 1) * 8 + 5, (mLayer + 1) * 8 + 6, (mLayer + 1) * 8 + 7]);
    end;
    AddUnit(mName, 'unit ' + mName + ';'#10'interface'#10 + mUsesText + 'type'#10'  T' + mName + ' = class'#10 +
      IfThen(mLayer < 249, Format('    FNext: TU%.4d;'#10, [(mLayer + 1) * 8 + mIndex mod 8]), '') +
      '    procedure Arbeite;'#10'  end;'#10'implementation'#10'procedure T' + mName + '.Arbeite;'#10'begin'#10 +
      'end;'#10'end.');
  end;
  Build;
  mWatch := TStopwatch.StartNew;
  mFound := Find('U0000', Format('U%.4d', [8 * 8 + 3]));
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(mFound.Status));
  Assert.AreEqual(8, Integer(Length(mFound.Routes[0].Steps)));
  mFound := Find('TU0000', Format('TU%.4d', [8 * 8]));
  Assert.AreEqual(Ord(TSymbolPathStatus.Found), Ord(mFound.Status));
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 2000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
end;

initialization
  TDUnitX.RegisterTestFixture(TSymbolPathTests);

end.
