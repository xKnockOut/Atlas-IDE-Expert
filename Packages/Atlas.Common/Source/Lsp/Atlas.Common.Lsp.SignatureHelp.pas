unit Atlas.Common.Lsp.SignatureHelp;

// Parameterhilfe (textDocument/signatureHelp): zeigt beim Aufruf alle Überladungen der Routine,
// hebt den aktiven Parameter hervor und übernimmt die ///-Dokumentation samt <param>-Texten
// (TXmlDoc mit <inheritdoc/>, #654).
// Der Aufruf wird an den Tokens vor dem Cursor erkannt: die innerste offene Klammer hinter
// einem Bezeichner; Kommas auf derselben Ebene zählen den aktiven Parameter.
// Überladungen nach Argumenttypen (#498): Jedes bisherige Argument bekommt einen Typ (Literale: Zeichen, String,
// Zahl, Boolean, nil, Menge; Bezeichner über die Namensauflösung, Aufzählungswerte über ihren Typ) und wird mit dem
// Parametertyp verglichen (TResolverText.ArgumentFits). Unbekannte Typen gelten als verträglich. Jede Signatur
// trägt das Ergebnis in data.fits und data.mismatch (erstes unverträgliches Argument, -1); vorgewählt wird die
// erste verträgliche mit genug Parametern.
// Formatroutinen (#451): Ist die Routine Format oder eine andere Formatroutine (Pascal.FormatRoutines, dazu eigene
// aus FormatRoutinesFor), steht unter "format" die Zuordnung Platzhalter → Argument (Lsp.SignatureFormat).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Lsp.SignatureFormat,
  Atlas.Common.Lsp.Hover;

type
  TCallSite = record
    /// <summary>Position des Routinennamens vor der Klammer.</summary>
    NamePosition: TTextPosition;
    /// <summary>Nullbasiert.</summary>
    ActiveParameter: Integer;
    Found: Boolean;
    /// <summary>Tokens der bisherigen Argumente (Index in ATree.Tokens, Last einschließlich), das gerade getippte
    /// eingeschlossen; First &gt; Last bei leerem Argument (#498).</summary>
    ArgumentFirst: TArray<Integer>;
    ArgumentLast: TArray<Integer>;
  end;

  TSignatureParameter = record
    /// <summary>Bereich im Label der Signatur (Zeichen, nullbasiert, Ende exklusiv).</summary>
    StartIndex: Integer;
    EndIndex: Integer;
    Documentation: string;
    /// <summary>Typ hinter dem Doppelpunkt ohne Vorgabewert; '' bei untypisierten Parametern (#498).</summary>
    TypeName: string;
  end;

  TSignature = record
    Text: string;
    Documentation: string;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Kopf mit Typ-Präfix (procedure TFoo.Bar), also der Rumpf einer Methode.</summary>
    Qualified: Boolean;
    /// <summary>Alle bisherigen Argumente sind mit ihren Parametern verträglich (#498).</summary>
    Fits: Boolean;
    /// <summary>Erstes unverträgliches Argument, -1 ohne.</summary>
    Mismatch: Integer;
  end;

  TSignatureHelp = record
    Signatures: TArray<TSignature>;
    ActiveSignature: Integer;
    ActiveParameter: Integer;
    /// <summary>Signaturen aus der eingebauten Liste von System (#880), ohne Quelltext.</summary>
    Intrinsic: Boolean;
    /// <summary>Platzhalter einer Formatroutine (#451); Found = False sonst.</summary>
    Format: TSignatureFormat;
    function Found: Boolean;
  end;

  /// <summary>Eingaben der Parameterhilfe: Namensauflösung, Index, Dokument und Formatroutinen (#451).</summary>
  TSignatureHelpRequest = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    TreeText: string;
    FileName: string;
    ReadText: THoverReadText;
    /// <summary>Formatroutinen (#451); Create setzt die eingebauten.</summary>
    Routines: TArray<TFormatRoutine>;
    class function Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const AReadText: THoverReadText): TSignatureHelpRequest; static;
  end;

  /// <summary>Formatroutinen für das Dokument AUri: eingebaute und eigene (#451).</summary>
  TFormatRoutinesFunc = reference to function(const AUri: string): TArray<TFormatRoutine>;

  TLspSignatureHelp = class
  public const
    cMethod = 'textDocument/signatureHelp';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: THoverReadText;
    FNamespaces: TArray<string>;
    FFormatRoutinesFor: TFormatRoutinesFunc;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AReadText: THoverReadText); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>signatureHelpProvider mit ( und , als Auslöser.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Innerster offener Aufruf vor APosition.</summary>
    class function CallSiteAt(ATree: TSyntaxTree; const APosition: TTextPosition): TCallSite; static;
    /// <summary>Typ des Arguments aus ATokens[AFirst..ALast] (#498): Char, string, Integer, Double, Boolean, nil,
    /// [] oder der Typ eines Bezeichners; '' wenn unbekannt.</summary>
    class function ArgumentType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      AFirst, ALast: Integer): string; static;
    /// <summary>Setzt Fits und Mismatch von ASignature für AArgumentTypes.</summary>
    class procedure Match(var ASignature: TSignature; const AArgumentTypes: TArray<string>); static;
    /// <summary>Kopf einer Routine ab ALine/AColumn bis zum ; hinter der Parameterliste, auf eine Zeile
    /// gebracht.</summary>
    class function ParseSignature(const ALines: TArray<string>; ALine, AColumn: Integer): TSignature; static;
    /// <summary>Signaturen des Aufrufs an APosition im Dokument von ARequest.</summary>
    class function HelpAt(const ARequest: TSignatureHelpRequest; const APosition: TTextPosition): TSignatureHelp;
      static;
    /// <summary>SignatureHelp des LSP; JSON-null ohne Signaturen. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AHelp: TSignatureHelp): TJSONValue; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Formatroutinen je Dokument (#451); ohne gelten die eingebauten.</summary>
    property FormatRoutinesFor: TFormatRoutinesFunc read FFormatRoutinesFor write FFormatRoutinesFor;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Index.Files,
  System.Math,
  System.StrUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSignatureHelpText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TSignatureHelpText] of TAtlasText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen'; En: 'Fields "textDocument.uri" and "position" missing'));

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  cMaxHeaderLines = 50;
  cParameterModifiers: array[0..4] of string = ('const ', 'var ', 'out ', 'constref ', '[ref] ');
  /// <summary>Schlüsselwörter, an denen die Suche nach der offenen Klammer endet.</summary>
  cStatementKeywords: array[0..4] of string = ('begin', 'end', 'then', 'do', 'var');
  /// <summary>Zeichen hinter einem Parameternamen in seiner Gruppe.</summary>
  cNameEnds: array[0..2] of string = (':', ' ', ',');
  /// <summary>LiteralChars: kein Zeichen- oder String-Literal.</summary>
  cNoLiteral = -2;

