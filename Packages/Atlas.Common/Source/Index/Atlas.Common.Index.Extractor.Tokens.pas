unit Atlas.Common.Index.Extractor.Tokens;

// Liest aus den Tokens einer Unit, was der Syntaxbaum nicht festhält: Namensstellen, Signaturen als Text,
// Hinweise (deprecated, platform …), XML-Doku und den Schalter {$SCOPEDENUMS}. Ausgelagert aus
// Atlas.Common.Index.Extractor.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TIndexTokenReader = class
  private
    FTokens: TArray<TPascalToken>;
    /// <summary>Stellen der {$SCOPEDENUMS}-Schalter in FTokens (Offset, ON?); FScopedKnown nach dem ersten Lesen.
    /// </summary>
    FScopedOffsets: TArray<Integer>;
    FScopedOn: TArray<Boolean>;
    FScopedKnown: Boolean;
    procedure ReadScopedSwitches;
    /// <summary>Erstes Token ab AIndex, das weder Kommentar noch Direktive ist (Length(FTokens) ohne).</summary>
    function NextCode(AIndex: Integer): Integer;
    /// <summary>Letztes Token bis AIndex, das weder Kommentar noch Direktive ist (-1 ohne).</summary>
    function PreviousCode(AIndex: Integer): Integer;
    function IsHintAt(APos: Integer): Boolean;
    /// <summary>Endet an APos ein Hinweis? Hinter ihm folgt ";", "," oder der Grund als String, sonst ist er ein
    /// Bezeichner (z. B. ein Feld "platform: Integer").</summary>
    function EndsHint(APos: Integer): Boolean;
    /// <summary>Grund hinter deprecated am Token APos (deprecated 'Stattdessen Bar verwenden') nach AText.</summary>
    procedure ReasonAt(APos: Integer; var AText: string);
    procedure HeaderDirectives(AHeader: TSyntaxNode; var AWords: TArray<string>; var AReason: string);
    /// <summary>Hinweise vor dem Ende der Deklaration: "X = 1 deprecated;", "A: Integer platform;".</summary>
    procedure HintsBefore(ALast: Integer; var AWords: TArray<string>; var AReason: string);
    /// <summary>Hinweise hinter dem Ende des Knotens, die trotzdem zu ihm gehören.</summary>
    procedure HintsAfter(AFirst: Integer; var AWords: TArray<string>; var AReason: string);
    /// <summary>Erstes "of" außerhalb von Klammern in AFirst..ALast-1; -1 ohne.</summary>
    function TopLevelOf(AFirst, ALast: Integer): Integer;
    /// <summary>Erstes Token hinter dem Unit-Namen ab AIndex (Teile mit Punkt dazwischen).</summary>
    function AfterUnitName(AIndex: Integer): Integer;
    /// <summary>Länge hinter string[8] als "[8]"; '' bei anderen Typen.</summary>
    function StringLengthSuffix(ANode: TSyntaxNode): string;
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    /// <summary>AText, auf höchstens AMax Zeichen gekürzt (mit „…“ am Ende).</summary>
    class function Shortened(const AText: string; AMax: Integer): string; static;
    function TokenIndexAt(AOffset: Integer): Integer;
    /// <summary>Gilt {$SCOPEDENUMS ON} an AOffset?</summary>
    function ScopedAt(AOffset: Integer): Boolean;
    function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
    function IsConstructor(ANode: TSyntaxNode): Boolean;
    /// <summary>Beginnt die Deklaration mit "class" oder steht "class" direkt davor ("class property",
    /// "class var" vor dem var-Abschnitt)?</summary>
    function IsClassMember(ANode: TSyntaxNode): Boolean;
    function IsDefaultProperty(ANode: TSyntaxNode): Boolean;
    /// <summary>Tokens AFrom..ATo (ohne Kommentare und Compiler-Direktiven) als eine Zeile; mit
    /// AFirstLine endet der Text am Ende der ersten Zeile außerhalb von Klammern.</summary>
    function TokenText(AFrom, ATo: Integer; AFirstLine: Boolean): string;
    function SignatureOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind; const AName, ATypeText: string): string;
    /// <summary>Art des Prozedurtyps AType (#1326): 'of object' bei Methodenzeigern, 'reference to' bei
    /// Methodenreferenzen, sonst ''. Gelesen aus den Tokens, also unabhängig von Zeilenumbrüchen.</summary>
    function ProcedureKindOf(AType: TSyntaxNode): string;
    /// <summary>Direktiven der Deklaration; ADeprecatedText: Grund hinter deprecated 'Grund' (#38), sonst ''.
    /// </summary>
    function DirectivesOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind; out ADeprecatedText: string): TArray<string>;
    function SummaryOf(ANode: TSyntaxNode): string;
    /// <summary>Hinweise zwischen unit Name und ";" (#1018).</summary>
    procedure UnitHints(var AUnit: TUnitIndex);
    property Tokens: TArray<TPascalToken> read FTokens;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.RegularExpressions,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Extractor.TypeText;

