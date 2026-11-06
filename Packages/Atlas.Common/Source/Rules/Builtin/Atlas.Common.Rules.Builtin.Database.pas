unit Atlas.Common.Rules.Builtin.Database;

// Regeln für SQL im Quelltext und in der Formulardatei (#909, Gruppe Datenbank):
//   sql-write-without-where  UPDATE bzw. DELETE ohne WHERE (#966). Der SQL-Text
//                            entsteht je Empfänger in einer Routine aus
//                            SQL.Text :=, SQL.Add, CommandText := und Clear, dazu
//                            das erste Argument von ExecSQL, ExecSQLScalar, Open,
//                            ExecuteDirect und Execute; Werte aus Konstanten und
//                            lokalen Zuweisungen setzt die Regel ein. In der
//                            Formulardatei zählen SQL.Strings (auch DeleteSQL,
//                            ModifySQL) und CommandText, solange die Unit die
//                            Eigenschaft nicht selbst verändert.
//   sql-select-star          SELECT * bzw. SELECT t.* (#967) in denselben
//                            Quellen; EXISTS (SELECT * …) und COUNT(*) bleiben
//                            still. Korrektur: * durch die persistenten Felder
//                            der Datenmenge aus der Formulardatei ersetzen,
//                            solange der Stern in einem einzelnen Literal steht.
//
// Beide Regeln teilen den Lauf TSqlScan; welche Stellen eines SQL-Texts zählen,
// entscheidet ein TSqlFinder je Regel.
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
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Database.Statements;

const
  SqlWriteWithoutWhereRuleId = 'sql-write-without-where';
  SqlSelectStarRuleId = 'sql-select-star';

type
  TSqlWrite = Atlas.Common.Rules.Builtin.Database.Statements.TSqlWrite;
  TSqlStar = Atlas.Common.Rules.Builtin.Database.Statements.TSqlStar;

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

  TSqlSelectStarRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Sterne in Spaltenlisten von ASql, auch in Unterabfragen, außer in EXISTS (…). #1 steht für
    /// einen unbekannten Teil. AStrictCase: SELECT nur in Großbuchstaben.</summary>
    class function Stars(const ASql: string; AStrictCase: Boolean): TArray<TSqlStar>; static;
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
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDatabaseText = (OfTable, DeleteAll, UpdateAll, WhereTitle, InFormFile, StarTitle, AllColumns, AllColumnsOf,
    ReplaceStar, OfNamedTable);

const
  cTexts: array[TDatabaseText] of TAtlasText = (
    (De: 'der Tabelle'; En: 'of the table'),
    (De: 'DELETE ohne WHERE löscht alle Zeilen %s%s.'; En: 'DELETE without WHERE deletes all rows %s%s.'),
    (De: 'UPDATE ohne WHERE ändert alle Zeilen %s%s.'; En: 'UPDATE without WHERE changes all rows %s%s.'),
    (De: 'UPDATE oder DELETE ohne WHERE'; En: 'UPDATE or DELETE without WHERE'),
    (De: ' (%s.%s in der Formulardatei)'; En: ' (%s.%s in the form file)'),
    (De: 'SELECT * im Code'; En: 'SELECT * in code'),
    (De: 'SELECT * holt alle Spalten%s; neue Spalten ändern still die Datenmenge.';
     En: 'SELECT * fetches all columns%s; new columns silently change the dataset.'),
    (De: 'SELECT %s.* holt alle Spalten von %0:s%s; neue Spalten ändern still die Datenmenge.';
     En: 'SELECT %s.* fetches all columns of %0:s%s; new columns silently change the dataset.'),
    (De: '* durch die persistenten Felder ersetzen'; En: 'Replace * with the persistent fields'),
    (De: 'von %s'; En: 'of %s'));

{$SCOPEDENUMS OFF}

const
  Hole = cSqlHole;
  // Open(SQL) gibt es bei FireDAC (TFDQuery, TFDConnection).
  SqlCalls: array[0..4] of string = ('ExecSQL', 'ExecSQLScalar', 'ExecuteDirect', 'Execute', 'Open');
  // Zugriffe auf einen Empfänger, die seinen SQL-Text nicht ändern.
  HarmlessMembers: array[0..3] of string = ('Text', 'Count', 'BeginUpdate', 'EndUpdate');
  QuoteChars: array[0..3] of string = ('"', '[', ']', '`');

type
{$SCOPEDENUMS ON}
  TCarrier = (None, Assign, Append, Clear, Execute);
{$SCOPEDENUMS OFF}

{ TSqlBuild }

type
  TSqlPiece = record
    /// <summary>Ab hier im Text (1-basiert) stammt der Text aus Token.</summary>
    Offset: Integer;
    Token: Integer;
    /// <summary>Der Text stammt unverändert aus dem Literal Token (nicht aus einer Konstanten).</summary>
    Direct: Boolean;
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
    /// <summary>Text eines String-Literals, das an der Stelle AToken steht.</summary>
    procedure AddLiteral(const AText: string; AToken: Integer);
    procedure AddHole(AToken: Integer);
    /// <summary>Text von ABuild anhängen; AToken &lt; 0 übernimmt dessen Stücke, sonst zählt alles zu AToken.</summary>
    procedure AddBuild(ABuild: TSqlBuild; AToken: Integer);
    procedure NewLine;
    function TokenAt(AOffset: Integer): Integer;
    /// <summary>Stück, aus dem AOffset stammt; False ohne.</summary>
    function PieceAt(AOffset: Integer; out APiece: TSqlPiece): Boolean;
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
  begin
    Exit;
  end;
  Piece.Offset := Length(Text) + 1;
  Piece.Token := AToken;
  Piece.Direct := False;
  Pieces := Pieces + [Piece];
  Text := Text + AText;
end;

procedure TSqlBuild.AddLiteral(const AText: string; AToken: Integer);
begin
  AddText(AText, AToken);
  if AText <> '' then
  begin
    Pieces[High(Pieces)].Direct := True;
  end;
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
  begin
    Unknown := True;
  end;
  if AToken >= 0 then
  begin
    AddText(ABuild.Text, AToken);
    Exit;
  end;
  for Piece in ABuild.Pieces do
  begin
    Pieces := Pieces + [Piece];
  end;
  for Index := Length(Pieces) - Length(ABuild.Pieces) to High(Pieces) do
  begin
    Inc(Pieces[Index].Offset, Length(Text));
  end;
  Text := Text + ABuild.Text;
end;

procedure TSqlBuild.NewLine;
begin
  if Text <> '' then
  begin
    Text := Text + #13#10;
  end;
end;

function TSqlBuild.TokenAt(AOffset: Integer): Integer;
var
  Piece: TSqlPiece;
