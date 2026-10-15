unit Atlas.Common.Editing.TestUnits.Tests;

// Tests für das DUnitX-Testgerüst (#274) und die Namen von Unit und Testunit (#189).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnitsTests = class
  public
    [Test]
    procedure NamesFollowPattern;
    [Test]
    procedure TestedNameOnlyForMatchingPattern;
    [Test]
    procedure FixtureNames;
    [Test]
    procedure ClassAtDeclarationAndMethod;
    [Test]
    procedure MethodsPublicOnlyAndOverloadsNumbered;
    [Test]
    procedure RoutinesWithoutClass;
    [Test]
    procedure CreateExpressions;
    [Test]
    procedure UnitTextParsesWithFixture;
    [Test]
    procedure UnitTextWithoutCreatableSubject;
    [Test]
    procedure TestProgramDetected;
    [Test]
    procedure RelativePaths;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.TestUnits;

const
  KundenText =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    procedure Intern;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '    function Rabatt(AWert: Currency): Currency; overload;'#10 +
    '    function Rabatt(AWert: Currency; AStufe: Integer): Currency; overload;'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    #10 +
    '  TAuftrag = class(TComponent)'#10 +
    '  public'#10 +
    '    procedure Buchen;'#10 +
    '  end;'#10 +
    #10 +
    'implementation'#10 +
    #10 +
    'constructor TKunde.Create;'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'destructor TKunde.Destroy;'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'procedure TKunde.Intern;'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'function TKunde.Rabatt(AWert: Currency): Currency;'#10 +
    'begin'#10 +
    '  Result := AWert;'#10 +
    'end;'#10 +
    #10 +
    'function TKunde.Rabatt(AWert: Currency; AStufe: Integer): Currency;'#10 +
    'begin'#10 +
    '  Result := AWert * AStufe;'#10 +
    'end;'#10 +
    #10 +
    'procedure TKunde.Speichern;'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'procedure TAuftrag.Buchen;'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'end.';

function KundenIndex: TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(KundenText, 'C:\Projekt\Kunden.pas', nil);
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

procedure TTestUnitsTests.NamesFollowPattern;
begin
  Assert.AreEqual('Kunden.Tests', TTestUnits.TestUnitName('Kunden', '{unit}.Tests'));
  Assert.AreEqual('Test.Kunden', TTestUnits.TestUnitName('Kunden', 'Test.{unit}'));
  // Ohne {unit} gilt die Vorgabe.
  Assert.AreEqual('Kunden.Tests', TTestUnits.TestUnitName('Kunden', ''));
  Assert.AreEqual('Kunden.Tests', TTestUnits.TestUnitName('Kunden', 'Tests'));
end;

procedure TTestUnitsTests.TestedNameOnlyForMatchingPattern;
var
  Name: string;
begin
  Assert.IsTrue(TTestUnits.TestedUnitName('Kunden.Tests', '{unit}.Tests', Name));
  Assert.AreEqual('Kunden', Name);
  Assert.IsTrue(TTestUnits.TestedUnitName('kunden.logik.tests', '{unit}.Tests', Name), 'ohne Groß/klein');
  Assert.AreEqual('kunden.logik', Name);
  Assert.IsTrue(TTestUnits.TestedUnitName('Test.Kunden', 'Test.{unit}', Name));
  Assert.AreEqual('Kunden', Name);
  Assert.IsFalse(TTestUnits.TestedUnitName('Kunden', '{unit}.Tests', Name));
  Assert.IsFalse(TTestUnits.TestedUnitName('.Tests', '{unit}.Tests', Name), 'leerer Name');
end;

procedure TTestUnitsTests.FixtureNames;
begin
  Assert.AreEqual('TKundeTests', TTestUnits.FixtureName('TKunde', 'Kunden'));
  Assert.AreEqual('TTabelleTests', TTestUnits.FixtureName('Tabelle', 'Kunden'));
  Assert.AreEqual('TLogikTests', TTestUnits.FixtureName('', 'Kunden.Logik'));
end;

procedure TTestUnitsTests.ClassAtDeclarationAndMethod;
var
  Index: TUnitIndex;
