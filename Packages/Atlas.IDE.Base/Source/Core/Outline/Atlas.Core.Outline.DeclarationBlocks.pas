unit Atlas.Core.Outline.DeclarationBlocks;

// Deklarationsblöcke der Unit-Ebene (#1766), Kern ohne VCL und OTA:
// - Ein Block beginnt mit type, const, var, resourcestring, threadvar, label
//   oder exports außerhalb von Typen und Routinen und endet am nächsten
//   Block, an uses, interface, implementation, initialization, finalization,
//   begin oder end, an der nächsten Routine bzw. am Ende des Texts.
// - Lokale Blöcke in Routinen und Unterblöcke in Typen zählen nicht
//   (TAtlasTypeText.UnitTokens); Kommentare und Strings fallen weg.
// - Jeder Block kennt den Teil der Unit (interface, implementation; leer in
//   Programmen). At liefert alle Blöcke, die Schlüsselwörter der Teile und den
//   Block am Caret: Die Zeile des Schlüsselworts gehört schon zum Block, die
//   Zeile des beendenden Worts nicht mehr.

interface

uses
  Atlas.Core.Outline.Model;

type
  /// <summary>Deklarationsblock der Unit-Ebene.</summary>
  TAtlasDeclarationBlock = record
    /// <summary>Schlüsselwort klein („resourcestring“).</summary>
    Keyword: string;
    /// <summary>Teil der Unit: „interface“, „implementation“ oder leer.</summary>
    Section: string;
    /// <summary>Anfang des Schlüsselworts, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Wort bzw. Routine, die den Block beendet, 0-basiert.</summary>
    EndLine: Integer;
    EndCharacter: Integer;
  end;

  TAtlasDeclarationBlocks = TArray<TAtlasDeclarationBlock>;

  /// <summary>Deklarationsblöcke der Unit und der Block an einer Stelle.</summary>
  TAtlasDeclarationBlockPlace = record
    Blocks: TAtlasDeclarationBlocks;
    /// <summary>Schlüsselwörter interface und implementation (Keyword, Line, Character).</summary>
    Sections: TAtlasDeclarationBlocks;
    /// <summary>Index des Blocks an der Stelle; -1 außerhalb.</summary>
    Current: Integer;
  end;

  TAtlasDeclarationBlockFinder = class
  public
    /// <summary>Alle Deklarationsblöcke der Unit in Quelltextreihenfolge.</summary>
    class function BlocksOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>): TAtlasDeclarationBlocks;
      static;
    /// <summary>Blöcke der Unit und der Block in Zeile ALine (0-basiert).</summary>
    class function At(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      ALine: Integer): TAtlasDeclarationBlockPlace; static;
    /// <summary>Elemente der Unit-Ebene im Block ABlock von APlace in Quelltextreihenfolge.</summary>
    class function MembersOf(const ANodes: TAtlasOutlineNodes; const APlace: TAtlasDeclarationBlockPlace;
      ABlock: Integer): TArray<Integer>; static;
  end;

implementation

uses
  Atlas.Core.Outline.TypeText;

const
  cBlockWords: array[0..6] of string = ('type', 'const', 'var', 'resourcestring', 'threadvar', 'label', 'exports');
  cEndWords: array[0..6] of string = ('uses', 'interface', 'implementation', 'initialization', 'finalization',
    'begin', 'end');

/// <summary>Knoten der Unit-Ebene (Eltern fehlt oder ist interface/implementation)?</summary>
function AtUnitLevel(const ANodes: TAtlasOutlineNodes; ANode: Integer): Boolean;
var
  mParent: Integer;
begin
  mParent := ANodes[ANode].Parent;
  Result := not TAtlasOutline.IsSection(ANodes[ANode]) and ((mParent < 0) or
    TAtlasOutline.IsSection(ANodes[mParent]));
end;

/// <summary>Beendet den offenen Block AOpen an ALine/ACharacter.</summary>
procedure CloseBlock(var ABlocks: TAtlasDeclarationBlocks; var AOpen: Boolean; ALine, ACharacter: Integer);
begin
  if AOpen then
  begin
    ABlocks[High(ABlocks)].EndLine := ALine;
    ABlocks[High(ABlocks)].EndCharacter := ACharacter;
    AOpen := False;
  end;
end;

/// <summary>Schlüsselwort AToken als Block ohne Ende.</summary>
function NewBlock(const AToken: TAtlasTypeToken; const ASection: string; AEndLine: Integer): TAtlasDeclarationBlock;
begin
  Result.Keyword := AToken.Text;
  Result.Section := ASection;
  Result.Line := AToken.Line;
  Result.Character := AToken.Character;
  Result.EndLine := AEndLine;
  Result.EndCharacter := MaxInt;
end;