const
  cHintDirectives: array[0..3] of string = ('deprecated', 'platform', 'library', 'experimental');
  cNoSpaceBefore: array[0..9] of string = (';', ',', ')', ']', ':', '.', '(', '[', '^', '>');
  cNoSpaceAfter: array[0..4] of string = ('(', '[', '.', '<', '@');

/// <summary>Gehört AToken in den Text einer Signatur? Kommentare und Direktiven nicht, {$I datei.inc} als Wert
/// (#849) schon: AddIncluded setzt den Inhalt ein.</summary>
function IsTextToken(const AToken: TPascalToken): Boolean;
var
  mIncludeName: string;
begin
  Result := (AToken.Kind <> TPascalTokenKind.Comment) and ((AToken.Kind <> TPascalTokenKind.Directive) or
    TPascalPreprocessor.IncludeFileOf(AToken.Text, mIncludeName));
end;

/// <summary>Hängt AToken an; Leerzeichen nur, wo kein Satzzeichen es verbietet ("A: Integer", "F(A)").</summary>
procedure AppendTokenText(ABuilder: TStringBuilder; const AToken: TPascalToken; const APrevious: string);
begin
  if (ABuilder.Length > 0) and (AToken.Text <> '') and
    not ((AToken.Kind = TPascalTokenKind.Symbol) and (IndexStr(AToken.Text, cNoSpaceBefore) >= 0)) and
    (IndexStr(APrevious, cNoSpaceAfter) < 0) then
  begin
    ABuilder.Append(' ');
  end;
  ABuilder.Append(AToken.Text);
end;

/// <summary>Klammertiefe hinter AToken.</summary>
function DepthAfter(const AToken: TPascalToken; ADepth: Integer): Integer;
begin
  Result := ADepth;
  if AToken.Kind <> TPascalTokenKind.Symbol then
  begin
    Exit;
  end;
  if (AToken.Text = '(') or (AToken.Text = '[') then
  begin
    Inc(Result);
  end
  else if ((AToken.Text = ')') or (AToken.Text = ']')) and (Result > 0) then
  begin
    Dec(Result);
  end;
end;

