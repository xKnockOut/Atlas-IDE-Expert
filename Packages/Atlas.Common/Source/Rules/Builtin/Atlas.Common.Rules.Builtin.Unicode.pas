unit Atlas.Common.Rules.Builtin.Unicode;

// Unicode-Sicherheit im Quelltext (#150):
//   bidi-control          bidirektionale Steuerzeichen (Trojan Source, CVE-2021-42574)
//   invisible-char        unsichtbare und Nullbreiten-Zeichen
//   control-char          NUL- und Steuerzeichen, U+FFFD und ungültige UTF-8-Bytes
//   confusable-identifier Bezeichner mit Zeichen, die lateinischen gleichen
//   file-encoding-unsupported  UTF-32-Datei (F2438) oder Zeichen im Code, die der Compiler
//                         nicht annimmt (E2038), etwa typografische Anführungszeichen (#1085)
//
// Konfidenz nach Ort und Art: Einbettungen und Überschreibungen
// (U+202A–U+202E, U+2066–U+2069) hoch, ausgeglichen in einem String mit
// RTL-Schrift niedrig; Richtungsmarken (U+200E, U+200F, U+061C) niedrig.
// Unsichtbare Zeichen in Strings und Kommentaren mittel, sonst hoch.
// Bezeichner mit Zeichen aus der Confusables-Liste hoch, andere Mischungen
// von Latein mit Griechisch oder Kyrillisch mittel, sonstige Nicht-ASCII-
// Zeichen niedrig.
//
// Aufeinanderfolgende Zeichen derselben Regel ergeben eine Diagnose über
// den ganzen Bereich. Korrekturen: in Strings durch #$XXXX ersetzen (Wert
// bleibt gleich), sonst entfernen; Bezeichner durch lateinische Zeichen.
//
// Text-Formulardateien (FormText) prüfen bidi-control, invisible-char und
// control-char mit: #nnnn-Folgen werden dekodiert; gemeldet wird in der
// Unit am Feld der Komponente bzw. an der Formularklasse, mit Zeile der
// Formulardatei; die Korrektur ändert die Formulardatei.
//
// Ungültige UTF-8-Bytes: control-char liest die Datei über ReadFile und
// meldet die Fehlstellen aus TFileEncoding.InvalidUtf8 mit Zeile und Spalte,
// sofern der gelesene Text dem geprüften entspricht. Eine ANSI-Datei mit
// einem zufällig gültigen UTF-8-Paar bleibt ANSI (#1327).
// U+FFFD selbst (nicht an einer Fehlstelle): im Code ein Fehler, im String
// ein Hinweis, im Kommentar nichts; dcc übersetzt beides (#1327).
//
// file-encoding-unsupported: UTF-32 erkennt die BOM der über ReadFile gelesenen Bytes; dann meldet
// control-char die Unit nicht, weil ihr Text falsch dekodiert ist. E2038 nur außerhalb von Strings,
// Kommentaren, Direktiven, asm-Blöcken und {$IF…}-Zweigen und nur für sichere Fälle: ASCII ! " ? \ ` | ~
// sowie Satz- und Sonderzeichen jenseits von ASCII (keine Buchstaben, Ziffern, Verbinder wie U+203F;
// Steuer-, Format- und Leerzeichen melden die anderen Regeln). Ein Paar Anführungszeichen auf einer
// Zeile wird zum String; einzelne Zeichen mit eindeutigem ASCII-Gegenstück (– × ≤ …) werden ersetzt.
// Eine UTF-32-Datei lässt sich nicht mit einer Textänderung umkodieren: keine Korrektur (#894).

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TBidiControlRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInvisibleCharRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TControlCharRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TConfusableIdentifierRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Lateinisches Gegenstück eines verwechselbaren Zeichens (kyrillisch "а" → "a"); #0 ohne.</summary>
    class function LatinOf(AChar: Char): Char; static;
  end;

  TFileEncodingUnsupportedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Nimmt der Compiler das Zeichen außerhalb von Strings und Kommentaren sicher nicht an (E2038)?
    /// Satz- und Sonderzeichen, nie Buchstaben, Ziffern oder Verbinder.</summary>
    class function IsIllegal(ACode: Integer): Boolean; static;
  end;

/// <summary>Registriert alle Unicode-Regeln.</summary>
procedure RegisterUnicodeRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TUnicodeText = (CharCount, RemoveChar, RemoveInForm, InFormFile, BidiTitle, Bidi, InvisibleTitle, Invisible,
    ControlTitle, InvalidUtf8, ControlPrefix, Control, InvalidUtf8Form, RejectedTitle, ReplaceWithString,
    ReplaceWithQuoted, CharNotAllowed, Utf32, ConfusableTitle, ReplaceLatin, Confusable, MixedScripts, NonAscii,
    ReplaceWith, ReplaceInForm, Typographic, DoubleQuotes);

const
  cTexts: array[TUnicodeText] of TAtlasText = (
    (De: '%d Zeichen %s'; En: '%d characters %s'),
    (De: 'Zeichen entfernen'; En: 'Remove character'),
    (De: 'In der Formulardatei entfernen'; En: 'Remove in the form file'),
    (De: 'Formulardatei, Zeile %d%s: %s %s'; En: 'Form file, line %d%s: %s %s'),
    (De: 'Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source)';
     En: 'Bidirectional control characters can display code differently from how it is compiled (Trojan Source)'),
    (De: 'Bidirektionales Steuerzeichen, Anzeige und Bedeutung können abweichen (Trojan Source):';
     En: 'Bidirectional control character, display and meaning can differ (Trojan Source):'),
    (De: 'Unsichtbare oder Nullbreiten-Zeichen im Quelltext'; En: 'Invisible or zero-width characters in the source'),
    (De: 'Unsichtbares Zeichen'; En: 'Invisible character'),
    (De: 'NUL- und Steuerzeichen oder ungültige UTF-8-Bytes im Quelltext und in der Formulardatei';
     En: 'NUL and control characters or invalid UTF-8 bytes in the source and in the form file'),
    (De: 'Ungültiges UTF-8-Byte $%s (Byte %d der Datei)'; En: 'Invalid UTF-8 byte $%s (byte %d of the file)'),
    (De: 'Steuerzeichen oder ungültiges Byte '; En: 'Control character or invalid byte '),
    (De: 'Steuerzeichen oder ungültiges Byte'; En: 'Control character or invalid byte'),
    (De: 'Formulardatei, Zeile %d, Spalte %d: ungültiges UTF-8-Byte $%s';
     En: 'Form file, line %d, column %d: invalid UTF-8 byte $%s'),
    (De: 'Datei in UTF-32 oder Zeichen im Code, die der Compiler nicht annimmt (wie F2438, E2038)';
     En: 'File in UTF-32 or characters in the code that the compiler does not accept (like F2438, E2038)'),
    (De: 'Durch den String %s ersetzen'; En: 'Replace with the string %s'),
    (De: 'Durch "%s" ersetzen'; En: 'Replace with "%s"'),
    (De: 'Zeichen ''%s'' (#$%s) ist im Quelltext nicht erlaubt (wie E2038).';
     En: 'Character ''%s'' (#$%s) is not allowed in the source (like E2038).'),
    (De: 'Die Datei ist UTF-32 kodiert; der Compiler liest nur UTF-8, UTF-16 und ANSI (wie F2438). In UTF-8 mit BOM ' +
      'speichern.';
     En: 'The file is UTF-32 encoded; the compiler reads only UTF-8, UTF-16 and ANSI (like F2438). Save it in UTF-8 ' +
      'with BOM.'),
    (De: 'Bezeichner mit Zeichen aus mehreren Schriften oder Nicht-ASCII-Zeichen (Verwechslungsgefahr)';
     En: 'Identifier with characters from several scripts or non-ASCII characters (risk of confusion)'),
    (De: 'Durch "%s" mit lateinischen Zeichen ersetzen'; En: 'Replace with "%s" in Latin characters'),
    (De: 'Bezeichner "%s" enthält Zeichen, die lateinischen gleichen; Verwechslung mit "%s" möglich';
     En: 'Identifier "%s" contains characters resembling Latin ones; confusion with "%s" possible'),
    (De: 'Bezeichner "%s" mischt Schriften'; En: 'Identifier "%s" mixes scripts'),
    (De: 'Bezeichner "%s" enthält Nicht-ASCII-Zeichen'; En: 'Identifier "%s" contains non-ASCII characters'),
    (De: 'Durch %s ersetzen'; En: 'Replace with %s'),
    (De: 'In der Formulardatei durch %s ersetzen'; En: 'Replace with %s in the form file'),
    (De: 'Typografische Anführungszeichen sind im Quelltext nicht erlaubt (wie E2038).';
     En: 'Typographic quotation marks are not allowed in the source (like E2038).'),
    (De: 'Doppelte Anführungszeichen sind im Quelltext nicht erlaubt, Strings stehen in '' (wie E2038).';
     En: 'Double quotation marks are not allowed in the source, strings are enclosed in '' (like E2038).'));

