unit Atlas.Core.Problems.AtCaret.Tests;

// Tests für den Atlas-Befund unter der Schreibmarke (#1886, #1967): gegen eine Fälschung des oberen Editors
// und einen echten Befundspeicher, ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProblemAtCaretTests = class
  public
    [Test]
    procedure ReturnsRuleOfAtlasProblemAtCaret;
    /// <summary>Compilermeldungen und Befunde ohne Code haben keine Regelseite; der nächste Befund zählt.</summary>
    [Test]
    procedure SkipsCompilerMessagesAndProblemsWithoutCode;
    [Test]
    procedure CaretBesideProblemGivesNothing;
    [Test]
    procedure NoEditorOrNoStoreGivesNothing;
  end;

implementation

uses
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Files.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.AtCaret,
  Atlas.Tests.EditorFilesFake;

const
  cFile = 'C:\P\A.pas';

function Problem(ALine, ACharacter: Integer; const ACode, ASource: string): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.StartCharacter := ACharacter;
  Result.EndLine := ALine;
  Result.EndCharacter := ACharacter + 3;
  Result.Message := 'Befund';
  Result.Code := ACode;
  Result.Source := ASource;
  Result.Severity := TAtlasProblemSeverity.Warning;
end;

function EditorAt(ALine, ACharacter: Integer): IAtlasActiveEditor;
begin
  Result := TAtlasActiveEditorFake.Create(TAtlasActiveEditorPos.At(cFile, ALine, ACharacter));
end;

procedure TAtlasProblemAtCaretTests.ReturnsRuleOfAtlasProblemAtCaret;
var
  mStore: TAtlasProblemStore;
  mRule: string;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update(cFile, 'a'#10'  b := 1;', True, [Problem(1, 2, 'magic-number', 'Atlas')], '1', False);
    Assert.IsTrue(TAtlasProblemAtCaret.Rule(EditorAt(1, 3), mStore, mRule));
    Assert.AreEqual('magic-number', mRule);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemAtCaretTests.SkipsCompilerMessagesAndProblemsWithoutCode;
var
  mStore: TAtlasProblemStore;
  mRule: string;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update(cFile, 'abcdef', True, [Problem(0, 0, 'E2003', TAtlasProblem.cCompilerSource),
      Problem(0, 0, '', 'Atlas'), Problem(0, 1, 'unused-variable', 'Atlas')], '1', False);
    Assert.IsTrue(TAtlasProblemAtCaret.Rule(EditorAt(0, 2), mStore, mRule));
    Assert.AreEqual('unused-variable', mRule);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemAtCaretTests.CaretBesideProblemGivesNothing;
var
  mStore: TAtlasProblemStore;
  mRule: string;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update(cFile, 'a'#10'b', True, [Problem(0, 0, 'magic-number', 'Atlas')], '1', False);
    Assert.IsFalse(TAtlasProblemAtCaret.Rule(EditorAt(1, 0), mStore, mRule));
    Assert.AreEqual('', mRule);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProblemAtCaretTests.NoEditorOrNoStoreGivesNothing;
var
  mStore: TAtlasProblemStore;
  mEditor: IAtlasActiveEditor;
  mRule: string;
begin
  mStore := TAtlasProblemStore.Create;
  try
    mStore.Update(cFile, 'abc', True, [Problem(0, 0, 'magic-number', 'Atlas')], '1', False);
    mEditor := TAtlasActiveEditorFake.Create(TAtlasActiveEditorPos.None);
    Assert.IsFalse(TAtlasProblemAtCaret.Rule(mEditor, mStore, mRule), 'ohne Editor');
    Assert.IsFalse(TAtlasProblemAtCaret.Rule(EditorAt(0, 1), nil, mRule), 'ohne Speicher');
    Assert.IsFalse(TAtlasProblemAtCaret.Rule(nil, mStore, mRule), 'ohne Schnittstelle');
  finally
    mStore.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProblemAtCaretTests);

end.
