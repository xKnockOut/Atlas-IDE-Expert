unit BDLsp.Common.Editing.ExpressionCommands.Tests;

// Tests für die Schnellbefehle /format, /multiline, /iif und /inc (#303).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExpressionCommandsTests = class
  public
    [Test]
    procedure FormatUsesTypes;
    [Test]
    procedure FormatUnknownTypeAddsHint;
    [Test]
    procedure FormatWithoutConcatenationFails;
    [Test]
    procedure MultilineBothWays;
    [Test]
    procedure MultilineNeedsDelphi12;
    [Test]
    procedure IifBuildsConditionalExpression;
    [Test]
    procedure IifNeedsDelphi13AndSameTarget;
    [Test]
    procedure IncAndDec;
    [Test]
    procedure IncRejectsOtherShapes;
    [Test]
    procedure OutsideRoutineFails;
    [Test]
    procedure ModernUsesInlineVariable;
    [Test]
    procedure ModernWithoutChangesFails;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Editing.SlashCommands;

const
  RoutineUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'implementation'#10 +                           // 2
    'uses'#10 +                                     // 3
    '  System.SysUtils;'#10 +                       // 4
    'procedure Run(N: Integer; Preis: Double);'#10 + // 5
    'var'#10 +                                      // 6
    '  Name, S: string;'#10 +                       // 7
    '  Zaehler: Integer;'#10 +                      // 8
    'begin'#10 +                                    // 9
    '  %s'#10 +                                     // 10 Befehl
    '%s'#10 +                                       // 11 Anweisung
    'end;'#10 +                                     // 12
    'end.';

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

function Source(const ACommand, AStatement: string): string;
begin
  Result := StringReplace(StringReplace(RoutineUnit, '%s', ACommand, []), '%s', AStatement, []);
end;

function TryRun(const ACommand, AStatement, AVersion: string; out AText: string): Boolean;
var
  Edits: TArray<TRuleEdit>;
begin
  AText := Source(ACommand, AStatement);
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(11, 0), nil, nil, Edits, nil,
    AVersion);
  if Result then
    AText := Apply(AText, Edits);
end;

function Expand(const ACommand, AStatement: string; const AVersion: string = ''): string;
begin
  Assert.IsTrue(TryRun(ACommand, AStatement, AVersion, Result), ACommand + ' ' + AStatement);
  Assert.IsTrue(Pos(ACommand, Result) = 0, Result);
end;

procedure TExpressionCommandsTests.FormatUsesTypes;
var
  Text: string;
begin
  Text := Expand('/format', '  S := ''Kunde '' + Name + '' hat '' + IntToStr(N) + '' Aufträge zu '' + ' +
    'FloatToStr(Preis) + '' (100%)'';');
  Assert.IsTrue(Pos('  S := Format(''Kunde %s hat %d Aufträge zu %g (100%%)'', [Name, N, Preis]);', Text) > 0,
    Text);
  Text := Expand('/format', '  S := ''Preis: '' + Preis;');
  Assert.IsTrue(Pos('Format(''Preis: %g'', [Preis])', Text) > 0, Text);
end;

procedure TExpressionCommandsTests.FormatUnknownTypeAddsHint;
var
  Text: string;
begin
  Text := Expand('/format', '  ShowMessage(''Wert: '' + Liste.Text);');
  Assert.IsTrue(Pos('ShowMessage(Format(''Wert: %s'', [Liste.Text]));', Text) > 0, Text);
  Assert.IsTrue(Pos('// /format: Typ von Liste.Text unbekannt', Text) > 0, Text);
end;

procedure TExpressionCommandsTests.FormatWithoutConcatenationFails;
var
  Text: string;
begin
  Assert.IsFalse(TryRun('/format', '  S := ''nur Text'';', '', Text));
  Assert.IsFalse(TryRun('/format', '  Zaehler := Zaehler + 1;', '', Text));
end;

procedure TExpressionCommandsTests.MultilineBothWays;
var
  Text: string;
