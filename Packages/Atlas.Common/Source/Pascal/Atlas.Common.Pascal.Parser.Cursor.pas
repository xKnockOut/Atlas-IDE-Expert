unit Atlas.Common.Pascal.Parser.Cursor;

// Grundlage des Parsers (Pascal.Parser): Token lesen, Knoten anlegen, Diagnosen
// sammeln und nach Fehlern wieder aufsetzen. Die Klassen darüber (Ausdrücke,
// Deklarationen, Typen, Anweisungen) erben davon; die Kette steht in
// Pascal.Parser.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Wo der Parser nach einem Fehler wieder aufsetzt.</summary>
  TRecovery = (Declarations, Members, Statements);

  /// <summary>Korrektur zu einer Diagnose: ATitle ersetzt den Bereich AStart..AEnd durch AText.</summary>
  TParserFix = record
    Title: string;
    Edits: TArray<TTextEdit>;
    /// <summary>Ohne Rückfrage anwendbar (source.fixAll).</summary>
    Safe: Boolean;
    class function Create(const ATitle: string; const AStart, AEnd: TTextPosition; const AText: string;
      ASafe: Boolean): TParserFix; static;
  end;

  /// <summary>Token des Texts und Knoten des Baums: Lesen, Vorausschauen, Knotenbereiche.</summary>
  TParserCursor = class
  protected
    FAllTokens: TArray<TPascalToken>;
    /// <summary>Nur bedeutungstragende Token, ohne Kommentare und Direktiven.</summary>
    FTokens: TArray<TPascalToken>;
    FIndex: Integer;
    /// <summary>Aktuelle Verschachtelungstiefe von Anweisungen, Typen und Ausdrücken.</summary>
    FDepth: Integer;
    FCancellation: IPascalCancellation;
    FAdvances: Integer;
    FDiagnostics: TList<TSyntaxDiagnostic>;
    FEndPos: TTextPosition;
    FEndOffset: Integer;
    /// <summary>Endwörter der innersten Anweisungsliste, für die Fehlerbehandlung.</summary>
    FTerminators: TArray<string>;
    /// <summary>Übersprungene Bereiche (inaktive Zweige); ihre Token erzeugen keine Diagnosen.</summary>
    FSkip: TArray<TTextRange>;
    function AtEnd: Boolean; inline;
    function Current: TPascalToken;
    function PeekToken(ADelta: Integer): TPascalToken;
    function IsKw(const AWord: string): Boolean; overload;
    function IsKw(const AWords: array of string): Boolean; overload;
    function IsSym(const ASymbol: string): Boolean;
    function IsIdent: Boolean;
    function IsIdentText(const AText: string): Boolean;
    function PeekIsSym(ADelta: Integer; const ASymbol: string): Boolean;
    function PeekIsKw(ADelta: Integer; const AWord: string): Boolean;
    procedure Advance;
    function AcceptKw(const AWord: string): Boolean;
    function AcceptSym(const ASymbol: string): Boolean;
    function StartNode(AKind: TSyntaxKind): TSyntaxNode;
    procedure FinishNode(ANode: TSyntaxNode; AStartIndex: Integer);
    function NodeStart: Integer; inline;
    function Leaf(AKind: TSyntaxKind; const AName: string): TSyntaxNode;
    /// <summary>Teilt das aktuelle Token ">=" in ">" und "=" (IBaz&lt;string&gt;=nil, #1142).</summary>
    procedure SplitGreaterEqual;
    /// <summary>^ mit direkt folgendem einzelnem Zeichen am Anfang eines Ausdrucks: Steuerzeichen wie ^C (#862).
    /// </summary>
    function IsControlChar: Boolean;
  public
    constructor Create(const AText: string; const ACancellation: IPascalCancellation;
      const ASkip: TArray<TTextRange>); overload;
    constructor Create(const AText: string; const ACancellation: IPascalCancellation); overload;
    destructor Destroy; override;
  end;

  /// <summary>Diagnosen, erwartete Token und Wiederaufsetzen nach Fehlern.</summary>
  TParserBase = class(TParserCursor)
  protected
    procedure ExpectKw(const AWord: string);
    procedure ExpectSym(const ASymbol: string);
    function ExpectIdent: string;
    procedure Diagnose(const AMessage: string);
    /// <summary>Fehlendes ';' in Deklarationen (wie E2029).</summary>
    procedure DiagnoseMissingSemicolon; overload;
    /// <summary>Wie oben; AStatement: zwischen Anweisungen, dort meldet der Compiler E2066.</summary>
    procedure DiagnoseMissingSemicolon(AStatement: Boolean); overload;
    procedure DiagnoseAt(const AMessage: string; const AStartPos, AEndPos: TTextPosition);
    /// <summary>Meldung mit Compilercode: AMessage bekommt „(wie ACode).“ angehängt.</summary>
    procedure DiagnoseCode(const ACode, AMessage: string; const AStartPos, AEndPos: TTextPosition); overload;
    /// <summary>Wie oben, mit Korrektur AFix.</summary>
    procedure DiagnoseCode(const ACode, AMessage: string; const AStartPos, AEndPos: TTextPosition;
      const AFix: TParserFix); overload;
    procedure AddDiagnostic(const ADiagnostic: TSyntaxDiagnostic);
    procedure DiagnoseUnexpected(const AExpected: string); overload;
    procedure DiagnoseUnexpected(const ACode, AExpected: string); overload;
    /// <summary>Nicht geschlossene Strings und Kommentare (E2052, E2057), Zahlen mit leerem Exponenten (E2053)
    /// und die Prüfungen am Baum.</summary>
    procedure CheckTokensAndTree(ARoot: TSyntaxNode);
    /// <summary>Meldet AToken, wenn er offen ist; True bei offenem Kommentar, danach ist nichts mehr zu prüfen.
    /// </summary>
    function CheckOpenToken(const AToken: TPascalToken): Boolean;
    /// <summary>Offener String (E2052); Meldungen dahinter in derselben Zeile fallen weg.</summary>
    procedure DiagnoseOpenString(const AToken: TPascalToken);
    /// <summary>Offener Kommentar bis Dateiende (E2057); alle Meldungen dahinter fallen weg.</summary>
    procedure DiagnoseOpenComment(const AToken: TPascalToken);
    function IsRecoveryPoint(ARecovery: TRecovery): Boolean;
    procedure SkipError(AParent: TSyntaxNode; ARecovery: TRecovery);
    function ParseQualifiedName: string;
    function IsSectionEnd: Boolean;
    function IsDeclarationStart: Boolean;
    function IsRoutineStart: Boolean;
    function EnterNesting: Boolean;
    function TooDeep: TSyntaxNode;
  end;

