unit Atlas.Common.Editing.ClassBodies.Tests;

// Rümpfe einer Klasse (#1834): Gestalt aus der Deklaration, Rang beim Ordnen
// (#1836), Vorbefüllung (#1837) und Kommentar um die Rümpfe (#1835).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TClassBodiesTests = class
  public
    [Test]
    procedure ReadsShape;
    [Test]
    procedure RanksLifecycleAccessorsOverrides;
    [Test]
    procedure ReadsParameterNames;
    [Test]
    procedure StubsForOverridesAndAccessors;
    [Test]
    procedure NoStubsWithoutMatchingField;
    [Test]
    procedure WrapsWithTypeComment;
    [Test]
    procedure FindsExistingTypeComment;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.TypeComments,
  Atlas.Common.Editing.ClassBodies;

const
  Quelle =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  /// <summary>Kunde mit Adresse.</summary>'#10 +
    '  TKunde = class(TComponent)'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    FAlter: Int64;'#10 +
    '    function GetName: string;'#10 +
    '    procedure SetName(const AValue: string);'#10 +
    '    function GetAlter: Integer;'#10 +
    '    function GetPosten(AIndex: Integer): string;'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10 +
    '    destructor Destroy; override;'#10 +
    '    procedure AfterConstruction; override;'#10 +
    '    class constructor Init;'#10 +
    '    procedure Loaded; override;'#10 +
    '    property Name: string read GetName write SetName;'#10 +
    '    property Alter: Integer read GetAlter;'#10 +
    '    property Posten[AIndex: Integer]: string read GetPosten;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

