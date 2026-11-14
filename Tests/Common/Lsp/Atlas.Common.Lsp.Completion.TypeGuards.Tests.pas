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
  HauptFile = 'C:\P\Haupt.pas';

  UnitTypen =
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
    Index: Integer;
  begin
    for Index := 0 to ItemsOf(AResult).Count - 1 do
    begin
      Result := ItemsOf(AResult).Items[Index] as TJSONObject;
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
    Item: TJSONObject;
  begin
    Result := '';
    Item := ItemNamed(AResult, ALabel);
    if (Item <> nil) and (Item.FindValue('data.' + APath) <> nil) then
    begin
      Result := Item.FindValue('data.' + APath).Value;
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
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitTypen, 'C:\P\Typen.pas', nil));
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
  Marker, Index, Line, LineStart: Integer;
  Text, Uri: string;
  Request, Response: TJSONObject;
begin
  Marker := Pos('|', AText);
  Line := 0;
  LineStart := 1;
  for Index := 1 to Marker - 1 do
  begin
    if AText[Index] = #10 then
    begin
      Inc(Line);
      LineStart := Index + 1;
    end;
  end;
  Text := Copy(AText, 1, Marker - 1) + Copy(AText, Marker + 1, MaxInt);
  Uri := TDocumentUris.FromPath(HauptFile);
  FStore.Close(Uri);
  FStore.Open(Uri, 'delphi', 1, Text);
  Inc(FId);
  Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) +
    ',"method":"textDocument/completion","params":{"textDocument":{"uri":"' + Uri.Replace('\', '\\') +
    '"},"position":{"line":' + IntToStr(Line) + ',"character":' + IntToStr(Marker - LineStart) + '}}}') as
    TJSONObject;
  try
    Response := FDispatcher.DispatchMessage(Request);
  finally
    Request.Free;
  end;
  try
    Assert.IsTrue(Response.GetValue('result') is TJSONObject, Response.ToJSON);
    Result := Response.GetValue('result').Clone as TJSONObject;
  finally
    Response.Free;
  end;
end;

function TCompletionTypeGuardsTests.GuardOf(const ABody: string; AStrict: Boolean;
  const AByRef: TTypeGuardArgumentFunc; out AGuard: TTypeGuard): Boolean;
var
  Text: string;
  Marker: Integer;
  Tree: TSyntaxTree;
begin
  Text := HauptWith(ABody);
  Marker := Pos('|', Text);
  Text := Copy(Text, 1, Marker - 1) + Copy(Text, Marker + 1, MaxInt);
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Result := TCompletionTypeGuards.Find(Tree.Tokens, TokenFrom(Tree.Tokens, Marker - 1), AStrict, AByRef, AGuard);
  finally
    Tree.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.ThenBranchNarrows;
var
  Guard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Lies(nil);'#13#10 +
    '    |AWert.Text;'#13#10 +
    '  end;', False, nil, Guard));
  Assert.AreEqual('TObjekt', Guard.TypeName);
  Assert.AreEqual(6, Guard.Line);
  Assert.IsTrue(GuardOf('  if AWert is Typen.TObjekt then |AWert.Text;', False, nil, Guard));
  Assert.AreEqual('Typen.TObjekt', Guard.TypeName);
end;

procedure TCompletionTypeGuardsTests.AndChainNarrows;
var
  Guard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf('  if Assigned(AWert) and (AWert is TObjekt) then |AWert.Text;', False, nil, Guard));
  Assert.IsTrue(GuardOf('  if (AWert is TObjekt) and not (AWert is TListe) then |AWert.Text;', False, nil,
    Guard));
  Assert.AreEqual('TObjekt', Guard.TypeName);
end;

