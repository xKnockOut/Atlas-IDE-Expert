unit Atlas.Common.Editing.DeclarationCommands.Tests;

// Tests für die Schnellbefehle /var, /const, /field, /prop, /resstr und /guid (#294).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationCommandsTests = class
  public
    /// <summary>Führt einen Befehl vorab aus; einmalig angelegte Daten zählen sonst als Leck des ersten
    /// Tests.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure VarCreatesSectionBeforeBegin;
    [Test]
    procedure VarAppendsToExistingSection;
    [Test]
    procedure InlineVarReplacesLine;
    [Test]
    procedure VarOutsideRoutineFails;
    /// <summary>#294: Inline-Variable vor Delphi 10.3 bleibt stehen und bekommt einen Hinweis.</summary>
    [Test]
    procedure InlineVarNeedsDelphi103;
    /// <summary>#294: /const außerhalb einer Routine und /prop außerhalb einer Klasse bleiben stehen.</summary>
    [Test]
    procedure ConstAndPropOutsideFail;
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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract;

const
  cClassUnit =
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
  Result := Format(cClassUnit, [ACommand]);
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mOffsets: TArray<Integer>;
  mIndex, mStart, mStop: Integer;
begin
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  // Von hinten nach vorn, damit die Positionen gültig bleiben.
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for mEdit in AEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
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

procedure TDeclarationCommandsTests.WarmUp;
var
  mEdits: TArray<TRuleEdit>;
begin
  Run(WithCommand('/var Count: Integer'), 16, mEdits);
  Parses(WithCommand(''));
end;

