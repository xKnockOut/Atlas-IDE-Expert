unit BDLsp.Common.Editing.RecordCommands.Tests;

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
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Editing.SlashCommands,
  BDLsp.Common.Editing.RecordCommands;

/// <summary>Führt den Befehl in Zeile ALine aus und wendet die Änderungen an; '' wenn er nicht passt.</summary>
function Expand(const AText: string; ALine: Integer;
  const AVersion: string = ''): string;
var
  Edits: TArray<TRuleEdit>;
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  if not TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, Edits, nil,
    AVersion) then
    Exit('');
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(Edits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in Edits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
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

const
  Punkt =
    'unit U;'#10 +                             // 0
    'interface'#10 +                           // 1
    'type'#10 +                                // 2
    '  TPunkt = record'#10 +                   // 3
    '    X, Y: Integer;'#10 +                  // 4
    '    %s'#10 +                              // 5 Befehl
    '  end;'#10 +                              // 6
    'implementation'#10 +                      // 7
    'end.';

  Kunde =
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
  Part: string;
  Name: string;
begin
  Part := Copy(AText, Pos(AFrom, AText), MaxInt);
  Part := Copy(Part, 1, Pos(AStop, Part));
  Result := '';
  for Name in ['FNr', 'FName', 'FAdresse'] do
    if ContainsText(Part, Name) then
      Result := Result + Name + ' ';
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
  Text: string;
begin
  Text := Expand('unit U;'#10'interface'#10'type'#10'  /record TPunkt X, Y: Integer; Name: string'#10 +
    'implementation'#10'end.', 3);
  Assert.Contains(Text, '  TPunkt = record'#10'    X, Y: Integer;'#10'    Name: string;'#10 +
    '    constructor Create(AX, AY: Integer; AName: string);'#10'  end;');
  Assert.Contains(Text, 'constructor TPunkt.Create(AX, AY: Integer; AName: string);'#10'begin'#10'  X := AX;'#10 +
    '  Y := AY;'#10'  Name := AName;'#10'end;');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TRecordCommandsTests.RecordReadOnly;
var
  Text: string;
begin
  Text := Expand('unit U;'#10'interface'#10'/record TPunkt X, Y: Integer ro'#10'implementation'#10'end.', 2);
  Assert.Contains(Text, 'type'#10'  TPunkt = record'#10'  private'#10'    FX, FY: Integer;'#10'  public'#10);
  Assert.Contains(Text, '    property X: Integer read FX;'#10'    property Y: Integer read FY;');
  Assert.Contains(Text, '  FX := AX;');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TRecordCommandsTests.RecordInRoutineFails;
begin
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  /record TPunkt X: Integer'#10'end;'#10'end.', 5));
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'type'#10'  /record TPunkt'#10'implementation'#10'end.', 3));
end;

procedure TRecordCommandsTests.OperatorEqualBringsNotEqual;
var
  Text: string;
begin
  Text := Expand(Format(Punkt, ['/operator =']), 5);
  Assert.Contains(Text, 'class operator Equal(const A, B: TPunkt): Boolean;');
  Assert.Contains(Text, 'class operator NotEqual(const A, B: TPunkt): Boolean;');
  Assert.Contains(Text, '  Result := (A.X = B.X) and (A.Y = B.Y);');
  Assert.Contains(Text, '  Result := not (A = B);');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TRecordCommandsTests.OperatorAddAndImplicit;
var
  Text: string;
begin
  Text := Expand(Format(Punkt, ['/operator + Implicit']), 5);
  Assert.Contains(Text, 'class operator TPunkt.Add(const A, B: TPunkt): TPunkt;'#10'begin'#10 +
    '  Result.X := A.X + B.X;'#10'  Result.Y := A.Y + B.Y;'#10'end;');
  Assert.Contains(Text, 'class operator Implicit(const Value: TPunkt): string;');
  Assert.AreEqual('', Expand(Format(Punkt, ['/operator ?']), 5));
end;

procedure TRecordCommandsTests.OperatorOutsideRecordFails;
begin
  Assert.AreEqual('', Expand(Format(Kunde, ['TObject', '/operator =']), 9));
end;

procedure TRecordCommandsTests.EqualsAndHashUseSameFields;
var
  Text: string;
begin
  Text := Expand(Format(Kunde, ['TObject', '/equals FNr, FName']), 9);
  Assert.Contains(Text, 'function Equals(Obj: TObject): Boolean; override;');
  Assert.Contains(Text, 'THashBobJenkins.GetHashValue(FName, Result)');
  Assert.Contains(Text, 'System.Hash');
  // Gleiche Objekte haben gleiche Hashwerte: beide Methoden lesen dieselben Felder.
  Assert.AreEqual('FNr FName ', FieldOrder(Text, 'TKunde.Equals', 'end;'));
  Assert.AreEqual('FNr FName ', FieldOrder(Text, 'TKunde.GetHashCode', 'end;'));
  Text := Expand(Format(Kunde, ['TObject', '/equals']), 9);
  Assert.AreEqual(FieldOrder(Text, 'TKunde.Equals', 'end;'), FieldOrder(Text, 'TKunde.GetHashCode', 'end;'));
  Assert.Contains(Text, 'FAdresse.Equals(TKunde(Obj).FAdresse)');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TRecordCommandsTests.EqualsOnRecordAddsOperators;
var
  Text: string;
begin
  Text := Expand(Format(Punkt, ['/equals']), 5);
  Assert.Contains(Text, 'class operator Equal(const A, B: TPunkt): Boolean;');
  Assert.Contains(Text, 'class operator NotEqual(const A, B: TPunkt): Boolean;');
end;

procedure TRecordCommandsTests.EqualsUnknownFieldFails;
begin
  Assert.AreEqual('', Expand(Format(Kunde, ['TObject', '/equals FGibtsNicht']), 9));
  Assert.AreEqual('', Expand('unit U;'#10'interface'#10'/equals'#10'implementation'#10'end.', 2));
end;

procedure TRecordCommandsTests.CloneFreesResultOnError;
var
  Text: string;
begin
  Text := Expand(Format(Kunde, ['TObject', '/clone']), 9);
  Assert.Contains(Text, 'function TKunde.Clone: TKunde;'#10'begin'#10'  Result := TKunde.Create;'#10'  try'#10 +
    '    Result.FNr := FNr;'#10'    Result.FName := FName;'#10'    // TODO: Result.FAdresse aus FAdresse kopieren'#10 +
    '  except'#10'    Result.Free;'#10'    raise;'#10'  end;'#10'end;');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TRecordCommandsTests.CloneUsesAssignForPersistent;
begin
  Assert.Contains(Expand(Format(Kunde, ['TPersistent', '/clone']), 9), '  try'#10'    Result.Assign(Self);'#10 +
    '  except');
end;

procedure TRecordCommandsTests.CloneOutsideClassFails;
begin
  Assert.AreEqual('', Expand(Format(Punkt, ['/clone']), 5));
end;

initialization
  TDUnitX.RegisterTestFixture(TRecordCommandsTests);

end.