begin
  Result := -1;
  for Piece in Pieces do
  begin
    if (Piece.Offset <= AOffset) or (Result < 0) then
    begin
      Result := Piece.Token;
    end;
  end;
end;

function TSqlBuild.PieceAt(AOffset: Integer; out APiece: TSqlPiece): Boolean;
var
  Piece: TSqlPiece;
begin
  Result := False;
  APiece := Default(TSqlPiece);
  for Piece in Pieces do
  begin
    if Piece.Offset <= AOffset then
    begin
      APiece := Piece;
      Result := True;
    end;
  end;
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

  /// <summary>Stelle in einem SQL-Text, die eine Regel meldet.</summary>
  TSqlHit = record
    /// <summary>Stelle im SQL-Text (1-basiert).</summary>
    Offset: Integer;
    Message: string;
    Confidence: TRuleConfidence;
  end;

  /// <summary>Meldet die Stellen eines SQL-Texts; AStrictCase wie bei TSqlWriteWithoutWhereRule.Writes.
  /// ASuffix ergänzt die Meldung um die Herkunft, z. B. " (qry.SQL in der Formulardatei)".</summary>
  TSqlFinder = reference to function(const ASql: string; AStrictCase: Boolean; const ASuffix: string):
    TArray<TSqlHit>;

  TSqlFound = record
    Range: TTextRange;
    Message: string;
    Confidence: TRuleConfidence;
    /// <summary>Empfänger in Kleinbuchstaben; '' bei einzelnen Ausdrücken.</summary>
    Key: string;
    Segment: Integer;
    /// <summary>Token, an dem die Meldung steht.</summary>
    Token: Integer;
    /// <summary>Stelle im Klartext des Literals Token (1-basiert); 0, wenn die Stelle aus einer Konstanten
    /// oder einem lokalen Wert stammt.</summary>
    LiteralOffset: Integer;
  end;

  /// <summary>Korrekturen zu einem Fund; nil ohne.</summary>
  TSqlFixer = reference to function(const AFound: TSqlFound): TArray<TRuleFix>;

  /// <summary>SQL-Text aus Pascal-Ausdrücken: Literale, Verkettung, Format/Concat, Konstanten, lokale Werte und
  /// Empfänger; alles andere ist ein unbekannter Teil.</summary>
  TSqlExpressions = class
  protected
    FTokens: TArray<TPascalToken>;
    FConstants: TObjectDictionary<string, TNamedValue>;
    FLocals: TObjectDictionary<string, TNamedValue>;
    FReceivers: TObjectDictionary<string, TSqlBuild>;
    FReceiverRead: string;
    function IsChainStart(AIndex: Integer): Boolean;
    function Chain(AIndex: Integer; out ALast: Integer): string;
    function MatchingClose(AOpen: Integer): Integer;
    function ExpressionEnd(AFirst: Integer): Integer;
    function StartsLiteral(AIndex: Integer): Boolean;
    procedure Evaluate(AFirst, ALast: Integer; ABuild: TSqlBuild);
  private
    procedure AddLiteral(AIndex: Integer; ABuild: TSqlBuild);
    function EvaluateCall(const AName: string; ALast: Integer; ABuild: TSqlBuild): Integer;
    function AddReceiver(const AName: string; ABuild: TSqlBuild): Boolean;
    procedure EvaluateName(const AName: string; AIndex, ALast: Integer; ABuild: TSqlBuild);
    function EvaluateIdentifier(AIndex, ALast: Integer; ABuild: TSqlBuild): Integer;
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    property Tokens: TArray<TPascalToken> read FTokens;
  end;

  /// <summary>Ein Lauf der Regel über die Token einer Unit.</summary>
  TSqlScan = class(TSqlExpressions)
  private
    FFinder: TSqlFinder;
    FConsumed: TArray<Boolean>;
    FSegments: TArray<Integer>;
    FKeys: TDictionary<string, Boolean>;
    /// <summary>Segmente, in denen ein Empfänger ergänzt oder weitergegeben wird.</summary>
    FTouched: TObjectDictionary<string, TList<Integer>>;
    FFound: TList<TSqlFound>;
    FSegment: Integer;
    function Carrier(AIndex: Integer; out AKey: string; out ALast: Integer): TCarrier;
    function ChangesReceiver(const AChain, AKey: string): Boolean;
    procedure Consume(AFirst, ALast: Integer);
    procedure Finish(ABuild: TSqlBuild; const AKey: string);
    procedure FinishNamed(AValues: TObjectDictionary<string, TNamedValue>; AFirst, ALast: Integer);
    procedure FinishSegment(AFirst, ALast: Integer);
    procedure Touch(const AKey: string; ASegment: Integer);
    procedure ComputeSegments;
    function CollectConstant(AIndex: Integer): Integer;
    procedure CollectConstants;
    procedure TouchReceivers(AIndex: Integer);
    procedure CollectKeys;
    function ScanAssign(const AKey: string; ALast: Integer): Integer;
    function ScanAppend(const AKey: string; ALast: Integer): Integer;
    function ScanClear(const AKey: string; ALast: Integer): Integer;
    function ScanExecute(ALast: Integer): Integer;
    function ScanLocal(AIndex, ALast: Integer; out ANext: Integer): Boolean;
    function MarkChanged(AIndex: Integer): Integer;
    function ScanChain(AIndex: Integer): Integer;
    function StartsLooseLiteral(AIndex: Integer): Boolean;
    function ScanLiteral(AIndex: Integer): Integer;
    procedure Scan;
    function TouchedElsewhere(const AFound: TSqlFound): Boolean;
  public
    constructor Create(const ATokens: TArray<TPascalToken>; const AFinder: TSqlFinder);
    destructor Destroy; override;
    procedure Run;
    /// <summary>Meldet die Funde; AFixer liefert ihre Korrekturen (nil: keine).</summary>
    procedure Report(const AReport: IRuleReport; const AFixer: TSqlFixer);
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
  begin
    Table := cTexts[TDatabaseText.OfTable].Text;
  end
  else
  begin
    Table := cTexts[TDatabaseText.OfNamedTable].Fmt([AWrite.Table]);
  end;
  if AWrite.Kind = 'DELETE' then
  begin
    Result := cTexts[TDatabaseText.DeleteAll].Fmt([Table, ASuffix]);
  end
  else
  begin
    Result := cTexts[TDatabaseText.UpdateAll].Fmt([Table, ASuffix]);
  end;
end;

function WriteConfidence(const AWrite: TSqlWrite): TRuleConfidence;
begin
  if AWrite.Table = '' then
  begin
    Result := TRuleConfidence.Medium;
  end
  else
  begin
    Result := TRuleConfidence.High;
  end;