{$SCOPEDENUMS OFF}

type
  {$SCOPEDENUMS ON}
  /// <summary>Wo ein Zeichen steht.</summary>
  TCharPlace = (Code, StringLiteral, Comment);
  /// <summary>Welche Regel ein Zeichen meldet.</summary>
  TCharRule = (Bidi, Invisible, Control);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein auffälliges Zeichen.</summary>
  THit = record
    Code: Integer;
    /// <summary>Offset ab 1 im geprüften Text.</summary>
    Offset: Integer;
    Pos: TTextPosition;
    Confidence: TRuleConfidence;
    /// <summary>Roh im Text; False bei #nnnn in einer Formulardatei.</summary>
    Raw: Boolean;
  end;

  /// <summary>Zusammenhängender Bereich auffälliger Zeichen einer Regel.</summary>
  TRun = record
    Hits: TArray<THit>;
    Place: TCharPlace;
    /// <summary>Hinter dem letzten Zeichen.</summary>
    EndPos: TTextPosition;
    /// <summary>Ende des Bereichs im Text (Offset ab 1, exklusiv).</summary>
    EndOffset: Integer;
    /// <summary>Der umgebende String ist mehrzeilig (''') und lässt sich nicht teilen.</summary>
    MultiLine: Boolean;
  end;

function IsBidiControl(AC: Integer): Boolean;
begin
  case AC of
    $061C, $200E, $200F, $202A..$202E, $2066..$2069:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Richtungsmarke ohne Einbettung: legitim in RTL-Text.</summary>
function IsBidiMark(AC: Integer): Boolean;
begin
  Result := (AC = $061C) or (AC = $200E) or (AC = $200F);
end;

function IsInvisible(AC: Integer): Boolean;
begin
  case AC of
    $00AD, $180E, $200B..$200D, $2060..$2064, $FEFF:
      Result := True;
  else
    Result := False;
  end;
end;

function IsBadControl(AC: Integer): Boolean;
begin
  case AC of
    0..8, 11, 14..31, $7F, $FFFD:
      Result := True;
  else
    Result := False;
  end;
end;

function IsRtlLetter(AC: Char): Boolean;
begin
  case Ord(AC) of
    $0590..$08FF, $FB1D..$FDFF, $FE70..$FEFC:
      Result := True;
  else
    Result := False;
  end;
end;

function Matches(ARule: TCharRule; ACode: Integer): Boolean;
begin
  case ARule of
    TCharRule.Bidi:
      Result := IsBidiControl(ACode);
    TCharRule.Invisible:
      Result := IsInvisible(ACode);
  else
    Result := IsBadControl(ACode);
  end;
end;

function CodeName(ACode: Integer): string;
begin
  Result := 'U+' + IntToHex(ACode, 4);
end;

/// <summary>"U+200B" bzw. "50 Zeichen U+200B, U+200C" für einen Bereich.</summary>
function RunCodes(const ARun: TRun): string;
var
  mCodes: TList<Integer>;
  mHit: THit;
  mCode: Integer;
begin
  mCodes := TList<Integer>.Create;
  try
    for mHit in ARun.Hits do
    begin
      if not mCodes.Contains(mHit.Code) then
      begin
        mCodes.Add(mHit.Code);
      end;
    end;
    Result := '';
    for mCode in mCodes do
    begin
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + CodeName(mCode);
    end;
    if Length(ARun.Hits) > 1 then
    begin
      Result := cTexts[TUnicodeText.CharCount].Fmt([Length(ARun.Hits), Result]);
    end;
  finally
    mCodes.Free;
  end;
end;

/// <summary>Ort jedes Zeichens nach den Token des Baums; ohne Baum alles Code.</summary>
function PlacesOf(const AContext: TRuleContext; out AMultiLine: TArray<Boolean>;
  out ATokenStart, ATokenEnd: TArray<Integer>): TArray<TCharPlace>;
var
  mToken: TPascalToken;
  mIndex, mLast: Integer;
  mPlace: TCharPlace;
begin
  SetLength(Result, Length(AContext.Text) + 1);
  SetLength(AMultiLine, Length(AContext.Text) + 1);
  SetLength(ATokenStart, Length(AContext.Text) + 1);
  SetLength(ATokenEnd, Length(AContext.Text) + 1);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := TCharPlace.Code;
    ATokenStart[mIndex] := mIndex;
    ATokenEnd[mIndex] := mIndex + 1;
  end;
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  for mToken in AContext.Tree.Tokens do
  begin
    case mToken.Kind of
      TPascalTokenKind.StringLiteral:
        mPlace := TCharPlace.StringLiteral;
      TPascalTokenKind.Comment, TPascalTokenKind.Directive:
        mPlace := TCharPlace.Comment;
    else
      Continue;
    end;
    mLast := mToken.Offset + Length(mToken.Text);
    if mLast > Length(AContext.Text) then
    begin
      mLast := Length(AContext.Text);
    end;
    for mIndex := mToken.Offset + 1 to mLast do
    begin
      Result[mIndex] := mPlace;
      AMultiLine[mIndex] := StartsStr('''''''', mToken.Text);
      ATokenStart[mIndex] := mToken.Offset + 1;
      ATokenEnd[mIndex] := mLast + 1;
    end;
  end;
end;

/// <summary>Stehen alle Einbettungen eines Tokens paarweise geschlossen, und enthält es RTL-Schrift?</summary>
function BalancedRtl(const AText: string; AStart, AStop: Integer): Boolean;
var
  mIndex, mEmbeddings, mIsolates: Integer;
  mRtl: Boolean;
begin
  mEmbeddings := 0;
  mIsolates := 0;
  mRtl := False;
  for mIndex := AStart to AStop - 1 do
    case Ord(AText[mIndex]) of
      $202A, $202B, $202D, $202E:
        Inc(mEmbeddings);
      $202C:
        begin
          Dec(mEmbeddings);
          if mEmbeddings < 0 then
          begin
            Exit(False);
          end;
        end;
      $2066..$2068:
        Inc(mIsolates);
      $2069:
        begin
          Dec(mIsolates);
          if mIsolates < 0 then
          begin
            Exit(False);
          end;
        end;
    else
      if IsRtlLetter(AText[mIndex]) then
      begin
        mRtl := True;
      end;
    end;
  Result := mRtl and (mEmbeddings = 0) and (mIsolates = 0);
end;

function ConfidenceOf(ARule: TCharRule; ACode: Integer; APlace: TCharPlace; ABalancedRtl: Boolean): TRuleConfidence;
begin
  Result := TRuleConfidence.High;
  case ARule of
    TCharRule.Bidi:
      if IsBidiMark(ACode) or ((APlace = TCharPlace.StringLiteral) and ABalancedRtl) then
      begin
        Result := TRuleConfidence.Low;
      end;
    TCharRule.Invisible:
      if APlace <> TCharPlace.Code then
      begin
        Result := TRuleConfidence.Medium;
      end;
    TCharRule.Control: ;
  end;