/// <summary>Stringliteral ohne Anführungszeichen, verdoppelte Anführungszeichen einfach.</summary>
function Unquoted(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''', [rfReplaceAll]);
  end;
end;

/// <summary>AWord klein an AWords anhängen, wenn noch nicht enthalten.</summary>
procedure AddHint(var AWords: TArray<string>; const AWord: string);
begin
  if IndexText(AWord, AWords) < 0 then
  begin
    AWords := AWords + [LowerCase(AWord)];
  end;
end;

/// <summary>Endet die Signatur von AKind am Ende der ersten Zeile? Ein Prozedurtyp über mehrere Zeilen gehört
/// ganz hinein, sonst fehlt "of object" (#1326).</summary>
function IsFirstLineKind(ANode: TSyntaxNode; AKind: TIndexSymbolKind): Boolean;
begin
  Result := (AKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias]) and
    not ((AKind = TIndexSymbolKind.TypeAlias) and (TIndexTypeText.ProcedureTypeOf(ANode) <> nil));
end;

{ TIndexTokenReader }

constructor TIndexTokenReader.Create(const ATokens: TArray<TPascalToken>);
begin
  inherited Create;
  FTokens := ATokens;
end;

class function TIndexTokenReader.Shortened(const AText: string; AMax: Integer): string;
begin
  Result := AText;
  if Length(Result) > AMax then
  begin
    Result := Copy(Result, 1, AMax - 1) + '…';
  end;
end;

function TIndexTokenReader.TokenIndexAt(AOffset: Integer): Integer;
var
  mLeft, mRight, mMiddle: Integer;
begin
  mLeft := 0;
  mRight := Length(FTokens);
  while mLeft < mRight do
  begin
    mMiddle := (mLeft + mRight) div 2;
    if FTokens[mMiddle].Offset < AOffset then
    begin
      mLeft := mMiddle + 1;
    end
    else
    begin
      mRight := mMiddle;
    end;
  end;
  Result := mLeft;
end;

function TIndexTokenReader.NextCode(AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result < Length(FTokens)) and (FTokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
end;

function TIndexTokenReader.PreviousCode(AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result >= 0) and (FTokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

procedure TIndexTokenReader.ReadScopedSwitches;
var
  mToken: TPascalToken;
  mText: string;
begin
  FScopedKnown := True;
  for mToken in FTokens do
  begin
    if mToken.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    mText := UpperCase(mToken.Text);
    if mText.StartsWith('{$SCOPEDENUMS') or mText.StartsWith('(*$SCOPEDENUMS') then
    begin
      mText := Trim(Copy(mText, Pos('SCOPEDENUMS', mText) + Length('SCOPEDENUMS'), MaxInt));
      FScopedOffsets := FScopedOffsets + [mToken.Offset];
      FScopedOn := FScopedOn + [mText.StartsWith('ON')];
    end;
  end;
end;

function TIndexTokenReader.ScopedAt(AOffset: Integer): Boolean;
var
  mIndex: Integer;
begin
  if not FScopedKnown then
  begin
    ReadScopedSwitches;
  end;
  Result := False;
  mIndex := 0;
  while (mIndex <= High(FScopedOffsets)) and (FScopedOffsets[mIndex] < AOffset) do
  begin
    Result := FScopedOn[mIndex];
    Inc(mIndex);
  end;
end;

function TIndexTokenReader.NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
var
  mIndex: Integer;
begin
  mIndex := TokenIndexAt(ANode.StartOffset);
  while (mIndex < Length(FTokens)) and (FTokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      (SameText(FTokens[mIndex].Text, AName) or SameText(FTokens[mIndex].Text, '&' + AName)) then
    begin
      Exit(TTextRange.Create(FTokens[mIndex].StartPos, FTokens[mIndex].EndPos));
    end;
    Inc(mIndex);
  end;
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function TIndexTokenReader.IsConstructor(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := NextCode(TokenIndexAt(ANode.StartOffset));
  if (mIndex < Length(FTokens)) and FTokens[mIndex].IsKeyword('class') then
  begin
    Inc(mIndex);
  end;
  Result := (mIndex < Length(FTokens)) and
    (FTokens[mIndex].IsKeyword('constructor') or FTokens[mIndex].IsKeyword('destructor'));
end;

function TIndexTokenReader.IsClassMember(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := NextCode(TokenIndexAt(ANode.StartOffset));
  if (mIndex < Length(FTokens)) and FTokens[mIndex].IsKeyword('class') then
  begin
    Exit(True);
  end;
  mIndex := PreviousCode(TokenIndexAt(ANode.StartOffset) - 1);
  if (mIndex < 0) or not FTokens[mIndex].IsKeyword('class') then
  begin
    Exit(False);
  end;
  // "TFoo = class" bzw. "= packed class" direkt vor dem ersten Mitglied ist der Typ selbst.
  mIndex := PreviousCode(mIndex - 1);
  Result := (mIndex >= 0) and not FTokens[mIndex].IsSymbol('=') and not FTokens[mIndex].IsKeyword('packed');
end;

function TIndexTokenReader.IsDefaultProperty(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  // property Items[I: Integer]: T read Get; default;  Anders als "default 0" (gespeicherter
  // Standardwert) folgt "default" hier auf ein Semikolon.
  Result := False;
  mIndex := TokenIndexAt(ANode.StartOffset);
  while (mIndex + 1 < Length(FTokens)) and (FTokens[mIndex].Offset <= ANode.EndOffset) do
  begin
    if FTokens[mIndex].IsSymbol(';') and SameText(FTokens[mIndex + 1].Text, 'default') then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
end;

function TIndexTokenReader.TokenText(AFrom, ATo: Integer; AFirstLine: Boolean): string;
var
  mBuilder: TStringBuilder;
  mIndex, mDepth, mFirstLine: Integer;
  mToken: TPascalToken;
  mPrevious: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    mDepth := 0;
    mFirstLine := -1;
    mPrevious := '';
    for mIndex := Max(AFrom, 0) to Min(ATo, High(FTokens)) do
    begin
      mToken := FTokens[mIndex];
      if not IsTextToken(mToken) then
      begin
        Continue;
      end;
      if mFirstLine < 0 then
      begin
        mFirstLine := mToken.StartPos.Line;
      end;
      if AFirstLine and (mDepth = 0) and (mToken.StartPos.Line > mFirstLine) then
      begin
        Break;
      end;
      AppendTokenText(mBuilder, mToken, mPrevious);
      mDepth := DepthAfter(mToken, mDepth);
      mPrevious := mToken.Text;
      if mBuilder.Length > TIndexSymbol.cMaxSignature then
      begin
        Break;
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  Result := Shortened(Result, TIndexSymbol.cMaxSignature);
end;

function TIndexTokenReader.StringLengthSuffix(ANode: TSyntaxNode): string;
var
  mTypeRef: TSyntaxNode;
begin
  // string[8]: Die Länge gehört zur Signatur (Anzeige, string-length-limit #1036); der Typname bleibt
  // string, damit die Namensauflösung ihn findet.
  Result := '';
  mTypeRef := TIndexTypeText.DeclaredTypeNode(ANode);
  if (mTypeRef <> nil) and SameText(mTypeRef.Name, 'string') and (mTypeRef.ChildCount = 1) and
    (mTypeRef[0].Kind <> TSyntaxKind.GenericArgs) then
  begin
    Result := '[' + TokenText(TokenIndexAt(mTypeRef[0].StartOffset), TokenIndexAt(mTypeRef[0].EndOffset) - 1,
      False) + ']';
  end;
end;

function TIndexTokenReader.SignatureOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind;
  const AName, ATypeText: string): string;
var
  mNode: TSyntaxNode;
begin
  if AKind = TIndexSymbolKind.EnumMember then
  begin
    Exit(AName);
  end;
  // A, B: Integer: je Name eine eigene Signatur.
  if (AKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable]) and (ATypeText <> '') then
  begin
    Exit(AName + ': ' + ATypeText + StringLengthSuffix(ANode));
  end;
  mNode := TIndexTypeText.HeaderOf(ANode);
  Result := TokenText(TokenIndexAt(mNode.StartOffset), TokenIndexAt(mNode.EndOffset) - 1,
    IsFirstLineKind(mNode, AKind));
  // Ein abschließendes Semikolon gehört nicht zur Anzeige.
  while Result.EndsWith(';') do
  begin
    Result := Copy(Result, 1, Length(Result) - 1).TrimRight;
  end;
end;

function TIndexTokenReader.TopLevelOf(AFirst, ALast: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AFirst;
  while Result < ALast do
  begin
    if (mDepth = 0) and FTokens[Result].IsKeyword('of') then
    begin
      Exit;
    end;
    mDepth := DepthAfter(FTokens[Result], mDepth);
    Inc(Result);
  end;
  Result := -1;
end;

function TIndexTokenReader.ProcedureKindOf(AType: TSyntaxNode): string;
var
  mOf, mLast, mIndex: Integer;
begin
  Result := '';
  if AType = nil then
  begin
    Exit;
  end;
  if SameText(AType.Name, 'reference') then
  begin
    Exit('reference to');
  end;
  mLast := TokenIndexAt(AType.EndOffset) - 1;
  mOf := TopLevelOf(TokenIndexAt(AType.StartOffset), mLast);
  // Kommentare und Direktiven zwischen "of" und "object" überspringen.
  mIndex := NextCode(mOf + 1);
  if (mOf >= 0) and (mIndex <= mLast) and SameText(FTokens[mIndex].Text, 'object') then
  begin
    Result := 'of object';
  end;
end;

function TIndexTokenReader.IsHintAt(APos: Integer): Boolean;
begin
  Result := (APos >= 0) and (APos < Length(FTokens)) and
    (FTokens[APos].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    (IndexText(FTokens[APos].Text, cHintDirectives) >= 0);
end;

function TIndexTokenReader.EndsHint(APos: Integer): Boolean;
begin
  Result := (APos >= Length(FTokens)) or FTokens[APos].IsSymbol(';') or FTokens[APos].IsSymbol(',') or
    (FTokens[APos].Kind = TPascalTokenKind.StringLiteral) or IsHintAt(APos);
end;

procedure TIndexTokenReader.ReasonAt(APos: Integer; var AText: string);
var
  mNext: Integer;
begin
  if (APos < 0) or (APos >= Length(FTokens)) or not SameText(FTokens[APos].Text, 'deprecated') then
  begin
    Exit;
  end;
  mNext := NextCode(APos + 1);
  if (mNext < Length(FTokens)) and (FTokens[mNext].Kind = TPascalTokenKind.StringLiteral) then
  begin
    AText := Unquoted(FTokens[mNext].Text);
  end;
end;

procedure TIndexTokenReader.HeaderDirectives(AHeader: TSyntaxNode; var AWords: TArray<string>;
  var AReason: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[mIndex].Kind = TSyntaxKind.Directive then
    begin
      AddHint(AWords, AHeader[mIndex].Name);
      ReasonAt(TokenIndexAt(AHeader[mIndex].StartOffset), AReason);
    end;
  end;
end;

procedure TIndexTokenReader.HintsBefore(ALast: Integer; var AWords: TArray<string>; var AReason: string);
var
  mIndex: Integer;
begin
  mIndex := ALast;
  while (mIndex > 0) and ((FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive,
    TPascalTokenKind.StringLiteral]) or FTokens[mIndex].IsSymbol(';')) do
  begin
    Dec(mIndex);
  end;
  while (mIndex > 0) and IsHintAt(mIndex) do
  begin
    AddHint(AWords, FTokens[mIndex].Text);
    ReasonAt(mIndex, AReason);
    Dec(mIndex);
    while (mIndex > 0) and ((FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.StringLiteral]) or
      FTokens[mIndex].IsSymbol(',')) do
    begin
      Dec(mIndex);
    end;
  end;
end;

procedure TIndexTokenReader.HintsAfter(AFirst: Integer; var AWords: TArray<string>; var AReason: string);
var
  mIndex: Integer;
begin
  mIndex := AFirst;
  while (mIndex < Length(FTokens)) and (FTokens[mIndex].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive, TPascalTokenKind.StringLiteral]) do
  begin
    Inc(mIndex);
  end;
  while IsHintAt(mIndex) and EndsHint(NextCode(mIndex + 1)) do
  begin
    AddHint(AWords, FTokens[mIndex].Text);
    ReasonAt(mIndex, AReason);
    mIndex := NextCode(mIndex + 1);
    while (mIndex < Length(FTokens)) and ((FTokens[mIndex].Kind = TPascalTokenKind.StringLiteral) or
      FTokens[mIndex].IsSymbol(',')) do
    begin
      mIndex := NextCode(mIndex + 1);
    end;
  end;
end;

function TIndexTokenReader.DirectivesOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind;
  out ADeprecatedText: string): TArray<string>;
var
  mNode: TSyntaxNode;
  mLast: Integer;
begin
  Result := nil;
  ADeprecatedText := '';
  mNode := TIndexTypeText.HeaderOf(ANode);
  if mNode.Kind = TSyntaxKind.RoutineHeader then
  begin
    HeaderDirectives(mNode, Result, ADeprecatedText);
  end
  else if AKind <> TIndexSymbolKind.EnumMember then
  begin
    mLast := TokenIndexAt(mNode.EndOffset) - 1;
    HintsBefore(mLast, Result, ADeprecatedText);
    HintsAfter(mLast + 1, Result, ADeprecatedText);
  end;
end;

function TIndexTokenReader.SummaryOf(ANode: TSyntaxNode): string;
var
  mIndex, mDepth: Integer;
  mLines: TArray<string>;
  mDoc: TXmlDoc;
begin
  Result := '';
  mIndex := TokenIndexAt(ANode.StartOffset) - 1;
  // Attribute zwischen Doku und Deklaration überspringen: [Weak] /// steht darüber.
  while (mIndex >= 0) and FTokens[mIndex].IsSymbol(']') do
  begin
    mDepth := 0;
    repeat
      if FTokens[mIndex].IsSymbol(']') then
      begin
        Inc(mDepth);
      end
      else if FTokens[mIndex].IsSymbol('[') then
      begin
        Dec(mDepth);
      end;
      Dec(mIndex);
    until (mIndex < 0) or (mDepth = 0);
  end;
  mLines := nil;
  while (mIndex >= 0) and (FTokens[mIndex].Kind = TPascalTokenKind.Comment) and
    FTokens[mIndex].Text.StartsWith('///') do
  begin
    mLines := [Copy(FTokens[mIndex].Text, 4, MaxInt)] + mLines;
    Dec(mIndex);
  end;
  if Length(mLines) = 0 then
  begin
    Exit;
  end;
  mDoc := TXmlDoc.Parse(String.Join(#10, mLines));
  // Eine Zeile, Leerraum zusammengefasst.
  Result := Shortened(TRegEx.Replace(mDoc.Summary, '\s+', ' ').Trim, TIndexSymbol.cMaxSummary);
end;

function TIndexTokenReader.AfterUnitName(AIndex: Integer): Integer;
var
  mAfterPart: Boolean;
begin
  // Name aus Teilen mit Punkt dazwischen; nach einem Teil ohne folgenden Punkt beginnen die Hinweise.
  Result := AIndex;
  mAfterPart := False;
  while (Result < Length(FTokens)) and not FTokens[Result].IsSymbol(';') do
  begin
    if mAfterPart and not FTokens[Result].IsSymbol('.') then
    begin
      Exit;
    end;
    mAfterPart := not FTokens[Result].IsSymbol('.');
    Result := NextCode(Result + 1);
  end;
end;

procedure TIndexTokenReader.UnitHints(var AUnit: TUnitIndex);
var
  mIndex: Integer;
begin
  // unit A.B deprecated 'Grund' platform;  Kommentare und Direktiven dazwischen überspringen.
  // Der Unit-Name zählt nicht als Hinweis: Atlas.Settings.Experimental ist nicht experimental.
  mIndex := NextCode(0);
  if (mIndex >= Length(FTokens)) or (FTokens[mIndex].Kind <> TPascalTokenKind.Keyword) or
    not SameText(FTokens[mIndex].Text, 'unit') then
  begin
    Exit;
  end;
  mIndex := AfterUnitName(NextCode(mIndex + 1));
  while (mIndex < Length(FTokens)) and not FTokens[mIndex].IsSymbol(';') do
  begin
    if IsHintAt(mIndex) then
    begin
      AddHint(AUnit.Directives, FTokens[mIndex].Text);
      ReasonAt(mIndex, AUnit.DeprecatedText);
    end;
    mIndex := NextCode(mIndex + 1);
  end;
end;

end.
