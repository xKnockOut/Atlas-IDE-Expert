unit Atlas.Common.Editing.RecordCommands.Tests;

// Tests für die Schnellbefehle /record, /operator, /equals und /clone (#323).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRecordCommandsTests = class
  public
    [Test]
    procedure OperatorNames;
    [Test]
    procedure RecordWithConstructor;
    [Test]
    procedure RecordReadOnly;
    [Test]
    procedure RecordInRoutineFails;
    [Test]
    procedure OperatorEqualBringsNotEqual;
    [Test]
    procedure OperatorAddAndImplicit;
    [Test]
    procedure OperatorOutsideRecordFails;
    [Test]
    procedure EqualsAndHashUseSameFields;
    [Test]
    procedure EqualsOnRecordAddsOperators;
    [Test]
    procedure EqualsUnknownFieldFails;
    [Test]
    procedure CloneFreesResultOnError;
    [Test]
    procedure CloneUsesAssignForPersistent;
    [Test]
    procedure CloneOutsideClassFails;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.RecordCommands;

/// <summary>Führt den Befehl in Zeile ALine aus und wendet die Änderungen an; '' wenn er nicht passt.</summary>
function Expand(const AText: string; ALine: Integer;
  const AVersion: string): string; overload;
var
  mEdits: TArray<TRuleEdit>;
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mOffsets: TArray<Integer>;
  mIndex, mStart, mStop: Integer;
