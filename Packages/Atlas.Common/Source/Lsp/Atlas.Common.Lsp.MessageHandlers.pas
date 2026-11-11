unit Atlas.Common.Lsp.MessageHandlers;

// Message-Handler einer Klasse (procedure WMPaint(var Message: TWMPaint); message WM_PAINT;)
// und welche Vorfahren dieselbe Nachricht schon behandeln. Grundlage für Code Lens und Hover (#36).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  TMessageReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TMessageHandler = record
    /// <summary>Nachricht wie im Quelltext, z. B. WM_PAINT.</summary>
    Message: string;
    MethodName: string;
    TypeName: string;
    FileName: string;
    SelectionRange: TTextRange;
  end;

  TMessageOverview = record
    Own: TArray<TMessageHandler>;
    /// <summary>Je Eintrag in Own der nächste Vorfahr mit derselben Nachricht; TypeName '' = keiner.</summary>
    Inherited_: TArray<TMessageHandler>;
    function Found: Boolean;
    /// <summary>Kurzfassung für Code Lens, z. B. "behandelt WM_PAINT, WM_SIZE (WM_PAINT auch in
    /// TWinControl)".</summary>
    function Title: string;
    function ToMarkdown: string;
  end;

  TMessageHandlers = class
  public const
    cMaxDepth = 32;
  public
    /// <summary>Message-Handler, die ATypeName in ATree selbst deklariert.</summary>
    class function InTree(ATree: TSyntaxTree; const AFileName, ATypeName: string): TArray<TMessageHandler>; static;
    /// <summary>Eigene Handler von ATypeName und die Vorfahren, die dieselben Nachrichten behandeln.</summary>
    class function Overview(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName, ATypeName: string; const AReadText: TMessageReadText): TMessageOverview; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TMessageHandlersText = (AlsoIn, AlsoIn2, Handles, Messages);

