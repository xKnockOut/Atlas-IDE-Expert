unit Atlas.Common.Lsp.InterfaceMethods.Tests;

// Erfüllte Interface-Methoden je Methodendeklaration (#1785): Interfaces mit
// Vorfahren, Zuordnungen, Überladungen, Vorfahrklassen nur mit override.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.InterfaceMethods;

type
  [TestFixture]
  TLspInterfaceMethodsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Describe(const AText, AFileName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MarksMethodsWithInheritedInterfaces;
    [Test]
    procedure HonoursResolutionClauses;
    [Test]
    procedure PicksOverloadByParameters;
    [Test]
    procedure AncestorInterfacesOnlyWithOverride;
    [Test]
    procedure WritesJson;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cApiFile = 'C:\P\KundenApi.pas';
  cKundenFile = 'C:\P\Kunden.pas';
  cSohnFile = 'C:\P\Sohn.pas';

  cUnitApi =
    'unit KundenApi;'#10 +                                        // 0
    'interface'#10 +                                              // 1
    'type'#10 +                                                   // 2
    '  IBasis = interface'#10 +                                   // 3
    '    procedure Pruefe;'#10 +                                  // 4
    '  end;'#10 +                                                 // 5
    '  IKunde = interface(IBasis)'#10 +                           // 6
    '    procedure Speichern;'#10 +                               // 7
    '    function Name: string;'#10 +                             // 8
    '  end;'#10 +                                                 // 9
    '  IDruck = interface'#10 +                                   // 10
    '    procedure Drucke(const AText: string); overload;'#10 +   // 11
    '    procedure Drucke(ASeite: Integer); overload;'#10 +       // 12
    '    procedure Speichern;'#10 +                               // 13
    '  end;'#10 +                                                 // 14
    'implementation'#10 +                                         // 15
    'end.';

  cUnitKunden =
    'unit Kunden;'#10 +                                           // 0
    'interface'#10 +                                              // 1
    'uses KundenApi;'#10 +                                        // 2
    'type'#10 +                                                   // 3
    '  TKunde = class(TInterfacedObject, IKunde, IDruck)'#10 +    // 4
    '    procedure IDruck.Speichern = Sichern;'#10 +              // 5
    '    procedure Pruefe;'#10 +                                  // 6
    '    procedure Speichern; virtual;'#10 +                      // 7
    '    procedure Sichern;'#10 +                                 // 8
    '    function Name: string;'#10 +                             // 9
    '    procedure Drucke(ASeite: Integer); overload;'#10 +       // 10
    '    procedure Drucke(const AText: string); overload;'#10 +   // 11
    '    procedure Hilfe;'#10 +                                   // 12
    '  end;'#10 +                                                 // 13
    'implementation'#10 +                                         // 14
    'procedure TKunde.Pruefe;'#10 +                               // 15
    'begin'#10 +                                                  // 16
    'end;'#10 +                                                   // 17
    'procedure TKunde.Speichern;'#10 +                            // 18
    'begin'#10 +                                                  // 19
    'end;'#10 +                                                   // 20
    'procedure TKunde.Sichern;'#10 +                              // 21
    'begin'#10 +                                                  // 22
    'end;'#10 +                                                   // 23
    'function TKunde.Name: string;'#10 +                          // 24
    'begin'#10 +                                                  // 25
    'end;'#10 +                                                   // 26
    'procedure TKunde.Drucke(ASeite: Integer);'#10 +              // 27
    'begin'#10 +                                                  // 28
    'end;'#10 +                                                   // 29
    'procedure TKunde.Drucke(const AText: string);'#10 +          // 30
    'begin'#10 +                                                  // 31
    'end;'#10 +                                                   // 32
    'procedure TKunde.Hilfe;'#10 +                                // 33
    'begin'#10 +                                                  // 34
    'end;'#10 +                                                   // 35
    'end.';

  cUnitSohn =
    'unit Sohn;'#10 +                                             // 0
    'interface'#10 +                                              // 1
    'uses Kunden;'#10 +                                           // 2
    'type'#10 +                                                   // 3
    '  TSohn = class(TKunde)'#10 +                                // 4
    '    procedure Speichern; override;'#10 +                     // 5
    '    function Name: string;'#10 +                             // 6
    '  end;'#10 +                                                 // 7
    'implementation'#10 +                                         // 8
    'procedure TSohn.Speichern;'#10 +                             // 9
    'begin'#10 +                                                  // 10
    'end;'#10 +                                                   // 11
    'function TSohn.Name: string;'#10 +                           // 12
    'begin'#10 +                                                  // 13
    'end;'#10 +                                                   // 14
    'end.';

{ TLspInterfaceMethodsTests }

procedure TLspInterfaceMethodsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitApi, cApiFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKunden, cKundenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitSohn, cSohnFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspInterfaceMethodsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspInterfaceMethodsTests.Describe(const AText, AFileName: string): string;
var
  mTree: TSyntaxTree;
  mMark: TInterfaceMethodMark;
  mTarget: TInterfaceMethodTarget;
begin
  Result := '';
  mTree := TPascalParser.Parse(AText);
  try
    for mMark in TLspInterfaceMethods.Marks(FResolver, mTree, AFileName) do
    begin
      Result := Result + IntToStr(mMark.Line) + ' ' + mMark.Name;
      for mTarget in mMark.Targets do
      begin
        Result := Result + Format(' %s@%s:%d', [mTarget.Name, mTarget.UnitName, mTarget.Range.StartPos.Line]);
      end;
      Result := Result + '|';
    end;
  finally
    mTree.Free;
  end;
end;

procedure TLspInterfaceMethodsTests.MarksMethodsWithInheritedInterfaces;
var
  mText: string;
begin
  mText := Describe(cUnitKunden, cKundenFile);
  // Pruefe kommt aus IBasis, dem Vorfahren von IKunde; nur Deklarationen, keine Rümpfe; Hilfe hat keins.
  Assert.Contains(mText, '6 TKunde.Pruefe IBasis.Pruefe@KundenApi:4|');
  Assert.Contains(mText, '9 TKunde.Name IKunde.Name@KundenApi:8|');
  Assert.DoesNotContain(mText, 'Hilfe');
  Assert.DoesNotContain(mText, '|15 ');
end;

procedure TLspInterfaceMethodsTests.HonoursResolutionClauses;
var
  mText: string;
begin
  mText := Describe(cUnitKunden, cKundenFile);
  // IDruck.Speichern = Sichern: Speichern erfüllt nur IKunde, Sichern erfüllt IDruck.Speichern.
  Assert.Contains(mText, '7 TKunde.Speichern IKunde.Speichern@KundenApi:7|');
  Assert.Contains(mText, '8 TKunde.Sichern IDruck.Speichern@KundenApi:13|');
end;

procedure TLspInterfaceMethodsTests.PicksOverloadByParameters;
var
  mText: string;
begin
  mText := Describe(cUnitKunden, cKundenFile);
  Assert.Contains(mText, '10 TKunde.Drucke IDruck.Drucke@KundenApi:12|');
  Assert.Contains(mText, '11 TKunde.Drucke IDruck.Drucke@KundenApi:11|');
end;

procedure TLspInterfaceMethodsTests.AncestorInterfacesOnlyWithOverride;
begin
  // Speichern überschreibt und erfüllt so IKunde.Speichern weiter; Name verdeckt nur.
  Assert.AreEqual('5 TSohn.Speichern IKunde.Speichern@KundenApi:7|', Describe(cUnitSohn, cSohnFile));
end;

procedure TLspInterfaceMethodsTests.WritesJson;
var
  mTree: TSyntaxTree;
  mJson: TJSONObject;
  mMethod, mTarget: TJSONObject;
begin
  mTree := TPascalParser.Parse(cUnitSohn);
  try
    mJson := TLspInterfaceMethods.Json(TLspInterfaceMethods.Marks(FResolver, mTree, cSohnFile));
    try
      mMethod := (mJson.GetValue('methods') as TJSONArray).Items[0] as TJSONObject;
      Assert.AreEqual(5, mMethod.GetValue<Integer>('line'));
      Assert.AreEqual('TSohn.Speichern', mMethod.GetValue<string>('name'));
      mTarget := (mMethod.GetValue('interfaces') as TJSONArray).Items[0] as TJSONObject;
      Assert.AreEqual('IKunde.Speichern', mTarget.GetValue<string>('name'));
      Assert.AreEqual('KundenApi', mTarget.GetValue<string>('unit'));
      Assert.AreEqual(7, mTarget.GetValue<Integer>('line'));
      Assert.AreEqual(14, mTarget.GetValue<Integer>('character'));
      Assert.IsTrue(mTarget.GetValue<string>('uri').EndsWith('KundenApi.pas'));
    finally
      mJson.Free;
    end;
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInterfaceMethodsTests);

end.
