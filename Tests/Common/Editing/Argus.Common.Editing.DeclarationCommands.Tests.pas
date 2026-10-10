unit Argus.Common.Editing.DeclarationCommands.Tests;

// Tests für die Schnellbefehle /var, /const, /field, /prop, /resstr und /guid (#294).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationCommandsTests = class
  public
    [Test]
    procedure VarCreatesSectionBeforeBegin;
    [Test]
    procedure VarAppendsToExistingSection;
    [Test]
    procedure InlineVarReplacesLine;
    [Test]
    procedure VarOutsideRoutineFails;
    [Test]
    procedure ConstLocalAndImplementation;
    [Test]
    procedure FieldGoesToPrivate;
    [Test]
    procedure FieldOutsideClassFails;
    [Test]
    procedure PropCreatesPrivateAndSetter;
    [Test]
    procedure ReadOnlyPropHasNoSetter;
    [Test]
    procedure ResStrReplacesLiteral;
    [Test]
    procedure ResStrWithoutLiteralFails;
    [Test]
    procedure GuidInInterface;
    [Test]
    procedure GuidOutsideInterfaceFails;
    [Test]
    procedure ResultsParseWithoutErrors;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Editing.SlashCommands;

const
  ClassUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TFoo = class'#10 +                           // 3
    '  public'#10 +                                 // 4
    '    procedure Run;'#10 +                       // 5
    '  end;'#10 +                                   // 6
    '  IBar = interface'#10 +                       // 7
    '    procedure Go;'#10 +                        // 8
    '  end;'#10 +                                   // 9
    'implementation'#10 +                           // 10
    'uses'#10 +                                     // 11
    '  System.SysUtils;'#10 +                       // 12
    #10 +                                           // 13
    'procedure TFoo.Run;'#10 +                      // 14
    'begin'#10 +                                    // 15
    '  %s'#10 +                                     // 16 Befehl
    '  Writeln(''Fehler beim Laden'');'#10 +        // 17
    'end;'#10 +                                     // 18
    #10 +                                           // 19
    'end.';

/// <summary>Text mit dem Befehl in Zeile 16 bzw. AText mit eigener Befehlszeile.</summary>
function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits);
end;

function WithCommand(const ACommand: string): string;
begin
  Result := Format(ClassUnit, [ACommand]);
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
  // Von hinten nach vorn, damit die Positionen gültig bleiben.
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

