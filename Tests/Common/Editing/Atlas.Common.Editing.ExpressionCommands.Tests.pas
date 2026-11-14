unit Atlas.Common.Editing.ExpressionCommands.Tests;

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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.SlashCommands;

const
  cRoutineUnit =
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

function Source(const ACommand, AStatement: string): string;
begin
  Result := StringReplace(StringReplace(cRoutineUnit, '%s', ACommand, []), '%s', AStatement, []);
end;

function TryRun(const ACommand, AStatement, AVersion: string; out AText: string): Boolean;
var
  mEdits: TArray<TRuleEdit>;
begin
  AText := Source(ACommand, AStatement);
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(11, 0), TSlashEnvironment.Create(nil,
    nil, nil, AVersion, '', nil), mEdits);
  if Result then
  begin
    AText := Apply(AText, mEdits);
  end;
end;

function Expand(const ACommand, AStatement: string; const AVersion: string): string; overload;
begin
  Assert.IsTrue(TryRun(ACommand, AStatement, AVersion, Result), ACommand + ' ' + AStatement);
  Assert.AreEqual(0, Pos(ACommand, Result), Result);
end;

function Expand(const ACommand, AStatement: string): string; overload;
begin
  Result := Expand(ACommand, AStatement, '');
end;

procedure TExpressionCommandsTests.FormatUsesTypes;
var
  mText: string;
begin
  mText := Expand('/format', '  S := ''Kunde '' + Name + '' hat '' + IntToStr(N) + '' Aufträge zu '' + ' +
    'FloatToStr(Preis) + '' (100%)'';');
  Assert.IsTrue(Pos('  S := Format(''Kunde %s hat %d Aufträge zu %g (100%%)'', [Name, N, Preis]);', mText) > 0,
    mText);
  mText := Expand('/format', '  S := ''Preis: '' + Preis;');
  Assert.IsTrue(Pos('Format(''Preis: %g'', [Preis])', mText) > 0, mText);
end;

procedure TExpressionCommandsTests.FormatUnknownTypeAddsHint;
var
  mText: string;
begin
  // Nicht über Expand: Der Hinweis nennt den Befehl selbst ("// /format: ...").
  Assert.IsTrue(TryRun('/format', '  ShowMessage(''Wert: '' + Liste.Text);', '', mText));
  Assert.AreEqual(0, Pos(#10'  /format', mText), mText);
  Assert.IsTrue(Pos('ShowMessage(Format(''Wert: %s'', [Liste.Text]));', mText) > 0, mText);
  Assert.IsTrue(Pos('// /format: Typ von Liste.Text unbekannt', mText) > 0, mText);
end;

procedure TExpressionCommandsTests.FormatWithoutConcatenationFails;
var
  mText: string;
begin
  Assert.IsFalse(TryRun('/format', '  S := ''nur Text'';', '', mText));
  Assert.IsFalse(TryRun('/format', '  Zaehler := Zaehler + 1;', '', mText));
end;

procedure TExpressionCommandsTests.MultilineBothWays;
var
  mText: string;
begin
  mText := Expand('/multiline', '  S := ''SELECT *'' + sLineBreak + ''FROM Kunde'';');
  Assert.IsTrue(Pos('  S := '''''''#10'    SELECT *'#10'    FROM Kunde'#10'    '''''';', mText) > 0, mText);
  mText := Expand('/multiline!', '  S := '''''''#10'    SELECT *'#10'    FROM Kunde'#10'    '''''';');
  Assert.IsTrue(Pos('''SELECT *'' + sLineBreak', mText) > 0, mText);
  Assert.IsTrue(Pos('''FROM Kunde'';', mText) > 0, mText);
end;

procedure TExpressionCommandsTests.MultilineNeedsDelphi12;
var
  mText: string;
begin
  // Delphi 11 (22.0) kennt keine mehrzeiligen Strings.
  Assert.IsFalse(TryRun('/multiline', '  S := ''a'' + sLineBreak + ''b'';', '22.0', mText));
  Assert.IsTrue(TryRun('/multiline', '  S := ''a'' + sLineBreak + ''b'';', '23.0', mText));
  Assert.IsFalse(TryRun('/multiline', '  S := ''nur eine Zeile'';', '', mText));
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
  mText: string;
begin
  // Delphi 12 (23.0) kennt keine Bedingungsausdrücke.
  Assert.IsFalse(TryRun('/iif', '  if N > 0 then S := ''ja'' else S := ''nein'';', '23.0', mText));
  Assert.IsFalse(TryRun('/iif', '  if N > 0 then S := ''ja'' else Name := ''nein'';', '', mText));
  Assert.IsFalse(TryRun('/iif', '  if N > 0 then begin S := ''ja''; end else S := ''nein'';', '', mText));
end;

procedure TExpressionCommandsTests.IncAndDec;
begin
  Assert.IsTrue(Pos('  Inc(Zaehler);', Expand('/inc', '  Zaehler := Zaehler + 1;')) > 0);
  Assert.IsTrue(Pos('  Dec(Zaehler, N * 2);', Expand('/inc', '  Zaehler := Zaehler - N * 2;')) > 0);
  Assert.IsTrue(Pos('  Inc(Werte[N], 3);', Expand('/inc', '  Werte[N] := Werte[N] + 3;')) > 0);
end;

procedure TExpressionCommandsTests.IncRejectsOtherShapes;
var
  mText: string;
begin
  Assert.IsFalse(TryRun('/inc', '  Zaehler := N + 1;', '', mText));
  Assert.IsFalse(TryRun('/inc', '  Zaehler := Zaehler - N + 1;', '', mText));
  Assert.IsFalse(TryRun('/inc', '  Preis := Preis + 0.5;', '', mText));
end;

procedure TExpressionCommandsTests.OutsideRoutineFails;
var
  mText: string;
begin
  mText := StringReplace(Source('', '  S := S;'), 'interface'#10, 'interface'#10'/inc'#10, []);
  Assert.AreEqual(1, Integer(Length(TSlashCommandRegistry.Shared.Problems(mText, nil))));
end;

procedure TExpressionCommandsTests.ModernUsesInlineVariable;
var
  mText: string;
begin
  mText := Expand('/modern', '  Zaehler := N;'#10'  Log(Zaehler);');
  Assert.IsTrue(Pos('  var Zaehler: Integer := N;', mText) > 0, mText);
  Assert.AreEqual(0, Pos('  Zaehler: Integer;', mText), mText);
end;

procedure TExpressionCommandsTests.ModernWithoutChangesFails;
var
  mText: string;
begin
  Assert.IsFalse(TryRun('/modern', '  Log(N);', '', mText));
  // Vor Delphi 10.3 keine Inline-Variablen.
  Assert.IsFalse(TryRun('/modern', '  Zaehler := N;', '19.0', mText));
  Assert.IsFalse(TryRun('/modern -inline', '  Zaehler := N;', '', mText));
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionCommandsTests);

end.
