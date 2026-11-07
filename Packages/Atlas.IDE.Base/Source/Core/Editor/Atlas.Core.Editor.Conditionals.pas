unit Atlas.Core.Editor.Conditionals;

// Bedingte Übersetzung für die eigenen Lexer des Plugins (#775 und folgende):
// Welche Zweige von $IFDEF, $IFNDEF, $IF, $ELSEIF, $ELSE und $ENDIF/$IFEND
// aktiv sind, mit $DEFINE und $UNDEF in aktiven Zweigen. Ohne diese Auswertung
// sahen die Lexer alle Zweige zugleich; stehen dort alternative Rümpfe
// ({$IFDEF MSWINDOWS} begin … end; {$ELSE} begin … end; {$ENDIF}), geriet der
// Aufbau durcheinander und der Methodenwechsel fand ab dort keine Routine mehr.
// $IF versteht Defined(X), Declared(X), CompilerVersion, RTLVersion, Zahlen,
// Vergleiche, not, and, or und Klammern; Unbekanntes gilt als wahr, $IFOPT als
// falsch. Je Bedingung ist genau ein Zweig aktiv, wie beim Compiler.
// Reine Logik ohne VCL und OTA; die Symbole bringt der Aufrufer mit
// (TTextDefines.Predefined und die Defines des Projekts).

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasConditionals = class
  private type
    TFrame = record
      ParentActive: Boolean;
      Taken: Boolean;
      Active: Boolean;
    end;
  private
    FDefines: TDictionary<string, Boolean>;
    FFrames: TList<TFrame>;
    FCompilerVersion: Double;
    function Evaluate(const AExpression: string): Boolean;
    /// <summary>Bedingung von $IFDEF, $IFNDEF bzw. $IF; $IFOPT kennt nur der Compiler (falsch).</summary>
    function BranchCondition(const AName, AArgument: string): Boolean;
    procedure OpenBranch(const AName, AArgument: string);
    /// <summary>$ELSEIF: aktiv, wenn noch kein Zweig gewählt ist und die Bedingung gilt.</summary>
    procedure NextBranch(const AArgument: string);
    /// <summary>$ELSE: aktiv, wenn noch kein Zweig gewählt ist.</summary>
    procedure LastBranch;
    procedure CloseBranch;
    procedure DefineSymbol(const AArgument: string);
    procedure UndefineSymbol(const AArgument: string);
  public
    /// <summary>ADefines: gesetzte Symbole (Groß-/Kleinschreibung egal); ACompilerVersion z. B. 37.0.</summary>
    constructor Create(const ADefines: TArray<string>; ACompilerVersion: Double);
    destructor Destroy; override;
    /// <summary>Direktive ohne Klammern und ohne "$", z. B. "IFDEF FPC"; True, wenn sie die bedingte Übersetzung
    /// betrifft (dann ist sie verarbeitet).</summary>
    function Handle(const ADirective: string): Boolean;
    /// <summary>Liegt die aktuelle Stelle in einem aktiven Zweig?</summary>
    function Active: Boolean;
    /// <summary>Ist ASymbol gesetzt?</summary>
    function Defined(const ASymbol: string): Boolean;
    property CompilerVersion: Double read FCompilerVersion;
  end;

implementation

uses
  System.Character;

type
  TExprTokenKind = (etIdent, etNumber, etSymbol, etEnd);

  TExprToken = record
    Kind: TExprTokenKind;
    Text: string;
  end;

  /// <summary>Ausdruck hinter $IF bzw. $ELSEIF; rekursiver Abstieg über or, and, not und Vergleiche.</summary>
  TExprParser = class
  private
    FOwner: TAtlasConditionals;
    FTokens: TArray<TExprToken>;
    FPos: Integer;
    procedure Scan(const AText: string);
    function Peek: TExprToken;
    function Take: TExprToken;
    function IsWord(const AWord: string): Boolean;
    function IsSymbol(const ASymbol: string): Boolean;
    function ParseOr: Double;
    function ParseAnd: Double;
    function ParseNot: Double;
    function ParseCompare: Double;
    /// <summary>Defined(…) bzw. Declared(…) nach dem Wort AWord.</summary>
    function ParseDefined(const AWord: string): Double;
    function ParseIdent(const AWord: string): Double;
    function ParseValue: Double;
  public
    constructor Create(AOwner: TAtlasConditionals; const AText: string);
    function Run: Boolean;
  end;

