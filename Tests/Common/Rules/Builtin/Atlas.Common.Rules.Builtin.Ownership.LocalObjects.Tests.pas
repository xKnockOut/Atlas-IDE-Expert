unit Atlas.Common.Rules.Builtin.Ownership.LocalObjects.Tests;

// Tests von local-object-not-freed und created-result-not-freed (#1876): Beispiel mit Korrektur, Inline-Variablen,
// Freigaben und Weitergaben, Owner und Threads, Fabrikfunktionen der Datei und aus der Option factories,
// Abschalten; Weitergabe an Routinen anderer Units über die Besitz-Zusammenfassung im Index.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLocalObjectNotFreedTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure InlineVariable;
    [Test]
    procedure ReleasesAreSilent;
    [Test]
    procedure EscapesAreSilent;
    [Test]
    procedure OwnersThreadsAndRecordsAreSilent;
    [Test]
    procedure UnknownClassIsSilent;
    [Test]
    procedure RoutineOfOtherUnitOnlyBorrows;
    [Test]
    procedure RoutineOfOtherUnitFreesOrKeeps;
    [Test]
    procedure OwnAssignThatKeepsIsNoReadingCall;
    [Test]
    procedure RuleCanBeTurnedOff;
  end;

  [TestFixture]
  TCreatedResultNotFreedTests = class
  public
    [Test]
    procedure FactoryOfTheFile;
    [Test]
    procedure FunctionsThatAreNoFactories;
    [Test]
    procedure FactoryFromSettings;
    [Test]
    procedure ReleasedOrPassedResultIsSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Ownership.LocalObjects,
  Atlas.Common.Documents.TextChanges,
  Atlas.Common.Index.Contract,
  Atlas.Tests.SymbolIndex,
  Atlas.Tests.RuleAssert,
  Atlas.Tests.SourceText;

