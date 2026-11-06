unit Atlas.Common.Rules.Builtin.Database.Statements;

// SQL-Anweisungen in einem SQL-Text für die Regeln der Gruppe Datenbank
// (Atlas.Common.Rules.Builtin.Database): Zerlegung in Token, UPDATE bzw.
// DELETE ohne Einschränkung (sql-write-without-where) und Sterne in
// Spaltenlisten (sql-select-star). Unbekannte Teile stehen als cSqlHole.

interface

const
  /// <summary>Unbekannter Teil (Variable, Aufruf) im SQL-Text.</summary>
  cSqlHole = #1;

type
  /// <summary>Schreibende SQL-Anweisung, die alle Zeilen trifft.</summary>
  TSqlWrite = record
    /// <summary>DELETE oder UPDATE.</summary>
    Kind: string;
    /// <summary>Tabelle wie geschrieben, auch mit Schema; '' bei dynamischem Namen.</summary>
    Table: string;
    /// <summary>Stelle des Schlüsselworts im SQL-Text (1-basiert).</summary>
    Offset: Integer;
  end;

  /// <summary>SELECT * bzw. SELECT Alias.* in einer Spaltenliste.</summary>
  TSqlStar = record
    /// <summary>Stelle des Sterns im SQL-Text (1-basiert).</summary>
    Offset: Integer;
    /// <summary>Alias bzw. Tabelle vor .*; '' bei *.</summary>
    Qualifier: string;
  end;

/// <summary>UPDATE- und DELETE-Anweisungen in ASql ohne WHERE, JOIN, TOP, LIMIT und ROWS auf oberster Ebene.
/// AStrictCase: Schlüsselwort nur in Großbuchstaben.</summary>
function SqlWrites(const ASql: string; AStrictCase: Boolean): TArray<TSqlWrite>;
/// <summary>Sterne in Spaltenlisten von ASql, auch in Unterabfragen, außer in EXISTS (…). AStrictCase: SELECT
/// nur in Großbuchstaben.</summary>
function SqlStars(const ASql: string; AStrictCase: Boolean): TArray<TSqlStar>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Chars;

const
  cClauseWords: array[0..16] of string = ('WHERE', 'SET', 'FROM', 'RETURNING', 'OUTPUT', 'USING', 'JOIN', 'INNER',
    'LEFT', 'RIGHT', 'FULL', 'CROSS', 'LIMIT', 'ROWS', 'ORDER', 'OPTION', 'AS');
  // Schränken die Zeilen ein, auch ohne WHERE.
  cRestrictWords: array[0..5] of string = ('WHERE', 'JOIN', 'LIMIT', 'ROWS', 'TOP', 'FETCH');
  // Davor steht ein unbekannter Teil an der Stelle eines Werts, nicht einer Klausel.
  cValueWords: array[0..10] of string = ('AND', 'OR', 'NOT', 'LIKE', 'IN', 'IS', 'THEN', 'ELSE', 'WHEN', 'VALUES',
    'BETWEEN');
  cValueSymbols = '=<>,(+-*/|%';
  // Stehen zwischen SELECT und der Spaltenliste.
  cSelectModifiers: array[0..3] of string = ('DISTINCT', 'ALL', 'UNIQUE', 'DISTINCTROW');
  // Nehmen eine Zahl, einen Parameter oder einen Ausdruck in Klammern mit (TOP 10, FIRST 5 SKIP 10).
  cSelectLimits: array[0..2] of string = ('TOP', 'FIRST', 'SKIP');

type
{$SCOPEDENUMS ON}
  TSqlTokenKind = (Word, Quoted, Literal, Symbol, Hole);
{$SCOPEDENUMS OFF}

  TSqlToken = record
    Kind: TSqlTokenKind;
    Text: string;
    Offset: Integer;
    Depth: Integer;
  end;

/// <summary>Beginnt ASql an der Stelle AIndex mit AText?</summary>
function StartsAt(const ASql: string; AIndex: Integer; const AText: string): Boolean;
begin
  Result := Copy(ASql, AIndex, Length(AText)) = AText;
end;

