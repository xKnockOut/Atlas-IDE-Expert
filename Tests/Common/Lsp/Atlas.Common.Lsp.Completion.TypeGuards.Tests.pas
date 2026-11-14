unit Atlas.Common.Lsp.Completion.TypeGuards.Tests;

// Tests für die Vervollständigung nach Typprüfungen (#2107): Erkennung der Einengung auf den Token samt
// Ausschlüssen, Liste und eingesetzter Text über textDocument/completion, Nachfahren nach "X is ".

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.Completion.TypeGuards;

type
  [TestFixture]
  TCompletionTypeGuardsTests = class
  private
    FIndex: ISymbolIndex;
    FStore: IDocumentStore;
    FCompletion: TLspCompletion;
    FDispatcher: TJsonRpcDispatcher;
    FSettings: TCompletionSettings;
    FId: Integer;
    /// <summary>Fragt an der Stelle von "|" in AText. Der Aufrufer gibt frei.</summary>
    function Complete(const AText: string): TJSONObject;
    /// <summary>Find für den Bezeichner hinter "|" in der Routine mit ABody; AByRef nil = jedes Argument var.
    /// </summary>
    function GuardOf(const ABody: string; AStrict: Boolean; const AByRef: TTypeGuardArgumentFunc;
      out AGuard: TTypeGuard): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ThenBranchNarrows;
    [Test]
    procedure AndChainNarrows;
    [Test]
    procedure WhileConditionNarrows;
    [Test]
    procedure NegatedExitNarrowsToBlockEnd;
    [Test]
    procedure NegatedWithoutJumpDoesNotNarrow;
    [Test]
    procedure OrChainDoesNotNarrow;
    [Test]
    procedure ElseBranchDoesNotNarrow;
    [Test]
    procedure OutsideBlockDoesNotNarrow;
    [Test]
    procedure AssignmentStopsNarrowing;
    [Test]
    procedure VarArgumentStopsNarrowing;
    [Test]
    procedure PlainArgumentKeepsNarrowing;
    [Test]
    procedure AssignmentLaterInLoopStopsNarrowing;
    [Test]
    procedure FieldOnlyInFirstStatement;
    [Test]
    procedure AnonymousMethodDoesNotNarrow;
    [Test]
    procedure ClosestGuardWins;
    [Test]
    procedure ParamByRefReadsSignature;
    [Test]
    procedure MembersOfGuardedTypeComeWithCast;
    [Test]
    procedure HardCastFollowsSenderCast;
    [Test]
    procedure SwitchedOffOffersDeclaredMembersOnly;
    [Test]
    procedure VarCallInBetweenOffersDeclaredMembersOnly;
    [Test]
    procedure DescendantsAfterIsAreMarked;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitTypen =
    'unit Typen;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TWert = class'#13#10 +
    '  public'#13#10 +
    '    function Text: string;'#13#10 +
    '  end;'#13#10 +
    '  TObjekt = class(TWert)'#13#10 +
    '  public'#13#10 +
    '    Anzahl: Integer;'#13#10 +
    '    function Wert(const AName: string): TWert;'#13#10 +
    '  end;'#13#10 +
    '  TListe = class(TWert)'#13#10 +
    '  end;'#13#10 +
    '  TFremd = class'#13#10 +
    '  end;'#13#10 +
    'procedure Aendere(var AWert: TWert);'#13#10 +
    'procedure Lies(AWert: TWert);'#13#10 +
    'implementation'#13#10 +
    'function TWert.Text: string; begin end;'#13#10 +
    'function TObjekt.Wert(const AName: string): TWert; begin end;'#13#10 +
    'procedure Aendere(var AWert: TWert); begin end;'#13#10 +
    'procedure Lies(AWert: TWert); begin end;'#13#10 +
    'end.';

  /// <summary>Unit Haupt mit einer Routine Pruefe(AWert: TWert), ABody zwischen begin und end.</summary>
  function HauptWith(const ABody: string): string;
  begin
    Result :=
      'unit Haupt;'#13#10 +
      'interface'#13#10 +
      'uses Typen;'#13#10 +
      'implementation'#13#10 +
      'procedure Pruefe(AWert: TWert);'#13#10 +
      'begin'#13#10 +
      ABody + #13#10 +
      'end;'#13#10 +
      'end.';
  end;

  function ItemsOf(AResult: TJSONObject): TJSONArray;
  begin
    Result := AResult.GetValue('items') as TJSONArray;
  end;

  /// <summary>Eintrag mit dem Label ALabel; nil ohne.</summary>
  function ItemNamed(AResult: TJSONObject; const ALabel: string): TJSONObject;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ItemsOf(AResult).Count - 1 do
    begin
      Result := ItemsOf(AResult).Items[mIndex] as TJSONObject;
      if Result.GetValue<string>('label') = ALabel then
      begin
        Exit;
      end;
    end;
    Result := nil;
  end;

  /// <summary>Wert unter data.APath des Eintrags ALabel; '' ohne.</summary>
  function DataOf(AResult: TJSONObject; const ALabel, APath: string): string;
  var
    mItem: TJSONObject;
  begin
    Result := '';
    mItem := ItemNamed(AResult, ALabel);
    if (mItem <> nil) and (mItem.FindValue('data.' + APath) <> nil) then
    begin
      Result := mItem.FindValue('data.' + APath).Value;
    end;
  end;