begin
  Index := KundenIndex;
  Assert.AreEqual('TKunde', TTestUnits.ClassAt(Index, 3), 'Kopf der Klasse');
  Assert.AreEqual('TKunde', TTestUnits.ClassAt(Index, 12), 'Methode in der Deklaration');
  Assert.AreEqual('TAuftrag', TTestUnits.ClassAt(Index, 17));
  Assert.AreEqual('', TTestUnits.ClassAt(Index, 1), 'interface');
  Assert.AreEqual('TKunde', TTestUnits.ClassAt(Index, 37), 'Rumpf von TKunde.Rabatt');
  Assert.AreEqual('TAuftrag', TTestUnits.ClassAt(Index, 49), 'Rumpf von TAuftrag.Buchen');
  Assert.AreEqual('TKunde', TTestUnits.FirstClass(Index));
end;

procedure TTestUnitsTests.MethodsPublicOnlyAndOverloadsNumbered;
var
  Methods: TArray<TTestUnitMethod>;
begin
  Methods := TTestUnits.TestMethods(KundenIndex, 'TKunde');
  // Ohne Konstruktor, Destroy und private Intern.
  Assert.AreEqual(3, Integer(Length(Methods)));
  Assert.AreEqual('TestRabatt', Methods[0].Name);
  Assert.AreEqual('TKunde.Rabatt', Methods[0].Target);
  Assert.AreEqual('TestRabatt2', Methods[1].Name);
  Assert.AreEqual('TestSpeichern', Methods[2].Name);
end;

procedure TTestUnitsTests.RoutinesWithoutClass;
const
  Text = 'unit Werkzeug;'#10'interface'#10'function Summe(A, B: Integer): Integer;'#10 +
    'procedure Leeren;'#10'implementation'#10'function Summe(A, B: Integer): Integer;'#10'begin'#10 +
    '  Result := A + B;'#10'end;'#10'procedure Leeren;'#10'begin'#10'end;'#10'procedure Intern;'#10 +
    'begin'#10'end;'#10'end.';
var
  Index: TUnitIndex;
  Methods: TArray<TTestUnitMethod>;
  Unit_: string;