/// <summary>Unit mit der Routine Lauf (Variablen AVars, Rumpf ABody) und einer eigenen Klasse TProtokoll.</summary>
function Source(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10 +
    '  TProtokoll = class(TObject)'#10'  end;'#10'implementation'#10 +
    'procedure Lauf(Ziel: TStrings);'#10'var'#10 + AVars + 'begin'#10 + ABody + 'end;'#10'end.';
end;

{ TLocalObjectNotFreedTests }

procedure TLocalObjectNotFreedTests.IssueExampleWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('  Liste: TStringList;'#10, '  Liste := TStringList.Create;'#10'  Liste.Add(''a'');'#10 +
    '  Ziel.Text := Liste.Text;'#10);
  mFound := TRuleAssert.Findings(TLocalObjectNotFreedRule.Create, mSource);
  Assert.AreEqual('12: Liste erhält ein neues TStringList, das die Routine weder freigibt noch weitergibt ' +
    '(Speicherleck).|', TRuleAssert.LineMessages(mFound));
  Assert.AreEqual(cLocalObjectNotFreedRuleId, mFound[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('try … finally Liste.Free end einfügen', mFound[0].Fixes[0].Title);
  mFixed := TTextChanges.Apply(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(Source('  Liste: TStringList;'#10, '  Liste := TStringList.Create;'#10'  try'#10 +
    '    Liste.Add(''a'');'#10'    Ziel.Text := Liste.Text;'#10'  finally'#10'    Liste.Free;'#10'  end;'#10), mFixed);
  TTestSource.AssertParses(mFixed);
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, mFixed);
end;

procedure TLocalObjectNotFreedTests.InlineVariable;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('  Zahl: Integer;'#10, '  var Liste := TList<Integer>.Create;'#10'  Liste.Add(1);'#10 +
    '  Zahl := Liste.Count;'#10);
  mFound := TRuleAssert.Findings(TLocalObjectNotFreedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFound)), TRuleAssert.LineMessages(mFound));
  Assert.Contains(mFound[0].Message, 'Liste erhält ein neues TList');
  mFixed := TTextChanges.Apply(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(Source('  Zahl: Integer;'#10, '  var Liste := TList<Integer>.Create;'#10'  try'#10 +
    '    Liste.Add(1);'#10'    Zahl := Liste.Count;'#10'  finally'#10'    Liste.Free;'#10'  end;'#10), mFixed);
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, mFixed);
  // Mit Typangabe und als spätere Zuweisung.
  TRuleAssert.Reports(TLocalObjectNotFreedRule.Create, Source('', '  var P: TProtokoll := TProtokoll.Create;'#10));
  TRuleAssert.Reports(TLocalObjectNotFreedRule.Create, Source('', '  var P: TProtokoll;'#10 +
    '  P := TProtokoll.Create;'#10));
end;

procedure TLocalObjectNotFreedTests.ReleasesAreSilent;
const
  cVars = '  P: TProtokoll;'#10;
  cCreate = '  P := TProtokoll.Create;'#10;
begin
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  FreeAndNil(P);'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  P.DisposeOf;'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  P.Destroy;'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  ObjektFreigeben(P);'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  try'#10'  finally'#10 +
    '    if Assigned(P) then'#10'      P.Free;'#10'  end;'#10));
end;

procedure TLocalObjectNotFreedTests.EscapesAreSilent;
const
  cVars = '  P: TProtokoll;'#10'  Objekt: TObject;'#10'  Schnitt: IInterface;'#10;
  cCreate = '  P := TProtokoll.Create;'#10;
begin
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  Ziel.AddObject(''p'', P);'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  Objekt := P;'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  Ziel.Objects[0] := P;'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  Schnitt := P as IInterface;'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  raise P;'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  Merken(TObject(P));'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  TThread.Queue(nil,'#10 +
    '    procedure'#10'    begin'#10'      P.Free;'#10'    end);'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, cCreate + '  with P do'#10'    Free;'#10));
  // Lokale Routine sieht die Variable ebenfalls.
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Lauf;'#10'var'#10'  P: TObject;'#10'  procedure Weg;'#10'  begin'#10'    P.Free;'#10'  end;'#10 +
    'begin'#10'  P := TObject.Create;'#10'  Weg;'#10'end;'#10'end.');
  // Interface-Variable: die Referenzzählung gibt frei.
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, '  Schnitt := TInterfacedObject.Create;'#10));
end;

procedure TLocalObjectNotFreedTests.OwnersThreadsAndRecordsAreSilent;
const
  cVars = '  K: TComponent;'#10'  T: TThread;'#10'  R: TRect;'#10'  A: TArray<string>;'#10;
begin
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, '  K := TComponent.Create(Ziel.Owner);'#10 +
    '  K := TComponent.Create(Self);'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, '  T := TWorkerThread.Create;'#10));
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, '  R := TRect.Create(0, 0, 1, 1);'#10 +
    '  A := TArray<string>.Create(''a'');'#10));
  // Unbekannte Klasse mit Argumenten trägt sich womöglich selbst ein.
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source('  F: TFremd;'#10, '  F := TFremd.Create(Ziel);'#10));
  // Owner nil: Niemand gibt frei.
  TRuleAssert.Reports(TLocalObjectNotFreedRule.Create, Source(cVars, '  K := TComponent.Create(nil);'#10));
  // Formular mit Show gibt sich womöglich selbst frei (caFree).
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, Source(cVars, '  K := TComponent.Create(nil);'#10 +
    '  K.Show;'#10));
end;

procedure TLocalObjectNotFreedTests.UnknownClassIsSilent;
var
  mFound: TArray<TRuleFinding>;
begin
  // Ohne Index unbekannt (TFremd könnte ein Record mit Create sein): still; RTL-Klasse und Klasse der Datei: hoch.
  mFound := TRuleAssert.Findings(TLocalObjectNotFreedRule.Create, Source('  P: TProtokoll;'#10'  F: TFremd;'#10 +
    '  L: TStringList;'#10, '  P := TProtokoll.Create;'#10'  F := TFremd.Create;'#10'  L := TStringList.Create;'#10));
  Assert.AreEqual(2, Integer(Length(mFound)), TRuleAssert.LineMessages(mFound));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFound[0].Confidence));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFound[1].Confidence));
  Assert.Contains(mFound[1].Message, 'TStringList');
end;

const
  cHelfer = 'unit Helfer;'#10'interface'#10'uses System.Classes;'#10'type'#10'  THalter = class'#10 +
    '  private'#10'    FListe: TStrings;'#10'  public'#10'    constructor Create(AListe: TStrings);'#10'  end;'#10 +
    'procedure StrBreakApart(const S, Trenner: string; Teile: TStrings);'#10'procedure Weg(A: TObject);'#10 +
    'procedure Weiter(A: TObject);'#10'procedure Anders(A: TObject);'#10'implementation'#10 +
    'constructor THalter.Create(AListe: TStrings);'#10'begin'#10'  FListe := AListe;'#10'end;'#10 +
    'procedure StrBreakApart(const S, Trenner: string; Teile: TStrings);'#10'begin'#10'  Teile.Add(S);'#10 +
    'end;'#10'procedure Weg(A: TObject);'#10'begin'#10'  A.Free;'#10'end;'#10 +
    'procedure Weiter(A: TObject);'#10'begin'#10'  Weg(A);'#10'end;'#10 +
    'procedure Anders(A: TObject);'#10'begin'#10'  A.Dispatch(A);'#10'end;'#10'end.';

/// <summary>Treffer für den Rumpf ABody (Variable Liste: TStringList) in einer Unit, die Helfer einbindet.
/// </summary>
function CrossUnitFindings(const ABody: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.IndexFindings(TLocalObjectNotFreedRule.Create,
    'unit Nutzer;'#10'interface'#10'implementation'#10'uses System.Classes, Helfer;'#10'procedure Lauf;'#10 +
    'var'#10'  Liste: TStringList;'#10'  Halter: THalter;'#10'begin'#10'  Liste := TStringList.Create;'#10 +
    ABody + 'end;'#10'end.', TTestIndex.Build([cHelfer, 'Helfer.pas']), '', 'Nutzer.pas');
end;

procedure TLocalObjectNotFreedTests.RoutineOfOtherUnitOnlyBorrows;
begin
  // StrBreakApart füllt die Liste nur: Sie bleibt ein Leck des Aufrufers.
  Assert.AreEqual(1, Integer(Length(CrossUnitFindings('  StrBreakApart(''a,b'', '','', Liste);'#10))));
  Assert.AreEqual(1, Integer(Length(CrossUnitFindings('  ExtractStrings(['',''], [], ''a,b'', Liste);'#10))));
end;

procedure TLocalObjectNotFreedTests.RoutineOfOtherUnitFreesOrKeeps;
begin
  Assert.AreEqual(0, Integer(Length(CrossUnitFindings('  Weg(Liste);'#10))));
  Assert.AreEqual(0, Integer(Length(CrossUnitFindings('  Weiter(Liste);'#10))));
  Assert.AreEqual(0, Integer(Length(CrossUnitFindings('  Halter := THalter.Create(Liste);'#10 +
    '  Halter.Free;'#10))));
  // Unklar (Aufruf einer Methode des Objekts) und unbekannte Routinen bleiben still.
  Assert.AreEqual(0, Integer(Length(CrossUnitFindings('  Anders(Liste);'#10))));
  Assert.AreEqual(0, Integer(Length(CrossUnitFindings('  Unbekannt(Liste);'#10))));
end;

procedure TLocalObjectNotFreedTests.OwnAssignThatKeepsIsNoReadingCall;
const
  cText = 'unit Werte;'#10'interface'#10'procedure Lauf;'#10'implementation'#10'type'#10'  TBau = class'#10 +
    '  end;'#10'  TWert = class'#10'  public'#10'    Aktuell: TBau;'#10 +
    '    procedure Assign(ABau: TBau);'#10'  end;'#10'procedure TWert.Assign(ABau: TBau);'#10'begin'#10 +
    '  Aktuell := ABau;'#10'end;'#10'procedure Lauf;'#10'var'#10'  Wert: TWert;'#10'  Bau: TBau;'#10'begin'#10 +
    '  Wert := nil;'#10'  Bau := TBau.Create;'#10'  Wert.Assign(Bau);'#10'end;'#10'end.';
begin
  // Assign gilt als lesend nur, solange der Index nichts über die Routine weiß; diese behält das Objekt.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TLocalObjectNotFreedRule.Create, cText,
    TTestIndex.Build([cText, 'Werte.pas']), '', 'Werte.pas'))));
  // Assign einer unbekannten Klasse bleibt lesend: Das Objekt ist ein Leck.
  Assert.AreEqual(1, Integer(Length(CrossUnitFindings('  Halter.Assign(Liste);'#10))));
end;

procedure TLocalObjectNotFreedTests.RuleCanBeTurnedOff;
var
  mSource: string;
begin
  mSource := Source('  P: TProtokoll;'#10, '  P := TProtokoll.Create;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLocalObjectNotFreedRule.Create, mSource))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLocalObjectNotFreedRule.Create, mSource,
    '{"rules": {"local-object-not-freed": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLocalObjectNotFreedRule.Create,
    StringReplace(mSource, '  P := TProtokoll.Create;', '  P := TProtokoll.Create; // lsp-ignore: ' +
    'local-object-not-freed', [])))));
end;

{ TCreatedResultNotFreedTests }

/// <summary>Unit mit den Fabriken NeueListe und TBau.Neu, der Funktion Gemerkt (keine Fabrik) und Lauf.</summary>
function FactorySource(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10'  TBau = class'#10 +
    '    class function Neu: TStringList;'#10'  end;'#10'var'#10'  GListe: TStringList;'#10'implementation'#10 +
    'function NeueListe(const AText: string): TStringList;'#10'begin'#10'  Result := TStringList.Create;'#10 +
    '  try'#10'    Result.Text := AText;'#10'  except'#10'    Result.Free;'#10'    raise;'#10'  end;'#10'end;'#10 +
    'class function TBau.Neu: TStringList;'#10'begin'#10'  Result := TStringList.Create;'#10'end;'#10 +
    'function Gemerkt: TStringList;'#10'begin'#10'  if GListe = nil then'#10'    GListe := TStringList.Create;'#10 +
    '  Result := GListe;'#10'end;'#10 +
    'procedure Lauf(Ziel: TStrings);'#10'var'#10 + AVars + 'begin'#10 + ABody + 'end;'#10'end.';
end;

{ TCreatedResultNotFreedTests }

procedure TCreatedResultNotFreedTests.FactoryOfTheFile;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := FactorySource('  L: TStringList;'#10, '  L := NeueListe(''a'');'#10'  Ziel.Assign(L);'#10);
  mFound := TRuleAssert.Findings(TCreatedResultNotFreedRule.Create, mSource);
  Assert.AreEqual('35: L erhält von NeueListe ein neues Objekt, das die Routine weder freigibt noch weitergibt ' +
    '(Speicherleck).|', TRuleAssert.LineMessages(mFound));
  Assert.AreEqual(cCreatedResultNotFreedRuleId, mFound[0].RuleId);
  mFixed := TTextChanges.Apply(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(FactorySource('  L: TStringList;'#10, '  L := NeueListe(''a'');'#10'  try'#10 +
    '    Ziel.Assign(L);'#10'  finally'#10'    L.Free;'#10'  end;'#10), mFixed);
  TRuleAssert.Silent(TCreatedResultNotFreedRule.Create, mFixed);
  // Klassenmethode über den Typnamen, Inline-Variable.
  mFound := TRuleAssert.Findings(TCreatedResultNotFreedRule.Create, FactorySource('',
    '  var L := TBau.Neu;'#10'  Ziel.Assign(L);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), TRuleAssert.LineMessages(mFound));
  Assert.Contains(mFound[0].Message, 'TBau.Neu');
  // Die andere Regel meldet nur Konstruktoren.
  TRuleAssert.Silent(TLocalObjectNotFreedRule.Create, FactorySource('  L: TStringList;'#10,
    '  L := NeueListe(''a'');'#10));
end;

procedure TCreatedResultNotFreedTests.FunctionsThatAreNoFactories;
begin
  // Gemerkt liefert ein gespeichertes Objekt; Methoden eines fremden Objekts kennt die Regel nicht.
  TRuleAssert.Silent(TCreatedResultNotFreedRule.Create, FactorySource('  L: TStringList;'#10,
    '  L := Gemerkt;'#10'  Ziel.Assign(L);'#10'  L := Ziel.Neu;'#10));
  // Result weitergegeben oder mit Owner erzeugt: keine Fabrik.
  TRuleAssert.Silent(TCreatedResultNotFreedRule.Create, 'unit U;'#10'interface'#10'uses'#10'  System.Classes;'#10 +
    'implementation'#10'function Neu(L: TList): TObject;'#10'begin'#10'  Result := TObject.Create;'#10 +
    '  L.Add(Result);'#10'end;'#10'function Teil(O: TComponent): TComponent;'#10'begin'#10 +
    '  Result := TComponent.Create(O);'#10'end;'#10'procedure Lauf(L: TList);'#10'var'#10'  A: TObject;'#10 +
    '  B: TComponent;'#10'begin'#10'  A := Neu(L);'#10'  B := Teil(nil);'#10'end;'#10'end.');
  // Klassenfunktion Create, die einen Record liefert: kein Objekt (Selbstlauf, TAtlasGitHubPulls.Create).
  TRuleAssert.Silent(TCreatedResultNotFreedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TErgebnis = record'#10'    N: Integer;'#10'  end;'#10'  TBau = class(TObject)'#10 +
    '    class function Create(A: Integer): TErgebnis; static;'#10'  end;'#10'implementation'#10 +
    'class function TBau.Create(A: Integer): TErgebnis;'#10'begin'#10'  Result.N := A;'#10'end;'#10 +
    'function Neu: TErgebnis;'#10'begin'#10'  Result := TBau.Create(1);'#10'end;'#10'procedure Lauf;'#10'var'#10 +
    '  E: TErgebnis;'#10'begin'#10'  E := Neu;'#10'end;'#10'end.');
end;

procedure TCreatedResultNotFreedTests.FactoryFromSettings;
var
  mSource: string;
begin
  mSource := FactorySource('  L: TStringList;'#10, '  L := Ziel.Kopie;'#10'  Ziel.Assign(L);'#10);
  TRuleAssert.Silent(TCreatedResultNotFreedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCreatedResultNotFreedRule.Create, mSource,
    '{"rules": {"created-result-not-freed": {"factories": ["Kopie"]}}}'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCreatedResultNotFreedRule.Create, mSource,
    '{"rules": {"created-result-not-freed": {"factories": ["Ziel.Kopie"]}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCreatedResultNotFreedRule.Create, mSource,
    '{"rules": {"created-result-not-freed": "off", "local-object-not-freed": {"factories": ["Kopie"]}}}'))));
end;

procedure TCreatedResultNotFreedTests.ReleasedOrPassedResultIsSilent;
begin
  TRuleAssert.Silent(TCreatedResultNotFreedRule.Create, FactorySource('  L: TStringList;'#10,
    '  L := NeueListe(''a'');'#10'  try'#10'    Ziel.Assign(L);'#10'  finally'#10'    L.Free;'#10'  end;'#10));
  TRuleAssert.Silent(TCreatedResultNotFreedRule.Create, FactorySource('  L: TStringList;'#10,
    '  L := NeueListe(''a'');'#10'  Ziel.AddObject(''l'', L);'#10));
end;

initialization
  TDUnitX.RegisterTestFixture(TLocalObjectNotFreedTests);
  TDUnitX.RegisterTestFixture(TCreatedResultNotFreedTests);

end.
