unit Atlas.Common.Rules.Builtin.Ownership.TokenScan;

// Gemeinsame Grundlage der Besitz-Regeln (owned-item-freed, create-without-assignment,
// self-as-interface-in-constructor): Code-Tokens ohne Kommentare und Direktiven, Zeilen der Datei, Klammern und
// generische Argumente überspringen, Knoten und Anweisungen an einer Stelle.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Gemeinsame Grundlage der Regeln: Tokens ohne Kommentare und Direktiven, Zeilen der Datei.</summary>
  TOwnershipTokenScan = class
  protected
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    /// <summary>Indizes der Code-Tokens in FTokens, nach Offset sortiert.</summary>
    FCode: TArray<Integer>;
    FLines: TArray<string>;
    FLineBreak: string;
    function Token(APosition: Integer): TPascalToken;
    function IsWord(APosition: Integer): Boolean;
    function IsSym(APosition: Integer; const ASymbol: string): Boolean;
    function IsName(APosition: Integer; const AName: string): Boolean;
    function IsKey(APosition: Integer; const AKeyword: string): Boolean;
    function CodeAt(AOffset: Integer): Integer;
    function Closing(AOpen: Integer): Integer;
    function TextBetween(AFirst, ALast: Integer): string;
    function SkipGenericArgs(APosition: Integer): Integer;
    /// <summary>Liegt die Stelle AOffset im Block ABlock?</summary>
    class function InBlock(ABlock: TSyntaxNode; AOffset: Integer): Boolean; static;
    /// <summary>Tiefster Knoten unter ANode, der AOffset enthält.</summary>
    class function NodeAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode; static;
    /// <summary>Anweisung direkt im Rumpf ABlock, die AOffset enthält; nil sonst.</summary>
    class function TopStatement(ABlock: TSyntaxNode; AOffset: Integer): TSyntaxNode; static;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines;

{ TOwnershipTokenScan }

constructor TOwnershipTokenScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mIndex: Integer;
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FCode := nil;
  for mIndex := 0 to High(FTokens) do
  begin
    if not (FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      FCode := FCode + [mIndex];
    end;
  end;
  FLines := TTextLines.SplitLines(AContext.Text, FLineBreak);
end;

function TOwnershipTokenScan.Token(APosition: Integer): TPascalToken;
begin
  Result := FTokens[FCode[APosition]];
end;

function TOwnershipTokenScan.IsWord(APosition: Integer): Boolean;
begin
  Result := (APosition >= 0) and (APosition <= High(FCode)) and
    (Token(APosition).Kind = TPascalTokenKind.Identifier);
end;

function TOwnershipTokenScan.IsSym(APosition: Integer; const ASymbol: string): Boolean;
begin
  Result := (APosition >= 0) and (APosition <= High(FCode)) and Token(APosition).IsSymbol(ASymbol);
end;

function TOwnershipTokenScan.IsName(APosition: Integer; const AName: string): Boolean;
begin
  Result := IsWord(APosition) and SameText(Token(APosition).Text, AName);
end;

function TOwnershipTokenScan.IsKey(APosition: Integer; const AKeyword: string): Boolean;
begin
  Result := (APosition >= 0) and (APosition <= High(FCode)) and Token(APosition).IsKeyword(AKeyword);
end;

function TOwnershipTokenScan.CodeAt(AOffset: Integer): Integer;
var
  mHigh, mMiddle: Integer;
begin
  // Binär statt ab Dateianfang mit einer Kopie je Token: FCode steht nach Offset sortiert (#1342).
  Result := 0;
  mHigh := Length(FCode);
  while Result < mHigh do
  begin
    mMiddle := (Result + mHigh) div 2;
    if FTokens[FCode[mMiddle]].Offset < AOffset then
    begin
      Result := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
end;

/// <summary>Passende schließende Klammer zu AOpen ("(" oder "["), sonst -1.</summary>
function TOwnershipTokenScan.Closing(AOpen: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  for Result := AOpen to High(FCode) do
  begin
    if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
  end;
  Result := -1;
end;

function TOwnershipTokenScan.TextBetween(AFirst, ALast: Integer): string;
begin
  Result := Copy(FContext.Text, Token(AFirst).Offset + 1,
    Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
end;

/// <summary>Position nach den generischen Argumenten "&lt;…&gt;" ab APosition.</summary>
function TOwnershipTokenScan.SkipGenericArgs(APosition: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := APosition;
  if not IsSym(Result, '<') then
  begin
    Exit;
  end;
  mDepth := 0;
  while Result <= High(FCode) do
  begin
    if Token(Result).IsSymbol('<') then
    begin
      Inc(mDepth);
    end
    else if Token(Result).IsSymbol('>') then
    begin
      Dec(mDepth);
    end
    else if Token(Result).IsSymbol('>>') then
    begin
      Dec(mDepth, 2);
    end
    else if Token(Result).IsSymbol(';') then
    begin
      Exit;
    end;
    Inc(Result);
    if mDepth <= 0 then
    begin
      Exit;
    end;
  end;
end;

{ Knoten }

class function TOwnershipTokenScan.InBlock(ABlock: TSyntaxNode; AOffset: Integer): Boolean;
begin
  Result := (AOffset >= ABlock.StartOffset) and (AOffset < ABlock.EndOffset);
end;

class function TOwnershipTokenScan.NodeAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
  mNext: TSyntaxNode;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht): je Ebene in das erste Kind, das AOffset enthält.
  Result := ANode;
  repeat
    mNext := nil;
    for mIndex := 0 to Result.ChildCount - 1 do
    begin
      if InBlock(Result[mIndex], AOffset) then
      begin
        mNext := Result[mIndex];
        Break;
      end;
    end;
    if mNext <> nil then
    begin
      Result := mNext;
    end;
  until mNext = nil;
end;

class function TOwnershipTokenScan.TopStatement(ABlock: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ABlock.ChildCount - 1 do
  begin
    if InBlock(ABlock[mIndex], AOffset) then
    begin
      Exit(ABlock[mIndex]);
    end;
  end;
  Result := nil;
end;

end.
