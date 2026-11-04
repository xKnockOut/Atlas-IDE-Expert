unit Atlas.Common.Lsp.DataFlow.Syntax;

// Datenfluss (#690): Hilfen am Syntaxbaum und an den Tokens, ohne Zustand. Gemeinsam für die Teile des Laufs.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TDataFlowSyntax = class
  public
    /// <summary>Innerster Knoten, der APosition enthält. Überlappen sich Geschwister (ein Sichtbarkeitsabschnitt
    /// reicht über die Mitglieder dahinter), gewinnt das später beginnende.</summary>
    class function NodeAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode; static;
    class function ChildIndex(AParent, AChild: TSyntaxNode): Integer; static;
    /// <summary>Token, das an APosition beginnt oder sie enthält; -1 sonst.</summary>
    class function TokenIndexAt(ATree: TSyntaxTree; const APosition: TTextPosition): Integer; static;
    /// <summary>Bezeichner ohne führendes &amp;.</summary>
    class function CleanName(const AText: string): string; static;
    /// <summary>Position des Namens eines Bezeichners bzw. des Mitglieds hinter dem letzten Punkt.</summary>
    class function NamePosition(ATree: TSyntaxTree; ANode: TSyntaxNode): TTextPosition; static;
    /// <summary>Erster Bezeichner AName im Bereich des Knotens.</summary>
    class function NameInNode(ATree: TSyntaxTree; ANode: TSyntaxNode; const AName: string;
      out APosition: TTextPosition): Boolean; static;
    /// <summary>Erster deklarierter Name einer Deklaration (var A, B: … liefert A) im Knoten.</summary>
    class function FirstDeclaredName(ATree: TSyntaxTree; ADeclaration: TSyntaxNode;
      out APosition: TTextPosition): Boolean; static;
    /// <summary>Name der Routine im Kopf: bei TFoo.Bar das letzte Vorkommen vor der Parameterliste.</summary>
    class function RoutineNamePosition(ATree: TSyntaxTree; AHeader: TSyntaxNode; const AName: string;
      out APosition: TTextPosition): Boolean; static;
    /// <summary>Name der Routine bzw. des Aufgerufenen ohne Typ-Präfix.</summary>
    class function ShortName(const AName: string): string; static;
    /// <summary>Kleingeschriebener Name des Aufgerufenen eines Call-Knotens.</summary>
    class function CalleeName(ACall: TSyntaxNode): string; static;
    /// <summary>Text einzeilig, Leerraum zusammengefasst, höchstens cMaxDetail Zeichen.</summary>
    class function SingleLine(const AText: string): string; static;
    /// <summary>Kleingeschriebenes Token vor APosition (ohne Kommentare und Direktiven).</summary>
    class function AccessorBefore(ATree: TSyntaxTree; const APosition: TTextPosition): string; static;
    /// <summary>Bezeichner hinter dem Schlüsselwort AKeyword (read, write) in der Property.</summary>
    class function Accessor(ATree: TSyntaxTree; AProperty: TSyntaxNode; const AKeyword: string;
      out APosition: TTextPosition): Boolean; static;
    class function PropertyName(ATree: TSyntaxTree; AProperty: TSyntaxNode; out APosition: TTextPosition): Boolean;
      static;
    /// <summary>ANode (auch als Liste[I] oder P^) ist das Ziel einer Zuweisung AStatement; AUnsafeReason wird
    /// 'pointer', wenn der Weg über einen Zeiger geht.</summary>
    class function WrittenTarget(ANode: TSyntaxNode; out AStatement: TSyntaxNode; var AUnsafeReason: string): Boolean;
      static;
    /// <summary>Umgebende Routine mit Rumpf; nil, wenn keine.</summary>
    class function RoutineWithBody(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>ANode steht im Kopf einer Routine (Deklaration, Implementierung, Parameter).</summary>
    class function InRoutineHeader(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Formulardatei (.dfm, .fmx): Vorkommen dort sind weder Quelle noch Ziel.</summary>
    class function IsFormFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract;

const
  cMaxDetail = 120;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
end;

function NodeContains(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := (ComparePositions(ANode.StartPos, APosition) <= 0) and (ComparePositions(APosition, ANode.EndPos) < 0);
end;

/// <summary>Bezeichner AName (ohne &amp;) im Token.</summary>
function IsIdentifierNamed(const AToken: TPascalToken; const AName: string): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) and SameText(TDataFlowSyntax.CleanName(AToken.Text), AName);
end;

function IsCommentOrDirective(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

{ TDataFlowSyntax }

class function TDataFlowSyntax.NodeAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  mIndex: Integer;
  mInner: TSyntaxNode;
begin
  Result := ARoot;
  repeat
    mInner := nil;
    for mIndex := 0 to Result.ChildCount - 1 do
    begin
      if NodeContains(Result[mIndex], APosition) and ((mInner = nil) or
        (ComparePositions(Result[mIndex].StartPos, mInner.StartPos) > 0)) then
      begin
        mInner := Result[mIndex];
      end;
    end;
    if mInner <> nil then
    begin
      Result := mInner;
    end;
  until mInner = nil;
end;

class function TDataFlowSyntax.ChildIndex(AParent, AChild: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to AParent.ChildCount - 1 do
  begin
    if AParent[mIndex] = AChild then
    begin
      Result := mIndex;
      Break;
    end;
  end;
end;

class function TDataFlowSyntax.TokenIndexAt(ATree: TSyntaxTree; const APosition: TTextPosition): Integer;
var
  mFirst, mLast, mMiddle: Integer;
begin
  Result := -1;
  mFirst := 0;
  mLast := Length(ATree.Tokens) - 1;
  while (Result < 0) and (mFirst <= mLast) do
  begin
    mMiddle := (mFirst + mLast) div 2;
    if ComparePositions(ATree.Tokens[mMiddle].EndPos, APosition) <= 0 then
    begin
      mFirst := mMiddle + 1;
    end
    else if ComparePositions(ATree.Tokens[mMiddle].StartPos, APosition) > 0 then
    begin
      mLast := mMiddle - 1;
    end
    else
    begin
      Result := mMiddle;
    end;
  end;
end;

class function TDataFlowSyntax.CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
  begin
    Result := Copy(AText, 2, MaxInt);
  end
  else
  begin
    Result := AText;
  end;
end;

class function TDataFlowSyntax.NamePosition(ATree: TSyntaxTree; ANode: TSyntaxNode): TTextPosition;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  Result := ANode.StartPos;
  if ANode.Kind <> TSyntaxKind.MemberAccess then
  begin
    Exit;
  end;
  // Das Mitglied steht als letzter gleichnamiger Bezeichner im Knoten.
  for mIndex := ATree.FirstTokenFrom(ANode.StartOffset) to High(ATree.Tokens) do
  begin
    mToken := ATree.Tokens[mIndex];
    if mToken.Offset >= ANode.EndOffset then
    begin
      Break;
    end;
    if (mToken.Offset >= ANode.StartOffset) and IsIdentifierNamed(mToken, CleanName(ANode.Name)) then
    begin
      Result := mToken.StartPos;
    end;
  end;
end;

class function TDataFlowSyntax.NameInNode(ATree: TSyntaxTree; ANode: TSyntaxNode; const AName: string;
  out APosition: TTextPosition): Boolean;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  Result := False;
  for mIndex := ATree.FirstTokenFrom(ANode.StartOffset) to High(ATree.Tokens) do
  begin
    mToken := ATree.Tokens[mIndex];
    if mToken.Offset >= ANode.EndOffset then
    begin
      Break;
    end;
    if (mToken.Offset >= ANode.StartOffset) and IsIdentifierNamed(mToken, AName) then
    begin
      APosition := mToken.StartPos;
      Result := True;
      Break;
    end;
  end;
end;

class function TDataFlowSyntax.FirstDeclaredName(ATree: TSyntaxTree; ADeclaration: TSyntaxNode;
  out APosition: TTextPosition): Boolean;
begin
  Result := NameInNode(ATree, ADeclaration, CleanName(Trim(ADeclaration.Name.Split([','])[0])), APosition);
end;

class function TDataFlowSyntax.RoutineNamePosition(ATree: TSyntaxTree; AHeader: TSyntaxNode; const AName: string;
  out APosition: TTextPosition): Boolean;
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  Result := False;
  for mIndex := ATree.FirstTokenFrom(AHeader.StartOffset) to High(ATree.Tokens) do
  begin
    mToken := ATree.Tokens[mIndex];
    if mToken.Offset >= AHeader.EndOffset then
    begin
      Break;
    end;
    if mToken.Offset < AHeader.StartOffset then
    begin
      Continue;
    end;
    if IsIdentifierNamed(mToken, AName) then
    begin
      APosition := mToken.StartPos;
      Result := True;
    end;
    if mToken.IsSymbol('(') or mToken.IsSymbol(';') or mToken.IsSymbol(':') then
    begin
      Break;
    end;
  end;
end;

class function TDataFlowSyntax.ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

class function TDataFlowSyntax.CalleeName(ACall: TSyntaxNode): string;
begin
  Result := '';
  if ACall.ChildCount > 0 then
  begin
    Result := LowerCase(CleanName(ShortName(ACall[0].Name)));
  end;
end;

class function TDataFlowSyntax.SingleLine(const AText: string): string;
var
  mIndex: Integer;
  mSpace: Boolean;
begin
  Result := '';
  mSpace := False;
  for mIndex := 1 to Length(AText) do
  begin
    if CharInSet(AText[mIndex], [#9, #10, #13, ' ']) then
    begin
      mSpace := Result <> '';
    end
    else
    begin
      if mSpace then
      begin
        Result := Result + ' ';
      end;
      mSpace := False;
      Result := Result + AText[mIndex];
    end;
  end;
  if Length(Result) > cMaxDetail then
  begin
    Result := Copy(Result, 1, cMaxDetail - 1) + '…';
  end;
end;

class function TDataFlowSyntax.AccessorBefore(ATree: TSyntaxTree; const APosition: TTextPosition): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := TokenIndexAt(ATree, APosition) - 1;
  while (mIndex >= 0) and IsCommentOrDirective(ATree.Tokens[mIndex]) do
  begin
    Dec(mIndex);
  end;
  if mIndex >= 0 then
  begin
    Result := LowerCase(ATree.Tokens[mIndex].Text);
  end;
end;

class function TDataFlowSyntax.Accessor(ATree: TSyntaxTree; AProperty: TSyntaxNode; const AKeyword: string;
  out APosition: TTextPosition): Boolean;
var
  mIndex: Integer;
  mToken: TPascalToken;
  mArmed: Boolean;
begin
  Result := False;
  mArmed := False;
  for mIndex := ATree.FirstTokenFrom(AProperty.StartOffset) to High(ATree.Tokens) do
  begin
    mToken := ATree.Tokens[mIndex];
    if mToken.Offset >= AProperty.EndOffset then
    begin
      Break;
    end;
    if (mToken.Offset < AProperty.StartOffset) or IsCommentOrDirective(mToken) then
    begin
      Continue;
    end;
    if mArmed and (mToken.Kind = TPascalTokenKind.Identifier) then
    begin
      APosition := mToken.StartPos;
      Result := True;
      Break;
    end;
    mArmed := SameText(mToken.Text, AKeyword) and (mToken.Kind in [TPascalTokenKind.Keyword,
      TPascalTokenKind.Identifier]);
  end;
end;

class function TDataFlowSyntax.PropertyName(ATree: TSyntaxTree; AProperty: TSyntaxNode;
  out APosition: TTextPosition): Boolean;
begin
  Result := NameInNode(ATree, AProperty, CleanName(AProperty.Name), APosition);
end;

class function TDataFlowSyntax.WrittenTarget(ANode: TSyntaxNode; out AStatement: TSyntaxNode;
  var AUnsafeReason: string): Boolean;
var
  mCurrent: TSyntaxNode;
begin
  mCurrent := ANode;
  while (mCurrent.Parent <> nil) and (mCurrent.Parent.Kind in [TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
    (mCurrent.Parent[0] = mCurrent) do
  begin
    if mCurrent.Parent.Kind = TSyntaxKind.Dereference then
    begin
      AUnsafeReason := 'pointer';
    end;
    mCurrent := mCurrent.Parent;
  end;
  AStatement := mCurrent.Parent;
  Result := (AStatement <> nil) and (AStatement.Kind = TSyntaxKind.AssignStatement) and
    (AStatement.ChildCount >= 2) and (AStatement[0] = mCurrent);
end;

class function TDataFlowSyntax.RoutineWithBody(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and not ((Result.Kind = TSyntaxKind.RoutineDecl) and
    (Result.FindChild(TSyntaxKind.Block) <> nil)) do
  begin
    Result := Result.Parent;
  end;
end;

class function TDataFlowSyntax.InRoutineHeader(ANode: TSyntaxNode): Boolean;
var
  mAncestor: TSyntaxNode;
begin
  Result := False;
  mAncestor := ANode.Parent;
  while (mAncestor <> nil) and not Result do
  begin
    Result := mAncestor.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.Parameters];
    mAncestor := mAncestor.Parent;
  end;
end;

class function TDataFlowSyntax.IsFormFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dfm') or SameText(ExtractFileExt(AFileName), '.fmx');
end;

end.
