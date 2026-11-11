unit Atlas.Core.Outline.MemberBlocks;

// Unterblöcke im Deklarationsteil eines Typs (#1767), Kern ohne VCL und OTA:
// - Ein Unterblock beginnt mit const, type oder class var und endet am
//   nächsten Unterblock, an var, am ersten Methoden- oder Eigenschaftsteil
//   (procedure, function, constructor, destructor, property, operator, auch
//   mit class davor), am nächsten Sichtbarkeitsschlüsselwort oder am end des
//   Typs. Ein ausdrückliches var ist kein Unterblock (Feldteil wie ohne
//   Schlüsselwort).
// - Es zählen nur Wörter außerhalb von Klammern (Parameterlisten, Attribute);
//   Text verschachtelter Typen, Kommentare und Strings fallen weg
//   (TAtlasTypeText).
// - At liefert die Unterblöcke des Sichtbarkeitsabschnitts am Caret und den
//   Block, in dem der Caret steht. Die Zeile des Schlüsselworts gehört schon
//   zum Block, die Zeile des beendenden Worts nicht mehr.

interface

uses
  Atlas.Core.Outline.Model;

type
  /// <summary>Unterblock im Deklarationsteil eines Typs.</summary>
  TAtlasMemberBlock = record
    /// <summary>„const“, „type“ oder „class var“.</summary>
    Keyword: string;
    /// <summary>Anfang des Schlüsselworts, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Wort, das den Block beendet, bzw. Ende des Typs, 0-basiert.</summary>
    EndLine: Integer;
    EndCharacter: Integer;
  end;

  TAtlasMemberBlocks = TArray<TAtlasMemberBlock>;

  /// <summary>Unterblock an einer Stelle des Quelltexts.</summary>
  TAtlasMemberBlockPlace = record
    /// <summary>Typ wie bei TAtlasVisibilitySectionFinder.TypeAt; -1 ohne.</summary>
    TypeNode: Integer;
    /// <summary>Unterblöcke im Sichtbarkeitsabschnitt der Stelle in Quelltextreihenfolge.</summary>
    Blocks: TAtlasMemberBlocks;
    /// <summary>Index des Blocks an der Stelle; -1 außerhalb eines Unterblocks.</summary>
    Current: Integer;
  end;

  TAtlasMemberBlockFinder = class
  public
    /// <summary>Alle Unterblöcke des Typs AType in Quelltextreihenfolge.</summary>
    class function BlocksOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      AType: Integer): TAtlasMemberBlocks; static;
    /// <summary>Unterblock an der Stelle ALine/ACharacter (0-basiert).</summary>
    class function At(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
      ACharacter: Integer): TAtlasMemberBlockPlace; static;
    /// <summary>Mitglieder des Typs im Block ABlock von APlace in Quelltextreihenfolge.</summary>
    class function MembersOf(const ANodes: TAtlasOutlineNodes; const APlace: TAtlasMemberBlockPlace;
      ABlock: Integer): TArray<Integer>; static;
  end;

implementation

uses
  Atlas.Core.Outline.TypeText,
  Atlas.Core.Outline.VisibilitySections;

const
  /// <summary>Wörter, mit denen der Methoden- und Eigenschaftsteil beginnt.</summary>
  cMemberWords: array[0..5] of string = ('procedure', 'function', 'constructor', 'destructor', 'property',
    'operator');
  cVisibilityWords: array[0..4] of string = ('strict', 'private', 'protected', 'public', 'published');

type
  /// <summary>Sammelt die Blöcke beim Lauf über die Wörter eines Typs.</summary>
  TBlockCollector = class
  private
    FTokens: TAtlasTypeTokens;
    FBlocks: TAtlasMemberBlocks;
    FOpen: Boolean;
    function NextText(AIndex: Integer): string;
    function NextIsWord(AIndex: Integer): Boolean;
    procedure Close(ALine, ACharacter: Integer);
    procedure Open(const AKeyword: string; const AToken: TAtlasTypeToken);
    procedure Visit(var AIndex: Integer);
  public
    constructor Create(const ATokens: TAtlasTypeTokens);
    function Run(AEndLine, AEndCharacter: Integer): TAtlasMemberBlocks;
  end;

constructor TBlockCollector.Create(const ATokens: TAtlasTypeTokens);
begin
  inherited Create;
  FTokens := ATokens;
end;

function TBlockCollector.NextText(AIndex: Integer): string;
begin
  Result := '';
  if AIndex < High(FTokens) then
  begin
    Result := FTokens[AIndex + 1].Text;
  end;
end;

function TBlockCollector.NextIsWord(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= High(FTokens)) or FTokens[AIndex + 1].Word;
end;

procedure TBlockCollector.Close(ALine, ACharacter: Integer);
begin
  if FOpen then
  begin
    FBlocks[High(FBlocks)].EndLine := ALine;
    FBlocks[High(FBlocks)].EndCharacter := ACharacter;
    FOpen := False;
  end;
end;

procedure TBlockCollector.Open(const AKeyword: string; const AToken: TAtlasTypeToken);
var
  mBlock: TAtlasMemberBlock;
begin
  Close(AToken.Line, AToken.Character);
  mBlock.Keyword := AKeyword;
  mBlock.Line := AToken.Line;
  mBlock.Character := AToken.Character;
  mBlock.EndLine := AToken.Line;
  mBlock.EndCharacter := AToken.Character;
  FBlocks := FBlocks + [mBlock];
  FOpen := True;
end;