end;

/// <summary>Formatangabe ab AStart (dem %) in AText durch einen unbekannten Teil ersetzen; AIndex steht danach
/// auf ihrem letzten Zeichen. %% wird zu einem Leerzeichen.</summary>
procedure MarkFormatSpec(var AText: string; AStart: Integer; out AIndex: Integer);
var
  mBlank: Integer;
begin
  AIndex := AStart + 1;
  if AText[AIndex] = '%' then
  begin
    AText[AIndex] := ' ';
    Exit;
  end;
  while (AIndex < Length(AText)) and CharInSet(AText[AIndex], ['0'..'9', ':', '-', '.', '*']) do
  begin
    Inc(AIndex);
  end;
  AText[AStart] := Hole;
  for mBlank := AStart + 1 to AIndex do
  begin
    AText[mBlank] := ' ';
  end;
end;

/// <summary>Formatangaben (%s, %0:d) als unbekannte Teile; die Länge bleibt gleich.</summary>
function FormatHoles(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  mIndex := 1;
  while mIndex < Length(Result) do
  begin
    if Result[mIndex] = '%' then
    begin
      MarkFormatSpec(Result, mIndex, mIndex);
    end;
    Inc(mIndex);
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

{ TSqlExpressions }

constructor TSqlExpressions.Create(const ATokens: TArray<TPascalToken>);
begin
  inherited Create;
  FTokens := ATokens;
  FConstants := TObjectDictionary<string, TNamedValue>.Create([doOwnsValues]);
  FLocals := TObjectDictionary<string, TNamedValue>.Create([doOwnsValues]);
  FReceivers := TObjectDictionary<string, TSqlBuild>.Create([doOwnsValues]);
end;

destructor TSqlExpressions.Destroy;
begin
  FReceivers.Free;
  FLocals.Free;
  FConstants.Free;
  inherited Destroy;
end;

function TSqlExpressions.IsChainStart(AIndex: Integer): Boolean;
begin
  Result := (FTokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    ((AIndex = 0) or not FTokens[AIndex - 1].IsSymbol('.'));
end;

function TSqlExpressions.Chain(AIndex: Integer; out ALast: Integer): string;
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

{ TSqlScan }

constructor TSqlScan.Create(const ATokens: TArray<TPascalToken>; const AFinder: TSqlFinder);
begin
  inherited Create(ATokens);
  FFinder := AFinder;
  SetLength(FConsumed, Length(FTokens));
  FKeys := TDictionary<string, Boolean>.Create;
  FTouched := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  FFound := TList<TSqlFound>.Create;
end;

destructor TSqlScan.Destroy;
begin
  FFound.Free;
  FTouched.Free;
  FKeys.Free;
  inherited Destroy;
end;

function TSqlScan.Carrier(AIndex: Integer; out AKey: string; out ALast: Integer): TCarrier;
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
  begin
    Exit;
  end;
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
  begin
    Result := TCarrier.Execute;
  end;
  AKey := LowerCase(AKey);
end;

function TSqlExpressions.MatchingClose(AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to High(FTokens) do
  begin
    if FTokens[Result].IsSymbol('(') or FTokens[Result].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if FTokens[Result].IsSymbol(')') or FTokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit;
      end;
    end;
  end;
  Result := High(FTokens);
end;

function TSqlExpressions.ExpressionEnd(AFirst: Integer): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  Index := AFirst;
  while Index <= High(FTokens) do
  begin
    Token := FTokens[Index];
    if Token.IsSymbol('(') or Token.IsSymbol('[') then
    begin
      Index := MatchingClose(Index);
    end
    else if (Token.Kind = TPascalTokenKind.Keyword) or
      ((Token.Kind = TPascalTokenKind.Symbol) and not Token.IsSymbol('+') and not Token.IsSymbol('.')) then
    begin
      Break;
    end;
    Inc(Index);
  end;
  Result := Index - 1;
end;

function TSqlExpressions.StartsLiteral(AIndex: Integer): Boolean;
begin
  Result := (AIndex <= High(FTokens)) and ((FTokens[AIndex].Kind in [TPascalTokenKind.StringLiteral,
    TPascalTokenKind.CharLiteral]) or ((AIndex < High(FTokens)) and MatchText(FTokens[AIndex].Text,
    ['Format', 'Concat']) and FTokens[AIndex + 1].IsSymbol('(')));
end;

function TSqlScan.ChangesReceiver(const AChain, AKey: string): Boolean;
var
  Rest: string;
begin
  if SameText(AChain, AKey) then
  begin
    // Die Eigenschaft CommandText selbst lesen ändert nichts; X.SQL weitergeben schon.
    Exit(not EndsText('commandtext', AKey));
  end;
  if not StartsText(AKey + '.', AChain) then
  begin
    Exit(False);
  end;
  Rest := Copy(AChain, Length(AKey) + 2, MaxInt);
  if Pos('.', Rest) > 0 then
  begin
    Rest := Copy(Rest, 1, Pos('.', Rest) - 1);
  end;
  Result := not MatchText(Rest, HarmlessMembers);
end;

procedure TSqlScan.Consume(AFirst, ALast: Integer);
var
  Index: Integer;
begin
  for Index := AFirst to ALast do
  begin
    FConsumed[Index] := True;
  end;
end;

procedure TSqlExpressions.AddLiteral(AIndex: Integer; ABuild: TSqlBuild);
var
  mPlain: string;
begin
  if TStringLiterals.PlainText(FTokens[AIndex].Text, mPlain) then
  begin
    ABuild.AddLiteral(mPlain, AIndex);
  end
  else
  begin
    ABuild.AddHole(AIndex);
  end;
end;

/// <summary>Format(…) oder Concat(…) ab dem Namen bis ALast; liefert die schließende Klammer.</summary>
function TSqlExpressions.EvaluateCall(const AName: string; ALast: Integer; ABuild: TSqlBuild): Integer;
var
  mStart: Integer;
  mInner: TSqlBuild;
begin
  Result := MatchingClose(ALast + 1);
  mInner := TSqlBuild.Create(ABuild.SqlContext);
  try
    mStart := ALast + 2;
    if SameText(AName, 'Format') then
    begin
      Evaluate(mStart, ExpressionEnd(mStart), mInner);
      mInner.Text := FormatHoles(mInner.Text);
    end
    else
    begin
      while mStart < Result do
      begin
        Evaluate(mStart, ExpressionEnd(mStart), mInner);
        mStart := ExpressionEnd(mStart) + 2;
      end;
    end;
    ABuild.AddBuild(mInner, -1);
  finally
    mInner.Free;
  end;
end;

/// <summary>Aktueller Wert des Namens AName in AValues; False ohne oder nach einer Zuweisung ohne Literal.</summary>
function CurrentValue(AValues: TObjectDictionary<string, TNamedValue>; const AName: string;
  out ABuild: TSqlBuild): Boolean;
var
  mValue: TNamedValue;
begin
  ABuild := nil;
  if AValues.TryGetValue(LowerCase(AName), mValue) then
  begin
    ABuild := mValue.Current;
  end;
  Result := ABuild <> nil;
end;

/// <summary>Liest AName den Text eines Empfängers (X.SQL.Text, X.CommandText)? Dann dessen Text anhängen.</summary>
function TSqlExpressions.AddReceiver(const AName: string; ABuild: TSqlBuild): Boolean;
var
  mReceiver: TPair<string, TSqlBuild>;
  mKey: string;
begin
  Result := False;
  for mReceiver in FReceivers do
  begin
    mKey := mReceiver.Key;
    if SameText(AName, mKey + '.Text') or (EndsText('commandtext', mKey) and SameText(AName, mKey)) then
    begin
      ABuild.AddBuild(mReceiver.Value, -1);
      FReceiverRead := mKey;
      Exit(True);
    end;
  end;
end;

/// <summary>Name AName von AIndex bis ALast: Wert einer lokalen Variablen, einer Konstanten oder eines
/// Empfängers, sonst ein unbekannter Teil.</summary>
procedure TSqlExpressions.EvaluateName(const AName: string; AIndex, ALast: Integer; ABuild: TSqlBuild);
var
  mValue: TSqlBuild;
begin
  if (ALast = AIndex) and (CurrentValue(FLocals, AName, mValue) or CurrentValue(FConstants, AName, mValue)) then
  begin
    ABuild.AddBuild(mValue, AIndex);
  end
  else if not AddReceiver(AName, ABuild) then
  begin
    ABuild.AddHole(AIndex);
  end;
end;

/// <summary>Bezeichner ab AIndex (bis höchstens ALast); liefert das letzte verarbeitete Token.</summary>
function TSqlExpressions.EvaluateIdentifier(AIndex, ALast: Integer; ABuild: TSqlBuild): Integer;
var
  mName: string;
  mLast: Integer;
begin
  mName := Chain(AIndex, mLast);
  Result := mLast;
  if (mLast < ALast) and FTokens[mLast + 1].IsSymbol('(') and MatchText(mName, ['Format', 'Concat']) then
  begin
    Result := EvaluateCall(mName, mLast, ABuild);
  end
  else if (mLast < ALast) and (FTokens[mLast + 1].IsSymbol('(') or FTokens[mLast + 1].IsSymbol('[')) then
  begin
    ABuild.AddHole(AIndex);
    Result := MatchingClose(mLast + 1);
  end
  else if SameText(mName, 'sLineBreak') then
  begin
    ABuild.AddText(#13#10, AIndex);
  end
  else
  begin
    EvaluateName(mName, AIndex, mLast, ABuild);
  end;
end;

procedure TSqlExpressions.Evaluate(AFirst, ALast: Integer; ABuild: TSqlBuild);
var
  mIndex: Integer;
begin
  mIndex := AFirst;
  while mIndex <= ALast do
  begin
    if FTokens[mIndex].Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral] then
    begin
      AddLiteral(mIndex, ABuild);
    end
    else if FTokens[mIndex].IsSymbol('(') or FTokens[mIndex].IsSymbol('[') then
    begin
      ABuild.AddHole(mIndex);
      mIndex := MatchingClose(mIndex);
    end
    else if FTokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      mIndex := EvaluateIdentifier(mIndex, ALast, ABuild);
    end
    else if not FTokens[mIndex].IsSymbol('+') then
    begin
      // + verkettet, alles andere ist unbekannt.
      ABuild.AddHole(mIndex);
    end;
    Inc(mIndex);
  end;
end;

procedure TSqlScan.Finish(ABuild: TSqlBuild; const AKey: string);
var
  Hit: TSqlHit;
  Found: TSqlFound;
  Token: Integer;
  Piece: TSqlPiece;
begin
  if ABuild.Unknown then
  begin
    Exit;
  end;
  for Hit in FFinder(ABuild.Text, not ABuild.SqlContext, '') do
  begin
    Token := ABuild.TokenAt(Hit.Offset);
    if Token < 0 then
    begin
      Continue;
    end;
    Found.Range := TTextRange.Create(FTokens[Token].StartPos, FTokens[Token].EndPos);
    Found.Message := Hit.Message;
    Found.Confidence := Hit.Confidence;
    Found.Key := AKey;
    Found.Segment := FSegment;
    Found.Token := Token;
    Found.LiteralOffset := 0;
    if ABuild.PieceAt(Hit.Offset, Piece) and Piece.Direct and (Piece.Token = Token) then
    begin
      Found.LiteralOffset := Hit.Offset - Piece.Offset + 1;
    end;
    FFound.Add(Found);
  end;
end;

procedure TSqlScan.FinishNamed(AValues: TObjectDictionary<string, TNamedValue>; AFirst, ALast: Integer);
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
    begin
      if IsChainStart(Index) and SameText(FTokens[Index].Text, Pair.Key) and
        not Pair.Value.Definitions.Contains(Index) then
      begin
        Used := True;
        Break;
      end;
    end;
    if not Used then
    begin
      for Build in Pair.Value.Builds do
      begin
        Finish(Build, '');
      end;
    end;
  end;
end;

procedure TSqlScan.FinishSegment(AFirst, ALast: Integer);
var
  Pair: TPair<string, TSqlBuild>;
begin
  for Pair in FReceivers do
  begin
    Finish(Pair.Value, Pair.Key);
  end;
  FReceivers.Clear;
  FinishNamed(FLocals, AFirst, ALast);
  FLocals.Clear;
end;

procedure TSqlScan.Touch(const AKey: string; ASegment: Integer);
var
  Segments: TList<Integer>;
begin
  if not FTouched.TryGetValue(AKey, Segments) then
  begin
    Segments := TList<Integer>.Create;
    FTouched.Add(AKey, Segments);
  end;
  if not Segments.Contains(ASegment) then
  begin
    Segments.Add(ASegment);
  end;
end;

function IsSymbolIn(const AToken: TPascalToken; const ASymbols: array of string): Boolean;
var
  mSymbol: string;
begin
  Result := False;
  for mSymbol in ASymbols do
  begin
    Result := Result or AToken.IsSymbol(mSymbol);
  end;
end;

function IsKeywordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Keyword) and MatchText(AToken.Text, AWords);
end;

/// <summary>Beginnt ATokens[AIndex] ein neues Segment: eine Routine (keine anonyme Methode) oder einen
/// Abschnitt wie implementation?</summary>
function StartsSegment(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := IsKeywordIn(ATokens[AIndex], ['procedure', 'function', 'constructor', 'destructor', 'implementation',
    'initialization', 'finalization']) and not ((AIndex > 0) and (IsSymbolIn(ATokens[AIndex - 1],
    [':=', '(', ',', '=', ':']) or IsKeywordIn(ATokens[AIndex - 1], ['to', 'of'])));
end;

procedure TSqlScan.ComputeSegments;
var
  mIndex, mSegment: Integer;
begin
  // Jede Routine (und jeder Abschnitt wie implementation) ist ein Segment; anonyme Methoden nicht.
  SetLength(FSegments, Length(FTokens));
  mSegment := 0;
  for mIndex := 0 to High(FTokens) do
  begin
    if StartsSegment(FTokens, mIndex) then
    begin
      Inc(mSegment);
    end;
    FSegments[mIndex] := mSegment;
  end;
end;

/// <summary>Konstante ab dem Namen AIndex mit einem Literal als Wert merken; liefert das letzte verarbeitete
/// Token.</summary>
function TSqlScan.CollectConstant(AIndex: Integer): Integer;
var
  mFirst: Integer;
  mValue: TNamedValue;
  mBuild: TSqlBuild;
begin
  Result := AIndex;
  mFirst := AIndex + 1;
  while (mFirst <= High(FTokens)) and not FTokens[mFirst].IsSymbol('=') and not FTokens[mFirst].IsSymbol(';') do
  begin
    Inc(mFirst);
  end;
  Inc(mFirst);
  if not StartsLiteral(mFirst) then
  begin
    Exit;
  end;
  Result := ExpressionEnd(mFirst);
  mBuild := TSqlBuild.Create(False);
  Evaluate(mFirst, Result, mBuild);
  if not FConstants.TryGetValue(LowerCase(FTokens[AIndex].Text), mValue) then
  begin
    mValue := TNamedValue.Create;
    FConstants.Add(LowerCase(FTokens[AIndex].Text), mValue);
  end;
  mValue.Assign(mBuild, AIndex);
  Consume(mFirst, Result);
end;

procedure TSqlScan.CollectConstants;
var
  mIndex, mDepth: Integer;
  mInConst: Boolean;
begin
  mInConst := False;
  mDepth := 0;
  mIndex := 0;
  while mIndex < High(FTokens) do
  begin
    if IsSymbolIn(FTokens[mIndex], ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if IsSymbolIn(FTokens[mIndex], [')', ']']) then
    begin
      Dec(mDepth);
    end
    else if mDepth > 0 then
      // "const" in Parameterlisten ist kein Konstantenabschnitt.
    else if IsKeywordIn(FTokens[mIndex], ['const', 'resourcestring']) then
    begin
      mInConst := True;
    end
    else if IsKeywordIn(FTokens[mIndex], ['var', 'type', 'begin', 'procedure', 'function', 'implementation']) then
    begin
      mInConst := False;
    end
    else if mInConst and IsChainStart(mIndex) and IsSymbolIn(FTokens[mIndex + 1], ['=', ':']) then
    begin
      mIndex := CollectConstant(mIndex);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Ergänzt oder gibt die Kette ab AIndex einen Empfänger weiter? Dann gilt er in diesem Segment als
/// berührt.</summary>
procedure TSqlScan.TouchReceivers(AIndex: Integer);
var
  mKey, mFull: string;
  mLast: Integer;
  mPair: TPair<string, Boolean>;
begin
  case Carrier(AIndex, mKey, mLast) of
    TCarrier.Append:
      Touch(mKey, FSegments[AIndex]);
    TCarrier.None:
      begin
        mFull := Chain(AIndex, mLast);
        for mPair in FKeys do
        begin
          if ChangesReceiver(mFull, mPair.Key) then
          begin
            Touch(mPair.Key, FSegments[AIndex]);
          end;
        end;
      end;
  end;
end;

procedure TSqlScan.CollectKeys;
var
  mIndex, mLast: Integer;
  mKey: string;
begin
  for mIndex := 0 to High(FTokens) do
  begin
    if IsChainStart(mIndex) and (Carrier(mIndex, mKey, mLast) in [TCarrier.Assign, TCarrier.Append,
      TCarrier.Clear]) then
    begin
      FKeys.AddOrSetValue(mKey, True);
    end;
  end;
  // Ergänzt oder weitergegeben: gilt in den anderen Routinen als unbekannt.
  for mIndex := 0 to High(FTokens) do
  begin
    if IsChainStart(mIndex) then
    begin
      TouchReceivers(mIndex);
    end;
  end;
end;

/// <summary>Empfänger.SQL.Text := … bzw. CommandText := …; liefert das nächste Token.</summary>
function TSqlScan.ScanAssign(const AKey: string; ALast: Integer): Integer;
var
  mFirst, mClose: Integer;
  mBuild, mOld: TSqlBuild;
begin
  mFirst := ALast + 2;
  mClose := ExpressionEnd(mFirst);
  mBuild := TSqlBuild.Create(IsSqlKey(AKey));
  FReceiverRead := '';
  Evaluate(mFirst, mClose, mBuild);
  if FReceivers.TryGetValue(AKey, mOld) and (FReceiverRead <> AKey) then
  begin
    Finish(mOld, AKey);
  end;
  FReceivers.AddOrSetValue(AKey, mBuild);
  Consume(mFirst, mClose);
  Result := mClose + 1;
end;

/// <summary>Empfänger.SQL.Add(…); liefert das nächste Token.</summary>
function TSqlScan.ScanAppend(const AKey: string; ALast: Integer): Integer;
var
  mClose: Integer;
  mBuild, mLine: TSqlBuild;
begin
  mClose := MatchingClose(ALast + 1);
  if not FReceivers.TryGetValue(AKey, mBuild) then
  begin
    mBuild := TSqlBuild.Create(IsSqlKey(AKey));
    FReceivers.Add(AKey, mBuild);
  end;
  if ExpressionEnd(ALast + 2) = mClose - 1 then
  begin
    mLine := TSqlBuild.Create(mBuild.SqlContext);
    try
      Evaluate(ALast + 2, mClose - 1, mLine);
      mBuild.NewLine;
      mBuild.AddBuild(mLine, -1);
    finally
      mLine.Free;
    end;
  end
  else
  begin
    mBuild.Unknown := True;
  end;
  Consume(ALast + 1, mClose);
  Result := mClose + 1;
end;

/// <summary>Empfänger.SQL.Clear; liefert das nächste Token.</summary>
function TSqlScan.ScanClear(const AKey: string; ALast: Integer): Integer;
var
  mOld: TSqlBuild;
begin
  if FReceivers.TryGetValue(AKey, mOld) then
  begin
    Finish(mOld, AKey);
    FReceivers.Remove(AKey);
  end;
  Result := ALast + 1;
end;

/// <summary>ExecSQL(…), Open(…) und Verwandte mit SQL-Text; liefert das nächste Token.</summary>
function TSqlScan.ScanExecute(ALast: Integer): Integer;
var
  mClose, mFirst: Integer;
  mBuild: TSqlBuild;
begin
  mClose := MatchingClose(ALast + 1);
  mFirst := ALast + 2;
  if mFirst < mClose then
  begin
    mBuild := TSqlBuild.Create(True);
    try
      Evaluate(mFirst, ExpressionEnd(mFirst), mBuild);
      Finish(mBuild, '');
    finally
      mBuild.Free;
    end;
  end;
  Consume(ALast + 1, mClose);
  Result := mClose + 1;
end;

/// <summary>Zuweisung an eine lokale Variable ab AIndex: mit Literal gemerkt (ANext ist das nächste Token),
/// sonst ist ihr Wert unbekannt.</summary>
function TSqlScan.ScanLocal(AIndex, ALast: Integer; out ANext: Integer): Boolean;
var
  mFirst, mClose: Integer;
  mName: string;
  mValue: TNamedValue;
  mBuild: TSqlBuild;
begin
  Result := False;
  ANext := AIndex;
  if (ALast <> AIndex) or (AIndex >= High(FTokens)) or not FTokens[AIndex + 1].IsSymbol(':=') then
  begin
    Exit;
  end;
  mName := LowerCase(FTokens[AIndex].Text);
  mFirst := AIndex + 2;
  Result := StartsLiteral(mFirst);
  if FLocals.TryGetValue(mName, mValue) and not Result then
  begin
    mValue.Current := nil;
  end;
  if not Result then
  begin
    Exit;
  end;
  mClose := ExpressionEnd(mFirst);
  mBuild := TSqlBuild.Create(False);
  Evaluate(mFirst, mClose, mBuild);
  if not FLocals.TryGetValue(mName, mValue) then
  begin
    mValue := TNamedValue.Create;
    FLocals.Add(mName, mValue);
  end;
  mValue.Assign(mBuild, AIndex);
  Consume(mFirst, mClose);
  ANext := mClose + 1;
end;

/// <summary>Kette ab AIndex, die Empfänger verändern kann (weitergeben, Eigenschaften setzen): diese gelten als
/// unbekannt. Liefert das nächste Token.</summary>
function TSqlScan.MarkChanged(AIndex: Integer): Integer;
var
  mKey: string;
  mLast: Integer;
  mPair: TPair<string, TSqlBuild>;
begin
  mKey := Chain(AIndex, mLast);
  for mPair in FReceivers do
  begin
    if ChangesReceiver(mKey, mPair.Key) then
    begin
      mPair.Value.Unknown := True;
    end;
  end;
  Result := mLast + 1;
end;

/// <summary>Kette ab AIndex; liefert das nächste Token.</summary>
function TSqlScan.ScanChain(AIndex: Integer): Integer;
var
  mKey: string;
  mLast: Integer;
begin
  Result := -1;
  case Carrier(AIndex, mKey, mLast) of
    TCarrier.Assign:
      Result := ScanAssign(mKey, mLast);
    TCarrier.Append:
      Result := ScanAppend(mKey, mLast);
    TCarrier.Clear:
      Result := ScanClear(mKey, mLast);
    TCarrier.Execute:
      Result := ScanExecute(mLast);
  end;
  if (Result < 0) and not ScanLocal(AIndex, mLast, Result) then
  begin
    Result := MarkChanged(AIndex);
  end;
end;

/// <summary>Ein Literal, das nicht hinter + steht: Anfang eines einzelnen Ausdrucks.</summary>
function TSqlScan.StartsLooseLiteral(AIndex: Integer): Boolean;
begin
  Result := (FTokens[AIndex].Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) and
    not ((AIndex > 0) and FTokens[AIndex - 1].IsSymbol('+'));
end;

/// <summary>Einzelner Ausdruck ab dem Literal AIndex; liefert das nächste Token.</summary>
function TSqlScan.ScanLiteral(AIndex: Integer): Integer;
var
  mClose: Integer;
  mBuild: TSqlBuild;
begin
  mClose := ExpressionEnd(AIndex);
  mBuild := TSqlBuild.Create(False);
  try
    Evaluate(AIndex, mClose, mBuild);
    Finish(mBuild, '');
  finally
    mBuild.Free;
  end;
  Consume(AIndex, mClose);
  Result := mClose + 1;
end;

procedure TSqlScan.Scan;
var
  mIndex, mSegmentStart: Integer;
begin
  mSegmentStart := 0;
  FSegment := 0;
  mIndex := 0;
  while mIndex <= High(FTokens) do
  begin
    if FSegments[mIndex] <> FSegment then
    begin
      FinishSegment(mSegmentStart, mIndex - 1);
      mSegmentStart := mIndex;
      FSegment := FSegments[mIndex];
    end;
    if FConsumed[mIndex] then
    begin
      Inc(mIndex);
    end
    else if IsChainStart(mIndex) then
    begin
      mIndex := ScanChain(mIndex);
    end
    else if StartsLooseLiteral(mIndex) then
    begin
      mIndex := ScanLiteral(mIndex);
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
  FinishSegment(mSegmentStart, High(FTokens));
  FinishNamed(FConstants, 0, High(FTokens));
end;

procedure TSqlScan.Run;
begin
  if Length(FTokens) = 0 then
  begin
    Exit;
  end;
  ComputeSegments;
  CollectConstants;
  CollectKeys;
  Scan;
end;

/// <summary>Wird der Empfänger des Funds in einem anderen Segment ergänzt oder weitergegeben?</summary>
function TSqlScan.TouchedElsewhere(const AFound: TSqlFound): Boolean;
var
  mSegments: TList<Integer>;
  mSegment: Integer;
begin
  Result := False;
  if (AFound.Key <> '') and FTouched.TryGetValue(AFound.Key, mSegments) then
  begin
    for mSegment in mSegments do
    begin
      Result := Result or (mSegment <> AFound.Segment);
    end;
  end;
end;

procedure TSqlScan.Report(const AReport: IRuleReport; const AFixer: TSqlFixer);
var
  mFound: TSqlFound;
  mSeen: TDictionary<string, Boolean>;
  mId: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mFound in FFound do
    begin
      mId := Format('%d:%d:%s', [mFound.Range.StartPos.Line, mFound.Range.StartPos.Character, mFound.Message]);
      if TouchedElsewhere(mFound) or mSeen.ContainsKey(mId) then
      begin
        Continue;
      end;
      mSeen.Add(mId, True);
      if Assigned(AFixer) then
      begin
        AReport.Add(mFound.Range, mFound.Message, mFound.Confidence, AFixer(mFound));
      end
      else
      begin
        AReport.Add(mFound.Range, mFound.Message, mFound.Confidence);
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

{ TSqlWriteWithoutWhereRule }

function TSqlWriteWithoutWhereRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SqlWriteWithoutWhereRuleId, TRuleSeverity.Warning,
    cTexts[TDatabaseText.WhereTitle].Text);
end;

class function TSqlWriteWithoutWhereRule.Writes(const ASql: string; AStrictCase: Boolean): TArray<TSqlWrite>;
begin
  Result := SqlWrites(ASql, AStrictCase);
end;

class function TSqlWriteWithoutWhereRule.Allowed(const ATable: string; const AAllowed: TArray<string>): Boolean;
var
  Name, Last, Item: string;
begin
  Name := ATable;
  for Item in QuoteChars do
  begin
    Name := StringReplace(Name, Item, '', [rfReplaceAll]);
  end;
  Last := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  for Item in AAllowed do
  begin
    if SameText(Item, Name) or SameText(Item, Last) then
    begin
      Exit(True);
    end;
  end;
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
    begin
      Break;
    end;
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, AName) and
      ATokens[Index + 1].IsSymbol(':') then
    begin
      Exit(Index);
    end;
  end;
  for Index := 0 to High(ATokens) - 1 do
  begin
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, AFormClass) and
      ATokens[Index + 1].IsSymbol('=') then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

/// <summary>Verändert die Unit AName.AProperty selbst (Zuweisung, Add, Weitergabe)?</summary>
function SourceTouches(const ATokens: TArray<TPascalToken>; const APrefix: string): Boolean;
var
  Index, Last: Integer;
  Full: string;
begin
  for Index := 0 to High(ATokens) do
  begin
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
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function IsSqlProperty(const AName: string): Boolean;
begin
  Result := EndsText('SQL.Strings', AName) or SameText(AName, 'CommandText') or
    SameText(AName, 'CommandText.Strings');
end;

/// <summary>SQL-Eigenschaft AProp von AObject aus der Formulardatei prüfen, wenn die Unit sie nicht selbst
/// verändert; gemeldet am Feld bzw. am Formularklassennamen.</summary>
procedure CheckFormProperty(const ATokens: TArray<TPascalToken>; AObject: TDfmObject; const AProp: TDfmProperty;
  const AFormClass: string; const AFinder: TSqlFinder; const AReport: IRuleReport);
var
  mText, mRoot: string;
  mHit: TSqlHit;
  mAnchor: Integer;
begin
  if not IsSqlProperty(AProp.Name) or not TSqlText.FormValue(AProp.Value, mText) then
  begin
    Exit;
  end;
  mRoot := AProp.Name;
  if EndsText('.Strings', mRoot) then
  begin
    mRoot := Copy(mRoot, 1, Length(mRoot) - Length('.Strings'));
  end;
  if SourceTouches(ATokens, AObject.Name + '.' + mRoot) then
  begin
    Exit;
  end;
  for mHit in AFinder(mText, False, cTexts[TDatabaseText.InFormFile].Fmt([AObject.Name, mRoot])) do
  begin
    mAnchor := FormAnchor(ATokens, AObject.Name, AFormClass);
    if mAnchor >= 0 then
    begin
      AReport.Add(TTextRange.Create(ATokens[mAnchor].StartPos, ATokens[mAnchor].EndPos), mHit.Message,
        mHit.Confidence);
    end;
  end;
end;

procedure CheckForm(const ATokens: TArray<TPascalToken>; AObject: TDfmObject; const AFormClass: string;
  const AFinder: TSqlFinder; const AReport: IRuleReport);
var
  mProp: TDfmProperty;
  mChild: TDfmObject;
begin
  if AObject.Name <> '' then
  begin
    for mProp in AObject.Properties do
    begin
      CheckFormProperty(ATokens, AObject, mProp, AFormClass, AFinder, AReport);
    end;
  end;
  for mChild in AObject.Children do
  begin
    CheckForm(ATokens, mChild, AFormClass, AFinder, AReport);
  end;
end;

/// <summary>Läuft TSqlScan mit AFinder über die Unit und die Formulardatei.</summary>
procedure CheckSql(const AContext: TRuleContext; const AReport: IRuleReport; const AFinder: TSqlFinder;
  const AFixer: TSqlFixer);
var
  Tokens: TArray<TPascalToken>;
  Scan: TSqlScan;
  Document: TDfmDocument;
begin
  Tokens := TRuleDerived.CodeTokens(TRuleDerived.Open(AContext), AContext);
  Scan := TSqlScan.Create(Tokens, AFinder);
  try
    Scan.Run;
    Scan.Report(AReport, AFixer);
  finally
    Scan.Free;
  end;
  if AContext.FormText = '' then
  begin
    Exit;
  end;
  Document := TDfmParser.Parse(AContext.FormText);
  try
    if Document.Root <> nil then
    begin
      CheckForm(Tokens, Document.Root, Document.Root.TypeName, AFinder, AReport);
    end;
  finally
    Document.Free;
  end;
end;

procedure TSqlWriteWithoutWhereRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Allowed: TArray<string>;
  Finder: TSqlFinder;
begin
  Allowed := TRuleOptions.Strings(AContext.Options, 'allowTables', nil);
  Finder :=
    function(const ASql: string; AStrictCase: Boolean; const ASuffix: string): TArray<TSqlHit>
    var
      Write: TSqlWrite;
      Hit: TSqlHit;
    begin
      Result := nil;
      for Write in TSqlWriteWithoutWhereRule.Writes(ASql, AStrictCase) do
      begin
        if (Write.Table <> '') and TSqlWriteWithoutWhereRule.Allowed(Write.Table, Allowed) then
        begin
          Continue;
        end;
        Hit.Offset := Write.Offset;
        Hit.Message := WriteMessage(Write, ASuffix);
        Hit.Confidence := WriteConfidence(Write);
        Result := Result + [Hit];
      end;
    end;
  CheckSql(AContext, AReport, Finder, nil);
end;

{ TSqlSelectStarRule }

const
  // Feldarten, die nicht aus der Abfrage kommen (TFieldKind).
  ComputedFieldKinds: array[0..3] of string = ('fkCalculated', 'fkLookup', 'fkInternalCalc', 'fkAggregate');

function TSqlSelectStarRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SqlSelectStarRuleId, TRuleSeverity.Hint, cTexts[TDatabaseText.StarTitle].Text, True);
end;

