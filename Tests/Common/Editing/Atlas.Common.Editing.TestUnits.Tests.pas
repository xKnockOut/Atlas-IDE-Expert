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
  cKundenText =
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
  Result := TIndexExtractor.ExtractText(cKundenText, 'C:\Projekt\Kunden.pas', nil);
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
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
  mName: string;
begin
  Assert.IsTrue(TTestUnits.TestedUnitName('Kunden.Tests', '{unit}.Tests', mName));
  Assert.AreEqual('Kunden', mName);
  Assert.IsTrue(TTestUnits.TestedUnitName('kunden.logik.tests', '{unit}.Tests', mName), 'ohne Groß/klein');
  Assert.AreEqual('kunden.logik', mName);
  Assert.IsTrue(TTestUnits.TestedUnitName('Test.Kunden', 'Test.{unit}', mName));
  Assert.AreEqual('Kunden', mName);
  Assert.IsFalse(TTestUnits.TestedUnitName('Kunden', '{unit}.Tests', mName));
  Assert.IsFalse(TTestUnits.TestedUnitName('.Tests', '{unit}.Tests', mName), 'leerer Name');
end;

procedure TTestUnitsTests.FixtureNames;
begin
  Assert.AreEqual('TKundeTests', TTestUnits.FixtureName('TKunde', 'Kunden'));
  Assert.AreEqual('TTabelleTests', TTestUnits.FixtureName('Tabelle', 'Kunden'));
  Assert.AreEqual('TLogikTests', TTestUnits.FixtureName('', 'Kunden.Logik'));
end;

procedure TTestUnitsTests.ClassAtDeclarationAndMethod;
var
  mIndex: TUnitIndex;
begin
  mIndex := KundenIndex;
  Assert.AreEqual('TKunde', TTestUnits.ClassAt(mIndex, 3), 'Kopf der Klasse');
  Assert.AreEqual('TKunde', TTestUnits.ClassAt(mIndex, 12), 'Methode in der Deklaration');
  Assert.AreEqual('TAuftrag', TTestUnits.ClassAt(mIndex, 17));
  Assert.AreEqual('', TTestUnits.ClassAt(mIndex, 1), 'interface');
  Assert.AreEqual('TKunde', TTestUnits.ClassAt(mIndex, 37), 'Rumpf von TKunde.Rabatt');
  Assert.AreEqual('TAuftrag', TTestUnits.ClassAt(mIndex, 49), 'Rumpf von TAuftrag.Buchen');
  Assert.AreEqual('TKunde', TTestUnits.FirstClass(mIndex));
end;

procedure TTestUnitsTests.MethodsPublicOnlyAndOverloadsNumbered;
var
  mMethods: TArray<TTestUnitMethod>;
begin
  mMethods := TTestUnits.TestMethods(KundenIndex, 'TKunde');
  // Ohne Konstruktor, Destroy und private Intern.
  Assert.AreEqual(3, Integer(Length(mMethods)));
  Assert.AreEqual('TestRabatt', mMethods[0].Name);
  Assert.AreEqual('TKunde.Rabatt', mMethods[0].Target);
  Assert.AreEqual('TestRabatt2', mMethods[1].Name);
  Assert.AreEqual('TestSpeichern', mMethods[2].Name);
end;

procedure TTestUnitsTests.RoutinesWithoutClass;
const
  cText = 'unit Werkzeug;'#10'interface'#10'function Summe(A, B: Integer): Integer;'#10 +
    'procedure Leeren;'#10'implementation'#10'function Summe(A, B: Integer): Integer;'#10'begin'#10 +
    '  Result := A + B;'#10'end;'#10'procedure Leeren;'#10'begin'#10'end;'#10'procedure Intern;'#10 +
    'begin'#10'end;'#10'end.';
var
  mIndex: TUnitIndex;
  mMethods: TArray<TTestUnitMethod>;
  mUnit_: string;