/// <summary>Wort an AIndex außerhalb von Klammern: öffnet oder schließt einen Block.</summary>
procedure TBlockCollector.Visit(var AIndex: Integer);
var
  mToken: TAtlasTypeToken;
begin
  mToken := FTokens[AIndex];
  if mToken.Escaped then
  begin
    Exit;
  end;
  if TAtlasTypeText.IsOneOf(mToken.Text, ['const', 'type']) then
  begin
    Open(mToken.Text, mToken);
  end
  else if (mToken.Text = 'class') and (NextText(AIndex) = 'var') then
  begin
    Open('class var', mToken);
    Inc(AIndex);
  end
  else if TAtlasTypeText.IsOneOf(mToken.Text, ['var', 'end']) or TAtlasTypeText.IsOneOf(mToken.Text, cMemberWords) or
    ((mToken.Text = 'class') and TAtlasTypeText.IsOneOf(NextText(AIndex), cMemberWords)) or
    (TAtlasTypeText.IsOneOf(mToken.Text, cVisibilityWords) and NextIsWord(AIndex)) then
  begin
    // Feldteil, Methoden- und Eigenschaftsteil, nächster Abschnitt oder Ende des Typs.
    Close(mToken.Line, mToken.Character);
  end;
end;

function TBlockCollector.Run(AEndLine, AEndCharacter: Integer): TAtlasMemberBlocks;
var
  mIndex, mDepth: Integer;
begin
  FBlocks := nil;
  FOpen := False;
  mDepth := 0;
  mIndex := 0;
  while mIndex <= High(FTokens) do
  begin
    if (FTokens[mIndex].Text = '(') or (FTokens[mIndex].Text = '[') then
    begin
      Inc(mDepth);
    end
    else if (FTokens[mIndex].Text = ')') or (FTokens[mIndex].Text = ']') then
    begin
      Dec(mDepth);
    end
    else if (mDepth <= 0) and FTokens[mIndex].Word then
    begin
      Visit(mIndex);
    end;
    Inc(mIndex);
  end;
  Close(AEndLine, AEndCharacter);
  Result := FBlocks;
end;

class function TAtlasMemberBlockFinder.BlocksOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  AType: Integer): TAtlasMemberBlocks;
var
  mCollector: TBlockCollector;
begin
  Result := nil;
  if (AType < 0) or (AType > High(ANodes)) then
  begin
    Exit;
  end;
  mCollector := TBlockCollector.Create(TAtlasTypeText.Tokens(ANodes, ALines, AType));
  try
    Result := mCollector.Run(ANodes[AType].EndLine, ANodes[AType].EndCharacter);
  finally
    mCollector.Free;
  end;
end;

/// <summary>Liegt der Block im Abschnitt ASection von APlace (-1 = vor dem ersten Schlüsselwort)?</summary>
function InSection(const ABlock: TAtlasMemberBlock; const APlace: TAtlasVisibilityPlace; ASection: Integer): Boolean;
var
  mAfterStart, mBeforeEnd: Boolean;
begin
  mAfterStart := (ASection < 0) or not TAtlasTypeText.Before(ABlock.Line, ABlock.Character,
    APlace.Sections[ASection].Line, APlace.Sections[ASection].Character);
  mBeforeEnd := (ASection = High(APlace.Sections)) or TAtlasTypeText.Before(ABlock.Line, ABlock.Character,
    APlace.Sections[ASection + 1].Line, APlace.Sections[ASection + 1].Character);
  Result := mAfterStart and mBeforeEnd;
end;

class function TAtlasMemberBlockFinder.At(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ALine, ACharacter: Integer): TAtlasMemberBlockPlace;
var
  mSection: TAtlasVisibilityPlace;
  mBlock: TAtlasMemberBlock;
begin
  Result := Default(TAtlasMemberBlockPlace);
  Result.Current := -1;
  mSection := TAtlasVisibilitySectionFinder.At(ANodes, ALines, ALine, ACharacter);
  Result.TypeNode := mSection.TypeNode;
  if Result.TypeNode < 0 then
  begin
    Exit;
  end;
  for mBlock in BlocksOf(ANodes, ALines, Result.TypeNode) do
  begin
    if not InSection(mBlock, mSection, mSection.Current) then
    begin
      Continue;
    end;
    Result.Blocks := Result.Blocks + [mBlock];
    // Zeile des Schlüsselworts gehört dazu, Zeile des beendenden Worts nicht.
    if (mBlock.Line <= ALine) and (ALine < mBlock.EndLine) then
    begin
      Result.Current := High(Result.Blocks);
    end;
  end;
end;

class function TAtlasMemberBlockFinder.MembersOf(const ANodes: TAtlasOutlineNodes;
  const APlace: TAtlasMemberBlockPlace; ABlock: Integer): TArray<Integer>;
var
  mIndex: Integer;
  mNode: TAtlasOutlineNode;
  mBlock: TAtlasMemberBlock;
begin
  Result := nil;
  if (APlace.TypeNode < 0) or (ABlock < 0) or (ABlock > High(APlace.Blocks)) then
  begin
    Exit;
  end;
  mBlock := APlace.Blocks[ABlock];
  for mIndex := 0 to High(ANodes) do
  begin
    mNode := ANodes[mIndex];
    if (mNode.Parent = APlace.TypeNode) and not mNode.Hidden and
      not TAtlasTypeText.Before(mNode.NameLine, mNode.NameCharacter, mBlock.Line, mBlock.Character) and
      TAtlasTypeText.Before(mNode.NameLine, mNode.NameCharacter, mBlock.EndLine, mBlock.EndCharacter) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

end.
