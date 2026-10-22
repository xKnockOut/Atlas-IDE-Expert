unit Atlas.Common.Rules.Builtin.Database;

// Regeln für SQL im Quelltext und in der Formulardatei (#909, Gruppe Datenbank):
//   sql-write-without-where  UPDATE bzw. DELETE ohne WHERE (#966). Der SQL-Text
//                            entsteht je Empfänger in einer Routine aus
//                            SQL.Text :=, SQL.Add, CommandText := und Clear, dazu
//                            das erste Argument von ExecSQL, ExecSQLScalar,
//                            ExecuteDirect und Execute; Werte aus Konstanten und
//                            lokalen Zuweisungen setzt die Regel ein. In der
//                            Formulardatei zählen SQL.Strings (auch DeleteSQL,
//                            ModifySQL) und CommandText, solange die Unit die
//                            Eigenschaft nicht selbst verändert.
//
// Unbekannte Teile (Variablen, Aufrufe) stehen im SQL-Text als #1. Stehen sie
// hinter der Tabelle an einer Stelle, an der eine Klausel stehen kann, bleibt
// die Anweisung still; ein dynamischer Tabellenname meldet mit mittlerer
// Konfidenz. Ein Empfänger, den die Routine weitergibt oder den eine andere
// Routine ergänzt, gilt als unbekannt. Literale außerhalb von SQL-Eigenschaften
// zählen nur mit DELETE bzw. UPDATE in Großbuchstaben, damit Meldungstexte wie
// 'Delete from cart failed' still bleiben.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  SqlWriteWithoutWhereRuleId = 'sql-write-without-where';

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

  TSqlWriteWithoutWhereRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>UPDATE- und DELETE-Anweisungen in ASql ohne WHERE, JOIN, TOP, LIMIT und ROWS auf oberster
    /// Ebene. #1 steht für einen unbekannten Teil. AStrictCase: Schlüsselwort nur in Großbuchstaben.</summary>
    class function Writes(const ASql: string; AStrictCase: Boolean): TArray<TSqlWrite>; static;
    /// <summary>Steht ATable (mit oder ohne Schema, Anführungszeichen und eckige Klammern) in AAllowed?</summary>
    class function Allowed(const ATable: string; const AAllowed: TArray<string>): Boolean; static;
  end;

procedure RegisterDatabaseRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Editing.SqlText,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Text.Chars;

const
  Hole = #1;
  ClauseWords: array[0..16] of string = ('WHERE', 'SET', 'FROM', 'RETURNING', 'OUTPUT', 'USING', 'JOIN', 'INNER',
    'LEFT', 'RIGHT', 'FULL', 'CROSS', 'LIMIT', 'ROWS', 'ORDER', 'OPTION', 'AS');
  // Schränken die Zeilen ein, auch ohne WHERE.
  RestrictWords: array[0..5] of string = ('WHERE', 'JOIN', 'LIMIT', 'ROWS', 'TOP', 'FETCH');
  // Davor steht ein unbekannter Teil an der Stelle eines Werts, nicht einer Klausel.
  ValueWords: array[0..10] of string = ('AND', 'OR', 'NOT', 'LIKE', 'IN', 'IS', 'THEN', 'ELSE', 'WHEN', 'VALUES',
    'BETWEEN');
  ValueSymbols = '=<>,(+-*/|%';
  SqlCalls: array[0..3] of string = ('ExecSQL', 'ExecSQLScalar', 'ExecuteDirect', 'Execute');
  // Zugriffe auf einen Empfänger, die seinen SQL-Text nicht ändern.
  HarmlessMembers: array[0..3] of string = ('Text', 'Count', 'BeginUpdate', 'EndUpdate');
  QuoteChars: array[0..3] of string = ('"', '[', ']', '`');

type
{$SCOPEDENUMS ON}
  TSqlTokenKind = (Word, Quoted, Literal, Symbol, Hole);
  TCarrier = (None, Assign, Append, Clear, Execute);
{$SCOPEDENUMS OFF}

  TSqlToken = record
    Kind: TSqlTokenKind;
    Text: string;
    Offset: Integer;
    Depth: Integer;
  end;