const
  cTexts: array[TMessageHandlersText] of TAtlasText = (
    (De: ' auch in '; En: ' also in '),
    (De: ', auch in `%s.%s`'; En: ', also in `%s.%s`'),
    (De: 'behandelt '; En: 'handles '),
    (De: '**Nachrichten**' + #10;
     En: '**Messages**' + #10));

{$SCOPEDENUMS OFF}

function FirstTokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := Length(ATokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if ATokens[mMiddle].Offset < AOffset then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  Result := mLow;
end;

function FindClassNode(ANode: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  mRoot, mFound: TSyntaxNode;
  mTypeName: string;
begin
  mRoot := ANode;
  mTypeName := ATypeName;
  // Search statt Rekursion.
  mFound := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      if ACandidate = mRoot then
      begin
        Exit(TSyntaxSearchStep.Descend);
      end;
      if (ACandidate.Kind = TSyntaxKind.TypeDecl) and SameText(ACandidate.Name, mTypeName) and
        (ACandidate.FindChild(TSyntaxKind.ClassType) <> nil) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      // Routinen enthalten keine Klassen, die hier gemeint sind.
      if ACandidate.Kind = TSyntaxKind.RoutineDecl then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
  Result := nil;
  if mFound <> nil then
  begin
    Result := mFound.FindChild(TSyntaxKind.ClassType);
  end;
end;

/// <summary>Argument der Direktive message: alle Tokens der Direktive ADirective hinter "message".</summary>
function DirectiveArgument(const ATokens: TArray<TPascalToken>; ADirective: TSyntaxNode): string;
var
  mTokenIndex: Integer;
begin
  Result := '';
  mTokenIndex := FirstTokenAt(ATokens, ADirective.StartOffset) + 1;
  while (mTokenIndex <= High(ATokens)) and (ATokens[mTokenIndex].Offset < ADirective.EndOffset) do
  begin
    if not (ATokens[mTokenIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result := Result + ATokens[mTokenIndex].Text;
    end;
    Inc(mTokenIndex);
  end;
end;

/// <summary>Bereich des Methodennamens im Kopf AHeader; ohne Fund der ganze Kopf.</summary>
function NameRange(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TTextRange;
var
  mTokenIndex: Integer;
begin
  mTokenIndex := FirstTokenAt(ATokens, AHeader.StartOffset);
  while (mTokenIndex <= High(ATokens)) and (ATokens[mTokenIndex].Offset < AHeader.EndOffset) do
  begin
    if (ATokens[mTokenIndex].Kind = TPascalTokenKind.Identifier) and
      SameText(ATokens[mTokenIndex].Text, AHeader.Name) then
    begin
      Exit(TTextRange.Create(ATokens[mTokenIndex].StartPos, ATokens[mTokenIndex].EndPos));
    end;
    Inc(mTokenIndex);
  end;
  Result := TTextRange.Create(AHeader.StartPos, AHeader.EndPos);
end;

/// <summary>Botschaftsbehandler aus dem Methodenkopf AHeader (Direktive message) in AList.</summary>
procedure AddHandlers(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode; const AFileName, ATypeName: string;
  AList: TList<TMessageHandler>);
var
  mInner: Integer;
  mDirective: TSyntaxNode;
  mHandler: TMessageHandler;
begin
  for mInner := 0 to AHeader.ChildCount - 1 do
  begin
    mDirective := AHeader[mInner];
    if (mDirective.Kind <> TSyntaxKind.Directive) or (mDirective.Name <> 'message') then
    begin
      Continue;
    end;
    mHandler := Default(TMessageHandler);
    mHandler.MethodName := AHeader.Name;
    mHandler.TypeName := ATypeName;
    mHandler.FileName := AFileName;
    mHandler.Message := DirectiveArgument(ATokens, mDirective);
    mHandler.SelectionRange := NameRange(ATokens, AHeader);
    if mHandler.Message <> '' then
    begin
      AList.Add(mHandler);
    end;
  end;
end;

procedure CollectHandlers(ATree: TSyntaxTree; ANode: TSyntaxNode; const AFileName, ATypeName: string;
  AList: TList<TMessageHandler>);
var
  mRoot: TSyntaxNode;
  mTokens: TArray<TPascalToken>;
  mFileName, mTypeName: string;
  mList: TList<TMessageHandler>;
begin
  mRoot := ANode;
  mTokens := ATree.Tokens;
  mFileName := AFileName;
  mTypeName := ATypeName;
  mList := AList;
  // Walk statt Rekursion; die Reihenfolge der Behandler bleibt die des Quelltexts.
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      if AChild = mRoot then
      begin
        Exit(True);
      end;
      // Verschachtelte Typen gehören nicht zur Klasse.
      if AChild.Kind = TSyntaxKind.TypeDecl then
      begin
        Exit(False);
      end;
      if AChild.Kind <> TSyntaxKind.RoutineHeader then
      begin
        Exit(True);
      end;
      AddHandlers(mTokens, AChild, mFileName, mTypeName, mList);
      Result := False;
    end);
end;

{ TMessageOverview }

function TMessageOverview.Found: Boolean;
begin
  Result := Length(Own) > 0;
end;

function TMessageOverview.Title: string;
var
  mIndex: Integer;
  mAlso: string;
begin
  Result := '';
  mAlso := '';
  for mIndex := 0 to High(Own) do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + Own[mIndex].Message;
    if Inherited_[mIndex].TypeName <> '' then
    begin
      if mAlso <> '' then
      begin
        mAlso := mAlso + ', ';
      end;
      mAlso := mAlso + Own[mIndex].Message + cTexts[TMessageHandlersText.AlsoIn].Text + Inherited_[mIndex].TypeName;
    end;
  end;
  Result := cTexts[TMessageHandlersText.Handles].Text + Result;
  if mAlso <> '' then
  begin
    Result := Result + ' (' + mAlso + ')';
  end;
end;

function TMessageOverview.ToMarkdown: string;
var
  mIndex: Integer;
begin
  Result := '';
  if not Found then
  begin
    Exit;
  end;
  Result := cTexts[TMessageHandlersText.Messages].Text;
  for mIndex := 0 to High(Own) do
  begin
    Result := Result + #10 + '- `' + Own[mIndex].Message + '` → `' + Own[mIndex].MethodName + '`';
    if Inherited_[mIndex].TypeName <> '' then
    begin
      Result := Result + cTexts[TMessageHandlersText.AlsoIn2].Fmt([Inherited_[mIndex].TypeName,
        Inherited_[mIndex].MethodName]);
    end;
  end;
end;

{ TMessageHandlers }

class function TMessageHandlers.InTree(ATree: TSyntaxTree; const AFileName, ATypeName: string): TArray<TMessageHandler>;
var
  mClassNode: TSyntaxNode;
  mList: TList<TMessageHandler>;
begin
  Result := nil;
  if ATree = nil then
  begin
    Exit;
  end;
  mClassNode := FindClassNode(ATree.Root, ATypeName);
  if mClassNode = nil then
  begin
    Exit;
  end;
  mList := TList<TMessageHandler>.Create;
  try
    CollectHandlers(ATree, mClassNode, AFileName, ATypeName, mList);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Klasse ATypeName (nicht verschachtelt) im Index AUnit.</summary>
function ClassSymbolOf(const AUnit: TUnitIndex; const ATypeName: string; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and (mSymbol.Container = '') and
      SameText(mSymbol.Name, ATypeName) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Vorfahr der Klasse ATypeName aus ihrer Unit AUnit; False am Ende der Kette oder ohne Auflösung.
/// </summary>
function ResolveAncestor(AResolver: TNameResolver; const AUnit: TUnitIndex; const ATypeName: string;
  out AAncestor: TResolvedSymbol): Boolean;
var
  mClassSymbol: TIndexSymbol;
  mAncestorName: string;
begin
  Result := False;
  if not ClassSymbolOf(AUnit, ATypeName, mClassSymbol) then
  begin
    Exit;
  end;
  if Length(mClassSymbol.Ancestors) > 0 then
  begin
    mAncestorName := mClassSymbol.Ancestors[0];
  end
  else if not SameText(ATypeName, 'TObject') then
  begin
    mAncestorName := 'TObject';
  end
  else
  begin
    Exit;
  end;
  Result := (Pos('<', mAncestorName) = 0) and AResolver.ResolveTypeFrom(AUnit, mAncestorName, AAncestor) and
    (AAncestor.SymbolKind = TIndexSymbolKind.ClassType);
end;

/// <summary>Baum der Datei AFileName: AOwnTree für die eigene Datei AOwnFile, sonst aus ATrees oder gelesen.
/// </summary>
function TreeOf(const AFileName, AOwnFile: string; AOwnTree: TSyntaxTree;
  ATrees: TObjectDictionary<string, TSyntaxTree>; const AReadText: TMessageReadText; out ATree: TSyntaxTree): Boolean;
var
  mText: string;
begin
  Result := True;
  if SameText(AFileName, AOwnFile) then
  begin
    ATree := AOwnTree;
  end
  else if not ATrees.TryGetValue(UpperCase(AFileName), ATree) then
  begin
    Result := Assigned(AReadText) and AReadText(AFileName, mText);
    if Result then
    begin
      ATree := TSyntaxTreeCache.Parse(mText);
      ATrees.Add(UpperCase(AFileName), ATree);
    end;
  end;
end;

/// <summary>Trägt für noch nicht gefundene eigene Behandler den gleichen Behandler aus AHandlers ein.</summary>
procedure MatchInherited(var AOverview: TMessageOverview; const AHandlers: TArray<TMessageHandler>);
var
  mHandler: TMessageHandler;
  mIndex: Integer;
begin
  for mIndex := 0 to High(AOverview.Own) do
  begin
    for mHandler in AHandlers do
    begin
      if (AOverview.Inherited_[mIndex].TypeName = '') and SameText(mHandler.Message, AOverview.Own[mIndex].Message) then
      begin
        AOverview.Inherited_[mIndex] := mHandler;
      end;
    end;
  end;
end;

class function TMessageHandlers.Overview(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, ATypeName: string; const AReadText: TMessageReadText): TMessageOverview;
var
  mTrees: TObjectDictionary<string, TSyntaxTree>;
  mCurrentUnit: TUnitIndex;
  mCurrentTree, mTree: TSyntaxTree;
  mCurrentName: string;
  mAncestor: TResolvedSymbol;
  mDepth: Integer;
begin
  Result := Default(TMessageOverview);
  Result.Own := InTree(ATree, AFileName, ATypeName);
  SetLength(Result.Inherited_, Length(Result.Own));
  if not Result.Found then
  begin
    Exit;
  end;
  mTrees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
  try
    mCurrentTree := ATree;
    mCurrentUnit := TIndexExtractor.Extract(ATree, AFileName);
    mCurrentName := ATypeName;
    for mDepth := 1 to cMaxDepth do
    begin
      if not ResolveAncestor(AResolver, mCurrentUnit, mCurrentName, mAncestor) or
        not TreeOf(mAncestor.FileName, AFileName, ATree, mTrees, AReadText, mTree) then
      begin
        Break;
      end;
      MatchInherited(Result, InTree(mTree, mAncestor.FileName, mAncestor.Name));
      if mTree <> mCurrentTree then
      begin
        mCurrentUnit := TIndexExtractor.Extract(mTree, mAncestor.FileName);
      end;
      mCurrentTree := mTree;
      mCurrentName := mAncestor.Name;
    end;
  finally
    mTrees.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.MessageHandlers', cTexts);

end.