procedure TCompletionTypeGuardsTests.WhileConditionNarrows;
var
  Guard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf('  while AWert is TObjekt do |AWert.Text;', False, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.NegatedExitNarrowsToBlockEnd;
var
  Guard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf(
    '  if not (AWert is TObjekt) then'#13#10 +
    '    Exit;'#13#10 +
    '  Lies(nil);'#13#10 +
    '  |AWert.Text;', False, nil, Guard));
  Assert.IsTrue(GuardOf(
    '  if (AWert = nil) or not (AWert is TObjekt) then'#13#10 +
    '    raise Exception.Create(''x'');'#13#10 +
    '  |AWert.Text;', False, nil, Guard));
  Assert.IsTrue(GuardOf(
    '  if not (AWert is TObjekt) then begin Exit(False); end;'#13#10 +
    '  |AWert.Text;', False, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.NegatedWithoutJumpDoesNotNarrow;
var
  Guard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if not (AWert is TObjekt) then'#13#10 +
    '    Lies(nil);'#13#10 +
    '  |AWert.Text;', False, nil, Guard));
  Assert.IsFalse(GuardOf('  if not (AWert is TObjekt) then |AWert.Text;', False, nil, Guard));
  // Das not umfasst mehr als die Prüfung.
  Assert.IsFalse(GuardOf('  if not ((AWert is TObjekt) and Assigned(AWert)) then |AWert.Text;', False, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.OrChainDoesNotNarrow;
var
  Guard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf('  if (AWert is TObjekt) or (AWert = nil) then |AWert.Text;', False, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.ElseBranchDoesNotNarrow;
var
  Guard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '    Lies(nil)'#13#10 +
    '  else'#13#10 +
    '    |AWert.Text;', False, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.OutsideBlockDoesNotNarrow;
var
  Guard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Lies(nil);'#13#10 +
    '  end;'#13#10 +
    '  |AWert.Text;', False, nil, Guard));
  Assert.IsFalse(GuardOf(
    '  begin'#13#10 +
    '    if not (AWert is TObjekt) then Exit;'#13#10 +
    '  end;'#13#10 +
    '  |AWert.Text;', False, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.AssignmentStopsNarrowing;
var
  Guard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    AWert := nil;'#13#10 +
    '    |AWert.Text;'#13#10 +
    '  end;', False, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.VarArgumentStopsNarrowing;
var
  Guard: TTypeGuard;
  Calls: Integer;
begin
  Calls := 0;
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Aendere(AWert);'#13#10 +
    '    |AWert.Text;'#13#10 +
    '  end;', False,
    function(ACallOpen, AArgument: Integer): Boolean
    begin
      Inc(Calls);
      Assert.AreEqual(0, AArgument);
      Result := True;
    end, Guard));
  Assert.AreEqual(1, Calls);
  // Ohne Auskunft gilt jedes Argument als var.
  Assert.IsFalse(GuardOf('  if AWert is TObjekt then begin Lies(nil, AWert); |AWert.Text; end;', False, nil,
    Guard));
end;

procedure TCompletionTypeGuardsTests.PlainArgumentKeepsNarrowing;
var
  Guard: TTypeGuard;
  Arguments: string;
begin
  Arguments := '';
  Assert.IsTrue(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Lies(1, AWert);'#13#10 +
    '    Lies(TObjekt(AWert).Wert(''a''));'#13#10 +
    '    |AWert.Text;'#13#10 +
    '  end;', False,
    function(ACallOpen, AArgument: Integer): Boolean
    begin
      Arguments := Arguments + IntToStr(AArgument);
      Result := False;
    end, Guard));
  // Lies(1, AWert) und die Umwandlung TObjekt(AWert).
  Assert.AreEqual('10', Arguments);
end;

