unit BDLsp.Common.Editing.TypeCommands.Tests;

// Tests für die Schnellbefehle /enum, /helper, /singleton, /encapsulate, /assign und /json (#298).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeCommandsTests = class
  public
    [Test]
    procedure EnumWithPrefixInTypeSection;
    [Test]
    procedure EnumWithoutTypeSection;
    [Test]
    procedure EnumWithNamesReopensType;
    [Test]
    procedure EnumInRoutineFails;
    [Test]
    procedure HelperForRecordAndClass;
    [Test]
    procedure SingletonAddsInstance;
    [Test]
    procedure SingletonOutsideClassFails;
    [Test]
    procedure EncapsulateMakesProperty;
    [Test]
    procedure EncapsulatePrivateFieldFails;
    [Test]
    procedure AssignCopiesFields;
    [Test]
    procedure AssignOutsideClassFails;
    [Test]
    procedure JsonForSimpleFields;
    [Test]
    procedure JsonOutsideTypeFails;
    [Test]
    procedure ThreadWithoutTypeSection;
    [Test]
    procedure ThreadInClassFails;
    [Test]
    procedure ExceptionWithAndWithoutAncestor;
    [Test]
    procedure ExceptionInRoutineFails;
    [Test]
    procedure ResultsParseWithoutErrors;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Editing.SlashCommands,
  BDLsp.Common.Editing.TypeCommands;

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in AEdits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function Expand(const AText: string; ALine: Integer): string;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(AText, ALine, Edits), AText);
  Result := Apply(AText, Edits);
end;

function ProblemOf(const AText: string): string;
var
  Problems: TArray<TSlashProblem>;
begin
  Problems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Result := Problems[0].Message;
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
  ClassUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'uses'#10 +                                     // 2
    '  System.Classes;'#10 +                        // 3
    'type'#10 +                                     // 4
    '  TKunde = class(TPersistent)'#10 +            // 5
    '  private'#10 +                                // 6
    '    FListe: TStrings;'#10 +                    // 7
    '  public'#10 +                                 // 8
    '    FName: string;'#10 +                       // 9
    '    FAlter: Integer;'#10 +                     // 10
    '    FAktiv: Boolean;'#10 +                     // 11
    '    %s'#10 +                                   // 12 Befehl
    '  end;'#10 +                                   // 13
    'implementation'#10 +                           // 14
    #10 +                                           // 15
    'end.';

  TypeUnit =
    'unit U;'#10'interface'#10'type'#10'  TA = Integer;'#10'  %s'#10'  TB = Byte;'#10'implementation'#10'end.';

function InClass(const ACommand: string): string;
begin
  Result := Expand(Format(ClassUnit, [ACommand]), 12);
end;

procedure TTypeCommandsTests.EnumWithPrefixInTypeSection;
begin
  Assert.AreEqual('ks', EnumPrefix('TKundenStatus'));
  Assert.AreEqual(Format(TypeUnit, ['TFarbe = (fRot, fGruen, fBlau);']),
    Expand(Format(TypeUnit, ['/enum TFarbe rot, gruen, blau']), 4));
  Assert.AreEqual(Format(TypeUnit, ['TFarbe = (rot, gruen);']), Expand(Format(TypeUnit, ['/enum! TFarbe rot, gruen']),
    4));
end;

procedure TTypeCommandsTests.EnumWithoutTypeSection;
const
  Text = 'unit U;'#10'interface'#10'/enum TFarbe rot'#10'implementation'#10'end.';
begin
  Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TFarbe = (fRot);'#10'implementation'#10'end.',
    Expand(Text, 2));
end;

procedure TTypeCommandsTests.EnumWithNamesReopensType;
var
  Text: string;
