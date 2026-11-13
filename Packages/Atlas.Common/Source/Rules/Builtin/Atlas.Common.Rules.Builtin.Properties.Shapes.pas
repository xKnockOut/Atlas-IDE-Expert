unit Atlas.Common.Rules.Builtin.Properties.Shapes;

// Gelesene Property-Deklarationen für die Property-Regeln (Atlas.Common.Rules.Builtin.Properties): Indexparameter,
// Typtext, index-Angabe und die Zugriffe hinter read und write samt Feldselektoren, dazu die Übergabeart der
// Parameter einer Signatur und ob ein Typ Include-Dateien einbindet.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Ein Zugriff hinter read oder write: Name und Feldselektoren, Token von First bis Last.</summary>
  TPropertyAccessor = record
    IsWrite: Boolean;
    Name: string;
    Selectors: TArray<string>;
    First: Integer;
    Last: Integer;
  end;

  /// <summary>Gelesene Property: Indexparameter, Typtext, index-Angabe und Zugriffe.</summary>
  TPropertyShape = record
    Symbol: TIndexSymbol;
    /// <summary>Indexparameter ohne Klammern wie im Quelltext ("Index: Integer"); '' ohne.</summary>
    IndexText: string;
    /// <summary>Typ wie im Quelltext ("TList&lt;TKunde&gt;"); '' bei einer Property ohne Typ.</summary>
    TypeText: string;
    /// <summary>Die Property hat eine index-Angabe (index 3).</summary>
    HasIndex: Boolean;
    IsClass: Boolean;
    SingleLine: Boolean;
    Accessors: TArray<TPropertyAccessor>;
  end;

/// <summary>Bezeichner oder Schlüsselwort mit Text AWord (ohne Groß-/Kleinschreibung)?</summary>
function IsWord(const AToken: TPascalToken; const AWord: string): Boolean;

/// <summary>Modifizierer der Parameter einer Signatur in Reihenfolge ('', const, var, out, constref).</summary>
function ParamModifiers(const ASignature: string): TArray<string>;

/// <summary>Property ab dem Token "property" an AStart lesen (ATokens ohne Kommentare); False ohne Namen.</summary>
function ParseProperty(const AText: string; const ATokens: TArray<TPascalToken>; AStart: Integer;
  out AShape: TPropertyShape): Boolean;

/// <summary>Bindet der Typ AType Include-Dateien ein (Direktive in seinem Bereich)? Dann kennt die Datei nicht
/// alle Mitglieder.</summary>
function TypeHasInclude(const ATokens: TArray<TPascalToken>; const AType: TIndexSymbol): Boolean;

/// <summary>Typparameter der Klasse und ihrer Vorfahren: Sie passen zu jedem Typ.</summary>
function Wildcards(const AChain: TArray<TSymbolLocation>): TArray<string>;

/// <summary>'read' bzw. 'write'.</summary>
function ClauseOf(const AAccessor: TPropertyAccessor): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.DirectiveNames;

function IsWord(const AToken: TPascalToken; const AWord: string): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(AToken.Text, AWord);
end;

/// <summary>Index der schließenden Klammer zur öffnenden bei AOpen; 0 ohne.</summary>
function ClosingParen(const ASignature: string; AOpen: Integer): Integer;
var
  mDepth, mIndex: Integer;
