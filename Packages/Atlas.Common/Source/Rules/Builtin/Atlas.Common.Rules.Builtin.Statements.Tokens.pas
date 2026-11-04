unit Atlas.Common.Rules.Builtin.Statements.Tokens;

// Gemeinsame Hilfen der Anweisungsregeln (Statements, Statements.Loops, Statements.Cases, Statements.Datasets,
// Statements.Properties): Code-Token suchen, Klammern und Schlüsselwörter auf Klammerebene 0, Anweisungen im
// Syntaxbaum, Quelltext der Token und Dateiname des Kontexts.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

type
  TTokens = TArray<TPascalToken>;
  TSyntaxKinds = set of TSyntaxKind;

/// <summary>Kommentar oder Compileranweisung?</summary>
function IsTrivia(const AToken: TPascalToken): Boolean;
/// <summary>Erstes Code-Token ab AIndex (AIndex eingeschlossen); High + 1 ohne.</summary>
function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
/// <summary>Erstes Token ab AOffset (Index), High + 1 ohne.</summary>
function TokenFrom(const ATokens: TTokens; AOffset: Integer): Integer;
/// <summary>Knotenarten, die eine Anweisung sind.</summary>
function StatementKinds: TSyntaxKinds;
/// <summary>Erste Anweisung unter ANode, die nach AOffset beginnt; nil ohne.</summary>
function StatementAfter(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
/// <summary>Quelltext der Token AFirst..ALast wie geschrieben.</summary>
function SourceText(const AText: string; const ATokens: TTokens; AFirst, ALast: Integer): string;
/// <summary>Code-Token AFirst..ALast ohne Leerraum und Kommentare, kleingeschrieben (zum Vergleichen).</summary>
function CodeKey(const ATokens: TTokens; AFirst, ALast: Integer): string;
/// <summary>Letztes Code-Token vor AIndex (AIndex selbst ausgeschlossen).</summary>
function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
/// <summary>Index der schließenden Klammer zu AOpen, -1 ohne.</summary>
function Closing(const ATokens: TTokens; AOpen, AStop: Integer): Integer;
/// <summary>Erstes Token AText (Schlüsselwort bzw. Symbol) in AFrom..AStop-1 auf Klammerebene 0; -1 ohne.</summary>
function DepthZero(const ATokens: TTokens; AFrom, AStop: Integer; const AText: string; AKeyword: Boolean): Integer;
/// <summary>Bilden die ABaseCount Code-Token vor AIndex die Basis ABaseKey (CodeKey), ohne Punkt davor?</summary>
function BaseBefore(const ATokens: TTokens; AIndex: Integer; const ABaseKey: string; ABaseCount: Integer): Boolean;
/// <summary>Dateiname des Kontexts für die Namensauflösung: Datei, relativer Pfad oder Unitname.</summary>
function ContextFileName(const AContext: TRuleContext): string;
/// <summary>Ist AType ein eingebauter String-Typ?</summary>
function IsStringType(const AType: string): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Erstes Token ab AOffset (Index), High + 1 ohne.</summary>
function TokenFrom(const ATokens: TTokens; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
    begin
      Low := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
  Result := Low;
end;

function StatementKinds: TSyntaxKinds;
begin
  Result := [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.Error];
end;

/// <summary>Erste Anweisung unter ANode, die nach AOffset beginnt; nil ohne.</summary>
function StatementAfter(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[Index].Kind in StatementKinds) and (ANode[Index].StartOffset >= AOffset) then
    begin
      Exit(ANode[Index]);
    end;
  end;
  Result := nil;
end;

/// <summary>Quelltext der Token AFirst..ALast wie geschrieben.</summary>
function SourceText(const AText: string; const ATokens: TTokens; AFirst, ALast: Integer): string;
begin
  Result := Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset);
end;

/// <summary>Code-Token AFirst..ALast ohne Leerraum und Kommentare, kleingeschrieben (zum Vergleichen).</summary>
function CodeKey(const ATokens: TTokens; AFirst, ALast: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := AFirst to ALast do
  begin
    if not IsTrivia(ATokens[Index]) then
    begin
      Result := Result + LowerCase(ATokens[Index].Text);
    end;
  end;
end;

/// <summary>Letztes Code-Token vor AIndex (AIndex selbst ausgeschlossen).</summary>
function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Index der schließenden Klammer zu AOpen, -1 ohne.</summary>
function Closing(const ATokens: TTokens; AOpen, AStop: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to AStop - 1 do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit;
      end;
    end;
  end;
  Result := -1;
end;

/// <summary>Erstes Token AText (Schlüsselwort bzw. Symbol) in AFrom..AStop-1 auf Klammerebene 0; -1 ohne.</summary>
function DepthZero(const ATokens: TTokens; AFrom, AStop: Integer; const AText: string; AKeyword: Boolean): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  for Index := AFrom to AStop - 1 do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and ((AKeyword and ATokens[Index].IsKeyword(AText)) or
      (not AKeyword and ATokens[Index].IsSymbol(AText))) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

/// <summary>Bilden die ABaseCount Code-Token vor AIndex die Basis ABaseKey (CodeKey), ohne Punkt davor?</summary>
function BaseBefore(const ATokens: TTokens; AIndex: Integer; const ABaseKey: string; ABaseCount: Integer): Boolean;
var
  Before, Count, Prev: Integer;
  Key: string;
begin
  Key := '';
  Before := AIndex;
  Count := 0;
  while Count < ABaseCount do
  begin
    Before := PreviousCode(ATokens, Before);
    if Before < 0 then
    begin
      Exit(False);
    end;
    Key := LowerCase(ATokens[Before].Text) + Key;
    Inc(Count);
  end;
  Prev := PreviousCode(ATokens, Before);
  Result := (Key = ABaseKey) and ((Prev < 0) or not ATokens[Prev].IsSymbol('.'));
end;

/// <summary>Dateiname des Kontexts für die Namensauflösung: Datei, relativer Pfad oder Unitname.</summary>
function ContextFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

function IsStringType(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'UTF8String']);
end;

end.