begin
  Text := Expand(Format(TypeUnit, ['/enum TFarbe rot, gruen names']), 4);
  Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TA = Integer;'#10'  TFarbe = (fRot, fGruen);'#10'const'#10 +
    '  FarbeNamen: array[TFarbe] of string = (''rot'', ''gruen'');'#10'type'#10'  TB = Byte;'#10'implementation'#10 +
    'end.', Text);
  Assert.IsTrue(Parses(Text));
end;

procedure TTypeCommandsTests.EnumInRoutineFails;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /enum TA x'#10'end;'#10'end.';
begin
  Assert.AreEqual('/enum gilt nur auf Unit-Ebene', ProblemOf(Text));
end;

procedure TTypeCommandsTests.HelperForRecordAndClass;
var
  Text: string;
begin
  Text := Expand(Format(TypeUnit, ['/helper TA']), 4);
  Assert.IsTrue(Pos('  TAHelper = record helper for TA'#10'  public'#10'  end;'#10, Text) > 0, Text);
  Text := Expand(Format(TypeUnit, ['/helper TStrings']), 4);
  Assert.IsTrue(Pos('  TStringsHelper = class helper for TStrings'#10, Text) > 0, Text);
end;

procedure TTypeCommandsTests.SingletonAddsInstance;
var
  Text: string;
begin
  Text := InClass('/singleton');
  Assert.IsTrue(Pos('  private'#10'    class var FInstance: TKunde;'#10'  public'#10'    class destructor Destroy;'#10 +
    '    class function Instance: TKunde;'#10'  end;', Text) > 0, Text);
  Assert.IsTrue(Pos('class function TKunde.Instance: TKunde;'#10'begin'#10'  if FInstance = nil then'#10 +
    '    FInstance := TKunde.Create;'#10'  Result := FInstance;'#10'end;', Text) > 0, Text);
  Assert.IsTrue(Pos('  FreeAndNil(FInstance);', Text) > 0, Text);
end;

procedure TTypeCommandsTests.SingletonOutsideClassFails;
begin
  Assert.AreEqual('/singleton gilt nur in einer Klasse oder einer ihrer Methoden',
    ProblemOf(Format(TypeUnit, ['/singleton'])));
end;

procedure TTypeCommandsTests.EncapsulateMakesProperty;
var
  Text: string;
begin
  Text := InClass('/encapsulate FName');
  Assert.AreEqual(0, Pos('  public'#10'    FName: string;', Text), Text);
  Assert.IsTrue(Pos('  private'#10'    FName: string;'#10'    procedure SetName(const Value: string);'#10 +
    '  public'#10'    property Name: string read FName write SetName;'#10'  end;', Text) > 0, Text);
  Assert.IsTrue(Pos('procedure TKunde.SetName(const Value: string);'#10'begin'#10'  FName := Value;'#10'end;',
    Text) > 0, Text);
end;

procedure TTypeCommandsTests.EncapsulatePrivateFieldFails;
begin
  Assert.AreEqual('FListe ist schon private', ProblemOf(Format(ClassUnit, ['/encapsulate FListe'])));
  Assert.AreEqual('Kein Feld FOrt in TKunde', ProblemOf(Format(ClassUnit, ['/encapsulate FOrt'])));
end;

procedure TTypeCommandsTests.AssignCopiesFields;
var
  Text: string;
begin
  Text := InClass('/assign');
  Assert.IsTrue(Pos('    procedure Assign(Source: TPersistent); override;'#10'  end;', Text) > 0, Text);
  Assert.IsTrue(Pos('procedure TKunde.Assign(Source: TPersistent);'#10'begin'#10'  if Source is TKunde then'#10 +
    '  begin'#10'    FListe.Assign(TKunde(Source).FListe);'#10'    FName := TKunde(Source).FName;'#10 +
    '    FAlter := TKunde(Source).FAlter;'#10'    FAktiv := TKunde(Source).FAktiv;'#10'  end'#10'  else'#10 +
    '    inherited Assign(Source);'#10'end;', Text) > 0, Text);
end;

procedure TTypeCommandsTests.AssignOutsideClassFails;
begin
  Assert.AreEqual('/assign gilt nur in einer Klasse oder einer ihrer Methoden',
    ProblemOf(Format(TypeUnit, ['/assign'])));
end;

procedure TTypeCommandsTests.JsonForSimpleFields;
var
  Text: string;
begin
  Text := InClass('/json');
  Assert.IsTrue(Pos('  System.Classes, System.JSON;', Text) + Pos('  System.Classes,'#10'  System.JSON;', Text) > 0,
    Text);
  Assert.IsTrue(Pos('    function ToJson: TJSONObject;'#10 +
    '    class function FromJson(AJson: TJSONObject): TKunde; static;', Text) > 0, Text);
  Assert.IsTrue(Pos('  Result.AddPair(''Name'', FName);'#10'  Result.AddPair(''Alter'', TJSONNumber.Create(FAlter));'#10 +
    '  Result.AddPair(''Aktiv'', TJSONBool.Create(FAktiv));', Text) > 0, Text);
  Assert.IsTrue(Pos('  // TODO FListe: TStrings', Text) > 0, Text);
  Assert.IsTrue(Pos('  Result := TKunde.Create;'#10, Text) > 0, Text);
  Assert.IsTrue(Pos('  Result.FAlter := AJson.GetValue<Integer>(''Alter'');', Text) > 0, Text);
end;

procedure TTypeCommandsTests.JsonOutsideTypeFails;
begin
  Assert.AreEqual('/json gilt nur in einer Klasse oder einer ihrer Methoden', ProblemOf(Format(TypeUnit, ['/json'])));
end;

procedure TTypeCommandsTests.ThreadWithoutTypeSection;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10'/thread TWorker'#10#10'end.';
var
  Result_: string;
begin
  Result_ := Expand(Text, 5);
  Assert.IsTrue(Pos('type'#10'  TWorker = class(TThread)'#10'  protected'#10'    procedure Execute; override;'#10 +
    '  end;'#10, Result_) > 0, Result_);
  Assert.IsTrue(Pos('procedure TWorker.Execute;'#10'begin'#10, Result_) > 0, Result_);
  Assert.IsTrue(Pos('  while not Terminated do'#10, Result_) > 0, Result_);
  Assert.IsTrue(Pos('System.Classes', Result_) > 0, Result_);
  Assert.IsTrue(Parses(Result_), Result_);
end;

procedure TTypeCommandsTests.ThreadInClassFails;
begin
  Assert.AreEqual('/thread gilt nur auf Unit-Ebene', ProblemOf(Format(ClassUnit, ['/thread TWorker'])));
end;

procedure TTypeCommandsTests.ExceptionWithAndWithoutAncestor;
begin
  Assert.AreEqual(Format(TypeUnit, ['EImportFehler = class(Exception);']),
    Expand(Format(TypeUnit, ['/exception EImportFehler']), 4));
  Assert.AreEqual(Format(TypeUnit, ['EImportFehler = class(EBasis);']),
    Expand(Format(TypeUnit, ['/exception EImportFehler : EBasis']), 4));
end;

procedure TTypeCommandsTests.ExceptionInRoutineFails;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /exception EX'#10'end;'#10'end.';
begin
  Assert.AreEqual('/exception gilt nur auf Unit-Ebene', ProblemOf(Text));
end;

procedure TTypeCommandsTests.ResultsParseWithoutErrors;
const
  Commands: array[0..4] of string = ('/singleton', '/encapsulate FName', '/assign', '/json', '/encapsulate FAlter');
var
  Command, Text: string;
begin
  for Command in Commands do
  begin
    Text := InClass(Command);
    Assert.IsTrue(Parses(Text), Command + ': ' + Text);
  end;
  Assert.IsTrue(Parses(Expand(Format(TypeUnit, ['/helper TA']), 4)));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeCommandsTests);

end.