begin
  mDepth := 0;
  for mIndex := AOpen to Length(ASignature) do
  begin
    if ASignature[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if (ASignature[mIndex] = ')') and (mDepth = 1) then
    begin
      Exit(mIndex);
    end
    else if ASignature[mIndex] = ')' then
    begin
      Dec(mDepth);
    end;
  end;
  Result := 0;
end;

/// <summary>Parametergruppen ("const A, B: Integer") zwischen den Klammern AOpen und AClose.</summary>
function ParamGroups(const ASignature: string; AOpen, AClose: Integer): TArray<string>;
var
  mDepth, mIndex, mStart: Integer;
  mChar: Char;
begin
  Result := nil;
  mDepth := 0;
  mStart := AOpen + 1;
  for mIndex := AOpen + 1 to AClose do
  begin
    mChar := ASignature[mIndex];
    if CharInSet(mChar, ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(mChar, [']', '>']) or ((mChar = ')') and (mIndex < AClose)) then
    begin
      Dec(mDepth);
    end
    else if ((mChar = ';') and (mDepth = 0)) or (mIndex = AClose) then
    begin
      Result := Result + [Trim(Copy(ASignature, mStart, mIndex - mStart))];
      mStart := mIndex + 1;
    end;
  end;
end;

/// <summary>Modifizierer einer Parametergruppe ('', const, var, out, constref); ACount: Zahl ihrer Namen.</summary>
function GroupModifier(const AGroup: string; out ACount: Integer): string;
var
  mHead: string;
begin
  mHead := AGroup;
  if Pos(':', mHead) > 0 then
  begin
    mHead := Copy(mHead, 1, Pos(':', mHead) - 1);
  end;
  mHead := Trim(mHead);
  Result := LowerCase(Copy(mHead, 1, Pos(' ', mHead + ' ') - 1));
  if MatchText(Result, ['const', 'var', 'out', 'constref']) then
  begin
    mHead := Trim(Copy(mHead, Length(Result) + 1, MaxInt));
  end
  else
  begin
    Result := '';
  end;
  ACount := Length(mHead.Split([',']));
end;

function ParamModifiers(const ASignature: string): TArray<string>;
var
  mOpen, mClose, mCount, mIndex: Integer;
  mGroup, mModifier: string;
begin
  Result := nil;
  mOpen := Pos('(', ASignature);
  if mOpen = 0 then
  begin
    Exit;
  end;
  mClose := ClosingParen(ASignature, mOpen);
  if mClose = 0 then
  begin
    Exit;
  end;
  for mGroup in ParamGroups(ASignature, mOpen, mClose) do
  begin
    mModifier := GroupModifier(mGroup, mCount);
    for mIndex := 1 to mCount do
    begin
      Result := Result + [mModifier];
    end;
  end;
end;

/// <summary>Quelltext von Token AFrom bis ATo (Code-Token).</summary>
function SourceText(const AText: string; const ATokens: TArray<TPascalToken>; AFrom, ATo: Integer): string;
begin
  Result := Trim(Copy(AText, ATokens[AFrom].Offset + 1, ATokens[ATo].Offset + Length(ATokens[ATo].Text) -
    ATokens[AFrom].Offset));
end;

/// <summary>Wort, das den Typ einer Property beendet (read, write, index, stored, default, nodefault,
/// implements)?</summary>
function IsPropertyWord(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    MatchText(AToken.Text, ['read', 'write', 'index', 'stored', 'default', 'nodefault', 'implements']);
end;

type
  /// <summary>Zustand beim Lesen einer Property ab dem Token "property".</summary>
  TPropertyParser = record
    Text: string;
    Tokens: TArray<TPascalToken>;
    Index: Integer;
    Depth: Integer;
    /// <summary>Token "[" der Indexparameter; -1 ohne.</summary>
    Bracket: Integer;
    /// <summary>Erstes Token des Typs; -1 vor dem Doppelpunkt.</summary>
    TypeStart: Integer;
    Shape: TPropertyShape;
    procedure Open;
    procedure Close;
    /// <summary>Typtext bis vor Index übernehmen, falls noch keiner steht.</summary>
    procedure EndType;
    procedure ReadAccessor;
    /// <summary>Token bei Index auf Klammertiefe 0; False beim abschließenden Semikolon.</summary>
    function TopLevel: Boolean;
  end;

procedure TPropertyParser.Open;
begin
  if (Depth = 0) and Tokens[Index].IsSymbol('[') and (TypeStart < 0) then
  begin
    Bracket := Index;
  end;
  Inc(Depth);
end;

procedure TPropertyParser.Close;
begin
  Dec(Depth);
  if (Depth = 0) and (Bracket >= 0) and (Shape.IndexText = '') and (Index > Bracket + 1) then
  begin
    Shape.IndexText := SourceText(Text, Tokens, Bracket + 1, Index - 1);
  end;
end;

procedure TPropertyParser.EndType;
begin
  if (TypeStart > 0) and (Shape.TypeText = '') and (Index > TypeStart) then
  begin
    Shape.TypeText := SourceText(Text, Tokens, TypeStart, Index - 1);
  end;
end;

procedure TPropertyParser.ReadAccessor;
var
  mAccessor: TPropertyAccessor;
begin
  mAccessor := Default(TPropertyAccessor);
  mAccessor.IsWrite := IsWord(Tokens[Index], 'write');
  Inc(Index);
  mAccessor.Name := Tokens[Index].Text;
  mAccessor.First := Index;
  while (Index + 2 <= High(Tokens)) and Tokens[Index + 1].IsSymbol('.') and
    (Tokens[Index + 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Inc(Index, 2);
    mAccessor.Selectors := mAccessor.Selectors + [Tokens[Index].Text];
  end;
  mAccessor.Last := Index;
  Shape.Accessors := Shape.Accessors + [mAccessor];
end;

function TPropertyParser.TopLevel: Boolean;
var
  mToken: TPascalToken;
begin
  mToken := Tokens[Index];
  Result := not mToken.IsSymbol(';');
  if not Result then
  begin
    Exit;
  end;
  if mToken.IsSymbol(':') and (TypeStart < 0) then
  begin
    TypeStart := Index + 1;
  end
  else if IsPropertyWord(mToken) then
  begin
    EndType;
    if IsWord(mToken, 'index') then
    begin
      Shape.HasIndex := True;
    end
    else if (IsWord(mToken, 'read') or IsWord(mToken, 'write')) and (Index < High(Tokens)) and
      (Tokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
    begin
      ReadAccessor;
    end;
  end;
end;

function ParseProperty(const AText: string; const ATokens: TArray<TPascalToken>; AStart: Integer;
  out AShape: TPropertyShape): Boolean;
var
  mParser: TPropertyParser;
  mToken: TPascalToken;
begin
  AShape := Default(TPropertyShape);
  Result := (AStart + 1 <= High(ATokens)) and (ATokens[AStart + 1].Kind = TPascalTokenKind.Identifier);
  if not Result then
  begin
    Exit;
  end;
  mParser := Default(TPropertyParser);
  mParser.Text := AText;
  mParser.Tokens := ATokens;
  mParser.Index := AStart + 2;
  mParser.Bracket := -1;
  mParser.TypeStart := -1;
  while mParser.Index <= High(ATokens) do
  begin
    mToken := ATokens[mParser.Index];
    if mToken.IsSymbol('[') or mToken.IsSymbol('(') then
    begin
      mParser.Open;
    end
    else if mToken.IsSymbol(']') or mToken.IsSymbol(')') then
    begin
      mParser.Close;
    end
    else if (mParser.Depth = 0) and not mParser.TopLevel then
    begin
      Break;
    end;
    Inc(mParser.Index);
  end;
  if mParser.Index <= High(ATokens) then
  begin
    mParser.EndType;
  end;
  AShape := mParser.Shape;
  AShape.SingleLine := (mParser.Index <= High(ATokens)) and
    (ATokens[mParser.Index].StartPos.Line = ATokens[AStart].StartPos.Line);
end;

function TypeHasInclude(const ATokens: TArray<TPascalToken>; const AType: TIndexSymbol): Boolean;
var
  mToken: TPascalToken;
  mName: string;
begin
  for mToken in ATokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Directive) and (mToken.StartPos.Line >= AType.Range.StartPos.Line) and
      (mToken.StartPos.Line <= AType.Range.EndPos.Line) then
    begin
      mName := TDirectiveNames.LeadingName(TDirectiveNames.Body(mToken.Text));
      if SameText(mName, 'I') or SameText(mName, 'INCLUDE') then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function Wildcards(const AChain: TArray<TSymbolLocation>): TArray<string>;
var
  mLocation: TSymbolLocation;
  mName: string;
begin
  Result := nil;
  for mLocation in AChain do
  begin
    for mName in mLocation.Symbol.TypeParams.Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        Result := Result + [Trim(mName)];
      end;
    end;
  end;
end;

function ClauseOf(const AAccessor: TPropertyAccessor): string;
begin
  if AAccessor.IsWrite then
  begin
    Result := 'write';
  end
  else
  begin
    Result := 'read';
  end;
end;

end.
