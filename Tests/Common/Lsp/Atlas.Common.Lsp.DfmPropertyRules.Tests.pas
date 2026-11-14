unit Atlas.Common.Lsp.DfmPropertyRules.Tests;

// Tests für den Befehl „Eigenschaftsregeln anwenden“ (#309) und Code-Aktionen,
// die eine andere Datei als das Dokument ändern (Korrektur in der Formulardatei).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspDfmPropertyRulesTests = class
  public
    [Test]
    procedure CollectsFormEditsOfAllUnits;
    [Test]
    procedure SkipsOverlappingAndUnitEdits;
    [Test]
    procedure MapsFormFilesToUnits;
    [Test]
    procedure ActionWithFormEditsLeavesDocument;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.DfmPropertyRules;

const
  cUnitA = 'C:\P\A.pas';
  cUnitB = 'C:\P\B.pas';
  cUnitC = 'C:\P\C.pas';

function Finding(const ARuleId, AFileName: string; ALine: Integer; const ANewText: string): TRuleFinding;
var
  mFix: TRuleFix;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Range := TTextRange.Create(ALine, 0, ALine, 4);
  mFix := TRuleFix.Create('Korrektur', [TRuleEdit.Create(TTextRange.Create(ALine, 4, ALine, 9), ANewText)]);
  mFix.FileName := AFileName;
  Result.Fixes := [mFix];
end;

function Check(const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean;
begin
  AFindings := nil;
  Result := not SameText(AFileName, cUnitC);
  if SameText(AFileName, cUnitA) then
  begin
    AFindings := [Finding('dfm-property', 'C:\P\A.dfm', 3, 'True'), Finding('dfm-property', 'C:\P\A.dfm', 5, '[a]')];
  end
  else if SameText(AFileName, cUnitB) then
  begin
    AFindings := [Finding('dfm-property', 'C:\P\B.dfm', 1, '0')];
  end;
end;

procedure TLspDfmPropertyRulesTests.CollectsFormEditsOfAllUnits;
var
  mEdit: TJSONObject;
  mChanges: TJSONArray;
  mFiles, mEdits: Integer;
  mUri: string;
  mFirst: TJSONObject;
begin
  // C hat kein Formular, A kommt doppelt: zwei Dateien, drei Änderungen.
  mEdit := TLspDfmPropertyRules.BuildEdit([cUnitA, cUnitB, cUnitC, cUnitA], Check, mFiles, mEdits);
  try
    Assert.AreEqual(2, mFiles);
    Assert.AreEqual(3, mEdits);
    mChanges := mEdit.GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual(2, Integer(mChanges.Count));
    mUri := mChanges.Items[0].GetValue<string>('textDocument.uri');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\A.dfm'), mUri);
    Assert.AreEqual(2, (mChanges.Items[0].GetValue<TJSONArray>('edits')).Count);
    mFirst := (mChanges.Items[0].GetValue<TJSONArray>('edits')).Items[0] as TJSONObject;
    Assert.AreEqual('dfmPropertyRules', mFirst.GetValue<string>('annotationId'));
    Assert.AreEqual('True', mFirst.GetValue<string>('newText'));
    // Bestätigung durch den Benutzer (Änderungsanmerkung).
    Assert.IsTrue(mEdit.GetValue<Boolean>('changeAnnotations.dfmPropertyRules.needsConfirmation'));
    Assert.AreEqual('3 Änderungen in 2 Formulardateien',
      mEdit.GetValue<string>('changeAnnotations.dfmPropertyRules.description'));
  finally
    mEdit.Free;
  end;
end;

function CheckOverlap(const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean;
var
  mUnitFix: TRuleFinding;
begin
  // Zwei Regeln auf denselben Wert und eine Korrektur in der Unit selbst.
  mUnitFix := Finding('dfm-property', '', 2, 'x');
  AFindings := [Finding('dfm-property', 'C:\P\A.dfm', 3, 'True'), Finding('dfm-property', 'C:\P\A.dfm', 3, 'False'),
    mUnitFix, Finding('other-rule', 'C:\P\A.dfm', 7, 'y')];
  Result := True;
end;

procedure TLspDfmPropertyRulesTests.SkipsOverlappingAndUnitEdits;
var
  mEdit, mDocument: TJSONObject;
  mItems: TJSONArray;
  mFiles, mEdits: Integer;
begin
  mEdit := TLspDfmPropertyRules.BuildEdit([cUnitA], CheckOverlap, mFiles, mEdits);
  try
    Assert.AreEqual(1, mFiles);
    Assert.AreEqual(1, mEdits, 'die erste Korrektur gilt, die überlappende entfällt');
    mDocument := (mEdit.GetValue('documentChanges') as TJSONArray).Items[0] as TJSONObject;
    mItems := mDocument.GetValue('edits') as TJSONArray;
    Assert.AreEqual('True', (mItems.Items[0] as TJSONObject).GetValue<string>('newText'));
  finally
    mEdit.Free;
  end;
end;

procedure TLspDfmPropertyRulesTests.MapsFormFilesToUnits;
begin
  Assert.AreEqual('C:\P\A.pas', TLspDfmPropertyRules.UnitOf('C:\P\A.dfm'));
  Assert.AreEqual('C:\P\A.pas', TLspDfmPropertyRules.UnitOf('C:\P\A.fmx'));
  Assert.AreEqual('C:\P\A.pas', TLspDfmPropertyRules.UnitOf('C:\P\A.pas'));
end;

procedure TLspDfmPropertyRulesTests.ActionWithFormEditsLeavesDocument;
var
  mActions: TArray<TCodeAction>;
  mJson: TJSONObject;
  mChanges: TJSONObject;
begin
  mActions := TRuleCodeActions.ForFindings([Finding('dfm-property', 'C:\P\A.dfm', 3, 'True')], 'unit A;',
    TTextRange.Create(3, 0, 3, 0));
  Assert.IsTrue(Length(mActions) > 0);
  Assert.AreEqual(0, Integer(Length(mActions[0].Edits)));
  Assert.AreEqual('C:\P\A.dfm', mActions[0].FileEdits[0].FileName);
  mJson := TLspCodeActions.ActionToJson(TDocumentUris.FromPath(cUnitA), mActions[0]);
  try
    mChanges := mJson.GetValue<TJSONObject>('edit.changes');
    Assert.AreEqual(1, Integer(mChanges.Count), 'nur die Formulardatei');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\A.dfm'), mChanges.Pairs[0].JsonString.Value);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDfmPropertyRulesTests);

end.