/// <summary>Blöcke aus den Wörtern der Unit-Ebene; Routinen beenden sie erst danach (ShortenAtRoutines).
/// ASections erhält die Schlüsselwörter interface und implementation.</summary>
function CollectBlocks(const ATokens: TAtlasTypeTokens; AEndLine: Integer;
  out ASections: TAtlasDeclarationBlocks): TAtlasDeclarationBlocks;
var
  mToken: TAtlasTypeToken;
  mSection: string;
  mOpen: Boolean;
begin
  Result := nil;
  ASections := nil;
  mSection := '';
  mOpen := False;
  for mToken in ATokens do
  begin
    if not mToken.Word or mToken.Escaped then
    begin
      Continue;
    end;
    if TAtlasTypeText.IsOneOf(mToken.Text, cBlockWords) then
    begin
      CloseBlock(Result, mOpen, mToken.Line, mToken.Character);
      Result := Result + [NewBlock(mToken, mSection, AEndLine)];
      mOpen := True;
    end
    else if TAtlasTypeText.IsOneOf(mToken.Text, cEndWords) then
    begin
      CloseBlock(Result, mOpen, mToken.Line, mToken.Character);
      if TAtlasTypeText.IsOneOf(mToken.Text, ['interface', 'implementation']) then
      begin
        mSection := mToken.Text;
        ASections := ASections + [NewBlock(mToken, mSection, AEndLine)];
      end;
    end;
  end;
end;

/// <summary>Eine Routine der Unit-Ebene beendet den Block, in dem sie beginnt.</summary>
procedure ShortenAtRoutines(const ANodes: TAtlasOutlineNodes; var ABlocks: TAtlasDeclarationBlocks);
var
  mIndex, mBlock: Integer;
  mNode: TAtlasOutlineNode;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    mNode := ANodes[mIndex];
    if not (mNode.Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine]) or mNode.InBody or
      not AtUnitLevel(ANodes, mIndex) then
    begin
      Continue;
    end;
    for mBlock := 0 to High(ABlocks) do
    begin
      if TAtlasTypeText.Before(ABlocks[mBlock].Line, ABlocks[mBlock].Character, mNode.StartLine,
        mNode.StartCharacter) and TAtlasTypeText.Before(mNode.StartLine, mNode.StartCharacter,
        ABlocks[mBlock].EndLine, ABlocks[mBlock].EndCharacter) then
      begin
        ABlocks[mBlock].EndLine := mNode.StartLine;
        ABlocks[mBlock].EndCharacter := mNode.StartCharacter;
      end;
    end;
  end;
end;

/// <summary>Blöcke und Schlüsselwörter der Teile der Unit.</summary>
function Collect(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  out ASections: TAtlasDeclarationBlocks): TAtlasDeclarationBlocks;
begin
  Result := CollectBlocks(TAtlasTypeText.UnitTokens(ANodes, ALines), High(ALines) + 1, ASections);
  ShortenAtRoutines(ANodes, Result);
end;

class function TAtlasDeclarationBlockFinder.BlocksOf(const ANodes: TAtlasOutlineNodes;
  const ALines: TArray<string>): TAtlasDeclarationBlocks;
var
  mSections: TAtlasDeclarationBlocks;
begin
  Result := Collect(ANodes, ALines, mSections);
end;

class function TAtlasDeclarationBlockFinder.At(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ALine: Integer): TAtlasDeclarationBlockPlace;
var
  mIndex: Integer;
begin
  Result.Blocks := Collect(ANodes, ALines, Result.Sections);
  Result.Current := -1;
  for mIndex := 0 to High(Result.Blocks) do
  begin
    // Zeile des Schlüsselworts gehört dazu, Zeile des beendenden Worts nicht.
    if (Result.Blocks[mIndex].Line <= ALine) and (ALine < Result.Blocks[mIndex].EndLine) then
    begin
      Result.Current := mIndex;
    end;
  end;
end;

class function TAtlasDeclarationBlockFinder.MembersOf(const ANodes: TAtlasOutlineNodes;
  const APlace: TAtlasDeclarationBlockPlace; ABlock: Integer): TArray<Integer>;
var
  mIndex: Integer;
  mBlock: TAtlasDeclarationBlock;
begin
  Result := nil;
  if (ABlock < 0) or (ABlock > High(APlace.Blocks)) then
  begin
    Exit;
  end;
  mBlock := APlace.Blocks[ABlock];
  for mIndex := 0 to High(ANodes) do
  begin
    if AtUnitLevel(ANodes, mIndex) and not ANodes[mIndex].Hidden and
      not TAtlasTypeText.Before(ANodes[mIndex].NameLine, ANodes[mIndex].NameCharacter, mBlock.Line,
      mBlock.Character) and TAtlasTypeText.Before(ANodes[mIndex].NameLine, ANodes[mIndex].NameCharacter,
      mBlock.EndLine, mBlock.EndCharacter) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

end.
