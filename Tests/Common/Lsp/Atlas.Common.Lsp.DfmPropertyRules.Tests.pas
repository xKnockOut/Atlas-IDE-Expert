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
  UnitA = 'C:\P\A.pas';
  UnitB = 'C:\P\B.pas';
  UnitC = 'C:\P\C.pas';

function Finding(const ARuleId, AFileName: string; ALine: Integer; const ANewText: string): TRuleFinding;
var
  Fix: TRuleFix;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Range := TTextRange.Create(ALine, 0, ALine, 4);
  Fix := TRuleFix.Create('Korrektur', [TRuleEdit.Create(TTextRange.Create(ALine, 4, ALine, 9), ANewText)]);
  Fix.FileName := AFileName;
  Result.Fixes := [Fix];
end;

function Check(const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean;
begin
  AFindings := nil;
  Result := not SameText(AFileName, UnitC);
  if SameText(AFileName, UnitA) then
    AFindings := [Finding('dfm-property', 'C:\P\A.dfm', 3, 'True'), Finding('dfm-property', 'C:\P\A.dfm', 5, '[a]')]
  else if SameText(AFileName, UnitB) then
    AFindings := [Finding('dfm-property', 'C:\P\B.dfm', 1, '0')];
end;

procedure TLspDfmPropertyRulesTests.CollectsFormEditsOfAllUnits;
var
  Edit: TJSONObject;
  Changes: TJSONArray;
  Files, Edits: Integer;
  Uri: string;
  First: TJSONObject;
begin
  // C hat kein Formular, A kommt doppelt: zwei Dateien, drei Änderungen.
  Edit := TLspDfmPropertyRules.BuildEdit([UnitA, UnitB, UnitC, UnitA], Check, Files, Edits);
  try
    Assert.AreEqual(2, Files);
    Assert.AreEqual(3, Edits);
    Changes := Edit.GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual(2, Integer(Changes.Count));
    Uri := Changes.Items[0].GetValue<string>('textDocument.uri');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\A.dfm'), Uri);
    Assert.AreEqual(2, (Changes.Items[0].GetValue<TJSONArray>('edits')).Count);
    First := (Changes.Items[0].GetValue<TJSONArray>('edits')).Items[0] as TJSONObject;
    Assert.AreEqual('dfmPropertyRules', First.GetValue<string>('annotationId'));
    Assert.AreEqual('True', First.GetValue<string>('newText'));
    // Bestätigung durch den Benutzer (Änderungsanmerkung).
    Assert.IsTrue(Edit.GetValue<Boolean>('changeAnnotations.dfmPropertyRules.needsConfirmation'));
    Assert.AreEqual('3 Änderungen in 2 Formulardateien',
      Edit.GetValue<string>('changeAnnotations.dfmPropertyRules.description'));
  finally
    Edit.Free;
  end;
end;

function CheckOverlap(const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean;
var
  UnitFix: TRuleFinding;
begin
  // Zwei Regeln auf denselben Wert und eine Korrektur in der Unit selbst.
  UnitFix := Finding('dfm-property', '', 2, 'x');
  AFindings := [Finding('dfm-property', 'C:\P\A.dfm', 3, 'True'), Finding('dfm-property', 'C:\P\A.dfm', 3, 'False'),
    UnitFix, Finding('other-rule', 'C:\P\A.dfm', 7, 'y')];
  Result := True;
end;

procedure TLspDfmPropertyRulesTests.SkipsOverlappingAndUnitEdits;
var
  Edit, Document: TJSONObject;
  Items: TJSONArray;
  Files, Edits: Integer;
begin
  Edit := TLspDfmPropertyRules.BuildEdit([UnitA], CheckOverlap, Files, Edits);
  try
    Assert.AreEqual(1, Files);
    Assert.AreEqual(1, Edits, 'die erste Korrektur gilt, die überlappende entfällt');
    Document := (Edit.GetValue('documentChanges') as TJSONArray).Items[0] as TJSONObject;
    Items := Document.GetValue('edits') as TJSONArray;
    Assert.AreEqual('True', (Items.Items[0] as TJSONObject).GetValue<string>('newText'));
  finally
    Edit.Free;
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
  Actions: TArray<TCodeAction>;
  Json: TJSONObject;
  Changes: TJSONObject;
begin
  Actions := TRuleCodeActions.ForFindings([Finding('dfm-property', 'C:\P\A.dfm', 3, 'True')], 'unit A;',
    TTextRange.Create(3, 0, 3, 0));
  Assert.IsTrue(Length(Actions) > 0);
  Assert.AreEqual(0, Integer(Length(Actions[0].Edits)));
  Assert.AreEqual('C:\P\A.dfm', Actions[0].FileEdits[0].FileName);
  Json := TLspCodeActions.ActionToJson(TDocumentUris.FromPath(UnitA), Actions[0]);
  try
    Changes := Json.GetValue<TJSONObject>('edit.changes');
    Assert.AreEqual(1, Integer(Changes.Count), 'nur die Formulardatei');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\A.dfm'), Changes.Pairs[0].JsonString.Value);
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDfmPropertyRulesTests);

end.