type
  /// <summary>Rückwärtssuche nach der innersten offenen Aufrufklammer (CallSiteAt); sammelt die Argumente
  /// (#498).</summary>
  TCallScan = record
    Tokens: TArray<TPascalToken>;
    /// <summary>Letztes Token vor der Position.</summary>
    Last: Integer;
    Depth: Integer;
    Commas: Integer;
    /// <summary>Letztes Token des Arguments links vom nächsten Komma.</summary>
    SpanEnd: Integer;
    Firsts: TArray<Integer>;
    Lasts: TArray<Integer>;
    procedure AddArgument(AFirst: Integer);
    function Opening(AIndex: Integer; var ASite: TCallSite): Boolean;
    function Separator(AIndex: Integer): Boolean;
    /// <summary>Verarbeitet das Token AIndex; True beendet die Suche.</summary>
    function Step(AIndex: Integer; var ASite: TCallSite): Boolean;
  end;

  /// <summary>Ein Lauf von HelpAt: Aufruf finden, Überladungen sammeln, Argumente vergleichen.</summary>
  THelpRun = class
  private
    FRequest: TSignatureHelpRequest;
    FPosition: TTextPosition;
    FSite: TCallSite;
    FResolved: TResolvedSymbol;
    FLines: TArray<string>;
    FStarts: TArray<TTextPosition>;
    FStartSymbols: TArray<TResolvedSymbol>;
    procedure ResolveSite;
    function IntrinsicHelp: TSignatureHelp;
    function ReadLines: Boolean;
    procedure AddStart(const APosition: TTextPosition; const ASymbol: TResolvedSymbol);
    function IsOverload(const ASymbol: TIndexSymbol): Boolean;
    function OwnerUnit(out AOwner: TUnitIndex): Boolean;
    function CollectUnitStarts: Boolean;
    function CollectStarts: Boolean;
    function BoundTypes: TArray<string>;
    function HeaderLines(const AStart: TTextPosition; const ABindings: TArray<string>): TArray<string>;
    function Signatures: TArray<TSignature>;
    procedure MatchArguments(var ASignatures: TArray<TSignature>);
    procedure AddFormat(var AHelp: TSignatureHelp);
  public
    constructor Create(const ARequest: TSignatureHelpRequest; const APosition: TTextPosition);
    function Run: TSignatureHelp;
  end;

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

function CollapseSpaces(const AText: string): string;
var
  mIndex: Integer;
  mSpace: Boolean;