begin
  Index := TIndexExtractor.ExtractText(Text, 'Werkzeug.pas', nil);
  Methods := TTestUnits.TestMethods(Index, '');
  Assert.AreEqual(2, Integer(Length(Methods)));
  Assert.AreEqual('TestSumme', Methods[0].Name);
  Assert.AreEqual('TestLeeren', Methods[1].Name);
  Unit_ := TTestUnits.UnitText('Werkzeug.Tests', Index, '', #13#10);
  Assert.IsTrue(Parses(Unit_), Unit_);
  Assert.IsTrue(Pos('TWerkzeugTests = class', Unit_) > 0, Unit_);
  Assert.IsTrue(Pos('FSubject', Unit_) = 0, Unit_);
end;

procedure TTestUnitsTests.CreateExpressions;
const
  Text = 'unit U;'#10'interface'#10'type'#10 +
    '  TOhne = class end;'#10 +
    '  TMitArg = class public constructor Create(AName: string); end;'#10 +
    '  TOwner = class public constructor Create(AOwner: TComponent); end;'#10 +
    '  TListe<T> = class end;'#10 +
    'implementation'#10'end.';
var
  Index: TUnitIndex;
begin
  Index := TIndexExtractor.ExtractText(Text, 'U.pas', nil);
  Assert.AreEqual('TOhne.Create', TTestUnits.CreateExpression(Index, 'TOhne'));
  Assert.AreEqual('', TTestUnits.CreateExpression(Index, 'TMitArg'));
  Assert.AreEqual('TOwner.Create(nil)', TTestUnits.CreateExpression(Index, 'TOwner'));
  Assert.AreEqual('', TTestUnits.CreateExpression(Index, 'TListe'));
  Assert.AreEqual('TKunde.Create', TTestUnits.CreateExpression(KundenIndex, 'TKunde'));
  Assert.AreEqual('TAuftrag.Create(nil)', TTestUnits.CreateExpression(KundenIndex, 'TAuftrag'), 'Komponente');
end;

procedure TTestUnitsTests.UnitTextParsesWithFixture;
var
  Text: string;
begin
  Text := TTestUnits.UnitText('Kunden.Tests', KundenIndex, 'TKunde', #13#10);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(Text.StartsWith('unit Kunden.Tests;'#13#10), Text);
  Assert.IsTrue(Pos('uses'#13#10'  DUnitX.TestFramework,'#13#10'  Kunden;', Text) > 0, Text);
  Assert.IsTrue(Pos('  [TestFixture]'#13#10'  TKundeTests = class', Text) > 0, Text);
  Assert.IsTrue(Pos('    FSubject: TKunde;', Text) > 0, Text);
  Assert.IsTrue(Pos('    [Setup]'#13#10'    procedure Setup;', Text) > 0, Text);
  Assert.IsTrue(Pos('    [TearDown]'#13#10'    procedure TearDown;', Text) > 0, Text);
  Assert.IsTrue(Pos('    [Test]'#13#10'    procedure TestRabatt2;', Text) > 0, Text);
  Assert.IsTrue(Pos('  FSubject := TKunde.Create;', Text) > 0, Text);
  Assert.IsTrue(Pos('  FSubject.Free;', Text) > 0, Text);
  Assert.IsTrue(Pos('  Assert.Fail(''Test für TKunde.Speichern fehlt noch'');', Text) > 0, Text);
  Assert.IsTrue(Pos('initialization'#13#10'  TDUnitX.RegisterTestFixture(TKundeTests);', Text) > 0, Text);
  Assert.IsTrue(Text.EndsWith('end.'#13#10), Text);
end;

procedure TTestUnitsTests.UnitTextWithoutCreatableSubject;
const
  Text = 'unit U;'#10'interface'#10'type'#10 +
    '  TMitArg = class public constructor Create(AName: string); procedure Tu; end;'#10 +
    'implementation'#10'end.';
var
  Unit_: string;
begin
  Unit_ := TTestUnits.UnitText('U.Tests', TIndexExtractor.ExtractText(Text, 'U.pas', nil), 'TMitArg', #10);
  Assert.IsTrue(Parses(Unit_), Unit_);
  Assert.IsTrue(Pos('// TMitArg braucht Argumente im Konstruktor', Unit_) > 0, Unit_);
  Assert.IsTrue(Pos('FSubject := TMitArg', Unit_) = 0, Unit_);
end;

procedure TTestUnitsTests.TestProgramDetected;
const
  TestProgram = 'program Tests;'#10'{$APPTYPE CONSOLE}'#10'uses'#10'  DUnitX.TestFramework,'#10 +
    '  DUnitX.Loggers.Console;'#10'begin'#10'end.';
  App = 'program App;'#10'uses'#10'  Vcl.Forms;'#10'begin'#10'end.';
  TestUnit = 'unit X.Tests;'#10'interface'#10'uses DUnitX.TestFramework;'#10'implementation'#10'end.';
var
  Found: string;
begin
  Assert.IsTrue(TTestUnits.IsTestProgram(TestProgram));
  Assert.IsFalse(TTestUnits.IsTestProgram(App));
  Assert.IsFalse(TTestUnits.IsTestProgram(TestUnit), 'eine Unit ist kein Programm');
  Found := TTestUnits.FindTestProgram(['C:\P\App.dpr', 'C:\P\App.dproj', 'C:\P\Tests\Tests.dpr'],
    function(const AFileName: string): string
    begin
      if AFileName = 'C:\P\Tests\Tests.dpr' then
        Result := TestProgram
      else
        Result := App;
    end);
  Assert.AreEqual('C:\P\Tests\Tests.dpr', Found);
end;

procedure TTestUnitsTests.RelativePaths;
begin
  Assert.AreEqual('Kunden.Tests.pas', TTestUnits.RelativePath('C:\P\Tests\', 'C:\P\Tests\Kunden.Tests.pas'));
  Assert.AreEqual('Unit\Kunden.Tests.pas', TTestUnits.RelativePath('C:\P\Tests', 'C:\P\Tests\Unit\Kunden.Tests.pas'));
  Assert.AreEqual('..\Quelle\Kunden.pas', TTestUnits.RelativePath('C:\P\Tests\', 'c:\p\Quelle\Kunden.pas'));
  Assert.AreEqual('D:\Anders\K.pas', TTestUnits.RelativePath('C:\P\Tests\', 'D:\Anders\K.pas'));
end;

end.
