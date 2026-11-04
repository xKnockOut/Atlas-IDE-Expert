unit Atlas.Common.Editing.Inlining.Method.Tests;

// Tests für „Methode einbetten“ (#103, Teil A) über TMethodInlining.Run:
// einfache Form, Titel nach Routine bzw. Methode und die Gründe der
// Ablehnung (Rekursion, Konstruktor, Argumente, mehrere Exit). Die
// ausführlichen Fälle stehen in Atlas.Common.Editing.Inlining.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodInliningTests = class
  public
    [Test]
    procedure SimpleFunctionReplacesCall;
    [Test]
    procedure RejectsRecursion;
    [Test]
    procedure RejectsConstructor;
    [Test]
    procedure RejectsTooManyArguments;
    [Test]
    procedure RejectsSeveralExits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.Inlining.Types,
  Atlas.Common.Editing.Inlining.Syntax,
  Atlas.Common.Editing.Inlining.Method;

/// <summary>Zeilen mit #10 dahinter, eingerahmt von einer leeren Unit.</summary>
function UnitOf(const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10;
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
  Result := Result + 'end.'#10;
end;

/// <summary>Bettet den Aufruf von AName in der Zeile ALine (ab 0) ein; Ergebnistext oder '-' mit Grund.</summary>
function InlineAt(const AText, AName: string; ALine: Integer; out ATitle, AReason: string): string;
var
  mTree: TSyntaxTree;
  mSource: TInlineSource;
  mRoutines: TArray<TSyntaxNode>;
  mAction: TCodeAction;
  mLine: string;
begin
  Result := '-';
  ATitle := '';
  mTree := TPascalParser.Parse(AText);
  try
    mSource := TInlineSource.Create('u.pas', AText, mTree);
    mRoutines := TInlineSyntax.FindRoutines(mTree, AName);
    mLine := AText.Split([#10])[ALine];
    if TMethodInlining.Run(mSource, TTextPosition.Create(ALine, Pos(AName, mLine)),
      TInlineCallee.Create(mSource, mRoutines[0]), TInlineOptions.Default, mAction, AReason) then
    begin
      ATitle := mAction.Title;
      Result := TChangeSignature.ApplyEdits(AText, mAction.Edits);
    end;
  finally
    mTree.Free;
  end;
end;

procedure TMethodInliningTests.SimpleFunctionReplacesCall;
var
  mTitle, mReason: string;
begin
  Assert.AreEqual(UnitOf(['function Twice(A: Integer): Integer;', 'begin', '  Result := A * 2;', 'end;',
    'procedure P(Y: Integer);', 'begin', '  Y := (Y * 2) + 1;', 'end;']),
    InlineAt(UnitOf(['function Twice(A: Integer): Integer;', 'begin', '  Result := A * 2;', 'end;',
    'procedure P(Y: Integer);', 'begin', '  Y := Twice(Y) + 1;', 'end;']), 'Twice', 9, mTitle, mReason), mReason);
  Assert.AreEqual('Routine Twice einbetten', mTitle);
end;

procedure TMethodInliningTests.RejectsRecursion;
var
  mTitle, mReason: string;
begin
  Assert.AreEqual('-', InlineAt(UnitOf(['procedure Loop(A: Integer);', 'begin', '  Loop(A);', 'end;',
    'procedure P;', 'begin', '  Loop(1);', 'end;']), 'Loop', 9, mTitle, mReason));
  Assert.AreEqual('rekursiv', mReason);
end;

procedure TMethodInliningTests.RejectsConstructor;
var
  mTitle, mReason: string;
begin
  Assert.AreEqual('-', InlineAt(UnitOf(['constructor TFoo.Make;', 'begin', 'end;', 'procedure TFoo.P;', 'begin',
    '  Make;', 'end;']), 'Make', 8, mTitle, mReason));
  Assert.AreEqual('Konstruktoren und Destruktoren', mReason);
end;

procedure TMethodInliningTests.RejectsTooManyArguments;
var
  mTitle, mReason: string;
begin
  Assert.AreEqual('-', InlineAt(UnitOf(['procedure Show(A: Integer);', 'begin', '  Writeln(A);', 'end;',
    'procedure P;', 'begin', '  Show(1, 2);', 'end;']), 'Show', 9, mTitle, mReason));
  Assert.AreEqual('zu viele Argumente', mReason);
end;

procedure TMethodInliningTests.RejectsSeveralExits;
var
  mTitle, mReason: string;
begin
  Assert.AreEqual('-', InlineAt(UnitOf(['function Pick(A: Integer): Integer;', 'begin', '  if A > 0 then',
    '    Exit(1);', '  Exit(2);', 'end;', 'procedure P(Y: Integer);', 'begin', '  Y := Pick(Y);', 'end;']),
    'Pick', 11, mTitle, mReason));
  Assert.AreEqual('mehrere Exit', mReason);
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodInliningTests);

end.