const
  /// <summary>Wert für Unbekanntes: gilt als wahr bzw. als erfüllter Vergleich.</summary>
  cUnknownValue = 1.0;

function IsOneOf(const AText: string; const AList: array of string): Boolean;
var
  mItem: string;
begin
  Result := False;
  for mItem in AList do
  begin
    Result := Result or (AText = mItem);
  end;
end;

/// <summary>Zwei Zeichen lange Vergleiche: "&lt;=", "&gt;=", "&lt;&gt;".</summary>
function IsTwoCharSymbol(const AText: string; AStart: Integer): Boolean;
begin
  Result := (AStart < Length(AText)) and CharInSet(AText[AStart], ['<', '>']) and
    CharInSet(AText[AStart + 1], ['=', '>']);
end;

/// <summary>Token ab AIndex; AIndex steht danach dahinter.</summary>
function ScanToken(const AText: string; var AIndex: Integer): TExprToken;
var
  mStart: Integer;
begin
  mStart := AIndex;
  if AText[AIndex].IsLetter or (AText[AIndex] = '_') then
  begin
    while (AIndex <= Length(AText)) and (AText[AIndex].IsLetterOrDigit or CharInSet(AText[AIndex], ['_', '.'])) do
    begin
      Inc(AIndex);
    end;
    Result.Kind := etIdent;
  end
  else if AText[AIndex].IsDigit then
  begin
    while (AIndex <= Length(AText)) and (AText[AIndex].IsDigit or (AText[AIndex] = '.')) do
    begin
      Inc(AIndex);
    end;
    Result.Kind := etNumber;
  end
  else
  begin
    Inc(AIndex);
    if IsTwoCharSymbol(AText, mStart) then
    begin
      Inc(AIndex);
    end;
    Result.Kind := etSymbol;
  end;
  Result.Text := Copy(AText, mStart, AIndex - mStart);
end;

function IsCompareOperator(const AToken: TExprToken): Boolean;
begin
  Result := (AToken.Kind = etSymbol) and IsOneOf(AToken.Text, ['=', '<>', '<', '>', '<=', '>=']);
end;

/// <summary>Name und Argument einer Direktive: "IFDEF FPC" → IFDEF, FPC.</summary>
procedure SplitDirective(const ADirective: string; out AName, AArgument: string);
var
  mText: string;
  mSplit: Integer;
begin
  mText := Trim(ADirective);
  mSplit := 1;
  while (mSplit <= Length(mText)) and (mText[mSplit].IsLetterOrDigit or (mText[mSplit] = '_')) do
  begin
    Inc(mSplit);
  end;
  AName := UpperCase(Copy(mText, 1, mSplit - 1));
  AArgument := Trim(Copy(mText, mSplit, MaxInt));
end;

function Truth(ACondition: Boolean): Double;
begin
  if ACondition then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

{ TExprParser }

constructor TExprParser.Create(AOwner: TAtlasConditionals; const AText: string);
begin
  inherited Create;
  FOwner := AOwner;
  Scan(AText);
  FPos := 0;
end;

procedure TExprParser.Scan(const AText: string);
var
  mIndex: Integer;
begin
  FTokens := nil;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if AText[mIndex].IsWhiteSpace then
    begin
      Inc(mIndex);
    end
    else
    begin
      FTokens := FTokens + [ScanToken(AText, mIndex)];
    end;
  end;
end;

function TExprParser.Peek: TExprToken;
begin
  if FPos <= High(FTokens) then
  begin
    Result := FTokens[FPos];
  end
  else
  begin
    Result.Kind := etEnd;
    Result.Text := '';
  end;
end;

function TExprParser.Take: TExprToken;
begin
  Result := Peek;
  if FPos <= High(FTokens) then
  begin
    Inc(FPos);
  end;
end;