{ TCompletionTypeGuardsTests }

procedure TCompletionTypeGuardsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FStore := TDocumentStore.Create;
  FSettings := TCompletionSettings.Default;
  FId := 0;
  FCompletion := TLspCompletion.Create(FStore, FIndex);
  FCompletion.Hooks.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := FSettings;
    end;
  FDispatcher := TJsonRpcDispatcher.Create;
  FCompletion.Attach(FDispatcher);
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitTypen, 'C:\P\Typen.pas', nil));
end;

procedure TCompletionTypeGuardsTests.TearDown;
begin
  FDispatcher.Free;
  FCompletion.Free;
  FStore := nil;
  FIndex := nil;
end;

function TCompletionTypeGuardsTests.Complete(const AText: string): TJSONObject;
var
  mMarker, mIndex, mLine, mLineStart: Integer;
  mText, mUri: string;
  mRequest, mResponse: TJSONObject;
begin
  mMarker := Pos('|', AText);
  mLine := 0;
  mLineStart := 1;
  for mIndex := 1 to mMarker - 1 do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
      mLineStart := mIndex + 1;
    end;
  end;
  mText := Copy(AText, 1, mMarker - 1) + Copy(AText, mMarker + 1, MaxInt);
  mUri := TDocumentUris.FromPath(cHauptFile);
  FStore.Close(mUri);
  FStore.Open(mUri, 'delphi', 1, mText);
  Inc(FId);
  mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) +
    ',"method":"textDocument/completion","params":{"textDocument":{"uri":"' + mUri.Replace('\', '\\') +
    '"},"position":{"line":' + IntToStr(mLine) + ',"character":' + IntToStr(mMarker - mLineStart) + '}}}') as
    TJSONObject;
  try
    mResponse := FDispatcher.DispatchMessage(mRequest);
  finally
    mRequest.Free;
  end;
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONObject, mResponse.ToJSON);
    Result := mResponse.GetValue('result').Clone as TJSONObject;
  finally
    mResponse.Free;
  end;
end;

function TCompletionTypeGuardsTests.GuardOf(const ABody: string; AStrict: Boolean;
  const AByRef: TTypeGuardArgumentFunc; out AGuard: TTypeGuard): Boolean;
var
  mText: string;
  mMarker: Integer;
  mTree: TSyntaxTree;
begin
  mText := HauptWith(ABody);
  mMarker := Pos('|', mText);
  mText := Copy(mText, 1, mMarker - 1) + Copy(mText, mMarker + 1, MaxInt);
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Result := TCompletionTypeGuards.Find(mTree.Tokens, TokenFrom(mTree.Tokens, mMarker - 1), AStrict, AByRef, AGuard);
  finally
    mTree.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.ThenBranchNarrows;
var
  mGuard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Lies(nil);'#13#10 +
    '    |AWert.Text;'#13#10 +
    '  end;', False, nil, mGuard));
  Assert.AreEqual('TObjekt', mGuard.TypeName);
  Assert.AreEqual(6, mGuard.Line);
  Assert.IsTrue(GuardOf('  if AWert is Typen.TObjekt then |AWert.Text;', False, nil, mGuard));
  Assert.AreEqual('Typen.TObjekt', mGuard.TypeName);
end;

procedure TCompletionTypeGuardsTests.AndChainNarrows;
var
  mGuard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf('  if Assigned(AWert) and (AWert is TObjekt) then |AWert.Text;', False, nil, mGuard));
  Assert.IsTrue(GuardOf('  if (AWert is TObjekt) and not (AWert is TListe) then |AWert.Text;', False, nil,
    mGuard));
  Assert.AreEqual('TObjekt', mGuard.TypeName);
end;

