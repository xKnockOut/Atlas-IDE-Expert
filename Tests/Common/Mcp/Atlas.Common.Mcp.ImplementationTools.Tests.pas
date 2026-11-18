unit Atlas.Common.Mcp.ImplementationTools.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Mcp.ImplementationTools;

type
  [TestFixture]
  TMcpImplementationToolsTests = class
  private
    FTools: TMcpImplementationTools;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ListsInterfaceImplementationsWithKinds;
    [Test]
    procedure MarksTestUnits;
    [Test]
    procedure ListsVirtualOverridesAndAbstract;
    [Test]
    procedure ListsImplementingClassesOfType;
    [Test]
    procedure IncludeBodyShortensLongBodies;
    [Test]
    procedure JsonHasFormatLinesFromOneAndKinds;
    [Test]
    procedure AmbiguousNameListsCandidates;
    [Test]
    procedure UnknownNameGivesHint;
    [Test]
    procedure StaticMethodGivesNote;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Impact;

const
  cApiFile = 'C:\P\Api.pas';
  cTestFile = 'C:\P\Api.Tests.pas';
  cOtherFile = 'C:\P\Andere.pas';
  cApiUnit =
    'unit Api;'#10 +                                       // 1
    'interface'#10 +                                       // 2
    'type'#10 +                                            // 3
    '  IHost = interface'#10 +                             // 4
    '    procedure Run;'#10 +                              // 5
    '  end;'#10 +                                          // 6
    '  THost = class(TInterfacedObject, IHost)'#10 +      // 7
    '    procedure Run; virtual;'#10 +                     // 8
    '    procedure Fest;'#10 +                             // 9
    '    procedure Lang; virtual; abstract;'#10 +          // 10
    '  end;'#10 +                                          // 11
    '  TSpezial = class(THost)'#10 +                       // 12
    '    procedure Run; override;'#10 +                    // 13
    '    procedure Lang; override;'#10 +                   // 14
    '  end;'#10 +                                          // 15
    'implementation'#10 +                                  // 16
    'procedure THost.Run;'#10 +                            // 17
    'begin'#10 +                                           // 18
    'end;'#10 +                                            // 19
    'procedure THost.Fest;'#10 +                           // 20
    'begin'#10 +                                           // 21
    'end;'#10 +                                            // 22
    'procedure TSpezial.Run;'#10 +                         // 23
    'begin'#10 +                                           // 24
    '  inherited;'#10 +                                    // 25
    'end;'#10 +                                            // 26
    'procedure TSpezial.Lang;'#10 +                        // 27
    'begin'#10 +                                           // 28
    '  Schritt(1);'#10 + '  Schritt(2);'#10 + '  Schritt(3);'#10 + '  Schritt(4);'#10 + '  Schritt(5);'#10 +
    '  Schritt(6);'#10 + '  Schritt(7);'#10 + '  Schritt(8);'#10 + '  Schritt(9);'#10 + '  Schritt(10);'#10 +
    '  Schritt(11);'#10 + '  Schritt(12);'#10 + '  Schritt(13);'#10 + '  Schritt(14);'#10 + '  Schritt(15);'#10 +
    '  Schritt(16);'#10 + '  Schritt(17);'#10 + '  Schritt(18);'#10 + '  Schritt(19);'#10 + '  Schritt(20);'#10 +
    'end;'#10 +
    'end.';
  cTestUnit =
    'unit Api.Tests;'#10 +
    'interface'#10 +
    'uses Api;'#10 +
    'type'#10 +
    '  TFakeHost = class(TInterfacedObject, IHost)'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFakeHost.Run;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  cOtherUnit =
    'unit Andere;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAnderer = class'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TAnderer.Run;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cApiFile) then
  begin
    AText := cApiUnit;
  end
  else if SameText(AFileName, cTestFile) then
  begin
    AText := cTestUnit;
  end
  else if SameText(AFileName, cOtherFile) then
  begin
    AText := cOtherUnit;
  end
  else
  begin
    Result := False;
  end;
end;

function TestScope(const AUri: string): TImpactOptions;
begin
  Result := TImpactOptions.Default;
  Result.Tests.Units := ['Api.Tests'];
end;

{ TMcpImplementationToolsTests }

procedure TMcpImplementationToolsTests.Setup;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cApiUnit, cApiFile, nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cTestUnit, cTestFile, nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cOtherUnit, cOtherFile, nil));
  FTools := TMcpImplementationTools.Create(mIndex, ReadText);
end;

procedure TMcpImplementationToolsTests.TearDown;
begin
  FreeAndNil(FTools);
end;

procedure TMcpImplementationToolsTests.ListsInterfaceImplementationsWithKinds;
var
  mText: string;