end;

type
  /// <summary>Fasst Treffer zu Bereichen zusammen: gleicher Ort, Zeichen direkt hintereinander.</summary>
  TRunBuilder = class
  private
    FRuns: TArray<TRun>;
    FRun: TRun;
    FOpen: Boolean;
  public
    /// <summary>Schließt den offenen Bereich ab.</summary>
    procedure Flush;
    /// <summary>Hängt einen Treffer an; ein anderer Ort oder eine Lücke beginnt einen neuen Bereich.</summary>
    procedure Add(const AHit: THit; APlace: TCharPlace; AMultiLine: Boolean; AStop: Integer;
      const AEndPos: TTextPosition);
    /// <summary>Alle Bereiche, der offene eingeschlossen.</summary>
    function Runs: TArray<TRun>;
  end;

procedure TRunBuilder.Flush;
begin
  if FOpen then
  begin
    FRuns := FRuns + [FRun];
  end;
  FOpen := False;
end;

procedure TRunBuilder.Add(const AHit: THit; APlace: TCharPlace; AMultiLine: Boolean; AStop: Integer;
  const AEndPos: TTextPosition);
begin
  if FOpen and ((FRun.EndOffset <> AHit.Offset) or (FRun.Place <> APlace)) then
  begin
    Flush;
  end;
  if not FOpen then
  begin
    FRun := Default(TRun);
    FRun.Place := APlace;
    FRun.MultiLine := AMultiLine;
    FOpen := True;
  end;
  FRun.Hits := FRun.Hits + [AHit];
  FRun.EndOffset := AStop;
  FRun.EndPos := AEndPos;
end;

function TRunBuilder.Runs: TArray<TRun>;
begin
  Flush;
  Result := FRuns;
end;

/// <summary>Ein Treffer an APos.</summary>
function MakeHit(ACode, AOffset: Integer; const APos: TTextPosition; ARaw: Boolean;
  AConfidence: TRuleConfidence): THit;
begin
  Result.Code := ACode;
  Result.Offset := AOffset;
  Result.Pos := APos;
  Result.Raw := ARaw;
  Result.Confidence := AConfidence;
end;

/// <summary>Meldet die Regel das Zeichen an AIndex (ab 1)? Eine BOM am Dateianfang ist erlaubt.</summary>
function Flagged(ARule: TCharRule; ACode, AIndex: Integer): Boolean;
begin
  Result := Matches(ARule, ACode) and not ((AIndex = 1) and (ACode = $FEFF));
end;

/// <summary>Zeile und Spalte hinter AChar.</summary>
procedure Advance(AChar: Char; var ALine, AColumn: Integer);
begin
  if AChar = #10 then
  begin
    Inc(ALine);
    AColumn := 0;
  end
  else
  begin
    Inc(AColumn);
  end;
end;

/// <summary>Zusammenhängende Bereiche: gleiche Stelle (Ort), Zeichen direkt hintereinander.</summary>
function RunsOf(ARule: TCharRule; const AContext: TRuleContext): TArray<TRun>;
var
  mPlaces: TArray<TCharPlace>;
  mMultiLine: TArray<Boolean>;
  mTokenStart, mTokenEnd: TArray<Integer>;
  mIndex, mLine, mColumn, mCode: Integer;
  mConfidence: TRuleConfidence;
  mBuilder: TRunBuilder;
begin
  mPlaces := PlacesOf(AContext, mMultiLine, mTokenStart, mTokenEnd);
  mLine := 0;
  mColumn := 0;
  mBuilder := TRunBuilder.Create;
  try
    for mIndex := 1 to Length(AContext.Text) do
    begin
      mCode := Ord(AContext.Text[mIndex]);
      if Flagged(ARule, mCode, mIndex) then
      begin
        mConfidence := ConfidenceOf(ARule, mCode, mPlaces[mIndex],
          BalancedRtl(AContext.Text, mTokenStart[mIndex], mTokenEnd[mIndex]));
        mBuilder.Add(MakeHit(mCode, mIndex, TTextPosition.Create(mLine, mColumn), True, mConfidence),
          mPlaces[mIndex], mMultiLine[mIndex], mIndex + 1, TTextPosition.Create(mLine, mColumn + 1));
      end
      else
      begin
        mBuilder.Flush;
      end;
      Advance(AContext.Text[mIndex], mLine, mColumn);
    end;
    Result := mBuilder.Runs;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Höchste Konfidenz eines Bereichs: ein gefährliches Zeichen macht den ganzen Bereich gefährlich.</summary>
function RunConfidence(const ARun: TRun): TRuleConfidence;
var
  mHit: THit;
begin
  Result := TRuleConfidence.Low;
  for mHit in ARun.Hits do
  begin
    if Ord(mHit.Confidence) > Ord(Result) then
    begin
      Result := mHit.Confidence;
    end;
  end;
end;

/// <summary>"#$200B#$200B" für die Zeichen eines Bereichs.</summary>
function CharLiterals(const ARun: TRun; ADecimal: Boolean): string;
var
  mHit: THit;
begin
  Result := '';
  for mHit in ARun.Hits do
  begin
    if ADecimal then
    begin
      Result := Result + '#' + IntToStr(mHit.Code);
    end
    else
    begin
      Result := Result + '#$' + IntToHex(mHit.Code, 4);
    end;
  end;
end;

/// <summary>Korrektur eines Bereichs in der geprüften Datei; nil ohne passende.</summary>
function RunFixes(const ARun: TRun): TArray<TRuleFix>;
var
  mRange: TTextRange;
