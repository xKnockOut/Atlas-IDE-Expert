unit Atlas.Common.Lsp.FoldingRanges;

// Faltbereiche für textDocument/foldingRange: Klassen und andere strukturierte
// Typen, Routinen, begin/end- und andere Anweisungsblöcke, Deklarations-
// abschnitte, uses-Klauseln, {$REGION}/{$ENDREGION} und Kommentarblöcke.
// Nur Bereiche über mehrere Zeilen; je Startzeile höchstens einer.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

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
    cMethod = 'textDocument/foldingRange';
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
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Lsp.FormFiles,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFoldingRangesText = (FieldTextDocumentUriMissingIn);

const
  cTexts: array[TFoldingRangesText] of TAtlasText = (
    (De: 'Feld "textDocument.uri" fehlt in '; En: 'Field "textDocument.uri" missing in '));

{$SCOPEDENUMS OFF}

const
  cKindComment = 'comment';
  cKindImports = 'imports';
  cKindRegion = 'region';

procedure AddRange(AList: TList<TFoldingRange>; AStartLine, AEndLine: Integer; const AKind: string);
begin
  if AEndLine > AStartLine then
  begin
    AList.Add(TFoldingRange.Create(AStartLine, AEndLine, AKind));
  end;
end;

procedure CollectNodes(ARoot: TSyntaxNode; AList: TList<TFoldingRange>);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ, damit auch sehr tiefe Bäume (lange Ausdrucksketten) den Stapel nicht sprengen.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      case mNode.Kind of
        TSyntaxKind.UsesClause:
          AddRange(AList, mNode.StartPos.Line, mNode.EndPos.Line, cKindImports);
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
          AddRange(AList, mNode.StartPos.Line, mNode.EndPos.Line, '');
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      for mIndex := 0 to mNode.ChildCount - 1 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function IsDirective(const AToken: TPascalToken; const AName: string): Boolean;
var
  mText: string;