procedure TCompletionTypeGuardsTests.WhileConditionNarrows;
var
  mGuard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf('  while AWert is TObjekt do |AWert.Text;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.NegatedExitNarrowsToBlockEnd;
var
  mGuard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf(
    '  if not (AWert is TObjekt) then'#13#10 +
    '    Exit;'#13#10 +
    '  Lies(nil);'#13#10 +
    '  |AWert.Text;', False, nil, mGuard));
  Assert.IsTrue(GuardOf(
    '  if (AWert = nil) or not (AWert is TObjekt) then'#13#10 +
    '    raise Exception.Create(''x'');'#13#10 +
    '  |AWert.Text;', False, nil, mGuard));
  Assert.IsTrue(GuardOf(
    '  if not (AWert is TObjekt) then begin Exit(False); end;'#13#10 +
    '  |AWert.Text;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.NegatedWithoutJumpDoesNotNarrow;
var
  mGuard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if not (AWert is TObjekt) then'#13#10 +
    '    Lies(nil);'#13#10 +
    '  |AWert.Text;', False, nil, mGuard));
  Assert.IsFalse(GuardOf('  if not (AWert is TObjekt) then |AWert.Text;', False, nil, mGuard));
  // Das not umfasst mehr als die Prüfung.
  Assert.IsFalse(GuardOf('  if not ((AWert is TObjekt) and Assigned(AWert)) then |AWert.Text;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.OrChainDoesNotNarrow;
var
  mGuard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf('  if (AWert is TObjekt) or (AWert = nil) then |AWert.Text;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.ElseBranchDoesNotNarrow;
var
  mGuard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '    Lies(nil)'#13#10 +
    '  else'#13#10 +
    '    |AWert.Text;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.OutsideBlockDoesNotNarrow;
var
  mGuard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Lies(nil);'#13#10 +
    '  end;'#13#10 +
    '  |AWert.Text;', False, nil, mGuard));
  Assert.IsFalse(GuardOf(
    '  begin'#13#10 +
    '    if not (AWert is TObjekt) then Exit;'#13#10 +
    '  end;'#13#10 +
    '  |AWert.Text;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.AssignmentStopsNarrowing;
var
  mGuard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    AWert := nil;'#13#10 +
    '    |AWert.Text;'#13#10 +
    '  end;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.VarArgumentStopsNarrowing;
var
  mGuard: TTypeGuard;
  mCalls: Integer;
begin
  mCalls := 0;
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Aendere(AWert);'#13#10 +
    '    |AWert.Text;'#13#10 +
    '  end;', False,
    function(ACallOpen, AArgument: Integer): Boolean
    begin
      Inc(mCalls);
      Assert.AreEqual(0, AArgument);
      Result := True;
    end, mGuard));
  Assert.AreEqual(1, mCalls);
  // Ohne Auskunft gilt jedes Argument als var.
  Assert.IsFalse(GuardOf('  if AWert is TObjekt then begin Lies(nil, AWert); |AWert.Text; end;', False, nil,
    mGuard));
end;

procedure TCompletionTypeGuardsTests.PlainArgumentKeepsNarrowing;
var
  mGuard: TTypeGuard;
  mArguments: string;
begin
  mArguments := '';
  Assert.IsTrue(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Lies(1, AWert);'#13#10 +
    '    Lies(TObjekt(AWert).Wert(''a''));'#13#10 +
    '    |AWert.Text;'#13#10 +
    '  end;', False,
    function(ACallOpen, AArgument: Integer): Boolean
    begin
      mArguments := mArguments + IntToStr(AArgument);
      Result := False;
    end, mGuard));
  // Lies(1, AWert) und die Umwandlung TObjekt(AWert).
  Assert.AreEqual('10', mArguments);
end;