function TExprParser.IsWord(const AWord: string): Boolean;
begin
  Result := (Peek.Kind = etIdent) and SameText(Peek.Text, AWord);
end;

function TExprParser.IsSymbol(const ASymbol: string): Boolean;
begin
  Result := (Peek.Kind = etSymbol) and (Peek.Text = ASymbol);
end;

function TExprParser.Run: Boolean;
begin
  Result := ParseOr <> 0;
end;

function TExprParser.ParseOr: Double;
var
  mRight: Double;
begin
  Result := ParseAnd;
  while IsWord('or') do
  begin
    Take;
    mRight := ParseAnd;
    Result := Truth((Result <> 0) or (mRight <> 0));
  end;
end;

function TExprParser.ParseAnd: Double;
var
  mRight: Double;
begin
  Result := ParseNot;
  while IsWord('and') do
  begin
    Take;
    mRight := ParseNot;
    Result := Truth((Result <> 0) and (mRight <> 0));
  end;
end;

function TExprParser.ParseNot: Double;
begin
  if IsWord('not') then
  begin
    Take;
    Result := Truth(ParseNot = 0);
    Exit;
  end;
  Result := ParseCompare;
end;

function TExprParser.ParseCompare: Double;
var
  mOp: string;
  mRight: Double;
begin
  Result := ParseValue;
  if not IsCompareOperator(Peek) then
  begin
    Exit;
  end;
  mOp := Take.Text;
  mRight := ParseValue;
  // $IF vergleicht wie dcc exakt; eine Toleranz würde Zweige anders wählen als der Compiler.
  if mOp = '=' then
  begin
    Result := Truth(Result = mRight); // lsp-ignore: float-equality
  end
  else if mOp = '<>' then
  begin
    Result := Truth(Result <> mRight); // lsp-ignore: float-equality
  end
  else if mOp = '<' then
  begin
    Result := Truth(Result < mRight);
  end
  else if mOp = '>' then
  begin
    Result := Truth(Result > mRight);
  end
  else if mOp = '<=' then
  begin
    Result := Truth(Result <= mRight);
  end
  else
  begin
    Result := Truth(Result >= mRight);
  end;
end;

function TExprParser.ParseDefined(const AWord: string): Double;
var
  mName: string;
begin
  Result := cUnknownValue;
  mName := '';
  if IsSymbol('(') then
  begin
    Take;
    while not ((Peek.Kind = etEnd) or IsSymbol(')')) do
    begin
      mName := mName + Take.Text;
    end;
    Take;
  end;
  // Declared kennt nur der Compiler: bleibt wahr.
  if SameText(AWord, 'Defined') then
  begin
    Result := Truth(FOwner.Defined(mName));
  end;
end;

function TExprParser.ParseIdent(const AWord: string): Double;
begin
  Result := cUnknownValue;
  if SameText(AWord, 'Defined') or SameText(AWord, 'Declared') then
  begin
    Result := ParseDefined(AWord);
  end
  else if SameText(AWord, 'CompilerVersion') or SameText(AWord, 'RTLVersion') then
  begin
    Result := FOwner.CompilerVersion;
  end
  else if SameText(AWord, 'True') then
  begin
    Result := 1;
  end
  else if SameText(AWord, 'False') then
  begin
    Result := 0;
  end;
end;

function TExprParser.ParseValue: Double;
var
  mToken: TExprToken;
begin
  mToken := Take;
  Result := cUnknownValue;
  // Ende des Ausdrucks und Unbekanntes bleiben unbekannt.
  if mToken.Kind = etNumber then
  begin
    if not TryStrToFloat(mToken.Text, Result, TFormatSettings.Invariant) then
    begin
      Result := cUnknownValue;
    end;
  end
  else if mToken.Kind = etIdent then
  begin
    Result := ParseIdent(mToken.Text);
  end
  else if (mToken.Kind = etSymbol) and (mToken.Text = '(') then
  begin
    Result := ParseOr;
    if IsSymbol(')') then
    begin
      Take;
    end;
  end;
end;

{ TAtlasConditionals }

constructor TAtlasConditionals.Create(const ADefines: TArray<string>; ACompilerVersion: Double);
var
  mSymbol: string;
