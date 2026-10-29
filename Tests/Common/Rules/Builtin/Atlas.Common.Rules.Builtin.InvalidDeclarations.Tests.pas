unit Atlas.Common.Rules.Builtin.InvalidDeclarations.Tests;

// Tests der Regel declaration-invalid (#1380): je Code der Fall aus
// Tests/Compilermeldungen (E2006, E2024, E2062, E2128, W1029) und Gegenfälle,
// die dcc ohne Meldung übersetzt; W1029 nur mit C++-Ausgabe im Projekt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationInvalidTests = class
  public
    [Test]
    procedure PackedBeforeTypeName;
    [Test]
    procedure FileAsFunctionResult;
    [Test]
    procedure VirtualConstructorInObject;
    [Test]
    procedure PropertyWithoutAccessor;
    [Test]
    procedure DuplicateConstructorWithCppOutput;
    [Test]
    procedure CppOutputFromProject;
    [Test]
    procedure ValidDeclarationsAreSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.InvalidDeclarations,
  Atlas.Tests.RuleAssert;

type
  /// <summary>Unit-Suche, die nur die .dproj liefert.</summary>
  TProjectOnly = class(TInterfacedObject, IRuleUnitLookup)
  private
    FText: string;
  public
    constructor Create(const AText: string);
    function Find(const AUnitName, AInPath, AFromFile: string; ASources: TRuleUnitSources): TRuleUnitAnswer;
    function FindPackage(const APackage: string): TRuleUnitAnswer;
    function FindFile(const AFileName, AFromFile: string): TRuleUnitAnswer;
    function KnownUnits(ASources: TRuleUnitSources): TArray<string>;
    function FolderOutsidePaths(const AUnitName: string): string;
    function ReadProject(out AFileName, AText: string): Boolean;
  end;

constructor TProjectOnly.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
end;

function TProjectOnly.Find(const AUnitName, AInPath, AFromFile: string; ASources: TRuleUnitSources): TRuleUnitAnswer;
begin
  Result := TRuleUnitAnswer.Unknown;
end;

function TProjectOnly.FindPackage(const APackage: string): TRuleUnitAnswer;
begin
  Result := TRuleUnitAnswer.Unknown;
end;

function TProjectOnly.FindFile(const AFileName, AFromFile: string): TRuleUnitAnswer;
begin
  Result := TRuleUnitAnswer.Unknown;
end;

function TProjectOnly.KnownUnits(ASources: TRuleUnitSources): TArray<string>;
begin
  Result := nil;
end;

function TProjectOnly.FolderOutsidePaths(const AUnitName: string): string;
begin
  Result := '';
end;

function TProjectOnly.ReadProject(out AFileName, AText: string): Boolean;
begin
  AFileName := 'C:\Projekt\Projekt.dproj';
  AText := FText;
  Result := FText <> '';
end;

function Findings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TDeclarationInvalidRule.Create, ASource);
end;