procedure TCompletionTypeGuardsTests.AssignmentLaterInLoopStopsNarrowing;
var
  mGuard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '    while True do'#13#10 +
    '    begin'#13#10 +
    '      |AWert.Text;'#13#10 +
    '      AWert := nil;'#13#10 +
    '    end;', False, nil, mGuard));
  // Ohne Schleife zählt die spätere Zuweisung nicht.
  Assert.IsTrue(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    |AWert.Text;'#13#10 +
    '    AWert := nil;'#13#10 +
    '  end;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.FieldOnlyInFirstStatement;
var
  mGuard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf('  if AWert is TObjekt then begin |AWert.Text;', True, nil, mGuard));
  Assert.IsTrue(GuardOf('  if not (AWert is TObjekt) then Exit;'#13#10'  |AWert.Text;', True, nil, mGuard));
  Assert.IsFalse(GuardOf('  if AWert is TObjekt then begin Lies(nil); |AWert.Text; end;', True, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.AnonymousMethodDoesNotNarrow;
var
  mGuard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '    Lauf(procedure begin |AWert.Text; end);', False, nil, mGuard));
  Assert.IsFalse(GuardOf('  if AWert is TObjekt then with AWert do |AWert.Text;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.ClosestGuardWins;
var
  mGuard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf('  if AWert is TWert then if AWert is TObjekt then |AWert.Text;', False, nil, mGuard));
  Assert.AreEqual('TObjekt', mGuard.TypeName);
  // Andere Namen zählen nicht.
  Assert.IsFalse(GuardOf('  if Sender is TObjekt then |AWert.Text;', False, nil, mGuard));
end;

procedure TCompletionTypeGuardsTests.ParamByRefReadsSignature;
begin
  Assert.IsTrue(TCompletionTypeGuards.ParamByRef('procedure Aendere(var AWert: TWert)', 0));
  Assert.IsFalse(TCompletionTypeGuards.ParamByRef('procedure Lies(AWert: TWert)', 0));
  Assert.IsTrue(TCompletionTypeGuards.ParamByRef('procedure P(const A, B: string; out C: TObject)', 2));
  Assert.IsFalse(TCompletionTypeGuards.ParamByRef('procedure P(const A, B: string; out C: TObject)', 1));
  Assert.IsFalse(TCompletionTypeGuards.ParamByRef('function F(A: TArray<string>; B: Integer): Boolean', 1));
  // Mehr Argumente als Parameter: im Zweifel var.
  Assert.IsTrue(TCompletionTypeGuards.ParamByRef('procedure Lies(AWert: TWert)', 1));
end;

procedure TCompletionTypeGuardsTests.MembersOfGuardedTypeComeWithCast;
var
  mAnswer: TJSONObject;
  mItem: TJSONObject;
begin
  mAnswer := Complete(HauptWith(
    '  if AWert is TObjekt then'#13#10 +
    '    AWert.|'));
  try
    Assert.AreEqual('TObjekt', DataOf(mAnswer, 'Anzahl', 'narrowed'));
    Assert.AreEqual('AWert', DataOf(mAnswer, 'Anzahl', 'narrowedName'));
    Assert.AreEqual('7', DataOf(mAnswer, 'Anzahl', 'narrowedLine'));
    Assert.AreEqual('TObjekt', DataOf(mAnswer, 'Wert', 'narrowed'));
    mItem := ItemNamed(mAnswer, 'Anzahl');
    Assert.AreEqual('(AWert as TObjekt).Anzahl', mItem.GetValue<string>('textEdit.newText'));
    Assert.AreEqual(4, mItem.GetValue<Integer>('textEdit.range.start.character'));
    // Mitglieder des deklarierten Typs ohne Umwandlung und nur einmal.
    Assert.AreEqual('', DataOf(mAnswer, 'Text', 'narrowed'));
    Assert.IsNull(ItemNamed(mAnswer, 'Text').FindValue('textEdit'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.HardCastFollowsSenderCast;
var
  mAnswer: TJSONObject;
begin
  FSettings.SenderCast := TCompletionSenderCast.HardCast;
  mAnswer := Complete(HauptWith(
    '  if not (AWert is TObjekt) then Exit;'#13#10 +
    '  AWert.Anz|'));
  try
    Assert.AreEqual('TObjekt(AWert).Anzahl', ItemNamed(mAnswer, 'Anzahl').GetValue<string>('textEdit.newText'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.SwitchedOffOffersDeclaredMembersOnly;
var
  mAnswer: TJSONObject;
begin
  FSettings.TypeGuards := False;
  mAnswer := Complete(HauptWith(
    '  if AWert is TObjekt then'#13#10 +
    '    AWert.|'));
  try
    Assert.IsNull(ItemNamed(mAnswer, 'Anzahl'));
    Assert.IsNotNull(ItemNamed(mAnswer, 'Text'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.VarCallInBetweenOffersDeclaredMembersOnly;
var
  mAnswer: TJSONObject;
begin
  mAnswer := Complete(HauptWith(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Aendere(AWert);'#13#10 +
    '    AWert.|'#13#10 +
    '  end;'));
  try
    Assert.IsNull(ItemNamed(mAnswer, 'Anzahl'));
  finally
    mAnswer.Free;
  end;
  mAnswer := Complete(HauptWith(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Lies(AWert);'#13#10 +
    '    AWert.|'#13#10 +
    '  end;'));
  try
    Assert.AreEqual('TObjekt', DataOf(mAnswer, 'Anzahl', 'narrowed'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.DescendantsAfterIsAreMarked;
var
  mAnswer: TJSONObject;
begin
  mAnswer := Complete(HauptWith('  if AWert is T|'));
  try
    Assert.AreEqual('TWert', DataOf(mAnswer, 'TObjekt', 'descendantOf'));
    Assert.AreEqual('TWert', DataOf(mAnswer, 'TListe', 'descendantOf'));
    Assert.AreEqual('', DataOf(mAnswer, 'TFremd', 'descendantOf'));
    Assert.AreEqual('', DataOf(mAnswer, 'TWert', 'descendantOf'));
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionTypeGuardsTests);

end.
