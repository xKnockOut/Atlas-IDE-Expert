unit Atlas.Common.Lsp.DiagnosticItems.Tests;

// Tests für einzelne LSP-Diagnosen: Compilermeldungen, inaktive Bereiche, Präprozessor-Befunde, uses-Zustände
// und Formulardateien. Regeltreffer prüft Atlas.Common.Lsp.SyntaxDiagnostics.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspDiagnosticItemsTests = class
  public
    [Test]
    procedure CompilerMessageCoversIdentifier;
    [Test]
    procedure CompilerMessageWithoutColumnSkipsIndent;
    [Test]
    procedure CompilerMessageWithoutTextUsesColumnOrLine;
    [Test]
    procedure InactiveRegionCarriesConditionAndTarget;
    [Test]
    procedure IncludeCycleIsWarning;
    [Test]
    procedure NamesUsesStates;
    [Test]
    procedure FormParamsOnlyForFormFiles;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Lsp.DiagnosticItems;

function NewMessage(ALine, AColumn: Integer): TCompilerMessage;
begin
  Result := Default(TCompilerMessage);
  Result.Line := ALine;
  Result.Column := AColumn;
  Result.Severity := TCompilerSeverity.Warning;
  Result.Code := 'W1000';
  Result.Text := 'Symbol veraltet';
end;

procedure TLspDiagnosticItemsTests.CompilerMessageCoversIdentifier;
var
  mItem: TJSONObject;
begin
  mItem := TLspDiagnosticItems.CompilerMessageToJson(NewMessage(4, 2), '  Alt_1(x);', True);
  try
    Assert.AreEqual(4, mItem.GetValue<Integer>('range.start.line'));
    Assert.AreEqual(2, mItem.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(7, mItem.GetValue<Integer>('range.end.character'));
    Assert.AreEqual(2, mItem.GetValue<Integer>('severity'));
    Assert.AreEqual('W1000', mItem.GetValue<string>('code'));
    Assert.AreEqual(TLspDiagnosticItems.cCompilerSource, mItem.GetValue<string>('source'));
  finally
    mItem.Free;
  end;
end;

procedure TLspDiagnosticItemsTests.CompilerMessageWithoutColumnSkipsIndent;
var
  mItem: TJSONObject;
begin
  mItem := TLspDiagnosticItems.CompilerMessageToJson(NewMessage(1, -1), '    Exit;', True);
  try
    Assert.AreEqual(4, mItem.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(9, mItem.GetValue<Integer>('range.end.character'));
  finally
    mItem.Free;
  end;
end;

procedure TLspDiagnosticItemsTests.CompilerMessageWithoutTextUsesColumnOrLine;
var
  mItem: TJSONObject;
begin
  mItem := TLspDiagnosticItems.CompilerMessageToJson(NewMessage(3, 5), '', False);
  try
    Assert.AreEqual(5, mItem.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(6, mItem.GetValue<Integer>('range.end.character'));
  finally
    mItem.Free;
  end;
  // Ohne Spalte die ganze Zeile bis zum Anfang der nächsten.
  mItem := TLspDiagnosticItems.CompilerMessageToJson(NewMessage(-1, -1), '', False);
  try
    Assert.AreEqual(0, mItem.GetValue<Integer>('range.start.line'));
    Assert.AreEqual(1, mItem.GetValue<Integer>('range.end.line'));
  finally
    mItem.Free;
  end;
end;

procedure TLspDiagnosticItemsTests.InactiveRegionCarriesConditionAndTarget;
var
  mItem: TJSONObject;
begin
  mItem := TLspDiagnosticItems.InactiveToJson(TLspInactiveRegion.Create(TTextRange.Create(1, 0, 3, 0), 'WIN64'),
    'Win32', 'Debug');
  try
    Assert.AreEqual('Inaktiv: Bedingung WIN64 nicht erfüllt (Zielplattform Win32 · Debug)',
      mItem.GetValue<string>('message'));
    Assert.AreEqual('[1]', mItem.GetValue('tags').ToJSON);
    Assert.AreEqual('WIN64', mItem.GetValue<string>('data.inactive.condition'));
    Assert.AreEqual('Debug', mItem.GetValue<string>('data.inactive.config'));
  finally
    mItem.Free;
  end;
end;

procedure TLspDiagnosticItemsTests.IncludeCycleIsWarning;
var
  mIssue: TPreprocessorIssue;
  mItem: TJSONObject;
begin
  mIssue := Default(TPreprocessorIssue);
  mIssue.Kind := TPreprocessorIssueKind.IncludeCycle;
  mIssue.Message := 'Zyklus';
  mItem := TLspDiagnosticItems.IssueToJson(mIssue);
  try
    Assert.AreEqual(2, mItem.GetValue<Integer>('severity'));
    Assert.AreEqual('Zyklus', mItem.GetValue<string>('message'));
  finally
    mItem.Free;
  end;
  mIssue.Kind := TPreprocessorIssueKind.IncludeMissing;
  mItem := TLspDiagnosticItems.IssueToJson(mIssue);
  try
    Assert.AreEqual(4, mItem.GetValue<Integer>('severity'));
  finally
    mItem.Free;
  end;
end;

procedure TLspDiagnosticItemsTests.NamesUsesStates;
begin
  Assert.AreEqual('unused', TLspDiagnosticItems.UsesStateName(TUsesEntryState.Unused));
  Assert.AreEqual('initialization', TLspDiagnosticItems.UsesStateName(TUsesEntryState.KeptForInitialization));
  Assert.AreEqual('allowlist', TLspDiagnosticItems.UsesStateName(TUsesEntryState.KeptByAllowlist));
  Assert.AreEqual('implementation', TLspDiagnosticItems.UsesStateName(TUsesEntryState.OnlyImplementation));
  // Welche Regel ihr lsp-ignore und ihre Einstellungen für den Zustand gelten (#1135, #1136).
  Assert.AreEqual('unused-uses', TLspDiagnosticItems.UsesRuleOf(TUsesEntryState.Unused));
  Assert.AreEqual('uses-only-in-implementation', TLspDiagnosticItems.UsesRuleOf(TUsesEntryState.OnlyImplementation));
  Assert.AreEqual('', TLspDiagnosticItems.UsesRuleOf(TUsesEntryState.KeptForInitialization));
end;

procedure TLspDiagnosticItemsTests.FormParamsOnlyForFormFiles;
var
  mParams: TJSONObject;
begin
  Assert.IsFalse(TLspDiagnosticItems.TryFormParams('file:///c:/p/Main.pas', 'unit Main;', mParams));
  Assert.IsNull(mParams);
  Assert.IsTrue(TLspDiagnosticItems.TryFormParams('file:///c:/p/Main.dfm',
    'object Form1: TForm1' + sLineBreak + 'end' + sLineBreak, mParams));
  try
    Assert.AreEqual('file:///c:/p/Main.dfm', mParams.GetValue<string>('uri'));
    Assert.AreEqual(0, mParams.GetValue<TJSONArray>('diagnostics').Count);
  finally
    mParams.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDiagnosticItemsTests);

end.