begin
  Result := '';
  mSpace := False;
  for mIndex := 1 to Length(AText) do
  begin
    if CharInSet(AText[mIndex], [' ', #9, #10, #13]) then
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
end;

function IsSkipped(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Index des nächsten Tokens vor AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
function PreviousCodeToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsSkipped(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Letztes Token, das vor APosition beginnt; -1 ohne.</summary>
function LastTokenBefore(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if ComparePositions(ATokens[mIndex].StartPos, APosition) >= 0 then
    begin
      Break;
    end;
    Result := mIndex;
  end;
end;

/// <summary>; oder ein Schlüsselwort, hinter dem kein offener Aufruf mehr stehen kann.</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
var
  mKeyword: string;
begin
  Result := AToken.IsSymbol(';');
  for mKeyword in cStatementKeywords do
  begin
    Result := Result or AToken.IsKeyword(mKeyword);
  end;
end;

{ TCallScan }

procedure TCallScan.AddArgument(AFirst: Integer);
begin
  Firsts := TArray<Integer>.Create(AFirst) + Firsts;
  Lasts := TArray<Integer>.Create(SpanEnd) + Lasts;
end;

function TCallScan.Opening(AIndex: Integer; var ASite: TCallSite): Boolean;
var
  mPrevious: Integer;
begin
  Result := False;
  if Depth > 0 then
  begin
    Dec(Depth);
    Exit;
  end;
  mPrevious := PreviousCodeToken(Tokens, AIndex);
  if Tokens[AIndex].IsSymbol('(') and (mPrevious >= 0) and (Tokens[mPrevious].Kind = TPascalTokenKind.Identifier) then
  begin
    AddArgument(AIndex + 1);
    ASite.NamePosition := Tokens[mPrevious].StartPos;
    ASite.ActiveParameter := Commas;
    ASite.Found := True;
    ASite.ArgumentFirst := Firsts;
    ASite.ArgumentLast := Lasts;
    Exit(True);
  end;
  // Klammer um einen Ausdruck oder eine Menge: sie ist selbst ein Argument des äußeren Aufrufs.
  Commas := 0;
  Firsts := nil;
  Lasts := nil;
  SpanEnd := Last;
end;

function TCallScan.Separator(AIndex: Integer): Boolean;
begin
  Result := False;
  if Tokens[AIndex].IsSymbol(',') then
  begin
    Inc(Commas);
    AddArgument(AIndex + 1);
    SpanEnd := AIndex - 1;
  end
  else
  begin
    Result := EndsStatement(Tokens[AIndex]);
  end;
end;

function TCallScan.Step(AIndex: Integer; var ASite: TCallSite): Boolean;
var
  mToken: TPascalToken;
begin
  Result := False;
  mToken := Tokens[AIndex];
  if IsSkipped(mToken) then
  begin
    Exit;
  end;
  if mToken.IsSymbol(')') or mToken.IsSymbol(']') then
  begin
    Inc(Depth);
  end
  else if mToken.IsSymbol('(') or mToken.IsSymbol('[') then
  begin
    Result := Opening(AIndex, ASite);
  end
  else if Depth = 0 then
  begin
    Result := Separator(AIndex);
  end;
end;

{ TSignatureHelpRequest }

class function TSignatureHelpRequest.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const AReadText: THoverReadText): TSignatureHelpRequest;
begin
  Result := Default(TSignatureHelpRequest);
  Result.Resolver := AResolver;
  Result.Index := AIndex;
  Result.Tree := ATree;
  Result.TreeText := ATreeText;
  Result.FileName := AFileName;
  Result.ReadText := AReadText;
  Result.Routines := TFormatRoutines.Defaults;
end;

{ TSignatureHelp }

function TSignatureHelp.Found: Boolean;
begin
  Result := Length(Signatures) > 0;
end;

{ TLspSignatureHelp }

function TLspSignatureHelp.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspSignatureHelp.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspSignatureHelp.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText);
begin
  Create(AStore, AIndex, AReadText, nil);
end;

constructor TLspSignatureHelp.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspSignatureHelp.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, Handle);
end;

class function TLspSignatureHelp.Capability: TJSONObject;
var
  mTriggers, mRetriggers: TJSONArray;
begin
  mTriggers := TJSONArray.Create;
  mTriggers.Add('(');
  mTriggers.Add(',');
  mRetriggers := TJSONArray.Create;
  mRetriggers.Add(')');
  Result := TJSONObject.Create;
  Result.AddPair('triggerCharacters', mTriggers);
  Result.AddPair('retriggerCharacters', mRetriggers);
end;

class function TLspSignatureHelp.CallSiteAt(ATree: TSyntaxTree; const APosition: TTextPosition): TCallSite;
var
  mScan: TCallScan;
  mIndex: Integer;
begin
  Result := Default(TCallSite);
  if ATree = nil then
  begin
    Exit;
  end;
  mScan := Default(TCallScan);
  mScan.Tokens := ATree.Tokens;
  mScan.Last := LastTokenBefore(mScan.Tokens, APosition);
  // Argumente rückwärts gesammelt (#498).
  mScan.SpanEnd := mScan.Last;
  for mIndex := mScan.Last downto 0 do
  begin
    if mScan.Step(mIndex, Result) then
    begin
      Break;
    end;
  end;
end;

/// <summary>Position des ; außerhalb von Klammern in AText, 0 ohne; ADepth zählt offene Klammern über die Zeilen
/// hinweg.</summary>
function HeaderEnd(const AText: string; var ADepth: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 1 to Length(AText) do
  begin
    case AText[mIndex] of
      '(': Inc(ADepth);
      ')': Dec(ADepth);
      ';':
        if ADepth = 0 then
        begin
          Exit(mIndex);
        end;
    end;
  end;
end;

/// <summary>Kopf ab ALine/AColumn bis zum ; außerhalb von Klammern, Zeilen mit Leerzeichen verbunden.</summary>
function CollectHeader(const ALines: TArray<string>; ALine, AColumn: Integer): string;
var
  mDepth, mLine, mEnd: Integer;
  mText: string;
begin
  Result := '';
  mDepth := 0;
  mLine := ALine;
  while (mLine <= High(ALines)) and (mLine < ALine + cMaxHeaderLines) do
  begin
    mText := ALines[mLine];
    if mLine = ALine then
    begin
      mText := Copy(mText, AColumn + 1, MaxInt);
    end;
    mEnd := HeaderEnd(mText, mDepth);
    if mEnd > 0 then
    begin
      Exit(Result + Copy(mText, 1, mEnd - 1));
    end;
    Result := Result + mText + ' ';
    Inc(mLine);
  end;
end;

/// <summary>procedure TFoo.Bar → procedure Bar; True, wenn ein Typ-Präfix entfernt wurde.</summary>
function StripQualifier(var AText: string): Boolean;
var
  mKeyword, mOpen, mDot: Integer;
begin
  Result := False;
  mKeyword := Pos(' ', AText);
  if mKeyword = 0 then
  begin
    Exit;
  end;
  mOpen := Pos('(', AText);
  if mOpen > 0 then
  begin
    mDot := LastDelimiter('.', Copy(AText, 1, mOpen - 1));
  end
  else
  begin
    mDot := LastDelimiter('.', AText);
  end;
  Result := mDot > mKeyword;
  if Result then
  begin
    Delete(AText, mKeyword + 1, mDot - mKeyword);
  end;
end;

/// <summary>Position der Klammer, die die Klammer an AOpen schließt; 0 ohne.</summary>
function ClosingParen(const AText: string; AOpen: Integer): Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := 0;
  mDepth := 0;
  for mIndex := AOpen to Length(AText) do
  begin
    if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(mIndex);
      end;
    end;
  end;
end;

/// <summary>Typ hinter dem Doppelpunkt ohne Vorgabewert und ohne Unit davor (System.Boolean → Boolean, #498);
/// '' bei untypisierten Parametern.</summary>
function GroupType(const AGroupText: string): string;
var
  mColon, mEqual: Integer;
begin
  Result := '';
  mColon := Pos(':', AGroupText);
  if mColon = 0 then
  begin
    Exit;
  end;
  Result := Copy(AGroupText, mColon + 1, MaxInt);
  mEqual := Pos('=', Result);
  if mEqual > 0 then
  begin
    Result := Copy(Result, 1, mEqual - 1);
  end;
  Result := Trim(Result);
  if (Pos('<', Result) = 0) and (Pos(' ', Result) = 0) and (LastDelimiter('.', Result) > 0) then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

/// <summary>Namen vor dem Doppelpunkt ohne const/var/out/constref/[ref].</summary>
function GroupNames(const AGroupText: string): string;
var
  mColon: Integer;
  mModifier: string;
begin
  mColon := Pos(':', AGroupText);
  if mColon = 0 then
  begin
    Result := AGroupText;
  end
  else
  begin
    Result := Copy(AGroupText, 1, mColon - 1);
  end;
  for mModifier in cParameterModifiers do
  begin
    if StartsText(mModifier, Result) then
    begin
      Delete(Result, 1, Length(mModifier));
    end;
  end;
end;

function NewParameter(AStart, AEnd: Integer; const ATypeName: string): TSignatureParameter;
begin
  Result := Default(TSignatureParameter);
  Result.StartIndex := AStart;
  Result.EndIndex := AEnd;
  Result.TypeName := ATypeName;
end;

/// <summary>Parameter der Gruppe AText[AFrom..ATo) (1-basiert, ATo exklusiv). A, B: Integer gibt je Name einen
/// Parameter, hervorgehoben wird nur der Name.</summary>
function GroupParameters(const AText: string; AFrom, ATo: Integer): TArray<TSignatureParameter>;
var
  mGroup, mNames, mTypeName, mItem: string;
  mFrom, mOffset, mSearch: Integer;
begin
  Result := nil;
  mGroup := Copy(AText, AFrom, ATo - AFrom);
  mFrom := AFrom + Length(mGroup) - Length(TrimLeft(mGroup));
  mGroup := Trim(mGroup);
  if mGroup = '' then
  begin
    Exit;
  end;
  mTypeName := GroupType(mGroup);
  mNames := GroupNames(mGroup);
  if Pos(',', mNames) = 0 then
  begin
    Result := TArray<TSignatureParameter>.Create(NewParameter(mFrom - 1, mFrom - 1 + Length(mGroup), mTypeName));
    Exit;
  end;
  mSearch := mFrom;
  for mItem in mNames.Split([',']) do
  begin
    mOffset := PosEx(Trim(mItem), AText, mSearch);
    Result := Result + [NewParameter(mOffset - 1, mOffset - 1 + Length(Trim(mItem)), mTypeName)];
    mSearch := mOffset + Length(Trim(mItem));
  end;
end;

/// <summary>Parameter zwischen den Klammern an AOpen und AClose, Gruppen durch ; getrennt.</summary>
function ParameterGroups(const AText: string; AOpen, AClose: Integer): TArray<TSignatureParameter>;
var
  mIndex, mStart, mDepth: Integer;
begin
  Result := nil;
  mStart := AOpen + 1;
  mDepth := 0;
  for mIndex := AOpen + 1 to AClose do
  begin
    if (mIndex = AClose) or (AText[mIndex] = ';') and (mDepth = 0) then
    begin
      Result := Result + GroupParameters(AText, mStart, mIndex);
      mStart := mIndex + 1;
    end
    else if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
    end;
  end;
end;

class function TLspSignatureHelp.ParseSignature(const ALines: TArray<string>; ALine, AColumn: Integer): TSignature;
var
  mText: string;
  mOpen, mClose: Integer;
begin
  Result := Default(TSignature);
  Result.Fits := True;
  Result.Mismatch := -1;
  mText := CollapseSpaces(CollectHeader(ALines, ALine, AColumn));
  Result.Qualified := StripQualifier(mText);
  Result.Text := mText;
  mOpen := Pos('(', mText);
  if mOpen = 0 then
  begin
    Exit;
  end;
  mClose := ClosingParen(mText, mOpen);
  if mClose > 0 then
  begin
    Result.Parameters := ParameterGroups(mText, mOpen, mClose);
  end;
end;

/// <summary>Name ohne Unit bzw. umgebenden Typ davor (System.Boolean → Boolean); Generics bleiben.</summary>
function LastPart(const AName: string): string;
begin
  if Pos('<', AName) > 0 then
  begin
    Result := AName;
  end
  else
  begin
    Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
  end;
end;

/// <summary>Zeichen in einem String-Literal ('it''s' = 4); -1 bei mehrzeiligen.</summary>
function LiteralLength(const AText: string): Integer;
begin
  if StartsStr('''''''', AText) then
  begin
    Exit(-1);
  end;
  Result := Length(StringReplace(Copy(AText, 2, Length(AText) - 2), '''''', '''', [rfReplaceAll]));
end;

/// <summary>Tokens ATokens[AFirst..ALast] ohne Kommentare und Direktiven.</summary>
function CodeTokens(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TArray<TPascalToken>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := Max(AFirst, 0) to Min(ALast, High(ATokens)) do
  begin
    if not IsSkipped(ATokens[mIndex]) then
    begin
      Result := Result + [ATokens[mIndex]];
    end;
  end;
end;

/// <summary>Zeichen im Literal AToken; -1 bei mehrzeiligen Strings, cNoLiteral bei anderen Tokens.</summary>
function LiteralChars(const AToken: TPascalToken): Integer;
begin
  if AToken.Kind = TPascalTokenKind.StringLiteral then
  begin
    Result := LiteralLength(AToken.Text);
  end
  else if AToken.Kind = TPascalTokenKind.CharLiteral then
  begin
    Result := 1;
  end
  else
  begin
    Result := cNoLiteral;
  end;
end;

/// <summary>Zeichen und Strings, auch zusammengesetzt wie 'a'#13'b'; True, wenn AParts so bestimmt ist. Ein offenes
/// Literal wird noch getippt: True mit AType = ''.</summary>
function TextLiteralType(const AParts: TArray<TPascalToken>; out AType: string): Boolean;
var
  mToken: TPascalToken;
  mChars, mCount: Integer;
  mLiteral: Boolean;
begin
  Result := True;
  AType := '';
  mChars := 0;
  mLiteral := True;
  for mToken in AParts do
  begin
    if not mToken.Terminated then
    begin
      Exit;
    end;
    mCount := LiteralChars(mToken);
    if mCount = -1 then
    begin
      AType := 'string';
      Exit;
    end;
    if mCount = cNoLiteral then
    begin
      mLiteral := False;
    end
    else
    begin
      Inc(mChars, mCount);
    end;
  end;
  Result := mLiteral;
  if Result and (mChars = 1) then
  begin
    AType := 'Char';
  end
  else if Result then
  begin
    AType := 'string';
  end;
end;

function IsFloatText(const AText: string): Boolean;
begin
  Result := not CharInSet(AText[1], ['$', '%']) and ((Pos('.', AText) > 0) or ContainsText(AText, 'e'));
end;

/// <summary>Zahlen, auch mit Vorzeichen.</summary>
function NumberType(const AParts: TArray<TPascalToken>; out AType: string): Boolean;
var
  mStart: Integer;
begin
  AType := '';
  mStart := 0;
  if (Length(AParts) = 2) and (AParts[0].IsSymbol('-') or AParts[0].IsSymbol('+')) then
  begin
    mStart := 1;
  end;
  Result := (Length(AParts) = mStart + 1) and (AParts[mStart].Kind = TPascalTokenKind.Number);
  if Result and IsFloatText(AParts[mStart].Text) then
  begin
    AType := 'Double';
  end
  else if Result then
  begin
    AType := 'Integer';
  end;
end;

/// <summary>nil, True oder False allein.</summary>
function KeywordType(const AParts: TArray<TPascalToken>; out AType: string): Boolean;
begin
  AType := '';
  if Length(AParts) = 1 then
  begin
    if AParts[0].IsKeyword('nil') then
    begin
      AType := 'nil';
    end
    else if (AParts[0].Kind = TPascalTokenKind.Identifier) and (SameText(AParts[0].Text, 'True') or
      SameText(AParts[0].Text, 'False')) then
    begin
      AType := 'Boolean';
    end;
  end;
  Result := AType <> '';
end;

/// <summary>Menge, Zeichen, String, Zahl, nil oder Boolean; True, wenn AParts damit bestimmt ist.</summary>
function LiteralArgumentType(const AParts: TArray<TPascalToken>; out AType: string): Boolean;
begin
  Result := True;
  if AParts[0].IsSymbol('[') then
  begin
    AType := '[]';
  end
  else if not TextLiteralType(AParts, AType) and not NumberType(AParts, AType) then
  begin
    Result := KeywordType(AParts, AType);
  end;
end;

/// <summary>Bezeichner oder Kette A.B.C.</summary>
function IsNameChain(const AParts: TArray<TPascalToken>): Boolean;
var
  mIndex: Integer;
begin
  Result := Odd(Length(AParts));
  for mIndex := 0 to High(AParts) do
  begin
    if Odd(mIndex) then
    begin
      Result := Result and AParts[mIndex].IsSymbol('.');
    end
    else
    begin
      Result := Result and (AParts[mIndex].Kind = TPascalTokenKind.Identifier);
    end;
  end;
end;

/// <summary>Typ eines aufgelösten Bezeichners. Aufzählungswerte tragen ihren Typ als Container; Routinen bleiben
/// unbekannt (Methodenzeiger).</summary>
function ResolvedType(const AResolved: TResolvedSymbol): string;
begin
  Result := '';
  if not (AResolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) then
  begin
    Exit;
  end;
  if AResolved.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    Result := LastPart(AResolved.Container);
  end
  else if AResolved.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
    TIndexSymbolKind.Constant] then
  begin
    Result := LastPart(Trim(AResolved.TypeName));
  end;
end;

class function TLspSignatureHelp.ArgumentType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  AFirst, ALast: Integer): string;
var
  mParts: TArray<TPascalToken>;
begin
  Result := '';
  if (ATree = nil) or (AFirst > ALast) then
  begin
    Exit;
  end;
  mParts := CodeTokens(ATree.Tokens, AFirst, ALast);
  if (Length(mParts) = 0) or LiteralArgumentType(mParts, Result) then
  begin
    Exit;
  end;
  // Bezeichner oder Kette A.B.C; alles andere (Aufrufe, Ausdrücke) bleibt unbekannt.
  if (AResolver <> nil) and IsNameChain(mParts) then
  begin
    Result := ResolvedType(AResolver.Resolve(ATree, AFileName, mParts[High(mParts)].StartPos));
  end;
end;

class procedure TLspSignatureHelp.Match(var ASignature: TSignature; const AArgumentTypes: TArray<string>);
var
  mIndex: Integer;
begin
  ASignature.Fits := True;
  ASignature.Mismatch := -1;
  // Zu viele Argumente zählt der Hint selbst; hier nur die Typen.
  for mIndex := 0 to Min(High(AArgumentTypes), High(ASignature.Parameters)) do
  begin
    if not TResolverText.ArgumentFits(ASignature.Parameters[mIndex].TypeName, AArgumentTypes[mIndex]) then
    begin
      ASignature.Fits := False;
      ASignature.Mismatch := mIndex;
      Exit;
    end;
  end;
end;

/// <summary>Benennt der Parametertext AText (etwa "const A, B: Integer") den Parameter AName?</summary>
function NamesParameter(const AText, AName: string): Boolean;
var
  mEnd: string;
begin
  Result := SameText(AText, AName);
  for mEnd in cNameEnds do
  begin
    Result := Result or StartsText(AName + mEnd, AText) or ContainsText(AText, ' ' + AName + mEnd);
  end;
end;

procedure ApplyDocumentation(var ASignature: TSignature; const ADoc: TXmlDoc);
var
  mSection: TXmlDocSection;
  mName, mText: string;
  mIndex: Integer;
begin
  // Alles außer den Parametern an die Signatur, <param> an den passenden Parameter. Klartext: Der Hint
  // des Plugins und der Client von RAD Studio zeigen kein Markdown; Namen aus cref bleiben erhalten.
  ASignature.Documentation := ADoc.ToPlainText(False);
  for mSection in ADoc.Sections do
  begin
    if mSection.Kind <> TXmlDocSectionKind.Param then
    begin
      Continue;
    end;
    mName := mSection.Name;
    for mIndex := 0 to High(ASignature.Parameters) do
    begin
      mText := Copy(ASignature.Text, ASignature.Parameters[mIndex].StartIndex + 1,
        ASignature.Parameters[mIndex].EndIndex - ASignature.Parameters[mIndex].StartIndex);
      if NamesParameter(mText, mName) then
      begin
        ASignature.Parameters[mIndex].Documentation := mSection.Text;
        Break;
      end;
    end;
  end;
end;

/// <summary>Erste Überladung mit genug Parametern für AActiveParameter.</summary>
function ActiveSignatureOf(const ASignatures: TArray<TSignature>; AActiveParameter: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to High(ASignatures) do
  begin
    if Length(ASignatures[mIndex].Parameters) > AActiveParameter then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Steht der Name an APosition in einer Attributklammer ("[TestCase(")? ANameToken: sein Token.</summary>
function AttributeName(ATree: TSyntaxTree; const APosition: TTextPosition; out ANameToken: TPascalToken): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mPrev: Integer;
begin
  Result := False;
  mTokens := ATree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].StartPos.Line = APosition.Line) and
      (mTokens[mIndex].StartPos.Character = APosition.Character) then
    begin
      mPrev := PreviousCodeToken(mTokens, mIndex);
      ANameToken := mTokens[mIndex];
      Exit((mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and TAttributes.InBracket(mTokens, mPrev));
    end;
  end;
end;

/// <summary>Attribut (#465): Konstruktor der Attributklasse hinter dem Namen; [Foo] meint zuerst FooAttribute.
/// </summary>
function AttributeConstructor(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; const AResolved: TResolvedSymbol; out ACtor: TResolvedSymbol): Boolean;
var
  mNameToken: TPascalToken;
  mAttributeClass: TResolvedSymbol;
begin
  Result := False;
  ACtor := Default(TResolvedSymbol);
  if not AttributeName(ATree, APosition, mNameToken) then
  begin
    Exit;
  end;
  if not AResolver.Queries.AttributeClassOf(AResolved, mAttributeClass) and
    not AResolver.Queries.AttributeClassOf(AResolver.ResolveChain(ATree, AFileName,
      TArray<string>.Create(TAttributes.ShortName(mNameToken.Text) + 'Attribute'), mNameToken.Offset), mAttributeClass) then
  begin
    Exit;
  end;
  Result := AResolver.DeclaredMember(mAttributeClass, 'Create', ACtor) and
    (ACtor.SymbolKind = TIndexSymbolKind.Constructor_);
end;

/// <summary>Routinen der Unit System ohne Quelltext (#880): Signaturen aus der eingebauten Liste.</summary>
function IntrinsicSignatures(const AName: string): TArray<TSignature>;
var
  mIntrinsic: TSystemIntrinsic;
  mSignature: TSignature;
begin
  Result := nil;
  for mIntrinsic in TSystemIntrinsics.Find(AName) do
  begin
    if mIntrinsic.Kind = TIndexSymbolKind.Routine then
    begin
      mSignature := TLspSignatureHelp.ParseSignature([mIntrinsic.Declaration], 0, 0);
      if mSignature.Text = '' then
      begin
        Continue;
      end;
      mSignature.Documentation := mIntrinsic.Documentation;
      Result := Result + [mSignature];
    end;
  end;
end;

/// <summary>Erste verträgliche Überladung mit genug Parametern, sonst die erste mit genug Parametern.</summary>
function PreferredSignature(const ASignatures: TArray<TSignature>; AActiveParameter: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ASignatures) do
  begin
    if (Length(ASignatures[mIndex].Parameters) > AActiveParameter) and ASignatures[mIndex].Fits then
    begin
      Exit(mIndex);
    end;
  end;
  Result := ActiveSignatureOf(ASignatures, AActiveParameter);
end;

{ THelpRun }

constructor THelpRun.Create(const ARequest: TSignatureHelpRequest; const APosition: TTextPosition);
begin
  inherited Create;
  FRequest := ARequest;
  FPosition := APosition;
end;

procedure THelpRun.ResolveSite;
var
  mCtor: TResolvedSymbol;
begin
  FResolved := FRequest.Resolver.Resolve(FRequest.Tree, FRequest.FileName, FSite.NamePosition);
  // Attribut (#465): [TestCase('Name', |] zeigt den Konstruktor von TestCaseAttribute.
  if AttributeConstructor(FRequest.Resolver, FRequest.Tree, FRequest.FileName, FSite.NamePosition, FResolved,
    mCtor) then
  begin
    FResolved := mCtor;
  end;
end;

function THelpRun.IntrinsicHelp: TSignatureHelp;
var
  mName: string;
begin
  // Unbekannt: vielleicht eine Routine von System ohne Quelltext (SetLength, Inc ...; #880).
  Result := Default(TSignatureHelp);
  if TSystemIntrinsics.NameAt(FRequest.Tree, FSite.NamePosition, mName) then
  begin
    Result.Signatures := IntrinsicSignatures(mName);
    Result.Intrinsic := True;
    Result.ActiveParameter := FSite.ActiveParameter;
    Result.ActiveSignature := ActiveSignatureOf(Result.Signatures, FSite.ActiveParameter);
  end;
end;

function THelpRun.ReadLines: Boolean;
var
  mText: string;
begin
  if SameText(FResolved.FileName, FRequest.FileName) then
  begin
    mText := FRequest.TreeText;
  end
  else if not (Assigned(FRequest.ReadText) and FRequest.ReadText(FResolved.FileName, mText)) then
  begin
    Exit(False);
  end;
  FLines := TTextLines.SplitLines(mText);
  Result := True;
end;

procedure THelpRun.AddStart(const APosition: TTextPosition; const ASymbol: TResolvedSymbol);
begin
  FStarts := FStarts + [APosition];
  FStartSymbols := FStartSymbols + [ASymbol];
end;

function THelpRun.IsOverload(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind in cRoutineKinds) and SameText(ASymbol.Name, FResolved.Name) and
    SameText(ASymbol.Container, FResolved.Container);
end;

function THelpRun.OwnerUnit(out AOwner: TUnitIndex): Boolean;
begin
  Result := True;
  if SameText(FResolved.FileName, FRequest.FileName) then
  begin
    AOwner := TIndexExtractor.Extract(FRequest.Tree, FRequest.FileName);
  end
  else
  begin
    Result := TIndexFiles.UnitOf(FRequest.Index, FResolved.FileName, AOwner);
  end;
end;

function THelpRun.CollectUnitStarts: Boolean;
var
  mOwner: TUnitIndex;
  mSymbol: TIndexSymbol;
  mHasInterface: Boolean;
begin
  Result := OwnerUnit(mOwner);
  if not Result then
  begin
    Exit;
  end;
  mHasInterface := False;
  for mSymbol in mOwner.Symbols do
  begin
    mHasInterface := mHasInterface or (IsOverload(mSymbol) and mSymbol.InInterface);
  end;
  // Rümpfe globaler Routinen aus interface weglassen: sie dürfen die Parameter auslassen.
  for mSymbol in mOwner.Symbols do
  begin
    if IsOverload(mSymbol) and (mSymbol.InInterface or not mHasInterface) and
      SameText(mOwner.SymbolFile(mSymbol), FResolved.FileName) then
    begin
      AddStart(mSymbol.Range.StartPos, TResolvedSymbol.FromIndex(mOwner, mSymbol));
    end;
  end;
end;

function THelpRun.CollectStarts: Boolean;
var
  mNested: TResolvedSymbol;
begin
  // Überladungen: gleicher Name im selben Typ bzw. auf Unit-Ebene derselben Unit.
  Result := True;
  if FResolved.Kind = TResolvedKind.Local then
  begin
    // Verschachtelte Routinen (#881): alle Überladungen in der umgebenden Routine, vor und hinter dem Aufruf.
    for mNested in FRequest.Resolver.Candidates.LocalOverloads(FResolved) do
    begin
      AddStart(mNested.Range.StartPos, mNested);
    end;
  end
  else
  begin
    Result := CollectUnitStarts;
  end;
end;

function THelpRun.BoundTypes: TArray<string>;
var
  mBinding: string;
begin
  // Typargumente ohne Unit davor ("T=TKunde" statt "T=Listen.TKunde").
  Result := nil;
  for mBinding in FResolved.Bindings do
  begin
    Result := Result + [Copy(mBinding, 1, Pos('=', mBinding)) +
      FRequest.Resolver.Queries.UnqualifyType(Copy(mBinding, Pos('=', mBinding) + 1, MaxInt))];
  end;
end;

function THelpRun.HeaderLines(const AStart: TTextPosition; const ABindings: TArray<string>): TArray<string>;
var
  mLine: Integer;
begin
  // Gebundene Typparameter (#450): FItems: TObjectList<TKunde> zeigt Add(const Value: TKunde). Nur die
  // Zeilen des Kopfs; die Spalte des Anfangs bleibt, weil davor kein Typparameter steht.
  Result := FLines;
  if Length(ABindings) = 0 then
  begin
    Exit;
  end;
  Result := Copy(FLines);
  for mLine := AStart.Line to Min(High(Result), AStart.Line + cMaxHeaderLines) do
  begin
    Result[mLine] := TInterfaceStubs.SubstituteWords(Result[mLine], ABindings);
  end;
end;

function THelpRun.Signatures: TArray<TSignature>;
var
  mIndex: Integer;
  mStart: TTextPosition;
  mSignature: TSignature;
  mKey: string;
  mSeen, mBindings: TArray<string>;
  mReader: TDocReadText;
begin
  Result := nil;
  mSeen := nil;
  mBindings := BoundTypes;
  mReader := TLspDocumentation.Reader(FRequest.FileName, FRequest.TreeText, FRequest.ReadText);
  for mIndex := 0 to High(FStarts) do
  begin
    mStart := FStarts[mIndex];
    if (mStart.Line < 0) or (mStart.Line > High(FLines)) then
    begin
      Continue;
    end;
    mSignature := TLspSignatureHelp.ParseSignature(HeaderLines(mStart, mBindings), mStart.Line, mStart.Character);
    // Deklaration und Rumpf derselben Routine nur einmal; die Deklaration steht vorn und trägt die Doku.
    mKey := UpperCase(StringReplace(mSignature.Text, ' ', '', [rfReplaceAll]));
    if (mSignature.Text = '') or mSignature.Qualified or MatchStr(mKey, mSeen) then
    begin
      Continue;
    end;
    mSeen := mSeen + [mKey];
    ApplyDocumentation(mSignature, TLspDocumentation.Load(FRequest.Resolver, FStartSymbols[mIndex], FLines,
      mStart.Line, mReader));
    Result := Result + [mSignature];
  end;
end;

procedure THelpRun.MatchArguments(var ASignatures: TArray<TSignature>);
var
  mTypes: TArray<string>;
  mIndex: Integer;
begin
  // Argumenttypen (#498), erst nach dem Einsammeln der Überladungen aufgelöst.
  mTypes := nil;
  for mIndex := 0 to High(FSite.ArgumentFirst) do
  begin
    mTypes := mTypes + [TLspSignatureHelp.ArgumentType(FRequest.Resolver, FRequest.Tree, FRequest.FileName,
      FSite.ArgumentFirst[mIndex], FSite.ArgumentLast[mIndex])];
  end;
  for mIndex := 0 to High(ASignatures) do
  begin
    TLspSignatureHelp.Match(ASignatures[mIndex], mTypes);
  end;
end;

procedure THelpRun.AddFormat(var AHelp: TSignatureHelp);
var
  mRoutine: TFormatRoutine;
  mCall: TSignatureFormatCall;
begin
  // Platzhalter einer Formatroutine (#451), nach dem voll qualifizierten Namen.
  if (Length(AHelp.Signatures) = 0) or not TFormatRoutines.FindQualified(FRequest.Routines,
    FResolved.UnitName + '.' + FResolved.QualifiedName, mRoutine) then
  begin
    Exit;
  end;
  mCall := Default(TSignatureFormatCall);
  mCall.Resolver := FRequest.Resolver;
  mCall.Tree := FRequest.Tree;
  mCall.FileName := FRequest.FileName;
  mCall.Firsts := FSite.ArgumentFirst;
  mCall.Lasts := FSite.ArgumentLast;
  mCall.ActiveParameter := FSite.ActiveParameter;
  AHelp.Format := TSignatureFormats.Analyze(mCall, mRoutine);
end;

function THelpRun.Run: TSignatureHelp;
begin
  Result := Default(TSignatureHelp);
  FSite := TLspSignatureHelp.CallSiteAt(FRequest.Tree, FPosition);
  if not FSite.Found then
  begin
    Exit;
  end;
  ResolveSite;
  if not (FResolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) then
  begin
    Exit(IntrinsicHelp);
  end;
  if (FResolved.SymbolKind in cRoutineKinds) and ReadLines and CollectStarts then
  begin
    Result.Signatures := Signatures;
    Result.ActiveParameter := FSite.ActiveParameter;
    MatchArguments(Result.Signatures);
    Result.ActiveSignature := PreferredSignature(Result.Signatures, FSite.ActiveParameter);
    AddFormat(Result);
  end;
end;

class function TLspSignatureHelp.HelpAt(const ARequest: TSignatureHelpRequest;
  const APosition: TTextPosition): TSignatureHelp;
var
  mRun: THelpRun;
begin
  mRun := THelpRun.Create(ARequest, APosition);
  try
    Result := mRun.Run;
  finally
    mRun.Free;
  end;
end;

class function TLspSignatureHelp.ToJson(const AHelp: TSignatureHelp): TJSONValue;
var
  mSignatures, mParameters, mLabelRange: TJSONArray;
  mSignature, mParameter, mDocumentation, mData, mFormatJson: TJSONObject;
  mItem: TSignature;
  mIndex: Integer;
begin
  if not AHelp.Found then
  begin
    Exit(TJSONNull.Create);
  end;
  mSignatures := TJSONArray.Create;
  for mItem in AHelp.Signatures do
  begin
    mSignature := TJSONObject.Create;
    mSignatures.AddElement(mSignature);
    mSignature.AddPair('label', mItem.Text);
    if mItem.Documentation <> '' then
    begin
      mDocumentation := TJSONObject.Create;
      mDocumentation.AddPair('kind', 'markdown');
      mDocumentation.AddPair('value', mItem.Documentation);
      mSignature.AddPair('documentation', mDocumentation);
    end;
    mParameters := TJSONArray.Create;
    mSignature.AddPair('parameters', mParameters);
    for mIndex := 0 to High(mItem.Parameters) do
    begin
      mParameter := TJSONObject.Create;
      mParameters.AddElement(mParameter);
      mLabelRange := TJSONArray.Create;
      mLabelRange.Add(mItem.Parameters[mIndex].StartIndex);
      mLabelRange.Add(mItem.Parameters[mIndex].EndIndex);
      mParameter.AddPair('label', mLabelRange);
      if mItem.Parameters[mIndex].Documentation <> '' then
      begin
        mParameter.AddPair('documentation', mItem.Parameters[mIndex].Documentation);
      end;
    end;
    // Verträglichkeit der bisherigen Argumente (#498), für den Parameter-Hint des Plugins.
    mData := TJSONObject.Create;
    mData.AddPair('fits', TJSONBool.Create(mItem.Fits));
    mData.AddPair('mismatch', TJSONNumber.Create(mItem.Mismatch));
    mSignature.AddPair('data', mData);
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('signatures', mSignatures);
  TJSONObject(Result).AddPair('activeSignature', TJSONNumber.Create(AHelp.ActiveSignature));
  TJSONObject(Result).AddPair('activeParameter', TJSONNumber.Create(AHelp.ActiveParameter));
  // Platzhalter (#451), Erweiterung von Atlas.
  mFormatJson := TSignatureFormats.ToJson(AHelp.Format);
  if mFormatJson <> nil then
  begin
    TJSONObject(Result).AddPair('format', mFormatJson);
  end;
end;

function TLspSignatureHelp.Handle(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mPositionValue: TJSONValue;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mHelp: TSignatureHelp;
  mRequest: TSignatureHelpRequest;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TSignatureHelpText.FieldsTextDocumentUriAndPosition].Text);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mTree := mShared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    mRequest := TSignatureHelpRequest.Create(mResolver, FIndex, mTree, mDocument.Text, TDocumentUris.ToPath(mUri),
      FReadText);
    if Assigned(FFormatRoutinesFor) then
    begin
      mRequest.Routines := FFormatRoutinesFor(mUri);
    end;
    mHelp := HelpAt(mRequest, TLspPositions.ReadPosition(mPositionValue));
  finally
    mResolver.Free;
  end;
  Result := ToJson(mHelp);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.SignatureHelp', cTexts);

end.
