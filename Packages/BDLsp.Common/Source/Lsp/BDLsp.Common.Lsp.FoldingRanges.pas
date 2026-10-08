unit BDLsp.Common.Lsp.FoldingRanges;

// Faltbereiche für textDocument/foldingRange: Klassen und andere strukturierte
// Typen, Routinen, begin/end- und andere Anweisungsblöcke, Deklarations-
// abschnitte, uses-Klauseln, {$REGION}/{$ENDREGION} und Kommentarblöcke.
// Nur Bereiche über mehrere Zeilen; je Startzeile höchstens einer.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  System.Generics.Collections,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree;

type
  TFoldingRange = record
    StartLine: Integer;
    EndLine: Integer;
    /// <summary>FoldingRangeKind des LSP: 'comment', 'imports', 'region' oder leer.</summary>
    Kind: string;
    constructor Create(AStartLine, AEndLine: Integer; const AKind: string);
  end;

  TLspFoldingRanges = class
  public const
    Method = 'textDocument/foldingRange';
  private
    FStore: IDocumentStore;
    function HandleFoldingRange(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore);
    /// <summary>Registriert die Anfrage am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Faltbereiche des Baums, nach Startzeile sortiert.</summary>
    class function Collect(ATree: TSyntaxTree): TArray<TFoldingRange>; static;
    /// <summary>Antwort im Format des LSP. Der Aufrufer übernimmt das Array.</summary>
    class function ToJson(const ARanges: TArray<TFoldingRange>): TJSONArray; static;
  end;

implementation

uses
  System.Generics.Defaults,
  BDLsp.Common.Dfm.Contract,
  BDLsp.Common.Dfm.Parser,
  BDLsp.Common.Lsp.FormFiles,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.TreeCache,
  BDLsp.Common.Lsp.Internals.Cancellation;

const
  KindComment = 'comment';
  KindImports = 'imports';
  KindRegion = 'region';

procedure AddRange(AList: TList<TFoldingRange>; AStartLine, AEndLine: Integer; const AKind: string);
begin
  if AEndLine > AStartLine then
    AList.Add(TFoldingRange.Create(AStartLine, AEndLine, AKind));
end;

procedure CollectNodes(ARoot: TSyntaxNode; AList: TList<TFoldingRange>);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Iterativ, damit auch sehr tiefe Bäume (lange Ausdrucksketten) den Stapel nicht sprengen.
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      case Node.Kind of
        TSyntaxKind.UsesClause:
          AddRange(AList, Node.StartPos.Line, Node.EndPos.Line, KindImports);
        TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
        TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection,
        TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection,
        TSyntaxKind.TypeDecl, TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
        TSyntaxKind.InterfaceType, TSyntaxKind.HelperType,
        TSyntaxKind.RoutineDecl, TSyntaxKind.Block, TSyntaxKind.AsmBlock,
        TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse,
        TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
        TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
        TSyntaxKind.ExceptBlock, TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptionHandler,
        TSyntaxKind.AnonymousMethod, TSyntaxKind.SetConstructor, TSyntaxKind.Call:
          AddRange(AList, Node.StartPos.Line, Node.EndPos.Line, '');
      end;
      for Index := 0 to Node.ChildCount - 1 do
        Pending.Push(Node[Index]);
    end;
  finally
    Pending.Free;
  end;
end;

function IsDirective(const AToken: TPascalToken; const AName: string): Boolean;
var
  Text: string;