begin
  mIndex := TIndexExtractor.ExtractText(cText, 'Werkzeug.pas', nil);
  mMethods := TTestUnits.TestMethods(mIndex, '');
  Assert.AreEqual(2, Integer(Length(mMethods)));
  Assert.AreEqual('TestSumme', mMethods[0].Name);
  Assert.AreEqual('TestLeeren', mMethods[1].Name);
  mUnit_ := TTestUnits.UnitText('Werkzeug.Tests', mIndex, '', #13#10);
  Assert.IsTrue(Parses(mUnit_), mUnit_);
  Assert.IsTrue(Pos('TWerkzeugTests = class', mUnit_) > 0, mUnit_);
  Assert.AreEqual(0, Pos('FSubject', mUnit_), mUnit_);
end;

procedure TTestUnitsTests.CreateExpressions;
const
  cText = 'unit U;'#10'interface'#10'type'#10 +
    '  TOhne = class end;'#10 +
    '  TMitArg = class public constructor Create(AName: string); end;'#10 +
    '  TOwner = class public constructor Create(AOwner: TComponent); end;'#10 +
    '  TListe<T> = class end;'#10 +
    'implementation'#10'end.';
var
  mIndex: TUnitIndex;
begin
  mIndex := TIndexExtractor.ExtractText(cText, 'U.pas', nil);
  Assert.AreEqual('TOhne.Create', TTestUnits.CreateExpression(mIndex, 'TOhne'));
  Assert.AreEqual('', TTestUnits.CreateExpression(mIndex, 'TMitArg'));
  Assert.AreEqual('TOwner.Create(nil)', TTestUnits.CreateExpression(mIndex, 'TOwner'));
  Assert.AreEqual('', TTestUnits.CreateExpression(mIndex, 'TListe'));
  Assert.AreEqual('TKunde.Create', TTestUnits.CreateExpression(KundenIndex, 'TKunde'));
  Assert.AreEqual('TAuftrag.Create(nil)', TTestUnits.CreateExpression(KundenIndex, 'TAuftrag'), 'Komponente');
end;

procedure TTestUnitsTests.UnitTextParsesWithFixture;
var
  mText: string;
begin
  mText := TTestUnits.UnitText('Kunden.Tests', KundenIndex, 'TKunde', #13#10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(mText.StartsWith('unit Kunden.Tests;'#13#10), mText);
  Assert.IsTrue(Pos('uses'#13#10'  DUnitX.TestFramework,'#13#10'  Kunden;', mText) > 0, mText);
  Assert.IsTrue(Pos('  [TestFixture]'#13#10'  TKundeTests = class', mText) > 0, mText);
  Assert.IsTrue(Pos('    FSubject: TKunde;', mText) > 0, mText);
  Assert.IsTrue(Pos('    [Setup]'#13#10'    procedure Setup;', mText) > 0, mText);
  Assert.IsTrue(Pos('    [TearDown]'#13#10'    procedure TearDown;', mText) > 0, mText);
  Assert.IsTrue(Pos('    [Test]'#13#10'    procedure TestRabatt2;', mText) > 0, mText);
  Assert.IsTrue(Pos('  FSubject := TKunde.Create;', mText) > 0, mText);
  Assert.IsTrue(Pos('  FSubject.Free;', mText) > 0, mText);
  Assert.IsTrue(Pos('  Assert.Fail(''Test für TKunde.Speichern fehlt noch'');', mText) > 0, mText);
  Assert.IsTrue(Pos('initialization'#13#10'  TDUnitX.RegisterTestFixture(TKundeTests);', mText) > 0, mText);
  Assert.IsTrue(mText.EndsWith('end.'#13#10), mText);
end;

procedure TTestUnitsTests.UnitTextWithoutCreatableSubject;
const
  cText = 'unit U;'#10'interface'#10'type'#10 +
    '  TMitArg = class public constructor Create(AName: string); procedure Tu; end;'#10 +
    'implementation'#10'end.';
var
  mUnit_: string;
begin
  mUnit_ := TTestUnits.UnitText('U.Tests', TIndexExtractor.ExtractText(cText, 'U.pas', nil), 'TMitArg', #10);
  Assert.IsTrue(Parses(mUnit_), mUnit_);
  Assert.IsTrue(Pos('// TMitArg braucht Argumente im Konstruktor', mUnit_) > 0, mUnit_);
  Assert.AreEqual(0, Pos('FSubject := TMitArg', mUnit_), mUnit_);
end;

procedure TTestUnitsTests.TestProgramDetected;
const
  cTestProgram = 'program Tests;'#10'{$APPTYPE CONSOLE}'#10'uses'#10'  DUnitX.TestFramework,'#10 +
    '  DUnitX.Loggers.Console;'#10'begin'#10'end.';
  cApp = 'program App;'#10'uses'#10'  Vcl.Forms;'#10'begin'#10'end.';
  cTestUnit = 'unit X.Tests;'#10'interface'#10'uses DUnitX.TestFramework;'#10'implementation'#10'end.';
var
  mFound: string;
begin
  Assert.IsTrue(TTestUnits.IsTestProgram(cTestProgram));
  Assert.IsFalse(TTestUnits.IsTestProgram(cApp));
  Assert.IsFalse(TTestUnits.IsTestProgram(cTestUnit), 'eine Unit ist kein Programm');
  mFound := TTestUnits.FindTestProgram(['C:\P\App.dpr', 'C:\P\App.dproj', 'C:\P\Tests\Tests.dpr'],
    function(const AFileName: string): string
    begin
      if AFileName = 'C:\P\Tests\Tests.dpr' then
      begin
        Result := cTestProgram;
      end
      else
      begin
        Result := cApp;
      end;
    end);
  Assert.AreEqual('C:\P\Tests\Tests.dpr', mFound);
end;

procedure TTestUnitsTests.RelativePaths;
begin
  Assert.AreEqual('Kunden.Tests.pas', TTestUnits.RelativePath('C:\P\Tests\', 'C:\P\Tests\Kunden.Tests.pas'));
  Assert.AreEqual('Unit\Kunden.Tests.pas', TTestUnits.RelativePath('C:\P\Tests', 'C:\P\Tests\Unit\Kunden.Tests.pas'));
  Assert.AreEqual('..\Quelle\Kunden.pas', TTestUnits.RelativePath('C:\P\Tests\', 'c:\p\Quelle\Kunden.pas'));
  Assert.AreEqual('D:\Anders\K.pas', TTestUnits.RelativePath('C:\P\Tests\', 'D:\Anders\K.pas'));
end;

end.