begin
  inherited Create;
  FDefines := TDictionary<string, Boolean>.Create;
  FFrames := TList<TFrame>.Create;
  FCompilerVersion := ACompilerVersion;
  for mSymbol in ADefines do
  begin
    if Trim(mSymbol) <> '' then
    begin
      FDefines.AddOrSetValue(UpperCase(Trim(mSymbol)), True);
    end;
  end;
end;

destructor TAtlasConditionals.Destroy;
begin
  FFrames.Free;
  FDefines.Free;
  inherited;
end;

function TAtlasConditionals.Defined(const ASymbol: string): Boolean;
begin
  Result := FDefines.ContainsKey(UpperCase(Trim(ASymbol)));
end;

function TAtlasConditionals.Active: Boolean;
begin
  Result := (FFrames.Count = 0) or FFrames.Last.Active;
end;

function TAtlasConditionals.Evaluate(const AExpression: string): Boolean;
var
  mParser: TExprParser;
begin
  mParser := TExprParser.Create(Self, AExpression);
  try
    Result := mParser.Run;
  finally
    mParser.Free;
  end;
end;

function TAtlasConditionals.BranchCondition(const AName, AArgument: string): Boolean;
begin
  Result := False;
  if AName = 'IFDEF' then
  begin
    Result := Defined(AArgument);
  end
  else if AName = 'IFNDEF' then
  begin
    Result := not Defined(AArgument);
  end
  else if AName = 'IF' then
  begin
    Result := Evaluate(AArgument);
  end;
end;

procedure TAtlasConditionals.OpenBranch(const AName, AArgument: string);
var
  mFrame: TFrame;
begin
  mFrame.ParentActive := Active;
  mFrame.Active := mFrame.ParentActive and BranchCondition(AName, AArgument);
  mFrame.Taken := mFrame.Active;
  FFrames.Add(mFrame);
end;

procedure TAtlasConditionals.NextBranch(const AArgument: string);
var
  mFrame: TFrame;
begin
  mFrame := FFrames.Last;
  mFrame.Active := mFrame.ParentActive and not mFrame.Taken and Evaluate(AArgument);
  mFrame.Taken := mFrame.Taken or mFrame.Active;
  FFrames[FFrames.Count - 1] := mFrame;
end;

procedure TAtlasConditionals.LastBranch;
var
  mFrame: TFrame;
begin
  mFrame := FFrames.Last;
  mFrame.Active := mFrame.ParentActive and not mFrame.Taken;
  mFrame.Taken := True;
  FFrames[FFrames.Count - 1] := mFrame;
end;

procedure TAtlasConditionals.CloseBranch;
begin
  if FFrames.Count > 0 then
  begin
    FFrames.Delete(FFrames.Count - 1);
  end;
end;

procedure TAtlasConditionals.DefineSymbol(const AArgument: string);
begin
  if Active and (AArgument <> '') then
  begin
    FDefines.AddOrSetValue(UpperCase(AArgument), True);
  end;
end;

procedure TAtlasConditionals.UndefineSymbol(const AArgument: string);
begin
  if Active then
  begin
    FDefines.Remove(UpperCase(AArgument));
  end;
end;

function TAtlasConditionals.Handle(const ADirective: string): Boolean;
var
  mName, mArgument: string;
begin
  SplitDirective(ADirective, mName, mArgument);
  Result := True;
  if IsOneOf(mName, ['IFDEF', 'IFNDEF', 'IF', 'IFOPT']) then
  begin
    OpenBranch(mName, mArgument);
  end
  else if (mName = 'ELSEIF') and (FFrames.Count > 0) then
  begin
    NextBranch(mArgument);
  end
  else if (mName = 'ELSE') and (FFrames.Count > 0) then
  begin
    LastBranch;
  end
  else if IsOneOf(mName, ['ENDIF', 'IFEND']) then
  begin
    CloseBranch;
  end
  else if mName = 'DEFINE' then
  begin
    DefineSymbol(mArgument);
  end
  else if mName = 'UNDEF' then
  begin
    UndefineSymbol(mArgument);
  end
  else
  begin
    Result := False;
  end;
end;

end.
