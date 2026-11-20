unit Atlas.Common.Lsp.BlockFolds;

// Anweisungsblöcke zum Einklappen (#2795): atlas/blockFolds liefert je Block in
// einer Routine (begin/end eines if-, else-, Schleifen-, with-, case- oder
// on-Zweigs, try, repeat, case … of) die Stelle hinter dem öffnenden und hinter
// dem schließenden Token und eine Kopfzeile. Der Delphi-Editor faltet solche
// Blöcke nicht; das Plugin setzt an diese Stellen vorübergehend eine Region.
// Der begin/end-Rumpf einer Routine oder anonymen Methode zählt nicht, den
// faltet die IDE selbst. Nur Blöcke über mehrere Zeilen. Positionen 0-basiert
// in UTF-16-Einheiten wie im LSP.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TBlockFold = record
    /// <summary>if, else, for, while, with, case, on, try, repeat oder begin.</summary>
    Kind: string;
    /// <summary>Hinter dem öffnenden Token (begin, try, repeat, of).</summary>
    OpenPos: TTextPosition;
    /// <summary>Hinter dem schließenden Token (end bzw. Ende des until-Ausdrucks).</summary>
    ClosePos: TTextPosition;
    /// <summary>Kopf des Blocks wie „if mWert > 5 then“, eine Zeile, ohne Kommentare.</summary>
    Caption: string;
  end;

  TLspBlockFolds = class
  public const
    cMethod = 'atlas/blockFolds';
    /// <summary>Längste Kopfzeile; länger wird mit … gekürzt.</summary>
    cMaxCaption = 80;
  private
    FStore: IDocumentStore;
    function HandleBlockFolds(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore);
    /// <summary>Registriert die Anfrage am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Blöcke des Baums, nach öffnender Stelle sortiert.</summary>
    class function Collect(ATree: TSyntaxTree): TArray<TBlockFold>; static;
    /// <summary>Antwort {"blocks": [...]}; der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const ABlocks: TArray<TBlockFold>): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBlockFoldsText = (FieldTextDocumentUriMissingIn);

const
  cTexts: array[TBlockFoldsText] of TAtlasText = (
    (De: 'Feld "textDocument.uri" fehlt in '; En: 'Field "textDocument.uri" missing in '));

{$SCOPEDENUMS OFF}

type
  /// <summary>Sammelt die Blöcke eines Baums.</summary>
  TBlockCollector = record
    Tree: TSyntaxTree;
    List: TList<TBlockFold>;
    /// <summary>Code-Token von AFromOffset bis einschließlich ALast, Leerraum zu einem Leerzeichen.</summary>
    function TextOf(AFromOffset, ALast: Integer): string;
    procedure Add(const AKind: string; AOpener: Integer; const AClosePos: TTextPosition; const ACaption: string);
    procedure AddBlock(ANode: TSyntaxNode);
    procedure AddStatement(ANode: TSyntaxNode);
    procedure AddCase(ANode: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode);
  end;

