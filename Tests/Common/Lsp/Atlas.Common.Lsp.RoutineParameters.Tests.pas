unit Atlas.Common.Lsp.RoutineParameters.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.RoutineParameters;

type
  [TestFixture]
  TLspRoutineParametersTests = class
  private
    FTree: TSyntaxTree;
    function LineOf(const AMarker: string): Integer;
    function Describe(const AMarker: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MethodWithGroupedAndModifiedParameters;
    [Test]
    procedure LocalRoutineWins;
    [Test]
    procedure AnonymousMethodHasNoParameters;
    [Test]
    procedure UntypedVarAndOpenArray;
    [Test]
    procedure OutsideRoutine;
    [Test]
    procedure JsonShape;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.TreeCache;

const
  cSource =
    'unit Kunden;'#10 +                                                         // 0
    'interface'#10 +                                                            // 1
    'implementation'#10 +                                                       // 2
    'procedure TImport.Lies(const AName: string; A, B: Integer; var ALog: TStrings);'#10 + // 3
    '  procedure Innen(X: Double);'#10 +                                        // 4
    '  begin'#10 +                                                              // 5
    '    Zeige(X); // Innen'#10 +                                               // 6
    '  end;'#10 +                                                               // 7
    'begin'#10 +                                                                // 8
    '  Innen(A); // Aussen'#10 +                                                // 9
    '  Liste.ForEach(procedure(K: TKunde)'#10 +                                 // 10
    '    begin'#10 +                                                            // 11
    '      Zeige(K); // Anonym'#10 +                                            // 12
    '    end);'#10 +                                                            // 13
    'end;'#10 +                                                                 // 14
    'function Summe(out ATotal: Int64; var AData; const AWerte: array of Integer): Boolean;'#10 + // 15
    'begin'#10 +                                                                // 16
    '  Result := True; // Summe'#10 +                                           // 17
    'end;'#10 +                                                                 // 18
    'end.';

{ TLspRoutineParametersTests }

procedure TLspRoutineParametersTests.Setup;
begin
  FTree := TSyntaxTreeCache.Parse(cSource);
end;

procedure TLspRoutineParametersTests.TearDown;
begin
  FreeAndNil(FTree);
end;

function TLspRoutineParametersTests.LineOf(const AMarker: string): Integer;
var
  mLines: TArray<string>;
begin
  mLines := cSource.Split([#10]);
  Result := 0;
  while (Result <= High(mLines)) and (Pos(AMarker, mLines[Result]) = 0) do
  begin
    Inc(Result);
  end;
  Assert.IsTrue(Result <= High(mLines), AMarker + ' nicht gefunden');
end;

function TLspRoutineParametersTests.Describe(const AMarker: string): string;
var
  mParameters: TLspRoutineParameters;
  mRoutine: string;
  mList: TLspRoutineParameterList;
  mItem: TLspRoutineParameter;
begin
  mParameters := TLspRoutineParameters.Create(FTree, cSource);
  try
    if not mParameters.Answer(LineOf(AMarker), mRoutine, mList) then
    begin
      Exit('-');
    end;
  finally
    mParameters.Free;
  end;
  Result := mRoutine + ':';
  for mItem in mList do
  begin
    Result := Result + ' ' + Trim(mItem.Modifier + ' ' + mItem.Name) + ': ' + mItem.TypeName + ';';
  end;
end;

procedure TLspRoutineParametersTests.MethodWithGroupedAndModifiedParameters;
begin
  Assert.AreEqual('TImport.Lies: const AName: string; A: Integer; B: Integer; var ALog: TStrings;',
    Describe('// Aussen'));
end;

procedure TLspRoutineParametersTests.LocalRoutineWins;
begin
  Assert.AreEqual('Innen: X: Double;', Describe('// Innen'));
end;

procedure TLspRoutineParametersTests.AnonymousMethodHasNoParameters;
begin
  Assert.AreEqual('-', Describe('// Anonym'));
end;

procedure TLspRoutineParametersTests.UntypedVarAndOpenArray;
begin
  Assert.AreEqual('Summe: out ATotal: Int64; var AData: ; const AWerte: array of Integer;', Describe('// Summe'));
end;

procedure TLspRoutineParametersTests.OutsideRoutine;
begin
  Assert.AreEqual('-', Describe('interface'));
end;

procedure TLspRoutineParametersTests.JsonShape;
var
  mParameters: TLspRoutineParameters;
  mJson: TJSONObject;
begin
  mParameters := TLspRoutineParameters.Create(FTree, cSource);
  try
    mJson := mParameters.Execute(LineOf('// Innen'));
    try
      Assert.AreEqual('{"format":1,"routine":"Innen","parameters":[{"name":"X","type":"Double","modifier":""}]}',
        mJson.ToJSON);
    finally
      mJson.Free;
    end;
    mJson := mParameters.Execute(LineOf('interface'));
    try
      Assert.AreEqual('{"format":1,"routine":"","parameters":[]}', mJson.ToJSON);
    finally
      mJson.Free;
    end;
  finally
    mParameters.Free;
  end;
end;

end.