begin
  // {$REGION 'x'} oder (*$REGION*); Groß- und Kleinschreibung egal.
  Text := AToken.Text;
  if Text.StartsWith('{$') then
    Text := Text.Substring(2)
  else if Text.StartsWith('(*$') then
    Text := Text.Substring(3)
  else
    Exit(False);
  Result := Text.ToUpper.StartsWith(AName) and
    ((Length(Text) = Length(AName)) or not CharInSet(Text.Chars[Length(AName)], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

procedure CollectTokens(const ATokens: TArray<TPascalToken>; AList: TList<TFoldingRange>);
var
  Regions: TStack<Integer>;
  Token: TPascalToken;
  LineStart: Integer;
  LineEnd: Integer;
  PreviousLine: Integer;
begin
  Regions := TStack<Integer>.Create;
  try
    LineStart := -1;
    LineEnd := -1;
    PreviousLine := -1;
    for Token in ATokens do
    begin
      if Token.Kind = TPascalTokenKind.Directive then
      begin
        if IsDirective(Token, 'REGION') then
          Regions.Push(Token.StartPos.Line)
        else if IsDirective(Token, 'ENDREGION') and (Regions.Count > 0) then
          AddRange(AList, Regions.Pop, Token.EndPos.Line, KindRegion);
      end;
      if (Token.Kind = TPascalTokenKind.Comment) and Token.Text.StartsWith('//') and
        (Token.StartPos.Line > PreviousLine) then
      begin
        // Zeilenkommentar am Zeilenanfang: Block fortsetzen oder neu beginnen.
        if (LineStart >= 0) and (Token.StartPos.Line = LineEnd + 1) then
          LineEnd := Token.StartPos.Line
        else
        begin
          if LineStart >= 0 then
            AddRange(AList, LineStart, LineEnd, KindComment);
          LineStart := Token.StartPos.Line;
          LineEnd := LineStart;
        end;
      end
      else if Token.Kind = TPascalTokenKind.Comment then
        // Blockkommentar über mehrere Zeilen.
        AddRange(AList, Token.StartPos.Line, Token.EndPos.Line, KindComment);
      PreviousLine := Token.EndPos.Line;
    end;
    if LineStart >= 0 then
      AddRange(AList, LineStart, LineEnd, KindComment);
  finally
    Regions.Free;
  end;
end;

{ TFoldingRange }

constructor TFoldingRange.Create(AStartLine, AEndLine: Integer; const AKind: string);
begin
  StartLine := AStartLine;
  EndLine := AEndLine;
  Kind := AKind;
end;

{ TLspFoldingRanges }

constructor TLspFoldingRanges.Create(const AStore: IDocumentStore);
begin
  inherited Create;
  FStore := AStore;
end;

procedure TLspFoldingRanges.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Nebenläufig: Parsen großer Dateien blockiert die Nachrichtenschleife nicht.
  ADispatcher.RegisterConcurrentRequest(Method, HandleFoldingRange);
end;

class function TLspFoldingRanges.Collect(ATree: TSyntaxTree): TArray<TFoldingRange>;
var
  List: TList<TFoldingRange>;
  Unique: TList<TFoldingRange>;
  Range: TFoldingRange;
begin
  List := TList<TFoldingRange>.Create;
  Unique := TList<TFoldingRange>.Create;
  try
    CollectNodes(ATree.Root, List);
    CollectTokens(ATree.Tokens, List);
    // Nach Startzeile, bei gleicher Startzeile der größte Bereich zuerst.
    List.Sort(TComparer<TFoldingRange>.Construct(
      function(const ALeft, ARight: TFoldingRange): Integer
      begin
        Result := ALeft.StartLine - ARight.StartLine;
        if Result = 0 then
          Result := ARight.EndLine - ALeft.EndLine;
      end));
    for Range in List do
      if (Unique.Count = 0) or (Unique.Last.StartLine <> Range.StartLine) then
        Unique.Add(Range);
    Result := Unique.ToArray;
  finally
    Unique.Free;
    List.Free;
  end;
end;

class function TLspFoldingRanges.ToJson(const ARanges: TArray<TFoldingRange>): TJSONArray;
var
  Range: TFoldingRange;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Range in ARanges do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('startLine', TJSONNumber.Create(Range.StartLine));
    Item.AddPair('endLine', TJSONNumber.Create(Range.EndLine));
    if Range.Kind <> '' then
      Item.AddPair('kind', Range.Kind);
    Result.AddElement(Item);
  end;
end;

function TLspFoldingRanges.HandleFoldingRange(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Form: TDfmDocument;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt in ' + Method);
  // Nicht geöffnete Dokumente haben keine Faltbereiche.
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  // Formulardateien (#44) haben einen eigenen Baum.
  if TDfmParser.IsFormFile(Uri) then
  begin
    Form := TDfmParser.Parse(Document.Text);
    try
      Exit(TLspFormFiles.BuildFoldingRanges(Form));
    finally
      Form.Free;
    end;
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Result := ToJson(Collect(Tree));
end;

end.