/// <summary>Letztes Zeichen eines Zeilenkommentars ab AIndex (vor dem Zeilenende).</summary>
function LineCommentEnd(const ASql: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(ASql)) and not CharInSet(ASql[Result], [#10, #13]) do
  begin
    Inc(Result);
  end;
  Dec(Result);
end;

/// <summary>Letztes Zeichen eines Blockkommentars ab AIndex; ohne Ende das Ende des Texts.</summary>
function BlockCommentEnd(const ASql: string; AIndex: Integer): Integer;
begin
  Result := PosEx('*/', ASql, AIndex + 2);
  if Result = 0 then
  begin
    Result := Length(ASql);
  end
  else
  begin
    Inc(Result);
  end;
end;

/// <summary>Schließendes Zeichen des Literals oder Bezeichners ab AIndex; ohne Ende hinter dem Text.</summary>
function QuotedEnd(const ASql: string; AIndex: Integer): Integer;
var
  mClose: Char;
begin
  mClose := ASql[AIndex];
  if mClose = '[' then
  begin
    mClose := ']';
  end;
  Result := AIndex + 1;
  while (Result <= Length(ASql)) and (ASql[Result] <> mClose) do
  begin
    Inc(Result);
  end;
end;

function WordEnd(const ASql: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result < Length(ASql)) and (TTextChars.IsIdentChar(ASql[Result + 1]) or (ASql[Result + 1] = '$')) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Token ab AIndex: AEnd ist sein letztes Zeichen; False bei Leerraum und Kommentaren.</summary>
function NextSqlToken(const ASql: string; AIndex: Integer; out AKind: TSqlTokenKind; out AEnd: Integer): Boolean;
var
  mCh: Char;
begin
  mCh := ASql[AIndex];
  AEnd := AIndex;
  AKind := TSqlTokenKind.Symbol;
  Result := (mCh > ' ') and not StartsAt(ASql, AIndex, '--') and not StartsAt(ASql, AIndex, '/*');
  if mCh = cSqlHole then
  begin
    AKind := TSqlTokenKind.Hole;
    Result := True;
  end
  else if StartsAt(ASql, AIndex, '--') then
  begin
    AEnd := LineCommentEnd(ASql, AIndex);
  end
  else if StartsAt(ASql, AIndex, '/*') then
  begin
    AEnd := BlockCommentEnd(ASql, AIndex);
  end
  else if mCh = '''' then
  begin
    AKind := TSqlTokenKind.Literal;
    AEnd := QuotedEnd(ASql, AIndex);
  end
  else if CharInSet(mCh, ['"', '[', '`']) then
  begin
    AKind := TSqlTokenKind.Quoted;
    AEnd := QuotedEnd(ASql, AIndex);
  end
  else if TTextChars.IsIdentChar(mCh) then
  begin
    AKind := TSqlTokenKind.Word;
    AEnd := WordEnd(ASql, AIndex);
  end;
end;

function SqlTokens(const ASql: string): TArray<TSqlToken>;
var
  mIndex, mEnd, mDepth, mCount: Integer;
  mKind: TSqlTokenKind;
begin
  Result := nil;
  mCount := 0;
  mDepth := 0;
  mIndex := 1;
  while mIndex <= Length(ASql) do
  begin
    if NextSqlToken(ASql, mIndex, mKind, mEnd) then
    begin
      if ASql[mIndex] = ')' then
      begin
        Dec(mDepth);
      end;
      if mCount = Length(Result) then
      begin
        SetLength(Result, mCount * 2 + 8);
      end;
      Result[mCount].Kind := mKind;
      Result[mCount].Text := Copy(ASql, mIndex, mEnd - mIndex + 1);
      Result[mCount].Offset := mIndex;
      Result[mCount].Depth := mDepth;
      Inc(mCount);
      if ASql[mIndex] = '(' then
      begin
        Inc(mDepth);
      end;
    end;
    mIndex := mEnd + 1;
  end;
  SetLength(Result, mCount);
end;

function IsWord(const ATokens: TArray<TSqlToken>; AIndex, ALast: Integer; const AWord: string): Boolean;
begin
  Result := (AIndex <= ALast) and (ATokens[AIndex].Kind = TSqlTokenKind.Word) and SameText(ATokens[AIndex].Text, AWord);
end;

function IsWordIn(const ATokens: TArray<TSqlToken>; AIndex, ALast: Integer; const AWords: array of string): Boolean;
begin
  Result := (AIndex <= ALast) and (ATokens[AIndex].Kind = TSqlTokenKind.Word) and
    MatchText(ATokens[AIndex].Text, AWords);
end;

function IsTableName(const AToken: TSqlToken): Boolean;
begin
  Result := (AToken.Kind = TSqlTokenKind.Quoted) or
    ((AToken.Kind = TSqlTokenKind.Word) and not MatchText(AToken.Text, cClauseWords));
end;

/// <summary>Steht der unbekannte Teil ATokens[AIndex] an der Stelle eines Werts (nach =, Komma, AND …)?</summary>
function IsValueHole(const ATokens: TArray<TSqlToken>; AIndex: Integer): Boolean;
var
  mPrevious: TSqlToken;
begin
  mPrevious := ATokens[AIndex - 1];
  Result := ((mPrevious.Kind = TSqlTokenKind.Symbol) and (Pos(mPrevious.Text, cValueSymbols) > 0)) or
    ((mPrevious.Kind = TSqlTokenKind.Word) and MatchText(mPrevious.Text, cValueWords));
end;

/// <summary>Hinter DELETE: TOP schließt aus, FROM wird übersprungen (ohne FROM in Großschreibung kein SQL).</summary>
function DeleteHead(const ATokens: TArray<TSqlToken>; var AIndex: Integer; ALast: Integer;
  AStrictCase: Boolean): Boolean;
begin
  Result := not IsWord(ATokens, AIndex, ALast, 'TOP');
  if Result and IsWord(ATokens, AIndex, ALast, 'FROM') then
  begin
    Inc(AIndex);
  end
  else if AStrictCase then
  begin
    Result := False;
  end;
end;

/// <summary>Hinter UPDATE: UPDATE OR INSERT (Firebird) und UPDATE STATISTICS ändern keine bestehenden Zeilen
/// pauschal; ONLY wird übersprungen.</summary>
function UpdateHead(const ATokens: TArray<TSqlToken>; var AIndex: Integer; ALast: Integer): Boolean;
begin
  Result := not IsWordIn(ATokens, AIndex, ALast, ['OR', 'STATISTICS', 'TOP']);
  if IsWord(ATokens, AIndex, ALast, 'ONLY') then
  begin
    Inc(AIndex);
  end;
end;

/// <summary>Beginnt die Anweisung mit DELETE oder UPDATE? AIndex steht danach auf der Tabelle.</summary>
function WriteHead(const ATokens: TArray<TSqlToken>; AFirst, ALast: Integer; AStrictCase: Boolean;
  out AIsDelete: Boolean; out AIndex: Integer): Boolean;
begin
  AIsDelete := IsWord(ATokens, AFirst, ALast, 'DELETE');
  AIndex := AFirst + 1;
  Result := (AIsDelete or IsWord(ATokens, AFirst, ALast, 'UPDATE')) and
    (not AStrictCase or (ATokens[AFirst].Text = UpperCase(ATokens[AFirst].Text)));
  if Result and AIsDelete then
  begin
    Result := DeleteHead(ATokens, AIndex, ALast, AStrictCase);
  end
  else if Result then
  begin
    Result := UpdateHead(ATokens, AIndex, ALast);
  end;
end;

/// <summary>Tabelle ab AIndex (auch Schema.Tabelle oder ein unbekannter Teil); AIndex steht danach dahinter.</summary>
function ReadWriteTable(const ATokens: TArray<TSqlToken>; var AIndex: Integer; ALast: Integer;
  var AWrite: TSqlWrite): Boolean;
begin
  Result := AIndex <= ALast;
  if not Result then
  begin
    Exit;
  end;
  if ATokens[AIndex].Kind = TSqlTokenKind.Hole then
  begin
    Inc(AIndex);
  end
  else if IsTableName(ATokens[AIndex]) then
  begin
    AWrite.Table := ATokens[AIndex].Text;
    Inc(AIndex);
    while (AIndex < ALast) and (ATokens[AIndex].Text = '.') and IsTableName(ATokens[AIndex + 1]) do
    begin
      AWrite.Table := AWrite.Table + '.' + ATokens[AIndex + 1].Text;
      Inc(AIndex, 2);
    end;
  end
  else
  begin
    Result := False;
  end;
end;

procedure SkipAlias(const ATokens: TArray<TSqlToken>; var AIndex: Integer; ALast: Integer);
begin
  if IsWord(ATokens, AIndex, ALast, 'AS') then
  begin
    Inc(AIndex, 2);
  end
  else if (AIndex <= ALast) and IsTableName(ATokens[AIndex]) then
  begin
    Inc(AIndex);
  end;
end;

/// <summary>Folgt hinter der Tabelle SQL? Bei DELETE eine Klausel oder nichts (sonst Meldungstext), bei
/// UPDATE SET.</summary>
function WriteBodyFollows(const ATokens: TArray<TSqlToken>; AIndex, ALast: Integer; AIsDelete: Boolean): Boolean;
begin
  if AIsDelete then
  begin
    Result := (AIndex > ALast) or IsWordIn(ATokens, AIndex, ALast, cClauseWords);
  end
  else
  begin
    Result := IsWord(ATokens, AIndex, ALast, 'SET');
  end;
end;

/// <summary>Schränkt ATokens[AScan] die Zeilen ein (WHERE, JOIN … auf Ebene ALevel), oder ist es ein
/// unbekannter Teil an der Stelle einer Klausel?</summary>
function MayRestrict(const ATokens: TArray<TSqlToken>; AScan, ALast, ALevel: Integer): Boolean;
begin
  Result := (ATokens[AScan].Depth = ALevel) and IsWordIn(ATokens, AScan, ALast, cRestrictWords) or
    (ATokens[AScan].Kind = TSqlTokenKind.Hole) and not IsValueHole(ATokens, AScan);
end;

function StatementWrite(const ATokens: TArray<TSqlToken>; AFirst, ALast: Integer; AStrictCase: Boolean;
  out AWrite: TSqlWrite): Boolean;
var
  mIndex, mScan: Integer;
  mIsDelete: Boolean;
begin
  Result := False;
  AWrite := Default(TSqlWrite);
  if WriteHead(ATokens, AFirst, ALast, AStrictCase, mIsDelete, mIndex) and
    ReadWriteTable(ATokens, mIndex, ALast, AWrite) then
  begin
    SkipAlias(ATokens, mIndex, ALast);
    Result := WriteBodyFollows(ATokens, mIndex, ALast, mIsDelete);
    for mScan := mIndex to ALast do
    begin
      Result := Result and not MayRestrict(ATokens, mScan, ALast, ATokens[AFirst].Depth);
    end;
  end;
  if Result then
  begin
    AWrite.Kind := UpperCase(ATokens[AFirst].Text);
    AWrite.Offset := ATokens[AFirst].Offset;
  end;
end;

function SqlWrites(const ASql: string; AStrictCase: Boolean): TArray<TSqlWrite>;
var
  mTokens: TArray<TSqlToken>;
  mFirst, mLast: Integer;
  mWrite: TSqlWrite;
begin
  Result := nil;
  mTokens := SqlTokens(ASql);
  mFirst := 0;
  while mFirst <= High(mTokens) do
  begin
    mLast := mFirst;
    while (mLast <= High(mTokens)) and not ((mTokens[mLast].Kind = TSqlTokenKind.Symbol) and
      (mTokens[mLast].Text = ';') and (mTokens[mLast].Depth = mTokens[mFirst].Depth)) do
    begin
      Inc(mLast);
    end;
    if StatementWrite(mTokens, mFirst, mLast - 1, AStrictCase, mWrite) then
    begin
      Result := Result + [mWrite];
    end;
    mFirst := mLast + 1;
  end;
end;

/// <summary>TOP 10, FIRST (…), SKIP :n samt PERCENT und WITH TIES ab dem Wort AScan; liefert das Token
/// dahinter.</summary>
function SkipSelectLimit(const ATokens: TArray<TSqlToken>; AScan, ALevel: Integer): Integer;
begin
  Result := AScan + 1;
  if ATokens[Result].Text = '(' then
  begin
    while (Result <= High(ATokens)) and not ((ATokens[Result].Text = ')') and (ATokens[Result].Depth = ALevel)) do
    begin
      Inc(Result);
    end;
  end
  else if ATokens[Result].Text = ':' then
  begin
    Inc(Result);
  end;
  Inc(Result);
  if IsWord(ATokens, Result, High(ATokens), 'PERCENT') then
  begin
    Inc(Result);
  end;
  if IsWord(ATokens, Result, High(ATokens), 'WITH') and IsWord(ATokens, Result + 1, High(ATokens), 'TIES') then
  begin
    Inc(Result, 2);
  end;
end;

/// <summary>Überspringt DISTINCT, TOP n und Verwandte ab AScan; liefert den Anfang der Spaltenliste.</summary>
function SkipSelectPrefix(const ATokens: TArray<TSqlToken>; AScan, ALevel: Integer): Integer;
begin
  Result := AScan;
  while Result <= High(ATokens) do
  begin
    if IsWordIn(ATokens, Result, High(ATokens), cSelectModifiers) then
    begin
      Inc(Result);
    end
    else if IsWordIn(ATokens, Result, High(ATokens), cSelectLimits) and (Result < High(ATokens)) then
    begin
      Result := SkipSelectLimit(ATokens, Result, ALevel);
    end
    else
    begin
      Break;
    end;
  end;
end;

/// <summary>Stern (*) oder Alias.* am Anfang eines Spalteneintrags AScan an AFound anhängen.</summary>
procedure AddStarAt(const ATokens: TArray<TSqlToken>; AScan: Integer; var AFound: TArray<TSqlStar>);
var
  mStar: TSqlStar;
begin
  mStar := Default(TSqlStar);
  if ATokens[AScan].Text = '*' then
  begin
    mStar.Offset := ATokens[AScan].Offset;
    AFound := AFound + [mStar];
  end
  else if (ATokens[AScan].Kind in [TSqlTokenKind.Word, TSqlTokenKind.Quoted]) and (AScan + 2 <= High(ATokens)) and
    (ATokens[AScan + 1].Text = '.') and (ATokens[AScan + 2].Text = '*') then
  begin
    mStar.Offset := ATokens[AScan + 2].Offset;
    mStar.Qualifier := ATokens[AScan].Text;
    AFound := AFound + [mStar];
  end;
end;

/// <summary>Endet die Spaltenliste bei AScan (Ebene verlassen, FROM, ;)? ASawFrom: an einem FROM.</summary>
function ColumnListEnds(const ATokens: TArray<TSqlToken>; AScan, ALevel: Integer; out ASawFrom: Boolean): Boolean;
var
  mSameLevel: Boolean;
begin
  mSameLevel := ATokens[AScan].Depth = ALevel;
  ASawFrom := mSameLevel and IsWord(ATokens, AScan, High(ATokens), 'FROM');
  Result := (ATokens[AScan].Depth < ALevel) or ASawFrom or mSameLevel and
    (ATokens[AScan].Kind = TSqlTokenKind.Symbol) and (ATokens[AScan].Text = ';');
end;

/// <summary>Sterne der Spaltenliste ab AScan bis FROM auf derselben Ebene; AScan steht danach am Ende.</summary>
function ColumnStars(const ATokens: TArray<TSqlToken>; var AScan: Integer; ALevel: Integer;
  out ASawFrom, ASawHole: Boolean): TArray<TSqlStar>;
var
  mItemStart: Boolean;
begin
  Result := nil;
  mItemStart := True;
  ASawFrom := False;
  ASawHole := False;
  while (AScan <= High(ATokens)) and not ColumnListEnds(ATokens, AScan, ALevel, ASawFrom) do
  begin
    if ATokens[AScan].Depth = ALevel then
    begin
      ASawHole := ASawHole or (ATokens[AScan].Kind = TSqlTokenKind.Hole);
      if mItemStart then
      begin
        AddStarAt(ATokens, AScan, Result);
      end;
      mItemStart := (ATokens[AScan].Kind = TSqlTokenKind.Symbol) and (ATokens[AScan].Text = ',');
    end;
    Inc(AScan);
  end;
end;

/// <summary>SELECT bei AIndex, dessen Sterne zählen: in Großschreibung, wenn verlangt, und nicht in
/// EXISTS (SELECT * …), das nur nach Zeilen fragt.</summary>
function IsCheckedSelect(const ATokens: TArray<TSqlToken>; AIndex: Integer; AStrictCase: Boolean): Boolean;
begin
  Result := IsWord(ATokens, AIndex, High(ATokens), 'SELECT') and
    (not AStrictCase or (ATokens[AIndex].Text = 'SELECT')) and not ((AIndex >= 2) and
    (ATokens[AIndex - 1].Text = '(') and IsWord(ATokens, AIndex - 2, High(ATokens), 'EXISTS'));
end;

function SqlStars(const ASql: string; AStrictCase: Boolean): TArray<TSqlStar>;
var
  mTokens: TArray<TSqlToken>;
  mIndex, mScan: Integer;
  mSawFrom, mSawHole: Boolean;
  mFound: TArray<TSqlStar>;
begin
  Result := nil;
  mTokens := SqlTokens(ASql);
  for mIndex := 0 to High(mTokens) do
  begin
    if not IsCheckedSelect(mTokens, mIndex, AStrictCase) then
    begin
      Continue;
    end;
    mScan := SkipSelectPrefix(mTokens, mIndex + 1, mTokens[mIndex].Depth);
    mFound := ColumnStars(mTokens, mScan, mTokens[mIndex].Depth, mSawFrom, mSawHole);
    // Ohne FROM ist es kein SQL (Meldungstext); im SQL-Text darf ein unbekannter Teil das FROM bringen.
    if mSawFrom or (not AStrictCase and (mSawHole or (mScan > High(mTokens)))) then
    begin
      Result := Result + mFound;
    end;
  end;
end;

end.