class function TSqlSelectStarRule.Stars(const ASql: string; AStrictCase: Boolean): TArray<TSqlStar>;
begin
  Result := SqlStars(ASql, AStrictCase);
end;

/// <summary>Stelle (0-basiert ab Tokenanfang) des Zeichens APlain (1-basiert) im Klartext des einfachen
/// Literals ARaw; -1, wenn ARaw kein einfaches einzeiliges Literal ist.</summary>
function RawLiteralColumn(const ARaw: string; APlain: Integer): Integer;
var
  Index, Plain: Integer;
begin
  Result := -1;
  if (Length(ARaw) < 2) or (ARaw[1] <> '''') or (ARaw[Length(ARaw)] <> '''') or StartsStr('''''''', ARaw) then
  begin
    Exit;
  end;
  Index := 2;
  Plain := 1;
  while Index < Length(ARaw) do
  begin
    if Plain = APlain then
    begin
      Exit(Index - 1);
    end;
    if (ARaw[Index] = '''') and (ARaw[Index + 1] = '''') then
    begin
      Inc(Index, 2);
    end
    else
    begin
      Inc(Index);
    end;
    Inc(Plain);
  end;
end;

function FindDfmObject(AObject: TDfmObject; const AName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
  begin
    Exit(AObject);
  end;
  for Child in AObject.Children do
  begin
    Result := FindDfmObject(Child, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

/// <summary>FieldName der persistenten Felder von ADataSet, die aus der Abfrage kommen.</summary>
function PersistentFields(ADataSet: TDfmObject): TArray<string>;
var
  Child: TDfmObject;
  Prop: TDfmProperty;
  Name: string;
  Computed: Boolean;
begin
  Result := nil;
  for Child in ADataSet.Children do
  begin
    Name := '';
    Computed := False;
    for Prop in Child.Properties do
    begin
      if SameText(Prop.Name, 'FieldName') then
      begin
        Name := AnsiDequotedStr(Trim(Prop.Value), '''');
      end
      else if SameText(Prop.Name, 'FieldKind') and MatchText(Trim(Prop.Value), ComputedFieldKinds) then
      begin
        Computed := True;
      end;
    end;
    if (Name <> '') and not Computed then
    begin
      Result := Result + [Name];
    end;
  end;
end;

function StarMessage(const AStar: TSqlStar; const ASuffix: string): string;
begin
  if AStar.Qualifier = '' then
  begin
    Result := cTexts[TDatabaseText.AllColumns].Fmt([ASuffix]);
  end
  else
  begin
    Result := cTexts[TDatabaseText.AllColumnsOf].Fmt([AStar.Qualifier, ASuffix]);
  end;
end;

function SelectStarFinder: TSqlFinder;
begin
  Result :=
    function(const ASql: string; AStrictCase: Boolean; const ASuffix: string): TArray<TSqlHit>
    var
      mStar: TSqlStar;
      mHit: TSqlHit;
    begin
      Result := nil;
      for mStar in TSqlSelectStarRule.Stars(ASql, AStrictCase) do
      begin
        mHit.Offset := mStar.Offset;
        mHit.Message := StarMessage(mStar, ASuffix);
        mHit.Confidence := TRuleConfidence.High;
        Result := Result + [mHit];
      end;
    end;
end;

/// <summary>Spalte (0-basiert ab Tokenanfang) des Sterns von AFound in einem einzeiligen Literal; False, wenn
/// der Stern nicht unmittelbar aus einem Literal kommt.</summary>
function StarColumn(const ATokens: TArray<TPascalToken>; const AFound: TSqlFound; out AToken: TPascalToken;
  out AColumn: Integer): Boolean;
begin
  AColumn := -1;
  Result := AFound.LiteralOffset <> 0;
  if Result then
  begin
    AToken := ATokens[AFound.Token];
    AColumn := RawLiteralColumn(AToken.Text, AFound.LiteralOffset);
    Result := (AColumn >= 0) and (AToken.StartPos.Line = AToken.EndPos.Line) and (AToken.Text[AColumn + 1] = '*');
  end;
end;

/// <summary>Persistente Felder der Datenmenge zum Empfänger AKey (X.SQL) aus der Formulardatei; nil ohne.</summary>
function DataSetFields(ADocument: TDfmDocument; const AKey: string): TArray<string>;
var
  mName: string;
  mDataSet: TDfmObject;
begin
  Result := nil;
  if (ADocument = nil) or (ADocument.Root = nil) or not EndsText('.sql', AKey) then
  begin
    Exit;
  end;
  mName := Copy(AKey, 1, Length(AKey) - Length('.sql'));
  mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  mDataSet := FindDfmObject(ADocument.Root, mName);
  if mDataSet <> nil then
  begin
    Result := PersistentFields(mDataSet);
  end;
end;

/// <summary>„* durch die persistenten Felder ersetzen“: nur der Stern ohne Alias in einem einzeiligen Literal;
/// die Felder kommen aus der Formulardatei.</summary>
function StarFixes(ADocument: TDfmDocument; const ATokens: TArray<TPascalToken>;
  const AFound: TSqlFound): TArray<TRuleFix>;
var
  mFields: TArray<string>;
  mColumn: Integer;
  mToken: TPascalToken;
begin
  Result := nil;
  mFields := DataSetFields(ADocument, AFound.Key);
  if (mFields <> nil) and StarColumn(ATokens, AFound, mToken, mColumn) then
  begin
    Result := [TRuleFix.Create(cTexts[TDatabaseText.ReplaceStar].Text,
      [TRuleEdit.Create(TTextRange.Create(mToken.StartPos.Line, mToken.StartPos.Character + mColumn,
      mToken.StartPos.Line, mToken.StartPos.Character + mColumn + 1), string.Join(', ', mFields))])];
  end;
end;

function SelectStarFixer(ADocument: TDfmDocument; const ATokens: TArray<TPascalToken>): TSqlFixer;
begin
  Result :=
    function(const AFound: TSqlFound): TArray<TRuleFix>
    begin
      Result := StarFixes(ADocument, ATokens, AFound);
    end;
end;

procedure TSqlSelectStarRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mDocument: TDfmDocument;
begin
  mDocument := nil;
  if AContext.FormText <> '' then
  begin
    mDocument := TDfmParser.Parse(AContext.FormText);
  end;
  try
    CheckSql(AContext, AReport, SelectStarFinder(), SelectStarFixer(mDocument,
      TRuleDerived.CodeTokens(TRuleDerived.Open(AContext), AContext)));
  finally
    mDocument.Free;
  end;
end;

procedure RegisterDatabaseRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSqlWriteWithoutWhereRule.Create);
  ARegistry.Register(TSqlSelectStarRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Database', cTexts);

end.