begin
  Text := Expand('/multiline', '  S := ''SELECT *'' + sLineBreak + ''FROM Kunde'';');
  Assert.IsTrue(Pos('  S := '''''''#10'    SELECT *'#10'    FROM Kunde'#10'    '''''''';', Text) > 0, Text);
  Text := Expand('/multiline!', '  S := '''''''#10'    SELECT *'#10'    FROM Kunde'#10'    '''''''';');
  Assert.IsTrue(Pos('''SELECT *'' + sLineBreak', Text) > 0, Text);
  Assert.IsTrue(Pos('''FROM Kunde'';', Text) > 0, Text);
end;

procedure TExpressionCommandsTests.MultilineNeedsDelphi12;
var
  Text: string;
begin
  // Delphi 11 (22.0) kennt keine mehrzeiligen Strings.
  Assert.IsFalse(TryRun('/multiline', '  S := ''a'' + sLineBreak + ''b'';', '22.0', Text));
  Assert.IsTrue(TryRun('/multiline', '  S := ''a'' + sLineBreak + ''b'';', '23.0', Text));
  Assert.IsFalse(TryRun('/multiline', '  S := ''nur eine Zeile'';', '', Text));
end;

procedure TExpressionCommandsTests.IifBuildsConditionalExpression;
begin
  Assert.IsTrue(Pos('  S := if N > 0 then ''ja'' else ''nein'';',
    Expand('/iif', '  if N > 0 then S := ''ja'' else S := ''nein'';')) > 0);
  Assert.IsTrue(Pos('  Zaehler := if Name = '''' then 0 else Length(Name);',
    Expand('/iif', '  if Name = '''' then'#10'    Zaehler := 0'#10'  else'#10'    Zaehler := Length(Name);')) > 0);
end;

procedure TExpressionCommandsTests.IifNeedsDelphi13AndSameTarget;
var
  Text: string;
begin
  // Delphi 12 (23.0) kennt keine Bedingungsausdrücke.
  Assert.IsFalse(TryRun('/iif', '  if N > 0 then S := ''ja'' else S := ''nein'';', '23.0', Text));
  Assert.IsFalse(TryRun('/iif', '  if N > 0 then S := ''ja'' else Name := ''nein'';', '', Text));
  Assert.IsFalse(TryRun('/iif', '  if N > 0 then begin S := ''ja''; end else S := ''nein'';', '', Text));
end;

procedure TExpressionCommandsTests.IncAndDec;
begin
  Assert.IsTrue(Pos('  Inc(Zaehler);', Expand('/inc', '  Zaehler := Zaehler + 1;')) > 0);
  Assert.IsTrue(Pos('  Dec(Zaehler, N * 2);', Expand('/inc', '  Zaehler := Zaehler - N * 2;')) > 0);
  Assert.IsTrue(Pos('  Inc(Werte[N], 3);', Expand('/inc', '  Werte[N] := Werte[N] + 3;')) > 0);
end;

procedure TExpressionCommandsTests.IncRejectsOtherShapes;
var
  Text: string;
begin
  Assert.IsFalse(TryRun('/inc', '  Zaehler := N + 1;', '', Text));
  Assert.IsFalse(TryRun('/inc', '  Zaehler := Zaehler - N + 1;', '', Text));
  Assert.IsFalse(TryRun('/inc', '  Preis := Preis + 0.5;', '', Text));
end;

procedure TExpressionCommandsTests.OutsideRoutineFails;
var
  Text: string;
begin
  Text := StringReplace(Source('', '  S := S;'), 'interface'#10, 'interface'#10'/inc'#10, []);
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(Text, nil))));
end;

procedure TExpressionCommandsTests.ModernUsesInlineVariable;
var
  Text: string;
begin
  Text := Expand('/modern', '  Zaehler := N;'#10'  Log(Zaehler);');
  Assert.IsTrue(Pos('  var Zaehler: Integer := N;', Text) > 0, Text);
  Assert.IsTrue(Pos('  Zaehler: Integer;', Text) = 0, Text);
end;

procedure TExpressionCommandsTests.ModernWithoutChangesFails;
var
  Text: string;
begin
  Assert.IsFalse(TryRun('/modern', '  Log(N);', '', Text));
  // Vor Delphi 10.3 keine Inline-Variablen.
  Assert.IsFalse(TryRun('/modern', '  Zaehler := N;', '19.0', Text));
  Assert.IsFalse(TryRun('/modern -inline', '  Zaehler := N;', '', Text));
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionCommandsTests);

end.