const
  /// <summary>Höchste Verschachtelungstiefe; schützt vor Stapelüberlauf bei kaputtem Code.</summary>
  cMaxNesting = 256;

function SameWord(const A, B: string): Boolean; inline;
function InWords(const AText: string; const AWords: array of string): Boolean;
function Before(const A, B: TTextPosition): Boolean; inline;
function InRanges(const APos: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
/// <summary>Steht ein {$I datei.inc} hinter APrevious an der Stelle eines Werts (#849)? Siehe
/// TPascalParser.IncludeAsValue.</summary>
function IncludeAsValue(const APrevious: TPascalToken): Boolean;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.SyntaxChecks,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCursorText = (IncompleteString, CloseString, CloseCommentInLine, Missing, Add, OperatorOrMissing,
    ExpectedButEndOfFile, ExpectedButFound, NestedTooDeeplyMoreThan, UnexpectedEndOfFileIn,
    SyntaxErrorInFloatingPoint, Identifier, Like, Statement, IdentifierExpected);

const
  cTexts: array[TCursorText] of TAtlasText = (
    (De: 'Unvollständiger String'; En: 'Incomplete string'),
    (De: 'String schließen'; En: 'Close string'),
    (De: 'Kommentar in Zeile %d schließen'; En: 'Close comment in line %d'),
    (De: ''';'' fehlt'; En: ''';'' missing'),
    (De: ''';'' ergänzen'; En: 'Add '';'''),
    (De: 'Operator oder '';'' fehlt'; En: 'Operator or '';'' missing'),
    (De: ' erwartet, aber Dateiende gefunden'; En: ' expected but end of file found'),
    (De: '%s erwartet, aber ''%s'' gefunden'; En: '%s expected but ''%s'' found'),
    (De: 'Zu tief verschachtelt (mehr als %d Ebenen); Rest der Datei nicht ausgewertet';
     En: 'Nested too deeply (more than %d levels); rest of the file not evaluated'),
    (De: 'Unerwartetes Dateiende im Kommentar ab Zeile %d'; En: 'Unexpected end of file in the comment from line %d'),
    (De: 'Syntaxfehler in Gleitkommazahl'; En: 'Syntax error in floating point number'),
    (De: 'Bezeichner'; En: 'identifier'),
    (De: ' (wie %s).'; En: ' (like %s).'),
    (De: 'Anweisung'; En: 'statement'),
    (De: 'Bezeichner erwartet'; En: 'Identifier expected'));

{$SCOPEDENUMS OFF}

function SameWord(const A, B: string): Boolean; inline;
begin
  Result := SameText(A, B);
end;

function InWords(const AText: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    if SameText(AText, mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Before(const A, B: TTextPosition): Boolean; inline;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function InRanges(const APos: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
var
  mRange: TTextRange;
begin
  for mRange in ARanges do
  begin
    if not Before(APos, mRange.StartPos) and Before(APos, mRange.EndPos) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function IncludeAsValue(const APrevious: TPascalToken): Boolean;
const
  cValueStarts: array[0..8] of string = ('=', ':=', '(', ',', '[', '+', '-', '*', '/');
begin
  Result := (APrevious.Kind = TPascalTokenKind.Symbol) and InWords(APrevious.Text, cValueStarts);
end;

/// <summary>Gehört AToken in die Token des Parsers? Nicht in übersprungenen Bereichen, ohne Kommentare und
/// Direktiven außer {$I datei.inc} an der Stelle eines Werts hinter dem letzten Token in ASignificant.</summary>
function KeepToken(const AToken: TPascalToken; const ASkip: TArray<TTextRange>;
  ASignificant: TList<TPascalToken>): Boolean;
var
  mIncludeName: string;
begin
  if (ASkip <> nil) and InRanges(AToken.StartPos, ASkip) then
  begin
    Exit(False);
  end;
  if AToken.Kind = TPascalTokenKind.Comment then
  begin
    Exit(False);
  end;
  Result := (AToken.Kind <> TPascalTokenKind.Directive) or ((ASignificant.Count > 0) and
    TPascalPreprocessor.IncludeFileOf(AToken.Text, mIncludeName) and
    IncludeAsValue(ASignificant[ASignificant.Count - 1]));
end;

{ TParserFix }

class function TParserFix.Create(const ATitle: string; const AStart, AEnd: TTextPosition; const AText: string;
  ASafe: Boolean): TParserFix;
begin
  Result.Title := ATitle;
  Result.Edits := [TTextEdit.Create(TTextRange.Create(AStart, AEnd), AText)];
  Result.Safe := ASafe;
end;

{ TParserCursor }

constructor TParserCursor.Create(const AText: string; const ACancellation: IPascalCancellation);
begin
  Create(AText, ACancellation, nil);
end;

constructor TParserCursor.Create(const AText: string; const ACancellation: IPascalCancellation;
  const ASkip: TArray<TTextRange>);
var
  mToken: TPascalToken;
  mSignificant: TList<TPascalToken>;
begin
  inherited Create;
  FCancellation := ACancellation;
  FSkip := ASkip;
  FDiagnostics := TList<TSyntaxDiagnostic>.Create;
  FAllTokens := TPascalLexer.Tokenize(AText);
  mSignificant := TList<TPascalToken>.Create;
  try
    for mToken in FAllTokens do
    begin
      if KeepToken(mToken, ASkip, mSignificant) then
      begin
        mSignificant.Add(mToken);
      end;
    end;
    FTokens := mSignificant.ToArray;
  finally
    mSignificant.Free;
  end;
  if Length(FAllTokens) > 0 then
  begin
    FEndPos := FAllTokens[High(FAllTokens)].EndPos;
    FEndOffset := FAllTokens[High(FAllTokens)].Offset + Length(FAllTokens[High(FAllTokens)].Text);
  end;
end;

destructor TParserCursor.Destroy;
begin
  FDiagnostics.Free;
  inherited;
end;

function TParserCursor.AtEnd: Boolean;
begin
  Result := FIndex >= Length(FTokens);
end;

function TParserCursor.Current: TPascalToken;
begin
  Result := PeekToken(0);
end;

function TParserCursor.PeekToken(ADelta: Integer): TPascalToken;
begin
  if (FIndex + ADelta >= 0) and (FIndex + ADelta < Length(FTokens)) then
  begin
    Result := FTokens[FIndex + ADelta];
  end
  else
  begin
    // Platzhalter hinter dem letzten Token.
    Result := Default(TPascalToken);
    Result.Kind := TPascalTokenKind.Unknown;
    Result.Offset := FEndOffset;
    Result.StartPos := FEndPos;
    Result.EndPos := FEndPos;
  end;
end;

function TParserCursor.IsKw(const AWord: string): Boolean;
begin
  Result := not AtEnd and FTokens[FIndex].IsKeyword(AWord);
end;

function TParserCursor.IsKw(const AWords: array of string): Boolean;
begin
  Result := not AtEnd and (FTokens[FIndex].Kind = TPascalTokenKind.Keyword) and InWords(FTokens[FIndex].Text, AWords);
end;

function TParserCursor.IsSym(const ASymbol: string): Boolean;
begin
  Result := not AtEnd and FTokens[FIndex].IsSymbol(ASymbol);
end;

function TParserCursor.IsIdent: Boolean;
begin
  Result := not AtEnd and (FTokens[FIndex].Kind = TPascalTokenKind.Identifier);
end;

function TParserCursor.IsIdentText(const AText: string): Boolean;
begin
  Result := IsIdent and SameWord(FTokens[FIndex].Text, AText);
end;

function TParserCursor.PeekIsSym(ADelta: Integer; const ASymbol: string): Boolean;
begin
  Result := PeekToken(ADelta).IsSymbol(ASymbol);
end;

function TParserCursor.PeekIsKw(ADelta: Integer; const AWord: string): Boolean;
begin
  Result := PeekToken(ADelta).IsKeyword(AWord);
end;

procedure TParserCursor.Advance;
begin
  if AtEnd then
  begin
    Exit;
  end;
  Inc(FIndex);
  // Abbruch nur gelegentlich abfragen; danach gilt der Rest als gelesen.
  Inc(FAdvances);
  if ((FAdvances and 4095) = 0) and (FCancellation <> nil) and FCancellation.IsCancelled then
  begin
    FIndex := Length(FTokens);
  end;
end;

function TParserCursor.AcceptKw(const AWord: string): Boolean;
begin
  Result := IsKw(AWord);
  if Result then
  begin
    Advance;
  end;
end;

function TParserCursor.AcceptSym(const ASymbol: string): Boolean;
begin
  Result := IsSym(ASymbol);
  if Result then
  begin
    Advance;
  end;
end;

function TParserCursor.NodeStart: Integer;
begin
  Result := FIndex;
end;

function TParserCursor.StartNode(AKind: TSyntaxKind): TSyntaxNode;
begin
  Result := TSyntaxNode.Create(AKind);
end;

procedure TParserCursor.FinishNode(ANode: TSyntaxNode; AStartIndex: Integer);
var
  mFirst: TPascalToken;
  mLast: TPascalToken;
begin
  if FIndex > AStartIndex then
  begin
    mFirst := FTokens[AStartIndex];
    mLast := FTokens[FIndex - 1];
    ANode.SetRange(mFirst.StartPos, mLast.EndPos, mFirst.Offset, mLast.Offset + Length(mLast.Text));
  end
  else
  begin
    // Leerer Knoten, z. B. bei fehlendem Ausdruck: Position des nächsten Tokens.
    mFirst := Current;
    ANode.SetRange(mFirst.StartPos, mFirst.StartPos, mFirst.Offset, mFirst.Offset);
  end;
end;

function TParserCursor.Leaf(AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  mStart: Integer;
begin
  mStart := NodeStart;
  Result := StartNode(AKind);
  Result.Name := AName;
  Advance;
  FinishNode(Result, mStart);
end;

function TParserCursor.IsControlChar: Boolean;
var
  mNext: TPascalToken;
begin
  Result := IsSym('^');
  if not Result then
  begin
    Exit;
  end;
  mNext := PeekToken(1);
  // Ohne Leerraum dahinter; als Typ (^TFoo) kommt der Parser nicht hierher, P^ ist nachgestellt.
  Result := (mNext.Offset = Current.Offset + 1) and (Length(mNext.Text) = 1) and
    (mNext.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Symbol, TPascalTokenKind.Unknown]);
end;

procedure TParserCursor.SplitGreaterEqual;
var
  mEqual: TPascalToken;
begin
  // Der Lexer liest in IBaz<string>=nil ">=" als ein Token; hinter generischen Argumenten sind es ">" und "="
  // (#1142).
  mEqual := FTokens[FIndex];
  FTokens[FIndex].Text := '>';
  FTokens[FIndex].EndPos := TTextPosition.Create(mEqual.StartPos.Line, mEqual.StartPos.Character + 1);
  mEqual.Text := '=';
  Inc(mEqual.Offset);
  mEqual.StartPos := FTokens[FIndex].EndPos;
  Insert(mEqual, FTokens, FIndex + 1);
end;

{ TParserBase }

function DiagnosticBefore(const A, B: TSyntaxDiagnostic): Integer;
begin
  Result := A.StartPos.Line - B.StartPos.Line;
  if Result = 0 then
  begin
    Result := A.StartPos.Character - B.StartPos.Character;
  end;
end;

procedure TParserBase.ExpectKw(const AWord: string);
begin
  if not AcceptKw(AWord) then
  begin
    DiagnoseUnexpected('"' + AWord + '"');
  end;
end;

/// <summary>Schließende Klammer des Kommentars ATokenText: "*)" bzw. "}".</summary>
function CommentCloser(const ATokenText: string): string;
begin
  if StartsStr('(*', ATokenText) then
  begin
    Result := '*)';
  end
  else
  begin
    Result := '}';
  end;
end;

/// <summary>Ende der ersten Zeile des Tokens AToken (vor CR/LF), bei einer Zeile sein Ende.</summary>
function FirstLineEnd(const AToken: TPascalToken): TTextPosition;
var
  mBreak: Integer;
begin
  Result := AToken.EndPos;
  mBreak := Pos(#10, AToken.Text);
  if mBreak > 0 then
  begin
    if (mBreak > 1) and (AToken.Text[mBreak - 1] = #13) then
    begin
      Dec(mBreak);
    end;
    Result := TTextPosition.Create(AToken.StartPos.Line, AToken.StartPos.Character + mBreak - 1);
  end;
end;

procedure TParserBase.CheckTokensAndTree(ARoot: TSyntaxNode);
var
  mToken: TPascalToken;
  mDiagnostic: TSyntaxDiagnostic;
begin
  for mToken in FAllTokens do
  begin
    if mToken.Terminated or ((FSkip <> nil) and InRanges(mToken.StartPos, FSkip)) then
    begin
      Continue;
    end;
    if CheckOpenToken(mToken) then
    begin
      Break;
    end;
  end;
  for mDiagnostic in TSyntaxChecks.Check(ARoot, FAllTokens) do
  begin
    AddDiagnostic(mDiagnostic);
  end;
  FDiagnostics.Sort(TComparer<TSyntaxDiagnostic>.Construct(DiagnosticBefore));
end;

function TParserBase.CheckOpenToken(const AToken: TPascalToken): Boolean;
begin
  // Der erste offene String bzw. Kommentar ist die Ursache; was danach in derselben Zeile bzw. im Rest der
  // Datei gemeldet wurde, folgt daraus und fällt weg (der Compiler bricht dort ab).
  Result := False;
  if AToken.Kind = TPascalTokenKind.StringLiteral then
  begin
    DiagnoseOpenString(AToken);
  end
  else if AToken.Kind = TPascalTokenKind.Number then
  begin
    // 1.5e: Exponent ohne Ziffern (#1382).
    DiagnoseCode('E2053', cTexts[TCursorText.SyntaxErrorInFloatingPoint].Text, AToken.StartPos, AToken.EndPos);
  end
  else if AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
  begin
    DiagnoseOpenComment(AToken);
    Result := True;
  end;
end;

procedure TParserBase.DiagnoseOpenString(const AToken: TPascalToken);
var
  mIndex: Integer;
begin
  for mIndex := FDiagnostics.Count - 1 downto 0 do
  begin
    if (FDiagnostics[mIndex].StartPos.Line = AToken.StartPos.Line) and
      not Before(FDiagnostics[mIndex].StartPos, AToken.StartPos) then
    begin
      FDiagnostics.Delete(mIndex);
    end;
  end;
  if AToken.StartPos.Line = AToken.EndPos.Line then
  begin
    DiagnoseCode('E2052', cTexts[TCursorText.IncompleteString].Text, AToken.StartPos, AToken.EndPos,
      TParserFix.Create(cTexts[TCursorText.CloseString].Text, AToken.EndPos, AToken.EndPos, '''', False));
  end
  else
  begin
    DiagnoseCode('E2052', cTexts[TCursorText.IncompleteString].Text, AToken.StartPos, AToken.StartPos);
  end;
end;

procedure TParserBase.DiagnoseOpenComment(const AToken: TPascalToken);
var
  mIndex: Integer;
  mFirst, mLineEnd: TTextPosition;
  mCloser: string;
begin
  mFirst := AToken.StartPos;
  for mIndex := FDiagnostics.Count - 1 downto 0 do
  begin
    if not Before(FDiagnostics[mIndex].StartPos, mFirst) then
    begin
      FDiagnostics.Delete(mIndex);
    end;
  end;
  mCloser := CommentCloser(AToken.Text);
  // Geschlossen wird am Ende der ersten Zeile: Meist fehlt dort die Klammer.
  mLineEnd := FirstLineEnd(AToken);
  DiagnoseCode('E2057', cTexts[TCursorText.UnexpectedEndOfFileIn].Fmt([mFirst.Line + 1]), mFirst,
    TTextPosition.Create(mFirst.Line, mFirst.Character + Length(mCloser)),
    TParserFix.Create(cTexts[TCursorText.CloseCommentInLine].Fmt([mFirst.Line + 1]), mLineEnd, mLineEnd, mCloser,
    False));
end;

procedure TParserBase.ExpectSym(const ASymbol: string);
begin
  if AcceptSym(ASymbol) then
  begin
    Exit;
  end;
  if ASymbol = ';' then
  begin
    DiagnoseMissingSemicolon;
  end
  else
  begin
    DiagnoseUnexpected('"' + ASymbol + '"');
  end;
end;

procedure TParserBase.DiagnoseMissingSemicolon;
begin
  DiagnoseMissingSemicolon(False);
end;

procedure TParserBase.DiagnoseMissingSemicolon(AStatement: Boolean);
var
  mPrevious: TPascalToken;
  mCode: string;
begin
  // Folgefehler: An dieser Stelle wurde schon etwas gemeldet.
  if (FDiagnostics.Count > 0) and (FDiagnostics.Last.StartPos = Current.StartPos) then
  begin
    Exit;
  end;
  mPrevious := PeekToken(-1);
  // Am Zeilenende dort melden, wo es fehlt, nicht erst in der nächsten Zeile.
  mCode := 'E2029';
  if AStatement then
  begin
    mCode := 'E2066';
  end;
  if (FIndex > 0) and (AtEnd or (Current.StartPos.Line > mPrevious.EndPos.Line)) then
  begin
    DiagnoseCode(mCode, cTexts[TCursorText.Missing].Text, mPrevious.EndPos, mPrevious.EndPos,
      TParserFix.Create(cTexts[TCursorText.Add].Text, mPrevious.EndPos, mPrevious.EndPos, ';', False));
  end
  else if AStatement then
  begin
    // B := 1 2; – es fehlt ein Operator oder das Semikolon.
    DiagnoseCode(mCode, cTexts[TCursorText.OperatorOrMissing].Text, Current.StartPos, Current.EndPos);
  end
  else
  begin
    DiagnoseUnexpected('";"');
  end;
end;

function TParserBase.ExpectIdent: string;
begin
  if IsIdent then
  begin
    Result := Current.Text;
    Advance;
  end
  else
  begin
    DiagnoseUnexpected(cTexts[TCursorText.Identifier].Text);
    Result := '';
  end;
end;

procedure TParserBase.Diagnose(const AMessage: string);
begin
  DiagnoseAt(AMessage, Current.StartPos, Current.EndPos);
end;

procedure TParserBase.DiagnoseAt(const AMessage: string; const AStartPos, AEndPos: TTextPosition);
var
  mDiagnostic: TSyntaxDiagnostic;
begin
  mDiagnostic := Default(TSyntaxDiagnostic);
  mDiagnostic.Message := AMessage;
  mDiagnostic.StartPos := AStartPos;
  mDiagnostic.EndPos := AEndPos;
  AddDiagnostic(mDiagnostic);
end;

procedure TParserBase.AddDiagnostic(const ADiagnostic: TSyntaxDiagnostic);
begin
  // Mehrere Folgefehler an derselben Stelle melden wir nur einmal.
  if (FDiagnostics.Count > 0) and (FDiagnostics.Last.StartPos = ADiagnostic.StartPos) then
  begin
    Exit;
  end;
  FDiagnostics.Add(ADiagnostic);
end;

procedure TParserBase.DiagnoseCode(const ACode, AMessage: string; const AStartPos, AEndPos: TTextPosition);
begin
  DiagnoseCode(ACode, AMessage, AStartPos, AEndPos, Default(TParserFix));
end;

procedure TParserBase.DiagnoseCode(const ACode, AMessage: string; const AStartPos, AEndPos: TTextPosition;
  const AFix: TParserFix);
var
  mDiagnostic: TSyntaxDiagnostic;
begin
  mDiagnostic := Default(TSyntaxDiagnostic);
  mDiagnostic.Message := AMessage + cTexts[TCursorText.Like].Fmt([ACode]);
  mDiagnostic.StartPos := AStartPos;
  mDiagnostic.EndPos := AEndPos;
  mDiagnostic.Code := ACode;
  mDiagnostic.FixTitle := AFix.Title;
  mDiagnostic.FixEdits := AFix.Edits;
  mDiagnostic.FixSafe := AFix.Safe;
  AddDiagnostic(mDiagnostic);
end;

procedure TParserBase.DiagnoseUnexpected(const AExpected: string);
begin
  DiagnoseUnexpected('E2029', AExpected);
end;

procedure TParserBase.DiagnoseUnexpected(const ACode, AExpected: string);
var
  mExpected: string;
begin
  // Wie der Compiler: '%s' erwartet, aber '%s' gefunden.
  mExpected := StringReplace(AExpected, '"', '''', [rfReplaceAll]);
  if AtEnd then
  begin
    DiagnoseCode(ACode, mExpected + cTexts[TCursorText.ExpectedButEndOfFile].Text, Current.StartPos, Current.EndPos);
  end
  else
  begin
    DiagnoseCode(ACode, cTexts[TCursorText.ExpectedButFound].Fmt([mExpected, Current.Text]), Current.StartPos,
      Current.EndPos);
  end;
end;

function TParserBase.IsRecoveryPoint(ARecovery: TRecovery): Boolean;
begin
  case ARecovery of
    TRecovery.Declarations:
      Result := IsSectionEnd or IsDeclarationStart;
    TRecovery.Members:
      Result := IsKw('end') or IsSym(';') or IsIdent or IsRoutineStart or IsKw('property');
  else
    Result := IsSym(';') or IsKw(FTerminators) or
      IsKw(['begin', 'if', 'case', 'for', 'while', 'repeat', 'with', 'try', 'raise']);
  end;
end;

procedure TParserBase.SkipError(AParent: TSyntaxNode; ARecovery: TRecovery);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  // Mindestens ein Token überspringen, damit der Aufrufer weiterkommt.
  if AtEnd then
  begin
    Exit;
  end;
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.Error);
  case ARecovery of
    TRecovery.Declarations:
      DiagnoseUnexpected('Deklaration');
    TRecovery.Members:
      DiagnoseUnexpected('"end"');
  else
    DiagnoseUnexpected(cTexts[TCursorText.Statement].Text);
  end;
  repeat
    Advance;
  until AtEnd or IsRecoveryPoint(ARecovery);
  FinishNode(mNode, mStart);
  AParent.Add(mNode);
end;

function TParserBase.ParseQualifiedName: string;
begin
  Result := ExpectIdent;
  while IsSym('.') and (PeekToken(1).Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) do
  begin
    Advance;
    Result := Result + '.' + Current.Text;
    Advance;
  end;
  // uses System.; – hinter dem Punkt fehlt der Name.
  if IsSym('.') then
  begin
    Advance;
    DiagnoseCode('E2372', cTexts[TCursorText.IdentifierExpected].Text, Current.StartPos, Current.EndPos);
  end;
end;

function TParserBase.IsSectionEnd: Boolean;
begin
  Result := AtEnd or IsKw(['implementation', 'initialization', 'finalization', 'begin', 'end', 'asm']);
end;

function TParserBase.IsDeclarationStart: Boolean;
begin
  Result := IsKw(['type', 'const', 'resourcestring', 'var', 'threadvar', 'label', 'exports']) or
    IsRoutineStart or IsSym('[');
end;

function TParserBase.IsRoutineStart: Boolean;
begin
  // operator ohne class (FPC: operator := (…), operator Add(…)), aber nicht Operator: string bzw.
  // Operator, Art: string – das sind Felder oder Variablen.
  Result := IsKw(['procedure', 'function', 'constructor', 'destructor']) or
    (IsIdentText('operator') and not PeekToken(1).IsSymbol(':') and not PeekToken(1).IsSymbol(',')) or
    (IsKw('class') and (PeekIsKw(1, 'procedure') or PeekIsKw(1, 'function') or PeekIsKw(1, 'constructor') or
      PeekIsKw(1, 'destructor') or PeekToken(1).IsKeyword('operator') or
      ((PeekToken(1).Kind = TPascalTokenKind.Identifier) and SameWord(PeekToken(1).Text, 'operator'))));
end;

function TParserBase.EnterNesting: Boolean;
begin
  Result := FDepth < cMaxNesting;
  if Result then
  begin
    Inc(FDepth);
  end;
end;

function TParserBase.TooDeep: TSyntaxNode;
var
  mStart: Integer;
begin
  // Schutz vor Stapelüberlauf: Der Rest der Datei wird nicht mehr ausgewertet.
  Diagnose(cTexts[TCursorText.NestedTooDeeplyMoreThan].Fmt([cMaxNesting]));
  mStart := NodeStart;
  Result := StartNode(TSyntaxKind.Error);
  FIndex := Length(FTokens);
  FinishNode(Result, mStart);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.Parser.Cursor', cTexts);

end.