begin
  // {$REGION 'x'} oder (*$REGION*); Groß- und Kleinschreibung egal.
  mText := AToken.Text;
  if mText.StartsWith('{$') then
  begin
    mText := mText.Substring(2);
  end
  else if mText.StartsWith('(*$') then
  begin
    mText := mText.Substring(3);
  end
  else
  begin
    Exit(False);
  end;
  Result := mText.ToUpper.StartsWith(AName) and
    ((Length(mText) = Length(AName)) or not CharInSet(mText.Chars[Length(AName)], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

type
  /// <summary>Faltbereiche aus Tokens: Regionen und Kommentarblöcke.</summary>
  TTokenFolds = record
    List: TList<TFoldingRange>;
    Regions: TStack<Integer>;
    /// <summary>Erste und letzte Zeile des laufenden Blocks aus Zeilenkommentaren (-1 = keiner).</summary>
    LineStart: Integer;
    LineEnd: Integer;
    /// <summary>Letzte Zeile des vorigen Tokens.</summary>
    PreviousLine: Integer;
    procedure Directive(const AToken: TPascalToken);
    procedure LineComment(const AToken: TPascalToken);
    procedure Comment(const AToken: TPascalToken);
    procedure CloseLineComments;
  end;

procedure TTokenFolds.Directive(const AToken: TPascalToken);
begin
  if IsDirective(AToken, 'REGION') then
  begin
    Regions.Push(AToken.StartPos.Line);
  end
  else if IsDirective(AToken, 'ENDREGION') and (Regions.Count > 0) then
  begin
    AddRange(List, Regions.Pop, AToken.EndPos.Line, cKindRegion);
  end;
end;

procedure TTokenFolds.CloseLineComments;
begin
  if LineStart >= 0 then
  begin
    AddRange(List, LineStart, LineEnd, cKindComment);
  end;
end;

procedure TTokenFolds.LineComment(const AToken: TPascalToken);
begin
  // Zeilenkommentar am Zeilenanfang: Block fortsetzen oder neu beginnen.
  if (LineStart >= 0) and (AToken.StartPos.Line = LineEnd + 1) then
  begin
    LineEnd := AToken.StartPos.Line;
    Exit;
  end;
  CloseLineComments;
  LineStart := AToken.StartPos.Line;
  LineEnd := LineStart;
end;

procedure TTokenFolds.Comment(const AToken: TPascalToken);
begin
  if AToken.Text.StartsWith('//') and (AToken.StartPos.Line > PreviousLine) then
  begin
    LineComment(AToken);
  end
  else
  begin
    // Blockkommentar über mehrere Zeilen.
    AddRange(List, AToken.StartPos.Line, AToken.EndPos.Line, cKindComment);
  end;
end;

procedure CollectTokens(const ATokens: TArray<TPascalToken>; AList: TList<TFoldingRange>);
var
  mFolds: TTokenFolds;
  mToken: TPascalToken;
begin
  mFolds := Default(TTokenFolds);
  mFolds.List := AList;
  mFolds.LineStart := -1;
  mFolds.LineEnd := -1;
  mFolds.PreviousLine := -1;
  mFolds.Regions := TStack<Integer>.Create;
  try
    for mToken in ATokens do
    begin
      if mToken.Kind = TPascalTokenKind.Directive then
      begin
        mFolds.Directive(mToken);
      end
      else if mToken.Kind = TPascalTokenKind.Comment then
      begin
        mFolds.Comment(mToken);
      end;
      mFolds.PreviousLine := mToken.EndPos.Line;
    end;
    mFolds.CloseLineComments;
  finally
    mFolds.Regions.Free;
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
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleFoldingRange);
end;

class function TLspFoldingRanges.Collect(ATree: TSyntaxTree): TArray<TFoldingRange>;
var
  mList: TList<TFoldingRange>;
  mUnique: TList<TFoldingRange>;
  mRange: TFoldingRange;
begin
  mList := TList<TFoldingRange>.Create;
  mUnique := TList<TFoldingRange>.Create;
  try
    CollectNodes(ATree.Root, mList);
    CollectTokens(ATree.Tokens, mList);
    // Nach Startzeile, bei gleicher Startzeile der größte Bereich zuerst.
    mList.Sort(TComparer<TFoldingRange>.Construct(
      function(const ALeft, ARight: TFoldingRange): Integer
      begin
        Result := ALeft.StartLine - ARight.StartLine;
        if Result = 0 then
        begin
          Result := ARight.EndLine - ALeft.EndLine;
        end;
      end));
    for mRange in mList do
    begin
      if (mUnique.Count = 0) or (mUnique.Last.StartLine <> mRange.StartLine) then
      begin
        mUnique.Add(mRange);
      end;
    end;
    Result := mUnique.ToArray;
  finally
    mUnique.Free;
    mList.Free;
  end;
end;

class function TLspFoldingRanges.ToJson(const ARanges: TArray<TFoldingRange>): TJSONArray;
var
  mRange: TFoldingRange;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mRange in ARanges do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('startLine', TJSONNumber.Create(mRange.StartLine));
    mItem.AddPair('endLine', TJSONNumber.Create(mRange.EndLine));
    if mRange.Kind <> '' then
    begin
      mItem.AddPair('kind', mRange.Kind);
    end;
    Result.AddElement(mItem);
  end;
end;

function TLspFoldingRanges.HandleFoldingRange(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mForm: TDfmDocument;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TFoldingRangesText.FieldTextDocumentUriMissingIn].Text + cMethod);
  end;
  // Nicht geöffnete Dokumente haben keine Faltbereiche.
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  // Formulardateien (#44) haben einen eigenen Baum.
  if TDfmParser.IsFormFile(mUri) then
  begin
    mForm := TDfmParser.Parse(mDocument.Text);
    try
      Exit(TLspFormFiles.BuildFoldingRanges(mForm));
    finally
      mForm.Free;
    end;
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mTree := mShared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Result := ToJson(Collect(mTree));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.FoldingRanges', cTexts);

end.