/// <summary>Kopfzeile, die in {$REGION '…'} und (*$REGION '…'*) sicher steht.</summary>
function SafeCaption(const AText: string): string;
begin
  Result := AText.Replace('''', '"').Replace('}', ')').Replace('*)', '* )');
  if Length(Result) > TLspBlockFolds.cMaxCaption then
  begin
    Result := Copy(Result, 1, TLspBlockFolds.cMaxCaption - 1) + #$2026;
  end;
end;

{ TBlockCollector }

function TBlockCollector.TextOf(AFromOffset, ALast: Integer): string;
var
  mIndex: Integer;
  mToken: TPascalToken;
  mEnd: Integer;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mEnd := -1;
    for mIndex := Tree.FirstTokenFrom(AFromOffset) to ALast do
    begin
      mToken := Tree.Tokens[mIndex];
      if not IsCode(mToken) then
      begin
        Continue;
      end;
      if (mEnd >= 0) and (mToken.Offset > mEnd) then
      begin
        mBuilder.Append(' ');
      end;
      mBuilder.Append(mToken.Text);
      mEnd := mToken.Offset + Length(mToken.Text);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure TBlockCollector.Add(const AKind: string; AOpener: Integer; const AClosePos: TTextPosition;
  const ACaption: string);
var
  mFold: TBlockFold;
begin
  if (AOpener < 0) or (AOpener >= Length(Tree.Tokens)) then
  begin
    Exit;
  end;
  mFold := Default(TBlockFold);
  mFold.Kind := AKind;
  mFold.OpenPos := Tree.Tokens[AOpener].EndPos;
  mFold.ClosePos := AClosePos;
  mFold.Caption := SafeCaption(ACaption);
  if mFold.ClosePos.Line > mFold.OpenPos.Line then
  begin
    List.Add(mFold);
  end;
end;

/// <summary>Art eines begin-Blocks nach dem Token davor und dem umgebenden Knoten: else, if, for, while, with,
/// case, on; sonst begin.</summary>
function BlockKind(const ABefore: TPascalToken; AParent: TSyntaxKind): string;
begin
  Result := 'begin';
  if ABefore.IsKeyword('else') then
  begin
    Exit('else');
  end;
  if not (ABefore.IsKeyword('then') or ABefore.IsKeyword('do') or ABefore.IsSymbol(':')) then
  begin
    Exit;
  end;
  case AParent of
    TSyntaxKind.IfStatement: Result := 'if';
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement: Result := 'for';
    TSyntaxKind.WhileStatement: Result := 'while';
    TSyntaxKind.WithStatement: Result := 'with';
    TSyntaxKind.CaseItem: Result := 'case';
    TSyntaxKind.ExceptionHandler: Result := 'on';
  else
    // Übrige Knoten: ein bloßer begin-Block.
  end;
end;

procedure TBlockCollector.AddBlock(ANode: TSyntaxNode);
var
  mOpener, mBefore: Integer;
  mKind, mCaption: string;
begin
  // Rumpf einer Routine, einer anonymen Methode oder des Hauptprogramms faltet die IDE selbst.
  if (ANode.Parent = nil) or (ANode.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod,
    TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.PackageFile, TSyntaxKind.UnitFile]) then
  begin
    Exit;
  end;
  mOpener := NextCode(Tree.Tokens, Tree.FirstTokenFrom(ANode.StartOffset));
  if (mOpener >= Length(Tree.Tokens)) or not Tree.Tokens[mOpener].IsKeyword('begin') then
  begin
    Exit;
  end;
  mBefore := PreviousCode(Tree.Tokens, mOpener);
  mKind := 'begin';
  if mBefore >= 0 then
  begin
    mKind := BlockKind(Tree.Tokens[mBefore], ANode.Parent.Kind);
  end;
  // Kopf: if/for/while/with/case-Zweig/on bis zum Token vor begin; sonst das Wort selbst.
  mCaption := mKind;
  if (mKind <> 'begin') and (mKind <> 'else') then
  begin
    mCaption := TextOf(ANode.Parent.StartOffset, mBefore);
  end;
  Add(mKind, mOpener, ANode.EndPos, mCaption);
end;

procedure TBlockCollector.AddStatement(ANode: TSyntaxNode);
var
  mOpener: Integer;
  mKind: string;
begin
  mOpener := NextCode(Tree.Tokens, Tree.FirstTokenFrom(ANode.StartOffset));
  if mOpener >= Length(Tree.Tokens) then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.TryStatement then
  begin
    mKind := 'try';
  end
  else
  begin
    mKind := 'repeat';
  end;
  Add(mKind, mOpener, ANode.EndPos, mKind);
end;

procedure TBlockCollector.AddCase(ANode: TSyntaxNode);
var
  mOpener: Integer;
begin
  // Das "of" folgt auf den Ausdruck, das erste Kind.
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mOpener := NextCode(Tree.Tokens, Tree.FirstTokenFrom(ANode[0].EndOffset));
  if (mOpener >= Length(Tree.Tokens)) or not Tree.Tokens[mOpener].IsKeyword('of') then
  begin
    Exit;
  end;
  Add('case', mOpener, ANode.EndPos, TextOf(ANode.StartOffset, mOpener));
end;

procedure TBlockCollector.Visit(ANode: TSyntaxNode);
begin
  case ANode.Kind of
    TSyntaxKind.Block:
      AddBlock(ANode);
    TSyntaxKind.TryStatement, TSyntaxKind.RepeatStatement:
      AddStatement(ANode);
    TSyntaxKind.CaseStatement:
      AddCase(ANode);
  else
    // Übrige Knoten sind keine eigenen Blöcke.
  end;
end;

{ TLspBlockFolds }

constructor TLspBlockFolds.Create(const AStore: IDocumentStore);
begin
  inherited Create;
  FStore := AStore;
end;

procedure TLspBlockFolds.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  // Nebenläufig: Parsen großer Dateien blockiert die Nachrichtenschleife nicht.
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleBlockFolds);
end;

function TLspBlockFolds.HandleBlockFolds(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TBlockFoldsText.FieldTextDocumentUriMissingIn].Text + cMethod);
  end;
  // Nicht geöffnete Dokumente haben keine Blöcke.
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(ToJson(nil));
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  ACancellation.ThrowIfCancellationRequested;
  Result := ToJson(Collect(mShared.Tree));
end;

class function TLspBlockFolds.Collect(ATree: TSyntaxTree): TArray<TBlockFold>;
var
  mCollector: TBlockCollector;
  mNode: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mCollector := Default(TBlockCollector);
  mCollector.Tree := ATree;
  mCollector.List := TList<TBlockFold>.Create;
  try
    for mNode in TSyntaxNode.PreOrder(ATree.Root) do
    begin
      mCollector.Visit(mNode);
    end;
    // Eindeutig: verschiedene Blöcke beginnen nie hinter demselben Token.
    mCollector.List.Sort(TComparer<TBlockFold>.Construct(
      function(const ALeft, ARight: TBlockFold): Integer
      begin
        Result := TTextPosition.Compare(ALeft.OpenPos, ARight.OpenPos);
      end));
    Result := mCollector.List.ToArray;
  finally
    mCollector.List.Free;
  end;
end;

function PositionJson(const APosition: TTextPosition): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('line', TJSONNumber.Create(APosition.Line));
  Result.AddPair('character', TJSONNumber.Create(APosition.Character));
end;

class function TLspBlockFolds.ToJson(const ABlocks: TArray<TBlockFold>): TJSONObject;
var
  mBlocks: TJSONArray;
  mFold: TBlockFold;
  mItem: TJSONObject;
begin
  mBlocks := TJSONArray.Create;
  for mFold in ABlocks do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('kind', mFold.Kind);
    mItem.AddPair('open', PositionJson(mFold.OpenPos));
    mItem.AddPair('close', PositionJson(mFold.ClosePos));
    mItem.AddPair('caption', mFold.Caption);
    mBlocks.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('blocks', mBlocks);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.BlockFolds', cTexts);

end.