begin
  mText := FTools.Find('IHost.Run', False, False);
  Assert.Contains(mText, '3 Umsetzungen von IHost.Run');
  Assert.Contains(mText, 'THost.Run  ' + cApiFile + ':17  «umgesetzt»');
  Assert.Contains(mText, 'TSpezial.Run  ' + cApiFile + ':23  «überschrieben»');
  Assert.Contains(mText, 'TFakeHost.Run  ' + cTestFile + ':9  «umgesetzt»');
  Assert.DoesNotContain(mText, '(Test)');
end;

procedure TMcpImplementationToolsTests.MarksTestUnits;
var
  mText: string;
begin
  FTools.ImpactOptionsFor := TestScope;
  mText := FTools.Find('IHost.Run', False, False);
  Assert.Contains(mText, 'TFakeHost.Run  ' + cTestFile + ':9  «umgesetzt»  (Test)');
  Assert.DoesNotContain(mText, ':17  «umgesetzt»  (Test)');
end;

procedure TMcpImplementationToolsTests.ListsVirtualOverridesAndAbstract;
var
  mText: string;
begin
  mText := FTools.Find('THost.Run', False, False);
  Assert.Contains(mText, '2 Umsetzungen von THost.Run');
  Assert.Contains(mText, 'THost.Run  ' + cApiFile + ':17  «eigener Rumpf»');
  mText := FTools.Find('THost.Lang', False, False);
  Assert.Contains(mText, 'THost.Lang  ' + cApiFile + ':10  «abstrakt»');
  Assert.Contains(mText, 'TSpezial.Lang  ' + cApiFile + ':27  «überschrieben»');
end;

procedure TMcpImplementationToolsTests.ListsImplementingClassesOfType;
var
  mText: string;
begin
  mText := FTools.Find('IHost', False, False);
  Assert.Contains(mText, 'THost  ' + cApiFile + ':7');
  Assert.Contains(mText, 'TSpezial  ' + cApiFile + ':12');
  Assert.Contains(mText, 'TFakeHost  ' + cTestFile + ':5');
end;

procedure TMcpImplementationToolsTests.IncludeBodyShortensLongBodies;
var
  mText: string;
begin
  mText := FTools.Find('THost.Lang', True, False);
  Assert.Contains(mText, '```pascal');
  Assert.Contains(mText, 'procedure TSpezial.Lang;');
  Assert.Contains(mText, 'Schritt(18);');
  Assert.DoesNotContain(mText, 'Schritt(19);');
  Assert.Contains(mText, '… gekürzt, 20 von 23 Zeilen');
end;

procedure TMcpImplementationToolsTests.JsonHasFormatLinesFromOneAndKinds;
var
  mValue: TJSONValue;
  mRoot, mFirst: TJSONObject;
  mList: TJSONArray;
begin
  mValue := TJSONObject.ParseJSONValue(FTools.Find('IHost.Run', True, True));
  try
    mRoot := mValue as TJSONObject;
    Assert.AreEqual('json', mRoot.GetValue<string>('format'));
    Assert.AreEqual('interface', mRoot.GetValue<string>('kind'));
    Assert.AreEqual(3, mRoot.GetValue<Integer>('count'));
    mList := mRoot.GetValue<TJSONArray>('implementations');
    mFirst := mList.Items[0] as TJSONObject;
    Assert.AreEqual('THost', mFirst.GetValue<string>('type'));
    Assert.AreEqual('implements', mFirst.GetValue<string>('kind'));
    Assert.AreEqual(17, mFirst.GetValue<Integer>('line'));
    Assert.IsFalse(mFirst.GetValue<Boolean>('test'));
    Assert.IsTrue(mFirst.GetValue<string>('body').StartsWith('procedure THost.Run;'));
  finally
    mValue.Free;
  end;
end;

procedure TMcpImplementationToolsTests.AmbiguousNameListsCandidates;
var
  mText: string;
begin
  mText := FTools.Find('Run', False, False);
  Assert.Contains(mText, 'ist mehrdeutig');
  Assert.Contains(mText, 'Api.IHost.Run');
  Assert.Contains(mText, 'Andere.TAnderer.Run  ' + cOtherFile + ':5');
end;

procedure TMcpImplementationToolsTests.UnknownNameGivesHint;
begin
  Assert.AreEqual('Kein Symbol "TGibtEsNicht.Run" im Index.', FTools.Find('TGibtEsNicht.Run', False, False));
end;

procedure TMcpImplementationToolsTests.StaticMethodGivesNote;
var
  mText: string;
begin
  mText := FTools.Find('THost.Fest', False, False);
  Assert.Contains(mText, '1 Umsetzung von THost.Fest');
  Assert.Contains(mText, 'weder virtuell noch Methode eines Interfaces');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpImplementationToolsTests);

end.