function Shape: TTypeShape;
begin
  Result := TTypeShape.Read(TIndexExtractor.ExtractText(Quelle, 'U.pas', nil), Quelle.Split([#10]), 'TKunde');
end;

procedure TClassBodiesTests.ReadsShape;
var
  Kunde: TTypeShape;
  FieldType: string;
begin
  Kunde := Shape;
  Assert.AreEqual('TKunde', Kunde.TypeName);
  Assert.IsTrue(Kunde.IsClass);
  Assert.AreEqual('TComponent', Kunde.Ancestor);
  Assert.AreEqual('Kunde mit Adresse.', Kunde.Summary);
  Assert.AreEqual(3, Integer(Length(Kunde.Properties)));
  Assert.AreEqual('GetName', Kunde.Properties[0].ReadName);
  Assert.AreEqual('SetName', Kunde.Properties[0].WriteName);
  Assert.IsTrue(Kunde.Properties[2].Indexed);
  Assert.IsTrue(Kunde.FieldType('FName', FieldType));
  Assert.AreEqual('string', FieldType);
  Assert.IsFalse(Kunde.FieldType('FGibtsNicht', FieldType));
end;

procedure TClassBodiesTests.RanksLifecycleAccessorsOverrides;
var
  Kunde: TTypeShape;

  function Rank(const ADeclaration, AName: string): Integer;
  var
    Found: TMethodRank;
  begin
    Found := TClassBodies.RankOf(Kunde, ADeclaration, AName);
    Result := Found.Group * 100 + Found.Sub;
  end;

begin
  Kunde := Shape;
  Assert.IsTrue(Rank('class constructor Init;', 'Init') < Rank('constructor Create(AOwner: TComponent); override;',
    'Create'), 'class constructor zuerst');
  Assert.IsTrue(Rank('constructor Create(AOwner: TComponent); override;', 'Create') <
    Rank('destructor Destroy; override;', 'Destroy'));
  Assert.IsTrue(Rank('destructor Destroy; override;', 'Destroy') <
    Rank('procedure AfterConstruction; override;', 'AfterConstruction'));
  Assert.AreEqual(TClassBodies.cGroupAccessor * 100, Rank('function GetName: string;', 'GetName'));
  Assert.AreEqual(TClassBodies.cGroupAccessor * 100 + 1, Rank('procedure SetName(const AValue: string);',
    'SetName'), 'Setter direkt hinter seinem Getter');
  Assert.AreEqual(TClassBodies.cGroupAccessor * 100 + 2, Rank('function GetAlter: Integer;', 'GetAlter'));
  Assert.AreEqual(TClassBodies.cGroupOverride * 100, Rank('procedure Loaded; override;', 'Loaded'));
  Assert.AreEqual(TClassBodies.cGroupOther * 100, Rank('procedure Zeichnen;', 'Zeichnen'));
end;

procedure TClassBodiesTests.ReadsParameterNames;
var
  Names: TArray<string>;
begin
  Names := TClassBodies.ParameterNames('function Wert(const A, B: Integer; var C: string; out D): Integer;');
  Assert.AreEqual('A,B,C,D', string.Join(',', Names));
  Assert.AreEqual(0, Integer(Length(TClassBodies.ParameterNames('procedure Lauf;'))));
  Names := TClassBodies.ParameterNames('procedure Lauf(const S: string = ''a;b''; X: TArray<Integer>);');
  Assert.AreEqual('S,X', string.Join(',', Names), 'Standardwert und Generics');
end;

procedure TClassBodiesTests.StubsForOverridesAndAccessors;
var
  Kunde: TTypeShape;

  function Stub(const ADeclaration, AName: string): string;
  begin
    Result := string.Join('|', TClassBodies.StubLines(Kunde, ADeclaration, AName, '  '));
  end;

begin
  Kunde := Shape;
  Assert.AreEqual('  inherited;', Stub('constructor Create(AOwner: TComponent); override;', 'Create'));
  Assert.AreEqual('|  inherited;', Stub('destructor Destroy; override;', 'Destroy'), 'inherited am Ende');
  Assert.AreEqual('  Result := FName;', Stub('function GetName: string;', 'GetName'));
  Assert.AreEqual('  FName := AValue;', Stub('procedure SetName(const AValue: string);', 'SetName'));
  Assert.AreEqual('  inherited Loaded;', Stub('procedure Loaded; override;', 'Loaded'));
  Assert.AreEqual('  Result := inherited Wert(A, B);', Stub('function Wert(A, B: Integer): Integer; override;',
    'Wert'));
  Assert.AreEqual('', Stub('procedure Zeichnen;', 'Zeichnen'));
end;

procedure TClassBodiesTests.NoStubsWithoutMatchingField;
var
  Kunde: TTypeShape;
begin
  Kunde := Shape;
  Assert.AreEqual(0, Integer(Length(TClassBodies.StubLines(Kunde, 'function GetAlter: Integer;', 'GetAlter', '  '))),
    'FAlter hat einen anderen Typ');
  Assert.AreEqual(0, Integer(Length(TClassBodies.StubLines(Kunde, 'function GetPosten(AIndex: Integer): string;',
    'GetPosten', '  '))), 'Array-Property');
end;

procedure TClassBodiesTests.WrapsWithTypeComment;
var
  Kunde: TTypeShape;
  Options: TClassBodyOptions;
begin
  Kunde := Shape;
  Options := TClassBodyOptions.Default;
  Assert.AreEqual('{ TKunde }'#10#10'B', TClassBodies.Wrapped(Kunde, Options, 'B', #10));
  Options.TypeComment := TTypeCommentStyle.Summary;
  Assert.AreEqual('{ TKunde: Kunde mit Adresse. }'#10#10'B', TClassBodies.Wrapped(Kunde, Options, 'B', #10));
  Options.TypeComment := TTypeCommentStyle.Region;
  Assert.AreEqual('{$REGION ''TKunde''}'#10'B'#10'{$ENDREGION}', TClassBodies.Wrapped(Kunde, Options, 'B', #10));
  Options.TypeComment := TTypeCommentStyle.Off;
  Assert.AreEqual('B', TClassBodies.Wrapped(Kunde, Options, 'B', #10));
end;

procedure TClassBodiesTests.FindsExistingTypeComment;
var
  Text: TArray<string>;
begin
  Text := TArray<string>.Create('implementation', '', '{ TKunde }', '', 'procedure TKunde.A;');
  Assert.IsTrue(TClassBodies.HasTypeComment(Text, 0, 'TKunde'));
  Assert.IsFalse(TClassBodies.HasTypeComment(Text, 3, 'TKunde'), 'erst ab AFromLine');
  Assert.IsFalse(TClassBodies.HasTypeComment(Text, 0, 'TAnders'));
end;

initialization
  TDUnitX.RegisterTestFixture(TClassBodiesTests);

end.