procedure TCompletionTypeGuardsTests.AssignmentLaterInLoopStopsNarrowing;
var
  Guard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '    while True do'#13#10 +
    '    begin'#13#10 +
    '      |AWert.Text;'#13#10 +
    '      AWert := nil;'#13#10 +
    '    end;', False, nil, Guard));
  // Ohne Schleife zählt die spätere Zuweisung nicht.
  Assert.IsTrue(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    |AWert.Text;'#13#10 +
    '    AWert := nil;'#13#10 +
    '  end;', False, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.FieldOnlyInFirstStatement;
var
  Guard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf('  if AWert is TObjekt then begin |AWert.Text;', True, nil, Guard));
  Assert.IsTrue(GuardOf('  if not (AWert is TObjekt) then Exit;'#13#10'  |AWert.Text;', True, nil, Guard));
  Assert.IsFalse(GuardOf('  if AWert is TObjekt then begin Lies(nil); |AWert.Text; end;', True, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.AnonymousMethodDoesNotNarrow;
var
  Guard: TTypeGuard;
begin
  Assert.IsFalse(GuardOf(
    '  if AWert is TObjekt then'#13#10 +
    '    Lauf(procedure begin |AWert.Text; end);', False, nil, Guard));
  Assert.IsFalse(GuardOf('  if AWert is TObjekt then with AWert do |AWert.Text;', False, nil, Guard));
end;

procedure TCompletionTypeGuardsTests.ClosestGuardWins;
var
  Guard: TTypeGuard;
begin
  Assert.IsTrue(GuardOf('  if AWert is TWert then if AWert is TObjekt then |AWert.Text;', False, nil, Guard));
  Assert.AreEqual('TObjekt', Guard.TypeName);
  // Andere Namen zählen nicht.
  Assert.IsFalse(GuardOf('  if Sender is TObjekt then |AWert.Text;', False, nil, Guard));
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
  Answer: TJSONObject;
  Item: TJSONObject;
begin
  Answer := Complete(HauptWith(
    '  if AWert is TObjekt then'#13#10 +
    '    AWert.|'));
  try
    Assert.AreEqual('TObjekt', DataOf(Answer, 'Anzahl', 'narrowed'));
    Assert.AreEqual('AWert', DataOf(Answer, 'Anzahl', 'narrowedName'));
    Assert.AreEqual('7', DataOf(Answer, 'Anzahl', 'narrowedLine'));
    Assert.AreEqual('TObjekt', DataOf(Answer, 'Wert', 'narrowed'));
    Item := ItemNamed(Answer, 'Anzahl');
    Assert.AreEqual('(AWert as TObjekt).Anzahl', Item.GetValue<string>('textEdit.newText'));
    Assert.AreEqual(4, Item.GetValue<Integer>('textEdit.range.start.character'));
    // Mitglieder des deklarierten Typs ohne Umwandlung und nur einmal.
    Assert.AreEqual('', DataOf(Answer, 'Text', 'narrowed'));
    Assert.IsNull(ItemNamed(Answer, 'Text').FindValue('textEdit'));
  finally
    Answer.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.HardCastFollowsSenderCast;
var
  Answer: TJSONObject;
begin
  FSettings.SenderCast := TCompletionSenderCast.HardCast;
  Answer := Complete(HauptWith(
    '  if not (AWert is TObjekt) then Exit;'#13#10 +
    '  AWert.Anz|'));
  try
    Assert.AreEqual('TObjekt(AWert).Anzahl', ItemNamed(Answer, 'Anzahl').GetValue<string>('textEdit.newText'));
  finally
    Answer.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.SwitchedOffOffersDeclaredMembersOnly;
var
  Answer: TJSONObject;
begin
  FSettings.TypeGuards := False;
  Answer := Complete(HauptWith(
    '  if AWert is TObjekt then'#13#10 +
    '    AWert.|'));
  try
    Assert.IsNull(ItemNamed(Answer, 'Anzahl'));
    Assert.IsNotNull(ItemNamed(Answer, 'Text'));
  finally
    Answer.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.VarCallInBetweenOffersDeclaredMembersOnly;
var
  Answer: TJSONObject;
begin
  Answer := Complete(HauptWith(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Aendere(AWert);'#13#10 +
    '    AWert.|'#13#10 +
    '  end;'));
  try
    Assert.IsNull(ItemNamed(Answer, 'Anzahl'));
  finally
    Answer.Free;
  end;
  Answer := Complete(HauptWith(
    '  if AWert is TObjekt then'#13#10 +
    '  begin'#13#10 +
    '    Lies(AWert);'#13#10 +
    '    AWert.|'#13#10 +
    '  end;'));
  try
    Assert.AreEqual('TObjekt', DataOf(Answer, 'Anzahl', 'narrowed'));
  finally
    Answer.Free;
  end;
end;

procedure TCompletionTypeGuardsTests.DescendantsAfterIsAreMarked;
var
  Answer: TJSONObject;
begin
  Answer := Complete(HauptWith('  if AWert is T|'));
  try
    Assert.AreEqual('TWert', DataOf(Answer, 'TObjekt', 'descendantOf'));
    Assert.AreEqual('TWert', DataOf(Answer, 'TListe', 'descendantOf'));
    Assert.AreEqual('', DataOf(Answer, 'TFremd', 'descendantOf'));
    Assert.AreEqual('', DataOf(Answer, 'TWert', 'descendantOf'));
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionTypeGuardsTests);

end.
