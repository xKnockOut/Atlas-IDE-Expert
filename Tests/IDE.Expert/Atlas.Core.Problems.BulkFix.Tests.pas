unit Atlas.Core.Problems.BulkFix.Tests;

// Tests für das Modell der Sammelkorrektur im Fenster „Atlas-Prüfung“
// (#1352): Dateien der Befunde einer Regel, Argumente für den Server, Lesen
// der Antwort, Auswahl (verworfene Dateien nicht wählbar) und das
// zusammengefasste WorkspaceEdit der gewählten Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBulkFixPreviewTests = class
  public
    [Test]
    procedure FilesOfRuleOnceInOrder;
    [Test]
    procedure ArgumentsNameRuleAndFiles;
    [Test]
    procedure ReadsAnswer;
    [Test]
    procedure RejectedFileCannotBeChecked;
    [Test]
    procedure SelectedEditJoinsCheckedFiles;
    [Test]
    procedure EmptyAnswerGivesEmptyPreview;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.BulkFix;

const
  cAnswer = '{"summary": "Vorschau: 3 Korrekturen in 2 Dateien, nichts geschrieben", "files": [' +
    '{"file": "C:\\P\\A.pas", "fixes": 2, "rejected": false, "rules": [{"rule": "unused-uses", "count": 2}], ' +
    '"diff": "--- a/A.pas", "edit": {"changes": {"file:///C:/P/A.pas": [{"range": {"start": {"line": 1, ' +
    '"character": 0}, "end": {"line": 2, "character": 0}}, "newText": ""}]}}},' +
    '{"file": "C:\\P\\B.pas", "fixes": 1, "rejected": false, "rules": [], "diff": "--- a/B.pas", ' +
    '"edit": {"changes": {"file:///C:/P/B.pas": [{"range": {"start": {"line": 3, "character": 2}, ' +
    '"end": {"line": 3, "character": 4}}, "newText": "x"}]}}},' +
    '{"file": "C:\\P\\C.pas", "fixes": 0, "rejected": true, "rules": []}]}';

function Finding(const AFileName, ARule: string; ASource: string): TAtlasFinding;
begin
  Result := Default(TAtlasFinding);
  Result.FileName := AFileName;
  Result.Problem.Code := ARule;
  Result.Problem.Source := ASource;
  if ASource = TAtlasProblem.CompilerSource then
    Result.Category := TAtlasFindingCategory.Compiler
  else
    Result.Category := TAtlasFindingCategory.CodeSmell;
end;

function Preview: TAtlasBulkFixPreview;
var
  mAnswer: TJSONValue;
begin
  mAnswer := TJSONObject.ParseJSONValue(cAnswer);
  try
    Result := TAtlasBulkFixPreview.Create('unused-uses', mAnswer);
  finally
    mAnswer.Free;
  end;
end;

procedure TAtlasBulkFixPreviewTests.FilesOfRuleOnceInOrder;
var
  mFiles: TArray<string>;
begin
  mFiles := TAtlasBulkFixPreview.FilesOf(TArray<TAtlasFinding>.Create(Finding('B.pas', 'unused-uses', 'atlas'),
    Finding('A.pas', 'redundant-cast', 'atlas'), Finding('A.pas', 'unused-uses', 'atlas'),
    Finding('b.pas', 'UNUSED-USES', 'atlas'), Finding('C.pas', 'unused-uses', TAtlasProblem.CompilerSource)),
    'unused-uses');
  Assert.AreEqual('B.pas|A.pas', string.Join('|', mFiles));
end;

procedure TAtlasBulkFixPreviewTests.ArgumentsNameRuleAndFiles;
var
  mArguments: TJSONValue;
  mOptions: TJSONObject;
begin
  mArguments := TJSONObject.ParseJSONValue(TAtlasBulkFixPreview.ArgumentsJson('unused-uses',
    TArray<string>.Create('C:\P\'#$00C4'.pas', 'C:\P\B.pas')));
  try
    Assert.IsTrue(mArguments is TJSONArray);
    mOptions := TJSONArray(mArguments).Items[0] as TJSONObject;
    Assert.AreEqual('unused-uses', mOptions.GetValue<TJSONArray>('rules').Items[0].Value);
    Assert.AreEqual(2, mOptions.GetValue<TJSONArray>('files').Count);
    Assert.AreEqual('C:\P\'#$00C4'.pas', mOptions.GetValue<TJSONArray>('files').Items[0].Value);
  finally
    mArguments.Free;
  end;
end;

procedure TAtlasBulkFixPreviewTests.ReadsAnswer;
var
  mPreview: TAtlasBulkFixPreview;
begin
  mPreview := Preview;
  try
    Assert.AreEqual('unused-uses', mPreview.Rule);
    Assert.StartsWith('Vorschau: 3 Korrekturen', mPreview.Summary);
    Assert.AreEqual(3, mPreview.Count);
    Assert.AreEqual('C:\P\A.pas', mPreview.Files[0].FileName);
    Assert.AreEqual(2, mPreview.Files[0].Fixes);
    Assert.AreEqual('--- a/A.pas', mPreview.Files[0].Diff);
    Assert.IsTrue(mPreview.Files[0].Checked);
    Assert.IsTrue(mPreview.Files[2].Rejected);
    Assert.IsFalse(mPreview.Files[2].Checked);
    Assert.AreEqual(2, mPreview.SelectedCount);
    Assert.AreEqual(3, mPreview.SelectedFixes);
  finally
    mPreview.Free;
  end;
end;

procedure TAtlasBulkFixPreviewTests.RejectedFileCannotBeChecked;
var
  mPreview: TAtlasBulkFixPreview;
begin
  mPreview := Preview;
  try
    mPreview.SetChecked(2, True);
    Assert.IsFalse(mPreview.Files[2].Checked);
    mPreview.SetChecked(0, False);
    Assert.IsFalse(mPreview.Files[0].Checked);
    Assert.AreEqual(1, mPreview.SelectedCount);
    Assert.AreEqual(1, mPreview.SelectedFixes);
    mPreview.SetChecked(7, True);
    Assert.AreEqual(1, mPreview.SelectedCount);
  finally
    mPreview.Free;
  end;
end;

procedure TAtlasBulkFixPreviewTests.SelectedEditJoinsCheckedFiles;
var
  mPreview: TAtlasBulkFixPreview;
  mEdit: TLspWorkspaceEdit;
begin
  mPreview := Preview;
  try
    mEdit := mPreview.SelectedEdit;
    Assert.AreEqual(2, Integer(Length(mEdit.Files)));
    Assert.AreEqual(2, mEdit.EditCount);
    Assert.AreEqual('x', mEdit.Files[1].Edits[0].NewText);
    mPreview.SetChecked(1, False);
    mEdit := mPreview.SelectedEdit;
    Assert.AreEqual(1, Integer(Length(mEdit.Files)));
    Assert.AreEqual(1, mEdit.Files[0].Edits[0].StartPos.Line);
  finally
    mPreview.Free;
  end;
end;

procedure TAtlasBulkFixPreviewTests.EmptyAnswerGivesEmptyPreview;
var
  mPreview: TAtlasBulkFixPreview;
begin
  mPreview := TAtlasBulkFixPreview.Create('x', nil);
  try
    Assert.AreEqual(0, mPreview.Count);
    Assert.AreEqual('', mPreview.Summary);
    Assert.IsTrue(mPreview.SelectedEdit.IsEmpty);
  finally
    mPreview.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBulkFixPreviewTests);

end.
