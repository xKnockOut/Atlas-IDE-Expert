unit Atlas.Common.Editing.ClassCompletion;

// Klassenvervollständigung (#42), wie Strg+Umschalt+C in der IDE: Zu Methoden,
// die im Typ deklariert, aber nicht implementiert sind, erzeugt eine
// Code-Aktion leere Rümpfe im implementation-Abschnitt.
//
// Steht der Cursor auf einer solchen Methode, gilt die Aktion nur ihr; sonst
// allen fehlenden Methoden des Typs unter dem Cursor. Abstrakte Methoden,
// Methoden von Interfaces und generische Typen werden übergangen. Die Rümpfe
// kommen hinter die letzte vorhandene Methode des Typs, sonst vor
// initialization, finalization bzw. das abschließende "end.".
//
// Unmatched liefert für die Prüfregeln aus #124 beide Richtungen: deklarierte
// Methoden ohne Rumpf und Rümpfe ohne Deklaration. AddDeclaration ergänzt eine
// fehlende Deklaration im private-Abschnitt des Typs.
//
// DeclaredMethods (#660) liefert dieselbe Zuordnung von der anderen Seite:
// je Typ der Datei die deklarierten Methoden in ihrer Reihenfolge, jede mit
// ihrem Rumpf, falls es ihn gibt; die Reihenfolge der Rümpfe im
// implementation-Teil richtet sich danach.
//
// Pairs (#996) ordnet Deklarationen und Rümpfe ohne Gegenstück einander zu,
// deren Köpfe abweichen: gleicher Typ und Name, bei Überladungen die
// nächstliegende Deklaration (Parameteranzahl, dann Typen, Namen und
// Modifizierer); ist sie nicht eindeutig, bleibt das Paar aus. PairFixes (#100)
// gleicht Rumpf und Deklaration in beide Richtungen an, auch die
// Aufrufkonvention. Standardwerte bleiben nur in der Deklaration.
//
// Neue Rümpfe (#1834) kommen in der Reihenfolge Lebenszyklus, Zugriffsmethoden,
// überschriebene, übrige (TClassBodies.RankOf), vorbefüllt (O1) und beim
// ersten Rumpf eines Typs mit dem Kommentar über dem Abschnitt (K1–K4);
// Einstellungen über TClassBodyOptions.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassBodies;

