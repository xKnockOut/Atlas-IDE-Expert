unit Atlas.Common.Lsp.FindingsMemo.Tests;

// Treffer der Prüfregeln je Datei und Text (2.0-stable): Die Diagnose legt ab, die Code-Aktion liest am selben Text
// und rechnet die Regeln nicht noch einmal.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleFindingsMemoTests = class
  public
    [Test]
    procedure GivesFindingsForSameText;
    [Test]
    procedure MissesForOtherTextOrFile;
    [Test]
    procedure FileNameIgnoresCase;
    [Test]
    procedure DropsLeastRecentlyUsed;
    [Test]
    procedure HandsOutCopies;
    [Test]
    procedure DiagnosticsFillMemo;
    [Test]
    procedure CodeActionReadsMemo;
    [Test]
    procedure CodeActionFillsMemo;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.FindingsMemo;

const
  cLB = #13#10;
  cFileName = 'C:\P\Haupt.pas';
  cText = 'program Haupt;' + cLB + 'begin' + cLB + '  A := 1;' + cLB + 'end.';

/// <summary>Ein Treffer der Regel ARuleId in Zeile ALine mit einer Korrektur ATitle.</summary>
function Finding(const ARuleId: string; ALine: Integer; const ATitle: string): TRuleFinding;
var
  mFix: TRuleFix;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARuleId;
  Result.Range := TTextRange.Create(ALine, 0, ALine, 4);
  Result.Message := 'Meldung';
  mFix := Default(TRuleFix);
  mFix.Title := ATitle;
  Result.Fixes := [mFix];
end;

/// <summary>Regelumfeld mit allen Regeln, Datei und AMemo.</summary>
function RulesWith(const AMemo: IRuleFindingsMemo): TRuleCheckContext;
begin
  Result := Default(TRuleCheckContext);
  Result.Rules := BuiltinRules;
  Result.Settings := TServerSettings.Default;
  Result.RelativePath := 'Haupt.pas';
  Result.FileName := cFileName;
  Result.Memo := AMemo;
end;

/// <summary>Titel aller Code-Aktionen in Zeile ALine von cText, mit "|" getrennt.</summary>
function ActionTitles(const AMemo: IRuleFindingsMemo; ALine: Integer): string;
var
  mStore: IDocumentStore;
  mActions: TLspCodeActions;
  mDispatcher: TJsonRpcDispatcher;
  mUri: string;
  mRequest, mResponse: TJSONObject;
  mItem: TJSONValue;
  mProvider: TRuleContextProvider;
begin
  mStore := TDocumentStore.Create;
  mUri := TDocumentUris.FromPath(cFileName);
  mStore.Open(mUri, 'delphi', 1, cText);
  mProvider :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      AContext := RulesWith(AMemo);
      Result := True;
    end;
  mActions := TLspCodeActions.Create(mStore, mProvider);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mActions.Attach(mDispatcher);
    mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"textDocument/codeAction",' +
      '"params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') + '"},"range":{"start":{"line":' +
      IntToStr(ALine) + ',"character":0},"end":{"line":' + IntToStr(ALine) +
      ',"character":0}},"context":{"diagnostics":[]}}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
    finally
      mRequest.Free;
    end;
    try
      Result := '';
      for mItem in mResponse.GetValue('result') as TJSONArray do
      begin
        Result := Result + (mItem as TJSONObject).GetValue('title').Value + '|';
      end;
    finally
      mResponse.Free;
    end;
  finally
    mDispatcher.Free;
    mActions.Free;
  end;
end;

{ TRuleFindingsMemoTests }

procedure TRuleFindingsMemoTests.GivesFindingsForSameText;
var
  mMemo: IRuleFindingsMemo;
  mFound: TArray<TRuleFinding>;
begin
  mMemo := TRuleFindingsMemo.Create;
  mMemo.Put(cFileName, cText, [Finding('regel-a', 2, 'Korrektur A')]);
  Assert.IsTrue(mMemo.TryGet(cFileName, cText, mFound));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('regel-a', mFound[0].RuleId);
end;

procedure TRuleFindingsMemoTests.MissesForOtherTextOrFile;
var
  mMemo: IRuleFindingsMemo;
  mFound: TArray<TRuleFinding>;
begin
  mMemo := TRuleFindingsMemo.Create;
  mMemo.Put(cFileName, cText, [Finding('regel-a', 2, 'Korrektur A')]);
  Assert.IsFalse(mMemo.TryGet(cFileName, cText + ' ', mFound), 'anderer Text');
  Assert.AreEqual(0, Integer(Length(mFound)));
  Assert.IsFalse(mMemo.TryGet('C:\P\Andere.pas', cText, mFound), 'andere Datei');