begin
  Result := nil;
  mRange := TTextRange.Create(ARun.Hits[0].Pos, ARun.EndPos);
  if ARun.Place = TCharPlace.StringLiteral then
  begin
    // 'a<ZWSP>b' → 'a'#$200B'b': gleicher Wert, sichtbar. Mehrzeilige Strings lassen sich nicht teilen.
    if not ARun.MultiLine then
    begin
      Result := [TRuleFix.Create(cTexts[TUnicodeText.ReplaceWith].Fmt([CharLiterals(ARun, False)]),
        [TRuleEdit.Create(mRange, '''' + CharLiterals(ARun, False) + '''')], True)];
    end;
  end
  else
  begin
    Result := [TRuleFix.Create(cTexts[TUnicodeText.RemoveChar].Text, [TRuleEdit.Create(mRange, '')])];
  end;
end;

function RunRange(const ARun: TRun): TTextRange;
begin
  Result := TTextRange.Create(ARun.Hits[0].Pos, ARun.EndPos);
end;

{ Formulardatei }

type
  /// <summary>Text der Formulardatei mit dem Ort jedes Zeichens; #nnnn-Folgen als eigene Treffer.</summary>
  TFormScan = class
  private
    FText: string;
    FDocument: TDfmDocument;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    /// <summary>Bereiche einer Regel; Place StringLiteral innerhalb von Hochkommas und bei #nnnn.</summary>
    function Runs(ARule: TCharRule): TArray<TRun>;
    /// <summary>Innerstes Objekt und Property an APos; '' ohne.</summary>
    procedure Locate(const APos: TTextPosition; out AObject: TDfmObject; out AProperty: string);
    property Document: TDfmDocument read FDocument;
  end;

constructor TFormScan.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FDocument := TDfmParser.Parse(AText);
end;

destructor TFormScan.Destroy;
begin
  FDocument.Free;
  inherited;
end;

type
  /// <summary>Liest die Bereiche einer Regel aus dem Text einer Formulardatei.</summary>
  TFormRunScanner = class
  private
    FText: string;
    FRule: TCharRule;
    FBuilder: TRunBuilder;
    FIndex: Integer;
    FLine: Integer;
    FColumn: Integer;
    FInQuote: Boolean;
    /// <summary>Treffer von AOffset bis AStop (exklusiv) an der aktuellen Spalte.</summary>
    procedure AddHit(ACode, AOffset, AStop: Integer; APlace: TCharPlace; ARaw: Boolean);
    procedure SkipWhile(const AChars: TSysCharSet);
    procedure ScanQuote;
    procedure ScanCharConstant;
    procedure ScanChar;
  public
    constructor Create(const AText: string; ARule: TCharRule);
    destructor Destroy; override;
    function Run: TArray<TRun>;
  end;

constructor TFormRunScanner.Create(const AText: string; ARule: TCharRule);
begin
  inherited Create;
  FText := AText;
  FRule := ARule;
  FBuilder := TRunBuilder.Create;
end;

destructor TFormRunScanner.Destroy;
begin
  FBuilder.Free;
  inherited;
end;

procedure TFormRunScanner.AddHit(ACode, AOffset, AStop: Integer; APlace: TCharPlace; ARaw: Boolean);
begin
  FBuilder.Add(MakeHit(ACode, AOffset, TTextPosition.Create(FLine, FColumn), ARaw,
    ConfidenceOf(FRule, ACode, APlace, False)), APlace, False, AStop,
    TTextPosition.Create(FLine, FColumn + AStop - AOffset));
end;

procedure TFormRunScanner.SkipWhile(const AChars: TSysCharSet);
begin
  while (FIndex <= Length(FText)) and CharInSet(FText[FIndex], AChars) do
  begin
    Inc(FIndex);
  end;
end;

procedure TFormRunScanner.ScanQuote;
begin
  FBuilder.Flush;
  // '' innerhalb eines Strings ist ein Hochkomma, kein Ende.
  if FInQuote and (FIndex < Length(FText)) and (FText[FIndex + 1] = '''') then
  begin
    Inc(FIndex, 2);
    Inc(FColumn, 2);
    Exit;
  end;
  FInQuote := not FInQuote;
  Inc(FIndex);
  Inc(FColumn);
end;

procedure TFormRunScanner.ScanCharConstant;
var
  mStart, mCode: Integer;
  mDigits: string;
begin
  // Zeichenkonstante #8238 oder #$202E.
  mStart := FIndex;
  Inc(FIndex);
  if (FIndex <= Length(FText)) and (FText[FIndex] = '$') then
  begin
    Inc(FIndex);
    SkipWhile(['0'..'9', 'A'..'F', 'a'..'f']);
    mDigits := '$' + Copy(FText, mStart + 2, FIndex - mStart - 2);
  end
  else
  begin
    SkipWhile(['0'..'9']);
    mDigits := Copy(FText, mStart + 1, FIndex - mStart - 1);
  end;
  // Direkt folgende Konstanten setzen den Bereich fort: #8203#8203 ist eine Folge.
  if TryStrToInt(mDigits, mCode) and Matches(FRule, mCode) then
  begin
    AddHit(mCode, mStart, FIndex, TCharPlace.StringLiteral, False);
  end
  else
  begin
    FBuilder.Flush;
  end;
  Inc(FColumn, FIndex - mStart);
end;

procedure TFormRunScanner.ScanChar;
var
  mCode: Integer;
  mPlace: TCharPlace;
begin
  mCode := Ord(FText[FIndex]);
  if Flagged(FRule, mCode, FIndex) then
  begin
    mPlace := TCharPlace.Code;
    if FInQuote then
    begin
      mPlace := TCharPlace.StringLiteral;
    end;
    AddHit(mCode, FIndex, FIndex + 1, mPlace, True);
  end
  else
  begin
    FBuilder.Flush;
  end;
  Advance(FText[FIndex], FLine, FColumn);
  Inc(FIndex);
end;

function TFormRunScanner.Run: TArray<TRun>;
begin
  FIndex := 1;
  while FIndex <= Length(FText) do
  begin
    if FText[FIndex] = '''' then
    begin
      ScanQuote;
    end
    else if not FInQuote and (FText[FIndex] = '#') then
    begin
      ScanCharConstant;
    end
    else
    begin
      ScanChar;
    end;
  end;
  Result := FBuilder.Runs;
end;

function TFormScan.Runs(ARule: TCharRule): TArray<TRun>;
var
  mScanner: TFormRunScanner;
begin
  mScanner := TFormRunScanner.Create(FText, ARule);
  try
    Result := mScanner.Run;
  finally
    mScanner.Free;
  end;
end;

function Contains(const ARange: TTextRange; const APos: TTextPosition): Boolean;
begin
  Result := ((APos.Line > ARange.StartPos.Line) or ((APos.Line = ARange.StartPos.Line) and
    (APos.Character >= ARange.StartPos.Character))) and ((APos.Line < ARange.EndPos.Line) or
    ((APos.Line = ARange.EndPos.Line) and (APos.Character <= ARange.EndPos.Character)));
end;

procedure TFormScan.Locate(const APos: TTextPosition; out AObject: TDfmObject; out AProperty: string);

  procedure Visit(AObj: TDfmObject);
  var
    mChild: TDfmObject;
    mProp: TDfmProperty;
  begin
    if not Contains(AObj.Range, APos) then
    begin
      Exit;
    end;
    AObject := AObj;
    AProperty := '';
    for mProp in AObj.Properties do
    begin
      if Contains(mProp.ValueRange, APos) or Contains(mProp.NameRange, APos) then
      begin
        AProperty := mProp.Name;
      end;
    end;
    for mChild in AObj.Children do
    begin
      Visit(mChild);
    end;
  end;

begin
  AObject := nil;
  AProperty := '';
  if FDocument.Root <> nil then
  begin
    Visit(FDocument.Root);
  end;
end;

function OnlyReplacement(const ARun: TRun): Boolean;
var
  mHit: THit;
begin
  for mHit in ARun.Hits do
  begin
    if mHit.Code <> $FFFD then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>
/// Schweregrad eines Bereichs, der nur aus U+FFFD besteht (#1327): Off im Kommentar, Hint im String, sonst der
/// der Regel. dcc übersetzt das Ersatzzeichen in Kommentaren und Strings; nur im Code ist es ein Fehler (E2038).
/// Ein Ersatzzeichen im String deutet auf ein beim Umkodieren verlorenes Zeichen hin, ist aber kein Fehler.
/// </summary>
function ReplacementSeverity(ARule: TCharRule; const ARun: TRun): TRuleSeverity;
begin
  Result := TRuleSeverity.Default;
  if (ARule <> TCharRule.Control) or not OnlyReplacement(ARun) then
  begin
    Exit;
  end;
  case ARun.Place of
    TCharPlace.Comment:
      Result := TRuleSeverity.Off;
    TCharPlace.StringLiteral:
      Result := TRuleSeverity.Hint;
    TCharPlace.Code: ;
  end;
end;

/// <summary>Meldet einen Bereich mit dem Schweregrad aus ReplacementSeverity; Off meldet nichts.</summary>
procedure AddRun(ARule: TCharRule; const ARun: TRun; const AReport: IRuleReport; const ARange: TTextRange;
  const AMessage: string; const AFixes: TArray<TRuleFix>);
var
  mSeverity: TRuleSeverity;
begin
  mSeverity := ReplacementSeverity(ARule, ARun);
  if mSeverity = TRuleSeverity.Off then
  begin
    Exit;
  end;
  if mSeverity = TRuleSeverity.Default then
  begin
    AReport.Add(ARange, AMessage, RunConfidence(ARun), AFixes);
  end
  else
  begin
    AReport.AddWithSeverity(ARange, AMessage, mSeverity, AFixes);
  end;
end;

/// <summary>Name der Formularklasse in der Unit; Default(TTextRange) ohne.</summary>
function FormClassRange(const AUnitIndex: TUnitIndex; const AFormClass: string): TTextRange;
var
  mSymbol: TIndexSymbol;
begin
  Result := Default(TTextRange);
  for mSymbol in AUnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and (mSymbol.Container = '') and
      SameText(mSymbol.Name, AFormClass) then
    begin
      Exit(mSymbol.SelectionRange);
    end;
  end;
end;

type
  /// <summary>Meldet die Bereiche einer Regel in der Formulardatei an der passenden Stelle der Unit.</summary>
  TFormCharCheck = class
  private
    FRule: TCharRule;
    FContext: TRuleContext;
    FReport: IRuleReport;
    FWhat: string;
    FScan: TFormScan;
    FCache: IRuleDerivedCache;
    FUnitIndex: TUnitIndex;
    FFormClass: string;
    FClassRange: TTextRange;
    /// <summary>Feld der Komponente in der Formularklasse; sonst die Formularklasse.</summary>
    function FieldRange(AObject: TDfmObject): TTextRange;
    /// <summary>AFix als einzige Korrektur, angewendet auf die Formulardatei.</summary>
    function InFormFile(const AFix: TRuleFix): TArray<TRuleFix>;
    /// <summary>Korrektur in der Formulardatei; nil ohne.</summary>
    function FormFixes(const ARun: TRun): TArray<TRuleFix>;
    procedure ReportRun(const ARun: TRun);
  public
    constructor Create(ARule: TCharRule; const AContext: TRuleContext; const AReport: IRuleReport;
      const AWhat: string);
    destructor Destroy; override;
    /// <summary>ASkipReplacement: Bereiche nur aus U+FFFD übergehen.</summary>
    procedure Run(ASkipReplacement: Boolean);
  end;

constructor TFormCharCheck.Create(ARule: TCharRule; const AContext: TRuleContext; const AReport: IRuleReport;
  const AWhat: string);
begin
  inherited Create;
  FRule := ARule;
  FContext := AContext;
  FReport := AReport;
  FWhat := AWhat;
  FScan := TFormScan.Create(AContext.FormText);
end;

destructor TFormCharCheck.Destroy;
begin
  FScan.Free;
  inherited;
end;

function TFormCharCheck.FieldRange(AObject: TDfmObject): TTextRange;
var
  mSymbol: TIndexSymbol;
begin
  Result := FClassRange;
  if (AObject = nil) or (AObject = FScan.Document.Root) then
  begin
    Exit;
  end;
  for mSymbol in FUnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, FFormClass) and
      SameText(mSymbol.Name, AObject.Name) then
    begin
      Exit(mSymbol.SelectionRange);
    end;
  end;
end;

/// <summary>" (Objekt.Property)" für die Meldung; '' ohne Objekt.</summary>
function WhereText(AObject: TDfmObject; const AProperty: string): string;
begin
  Result := '';
  if AObject = nil then
  begin
    Exit;
  end;
  Result := AObject.Name;
  if AProperty <> '' then
  begin
    Result := Result + '.' + AProperty;
  end;
  if Result <> '' then
  begin
    Result := ' (' + Result + ')';
  end;
end;

function TFormCharCheck.InFormFile(const AFix: TRuleFix): TArray<TRuleFix>;
var
  mFix: TRuleFix;
begin
  mFix := AFix;
  mFix.FileName := FContext.FormFile;
  Result := [mFix];
end;

function TFormCharCheck.FormFixes(const ARun: TRun): TArray<TRuleFix>;
begin
  Result := nil;
  if FContext.FormFile = '' then
  begin
    Exit;
  end;
  // Rohe Zeichen in einem String der Formulardatei: als #nnnn ausschreiben, wie Delphi es tut.
  if (ARun.Place = TCharPlace.StringLiteral) and ARun.Hits[0].Raw and ARun.Hits[High(ARun.Hits)].Raw then
  begin
    Result := InFormFile(TRuleFix.Create(cTexts[TUnicodeText.ReplaceInForm].Fmt([CharLiterals(ARun, True)]),
      [TRuleEdit.Create(RunRange(ARun), '''' + CharLiterals(ARun, True) + '''')], True));
  end
  else if ARun.Place = TCharPlace.Code then
  begin
    Result := InFormFile(TRuleFix.Create(cTexts[TUnicodeText.RemoveInForm].Text, [TRuleEdit.Create(RunRange(ARun),
      '')]));
  end;
end;

procedure TFormCharCheck.ReportRun(const ARun: TRun);
var
  mObject: TDfmObject;
  mProperty: string;
begin
  FScan.Locate(ARun.Hits[0].Pos, mObject, mProperty);
  AddRun(FRule, ARun, FReport, FieldRange(mObject), cTexts[TUnicodeText.InFormFile].Fmt(
    [ARun.Hits[0].Pos.Line + 1, WhereText(mObject, mProperty), FWhat, RunCodes(ARun)]), FormFixes(ARun));
end;

procedure TFormCharCheck.Run(ASkipReplacement: Boolean);
var
  mRun: TRun;
begin
  if FScan.Document.Root = nil then
  begin
    Exit;
  end;
  FFormClass := FScan.Document.Root.TypeName;
  FCache := TRuleDerived.Open(FContext);
  FUnitIndex := TRuleDerived.UnitIndex(FCache, FContext);
  // Ohne Formularklasse in der Unit: am Anfang der Unit.
  FClassRange := FormClassRange(FUnitIndex, FFormClass);
  for mRun in FScan.Runs(FRule) do
  begin
    // U+FFFD an ungültigen Bytes meldet control-char schon mit Zeile und Spalte.
    if not (ASkipReplacement and OnlyReplacement(mRun)) then
    begin
      ReportRun(mRun);
    end;
  end;
end;

/// <summary>Meldet die Bereiche einer Regel in der Formulardatei an der passenden Stelle der Unit.</summary>
procedure CheckForm(ARule: TCharRule; const AContext: TRuleContext; const AReport: IRuleReport;
  const AWhat: string; ASkipReplacement: Boolean);
var
  mCheck: TFormCharCheck;
begin
  if (AContext.FormText = '') or (AContext.Tree = nil) or TFormModel.IsBinary(AContext.FormText) then
  begin
    Exit;
  end;
  mCheck := TFormCharCheck.Create(ARule, AContext, AReport, AWhat);
  try
    mCheck.Run(ASkipReplacement);
  finally
    mCheck.Free;
  end;
end;

/// <summary>Meldet die Bereiche einer Regel in der Unit und in der Formulardatei.</summary>
procedure CheckText(ARule: TCharRule; const AContext: TRuleContext; const AReport: IRuleReport;
  const AWhat: string);
var
  mRun: TRun;
begin
  for mRun in RunsOf(ARule, AContext) do
  begin
    AReport.Add(RunRange(mRun), AWhat + ' ' + RunCodes(mRun), RunConfidence(mRun), RunFixes(mRun));
  end;
  CheckForm(ARule, AContext, AReport, AWhat, False);
end;

{ TBidiControlRule }

function TBidiControlRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('bidi-control', TRuleSeverity.Error,
    cTexts[TUnicodeText.BidiTitle].Text);
end;

procedure TBidiControlRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  CheckText(TCharRule.Bidi, AContext, AReport,
    cTexts[TUnicodeText.Bidi].Text);
end;

{ TInvisibleCharRule }

function TInvisibleCharRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('invisible-char', TRuleSeverity.Warning,
    cTexts[TUnicodeText.InvisibleTitle].Text);
end;

procedure TInvisibleCharRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  CheckText(TCharRule.Invisible, AContext, AReport, cTexts[TUnicodeText.Invisible].Text);
end;

{ TControlCharRule }

function TControlCharRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('control-char', TRuleSeverity.Error,
    cTexts[TUnicodeText.ControlTitle].Text);
end;

/// <summary>Text ohne CR, damit Puffer mit anderen Zeilenenden als die Datei vergleichbar bleiben.</summary>
function WithoutCr(const AText: string): string;
begin
  Result := StringReplace(AText, #13, '', [rfReplaceAll]);
end;

/// <summary>Bytes der Datei AFileName (neben der Unit) über ReadFile; False, wenn sie nicht lesbar ist.</summary>
function ReadBytes(const AContext: TRuleContext; const AFileName: string; out ABytes: TBytes): Boolean;
begin
  ABytes := nil;
  Result := (AFileName <> '') and Assigned(AContext.ReadFile) and
    AContext.ReadFile(ExtractFileName(StringReplace(AFileName, '/', '\', [rfReplaceAll])), ABytes);
end;

/// <summary>Fehlstellen in den Bytes von AFileName, wenn ihr Text AText ist; sonst nil.</summary>
function InvalidBytes(const AContext: TRuleContext; const AFileName, AText: string): TArray<TInvalidUtf8>;
var
  mBytes: TBytes;
  mFormat: TFileFormat;
begin
  Result := nil;
  if not ReadBytes(AContext, AFileName, mBytes) then
  begin
    Exit;
  end;
  if TFileEncoding.IsBinaryForm(mBytes) then
  begin
    Exit;
  end;
  // Nur, wenn der geprüfte Text der Inhalt der Datei ist: sonst passen die Stellen nicht.
  if WithoutCr(TFileEncoding.Decode(mBytes, mFormat)) <> WithoutCr(AText) then
  begin
    Exit;
  end;
  Result := TFileEncoding.InvalidUtf8(mBytes, mFormat);
end;

/// <summary>Liegen alle Fehlstellen im Text? Sonst zählt der Dekodierer anders als InvalidUtf8, und keine
/// Stelle gilt.</summary>
function Verified(const AInvalid: TArray<TInvalidUtf8>; const AText: string): Boolean;
var
  mLines: TArray<string>;
  mItem: TInvalidUtf8;
begin
  mLines := WithoutCr(AText).Split([#10]);
  for mItem in AInvalid do
  begin
    if (mItem.Position.Line > High(mLines)) or (mItem.Position.Character >= Length(mLines[mItem.Position.Line])) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Klasse des Wurzelobjekts der Formulardatei; '' ohne.</summary>
function FormClassOf(const AFormText: string): string;
var
  mDocument: TDfmDocument;
begin
  Result := '';
  mDocument := TDfmParser.Parse(AFormText);
  try
    if mDocument.Root <> nil then
    begin
      Result := mDocument.Root.TypeName;
    end;
  finally
    mDocument.Free;
  end;
end;

procedure ReportInvalidBytes(const AReport: IRuleReport; const AInvalid: TArray<TInvalidUtf8>);
var
  mItem: TInvalidUtf8;
begin
  for mItem in AInvalid do
  begin
    AReport.Add(TTextRange.Create(mItem.Position, TTextPosition.Create(mItem.Position.Line,
      mItem.Position.Character + 1)), cTexts[TUnicodeText.InvalidUtf8].Fmt(
      [IntToHex(mItem.Value, 2), mItem.ByteOffset]));
  end;
end;

/// <summary>Steht ein U+FFFD des Bereichs an einer schon gemeldeten Fehlstelle?</summary>
function CoveredByInvalid(const ARun: TRun; const AInvalid: TArray<TInvalidUtf8>): Boolean;
var
  mHit: THit;
  mItem: TInvalidUtf8;
begin
  for mHit in ARun.Hits do
  begin
    for mItem in AInvalid do
    begin
      if (mHit.Code = $FFFD) and (mItem.Position.Line = mHit.Pos.Line) and
        (mItem.Position.Character = mHit.Pos.Character) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Steuerzeichen der Unit; U+FFFD an einer schon gemeldeten Fehlstelle nicht doppelt.</summary>
procedure ReportControlRuns(const AContext: TRuleContext; const AReport: IRuleReport;
  const AInvalid: TArray<TInvalidUtf8>);
var
  mRun: TRun;
begin
  for mRun in RunsOf(TCharRule.Control, AContext) do
  begin
    if not CoveredByInvalid(mRun, AInvalid) then
    begin
      AddRun(TCharRule.Control, mRun, AReport, RunRange(mRun), cTexts[TUnicodeText.ControlPrefix].Text +
        RunCodes(mRun), RunFixes(mRun));
    end;
  end;
end;

/// <summary>Steuerzeichen und ungültige Bytes der Formulardatei: an der Formularklasse, mit Zeile und Spalte der
/// Formulardatei.</summary>
procedure CheckFormBytes(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mInvalid: TArray<TInvalidUtf8>;
  mItem: TInvalidUtf8;
  mCache: IRuleDerivedCache;
  mRange: TTextRange;
begin
  mInvalid := nil;
  if (AContext.FormFile <> '') and (AContext.Tree <> nil) and not TFormModel.IsBinary(AContext.FormText) then
  begin
    mInvalid := InvalidBytes(AContext, AContext.FormFile, AContext.FormText);
  end;
  CheckForm(TCharRule.Control, AContext, AReport, cTexts[TUnicodeText.Control].Text, Length(mInvalid) > 0);
  if Length(mInvalid) = 0 then
  begin
    Exit;
  end;
  mCache := TRuleDerived.Open(AContext);
  mRange := FormClassRange(TRuleDerived.UnitIndex(mCache, AContext), FormClassOf(AContext.FormText));
  for mItem in mInvalid do
  begin
    AReport.Add(mRange, cTexts[TUnicodeText.InvalidUtf8Form].Fmt(
      [mItem.Position.Line + 1, mItem.Position.Character + 1, IntToHex(mItem.Value, 2)]));
  end;
end;

procedure TControlCharRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mInvalid: TArray<TInvalidUtf8>;
  mBytes: TBytes;
begin
  // Eine UTF-32-Datei ist als Text falsch dekodiert (lauter NUL); das meldet file-encoding-unsupported.
  if not (ReadBytes(AContext, AContext.RelativePath, mBytes) and TFileEncoding.HasUtf32Bom(mBytes)) then
  begin
    mInvalid := InvalidBytes(AContext, AContext.RelativePath, AContext.Text);
    if not Verified(mInvalid, AContext.Text) then
    begin
      mInvalid := nil;
    end;
    ReportInvalidBytes(AReport, mInvalid);
    ReportControlRuns(AContext, AReport, mInvalid);
  end;
  CheckFormBytes(AContext, AReport);
end;

{ TFileEncodingUnsupportedRule }

type
  {$SCOPEDENUMS ON}
  TQuoteKind = (None, Typographic, Double);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein Zeichen im Code, das der Compiler nicht annimmt.</summary>
  TIllegalChar = record
    Code: Integer;
    /// <summary>Offset ab 0 im Text.</summary>
    Offset: Integer;
    /// <summary>UTF-16-Einheiten: 2 bei einem Ersatzpaar.</summary>
    Size: Integer;
    Pos: TTextPosition;
    Quote: TQuoteKind;
    /// <summary>Index des Tokens.</summary>
    Token: Integer;
  end;

class function TFileEncodingUnsupportedRule.IsIllegal(ACode: Integer): Boolean;
begin
  case ACode of
    Ord('!'), Ord('"'), Ord('?'), Ord('\'), Ord('`'), Ord('|'), Ord('~'),
    $A1..$A9, $AB, $AC, $AE..$B1, $B4, $B6..$B8, $BB, $BF, $D7, $F7,
    // Allgemeine Interpunktion ohne die Verbinder U+203F, U+2040, U+2054 und ohne Zeilen-/Absatztrenner.
    $2010..$2027, $2030..$203E, $2041..$2053, $2055..$205E,
    // Währungen, Pfeile, mathematische und technische Zeichen, Rahmen, Formen, Symbole, Dingbats.
    $20A0..$20C0, $2190..$23FF, $2500..$27FF, $2900..$2BFF,
    // CJK-Interpunktion und Vollbreiten-ASCII ohne den Verbinder U+FF3F.
    $3001..$3003, $3008..$3011, $3014..$301F,
    $FF01..$FF0F, $FF1A..$FF20, $FF3B..$FF3E, $FF40, $FF5B..$FF65,
    // Emoji und Symbole jenseits der BMP.
    $1F000..$1FAFF:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Code des Zeichens an AIndex (ab 1), Ersatzpaare zusammengefasst; ASize = 1 oder 2.</summary>
function CodeAt(const AText: string; AIndex: Integer; out ASize: Integer): Integer;
var
  mTrail: Integer;
begin
  Result := Ord(AText[AIndex]);
  ASize := 1;
  if (Result < $D800) or (Result > $DBFF) or (AIndex >= Length(AText)) then
  begin
    Exit;
  end;
  mTrail := Ord(AText[AIndex + 1]);
  if (mTrail < $DC00) or (mTrail > $DFFF) then
  begin
    Exit;
  end;
  Result := $10000 + ((Result - $D800) shl 10) + (mTrail - $DC00);
  ASize := 2;
end;

function HasIllegalChar(const AText: string): Boolean;
var
  mIndex, mSize: Integer;
begin
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if TFileEncodingUnsupportedRule.IsIllegal(CodeAt(AText, mIndex, mSize)) then
    begin
      Exit(True);
    end;
    Inc(mIndex, mSize);
  end;
  Result := False;
end;

function QuoteKindOf(ACode: Integer): TQuoteKind;
begin
  case ACode of
    $22:
      Result := TQuoteKind.Double;
    $AB, $BB, $2018..$201F, $2039, $203A:
      Result := TQuoteKind.Typographic;
  else
    Result := TQuoteKind.None;
  end;
end;

/// <summary>Schließt AClose das mit AOpen begonnene Zitat? Deutsch „…“ ‚…‘ »…« ›…‹, englisch “…” ‘…’,
/// französisch «…» ‹…›, ASCII "…".</summary>
function Closes(AOpen, AClose: Integer): Boolean;
begin
  case AOpen of
    $22:
      Result := AClose = $22;
    $201E, $201C, $201F:
      Result := (AClose = $201C) or (AClose = $201D);
    $201A, $2018, $201B:
      Result := (AClose = $2018) or (AClose = $2019);
    $BB:
      Result := AClose = $AB;
    $AB:
      Result := AClose = $BB;
    $203A:
      Result := AClose = $2039;
    $2039:
      Result := AClose = $203A;
  else
    Result := False;
  end;
end;

/// <summary>Eindeutiges ASCII-Gegenstück; '' ohne.</summary>
function AsciiOf(ACode: Integer): string;
begin
  case ACode of
    $2010..$2015, $2212:
      Result := '-';
    $D7:
      Result := '*';
    $F7:
      Result := '/';
    $2260:
      Result := '<>';
    $2264:
      Result := '<=';
    $2265:
      Result := '>=';
    $FF01..$FF5E:
      begin
        Result := Chr(ACode - $FEE0);
        if Pos(Result, '+-*/=<>[].,():;^@') = 0 then
        begin
          Result := '';
        end;
      end;
  else
    Result := '';
  end;
end;

/// <summary>Steht der Scanner nach AToken in einem asm-Block? Der Parser endet den Block am nächsten end.</summary>
function InAsmAfter(const AToken: TPascalToken; AInAsm: Boolean): Boolean;
begin
  Result := AInAsm;
  if AToken.IsKeyword('asm') then
  begin
    Result := True;
  end
  else if AToken.IsKeyword('end') then
  begin
    Result := False;
  end;
end;

/// <summary>Hängt die unzulässigen Zeichen des Tokens AIndex an AResult[0..ACount-1] an.</summary>
procedure CollectIllegal(const AToken: TPascalToken; AIndex: Integer; var AResult: TArray<TIllegalChar>;
  var ACount: Integer);
var
  mPosition, mSize: Integer;
  mItem: TIllegalChar;
begin
  mPosition := 1;
  while mPosition <= Length(AToken.Text) do
  begin
    mItem.Code := CodeAt(AToken.Text, mPosition, mSize);
    if TFileEncodingUnsupportedRule.IsIllegal(mItem.Code) then
    begin
      mItem.Offset := AToken.Offset + mPosition - 1;
      mItem.Size := mSize;
      mItem.Pos := TTextPosition.Create(AToken.StartPos.Line, AToken.StartPos.Character + mPosition - 1);
      mItem.Quote := QuoteKindOf(mItem.Code);
      mItem.Token := AIndex;
      if ACount = Length(AResult) then
      begin
        SetLength(AResult, ACount * 2 + 4);
      end;
      AResult[ACount] := mItem;
      Inc(ACount);
    end;
    Inc(mPosition, mSize);
  end;
end;

/// <summary>Zeichen im Code außerhalb von asm-Blöcken und {$IF…}-Zweigen, die der Compiler nicht annimmt.</summary>
function IllegalChars(const ATokens: TArray<TPascalToken>): TArray<TIllegalChar>;
var
  mPaths: TArray<string>;
  mIndex, mCount: Integer;
  mInAsm: Boolean;
begin
  Result := nil;
  mCount := 0;
  mPaths := TConditionalBranches.Paths(ATokens);
  mInAsm := False;
  for mIndex := 0 to High(ATokens) do
  begin
    // Im Assembler gelten andere Zeichen, etwa "…" als String.
    mInAsm := InAsmAfter(ATokens[mIndex], mInAsm);
    if not mInAsm and (TConditionalBranches.PathAt(mPaths, mIndex) = '') and
      (ATokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Unknown]) then
    begin
      CollectIllegal(ATokens[mIndex], mIndex, Result, mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

/// <summary>Stehen zwischen den Tokens AFirst und ALast nur Code-Tokens? Sonst begänne im Zitat ein String
/// oder Kommentar, und die Korrektur änderte seine Bedeutung.</summary>
function OnlyCodeBetween(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := AFirst + 1 to ALast - 1 do
  begin
    if not (ATokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword,
      TPascalTokenKind.Number, TPascalTokenKind.Symbol, TPascalTokenKind.Unknown]) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Index des schließenden Anführungszeichens zu AChars[AOpen] auf derselben Zeile; -1 ohne.</summary>
function ClosingQuote(const AChars: TArray<TIllegalChar>; AOpen: Integer;
  const ATokens: TArray<TPascalToken>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := AOpen + 1 to High(AChars) do
  begin
    if AChars[mIndex].Pos.Line <> AChars[AOpen].Pos.Line then
    begin
      Break;
    end;
    if Closes(AChars[AOpen].Code, AChars[mIndex].Code) then
    begin
      if OnlyCodeBetween(ATokens, AChars[AOpen].Token, AChars[mIndex].Token) then
      begin
        Exit(mIndex);
      end;
      Break;
    end;
  end;
  Result := -1;
end;

function TFileEncodingUnsupportedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('file-encoding-unsupported', TRuleSeverity.Error,
    cTexts[TUnicodeText.RejectedTitle].Text);
end;

/// <summary>Korrektur eines Zitats von AOpen bis AClose zum String; ARange deckt beide Anführungszeichen ab.</summary>
function QuoteFixes(const AText: string; const AOpen, AClose: TIllegalChar; out ARange: TTextRange):
  TArray<TRuleFix>;
var
  mLiteral: string;
begin
  ARange := TTextRange.Create(AOpen.Pos, TTextPosition.Create(AClose.Pos.Line, AClose.Pos.Character + AClose.Size));
  mLiteral := QuotedStr(Copy(AText, AOpen.Offset + AOpen.Size + 1, AClose.Offset - AOpen.Offset - AOpen.Size));
  Result := [TRuleFix.Create(cTexts[TUnicodeText.ReplaceWithString].Fmt([mLiteral]),
    [TRuleEdit.Create(ARange, mLiteral)])];
end;

/// <summary>Ersatz eines einzelnen Zeichens durch sein ASCII-Gegenstück; nil ohne.</summary>
function CharFixes(const AChar: TIllegalChar; out ARange: TTextRange): TArray<TRuleFix>;
var
  mAscii: string;
begin
  ARange := TTextRange.Create(AChar.Pos, TTextPosition.Create(AChar.Pos.Line, AChar.Pos.Character + AChar.Size));
  Result := nil;
  mAscii := AsciiOf(AChar.Code);
  if mAscii <> '' then
  begin
    Result := [TRuleFix.Create(cTexts[TUnicodeText.ReplaceWithQuoted].Fmt([mAscii]), [TRuleEdit.Create(ARange,
      mAscii)])];
  end;
end;

function IllegalMessage(const AText: string; const AChar: TIllegalChar): string;
begin
  case AChar.Quote of
    TQuoteKind.Typographic:
      Result := cTexts[TUnicodeText.Typographic].Text;
    TQuoteKind.Double:
      Result := cTexts[TUnicodeText.DoubleQuotes].Text;
  else
    Result := cTexts[TUnicodeText.CharNotAllowed].Fmt(
      [Copy(AText, AChar.Offset + 1, AChar.Size), IntToHex(AChar.Code, 4)]);
  end;
end;

procedure ReportIllegalChars(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mChars: TArray<TIllegalChar>;
  mIndex, mClosing: Integer;
  mRange: TTextRange;
  mFixes: TArray<TRuleFix>;
begin
  mChars := IllegalChars(AContext.Tree.Tokens);
  mIndex := 0;
  while mIndex <= High(mChars) do
  begin
    mClosing := -1;
    if mChars[mIndex].Quote <> TQuoteKind.None then
    begin
      mClosing := ClosingQuote(mChars, mIndex, AContext.Tree.Tokens);
    end;
    if mClosing >= 0 then
    begin
      mFixes := QuoteFixes(AContext.Text, mChars[mIndex], mChars[mClosing], mRange);
      mIndex := mClosing;
    end
    else
    begin
      mFixes := CharFixes(mChars[mIndex], mRange);
    end;
    AReport.Add(mRange, IllegalMessage(AContext.Text, mChars[mIndex]), TRuleConfidence.High, mFixes);
    Inc(mIndex);
  end;
end;

procedure TFileEncodingUnsupportedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mBytes: TBytes;
begin
  if ReadBytes(AContext, AContext.RelativePath, mBytes) and TFileEncoding.HasUtf32Bom(mBytes) then
  begin
    // Der Text ist dann falsch dekodiert; weitere Meldungen wären Folgefehler.
    AReport.Add(TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(0, 1)),
      cTexts[TUnicodeText.Utf32].Text, TRuleConfidence.High);
    Exit;
  end;
  if AContext.Tree <> nil then
  begin
    ReportIllegalChars(AContext, AReport);
  end;
end;

{ TConfusableIdentifierRule }

type
  TScript = (Other, Latin, Greek, Cyrillic);

function ScriptOf(AC: Char): TScript;
begin
  case Ord(AC) of
    Ord('A')..Ord('Z'), Ord('a')..Ord('z'), $00C0..$024F:
      Result := TScript.Latin;
    $0370..$03FF:
      Result := TScript.Greek;
    $0400..$04FF, $0500..$052F:
      Result := TScript.Cyrillic;
  else
    Result := TScript.Other;
  end;
end;

const
  // Auszug aus der Unicode-Confusables-Liste: Zeichen, die lateinischen Buchstaben gleichen; cConfusableLatin
  // nennt an gleicher Stelle das lateinische Gegenstück.
  cConfusableChars =
    // Kyrillisch klein
    #$0430#$0435#$043E#$0440#$0441#$0445#$0443#$0456#$0458#$0455#$0501#$04BB +
    // Kyrillisch groß
    #$0410#$0412#$0415#$041A#$041C#$041D#$041E#$0420#$0421#$0422#$0425#$0406#$0408#$0405 +
    // Griechisch
    #$03BF#$03BD#$0391#$0392#$0395#$0396#$0397#$0399#$039A#$039C#$039D#$039F#$03A1#$03A4#$03A5#$03A7;
  cConfusableLatin = 'aeopcxyijsdh' + 'ABEKMHOPCTXIJS' + 'ovABEZHIKMNOPTYX';

class function TConfusableIdentifierRule.LatinOf(AChar: Char): Char;
var
  mIndex: Integer;
begin
  mIndex := Pos(AChar, cConfusableChars);
  if mIndex = 0 then
  begin
    Result := #0;
  end
  else
  begin
    Result := cConfusableLatin[mIndex];
  end;
end;

function TConfusableIdentifierRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('confusable-identifier', TRuleSeverity.Warning,
    cTexts[TUnicodeText.ConfusableTitle].Text);
end;

type
  TScripts = set of TScript;

  /// <summary>Schriften und Gegenstücke der Zeichen eines Bezeichners.</summary>
  TIdentifierScan = record
    Scripts: TScripts;
    NonAscii: Boolean;
    /// <summary>Mindestens ein Zeichen hat ein lateinisches Gegenstück.</summary>
    Confusable: Boolean;
    /// <summary>Jedes Nicht-ASCII-Zeichen hat ein lateinisches Gegenstück.</summary>
    OnlyLookalikes: Boolean;
    /// <summary>Bezeichner mit lateinischen Gegenstücken.</summary>
    Replaced: string;
  end;

function ScanIdentifier(const AText: string): TIdentifierScan;
var
  mChar, mLatin: Char;
begin
  Result := Default(TIdentifierScan);
  Result.OnlyLookalikes := True;
  for mChar in AText do
  begin
    mLatin := mChar;
    if Ord(mChar) > 127 then
    begin
      Result.NonAscii := True;
      mLatin := TConfusableIdentifierRule.LatinOf(mChar);
      Result.Confusable := Result.Confusable or (mLatin <> #0);
      Result.OnlyLookalikes := Result.OnlyLookalikes and (mLatin <> #0);
    end;
    if mLatin = #0 then
    begin
      mLatin := mChar;
    end;
    Result.Replaced := Result.Replaced + mLatin;
    Include(Result.Scripts, ScriptOf(mChar));
  end;
end;

procedure ReportIdentifier(const AToken: TPascalToken; const AScan: TIdentifierScan; const AReport: IRuleReport);
var
  mRange: TTextRange;
  mFixes: TArray<TRuleFix>;
begin
  mRange := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  if AScan.Confusable and ((TScript.Latin in AScan.Scripts) or AScan.OnlyLookalikes) then
  begin
    mFixes := nil;
    // Eindeutig nur, wenn jedes Nicht-ASCII-Zeichen ein lateinisches Gegenstück hat.
    if AScan.OnlyLookalikes then
    begin
      mFixes := [TRuleFix.Create(cTexts[TUnicodeText.ReplaceLatin].Fmt([AScan.Replaced]),
        [TRuleEdit.Create(mRange, AScan.Replaced)])];
    end;
    AReport.Add(mRange, cTexts[TUnicodeText.Confusable].Fmt([AToken.Text, AScan.Replaced]), TRuleConfidence.High,
      mFixes);
  end
  else if (TScript.Latin in AScan.Scripts) and (AScan.Scripts * [TScript.Greek, TScript.Cyrillic] <> []) then
  begin
    AReport.Add(mRange, cTexts[TUnicodeText.MixedScripts].Fmt([AToken.Text]), TRuleConfidence.Medium);
  end
  else
  begin
    AReport.Add(mRange, cTexts[TUnicodeText.NonAscii].Fmt([AToken.Text]), TRuleConfidence.Low);
  end;
end;

procedure TConfusableIdentifierRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mToken: TPascalToken;
  mScan: TIdentifierScan;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  for mToken in AContext.Tree.Tokens do
  begin
    // Satz- und Sonderzeichen machen keinen Bezeichner; das meldet file-encoding-unsupported.
    if (mToken.Kind = TPascalTokenKind.Identifier) and not HasIllegalChar(mToken.Text) then
    begin
      mScan := ScanIdentifier(mToken.Text);
      if mScan.NonAscii then
      begin
        ReportIdentifier(mToken, mScan, AReport);
      end;
    end;
  end;
end;

procedure RegisterUnicodeRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TBidiControlRule.Create);
  ARegistry.Register(TInvisibleCharRule.Create);
  ARegistry.Register(TControlCharRule.Create);
  ARegistry.Register(TConfusableIdentifierRule.Create);
  ARegistry.Register(TFileEncodingUnsupportedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Unicode', cTexts);

end.
