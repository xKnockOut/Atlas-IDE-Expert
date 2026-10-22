unit Atlas.Common.Rules.ConsideredUsed.Tests;

// Tests des Dienstes „gilt als verwendet“ (#1102): je Grund ein Fall, dazu
// unbekannte Vorfahren, Methodenzuordnung, Muster und gewöhnliche Mitglieder.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConsideredUsedTests = class
  public
    [Test]
    procedure DirectivesConstructorsAndOperators;
    [Test]
    procedure EnumeratorDefaultAndImplements;
    [Test]
    procedure AttributesAndKeepLists;
    [Test]
    procedure InterfaceMethods;
    [Test]
    procedure StreamingAndTestCases;
    [Test]
    procedure AccessorsExportsInterfacesHelpers;
    [Test]
    procedure UnknownAncestorAndPlainMembers;
    [Test]
    procedure PatternMatching;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.ConsideredUsed;

const
  LibraryText = 'unit System;'#10'interface'#10'type'#10'  TObject = class'#10'  end;'#10 +
    '  IInterface = interface'#10'    function _AddRef: Integer;'#10'  end;'#10 +
    '  TInterfacedObject = class(TObject, IInterface)'#10'  public'#10'    function _AddRef: Integer;'#10'  end;'#10 +
    '  TPersistent = class(TObject)'#10'  end;'#10'  TComponent = class(TPersistent)'#10'  end;'#10 +
    '  TTestCase = class(TObject)'#10'  end;'#10'implementation'#10'end.';

/// <summary>Grund für das Mitglied AContainer.AName aus AUnitText (Kind = erste Deklaration).</summary>
function ReasonOf(const AUnitText, AContainer, AName: string; const AKeepAttributes,
  AKeepPatterns: TArray<string>): TConsideredUsedReason; overload;
var
  Index: ISymbolIndex;
  Local: TUnitIndex;
  Tree: TSyntaxTree;
  Tokens: TArray<TPascalToken>;
  Token: TPascalToken;
  Service: TConsideredUsed;
  Symbol: TIndexSymbol;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(LibraryText, 'C:\BDS\source\System.pas', nil));
  Local := TIndexExtractor.ExtractText(AUnitText, 'C:\P\Probe.pas', nil);
  Index.AddUnit(Local);
  Tree := TSyntaxTreeCache.Parse(AUnitText);
  try
    Tokens := nil;
    for Token in Tree.Tokens do
      if not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
        Tokens := Tokens + [Token];
    Service := TConsideredUsed.Create(Index, Local, Tokens, AKeepAttributes, AKeepPatterns);
    try
      for Symbol in Local.Symbols do
        if SameText(Symbol.Name, AName) and SameText(Symbol.Container, AContainer) then
          Exit(Service.Reason(Symbol));
      Assert.Fail('Mitglied fehlt: ' + AName);
      Result := TConsideredUsedReason.None;
    finally
      Service.Free;
    end;
  finally
    Tree.Free;
  end;
end;

function ReasonOf(const AUnitText, AContainer, AName: string): TConsideredUsedReason; overload;
begin
  Result := ReasonOf(AUnitText, AContainer, AName, nil, nil);
end;

/// <summary>Unit Probe mit dem Typ TProbe (Vorfahr AAncestor, '' = keiner) und den Mitgliedern AMembers.</summary>
function Probe(const AAncestor, AMembers: string): string;
var
  Head: string;
begin
  Head := 'class';
  if AAncestor <> '' then
    Head := 'class(' + AAncestor + ')';
  Result := 'unit Probe;'#10'interface'#10'type'#10'  TProbe = ' + Head + #10 + AMembers + '  end;'#10 +
    'implementation'#10'end.';
end;