function SqlTokens(const ASql: string): TArray<TSqlToken>;
var
  Index, Start, Depth, Count: Integer;
  Ch, Close: Char;

  procedure Add(AKind: TSqlTokenKind; AStart, AEnd: Integer);
  begin
    if Count = Length(Result) then
      SetLength(Result, Count * 2 + 8);
    Result[Count].Kind := AKind;
    Result[Count].Text := Copy(ASql, AStart, AEnd - AStart + 1);
    Result[Count].Offset := AStart;
    Result[Count].Depth := Depth;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  Depth := 0;
  Index := 1;
  while Index <= Length(ASql) do
  begin
    Ch := ASql[Index];
    Start := Index;
    if Ch = Hole then
      Add(TSqlTokenKind.Hole, Index, Index)
    else if Ch <= ' ' then
      // Leerraum
    else if (Ch = '-') and (Index < Length(ASql)) and (ASql[Index + 1] = '-') then
    begin
      while (Index <= Length(ASql)) and not CharInSet(ASql[Index], [#10, #13]) do
        Inc(Index);
      Continue;
    end
    else if (Ch = '/') and (Index < Length(ASql)) and (ASql[Index + 1] = '*') then
    begin
      Index := PosEx('*/', ASql, Index + 2);
      if Index = 0 then
        Break;
      Inc(Index, 2);
      Continue;
    end
    else if CharInSet(Ch, ['''', '"', '[', '`']) then
    begin
      Close := Ch;
      if Ch = '[' then
        Close := ']';
      Inc(Index);
      while (Index <= Length(ASql)) and (ASql[Index] <> Close) do
        Inc(Index);
      if Ch = '''' then
        Add(TSqlTokenKind.Literal, Start, Index)
      else
        Add(TSqlTokenKind.Quoted, Start, Index);
    end
    else if TTextChars.IsIdentChar(Ch) then
    begin
      while (Index < Length(ASql)) and (TTextChars.IsIdentChar(ASql[Index + 1]) or (ASql[Index + 1] = '$')) do
        Inc(Index);
      Add(TSqlTokenKind.Word, Start, Index);
    end
    else
    begin
      if Ch = ')' then
        Dec(Depth);
      Add(TSqlTokenKind.Symbol, Start, Index);
      if Ch = '(' then
        Inc(Depth);
    end;
    Inc(Index);
  end;
  SetLength(Result, Count);
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
    ((AToken.Kind = TSqlTokenKind.Word) and not MatchText(AToken.Text, ClauseWords));
end;

/// <summary>Steht der unbekannte Teil ATokens[AIndex] an der Stelle eines Werts (nach =, Komma, AND …)?</summary>
function IsValueHole(const ATokens: TArray<TSqlToken>; AIndex: Integer): Boolean;
var
  Previous: TSqlToken;
begin
  Previous := ATokens[AIndex - 1];
  Result := ((Previous.Kind = TSqlTokenKind.Symbol) and (Pos(Previous.Text, ValueSymbols) > 0)) or
    ((Previous.Kind = TSqlTokenKind.Word) and MatchText(Previous.Text, ValueWords));
end;

function StatementWrite(const ATokens: TArray<TSqlToken>; AFirst, ALast: Integer; AStrictCase: Boolean;
  out AWrite: TSqlWrite): Boolean;
var
  Index, Scan, Level: Integer;
  IsDelete: Boolean;
begin
  Result := False;
  AWrite := Default(TSqlWrite);
  IsDelete := IsWord(ATokens, AFirst, ALast, 'DELETE');
  if not IsDelete and not IsWord(ATokens, AFirst, ALast, 'UPDATE') then
    Exit;
  if AStrictCase and (ATokens[AFirst].Text <> UpperCase(ATokens[AFirst].Text)) then
    Exit;
  Level := ATokens[AFirst].Depth;
  Index := AFirst + 1;
  if IsDelete then
  begin
    if IsWord(ATokens, Index, ALast, 'TOP') then
      Exit;
    if IsWord(ATokens, Index, ALast, 'FROM') then
      Inc(Index)
    else if AStrictCase then
      Exit;
  end
  else
  begin
    // UPDATE OR INSERT (Firebird) und UPDATE STATISTICS ändern keine bestehenden Zeilen pauschal.
    if IsWordIn(ATokens, Index, ALast, ['OR', 'STATISTICS', 'TOP']) then
      Exit;
    if IsWord(ATokens, Index, ALast, 'ONLY') then
      Inc(Index);
  end;
  if Index > ALast then
    Exit;
  if ATokens[Index].Kind = TSqlTokenKind.Hole then
    Inc(Index)
  else if IsTableName(ATokens[Index]) then
  begin
    AWrite.Table := ATokens[Index].Text;
    Inc(Index);
    while (Index < ALast) and (ATokens[Index].Text = '.') and IsTableName(ATokens[Index + 1]) do
    begin
      AWrite.Table := AWrite.Table + '.' + ATokens[Index + 1].Text;
      Inc(Index, 2);
    end;
  end
  else
    Exit;
  // Alias
  if IsWord(ATokens, Index, ALast, 'AS') then
    Inc(Index, 2)
  else if (Index <= ALast) and IsTableName(ATokens[Index]) then
    Inc(Index);
  if IsDelete then
  begin
    // Folgt kein SQL, ist es kein SQL (Meldungstext).
    if (Index <= ALast) and not IsWordIn(ATokens, Index, ALast, ClauseWords) then
      Exit;
  end
  else if not IsWord(ATokens, Index, ALast, 'SET') then
    Exit;
  for Scan := Index to ALast do
  begin
    if (ATokens[Scan].Depth = Level) and IsWordIn(ATokens, Scan, ALast, RestrictWords) then
      Exit;
    if (ATokens[Scan].Kind = TSqlTokenKind.Hole) and not IsValueHole(ATokens, Scan) then
      Exit;
  end;
  AWrite.Kind := UpperCase(ATokens[AFirst].Text);
  AWrite.Offset := ATokens[AFirst].Offset;
  Result := True;
end;

{ TSqlBuild }

type
  TSqlPiece = record
    /// <summary>Ab hier im Text (1-basiert) stammt der Text aus Token.</summary>
    Offset: Integer;
    Token: Integer;
  end;

  /// <summary>SQL-Text, wie ihn die Unit zusammensetzt; #1 für unbekannte Teile.</summary>
  TSqlBuild = class
  public
    Text: string;
    Pieces: TArray<TSqlPiece>;
    /// <summary>Aus einer SQL-Eigenschaft oder einem SQL-Aufruf: Schlüsselwort in jeder Schreibweise.</summary>
    SqlContext: Boolean;
    /// <summary>Weitergegeben oder anders verändert: nicht prüfen.</summary>
    Unknown: Boolean;
    constructor Create(ASqlContext: Boolean);
    procedure AddText(const AText: string; AToken: Integer);
    procedure AddHole(AToken: Integer);
    /// <summary>Text von ABuild anhängen; AToken &lt; 0 übernimmt dessen Stücke, sonst zählt alles zu AToken.</summary>
    procedure AddBuild(ABuild: TSqlBuild; AToken: Integer);
    procedure NewLine;
    function TokenAt(AOffset: Integer): Integer;
  end;

constructor TSqlBuild.Create(ASqlContext: Boolean);
begin
  inherited Create;
  SqlContext := ASqlContext;
end;

procedure TSqlBuild.AddText(const AText: string; AToken: Integer);
var
  Piece: TSqlPiece;
begin
  if AText = '' then
    Exit;
  Piece.Offset := Length(Text) + 1;
  Piece.Token := AToken;
  Pieces := Pieces + [Piece];
  Text := Text + AText;
end;

procedure TSqlBuild.AddHole(AToken: Integer);
begin
  AddText(' ' + Hole + ' ', AToken);
end;

procedure TSqlBuild.AddBuild(ABuild: TSqlBuild; AToken: Integer);
var
  Piece: TSqlPiece;
  Index: Integer;
begin
  if ABuild.Unknown then
    Unknown := True;
  if AToken >= 0 then
  begin
    AddText(ABuild.Text, AToken);
    Exit;
  end;
  for Piece in ABuild.Pieces do
    Pieces := Pieces + [Piece];
  for Index := Length(Pieces) - Length(ABuild.Pieces) to High(Pieces) do
    Inc(Pieces[Index].Offset, Length(Text));
  Text := Text + ABuild.Text;
end;

procedure TSqlBuild.NewLine;
begin
  if Text <> '' then
    Text := Text + #13#10;
end;

function TSqlBuild.TokenAt(AOffset: Integer): Integer;
var
  Piece: TSqlPiece;
begin
  Result := -1;
  for Piece in Pieces do
    if (Piece.Offset <= AOffset) or (Result < 0) then
      Result := Piece.Token;
end;

type
  /// <summary>Werte eines Namens (Konstante oder lokale Zuweisung) und die Stellen ihrer Zuweisung.</summary>
  TNamedValue = class
  public
    Builds: TObjectList<TSqlBuild>;
    /// <summary>Token der Namen links der Zuweisungen bzw. der Deklaration; zählen nicht als Verwendung.</summary>
    Definitions: TList<Integer>;
    /// <summary>Aktueller Wert; nil nach einer Zuweisung, die kein Literal ist.</summary>
    Current: TSqlBuild;
    constructor Create;
    destructor Destroy; override;
    procedure Assign(ABuild: TSqlBuild; ADefinition: Integer);
  end;

  TFoundWrite = record
    Range: TTextRange;
    Message: string;
    Confidence: TRuleConfidence;
    /// <summary>Empfänger in Kleinbuchstaben; '' bei einzelnen Ausdrücken.</summary>
    Key: string;
    Segment: Integer;
  end;

  /// <summary>Ein Lauf der Regel über die Token einer Unit.</summary>
  TSqlWriteScan = class
  private
    FTokens: TArray<TPascalToken>;
    FAllowed: TArray<string>;
    FConsumed: TArray<Boolean>;
    FSegments: TArray<Integer>;
    FConstants: TObjectDictionary<string, TNamedValue>;
    FLocals: TObjectDictionary<string, TNamedValue>;
    FReceivers: TObjectDictionary<string, TSqlBuild>;
    FKeys: TDictionary<string, Boolean>;
    /// <summary>Segmente, in denen ein Empfänger ergänzt oder weitergegeben wird.</summary>
    FTouched: TObjectDictionary<string, TList<Integer>>;
    FFound: TList<TFoundWrite>;
    FReceiverRead: string;
    FSegment: Integer;
    function IsChainStart(AIndex: Integer): Boolean;
    function Chain(AIndex: Integer; out ALast: Integer): string;
    function Carrier(AIndex: Integer; out AKey: string; out ALast: Integer): TCarrier;
    function MatchingClose(AOpen: Integer): Integer;
    function ExpressionEnd(AFirst: Integer): Integer;
    function StartsLiteral(AIndex: Integer): Boolean;
    function ChangesReceiver(const AChain, AKey: string): Boolean;
    procedure Evaluate(AFirst, ALast: Integer; ABuild: TSqlBuild);
    procedure Consume(AFirst, ALast: Integer);
    procedure Finish(ABuild: TSqlBuild; const AKey: string);
    procedure FinishNamed(AValues: TObjectDictionary<string, TNamedValue>; AFirst, ALast: Integer);
    procedure FinishSegment(AFirst, ALast: Integer);
    procedure Touch(const AKey: string; ASegment: Integer);
    procedure ComputeSegments;
    procedure CollectConstants;
    procedure CollectKeys;
    procedure Scan;
  public
    constructor Create(const ATokens: TArray<TPascalToken>; const AAllowed: TArray<string>);
    destructor Destroy; override;
    procedure Run;
    procedure Report(const AReport: IRuleReport);
    property Tokens: TArray<TPascalToken> read FTokens;
  end;

function IsSqlKey(const AKey: string): Boolean;
var
  Last: string;
begin
  Last := Copy(AKey, LastDelimiter('.', AKey) + 1, MaxInt);
  Result := EndsText('SQL', Last) or SameText(Last, 'CommandText');
end;

function WriteMessage(const AWrite: TSqlWrite; const ASuffix: string): string;
var
  Table: string;
begin
  if AWrite.Table = '' then
    Table := 'der Tabelle'
  else
    Table := 'von ' + AWrite.Table;
  if AWrite.Kind = 'DELETE' then
    Result := Format('DELETE ohne WHERE löscht alle Zeilen %s%s.', [Table, ASuffix])
  else
    Result := Format('UPDATE ohne WHERE ändert alle Zeilen %s%s.', [Table, ASuffix]);
end;

function WriteConfidence(const AWrite: TSqlWrite): TRuleConfidence;
begin
  if AWrite.Table = '' then
    Result := TRuleConfidence.Medium
  else
    Result := TRuleConfidence.High;
end;

/// <summary>Formatangaben (%s, %0:d) als unbekannte Teile; die Länge bleibt gleich.</summary>
function FormatHoles(const AText: string): string;
var
  Index, Start, Blank: Integer;
begin
  Result := AText;
  Index := 1;
  while Index < Length(Result) do
  begin
    if Result[Index] = '%' then
    begin
      Start := Index;
      Inc(Index);
      if Result[Index] = '%' then
        Result[Index] := ' '
      else
      begin
        while (Index < Length(Result)) and CharInSet(Result[Index], ['0'..'9', ':', '-', '.', '*']) do
          Inc(Index);
        Result[Start] := Hole;
        for Blank := Start + 1 to Index do
          Result[Blank] := ' ';
      end;
    end;
    Inc(Index);
  end;
end;

{ TNamedValue }

constructor TNamedValue.Create;
begin
  inherited Create;
  Builds := TObjectList<TSqlBuild>.Create;
  Definitions := TList<Integer>.Create;
end;

destructor TNamedValue.Destroy;
begin
  Definitions.Free;
  Builds.Free;
  inherited;
end;

procedure TNamedValue.Assign(ABuild: TSqlBuild; ADefinition: Integer);
begin
  Builds.Add(ABuild);
  Definitions.Add(ADefinition);
  Current := ABuild;
end;

{ TSqlWriteScan }

constructor TSqlWriteScan.Create(const ATokens: TArray<TPascalToken>; const AAllowed: TArray<string>);
begin
  inherited Create;
  FTokens := ATokens;
  FAllowed := AAllowed;
  SetLength(FConsumed, Length(FTokens));
  FConstants := TObjectDictionary<string, TNamedValue>.Create([doOwnsValues]);
  FLocals := TObjectDictionary<string, TNamedValue>.Create([doOwnsValues]);
  FReceivers := TObjectDictionary<string, TSqlBuild>.Create([doOwnsValues]);
  FKeys := TDictionary<string, Boolean>.Create;
  FTouched := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  FFound := TList<TFoundWrite>.Create;
end;

destructor TSqlWriteScan.Destroy;
begin
  FFound.Free;
  FTouched.Free;
  FKeys.Free;
  FReceivers.Free;
  FLocals.Free;
  FConstants.Free;
  inherited;
end;

function TSqlWriteScan.IsChainStart(AIndex: Integer): Boolean;
begin
  Result := (FTokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    ((AIndex = 0) or not FTokens[AIndex - 1].IsSymbol('.'));
end;

function TSqlWriteScan.Chain(AIndex: Integer; out ALast: Integer): string;
begin
  Result := FTokens[AIndex].Text;
  ALast := AIndex;
  while (ALast + 2 <= High(FTokens)) and FTokens[ALast + 1].IsSymbol('.') and
    (FTokens[ALast + 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Result := Result + '.' + FTokens[ALast + 2].Text;
    Inc(ALast, 2);
  end;
end;

function TSqlWriteScan.Carrier(AIndex: Integer; out AKey: string; out ALast: Integer): TCarrier;
var
  Full, Base, Member: string;
  Next: Integer;
begin
  Result := TCarrier.None;
  Full := Chain(AIndex, ALast);
  Base := Copy(Full, 1, LastDelimiter('.', Full) - 1);
  Member := FTokens[ALast].Text;
  Next := ALast + 1;
  AKey := '';
  if Next > High(FTokens) then
    Exit;
  if FTokens[Next].IsSymbol(':=') and SameText(Member, 'CommandText') then
  begin
    AKey := Full;
    Result := TCarrier.Assign;
  end
  else if FTokens[Next].IsSymbol(':=') and SameText(Member, 'Text') and (Base <> '') then
  begin
    AKey := Base;
    Result := TCarrier.Assign;
  end
  else if FTokens[Next].IsSymbol('(') and MatchText(Member, ['Add', 'Append']) and (Base <> '') then
  begin
    AKey := Base;
    Result := TCarrier.Append;
  end
  else if SameText(Member, 'Clear') and (Base <> '') then
  begin
    AKey := Base;
    Result := TCarrier.Clear;
  end
  else if FTokens[Next].IsSymbol('(') and MatchText(Member, SqlCalls) then
    Result := TCarrier.Execute;
  AKey := LowerCase(AKey);
end;

function TSqlWriteScan.MatchingClose(AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to High(FTokens) do
    if FTokens[Result].IsSymbol('(') or FTokens[Result].IsSymbol('[') then
      Inc(Depth)
    else if FTokens[Result].IsSymbol(')') or FTokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
  Result := High(FTokens);
end;

function TSqlWriteScan.ExpressionEnd(AFirst: Integer): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  Index := AFirst;
  while Index <= High(FTokens) do
  begin
    Token := FTokens[Index];
    if Token.IsSymbol('(') or Token.IsSymbol('[') then
      Index := MatchingClose(Index)
    else if (Token.Kind = TPascalTokenKind.Keyword) or
      ((Token.Kind = TPascalTokenKind.Symbol) and not Token.IsSymbol('+') and not Token.IsSymbol('.')) then
      Break;
    Inc(Index);
  end;
  Result := Index - 1;
end;

function TSqlWriteScan.StartsLiteral(AIndex: Integer): Boolean;
begin
  Result := (AIndex <= High(FTokens)) and ((FTokens[AIndex].Kind in [TPascalTokenKind.StringLiteral,
    TPascalTokenKind.CharLiteral]) or ((AIndex < High(FTokens)) and MatchText(FTokens[AIndex].Text,
    ['Format', 'Concat']) and FTokens[AIndex + 1].IsSymbol('(')));
end;

function TSqlWriteScan.ChangesReceiver(const AChain, AKey: string): Boolean;
var
  Rest: string;
begin
  if SameText(AChain, AKey) then
    // Die Eigenschaft CommandText selbst lesen ändert nichts; X.SQL weitergeben schon.
    Exit(not EndsText('commandtext', AKey));
  if not StartsText(AKey + '.', AChain) then
    Exit(False);
  Rest := Copy(AChain, Length(AKey) + 2, MaxInt);
  if Pos('.', Rest) > 0 then
    Rest := Copy(Rest, 1, Pos('.', Rest) - 1);
  Result := not MatchText(Rest, HarmlessMembers);
end;

procedure TSqlWriteScan.Consume(AFirst, ALast: Integer);
var
  Index: Integer;
begin
  for Index := AFirst to ALast do
    FConsumed[Index] := True;
end;

procedure TSqlWriteScan.Evaluate(AFirst, ALast: Integer; ABuild: TSqlBuild);
var
  Index, Last, Close, Start: Integer;
  Name, Plain, Key: string;
  Value: TNamedValue;
  Inner: TSqlBuild;
  Receiver: TPair<string, TSqlBuild>;
  Found: Boolean;
begin
  Index := AFirst;
  while Index <= ALast do
  begin
    if FTokens[Index].Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral] then
    begin
      if TStringLiterals.PlainText(FTokens[Index].Text, Plain) then
        ABuild.AddText(Plain, Index)
      else
        ABuild.AddHole(Index);
    end
    else if FTokens[Index].IsSymbol('+') then
      // verkettet
    else if FTokens[Index].IsSymbol('(') or FTokens[Index].IsSymbol('[') then
    begin
      ABuild.AddHole(Index);
      Index := MatchingClose(Index);
    end
    else if FTokens[Index].Kind = TPascalTokenKind.Identifier then
    begin
      Name := Chain(Index, Last);
      if (Last < ALast) and FTokens[Last + 1].IsSymbol('(') and MatchText(Name, ['Format', 'Concat']) then
      begin
        Close := MatchingClose(Last + 1);
        Inner := TSqlBuild.Create(ABuild.SqlContext);
        try
          if SameText(Name, 'Format') then
          begin
            Start := Last + 2;
            Evaluate(Start, ExpressionEnd(Start), Inner);
            Inner.Text := FormatHoles(Inner.Text);
          end
          else
          begin
            Start := Last + 2;
            while Start < Close do
            begin
              Evaluate(Start, ExpressionEnd(Start), Inner);
              Start := ExpressionEnd(Start) + 2;
            end;
          end;
          ABuild.AddBuild(Inner, -1);
        finally
          Inner.Free;
        end;
        Index := Close;
      end
      else if (Last < ALast) and (FTokens[Last + 1].IsSymbol('(') or FTokens[Last + 1].IsSymbol('[')) then
      begin
        ABuild.AddHole(Index);
        Index := MatchingClose(Last + 1);
      end
      else if SameText(Name, 'sLineBreak') then
      begin
        ABuild.AddText(#13#10, Index);
        Index := Last;
      end
      else
      begin
        Found := False;
        if (Last = Index) and FLocals.TryGetValue(LowerCase(Name), Value) and (Value.Current <> nil) then
        begin
          ABuild.AddBuild(Value.Current, Index);
          Found := True;
        end
        else if (Last = Index) and FConstants.TryGetValue(LowerCase(Name), Value) and (Value.Current <> nil) then
        begin
          ABuild.AddBuild(Value.Current, Index);
          Found := True;
        end
        else
          for Receiver in FReceivers do
          begin
            Key := Receiver.Key;
            if SameText(Name, Key + '.Text') or (EndsText('commandtext', Key) and SameText(Name, Key)) then
            begin
              ABuild.AddBuild(Receiver.Value, -1);
              FReceiverRead := Key;
              Found := True;
              Break;
            end;
          end;
        if not Found then
          ABuild.AddHole(Index);
        Index := Last;
      end;
    end
    else
      ABuild.AddHole(Index);
    Inc(Index);
  end;
end;

procedure TSqlWriteScan.Finish(ABuild: TSqlBuild; const AKey: string);
var
  Write: TSqlWrite;
  Found: TFoundWrite;
  Token: Integer;
begin
  if ABuild.Unknown then
    Exit;
  for Write in TSqlWriteWithoutWhereRule.Writes(ABuild.Text, not ABuild.SqlContext) do
  begin
    if (Write.Table <> '') and TSqlWriteWithoutWhereRule.Allowed(Write.Table, FAllowed) then
      Continue;
    Token := ABuild.TokenAt(Write.Offset);
    if Token < 0 then
      Continue;
    Found.Range := TTextRange.Create(FTokens[Token].StartPos, FTokens[Token].EndPos);
    Found.Message := WriteMessage(Write, '');
    Found.Confidence := WriteConfidence(Write);
    Found.Key := AKey;
    Found.Segment := FSegment;
    FFound.Add(Found);
  end;
end;

procedure TSqlWriteScan.FinishNamed(AValues: TObjectDictionary<string, TNamedValue>; AFirst, ALast: Integer);
var
  Pair: TPair<string, TNamedValue>;
  Index: Integer;
  Used: Boolean;
  Build: TSqlBuild;
begin
  // Ein Name, der sonst nirgends vorkommt, wird an seinem Literal gemeldet; sonst prüft die Verwendung.
  for Pair in AValues do
  begin
    Used := False;
    for Index := AFirst to ALast do
      if IsChainStart(Index) and SameText(FTokens[Index].Text, Pair.Key) and
        not Pair.Value.Definitions.Contains(Index) then
      begin
        Used := True;
        Break;
      end;
    if not Used then
      for Build in Pair.Value.Builds do
        Finish(Build, '');
  end;
end;

procedure TSqlWriteScan.FinishSegment(AFirst, ALast: Integer);
var
  Pair: TPair<string, TSqlBuild>;
begin
  for Pair in FReceivers do
    Finish(Pair.Value, Pair.Key);
  FReceivers.Clear;
  FinishNamed(FLocals, AFirst, ALast);
  FLocals.Clear;
end;

procedure TSqlWriteScan.Touch(const AKey: string; ASegment: Integer);
var
  Segments: TList<Integer>;
begin
  if not FTouched.TryGetValue(AKey, Segments) then
  begin
    Segments := TList<Integer>.Create;
    FTouched.Add(AKey, Segments);
  end;
  if not Segments.Contains(ASegment) then
    Segments.Add(ASegment);
end;

procedure TSqlWriteScan.ComputeSegments;
var
  Index, Segment: Integer;
  Token: TPascalToken;
begin
  // Jede Routine (und jeder Abschnitt wie implementation) ist ein Segment; anonyme Methoden nicht.
  SetLength(FSegments, Length(FTokens));
  Segment := 0;
  for Index := 0 to High(FTokens) do
  begin
    Token := FTokens[Index];
    if (Token.IsKeyword('procedure') or Token.IsKeyword('function') or Token.IsKeyword('constructor') or
      Token.IsKeyword('destructor') or Token.IsKeyword('implementation') or Token.IsKeyword('initialization') or
      Token.IsKeyword('finalization')) and not ((Index > 0) and (FTokens[Index - 1].IsSymbol(':=') or
      FTokens[Index - 1].IsSymbol('(') or FTokens[Index - 1].IsSymbol(',') or FTokens[Index - 1].IsSymbol('=') or
      FTokens[Index - 1].IsSymbol(':') or FTokens[Index - 1].IsKeyword('to') or
      FTokens[Index - 1].IsKeyword('of'))) then
      Inc(Segment);
    FSegments[Index] := Segment;
  end;
end;

procedure TSqlWriteScan.CollectConstants;
var
  Index, Depth, First, Last: Integer;
  InConst: Boolean;
  Value: TNamedValue;
  Build: TSqlBuild;
begin
  InConst := False;
  Depth := 0;
  Index := 0;
  while Index < High(FTokens) do
  begin
    if FTokens[Index].IsSymbol('(') or FTokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if FTokens[Index].IsSymbol(')') or FTokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if Depth > 0 then
      // "const" in Parameterlisten ist kein Konstantenabschnitt.
    else if FTokens[Index].IsKeyword('const') or FTokens[Index].IsKeyword('resourcestring') then
      InConst := True
    else if FTokens[Index].IsKeyword('var') or FTokens[Index].IsKeyword('type') or
      FTokens[Index].IsKeyword('begin') or FTokens[Index].IsKeyword('procedure') or
      FTokens[Index].IsKeyword('function') or FTokens[Index].IsKeyword('implementation') then
      InConst := False
    else if InConst and IsChainStart(Index) and (FTokens[Index + 1].IsSymbol('=') or
      FTokens[Index + 1].IsSymbol(':')) then
    begin
      First := Index + 1;
      while (First <= High(FTokens)) and not FTokens[First].IsSymbol('=') and not FTokens[First].IsSymbol(';') do
        Inc(First);
      Inc(First);
      if StartsLiteral(First) then
      begin
        Last := ExpressionEnd(First);
        Build := TSqlBuild.Create(False);
        Evaluate(First, Last, Build);
        if not FConstants.TryGetValue(LowerCase(FTokens[Index].Text), Value) then
        begin
          Value := TNamedValue.Create;
          FConstants.Add(LowerCase(FTokens[Index].Text), Value);
        end;
        Value.Assign(Build, Index);
        Consume(First, Last);
        Index := Last;
      end;
    end;
    Inc(Index);
  end;
end;

procedure TSqlWriteScan.CollectKeys;
var
  Index, Last: Integer;
  Key: string;
  Pair: TPair<string, Boolean>;
  Full: string;
begin
  for Index := 0 to High(FTokens) do
    if IsChainStart(Index) and (Carrier(Index, Key, Last) in [TCarrier.Assign, TCarrier.Append, TCarrier.Clear]) then
      FKeys.AddOrSetValue(Key, True);
  // Ergänzt oder weitergegeben: gilt in den anderen Routinen als unbekannt.
  for Index := 0 to High(FTokens) do
    if IsChainStart(Index) then
      case Carrier(Index, Key, Last) of
        TCarrier.Append:
          Touch(Key, FSegments[Index]);
        TCarrier.None:
          begin
            Full := Chain(Index, Last);
            for Pair in FKeys do
              if ChangesReceiver(Full, Pair.Key) then
                Touch(Pair.Key, FSegments[Index]);
          end;
      end;
end;

procedure TSqlWriteScan.Scan;
var
  Index, Last, First, Close, SegmentStart: Integer;
  Key, Name: string;
  Build, Old: TSqlBuild;
  Value: TNamedValue;
  Pair: TPair<string, TSqlBuild>;
begin
  SegmentStart := 0;
  FSegment := 0;
  Index := 0;
  while Index <= High(FTokens) do
  begin
    if FSegments[Index] <> FSegment then
    begin
      FinishSegment(SegmentStart, Index - 1);
      SegmentStart := Index;
      FSegment := FSegments[Index];
    end;
    if FConsumed[Index] then
    begin
      Inc(Index);
      Continue;
    end;
    if IsChainStart(Index) then
    begin
      case Carrier(Index, Key, Last) of
        TCarrier.Assign:
          begin
            First := Last + 2;
            Close := ExpressionEnd(First);
            Build := TSqlBuild.Create(IsSqlKey(Key));
            FReceiverRead := '';
            Evaluate(First, Close, Build);
            if FReceivers.TryGetValue(Key, Old) and (FReceiverRead <> Key) then
              Finish(Old, Key);
            FReceivers.AddOrSetValue(Key, Build);
            Consume(First, Close);
            Index := Close + 1;
            Continue;
          end;
        TCarrier.Append:
          begin
            Close := MatchingClose(Last + 1);
            if not FReceivers.TryGetValue(Key, Build) then
            begin
              Build := TSqlBuild.Create(IsSqlKey(Key));
              FReceivers.Add(Key, Build);
            end;
            if ExpressionEnd(Last + 2) = Close - 1 then
            begin
              Old := TSqlBuild.Create(Build.SqlContext);
              try
                Evaluate(Last + 2, Close - 1, Old);
                Build.NewLine;
                Build.AddBuild(Old, -1);
              finally
                Old.Free;
              end;
            end
            else
              Build.Unknown := True;
            Consume(Last + 1, Close);
            Index := Close + 1;
            Continue;
          end;
        TCarrier.Clear:
          begin
            if FReceivers.TryGetValue(Key, Old) then
            begin
              Finish(Old, Key);
              FReceivers.Remove(Key);
            end;
            Index := Last + 1;
            Continue;
          end;
        TCarrier.Execute:
          begin
            Close := MatchingClose(Last + 1);
            First := Last + 2;
            if First < Close then
            begin
              Build := TSqlBuild.Create(True);
              try
                Evaluate(First, ExpressionEnd(First), Build);
                Finish(Build, '');
              finally
                Build.Free;
              end;
            end;
            Consume(Last + 1, Close);
            Index := Close + 1;
            Continue;
          end;
      end;
      Name := LowerCase(FTokens[Index].Text);
      if (Last = Index) and (Index < High(FTokens)) and FTokens[Index + 1].IsSymbol(':=') then
      begin
        First := Index + 2;
        if StartsLiteral(First) then
        begin
          Close := ExpressionEnd(First);
          Build := TSqlBuild.Create(False);
          Evaluate(First, Close, Build);
          if not FLocals.TryGetValue(Name, Value) then
          begin
            Value := TNamedValue.Create;
            FLocals.Add(Name, Value);
          end;
          Value.Assign(Build, Index);
          Consume(First, Close);
          Index := Close + 1;
          Continue;
        end;
        if FLocals.TryGetValue(Name, Value) then
          Value.Current := nil;
      end;
      Key := Chain(Index, Last);
      for Pair in FReceivers do
        if ChangesReceiver(Key, Pair.Key) then
          Pair.Value.Unknown := True;
      Index := Last + 1;
      Continue;
    end;
    if (FTokens[Index].Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) and
      not ((Index > 0) and FTokens[Index - 1].IsSymbol('+')) then
    begin
      Close := ExpressionEnd(Index);
      Build := TSqlBuild.Create(False);
      try
        Evaluate(Index, Close, Build);
        Finish(Build, '');
      finally
        Build.Free;
      end;
      Consume(Index, Close);
      Index := Close + 1;
      Continue;
    end;
    Inc(Index);
  end;
  FinishSegment(SegmentStart, High(FTokens));
  FinishNamed(FConstants, 0, High(FTokens));
end;

procedure TSqlWriteScan.Run;
begin
  if Length(FTokens) = 0 then
    Exit;
  ComputeSegments;
  CollectConstants;
  CollectKeys;
  Scan;
end;

procedure TSqlWriteScan.Report(const AReport: IRuleReport);
var
  Found: TFoundWrite;
  Segments: TList<Integer>;
  Segment: Integer;
  Seen: TDictionary<string, Boolean>;
  Foreign: Boolean;
  Id: string;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Found in FFound do
    begin
      Foreign := False;
      if (Found.Key <> '') and FTouched.TryGetValue(Found.Key, Segments) then
        for Segment in Segments do
          if Segment <> Found.Segment then
            Foreign := True;
      if Foreign then
        Continue;
      Id := Format('%d:%d:%s', [Found.Range.StartPos.Line, Found.Range.StartPos.Character, Found.Message]);
      if Seen.ContainsKey(Id) then
        Continue;
      Seen.Add(Id, True);
      AReport.Add(Found.Range, Found.Message, Found.Confidence);
    end;
  finally
    Seen.Free;
  end;
end;

{ TSqlWriteWithoutWhereRule }

function TSqlWriteWithoutWhereRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SqlWriteWithoutWhereRuleId, TRuleSeverity.Warning, 'UPDATE oder DELETE ohne WHERE');
end;

class function TSqlWriteWithoutWhereRule.Writes(const ASql: string; AStrictCase: Boolean): TArray<TSqlWrite>;
var
  Tokens: TArray<TSqlToken>;
  First, Last: Integer;
  Write: TSqlWrite;
begin
  Result := nil;
  Tokens := SqlTokens(ASql);
  First := 0;
  while First <= High(Tokens) do
  begin
    Last := First;
    while (Last <= High(Tokens)) and not ((Tokens[Last].Kind = TSqlTokenKind.Symbol) and
      (Tokens[Last].Text = ';') and (Tokens[Last].Depth = Tokens[First].Depth)) do
      Inc(Last);
    if StatementWrite(Tokens, First, Last - 1, AStrictCase, Write) then
      Result := Result + [Write];
    First := Last + 1;
  end;
end;

class function TSqlWriteWithoutWhereRule.Allowed(const ATable: string; const AAllowed: TArray<string>): Boolean;
var
  Name, Last, Item: string;
begin
  Name := ATable;
  for Item in QuoteChars do
    Name := StringReplace(Name, Item, '', [rfReplaceAll]);
  Last := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  for Item in AAllowed do
    if SameText(Item, Name) or SameText(Item, Last) then
      Exit(True);
  Result := False;
end;

/// <summary>Token des Felds AName in der Klassendeklaration, sonst des Formularklassennamens; -1 ohne.</summary>
function FormAnchor(const ATokens: TArray<TPascalToken>; const AName, AFormClass: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ATokens) - 1 do
  begin
    if ATokens[Index].IsKeyword('implementation') then
      Break;
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, AName) and
      ATokens[Index + 1].IsSymbol(':') then
      Exit(Index);
  end;
  for Index := 0 to High(ATokens) - 1 do
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, AFormClass) and
      ATokens[Index + 1].IsSymbol('=') then
      Exit(Index);
  Result := -1;
end;

/// <summary>Verändert die Unit AName.AProperty selbst (Zuweisung, Add, Weitergabe)?</summary>
function SourceTouches(const ATokens: TArray<TPascalToken>; const APrefix: string): Boolean;
var
  Index, Last: Integer;
  Full: string;
begin
  for Index := 0 to High(ATokens) do
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and ((Index = 0) or not ATokens[Index - 1].IsSymbol('.')) then
    begin
      Full := ATokens[Index].Text;
      Last := Index;
      while (Last + 2 <= High(ATokens)) and ATokens[Last + 1].IsSymbol('.') and
        (ATokens[Last + 2].Kind = TPascalTokenKind.Identifier) do
      begin
        Full := Full + '.' + ATokens[Last + 2].Text;
        Inc(Last, 2);
      end;
      if SameText(Full, APrefix) or StartsText(APrefix + '.', Full) then
        Exit(True);
    end;
  Result := False;
end;

function IsSqlProperty(const AName: string): Boolean;
begin
  Result := EndsText('SQL.Strings', AName) or SameText(AName, 'CommandText') or
    SameText(AName, 'CommandText.Strings');
end;

procedure CheckForm(const ATokens: TArray<TPascalToken>; AObject: TDfmObject; const AFormClass: string;
  const AAllowed: TArray<string>; const AReport: IRuleReport);
var
  Prop: TDfmProperty;
  Child: TDfmObject;
  Text, Root: string;
  Write: TSqlWrite;
  Anchor: Integer;
begin
  if AObject.Name <> '' then
    for Prop in AObject.Properties do
    begin
      if not IsSqlProperty(Prop.Name) or not TSqlText.FormValue(Prop.Value, Text) then
        Continue;
      Root := Prop.Name;
      if EndsText('.Strings', Root) then
        Root := Copy(Root, 1, Length(Root) - Length('.Strings'));
      if SourceTouches(ATokens, AObject.Name + '.' + Root) then
        Continue;
      for Write in TSqlWriteWithoutWhereRule.Writes(Text, False) do
      begin
        if (Write.Table <> '') and TSqlWriteWithoutWhereRule.Allowed(Write.Table, AAllowed) then
          Continue;
        Anchor := FormAnchor(ATokens, AObject.Name, AFormClass);
        if Anchor >= 0 then
          AReport.Add(TTextRange.Create(ATokens[Anchor].StartPos, ATokens[Anchor].EndPos),
            WriteMessage(Write, Format(' (%s.%s in der Formulardatei)', [AObject.Name, Root])),
            WriteConfidence(Write));
      end;
    end;
  for Child in AObject.Children do
    CheckForm(ATokens, Child, AFormClass, AAllowed, AReport);
end;

procedure TSqlWriteWithoutWhereRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Allowed: TArray<string>;
  Scan: TSqlWriteScan;
  Document: TDfmDocument;
begin
  Tokens := TRuleDerived.CodeTokens(TRuleDerived.Open(AContext), AContext);
  Allowed := TRuleOptions.Strings(AContext.Options, 'allowTables', nil);
  Scan := TSqlWriteScan.Create(Tokens, Allowed);
  try
    Scan.Run;
    Scan.Report(AReport);
  finally
    Scan.Free;
  end;
  if AContext.FormText = '' then
    Exit;
  Document := TDfmParser.Parse(AContext.FormText);
  try
    if Document.Root <> nil then
      CheckForm(Tokens, Document.Root, Document.Root.TypeName, Allowed, AReport);
  finally
    Document.Free;
  end;
end;

procedure RegisterDatabaseRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSqlWriteWithoutWhereRule.Create);
end;

end.