procedure TDeclarationCommandsTests.VarCreatesSectionBeforeBegin;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Assert.IsTrue(Run(WithCommand('/var Liste: TStringList'), 16, Edits));
  Text := Apply(WithCommand('/var Liste: TStringList'), Edits);
  Assert.IsTrue(Pos('procedure TFoo.Run;'#10'var'#10'  Liste: TStringList;'#10'begin'#10'  Writeln', Text) > 0, Text);
end;

procedure TDeclarationCommandsTests.VarAppendsToExistingSection;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10'  A: Integer;'#10'begin'#10 +
    '  /var B: string'#10'end;'#10'end.';
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(Text, 7, Edits));
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10'  A: Integer;'#10 +
    '  B: string;'#10'begin'#10'end;'#10'end.', Apply(Text, Edits));
end;

procedure TDeclarationCommandsTests.InlineVarReplacesLine;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(WithCommand('/var I := 0'), 16, Edits));
  Assert.IsTrue(Pos(#10'  var I := 0;'#10, Apply(WithCommand('/var I := 0'), Edits)) > 0);
end;

procedure TDeclarationCommandsTests.VarOutsideRoutineFails;
const
  Text = 'unit U;'#10'interface'#10'/var X: Integer'#10#10'implementation'#10'end.';
var
  Edits: TArray<TRuleEdit>;
  Problems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(Run(Text, 2, Edits));
  Problems := TSlashCommandRegistry.Shared.Problems(Text, nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Assert.AreEqual('/var gilt nur im Rumpf einer Routine', Problems[0].Message);
end;

procedure TDeclarationCommandsTests.ConstLocalAndImplementation;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Assert.IsTrue(Run(WithCommand('/const Max = 10'), 16, Edits));
  Assert.IsTrue(Pos('procedure TFoo.Run;'#10'const'#10'  Max = 10;'#10'begin', Apply(WithCommand('/const Max = 10'),
    Edits)) > 0);
  Assert.IsTrue(Run(WithCommand('/const! Max = 10'), 16, Edits));
  Text := Apply(WithCommand('/const! Max = 10'), Edits);
  Assert.IsTrue(Pos('  System.SysUtils;'#10#10'const'#10'  Max = 10;'#10, Text) > 0, Text);
end;

procedure TDeclarationCommandsTests.FieldGoesToPrivate;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  // Ohne private-Abschnitt wird er vor "end" angelegt; Name bekommt das F.
  Assert.IsTrue(Run(WithCommand('/field name: string'), 16, Edits));
  Text := Apply(WithCommand('/field name: string'), Edits);
  Assert.IsTrue(Pos('    procedure Run;'#10'  private'#10'    FName: string;'#10'  end;', Text) > 0, Text);
  // Mit private-Abschnitt oben hinein.
  Text := StringReplace(WithCommand('/field FAnzahl: Integer'), '  public'#10, '  private'#10'    FA: Byte;'#10 +
    '  public'#10, []);
  Assert.IsTrue(Run(Text, 18, Edits));
  Assert.IsTrue(Pos('  private'#10'    FAnzahl: Integer;'#10'    FA: Byte;', Apply(Text, Edits)) > 0, Apply(Text, Edits));
end;

procedure TDeclarationCommandsTests.FieldOutsideClassFails;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /field X: Integer'#10 +
    'end;'#10'end.';
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(Run(Text, 5, Edits));
  Assert.AreEqual('/field gilt nur in einer Klasse oder einer ihrer Methoden',
    TSlashCommandRegistry.Shared.Problems(Text, nil)[0].Message);
end;

procedure TDeclarationCommandsTests.PropCreatesPrivateAndSetter;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Assert.IsTrue(Run(WithCommand('/prop Name: string'), 16, Edits));
  Text := Apply(WithCommand('/prop Name: string'), Edits);
  Assert.IsTrue(Pos('    procedure Run;'#10'  private'#10'    FName: string;'#10 +
    '    procedure SetName(const Value: string);'#10'  public'#10 +
    '    property Name: string read FName write SetName;'#10'  end;', Text) > 0, Text);
  // Setter-Rumpf hinter der letzten Methode der Klasse.
  Assert.IsTrue(Pos('end;'#10#10'procedure TFoo.SetName(const Value: string);'#10'begin'#10 +
    '  FName := Value;'#10'end;'#10, Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TDeclarationCommandsTests.ReadOnlyPropHasNoSetter;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Assert.IsTrue(Run(WithCommand('/prop Anzahl: Integer ro'), 16, Edits));
  Text := Apply(WithCommand('/prop Anzahl: Integer ro'), Edits);
  Assert.IsTrue(Pos('property Anzahl: Integer read FAnzahl;', Text) > 0, Text);
  Assert.AreEqual(0, Pos('SetAnzahl', Text));
end;

procedure TDeclarationCommandsTests.ResStrReplacesLiteral;
const
  Text = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  Writeln(''Fehler beim Laden'');'#10'  /resstr'#10'end;'#10'end.';
var
  Edits: TArray<TRuleEdit>;
  Output: string;
begin
  Assert.IsTrue(Run(Text, 6, Edits));
  Output := Apply(Text, Edits);
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10#10'resourcestring'#10 +
    '  SFehlerBeimLaden = ''Fehler beim Laden'';'#10'procedure P;'#10'begin'#10'  Writeln(SFehlerBeimLaden);'#10 +
    'end;'#10'end.', Output);
end;

procedure TDeclarationCommandsTests.ResStrWithoutLiteralFails;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(Run(WithCommand('  /resstr'), 16, Edits));
end;

procedure TDeclarationCommandsTests.GuidInInterface;
const
  Text = 'unit U;'#10'interface'#10'type'#10'  IBar = interface'#10'    /guid'#10'    procedure Go;'#10'  end;'#10 +
    'implementation'#10'end.';
var
  Edits: TArray<TRuleEdit>;
  Line: string;
begin
  Assert.IsTrue(Run(Text, 4, Edits));
  Assert.AreEqual(1, Integer(Length(Edits)));
  Line := Edits[0].NewText;
  Assert.AreEqual(46, Length(Line), Line);
  Assert.IsTrue(Line.StartsWith('    [''{') and Line.EndsWith('}'']'), Line);
  Assert.IsTrue(Parses(Apply(Text, Edits)));
end;

procedure TDeclarationCommandsTests.GuidOutsideInterfaceFails;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(Run(WithCommand('/guid'), 16, Edits));
end;

procedure TDeclarationCommandsTests.ResultsParseWithoutErrors;
const
  Commands: array[0..4] of string = ('/var Liste: TStringList', '/var I := 0', '/const Max = 10',
    '/const! Max = 10', '/field Name: string');
var
  Command: string;
  Edits: TArray<TRuleEdit>;
begin
  for Command in Commands do
  begin
    Assert.IsTrue(Run(WithCommand(Command), 16, Edits), Command);
    Assert.IsTrue(Parses(Apply(WithCommand(Command), Edits)), Command);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationCommandsTests);

end.