function ProjectFindings(const ASource, ADproj: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.UnitFindings(TDeclarationInvalidRule.Create, ASource, 'C:\Projekt\Fall.pas',
    TProjectOnly.Create(ADproj), '', '');
end;

/// <summary>Meldungen mit Zeile und Spalte, eine je Zeile.</summary>
function Listed(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
    Result := Result + Format('%d:%d %s', [mFinding.Range.StartPos.Line, mFinding.Range.StartPos.Character,
      mFinding.Message]) + #10;
end;

function InUnit(const AInterface, AImplementation: string): string;
begin
  Result := 'unit Fall;'#10'interface'#10 + AInterface + 'implementation'#10 + AImplementation + 'end.';
end;

const
  cCppProject = '<Project><PropertyGroup Condition="''$(Base)''!=''''">'#10 +
    '<DCC_AdditionalSwitches>-JPHNE</DCC_AdditionalSwitches></PropertyGroup></Project>';
  cDoppelt = 'type'#10'  TDoppelt = class'#10'  public'#10'    constructor Erzeugen(AWert: Integer);'#10 +
    '    constructor Anlegen(AWert: Integer);'#10'  end;'#10;

{ TDeclarationInvalidTests }

procedure TDeclarationInvalidTests.PackedBeforeTypeName;
begin
  // Cm.E2006
  Assert.AreEqual('3:13 packed gilt nur für array, record, object, class, set und file, nicht für Integer ' +
    '(wie E2006).'#10, Listed(Findings(InUnit('type'#10'  TGepackt = packed Integer;'#10, ''))));
  Assert.AreEqual('3:23 packed gilt nur für array, record, object, class, set und file, nicht für Byte ' +
    '(wie E2006).'#10, Listed(Findings(InUnit('var'#10'  GWert: { Kommentar } packed Byte;'#10, ''))));
end;

procedure TDeclarationInvalidTests.FileAsFunctionResult;
begin
  // Cm.E2024
  Assert.AreEqual('4:16 Datei kann keine Datei liefern; der Ergebnistyp file ist nicht erlaubt (wie E2024).'#10,
    Listed(Findings(InUnit('', #10'function Datei: file;'#10'begin'#10'end;'#10#10))));
end;

procedure TDeclarationInvalidTests.VirtualConstructorInObject;
begin
  // Cm.E2062
  Assert.AreEqual('4:22 Der Konstruktor Init eines object-Typs darf nicht virtual sein (wie E2062).'#10,
    Listed(Findings(InUnit('type'#10'  TAltObjekt = object'#10'    constructor Init; virtual;'#10 +
    '    procedure Zeigen; virtual;'#10'  end;'#10, ''))));
end;

procedure TDeclarationInvalidTests.PropertyWithoutAccessor;
begin
  // Cm.E2206 (Interface) und Cm.E2181 (automated): dcc meldet dazu E2128.
  Assert.AreEqual('9:13 Die Property Wert braucht read oder write; ein Interface kennt keine Property ohne ' +
    'Zugriff (wie E2128).'#10, Listed(Findings(InUnit('type'#10'  IBasis = interface'#10 +
    '    function GetWert: Integer;'#10'    property Wert: Integer read GetWert;'#10'  end;'#10#10 +
    '  IKind = interface(IBasis)'#10'    property Wert;'#10'  end;'#10, ''))));
  Assert.AreEqual('9:13 Die Property Wert im Abschnitt automated braucht read oder write (wie E2128).'#10,
    Listed(Findings(InUnit('type'#10'  TBasis = class'#10'  automated'#10'    property Wert: Integer read GetWert;'#10 +
    '  end;'#10'  TKind = class(TBasis)'#10'  automated'#10'    property Wert;'#10'  end;'#10, ''))));
end;

procedure TDeclarationInvalidTests.DuplicateConstructorWithCppOutput;
begin
  // Cm.W1029 mit -JPHNE; ohne C++-Ausgabe meldet dcc nichts.
  Assert.AreEqual('6:16 Die Konstruktoren Erzeugen und Anlegen haben dieselben Parametertypen; aus C++ ist ' +
    'Anlegen nicht erreichbar (wie W1029).'#10, Listed(ProjectFindings(InUnit(cDoppelt, ''), cCppProject)));
  Assert.AreEqual(0, Integer(Length(ProjectFindings(InUnit(cDoppelt, ''), '<Project></Project>'))));
  Assert.AreEqual(0, Integer(Length(Findings(InUnit(cDoppelt, '')))));
  // Andere Parametertypen oder var statt Wert: C++ unterscheidet sie.
  Assert.AreEqual(0, Integer(Length(ProjectFindings(InUnit('type'#10'  TZwei = class'#10 +
    '    constructor Erzeugen(AWert: Integer);'#10'    constructor Anlegen(AWert: string);'#10 +
    '    constructor Holen(var AWert: Integer);'#10'    class constructor Init;'#10'  end;'#10, ''),
    cCppProject))));
end;

procedure TDeclarationInvalidTests.CppOutputFromProject;
begin
  Assert.IsTrue(TDeclarationInvalidRule.CppOutput('<DCC_CBuilderOutput>All</DCC_CBuilderOutput>'));
  Assert.IsTrue(TDeclarationInvalidRule.CppOutput('<DCC_AdditionalSwitches>--doc -JL</DCC_AdditionalSwitches>'));
  Assert.IsFalse(TDeclarationInvalidRule.CppOutput('<DCC_CBuilderOutput>None</DCC_CBuilderOutput>'));
  Assert.IsFalse(TDeclarationInvalidRule.CppOutput('<DCC_AdditionalSwitches>--doc</DCC_AdditionalSwitches>'));
  Assert.IsFalse(TDeclarationInvalidRule.CppOutput(''));
end;

procedure TDeclarationInvalidTests.ValidDeclarationsAreSilent;
begin
  TRuleAssert.Silent(TDeclarationInvalidRule.Create, InUnit('type'#10 +
    '  TA = packed array[0..1] of Byte;'#10'  TB = packed record X: Byte; end;'#10'  TC = packed set of Byte;'#10 +
    '  TD = packed file of Byte;'#10'  TE = packed class end;'#10'  TF = packed object end;'#10 +
    '  TG = packed string[5];'#10 +
    '  TAltObjekt = object'#10'    constructor Init;'#10'    procedure Zeigen; virtual;'#10'  end;'#10 +
    '  IBasis = interface'#10'    function GetWert: Integer;'#10'    property Wert: Integer read GetWert;'#10 +
    '  end;'#10'  IDisp = dispinterface'#10'    property Wert: Integer dispid 1;'#10'  end;'#10 +
    '  TKlasse = class(TBasis)'#10'  published'#10'    property Wert;'#10'  end;'#10 +
    'function Liefere(var AWert: file): Integer;'#10 + cDoppelt, ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationInvalidTests);

end.