type
  /// <summary>Methode ohne Gegenstück (#124).</summary>
  TUnmatchedMethod = record
    /// <summary>Typ, ggf. mit umgebendem Typ (TAussen.TInnen).</summary>
    TypeName: string;
    Symbol: TIndexSymbol;
    /// <summary>True: deklariert, aber ohne Rumpf; False: Rumpf ohne Deklaration.</summary>
    Declared: Boolean;
    /// <summary>Kopf ohne ";", z. B. "procedure TFoo.Bar(A: Integer)" beim Rumpf.</summary>
    Header: string;
  end;

  /// <summary>Ein Parameter eines Methodenkopfs (#996).</summary>
  TShapeParameter = record
    /// <summary>const, var, out, constref oder '' (Kleinbuchstaben).</summary>
    Modifier: string;
    Name: string;
    /// <summary>Typ wie geschrieben; '' bei untypisierten Parametern.</summary>
    TypeName: string;
  end;

  /// <summary>Zerlegter Kopf einer Methode (#996).</summary>
  TSignatureShape = record
    /// <summary>procedure, function, constructor, destructor oder operator.</summary>
    Kind: string;
    Parameters: TArray<TShapeParameter>;
    /// <summary>Ergebnistyp wie geschrieben; '' ohne.</summary>
    ResultType: string;
    /// <summary>Aufrufkonvention in Kleinbuchstaben (stdcall, cdecl …); '' ohne Angabe.</summary>
    Convention: string;
    ConventionRange: TTextRange;
    /// <summary>Im Kopf steht bedingte Übersetzung ({$IFDEF} …); welche Parameter gelten, ist offen (#1324).
    /// </summary>
    Conditional: Boolean;
  end;

  /// <summary>Deklaration und Rumpf gleichen Namens, deren Köpfe voneinander abweichen (#996).</summary>
  TSignaturePair = record
    Declaration: TUnmatchedMethod;
    Body: TUnmatchedMethod;
    DeclarationShape: TSignatureShape;
    BodyShape: TSignatureShape;
  end;

  /// <summary>Deklarierte Methode eines Typs mit ihrem Rumpf (#660).</summary>
  TDeclaredMethod = record
    /// <summary>Typ, ggf. mit umgebendem Typ (TAussen.TInnen).</summary>
    TypeName: string;
    /// <summary>Stelle des Typs in der Datei, ab 0 in der Reihenfolge der Typen.</summary>
    TypeOrder: Integer;
    /// <summary>Stelle der Deklaration im Typ, ab 0.</summary>
    DeclarationOrder: Integer;
    Declaration: TIndexSymbol;
    HasBody: Boolean;
    Body: TIndexSymbol;
  end;

  TClassCompletion = class
  public
    /// <summary>Methoden ohne Gegenstück in Typen dieser Datei. Abstrakte, externe und forward-
    /// Methoden sowie generische Typen werden übergangen; Rümpfe zu Typen, die nicht in der
    /// Datei stehen, ebenfalls.</summary>
    class function Unmatched(ATree: TSyntaxTree; const AText: string): TArray<TUnmatchedMethod>; static;
    /// <summary>Je Typ der Datei (in ihrer Reihenfolge) die deklarierten Methoden in Deklarationsreihenfolge mit
    /// ihrem Rumpf (#660). Abstrakte, externe und forward-Methoden fehlen, generische Typen ebenso.</summary>
    class function DeclaredMethods(ATree: TSyntaxTree; const AText: string): TArray<TDeclaredMethod>; static;
    /// <summary>Fügt die Deklaration zu einem Rumpf ohne Deklaration im private-Abschnitt ein
    /// (legt ihn bei Bedarf an); False, wenn der Typ nicht passend aufgebaut ist.</summary>
    class function AddDeclaration(ATree: TSyntaxTree; const AText: string; const AMethod: TUnmatchedMethod;
      out AEdit: TTextEdit): Boolean; static;
    /// <summary>Aktion für fehlende Rümpfe an APosition; False, wenn nichts fehlt.</summary>
    class function MissingBodies(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>Wie oben mit den Einstellungen der Klassenvervollständigung (#1834).</summary>
    class function MissingBodies(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      const AOptions: TClassBodyOptions; out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>Wie oben mit classCompletion.* aus ASettings (ungesetzt: Vorgaben) und dem Formatstil AStyle.
    /// </summary>
    class function MissingBodies(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      const ASettings: TClassCompletionSettings; const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
      overload; static;
    /// <summary>Zerlegt den Kopf der Methode ASymbol; False, wenn er sich nicht lesen lässt.</summary>
    class function Shape(ATree: TSyntaxTree; const AText: string; const ASymbol: TIndexSymbol;
      out AShape: TSignatureShape): Boolean; static;
    /// <summary>Paare aus Unmatched: Deklaration und Rumpf desselben Typs und Namens, bei Überladungen nur
    /// wechselseitig eindeutig nächstliegende (#996).</summary>
    class function Pairs(ATree: TSyntaxTree; const AText: string): TArray<TSignaturePair>; static;
    /// <summary>"Implementierung an die Deklaration angleichen" und "Deklaration an die Implementierung
    /// angleichen" (#100) für APair. Liefert Code-Aktionen statt TRuleFix, damit Editing ohne Rules
    /// auskommt (A-11); die Regel signature-mismatch macht daraus Korrekturen.</summary>
    class function PairFixes(ATree: TSyntaxTree; const AText: string; const APair: TSignaturePair;
      out AFixes: TArray<TCodeAction>): Boolean; static;
    /// <summary>Fügt den Rumpf ABody (ohne Zeilenumbruch am Ende) für einen Typ dieser Datei ein: hinter die
    /// letzte vorhandene Methode des Typs, sonst vor initialization, finalization bzw. "end." (#443).</summary>
    class function BodyEdit(ATree: TSyntaxTree; const AText, ATypeName, ABody: string; out AEdit: TTextEdit): Boolean;
      overload; static;
    /// <summary>Wie oben; ist es der erste Rumpf des Typs, kommt der Kommentar nach AOptions davor (#1835).
    /// </summary>
    class function BodyEdit(ATree: TSyntaxTree; const AText, ATypeName, ABody: string;
      const AOptions: TClassBodyOptions; out AEdit: TTextEdit): Boolean; overload; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.RoutineSignatures,
  Atlas.Text.Lines,
  Atlas.Common.Editing.TypeComments,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TClassCompletionText = (AlignTheImplementationOfWith, AlignTheDeclarationOfWith, CreateMethodBodyFor,
    CreateMissingMethodBodyFor, CreateMissingMethodBodiesFor);

const
  cTexts: array[TClassCompletionText] of TAtlasText = (
    (De: 'Implementierung von %s an die Deklaration angleichen';
     En: 'Align the implementation of %s with the declaration'),
    (De: 'Deklaration von %s an die Implementierung angleichen';
     En: 'Align the declaration of %s with the implementation'),
    (De: 'Methodenrumpf für %s.%s erzeugen'; En: 'Create method body for %s.%s'),
    (De: 'Fehlenden Methodenrumpf für %s erzeugen'; En: 'Create missing method body for %s'),
    (De: '%d fehlende Methodenrümpfe für %s erzeugen'; En: 'Create %d missing method bodies for %s'));

{$SCOPEDENUMS OFF}

const
  // Bedingte Übersetzung im Kopf einer Methode (#1324).
  cConditionalDirectives: array[0..7] of string = ('IF', 'IFDEF', 'IFNDEF', 'IFOPT', 'ELSE', 'ELSEIF', 'ENDIF',
    'IFEND');
  cTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.HelperType];
  cMethodKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];

function ContainsLine(const ARange: TTextRange; ALine: Integer): Boolean;
begin
  Result := (ALine >= ARange.StartPos.Line) and (ALine <= ARange.EndPos.Line);
end;

/// <summary>Text von ARange bis zum Ende seiner letzten Zeile, Zeilen mit Leerzeichen verbunden.</summary>
function RangeText(const ALines: TArray<string>; const ARange: TTextRange): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := ARange.StartPos.Line to ARange.EndPos.Line do
  begin
    if (mLine < 0) or (mLine > High(ALines)) then
    begin
      Break;
    end;
    if mLine = ARange.StartPos.Line then
    begin
      Result := Copy(ALines[mLine], ARange.StartPos.Character + 1, MaxInt);
    end
    else
    begin
      Result := Result + ' ' + Trim(ALines[mLine]);
    end;
  end;
end;

/// <summary>Teile von AText an ADelimiter außerhalb von Klammern und Zeichenketten.</summary>
function SplitTopLevel(const AText: string; ADelimiter: Char): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
  mQuoted: Boolean;
begin
  Result := nil;
  mDepth := 0;
  mQuoted := False;
  mStart := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if mQuoted then
    begin
      Continue;
    end
    else if CharInSet(AText[mIndex], ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(AText[mIndex], [')', ']', '>']) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and (AText[mIndex] = ADelimiter) then
    begin
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  Result := Result + [Copy(AText, mStart, MaxInt)];
end;

function HasWord(const AText, AWord: string): Boolean;
var
  mIndex: Integer;
  mLower: string;
begin
  mLower := LowerCase(AText);
  mIndex := Pos(AWord, mLower);
  while mIndex > 0 do
  begin
    if ((mIndex = 1) or not CharInSet(mLower[mIndex - 1], ['a'..'z', '0'..'9', '_'])) and
      ((mIndex + Length(AWord) > Length(mLower)) or
      not CharInSet(mLower[mIndex + Length(AWord)], ['a'..'z', '0'..'9', '_'])) then
    begin
      Exit(True);
    end;
    mIndex := PosEx(AWord, mLower, mIndex + 1);
  end;
  Result := False;
end;

/// <summary>Kopf der Implementierung: Typname vor den Methodennamen.</summary>
function QualifiedHeader(const ASignature, AMethodName, ATypeName: string): string;
var
  mIndex: Integer;
begin
  // Der Name folgt auf procedure/function/constructor/destructor/operator.
  mIndex := Pos(LowerCase(' ' + AMethodName), LowerCase(ASignature));
  if mIndex = 0 then
  begin
    Exit('');
  end;
  Result := Copy(ASignature, 1, mIndex) + ATypeName + '.' + Copy(ASignature, mIndex + 1, MaxInt) + ';';
end;

/// <summary>Ist AIndex das "end" vor dem abschließenden "." der Unit (Kommentare dazwischen erlaubt)?</summary>
function IsUnitEnd(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mNext: Integer;
begin
  Result := ATokens[AIndex].IsKeyword('end');
  if Result then
  begin
    mNext := AIndex + 1;
    while (mNext <= High(ATokens)) and
      (ATokens[mNext].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    begin
      Inc(mNext);
    end;
    Result := (mNext <= High(ATokens)) and ATokens[mNext].IsSymbol('.');
  end;
end;

/// <summary>Zeile vor initialization, finalization oder dem abschließenden "end."; -1 ohne implementation.</summary>
function ImplementationEndLine(ATree: TSyntaxTree): Integer;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mInImplementation: Boolean;
begin
  Result := -1;
  mInImplementation := False;
  mTokens := ATree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].IsKeyword('implementation') then
    begin
      mInImplementation := True;
    end
    else if not mInImplementation then
    begin
      Continue;
    end
    else if mTokens[mIndex].IsKeyword('initialization') or mTokens[mIndex].IsKeyword('finalization') then
    begin
      Exit(mTokens[mIndex].StartPos.Line);
    end
    else if IsUnitEnd(mTokens, mIndex) then
    begin
      Result := mTokens[mIndex].StartPos.Line;
    end;
  end;
end;

function TypeNameOf(const ASymbol: TIndexSymbol): string;
begin
  if ASymbol.Container <> '' then
  begin
    Result := ASymbol.Container + '.' + ASymbol.Name;
  end
  else
  begin
    Result := ASymbol.Name;
  end;
end;

type
  /// <summary>Kopf hinter dem Methodennamen bis vor das erste ";" außerhalb von Klammern.</summary>
  TSignatureTail = record
    Range: TTextRange;
    /// <summary>"(const A: Integer): Boolean".</summary>
    Text: string;
    NameToken: Integer;
    LastToken: Integer;
  end;

/// <summary>Spitze Klammern auf Klammerebene 0: Constraints der Typparameter enthalten ";" (&lt;TI: IInterface;
/// TC: class&gt;, #1325). True beim ";", das den Kopf beendet.</summary>
function AngleStep(const AToken: TPascalToken; var AAngles: Integer): Boolean;
begin
  Result := False;
  if AToken.IsSymbol('<') then
  begin
    Inc(AAngles);
  end
  else if (AAngles > 0) and AToken.IsSymbol('>') then
  begin
    Dec(AAngles);
  end
  else
  begin
    Result := (AAngles = 0) and AToken.IsSymbol(';');
  end;
end;

/// <summary>Zählt Klammern mit; True beim ";", das den Kopf beendet.</summary>
function EndsTail(const AToken: TPascalToken; var ADepth, AAngles: Integer): Boolean;
begin
  Result := False;
  if AToken.IsSymbol('(') or AToken.IsSymbol('[') then
  begin
    Inc(ADepth);
  end
  else if AToken.IsSymbol(')') or AToken.IsSymbol(']') then
  begin
    Dec(ADepth);
  end
  else if ADepth = 0 then
  begin
    Result := AngleStep(AToken, AAngles);
  end;
end;

/// <summary>Letztes Token des Kopfes hinter dem Namen an AName (ohne Kommentare); -1 ohne.</summary>
function TailEnd(const ATokens: TArray<TPascalToken>; AName: Integer): Integer;
var
  mIndex, mDepth, mAngles: Integer;
begin
  Result := -1;
  mDepth := 0;
  mAngles := 0;
  for mIndex := AName + 1 to High(ATokens) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Comment then
    begin
      Continue;
    end;
    if EndsTail(ATokens[mIndex], mDepth, mAngles) then
    begin
      Break;
    end;
    Result := mIndex;
  end;
end;

/// <summary>Bereich und Text hinter dem Methodennamen bis vor das erste ";" außerhalb von Klammern,
/// z. B. "(const A: Integer): Boolean".</summary>
function SignatureTail(ATree: TSyntaxTree; const AText: string; const ASymbol: TIndexSymbol;
  out ATail: TSignatureTail): Boolean; overload;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mStartOffset: Integer;
begin
  ATail := Default(TSignatureTail);
  ATail.NameToken := -1;
  ATail.LastToken := -1;
  mTokens := ATree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].EndPos = ASymbol.SelectionRange.EndPos then
    begin
      ATail.NameToken := mIndex;
      Break;
    end;
  end;
  if ATail.NameToken >= 0 then
  begin
    ATail.LastToken := TailEnd(mTokens, ATail.NameToken);
  end;
  Result := ATail.LastToken >= 0;
  if Result then
  begin
    mStartOffset := mTokens[ATail.NameToken].Offset + Length(mTokens[ATail.NameToken].Text);
    ATail.Range := TTextRange.Create(mTokens[ATail.NameToken].EndPos, mTokens[ATail.LastToken].EndPos);
    ATail.Text := Copy(AText, mStartOffset + 1, mTokens[ATail.LastToken].Offset +
      Length(mTokens[ATail.LastToken].Text) - mStartOffset);
  end;
end;

function SignatureTail(ATree: TSyntaxTree; const AText: string; const ASymbol: TIndexSymbol;
  out ARange: TTextRange; out ATail: string): Boolean; overload;
var
  mTail: TSignatureTail;
begin
  Result := SignatureTail(ATree, AText, ASymbol, mTail);
  ARange := mTail.Range;
  ATail := mTail.Text;
end;

/// <summary>Text der Token AFirst..ALast ohne Kommentare und Direktiven (#1324): {Do not Localize}, {%H-} oder
/// //FI W521 gehören nicht zum Kopf. Leerraum oder ein weggelassenes Token zwischen zwei Token wird ein Leerzeichen.
/// AConditional: Darunter steht {$IF…}, {$ELSE…} oder {$ENDIF}; welche Teile gelten, hängt dann von der
/// Übersetzung ab.</summary>
function CleanTail(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; out AConditional: Boolean): string;
var
  mIndex, mEnd: Integer;
  mGap: Boolean;
begin
  Result := '';
  AConditional := False;
  mGap := False;
  mEnd := -1;
  for mIndex := AFirst to ALast do
  begin
    if ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      if (ATokens[mIndex].Kind = TPascalTokenKind.Directive) and
        MatchText(TPascalLexer.DirectiveName(ATokens[mIndex].Text), cConditionalDirectives) then
      begin
        AConditional := True;
      end;
      mGap := True;
      Continue;
    end;
    if (Result <> '') and (mGap or (ATokens[mIndex].Offset > mEnd)) then
    begin
      Result := Result + ' ';
    end;
    Result := Result + ATokens[mIndex].Text;
    mEnd := ATokens[mIndex].Offset + Length(ATokens[mIndex].Text);
    mGap := False;
  end;
end;

/// <summary>AText ohne Attribute in eckigen Klammern: "const [ref] A" → "const A" (#1324).</summary>
function WithoutAttributes(const AText: string): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '[' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ']' then
    begin
      if mDepth > 0 then
      begin
        Dec(mDepth);
      end;
      Result := Result + ' ';
    end
    else if mDepth = 0 then
    begin
      Result := Result + AText[mIndex];
    end;
  end;
  Result := Trim(Result);
  while Pos('  ', Result) > 0 do
  begin
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  end;
end;

/// <summary>+1 für "(" und "[", -1 für ")" und "]", sonst 0.</summary>
function BracketDelta(AChar: Char): Integer;
begin
  Result := 0;
  if CharInSet(AChar, ['(', '[']) then
  begin
    Result := 1;
  end
  else if CharInSet(AChar, [')', ']']) then
  begin
    Result := -1;
  end;
end;

/// <summary>Ein Zeichen der Parameterliste außerhalb von Strings: zählt Klammern und schließt Gruppen ab. True,
/// wenn die Liste an AIndex endet.</summary>
function SplitStep(const ATail: string; AIndex: Integer; var ADepth, AStart: Integer;
  var AGroups: TArray<string>): Boolean;
var
  mGroup: string;
begin
  ADepth := ADepth + BracketDelta(ATail[AIndex]);
  mGroup := Trim(Copy(ATail, AStart, AIndex - AStart));
  Result := (ADepth = 0) and (BracketDelta(ATail[AIndex]) < 0);
  if Result and (mGroup <> '') then
  begin
    AGroups := AGroups + [mGroup];
  end
  else if (ADepth = 1) and (ATail[AIndex] = ';') then
  begin
    AGroups := AGroups + [mGroup];
    AStart := AIndex + 1;
  end;
end;

/// <summary>Zerlegt "(A: Integer = 1; const B: string): Boolean" in Parametergruppen und den Rest.</summary>
function SplitParameters(const ATail: string; out AGroups: TArray<string>; out AAfter: string): Boolean;
var
  mIndex, mDepth, mStart: Integer;
  mQuoted: Boolean;
  mTail: string;
begin
  AGroups := nil;
  mTail := Trim(ATail);
  AAfter := mTail;
  Result := (mTail <> '') and (mTail[1] = '(');
  mDepth := 0;
  mQuoted := False;
  mStart := 2;
  mIndex := 1;
  while Result and (mIndex <= Length(mTail)) do
  begin
    if mTail[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted and SplitStep(mTail, mIndex, mDepth, mStart, AGroups) then
    begin
      AAfter := Copy(mTail, mIndex + 1, MaxInt);
      Exit;
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

/// <summary>Position des "=" eines Standardwerts in AGroup, 0 ohne.</summary>
function DefaultPos(const AGroup: string): Integer;
var
  mIndex, mDepth: Integer;
  mQuoted: Boolean;
begin
  mDepth := 0;
  mQuoted := False;
  for mIndex := 1 to Length(AGroup) do
  begin
    if AGroup[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end;
    if mQuoted then
    begin
      Continue;
    end;
    case AGroup[mIndex] of
      '(', '[', '<':
        Inc(mDepth);
      ')', ']', '>':
        Dec(mDepth);
      '=':
        if mDepth = 0 then
        begin
          Exit(mIndex);
        end;
    end;
  end;
  Result := 0;
end;

/// <summary>Namen einer Parametergruppe in Kleinbuchstaben ohne const/var/out, z. B. "a,b".</summary>
function GroupNames(const AGroup: string): string;
const
  cModifiers: array[0..3] of string = ('constref', 'const', 'var', 'out');
var
  mColon, mIndex: Integer;
  mNames: string;
begin
  mColon := Pos(':', AGroup);
  if mColon = 0 then
  begin
    mNames := AGroup;
  end
  else
  begin
    mNames := Copy(AGroup, 1, mColon - 1);
  end;
  mNames := LowerCase(Trim(mNames));
  // Attribute wie [ref] stehen vor den Namen, auch hinter dem Modifizierer: const [ref] A (#1324).
  mNames := WithoutAttributes(mNames);
  for mIndex := 0 to High(cModifiers) do
  begin
    if Pos(cModifiers[mIndex] + ' ', mNames) = 1 then
    begin
      mNames := Trim(Copy(mNames, Length(cModifiers[mIndex]) + 1, MaxInt));
      Break;
    end;
  end;
  Result := StringReplace(StringReplace(mNames, ' ', '', [rfReplaceAll]), #9, '', [rfReplaceAll]);
end;

function JoinGroups(const AGroups: TArray<string>; const AAfter: string): string;
var
  mIndex: Integer;
begin
  Result := '(';
  for mIndex := 0 to High(AGroups) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + '; ';
    end;
    Result := Result + AGroups[mIndex];
  end;
  Result := Result + ')' + AAfter;
end;

/// <summary>Kopf der Deklaration für den Rumpf: Standardwerte entfallen.</summary>
function WithoutDefaults(const ATail: string): string;
var
  mGroups: TArray<string>;
  mAfter: string;
  mIndex, mEquals: Integer;
begin
  if not SplitParameters(ATail, mGroups, mAfter) then
  begin
    Exit(TrimLeft(ATail));
  end;
  for mIndex := 0 to High(mGroups) do
  begin
    mEquals := DefaultPos(mGroups[mIndex]);
    if mEquals > 0 then
    begin
      mGroups[mIndex] := TrimRight(Copy(mGroups[mIndex], 1, mEquals - 1));
    end;
  end;
  Result := JoinGroups(mGroups, mAfter);
end;

/// <summary>Kopf des Rumpfs für die Deklaration; Standardwerte der alten Deklaration bleiben
/// bei gleichnamigen Parametern erhalten.</summary>
function WithDefaultsOf(const ABodyTail, ADeclTail: string): string;
var
  mGroups, mOld: TArray<string>;
  mAfter, mOldAfter: string;
  mIndex, mInner, mEquals: Integer;
begin
  if not SplitParameters(ABodyTail, mGroups, mAfter) then
  begin
    Exit(TrimLeft(ABodyTail));
  end;
  if SplitParameters(ADeclTail, mOld, mOldAfter) then
  begin
    for mIndex := 0 to High(mGroups) do
    begin
      for mInner := 0 to High(mOld) do
      begin
        mEquals := DefaultPos(mOld[mInner]);
        if (mEquals > 0) and (DefaultPos(mGroups[mIndex]) = 0) and
          (GroupNames(mGroups[mIndex]) = GroupNames(Copy(mOld[mInner], 1, mEquals - 1))) then
        begin
          mGroups[mIndex] := mGroups[mIndex] + ' ' + Trim(Copy(mOld[mInner], mEquals, MaxInt));
        end;
      end;
    end;
  end;
  Result := JoinGroups(mGroups, mAfter);
end;

const
  cConventions: array[0..5] of string = ('register', 'pascal', 'cdecl', 'stdcall', 'safecall', 'winapi');
  cDirectives: array[0..20] of string = ('overload', 'inline', 'static', 'virtual', 'dynamic', 'override',
    'abstract', 'reintroduce', 'final', 'message', 'deprecated', 'platform', 'experimental', 'library', 'assembler',
    'varargs', 'external', 'forward', 'unsafe', 'dispid', 'export');
  cModifiers: array[0..3] of string = ('constref', 'const', 'var', 'out');
  cKinds: array[0..4] of string = ('constructor', 'destructor', 'operator', 'function', 'procedure');

/// <summary>Parameter einer Gruppe "const A, B: string = ''" einzeln.</summary>
function GroupParameters(const AGroup: string): TArray<TShapeParameter>;
var
  mGroup, mNames, mTypeName, mModifier, mName: string;
  mEquals, mColon, mSpace: Integer;
  mParameter: TShapeParameter;
begin
  Result := nil;
  mGroup := AGroup;
  mEquals := DefaultPos(mGroup);
  if mEquals > 0 then
  begin
    mGroup := Copy(mGroup, 1, mEquals - 1);
  end;
  mColon := Pos(':', mGroup);
  if mColon > 0 then
  begin
    mNames := Trim(Copy(mGroup, 1, mColon - 1));
    mTypeName := Trim(Copy(mGroup, mColon + 1, MaxInt));
  end
  else
  begin
    mNames := Trim(mGroup);
    mTypeName := '';
  end;
  // Attribute wie [ref] stehen vor den Namen, auch hinter dem Modifizierer: const [ref] A (#1324).
  mNames := WithoutAttributes(mNames);
  mModifier := '';
  mSpace := Pos(' ', mNames);
  if (mSpace > 0) and MatchText(Copy(mNames, 1, mSpace - 1), cModifiers) then
  begin
    mModifier := LowerCase(Copy(mNames, 1, mSpace - 1));
    mNames := Trim(Copy(mNames, mSpace + 1, MaxInt));
  end;
  while Pos('  ', mTypeName) > 0 do
  begin
    mTypeName := StringReplace(mTypeName, '  ', ' ', [rfReplaceAll]);
  end;
  for mName in SplitTopLevel(mNames, ',') do
  begin
    mParameter.Modifier := mModifier;
    mParameter.Name := Trim(mName);
    mParameter.TypeName := mTypeName;
    Result := Result + [mParameter];
  end;
end;

function SameTypeName(const A, B: string): Boolean;
begin
  Result := SameText(StringReplace(A, ' ', '', [rfReplaceAll]), StringReplace(B, ' ', '', [rfReplaceAll]));
end;

/// <summary>Nähe zweier Köpfe für die Zuordnung bei Überladungen; höher = ähnlicher.</summary>
function Closeness(const ADeclaration, ABody: TSignatureShape): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  if Length(ADeclaration.Parameters) = Length(ABody.Parameters) then
  begin
    Inc(Result, 100);
  end;
  for mIndex := 0 to Min(High(ADeclaration.Parameters), High(ABody.Parameters)) do
  begin
    if SameTypeName(ADeclaration.Parameters[mIndex].TypeName, ABody.Parameters[mIndex].TypeName) then
    begin
      Inc(Result, 10);
    end;
    if SameText(ADeclaration.Parameters[mIndex].Name, ABody.Parameters[mIndex].Name) then
    begin
      Inc(Result, 5);
    end;
    if ADeclaration.Parameters[mIndex].Modifier = ABody.Parameters[mIndex].Modifier then
    begin
      Inc(Result, 1);
    end;
  end;
  if SameTypeName(ADeclaration.ResultType, ABody.ResultType) then
  begin
    Inc(Result, 3);
  end;
  if ADeclaration.Kind = ABody.Kind then
  begin
    Inc(Result, 3);
  end;
end;

/// <summary>Aufrufkonvention aus den Direktiven hinter dem Kopf ("overload; stdcall; …"); '' ohne.</summary>
function ConventionOfRest(const ARest: string): string;
var
  mPart, mWord: string;
  mSpace: Integer;
begin
  Result := '';
  for mPart in SplitTopLevel(ARest, ';') do
  begin
    mWord := LowerCase(Trim(mPart));
    mSpace := Pos(' ', mWord);
    if mSpace > 0 then
    begin
      mWord := Copy(mWord, 1, mSpace - 1);
    end;
    if MatchText(mWord, cConventions) then
    begin
      Exit(mWord);
    end;
    if not MatchText(mWord, cDirectives) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Weicht die ausdrücklich angegebene Konvention des Rumpfs von der Deklaration ab?</summary>
function ConventionDiffers(const ABody, ADeclaration: string): Boolean;
var
  mDeclaration: string;
begin
  mDeclaration := ADeclaration;
  if mDeclaration = '' then
  begin
    mDeclaration := 'register';
  end;
  Result := (ABody <> '') and (ABody <> mDeclaration);
end;

{ TClassCompletion }

/// <summary>Überspringt Kommentare ab AIndex.</summary>
procedure SkipComments(const ATokens: TArray<TPascalToken>; var AIndex: Integer);
begin
  while (AIndex <= High(ATokens)) and (ATokens[AIndex].Kind = TPascalTokenKind.Comment) do
  begin
    Inc(AIndex);
  end;
end;

/// <summary>Überspringt die Argumente einer Direktive wie message WM_PAINT oder deprecated 'Grund' bis vor ihr
/// ";".</summary>
procedure SkipDirectiveArguments(const ATokens: TArray<TPascalToken>; var AIndex: Integer);
var
  mDepth: Integer;
begin
  mDepth := 0;
  while (AIndex < High(ATokens)) and not ((mDepth = 0) and ATokens[AIndex + 1].IsSymbol(';')) do
  begin
    if ATokens[AIndex].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATokens[AIndex].IsSymbol(')') then
    begin
      Dec(mDepth);
    end;
    Inc(AIndex);
  end;
end;

/// <summary>Direktiven hinter dem Kopf, der an AEnd endet: "; overload; stdcall;". Merkt die Aufrufkonvention.
/// </summary>
procedure ReadShapeDirectives(const ATokens: TArray<TPascalToken>; const AEnd: TTextPosition;
  var AShape: TSignatureShape);
var
  mIndex: Integer;
begin
  mIndex := 0;
  while (mIndex <= High(ATokens)) and not (ATokens[mIndex].EndPos = AEnd) do
  begin
    Inc(mIndex);
  end;
  Inc(mIndex);
  SkipComments(ATokens, mIndex);
  while (mIndex <= High(ATokens)) and ATokens[mIndex].IsSymbol(';') do
  begin
    Inc(mIndex);
    SkipComments(ATokens, mIndex);
    if (mIndex > High(ATokens)) or not (MatchText(ATokens[mIndex].Text, cConventions) or
      MatchText(ATokens[mIndex].Text, cDirectives)) then
    begin
      Break;
    end;
    if MatchText(ATokens[mIndex].Text, cConventions) then
    begin
      AShape.Convention := LowerCase(ATokens[mIndex].Text);
      AShape.ConventionRange := TTextRange.Create(ATokens[mIndex].StartPos, ATokens[mIndex].EndPos);
    end;
    SkipDirectiveArguments(ATokens, mIndex);
    Inc(mIndex);
    SkipComments(ATokens, mIndex);
  end;
end;

/// <summary>Art der Routine im Kopf AHeader (constructor, function …); '' ohne.</summary>
function KindOfHeader(const AHeader: string): string;
var
  mWord: string;
begin
  for mWord in cKinds do
  begin
    if HasWord(AHeader, mWord) then
    begin
      Exit(mWord);
    end;
  end;
  Result := '';
end;

class function TClassCompletion.Shape(ATree: TSyntaxTree; const AText: string; const ASymbol: TIndexSymbol;
  out AShape: TSignatureShape): Boolean;
var
  mTail: TSignatureTail;
  mText, mAfter, mGroup, mRest: string;
  mGroups: TArray<string>;
begin
  AShape := Default(TSignatureShape);
  Result := SignatureTail(ATree, AText, ASymbol, mTail);
  if not Result then
  begin
    Exit;
  end;
  // Verglichen wird der Kopf ohne Kommentare und Direktiven (#1324).
  mText := CleanTail(ATree.Tokens, mTail.NameToken + 1, mTail.LastToken, AShape.Conditional);
  AShape.Kind := KindOfHeader(TRoutineSignatures.Head(RangeText(TTextLines.SplitLines(AText), ASymbol.Range), mRest));
  if SplitParameters(mText, mGroups, mAfter) then
  begin
    for mGroup in mGroups do
    begin
      AShape.Parameters := AShape.Parameters + GroupParameters(mGroup);
    end;
  end;
  mAfter := Trim(mAfter);
  if StartsStr(':', mAfter) then
  begin
    AShape.ResultType := Trim(Copy(mAfter, 2, MaxInt));
  end;
  ReadShapeDirectives(ATree.Tokens, mTail.Range.EndPos, AShape);
end;

class function TClassCompletion.Pairs(ATree: TSyntaxTree; const AText: string): TArray<TSignaturePair>;
var
  mItems: TArray<TUnmatchedMethod>;
  mShapes: TArray<TSignatureShape>;
  mValid: TArray<Boolean>;
  mIndex, mOther: Integer;
  mPair: TSignaturePair;

  function Candidate(A, B: Integer): Boolean;
  begin
    Result := (A <> B) and mValid[A] and mValid[B] and (mItems[A].Declared <> mItems[B].Declared) and
      SameText(mItems[A].TypeName, mItems[B].TypeName) and SameText(mItems[A].Symbol.Name, mItems[B].Symbol.Name);
  end;

  function Score(A, B: Integer): Integer;
  begin
    if mItems[A].Declared then
    begin
      Result := Closeness(mShapes[A], mShapes[B]);
    end
    else
    begin
      Result := Closeness(mShapes[B], mShapes[A]);
    end;
  end;

  /// <summary>Eindeutig nächstliegender Partner von A; -1 ohne oder bei Gleichstand.</summary>
  function Best(A: Integer): Integer;
  var
    B, mTop, mCount: Integer;
  begin
    Result := -1;
    mTop := -1;
    mCount := 0;
    for B := 0 to High(mItems) do
    begin
      if Candidate(A, B) then
      begin
        if Score(A, B) > mTop then
        begin
          mTop := Score(A, B);
          Result := B;
          mCount := 1;
        end
        else if Score(A, B) = mTop then
        begin
          Inc(mCount);
        end;
      end;
    end;
    if mCount <> 1 then
    begin
      Result := -1;
    end;
  end;

begin
  Result := nil;
  mItems := Unmatched(ATree, AText);
  SetLength(mShapes, Length(mItems));
  SetLength(mValid, Length(mItems));
  for mIndex := 0 to High(mItems) do
  begin
    mValid[mIndex] := Shape(ATree, AText, mItems[mIndex].Symbol, mShapes[mIndex]);
  end;
  for mIndex := 0 to High(mItems) do
  begin
    if mItems[mIndex].Declared then
    begin
      Continue;
    end;
    mOther := Best(mIndex);
    if (mOther < 0) or (Best(mOther) <> mIndex) then
    begin
      Continue;
    end;
    mPair.Declaration := mItems[mOther];
    mPair.Body := mItems[mIndex];
    mPair.DeclarationShape := mShapes[mOther];
    mPair.BodyShape := mShapes[mIndex];
    Result := Result + [mPair];
  end;
end;

class function TClassCompletion.PairFixes(ATree: TSyntaxTree; const AText: string; const APair: TSignaturePair;
  out AFixes: TArray<TCodeAction>): Boolean;
var
  mDeclRange, mBodyRange: TTextRange;
  mDeclTail, mBodyTail, mDeclTailText, mConvention: string;
  mFix: TCodeAction;
  mName: string;
begin
  AFixes := nil;
  Result := SignatureTail(ATree, AText, APair.Declaration.Symbol, mDeclRange, mDeclTail) and
    SignatureTail(ATree, AText, APair.Body.Symbol, mBodyRange, mBodyTail);
  if not Result then
  begin
    Exit;
  end;
  mName := APair.Body.Symbol.Name;
  mFix := Default(TCodeAction);
  mFix.Kind := cQuickFixKind;
  mFix.Title := cTexts[TClassCompletionText.AlignTheImplementationOfWith].Fmt([mName]);
  mFix.Edits := [TTextEdit.Create(mBodyRange, WithoutDefaults(mDeclTail))];
  // Eine abweichende Konvention im Rumpf übernimmt die der Deklaration (ohne Angabe register).
  if (APair.BodyShape.Convention <> '') and (APair.BodyShape.Convention <> APair.DeclarationShape.Convention) then
  begin
    mConvention := APair.DeclarationShape.Convention;
    if mConvention = '' then
    begin
      mConvention := 'register';
    end;
    mFix.Edits := mFix.Edits + [TTextEdit.Create(APair.BodyShape.ConventionRange, mConvention)];
  end;
  AFixes := AFixes + [mFix];
  mFix.Title := cTexts[TClassCompletionText.AlignTheDeclarationOfWith].Fmt([mName]);
  mDeclTailText := WithDefaultsOf(mBodyTail, mDeclTail);
  mFix.Edits := nil;
  if (APair.BodyShape.Convention <> '') and (APair.BodyShape.Convention <> APair.DeclarationShape.Convention) then
  begin
    if APair.DeclarationShape.Convention <> '' then
    begin
      mFix.Edits := [TTextEdit.Create(APair.DeclarationShape.ConventionRange, APair.BodyShape.Convention)];
    end
    else
    begin
      mDeclTailText := mDeclTailText + '; ' + APair.BodyShape.Convention;
    end;
  end;
  mFix.Edits := [TTextEdit.Create(mDeclRange, mDeclTailText)] + mFix.Edits;
  AFixes := AFixes + [mFix];
end;


type
  /// <summary>Zuordnung von Deklarationen und Rümpfen eines Typs (Unmatched, DeclaredMethods).</summary>
  TTypeMatch = record
    TypeName: string;
    Declarations: TArray<TIndexSymbol>;
    DeclarationHeaders: TArray<string>;
    /// <summary>Rumpf je Deklaration als Index in Bodies; -1 ohne Rumpf, -2 übergangen (abstract, external,
    /// forward).</summary>
    BodyOf: TArray<Integer>;
    Bodies: TArray<TIndexSymbol>;
    BodyHeaders: TArray<string>;
    BodyUsed: TArray<Boolean>;
  end;

type
  /// <summary>Ordnet die Methoden der Typen einer Datei ihren Rümpfen zu.</summary>
  TMethodMatcher = record
    Lines: TArray<string>;
    UnitIndex: TUnitIndex;
    TypeRanges: TArray<TTextRange>;
    /// <summary>Schlüssel und Aufrufkonvention je Rumpf des gerade zugeordneten Typs.</summary>
    BodyKeys: TArray<string>;
    BodyConventions: TArray<string>;
    function IsGeneric(const AType: TIndexSymbol): Boolean;
    function IsGenericOuter(const AType: TIndexSymbol; const AName: string): Boolean;
    function TypeMask(const AType: TIndexSymbol): string;
    function InAnyType(ALine: Integer): Boolean;
    function FreeBody(const AMatch: TTypeMatch; const AKey: string): Integer;
    procedure AddBody(var AMatch: TTypeMatch; const ASymbol: TIndexSymbol; const AHeader, ARest: string);
    procedure CollectMembers(const AType: TIndexSymbol; var AMatch: TTypeMatch);
    function BodyFor(var AMatch: TTypeMatch; ADeclaration: Integer): Integer;
    function MatchType(const AType: TIndexSymbol): TTypeMatch;
  end;

/// <summary>Generisch ist ein Typ mit Typparametern; die kennt der Index nicht immer, dann steht "&lt;" hinter dem
/// Namen.</summary>
function TMethodMatcher.IsGeneric(const AType: TIndexSymbol): Boolean;
var
  mRest: string;
begin
  mRest := Copy(Lines[AType.SelectionRange.EndPos.Line], AType.SelectionRange.EndPos.Character + 1, MaxInt);
  Result := (AType.TypeParams <> '') or TrimLeft(mRest).StartsWith('<');
end;

/// <summary>Ist der Typ AName, der AType umschließt, generisch?</summary>
function TMethodMatcher.IsGenericOuter(const AType: TIndexSymbol; const AName: string): Boolean;
var
  mOuter: TIndexSymbol;
begin
  for mOuter in UnitIndex.Symbols do
  begin
    if (mOuter.Kind in cTypeKinds) and SameText(TypeNameOf(mOuter), AName) and
      ContainsLine(mOuter.Range, AType.Range.StartPos.Line) then
    begin
      Exit(IsGeneric(mOuter));
    end;
  end;
  Result := False;
end;

/// <summary>Maske wie TRoutineSignatures.QualifierMask für den Typ AType: je umschließendem Typ '1' oder '0',
/// zuletzt AType selbst ('0', generische Typen werden übergangen).</summary>
function TMethodMatcher.TypeMask(const AType: TIndexSymbol): string;
var
  mParts: TArray<string>;
  mPrefix: string;
  mPart: Integer;
begin
  Result := '';
  mParts := TypeNameOf(AType).Split(['.']);
  mPrefix := '';
  for mPart := 0 to High(mParts) - 1 do
  begin
    if mPrefix <> '' then
    begin
      mPrefix := mPrefix + '.';
    end;
    mPrefix := mPrefix + mParts[mPart];
    if IsGenericOuter(AType, mPrefix) then
    begin
      Result := Result + '1';
    end
    else
    begin
      Result := Result + '0';
    end;
  end;
  Result := Result + '0';
end;

/// <summary>Steht ALine in irgendeinem Typ der Datei? Dann ist es eine Deklaration, kein Rumpf, auch wenn der Typ
/// ein gleichnamiger generischer ist (THashTable neben THashTable&lt;T&gt;, #1325).</summary>
function TMethodMatcher.InAnyType(ALine: Integer): Boolean;
var
  mRange: TTextRange;
begin
  for mRange in TypeRanges do
  begin
    if ContainsLine(mRange, ALine) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TMethodMatcher.FreeBody(const AMatch: TTypeMatch; const AKey: string): Integer;
var
  mCandidate: Integer;
begin
  for mCandidate := 0 to High(BodyKeys) do
  begin
    if not AMatch.BodyUsed[mCandidate] and (BodyKeys[mCandidate] = AKey) then
    begin
      Exit(mCandidate);
    end;
  end;
  Result := -1;
end;

procedure TMethodMatcher.AddBody(var AMatch: TTypeMatch; const ASymbol: TIndexSymbol; const AHeader, ARest: string);
begin
  AMatch.Bodies := AMatch.Bodies + [ASymbol];
  AMatch.BodyHeaders := AMatch.BodyHeaders + [AHeader];
  AMatch.BodyUsed := AMatch.BodyUsed + [False];
  BodyKeys := BodyKeys + [LowerCase(ASymbol.Name) + TRoutineSignatures.ParameterKey(AHeader) +
    TRoutineSignatures.ResultKey(AHeader)];
  BodyConventions := BodyConventions + [ConventionOfRest(ARest)];
end;

/// <summary>Deklarationen in AType und Rümpfe des Typs AMatch.TypeName.</summary>
procedure TMethodMatcher.CollectMembers(const AType: TIndexSymbol; var AMatch: TTypeMatch);
var
  mSymbol: TIndexSymbol;
  mMask, mHeader, mRest: string;
begin
  mMask := TypeMask(AType);
  for mSymbol in UnitIndex.Symbols do
  begin
    if not (mSymbol.Kind in cMethodKinds) or not SameText(mSymbol.Container, AMatch.TypeName) then
    begin
      Continue;
    end;
    mHeader := TRoutineSignatures.Head(RangeText(Lines, mSymbol.Range), mRest);
    if ContainsLine(AType.Range, mSymbol.Range.StartPos.Line) then
    begin
      AMatch.Declarations := AMatch.Declarations + [mSymbol];
      AMatch.DeclarationHeaders := AMatch.DeclarationHeaders + [mHeader];
    end
    // Deklarationen und Rümpfe eines gleichnamigen generischen Typs (TProperty<T>.Create) gehören nicht dazu;
    // mit bedingten Direktiven im Qualifizierer ('?') zählt der Rumpf wie bisher.
    else if not InAnyType(mSymbol.Range.StartPos.Line) and
      MatchStr(TRoutineSignatures.QualifierMask(mHeader, mSymbol.Name), [mMask, '?']) then
    begin
      AddBody(AMatch, mSymbol, mHeader, mRest);
    end;
  end;
end;

/// <summary>Rumpf zur Deklaration ADeclaration als Index in Bodies und belegt ihn; -1 ohne, -2 übergangen
/// (abstract, external, forward).</summary>
function TMethodMatcher.BodyFor(var AMatch: TTypeMatch; ADeclaration: Integer): Integer;
var
  mSymbol: TIndexSymbol;
  mRest, mHeader: string;
begin
  mSymbol := AMatch.Declarations[ADeclaration];
  TRoutineSignatures.Head(RangeText(Lines, mSymbol.Range), mRest);
  if HasWord(mRest, 'abstract') or HasWord(mRest, 'external') or HasWord(mRest, 'forward') then
  begin
    Exit(-2);
  end;
  mHeader := AMatch.DeclarationHeaders[ADeclaration];
  Result := FreeBody(AMatch, LowerCase(mSymbol.Name) + TRoutineSignatures.ParameterKey(mHeader) +
    TRoutineSignatures.ResultKey(mHeader));
  // Ohne Parameterliste im Rumpf passt er zur ersten Deklaration gleichen Namens.
  if Result < 0 then
  begin
    Result := FreeBody(AMatch, LowerCase(mSymbol.Name));
  end;
  // Eine andere ausdrückliche Aufrufkonvention im Rumpf passt nicht (E2037).
  if (Result >= 0) and ConventionDiffers(BodyConventions[Result], ConventionOfRest(mRest)) then
  begin
    Result := -1;
  end;
  if Result >= 0 then
  begin
    AMatch.BodyUsed[Result] := True;
  end;
end;

function TMethodMatcher.MatchType(const AType: TIndexSymbol): TTypeMatch;
var
  mDeclaration: Integer;
begin
  Result := Default(TTypeMatch);
  Result.TypeName := TypeNameOf(AType);
  BodyKeys := nil;
  BodyConventions := nil;
  CollectMembers(AType, Result);
  SetLength(Result.BodyOf, Length(Result.Declarations));
  for mDeclaration := 0 to High(Result.Declarations) do
  begin
    Result.BodyOf[mDeclaration] := BodyFor(Result, mDeclaration);
  end;
end;

/// <summary>Deklarationen und Rümpfe je Typ der Datei, in der Reihenfolge der Typen; generische Typen fehlen.
/// </summary>
function MatchMethods(ATree: TSyntaxTree; const AText: string): TArray<TTypeMatch>;
var
  mMatcher: TMethodMatcher;
  mType: TIndexSymbol;
begin
  Result := nil;
  mMatcher := Default(TMethodMatcher);
  mMatcher.Lines := TTextLines.SplitLines(AText);
  mMatcher.UnitIndex := TIndexExtractor.Extract(ATree, '');
  for mType in mMatcher.UnitIndex.Symbols do
  begin
    if mType.Kind in cTypeKinds then
    begin
      mMatcher.TypeRanges := mMatcher.TypeRanges + [mType.Range];
    end;
  end;
  for mType in mMatcher.UnitIndex.Symbols do
  begin
    // Generische Typen brauchen die Typparameter im Kopf; die kennt der Index nicht.
    if (mType.Kind in cTypeKinds) and not mMatcher.IsGeneric(mType) then
    begin
      Result := Result + [mMatcher.MatchType(mType)];
    end;
  end;
end;

class function TClassCompletion.Unmatched(ATree: TSyntaxTree; const AText: string): TArray<TUnmatchedMethod>;
var
  mMatch: TTypeMatch;
  mIndex: Integer;
  mItem: TUnmatchedMethod;
begin
  Result := nil;
  for mMatch in MatchMethods(ATree, AText) do
  begin
    for mIndex := 0 to High(mMatch.Declarations) do
    begin
      if mMatch.BodyOf[mIndex] = -1 then
      begin
        mItem := Default(TUnmatchedMethod);
        mItem.TypeName := mMatch.TypeName;
        mItem.Symbol := mMatch.Declarations[mIndex];
        mItem.Declared := True;
        mItem.Header := mMatch.DeclarationHeaders[mIndex];
        Result := Result + [mItem];
      end;
    end;
    for mIndex := 0 to High(mMatch.Bodies) do
    begin
      if not mMatch.BodyUsed[mIndex] then
      begin
        mItem := Default(TUnmatchedMethod);
        mItem.TypeName := mMatch.TypeName;
        mItem.Symbol := mMatch.Bodies[mIndex];
        mItem.Header := mMatch.BodyHeaders[mIndex];
        Result := Result + [mItem];
      end;
    end;
  end;
end;

class function TClassCompletion.DeclaredMethods(ATree: TSyntaxTree; const AText: string): TArray<TDeclaredMethod>;
var
  mMatches: TArray<TTypeMatch>;
  mTypeIndex, mIndex: Integer;
  mItem: TDeclaredMethod;
begin
  Result := nil;
  mMatches := MatchMethods(ATree, AText);
  for mTypeIndex := 0 to High(mMatches) do
  begin
    for mIndex := 0 to High(mMatches[mTypeIndex].Declarations) do
    begin
      if mMatches[mTypeIndex].BodyOf[mIndex] = -2 then
      begin
        Continue;
      end;
      mItem := Default(TDeclaredMethod);
      mItem.TypeName := mMatches[mTypeIndex].TypeName;
      mItem.TypeOrder := mTypeIndex;
      mItem.DeclarationOrder := mIndex;
      mItem.Declaration := mMatches[mTypeIndex].Declarations[mIndex];
      mItem.HasBody := mMatches[mTypeIndex].BodyOf[mIndex] >= 0;
      if mItem.HasBody then
      begin
        mItem.Body := mMatches[mTypeIndex].Bodies[mMatches[mTypeIndex].BodyOf[mIndex]];
      end;
      Result := Result + [mItem];
    end;
  end;
end;

/// <summary>Typ ATypeName ("TAussen.TInnen") in AUnit; False ohne.</summary>
function FindTypeNamed(const AUnit: TUnitIndex; const ATypeName: string; out AType: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in cTypeKinds) and SameText(TypeNameOf(mSymbol), ATypeName) then
    begin
      AType := mSymbol;
      Exit(True);
    end;
  end;
  AType := Default(TIndexSymbol);
  Result := False;
end;

/// <summary>Deklariert AType schon eine Methode namens AName?</summary>
function DeclaresMethod(const AUnit: TUnitIndex; const AType: TIndexSymbol; const ATypeName, AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in cMethodKinds) and SameText(mSymbol.Container, ATypeName) and SameText(mSymbol.Name, AName) and
      ContainsLine(AType.Range, mSymbol.Range.StartPos.Line) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Deklaration zum Rumpf AMethod: "procedure TFoo.Bar(A: Integer)" wird "procedure Bar(A: Integer);",
/// mit overload, wenn AType den Namen schon deklariert; '' ohne Qualifizierer.</summary>
function DeclarationOfBody(const AUnit: TUnitIndex; const AType: TIndexSymbol; const AMethod: TUnmatchedMethod): string;
var
  mIndex: Integer;
begin
  mIndex := Pos(LowerCase(AMethod.TypeName + '.'), LowerCase(AMethod.Header));
  if mIndex = 0 then
  begin
    Exit('');
  end;
  Result := Copy(AMethod.Header, 1, mIndex - 1) + Copy(AMethod.Header, mIndex + Length(AMethod.TypeName) + 1,
    MaxInt) + ';';
  if DeclaresMethod(AUnit, AType, AMethod.TypeName, AMethod.Symbol.Name) and not HasWord(Result, 'overload') then
  begin
    Result := Result + ' overload;';
  end;
end;

/// <summary>Einfügung in einen vorhandenen private-Abschnitt (nicht strict private) direkt im Typ.</summary>
function PrivateSectionEdit(const ALines: TArray<string>; const AType: TIndexSymbol;
  const ADeclaration, ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  mLine: Integer;
begin
  AEdit := Default(TTextEdit);
  for mLine := AType.Range.StartPos.Line + 1 to AType.Range.EndPos.Line - 1 do
  begin
    if SameText(Trim(ALines[mLine]), 'private') then
    begin
      AEdit := TTextEdit.Create(TTextRange.Create(mLine, Length(ALines[mLine]), mLine, Length(ALines[mLine])),
        ALineBreak + TTextLines.IndentOf(ALines[mLine]) + '  ' + ADeclaration);
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Neuer private-Abschnitt mit ADeclaration vor dem "end" des Typs.</summary>
function NewSectionEdit(const ALines: TArray<string>; const AType: TIndexSymbol;
  const ADeclaration, ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  mEndLine: Integer;
  mIndent: string;
begin
  AEdit := Default(TTextEdit);
  mEndLine := AType.Range.EndPos.Line;
  Result := LowerCase(TrimLeft(ALines[mEndLine])).StartsWith('end');
  if Result then
  begin
    mIndent := TTextLines.IndentOf(ALines[mEndLine]);
    AEdit := TTextEdit.Create(TTextRange.Create(mEndLine, 0, mEndLine, 0),
      mIndent + 'private' + ALineBreak + mIndent + '  ' + ADeclaration + ALineBreak);
  end;
end;

class function TClassCompletion.AddDeclaration(ATree: TSyntaxTree; const AText: string;
  const AMethod: TUnmatchedMethod; out AEdit: TTextEdit): Boolean;
var
  mLines: TArray<string>;
  mUnit: TUnitIndex;
  mType: TIndexSymbol;
  mDeclaration, mLB: string;
begin
  AEdit := Default(TTextEdit);
  if AMethod.Declared then
  begin
    Exit(False);
  end;
  mLines := TTextLines.SplitLines(AText);
  mUnit := TIndexExtractor.Extract(ATree, '');
  if not FindTypeNamed(mUnit, AMethod.TypeName, mType) or (mType.Range.EndPos.Line <= mType.Range.StartPos.Line) or
    (mType.Range.EndPos.Line > High(mLines)) then
  begin
    Exit(False);
  end;
  mDeclaration := DeclarationOfBody(mUnit, mType, AMethod);
  mLB := TTextLines.LineBreakOf(AText);
  Result := (mDeclaration <> '') and (PrivateSectionEdit(mLines, mType, mDeclaration, mLB, AEdit) or
    NewSectionEdit(mLines, mType, mDeclaration, mLB, AEdit));
end;

class function TClassCompletion.BodyEdit(ATree: TSyntaxTree; const AText, ATypeName, ABody: string;
  out AEdit: TTextEdit): Boolean;
begin
  Result := BodyEdit(ATree, AText, ATypeName, ABody, TClassBodyOptions.Default, AEdit);
end;

/// <summary>Zeile von "implementation"; 0 ohne.</summary>
function ImplementationLine(ATree: TSyntaxTree): Integer;
var
  mToken: TPascalToken;
begin
  for mToken in ATree.Tokens do
  begin
    if mToken.IsKeyword('implementation') then
    begin
      Exit(mToken.StartPos.Line);
    end;
  end;
  Result := 0;
end;

/// <summary>ABodies mit dem Kommentar zu AShape, wenn ab AFromLine (implementation) noch keiner steht (#1835).
/// </summary>
function WithTypeComment(const ALines: TArray<string>; AFromLine: Integer; const AShape: TTypeShape;
  const ABodies, ALineBreak: string; const AOptions: TClassBodyOptions): string;
begin
  Result := ABodies;
  if not TClassBodies.HasTypeComment(ALines, AFromLine, AShape.TypeName) then
  begin
    Result := TClassBodies.Wrapped(AShape, AOptions, ABodies, ALineBreak);
  end;
end;

class function TClassCompletion.BodyEdit(ATree: TSyntaxTree; const AText, ATypeName, ABody: string;
  const AOptions: TClassBodyOptions; out AEdit: TTextEdit): Boolean;
var
  mLines: TArray<string>;
  mUnit: TUnitIndex;
  mSymbol, mType: TIndexSymbol;
  mLastLine, mInsertLine: Integer;
  mLB: string;
begin
  AEdit := Default(TTextEdit);
  mLines := TTextLines.SplitLines(AText);
  mUnit := TIndexExtractor.Extract(ATree, '');
  if not FindTypeNamed(mUnit, ATypeName, mType) then
  begin
    Exit(False);
  end;
  mLastLine := -1;
  for mSymbol in mUnit.Symbols do
  begin
    if (mSymbol.Kind in cMethodKinds) and SameText(mSymbol.Container, ATypeName) and
      not ContainsLine(mType.Range, mSymbol.Range.StartPos.Line) and (mSymbol.Range.EndPos.Line > mLastLine) then
    begin
      mLastLine := mSymbol.Range.EndPos.Line;
    end;
  end;
  mLB := TTextLines.LineBreakOf(AText);
  if mLastLine >= 0 then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(mLastLine, Length(mLines[mLastLine]), mLastLine,
      Length(mLines[mLastLine])), mLB + mLB + ABody);
    Exit(True);
  end;
  mInsertLine := ImplementationEndLine(ATree);
  Result := mInsertLine >= 0;
  if Result then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(mInsertLine, 0, mInsertLine, 0),
      WithTypeComment(mLines, ImplementationLine(ATree), TTypeShape.Read(mUnit, mLines, ATypeName), ABody, mLB,
      AOptions) + mLB + mLB);
  end;
end;

/// <summary>Innerster Typ in Zeile ALine; False ohne.</summary>
function InnermostType(const AUnit: TUnitIndex; ALine: Integer; out AType: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  AType := Default(TIndexSymbol);
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind in cTypeKinds) and ContainsLine(mSymbol.Range, ALine) and
      (not Result or (mSymbol.Range.StartPos.Line >= AType.Range.StartPos.Line)) then
    begin
      AType := mSymbol;
      Result := True;
    end;
  end;
end;

type
  /// <summary>Methoden eines Typs ohne Rumpf für MissingBodies.</summary>
  TBodyPlan = record
    TypeName: string;
    Declarations: TArray<TIndexSymbol>;
    /// <summary>Schlüssel der vorhandenen Rümpfe (Name und Parameter, klein).</summary>
    Implemented: TArray<string>;
    /// <summary>Letzte Zeile der vorhandenen Rümpfe; -1 ohne.</summary>
    LastLine: Integer;
    Missing: TArray<TIndexSymbol>;
    /// <summary>Der Cursor steht auf der fehlenden Methode; nur sie wird erzeugt.</summary>
    OnMethod: Boolean;
  end;

/// <summary>Deklarationen in AType und Schlüssel der vorhandenen Rümpfe.</summary>
procedure CollectTypeMethods(const ALines: TArray<string>; const AUnit: TUnitIndex; const AType: TIndexSymbol;
  var APlan: TBodyPlan);
var
  mSymbol: TIndexSymbol;
  mRest: string;
begin
  APlan.LastLine := -1;
  for mSymbol in AUnit.Symbols do
  begin
    if not (mSymbol.Kind in cMethodKinds) or not SameText(mSymbol.Container, APlan.TypeName) then
    begin
      Continue;
    end;
    if ContainsLine(AType.Range, mSymbol.Range.StartPos.Line) then
    begin
      APlan.Declarations := APlan.Declarations + [mSymbol];
    end
    else
    begin
      APlan.Implemented := APlan.Implemented + [LowerCase(mSymbol.Name) + TRoutineSignatures.ParameterKey(
        TRoutineSignatures.Head(RangeText(ALines, mSymbol.Range), mRest))];
      APlan.LastLine := Max(APlan.LastLine, mSymbol.Range.EndPos.Line);
    end;
  end;
end;

/// <summary>Nimmt den Rumpf zu ASymbol aus AImplemented; False, wenn keiner da ist. Ohne Parameterliste in der
/// Implementierung passt sie zur ersten Deklaration gleichen Namens.</summary>
function TakeImplemented(var AImplemented: TArray<string>; const ASymbol: TIndexSymbol;
  const AHeader: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexStr(LowerCase(ASymbol.Name) + TRoutineSignatures.ParameterKey(AHeader), AImplemented);
  if mIndex < 0 then
  begin
    mIndex := IndexStr(LowerCase(ASymbol.Name), AImplemented);
  end;
  Result := mIndex >= 0;
  if Result then
  begin
    Delete(AImplemented, mIndex, 1);
  end;
end;

/// <summary>Deklarationen ohne Rumpf (abstrakte ausgenommen); steht der Cursor (ALine) auf einer, nur sie.</summary>
procedure FindMissing(const ALines: TArray<string>; ALine: Integer; var APlan: TBodyPlan);
var
  mSymbol: TIndexSymbol;
  mHeader, mRest: string;
begin
  APlan.Missing := nil;
  APlan.OnMethod := False;
  for mSymbol in APlan.Declarations do
  begin
    mHeader := TRoutineSignatures.Head(RangeText(ALines, mSymbol.Range), mRest);
    if HasWord(mRest, 'abstract') or TakeImplemented(APlan.Implemented, mSymbol, mHeader) then
    begin
      Continue;
    end;
    if ContainsLine(mSymbol.Range, ALine) then
    begin
      APlan.Missing := [mSymbol];
      APlan.OnMethod := True;
      Break;
    end;
    APlan.Missing := APlan.Missing + [mSymbol];
  end;
end;

/// <summary>Rümpfe der fehlenden Methoden (vorbefüllt nach AOptions), je mit Zeilenumbruch davor und dahinter.
/// </summary>
function BodiesText(const ALines: TArray<string>; const APlan: TBodyPlan; const AShape: TTypeShape;
  const AOptions: TClassBodyOptions; const ALineBreak: string): string;
var
  mSymbol: TIndexSymbol;
  mHeader, mRest: string;
begin
  Result := '';
  for mSymbol in APlan.Missing do
  begin
    mHeader := QualifiedHeader(TRoutineSignatures.Head(RangeText(ALines, mSymbol.Range), mRest), mSymbol.Name,
      APlan.TypeName);
    if mHeader <> '' then
    begin
      Result := Result + ALineBreak + TClassBodies.Body(AShape, mHeader,
        TClassBodies.DeclarationText(ALines, mSymbol.Range), mSymbol.Name, AOptions, ALineBreak) + ALineBreak;
    end;
  end;
end;

/// <summary>Rang der Deklaration ASymbol: Gruppe, Stelle darin, Deklarationsreihenfolge.</summary>
function RankKey(const ALines: TArray<string>; const AShape: TTypeShape; const ASymbol: TIndexSymbol;
  AOrder: Integer): Int64;
var
  mRank: TMethodRank;
begin
  mRank := TClassBodies.RankOf(AShape, TClassBodies.DeclarationText(ALines, ASymbol.Range), ASymbol.Name);
  Result := (Int64(mRank.Group) * 100000 + mRank.Sub) * 100000 + AOrder;
end;

/// <summary>Fehlende Methoden nach Lebenszyklus, Zugriffsmethoden, überschriebenen, übrigen (R2, #1836).</summary>
procedure SortMissing(const ALines: TArray<string>; const AShape: TTypeShape; var APlan: TBodyPlan);
var
  mKeys: TArray<Int64>;
  mIndex, mTarget: Integer;
  mKey: Int64;
  mSymbol: TIndexSymbol;
begin
  SetLength(mKeys, Length(APlan.Missing));
  for mIndex := 0 to High(APlan.Missing) do
  begin
    mKeys[mIndex] := RankKey(ALines, AShape, APlan.Missing[mIndex], mIndex);
  end;
  // Einfügen: die Schlüssel sind eindeutig, die Reihenfolge ist damit stabil.
  for mIndex := 1 to High(mKeys) do
  begin
    mKey := mKeys[mIndex];
    mSymbol := APlan.Missing[mIndex];
    mTarget := mIndex - 1;
    while (mTarget >= 0) and (mKeys[mTarget] > mKey) do
    begin
      mKeys[mTarget + 1] := mKeys[mTarget];
      APlan.Missing[mTarget + 1] := APlan.Missing[mTarget];
      Dec(mTarget);
    end;
    mKeys[mTarget + 1] := mKey;
    APlan.Missing[mTarget + 1] := mSymbol;
  end;
end;

/// <summary>Einfügung der Rümpfe ABodies hinter den letzten vorhandenen Rumpf (ALastLine), sonst vor das Ende der
/// implementation; False ohne implementation.</summary>
function BodiesEdit(ATree: TSyntaxTree; const ALines: TArray<string>; ALastLine: Integer;
  const ABodies, ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  mInsertLine: Integer;
begin
  AEdit := Default(TTextEdit);
  if ALastLine >= 0 then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(ALastLine, Length(ALines[ALastLine]), ALastLine,
      Length(ALines[ALastLine])), ALineBreak + Copy(ABodies, 1, Length(ABodies) - Length(ALineBreak)));
    Exit(True);
  end;
  mInsertLine := ImplementationEndLine(ATree);
  Result := mInsertLine >= 0;
  if Result then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(mInsertLine, 0, mInsertLine, 0),
      Copy(ABodies, Length(ALineBreak) + 1, MaxInt) + ALineBreak);
  end;
end;

function BodiesTitle(const APlan: TBodyPlan): string;
begin
  if APlan.OnMethod then
  begin
    Result := cTexts[TClassCompletionText.CreateMethodBodyFor].Fmt([APlan.TypeName, APlan.Missing[0].Name]);
  end
  else if Length(APlan.Missing) = 1 then
  begin
    Result := cTexts[TClassCompletionText.CreateMissingMethodBodyFor].Fmt([APlan.TypeName]);
  end
  else
  begin
    Result := cTexts[TClassCompletionText.CreateMissingMethodBodiesFor].Fmt([Length(APlan.Missing), APlan.TypeName]);
  end;
end;

class function TClassCompletion.MissingBodies(ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; out AAction: TCodeAction): Boolean;
begin
  Result := MissingBodies(ATree, AText, APosition, TClassBodyOptions.Default, AAction);
end;

class function TClassCompletion.MissingBodies(ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const ASettings: TClassCompletionSettings; const AStyle: TFormatStyle;
  out AAction: TCodeAction): Boolean;
begin
  Result := MissingBodies(ATree, AText, APosition, TClassBodyOptions.FromSettings(ASettings, AStyle), AAction);
end;

/// <summary>ABodies (je Rumpf mit Zeilenumbruch davor und dahinter) als erste Rümpfe des Typs AShape: mit dessen
/// Kommentar, wenn ab AFromLine (implementation) noch keiner steht.</summary>
function FirstBodiesText(const ALines: TArray<string>; AFromLine: Integer; const AShape: TTypeShape;
  const ABodies, ALineBreak: string; const AOptions: TClassBodyOptions): string;
var
  mInner: string;
begin
  Result := ABodies;
  if (ABodies = '') or (AOptions.TypeComment = TTypeCommentStyle.Off) then
  begin
    Exit;
  end;
  mInner := Copy(ABodies, Length(ALineBreak) + 1, Length(ABodies) - 2 * Length(ALineBreak));
  Result := ALineBreak + WithTypeComment(ALines, AFromLine, AShape, mInner, ALineBreak, AOptions) + ALineBreak;
end;

class function TClassCompletion.MissingBodies(ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AOptions: TClassBodyOptions; out AAction: TCodeAction): Boolean;
var
  mLines: TArray<string>;
  mUnit: TUnitIndex;
  mType: TIndexSymbol;
  mPlan: TBodyPlan;
  mShape: TTypeShape;
  mRest, mLB, mBodies: string;
  mEdit: TTextEdit;
begin
  AAction := Default(TCodeAction);
  mLines := TTextLines.SplitLines(AText);
  mUnit := TIndexExtractor.Extract(ATree, '');
  // Innerster Typ unter dem Cursor; generische Typen brauchen die Typparameter im Kopf, die kennt der Index nicht.
  Result := InnermostType(mUnit, APosition.Line, mType);
  if Result then
  begin
    mRest := Copy(mLines[mType.SelectionRange.EndPos.Line], mType.SelectionRange.EndPos.Character + 1, MaxInt);
    Result := not TrimLeft(mRest).StartsWith('<');
  end;
  if not Result then
  begin
    Exit;
  end;
  mPlan := Default(TBodyPlan);
  mPlan.TypeName := TypeNameOf(mType);
  CollectTypeMethods(mLines, mUnit, mType, mPlan);
  FindMissing(mLines, APosition.Line, mPlan);
  mShape := TTypeShape.Read(mUnit, mLines, mPlan.TypeName);
  SortMissing(mLines, mShape, mPlan);
  mLB := TTextLines.LineBreakOf(AText);
  mBodies := BodiesText(mLines, mPlan, mShape, AOptions, mLB);
  if mPlan.LastLine < 0 then
  begin
    mBodies := FirstBodiesText(mLines, ImplementationLine(ATree), mShape, mBodies, mLB, AOptions);
  end;
  Result := (mBodies <> '') and BodiesEdit(ATree, mLines, mPlan.LastLine, mBodies, mLB, mEdit);
  if Result then
  begin
    AAction.Edits := [mEdit];
    AAction.Title := BodiesTitle(mPlan);
    AAction.Kind := cRewriteKind;
    AAction.Tag := cClassBodiesTag;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ClassCompletion', cTexts);

end.