procedure TConsideredUsedTests.DirectivesConstructorsAndOperators;
begin
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Directive, ReasonOf(Probe('', '  public'#10 +
    '    procedure Malen; virtual;'#10), 'TProbe', 'Malen'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Directive, ReasonOf(Probe('', '  public'#10 +
    '    procedure WMSize(var M: TMessage); message 5;'#10), 'TProbe', 'WMSize'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Constructor_, ReasonOf(Probe('', '  public'#10 +
    '    constructor Erzeugen;'#10), 'TProbe', 'Erzeugen'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Constructor_, ReasonOf(Probe('', '  public'#10 +
    '    destructor Abbauen;'#10), 'TProbe', 'Abbauen'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Operator, ReasonOf('unit Probe;'#10'interface'#10'type'#10 +
    '  TBetrag = record'#10'  public'#10'    class operator Add(const A, B: TBetrag): TBetrag;'#10'  end;'#10 +
    'implementation'#10'end.', 'TBetrag', 'Add'));
end;

procedure TConsideredUsedTests.EnumeratorDefaultAndImplements;
begin
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Enumerator, ReasonOf(Probe('', '  public'#10 +
    '    function GetEnumerator: TObject;'#10), 'TProbe', 'GetEnumerator'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.DefaultProperty, ReasonOf(Probe('', '  private'#10 +
    '    function Hole(I: Integer): Integer;'#10'  public'#10 +
    '    property Werte[I: Integer]: Integer read Hole; default;'#10), 'TProbe', 'Werte'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Implements, ReasonOf(Probe('TInterfacedObject, IInterface', '  private'#10 +
    '    FInner: IInterface;'#10'  public'#10'    property Inner: IInterface read FInner implements IInterface;'#10),
    'TProbe', 'Inner'));
end;

procedure TConsideredUsedTests.AttributesAndKeepLists;
begin
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Attribute, ReasonOf(Probe('', '  public'#10'    [JsonName(''n'')]'#10 +
    '    Name: string;'#10), 'TProbe', 'Name'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.TestFixture, ReasonOf('unit Probe;'#10'interface'#10'type'#10 +
    '  [TestFixture]'#10'  TProbe = class'#10'  public'#10'    procedure Pruefe;'#10'  end;'#10'implementation'#10 +
    'end.', 'TProbe', 'Pruefe'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.KeepAttribute, ReasonOf('unit Probe;'#10'interface'#10'type'#10 +
    '  [MVCPath(''/k'')]'#10'  TProbe = class'#10'  public'#10'    procedure Liste;'#10'  end;'#10'implementation'#10 +
    'end.', 'TProbe', 'Liste', ['MVCPath'], nil));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.KeepPattern, ReasonOf(Probe('', '  public'#10 +
    '    procedure KnopfHandler;'#10), 'TProbe', 'KnopfHandler', nil, ['*Handler']));
end;

procedure TConsideredUsedTests.InterfaceMethods;
const
  Unit_ = 'unit Probe;'#10'interface'#10'type'#10'  IZaehler = interface'#10'    procedure Zaehle;'#10 +
    '  end;'#10'  TProbe = class(TInterfacedObject, IZaehler)'#10'  public'#10'    procedure Zaehle;'#10 +
    '    procedure Anders;'#10'    procedure IZaehler.Zaehle = Anders2;'#10'    procedure Anders2;'#10'  end;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.InterfaceMethod, ReasonOf(Unit_, 'TProbe', 'Zaehle'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.InterfaceMethod, ReasonOf(Unit_, 'TProbe', 'Anders2'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.None, ReasonOf(Unit_, 'TProbe', 'Anders'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.InterfaceMember, ReasonOf(Unit_, 'IZaehler', 'Zaehle'));
end;

procedure TConsideredUsedTests.StreamingAndTestCases;
begin
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Streamed, ReasonOf(Probe('TComponent', '  private'#10 +
    '    FFarbe: Integer;'#10'  published'#10'    property Farbe: Integer read FFarbe;'#10), 'TProbe', 'Farbe'));
  // published Methode ohne Formular: zählt nur über Verwendungen.
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.None, ReasonOf(Probe('TComponent', '  published'#10 +
    '    procedure Klick(Sender: TObject);'#10), 'TProbe', 'Klick'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.TestFixture, ReasonOf(Probe('TTestCase', '  published'#10 +
    '    procedure TestAddieren;'#10), 'TProbe', 'TestAddieren'));
end;

procedure TConsideredUsedTests.AccessorsExportsInterfacesHelpers;
begin
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Accessor, ReasonOf(Probe('', '  public'#10 +
    '    function GetWert: Integer;'#10'    property Wert: Integer read GetWert;'#10), 'TProbe', 'GetWert'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.Exported, ReasonOf('library Probe;'#10'procedure Starten; stdcall;'#10 +
    'begin'#10'end;'#10'exports'#10'  Starten;'#10'begin'#10'end.', '', 'Starten'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.HelperMember, ReasonOf('unit Probe;'#10'interface'#10'type'#10 +
    '  TTextHilfe = record helper for string'#10'  public'#10'    function Leer: Boolean;'#10'  end;'#10 +
    'implementation'#10'end.', 'TTextHilfe', 'Leer'));
end;

procedure TConsideredUsedTests.UnknownAncestorAndPlainMembers;
begin
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.UnknownAncestor, ReasonOf(Probe('TUnbekannt', '  public'#10 +
    '    procedure Lauf;'#10), 'TProbe', 'Lauf'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.None, ReasonOf(Probe('', '  public'#10'    procedure Lauf;'#10), 'TProbe',
    'Lauf'));
  Assert.AreEqual<TConsideredUsedReason>(TConsideredUsedReason.None, ReasonOf(Probe('TComponent', '  public'#10'    procedure Lauf;'#10),
    'TProbe', 'Lauf'));
  Assert.AreEqual('Vorfahr oder Interface nicht im Index',
    TConsideredUsed.Explain(TConsideredUsedReason.UnknownAncestor));
end;

procedure TConsideredUsedTests.PatternMatching;
begin
  Assert.IsTrue(TConsideredUsed.Matches('*Handler', 'KnopfHandler'));
  Assert.IsTrue(TConsideredUsed.Matches('api*', 'ApiListe'));
  Assert.IsTrue(TConsideredUsed.Matches('T?', 'TX'));
  Assert.IsTrue(TConsideredUsed.Matches('*', ''));
  Assert.IsFalse(TConsideredUsed.Matches('*Handler', 'Handle'));
  Assert.IsFalse(TConsideredUsed.Matches('T?', 'TXY'));
  Assert.IsTrue(TConsideredUsed.Matches('TKunden*.Lade*', 'TKundenService.LadeAlle'));
end;

initialization
  TDUnitX.RegisterTestFixture(TConsideredUsedTests);

end.