end;

procedure TRuleFindingsMemoTests.FileNameIgnoresCase;
var
  mMemo: IRuleFindingsMemo;
  mFound: TArray<TRuleFinding>;
begin
  mMemo := TRuleFindingsMemo.Create;
  mMemo.Put(cFileName, cText, [Finding('regel-a', 2, 'Korrektur A')]);
  Assert.IsTrue(mMemo.TryGet(UpperCase(cFileName), cText, mFound));
  // Ein neuer Lauf ersetzt den Eintrag derselben Datei.
  mMemo.Put(LowerCase(cFileName), cText, nil);
  Assert.IsTrue(mMemo.TryGet(cFileName, cText, mFound));
  Assert.AreEqual(0, Integer(Length(mFound)));
end;

procedure TRuleFindingsMemoTests.DropsLeastRecentlyUsed;
var
  mMemo: IRuleFindingsMemo;
  mFound: TArray<TRuleFinding>;
  mIndex: Integer;
begin
  mMemo := TRuleFindingsMemo.Create;
  for mIndex := 1 to TRuleFindingsMemo.MaxEntries do
  begin
    mMemo.Put(Format('C:\P\U%d.pas', [mIndex]), cText, nil);
  end;
  // U1 benutzt, U2 ist damit der älteste.
  Assert.IsTrue(mMemo.TryGet('C:\P\U1.pas', cText, mFound));
  mMemo.Put('C:\P\Neu.pas', cText, nil);
  Assert.IsTrue(mMemo.TryGet('C:\P\U1.pas', cText, mFound), 'zuletzt benutzt bleibt');
  Assert.IsFalse(mMemo.TryGet('C:\P\U2.pas', cText, mFound), 'ältester fällt heraus');
  Assert.IsTrue(mMemo.TryGet('C:\P\Neu.pas', cText, mFound));
end;

procedure TRuleFindingsMemoTests.HandsOutCopies;
var
  mMemo: IRuleFindingsMemo;
  mFound, mAgain: TArray<TRuleFinding>;
begin
  mMemo := TRuleFindingsMemo.Create;
  mMemo.Put(cFileName, cText, [Finding('regel-a', 2, 'Korrektur A')]);
  Assert.IsTrue(mMemo.TryGet(cFileName, cText, mFound));
  mFound[0].RuleId := 'geaendert';
  Assert.IsTrue(mMemo.TryGet(cFileName, cText, mAgain));
  Assert.AreEqual('regel-a', mAgain[0].RuleId);
end;

procedure TRuleFindingsMemoTests.DiagnosticsFillMemo;
var
  mStore: IDocumentStore;
  mDocument: ITextDocument;
  mMemo: IRuleFindingsMemo;
  mParams: TJSONObject;
  mFound: TArray<TRuleFinding>;
begin
  mStore := TDocumentStore.Create;
  mDocument := mStore.Open(TDocumentUris.FromPath(cFileName), 'objectpascal', 1, cText);
  mMemo := TRuleFindingsMemo.Create;
  mParams := TLspSyntaxDiagnostics.BuildParams(mDocument, nil, '', RulesWith(mMemo));
  try
    Assert.IsTrue(mMemo.TryGet(cFileName, cText, mFound), 'die Diagnose legt ihre Treffer ab');
  finally
    mParams.Free;
  end;
end;

procedure TRuleFindingsMemoTests.CodeActionReadsMemo;
var
  mMemo: IRuleFindingsMemo;
begin
  mMemo := TRuleFindingsMemo.Create;
  // Diesen Treffer meldet keine Regel; erscheint seine Korrektur, kam er aus dem Memo.
  mMemo.Put(cFileName, cText, [Finding('aus-dem-memo', 2, 'Korrektur aus dem Memo')]);
  Assert.Contains(ActionTitles(mMemo, 2), 'Korrektur aus dem Memo');
end;

procedure TRuleFindingsMemoTests.CodeActionFillsMemo;
var
  mMemo: IRuleFindingsMemo;
  mFound: TArray<TRuleFinding>;
begin
  mMemo := TRuleFindingsMemo.Create;
  ActionTitles(mMemo, 2);
  Assert.IsTrue(mMemo.TryGet(cFileName, cText, mFound), 'die Code-Aktion legt ihren Lauf ab');
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleFindingsMemoTests);

end.