procedure TDeclarationCommandsTests.VarCreatesSectionBeforeBegin;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  Assert.IsTrue(Run(WithCommand('/var Liste: TStringList'), 16, mEdits));
  mText := Apply(WithCommand('/var Liste: TStringList'), mEdits);
  Assert.IsTrue(Pos('procedure TFoo.Run;'#10'var'#10'  Liste: TStringList;'#10'begin'#10'  Writeln', mText) > 0, mText);
end;

procedure TDeclarationCommandsTests.VarAppendsToExistingSection;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10'  A: Integer;'#10'begin'#10 +
    '  /var B: string'#10'end;'#10'end.';
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(cText, 7, mEdits));
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10'  A: Integer;'#10 +
    '  B: string;'#10'begin'#10'end;'#10'end.', Apply(cText, mEdits));
end;

procedure TDeclarationCommandsTests.InlineVarReplacesLine;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(WithCommand('/var I := 0'), 16, mEdits));
  Assert.IsTrue(Pos(#10'  var I := 0;'#10, Apply(WithCommand('/var I := 0'), mEdits)) > 0);
end;

procedure TDeclarationCommandsTests.VarOutsideRoutineFails;
const
  cText = 'unit U;'#10'interface'#10'/var X: Integer'#10#10'implementation'#10'end.';
var
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(Run(cText, 2, mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems(cText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('/var gilt nur im Rumpf einer Routine', mProblems[0].Message);
end;

procedure TDeclarationCommandsTests.InlineVarNeedsDelphi103;
var
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  // Delphi 10.2 (BDS 19.0): kein Inline-var; 10.3 (20.0) und unbekannt: erlaubt.
  Assert.IsFalse(TSlashCommandRegistry.Shared.AfterEnter(WithCommand('/var I := 0'), TTextPosition.Create(17, 0),
    TSlashEnvironment.Create(nil, nil, nil, '19.0', '', nil), mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems(WithCommand('/var I := 0'), nil, nil, '19.0');
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.IsTrue(mProblems[0].Message.StartsWith('Inline-Variablen gibt es erst ab Delphi 10.3'), mProblems[0].Message);
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(WithCommand('/var I := 0'), TTextPosition.Create(17, 0),
    TSlashEnvironment.Create(nil, nil, nil, '20.0', '', nil), mEdits));
  // Die lokale Variable geht in jeder Version.
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(WithCommand('/var I: Integer'), TTextPosition.Create(17, 0),
    TSlashEnvironment.Create(nil, nil, nil, '19.0', '', nil), mEdits));
end;

procedure TDeclarationCommandsTests.ConstAndPropOutsideFail;
const
  cOutside = 'unit U;'#10'interface'#10'%s'#10#10'implementation'#10'end.';
var
  mOk: Boolean;
  mEdits: TArray<TRuleEdit>;
  mProblems: TArray<TSlashProblem>;
begin
  Assert.IsFalse(Run(Format(cOutside, ['/const Max = 10']), 2, mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems(Format(cOutside, ['/const Max = 10']), nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual('/const gilt nur im Rumpf einer Routine; /const! schreibt in die implementation',
    mProblems[0].Message);
  // /const! braucht die implementation.
  mOk := Run('unit U;'#10'interface'#10'/const! Max = 10'#10#10'end.', 2, mEdits);
  if mOk then
  begin
    Assert.Fail(Apply('unit U;'#10'interface'#10'/const! Max = 10'#10#10'end.', mEdits));
  end;
  Assert.IsFalse(Run('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  /prop Name: string'#10#10'end;'#10'end.', 5, mEdits));
  mProblems := TSlashCommandRegistry.Shared.Problems('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10 +
    'begin'#10'  /prop Name: string'#10#10'end;'#10'end.', nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.IsTrue(mProblems[0].Message.StartsWith('/prop'), mProblems[0].Message);
  Assert.AreEqual(5, mProblems[0].Range.StartPos.Line);
end;

procedure TDeclarationCommandsTests.ConstLocalAndImplementation;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  Assert.IsTrue(Run(WithCommand('/const Max = 10'), 16, mEdits));
  Assert.IsTrue(Pos('procedure TFoo.Run;'#10'const'#10'  Max = 10;'#10'begin', Apply(WithCommand('/const Max = 10'),
    mEdits)) > 0);
  Assert.IsTrue(Run(WithCommand('/const! Max = 10'), 16, mEdits));
  mText := Apply(WithCommand('/const! Max = 10'), mEdits);
  Assert.IsTrue(Pos('  System.SysUtils;'#10#10'const'#10'  Max = 10;'#10, mText) > 0, mText);
end;

procedure TDeclarationCommandsTests.FieldGoesToPrivate;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  // Ohne private-Abschnitt wird er vor "end" angelegt; Name bekommt das F.
  Assert.IsTrue(Run(WithCommand('/field name: string'), 16, mEdits));
  mText := Apply(WithCommand('/field name: string'), mEdits);
  Assert.IsTrue(Pos('    procedure Run;'#10'  private'#10'    FName: string;'#10'  end;', mText) > 0, mText);
  // Mit private-Abschnitt oben hinein.
  mText := StringReplace(WithCommand('/field FAnzahl: Integer'), '  public'#10, '  private'#10'    FA: Byte;'#10 +
    '  public'#10, []);
  Assert.IsTrue(Run(mText, 18, mEdits));
  Assert.IsTrue(Pos('  private'#10'    FAnzahl: Integer;'#10'    FA: Byte;', Apply(mText, mEdits)) > 0, Apply(mText, mEdits));
end;

procedure TDeclarationCommandsTests.FieldOutsideClassFails;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  /field X: Integer'#10 +
    'end;'#10'end.';
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(Run(cText, 5, mEdits));
  Assert.AreEqual('/field gilt nur in einer Klasse oder einer ihrer Methoden',
    TSlashCommandRegistry.Shared.Problems(cText, nil)[0].Message);
end;

procedure TDeclarationCommandsTests.PropCreatesPrivateAndSetter;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  Assert.IsTrue(Run(WithCommand('/prop Name: string'), 16, mEdits));
  mText := Apply(WithCommand('/prop Name: string'), mEdits);
  Assert.IsTrue(Pos('    procedure Run;'#10'  private'#10'    FName: string;'#10 +
    '    procedure SetName(const Value: string);'#10'  public'#10 +
    '    property Name: string read FName write SetName;'#10'  end;', mText) > 0, mText);
  // Setter-Rumpf hinter der letzten Methode der Klasse.
  // Setter mit Änderungsprüfung wie bei der Code-Vorlage (#51); TFoo ist kein Control und hat kein Changed.
  Assert.IsTrue(Pos('end;'#10#10'procedure TFoo.SetName(const Value: string);'#10'begin'#10 +
    '  if FName <> Value then'#10'    FName := Value;'#10'end;'#10, mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TDeclarationCommandsTests.ReadOnlyPropHasNoSetter;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  Assert.IsTrue(Run(WithCommand('/prop Anzahl: Integer ro'), 16, mEdits));
  mText := Apply(WithCommand('/prop Anzahl: Integer ro'), mEdits);
  Assert.IsTrue(Pos('property Anzahl: Integer read FAnzahl;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('SetAnzahl', mText));
end;

procedure TDeclarationCommandsTests.ResStrReplacesLiteral;
const
  cText = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  Writeln(''Fehler beim Laden'');'#10'  /resstr'#10'end;'#10'end.';
var
  mEdits: TArray<TRuleEdit>;
  mOutput: string;
begin
  Assert.IsTrue(Run(cText, 6, mEdits));
  mOutput := Apply(cText, mEdits);
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10#10'resourcestring'#10 +
    '  SFehlerBeimLaden = ''Fehler beim Laden'';'#10'procedure P;'#10'begin'#10'  Writeln(SFehlerBeimLaden);'#10 +
    'end;'#10'end.', mOutput);
end;

procedure TDeclarationCommandsTests.ResStrWithoutLiteralFails;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(Run(WithCommand('  /resstr'), 16, mEdits));
end;

procedure TDeclarationCommandsTests.GuidInInterface;
const
  cText = 'unit U;'#10'interface'#10'type'#10'  IBar = interface'#10'    /guid'#10'    procedure Go;'#10'  end;'#10 +
    'implementation'#10'end.';
var
  mEdits: TArray<TRuleEdit>;
  mLine: string;
begin
  Assert.IsTrue(Run(cText, 4, mEdits));
  Assert.AreEqual(1, Integer(Length(mEdits)));
  mLine := mEdits[0].NewText;
  Assert.AreEqual(46, Integer(Length(mLine)), mLine);
  Assert.IsTrue(mLine.StartsWith('    [''{') and mLine.EndsWith('}'']'), mLine);
  Assert.IsTrue(Parses(Apply(cText, mEdits)));
end;

procedure TDeclarationCommandsTests.GuidOutsideInterfaceFails;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsFalse(Run(WithCommand('/guid'), 16, mEdits));
end;

procedure TDeclarationCommandsTests.ResultsParseWithoutErrors;
const
  cCommands: array[0..4] of string = ('/var Liste: TStringList', '/var I := 0', '/const Max = 10',
    '/const! Max = 10', '/field Name: string');
var
  mCommand: string;
  mEdits: TArray<TRuleEdit>;
begin
  for mCommand in cCommands do
  begin
    Assert.IsTrue(Run(WithCommand(mCommand), 16, mEdits), mCommand);
    Assert.IsTrue(Parses(Apply(WithCommand(mCommand), mEdits)), mCommand);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationCommandsTests);

end.