begin
  if not TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0),
    TSlashEnvironment.Create(nil, nil, nil, AVersion, '', nil), mEdits) then
  begin
    Exit('');
  end;
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  TArray.Sort<TRuleEdit>(mEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for mEdit in mEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function Expand(const AText: string; ALine: Integer): string; overload;
begin
  Result := Expand(AText, ALine, '');
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

const
  cPunkt =
    'unit U;'#10 +                             // 0
    'interface'#10 +                           // 1
    'type'#10 +                                // 2
    '  TPunkt = record'#10 +                   // 3
    '    X, Y: Integer;'#10 +                  // 4
    '    %s'#10 +                              // 5 Befehl
    '  end;'#10 +                              // 6
    'implementation'#10 +                      // 7
    'end.';

  cKunde =
    'unit U;'#10 +                             // 0
    'interface'#10 +                           // 1
    'uses System.Classes;'#10 +                // 2
    'type'#10 +                                // 3
    '  TKunde = class(%s)'#10 +                // 4
    '  private'#10 +                           // 5
    '    FNr: Integer;'#10 +                   // 6
    '    FName: string;'#10 +                  // 7
    '    FAdresse: TStringList;'#10 +          // 8
    '    %s'#10 +                              // 9 Befehl
    '  end;'#10 +                              // 10
    'implementation'#10 +                      // 11
    'end.';

/// <summary>Feldnamen in der Reihenfolge, in der sie in ALines nach AFrom bis AStop vorkommen.</summary>
function FieldOrder(const AText, AFrom, AStop: string): string;
var
  mPart: string;
  mName: string;
begin
  mPart := Copy(AText, Pos(AFrom, AText), MaxInt);
  mPart := Copy(mPart, 1, Pos(AStop, mPart));
  Result := '';
  for mName in ['FNr', 'FName', 'FAdresse'] do
  begin
    if ContainsText(mPart, mName) then
    begin
      Result := Result + mName + ' ';
    end;
  end;
end;

procedure TRecordCommandsTests.OperatorNames;
begin
  Assert.AreEqual('Equal', OperatorName('='));
  Assert.AreEqual('NotEqual', OperatorName('<>'));
  Assert.AreEqual('Add', OperatorName('+'));
  Assert.AreEqual('Implicit', OperatorName('implicit'));
  Assert.AreEqual('', OperatorName('?'));
end;

procedure TRecordCommandsTests.RecordWithConstructor;
var
  mText: string;
begin
  mText := Expand('unit U;'#10'interface'#10'type'#10'  /record TPunkt X, Y: Integer; Name: string'#10 +
    'implementation'#10'end.', 3);
  Assert.Contains(mText, '  TPunkt = record'#10'    X, Y: Integer;'#10'    Name: string;'#10 +
    '    constructor Create(AX, AY: Integer; AName: string);'#10'  end;');
  Assert.Contains(mText, 'constructor TPunkt.Create(AX, AY: Integer; AName: string);'#10'begin'#10'  X := AX;'#10 +
    '  Y := AY;'#10'  Name := AName;'#10'end;');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TRecordCommandsTests.RecordReadOnly;
var
  mText: string;
begin
  mText := Expand('unit U;'#10'interface'#10'/record TPunkt X, Y: Integer ro'#10'implementation'#10'end.', 2);
  Assert.Contains(mText, 'type'#10'  TPunkt = record'#10'  private'#10'    FX, FY: Integer;'#10'  public'#10);
  Assert.Contains(mText, '    property X: Integer read FX;'#10'    property Y: Integer read FY;');
  Assert.Contains(mText, '  FX := AX;');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TRecordCommandsTests.RecordInRoutineFails;
begin
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  /record TPunkt X: Integer'#10'end;'#10'end.', 5));
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'type'#10'  /record TPunkt'#10'implementation'#10'end.', 3));
end;

procedure TRecordCommandsTests.OperatorEqualBringsNotEqual;
var
  mText: string;
begin
  mText := Expand(Format(cPunkt, ['/operator =']), 5);
  Assert.Contains(mText, 'class operator Equal(const A, B: TPunkt): Boolean;');
  Assert.Contains(mText, 'class operator NotEqual(const A, B: TPunkt): Boolean;');
  Assert.Contains(mText, '  Result := (A.X = B.X) and (A.Y = B.Y);');
  Assert.Contains(mText, '  Result := not (A = B);');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TRecordCommandsTests.OperatorAddAndImplicit;
var
  mText: string;
begin
  mText := Expand(Format(cPunkt, ['/operator + Implicit']), 5);
  Assert.Contains(mText, 'class operator TPunkt.Add(const A, B: TPunkt): TPunkt;'#10'begin'#10 +
    '  Result.X := A.X + B.X;'#10'  Result.Y := A.Y + B.Y;'#10'end;');
  Assert.Contains(mText, 'class operator Implicit(const Value: TPunkt): string;');
  Assert.AreEqual('', Expand(Format(cPunkt, ['/operator ?']), 5));
end;

procedure TRecordCommandsTests.OperatorOutsideRecordFails;
begin
  Assert.AreEqual('', Expand(Format(cKunde, ['TObject', '/operator =']), 9));
end;

procedure TRecordCommandsTests.EqualsAndHashUseSameFields;
var
  mText: string;
begin
  mText := Expand(Format(cKunde, ['TObject', '/equals FNr, FName']), 9);
  Assert.Contains(mText, 'function Equals(Obj: TObject): Boolean; override;');
  Assert.Contains(mText, 'THashBobJenkins.GetHashValue(FName, Result)');
  Assert.Contains(mText, 'System.Hash');
  // Gleiche Objekte haben gleiche Hashwerte: beide Methoden lesen dieselben Felder.
  Assert.AreEqual('FNr FName ', FieldOrder(mText, 'TKunde.Equals', 'end;'));
  Assert.AreEqual('FNr FName ', FieldOrder(mText, 'TKunde.GetHashCode', 'end;'));
  mText := Expand(Format(cKunde, ['TObject', '/equals']), 9);
  Assert.AreEqual(FieldOrder(mText, 'TKunde.Equals', 'end;'), FieldOrder(mText, 'TKunde.GetHashCode', 'end;'));
  Assert.Contains(mText, 'FAdresse.Equals(TKunde(Obj).FAdresse)');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TRecordCommandsTests.EqualsOnRecordAddsOperators;
var
  mText: string;
begin
  mText := Expand(Format(cPunkt, ['/equals']), 5);
  Assert.Contains(mText, 'class operator Equal(const A, B: TPunkt): Boolean;');
  Assert.Contains(mText, 'class operator NotEqual(const A, B: TPunkt): Boolean;');
end;

procedure TRecordCommandsTests.EqualsUnknownFieldFails;
begin
  Assert.AreEqual('', Expand(Format(cKunde, ['TObject', '/equals FGibtsNicht']), 9));
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'/equals'#10'implementation'#10'end.', 2));
end;

procedure TRecordCommandsTests.CloneFreesResultOnError;
var
  mText: string;
begin
  mText := Expand(Format(cKunde, ['TObject', '/clone']), 9);
  Assert.Contains(mText, 'function TKunde.Clone: TKunde;'#10'begin'#10'  Result := TKunde.Create;'#10'  try'#10 +
    '    Result.FNr := FNr;'#10'    Result.FName := FName;'#10'    // TODO: Result.FAdresse aus FAdresse kopieren'#10 +
    '  except'#10'    Result.Free;'#10'    raise;'#10'  end;'#10'end;');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TRecordCommandsTests.CloneUsesAssignForPersistent;
begin
  Assert.Contains(Expand(Format(cKunde, ['TPersistent', '/clone']), 9), '  try'#10'    Result.Assign(Self);'#10 +
    '  except');
end;

procedure TRecordCommandsTests.CloneOutsideClassFails;
begin
  Assert.AreEqual('', Expand(Format(cPunkt, ['/clone']), 5));
end;

initialization
  TDUnitX.RegisterTestFixture(TRecordCommandsTests);

end.
