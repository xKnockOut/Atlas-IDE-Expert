unit Atlas.Core.Debug.Logpoint;

// Logpunkte (#583), ohne IDE: Ein Logpunkt ist ein Haltepunkt der IDE ohne
// Anhalten, der einen Text ins Ereignisprotokoll schreibt.
// - TAtlasLogpointTemplate zerlegt den Text mit Platzhaltern:
//   „Kunde {Kunde.Name}, Summe {Summe:0.00}“; „{{“ und „}}“ stehen für
//   geschweifte Klammern, die Formatangabe folgt dem letzten „:“ außerhalb
//   von Klammern und Anführungszeichen. Eine fehlende Klammer ist ein Fehler
//   mit Stelle.
// - TAtlasLogpointPlan übersetzt in die Eigenschaften des Haltepunkts
//   (vorher geprüft: ein Haltepunkt der IDE wertet genau einen Ausdruck aus
//   und schreibt ihn hinter die Meldung ins Ereignisprotokoll):
//   ohne Platzhalter nur die Meldung; mit genau einem Platzhalter ohne
//   Formatangabe wertet die IDE ihn aus (jeder Typ), Atlas setzt den Wert an
//   die Stelle von „{0}“ in der Meldung; sonst setzt ein Pascal-Ausdruck die
//   Teile zusammen (d = IntToStr, x = IntToHex, Muster mit 0 oder # =
//   FormatFloat, sonst Format), Platzhalter ohne Angabe gehen unverändert ein
//   und müssen Strings sein.
// - TAtlasLogpointMerger führt im Ereignisprotokoll Meldung und Wert zu einer
//   Zeile der Art Logpunkt zusammen.
// Die Meldung endet mit dem Ort („· Datei.pas:12“), damit das Protokoll zur
// Zeile springt.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasLogpointPartKind = (Text, Expression);
  /// <summary>Fehler im Text: fehlende „}“, einzelne „}“, leerer Platzhalter.</summary>
  TAtlasLogpointError = (None, MissingClose, StrayClose, EmptyPlaceholder);
  {$SCOPEDENUMS OFF}

  TAtlasLogpointPart = record
    Kind: TAtlasLogpointPartKind;
    /// <summary>Text bzw. Ausdruck (getrimmt).</summary>
    Text: string;
    /// <summary>Formatangabe nach dem letzten „:“; '' ohne.</summary>
    Format: string;
  end;

  TAtlasLogpointTemplate = record
    Parts: TArray<TAtlasLogpointPart>;
    Error: TAtlasLogpointError;
    /// <summary>Stelle des Fehlers (ab 1); 0 ohne Fehler.</summary>
    ErrorPos: Integer;
    class function Parse(const AText: string): TAtlasLogpointTemplate; static;
    function Valid: Boolean;
    function Expressions: TArray<string>;
    /// <summary>Nur Text, keine Formatangabe, genau ein Platzhalter?</summary>
    function SingleRaw: Boolean;
  end;

  TAtlasLogpointPlan = record
  public const
    /// <summary>Stelle des Werts in der Meldung, wenn die IDE den Ausdruck auswertet.</summary>
    cValueMark = '{0}';
    /// <summary>Trenner vor dem Ort am Ende der Meldung.</summary>
    cPlaceMark = ' · ';
  public
    LogMessage: string;
    /// <summary>Von der IDE auszuwertender Ausdruck; '' ohne.</summary>
    EvalExpression: string;
    Condition: string;
    PassCount: Integer;
    /// <summary>Eigenschaften des Haltepunkts zu ATemplate; APlace z. B. "Unit1.pas:12".</summary>
    class function Build(const ATemplate: TAtlasLogpointTemplate; const APrefix, APlace, ACondition: string;
      APassCount: Integer): TAtlasLogpointPlan; static;
    /// <summary>Bedingung ohne geschweifte Klammern: "{Summe} > 1000" wird "Summe > 1000".</summary>
    class function ConditionOf(const AText: string): string; static;
    /// <summary>Pascal-Stringliteral zu AText.</summary>
    class function Quoted(const AText: string): string; static;
  end;

  /// <summary>Führt Meldung und ausgewerteten Wert eines Logpunkts zu einer Zeile zusammen.</summary>
  TAtlasLogpointMerger = class
  private
    FPrefix: string;
    FPending: string;
  public
    constructor Create(const APrefix: string);
    /// <summary>Haltepunkt-Zeile AText (ohne Präfix der IDE). True mit AOutput, wenn eine Logpunkt-Zeile fertig ist;
    /// False, wenn die Zeile wartet (Meldung mit „{0}“) oder kein Logpunkt ist (AIsLogpoint False).</summary>
    function Feed(const AText: string; out AOutput: string; out AIsLogpoint: Boolean): Boolean;
    /// <summary>Wert aus einer Ausdruckszeile der IDE: alles nach „Ausdruck:“ bzw. „Ausdruck =“, ohne
    /// Anführungszeichen eines Strings.</summary>
    class function ValueOf(const ALine: string): string; static;
    /// <summary>Wartet eine Meldung auf ihren Wert?</summary>
    function Pending: Boolean;
    property Prefix: string read FPrefix;
  end;

implementation

uses
  System.StrUtils;

const
  /// <summary>Trenner zwischen Ausdruck und Wert in der Ausdruckszeile der IDE.</summary>
  cEqualsMark = ' = ';
  cColonMark = ': ';
  /// <summary>Formatangaben mit eigener Umwandlung, Stellen in IndexText.</summary>
  cPlainFormats: array[0..3] of string = ('', 's', 'd', 'x');
  cFormatNone = 0;
  cFormatString = 1;
  cFormatDecimal = 2;
  cFormatHex = 3;

{ TAtlasLogpointTemplate }

/// <summary>Tiefe der Klammern außerhalb von Anführungszeichen nach dem Zeichen AChar.</summary>
procedure Track(AChar: Char; var ADepth: Integer; var AQuoted: Boolean);
begin
  if AChar = '''' then
  begin
    AQuoted := not AQuoted;
  end
  else if AQuoted then
  begin
    Exit;
  end
  else if CharInSet(AChar, ['(', '[']) then
  begin
    Inc(ADepth);
  end
  else if CharInSet(AChar, [')', ']']) then
  begin
    Dec(ADepth);
  end;
end;

/// <summary>Stelle des letzten „:“ außerhalb von Klammern und Anführungszeichen; 0 ohne.</summary>
function LastFormatColon(const AInner: string): Integer;
var
  mIndex, mDepth: Integer;
  mQuoted: Boolean;
begin
  mDepth := 0;
  mQuoted := False;
  Result := 0;
  for mIndex := 1 to Length(AInner) do
  begin
    Track(AInner[mIndex], mDepth, mQuoted);
    if (AInner[mIndex] = ':') and not mQuoted and (mDepth = 0) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Formatangabe hinter dem letzten „:“ außerhalb von Klammern und Anführungszeichen abtrennen.</summary>
procedure SplitFormat(const AInner: string; out AExpression, AFormat: string);
var
  mSplit: Integer;
begin
  mSplit := LastFormatColon(AInner);
  // ":=" ist eine Zuweisung, keine Formatangabe.
  if (mSplit > 0) and (mSplit < Length(AInner)) and (AInner[mSplit + 1] = '=') then
  begin
    mSplit := 0;
  end;
  if mSplit = 0 then
  begin
    AExpression := Trim(AInner);
    AFormat := '';
  end
  else
  begin
    AExpression := Trim(Copy(AInner, 1, mSplit - 1));
    AFormat := Trim(Copy(AInner, mSplit + 1, MaxInt));
  end;
end;

procedure AddPart(var AParts: TArray<TAtlasLogpointPart>; AKind: TAtlasLogpointPartKind;
  const AText, AFormat: string);
var
  mPart: TAtlasLogpointPart;
begin
  // Aufeinanderfolgender Text wird eins.
  if (AKind = TAtlasLogpointPartKind.Text) and (Length(AParts) > 0) and
    (AParts[High(AParts)].Kind = TAtlasLogpointPartKind.Text) then
  begin
    AParts[High(AParts)].Text := AParts[High(AParts)].Text + AText;
    Exit;
  end;
  mPart.Kind := AKind;
  mPart.Text := AText;
  mPart.Format := AFormat;
  AParts := AParts + [mPart];
end;

function Fail(var ATemplate: TAtlasLogpointTemplate; AError: TAtlasLogpointError;
  APos: Integer): TAtlasLogpointTemplate;
begin
  ATemplate.Error := AError;
  ATemplate.ErrorPos := APos;
  Result := ATemplate;
end;

/// <summary>Steht an AIndex zweimal AChar („{{“ oder „}}“)?</summary>
function Doubled(const AText: string; AIndex: Integer; AChar: Char): Boolean;
begin
  Result := (AText[AIndex] = AChar) and (AIndex < Length(AText)) and (AText[AIndex + 1] = AChar);
end;

/// <summary>Bisherigen Text als Teil anfügen und leeren.</summary>
procedure FlushText(var AParts: TArray<TAtlasLogpointPart>; AText: TStringBuilder);
begin
  if AText.Length > 0 then
  begin
    AddPart(AParts, TAtlasLogpointPartKind.Text, AText.ToString, '');
    AText.Clear;
  end;
end;

/// <summary>Platzhalter ab AIndex („{“) lesen; AIndex steht danach hinter „}“. False mit Fehler in ATemplate.</summary>
function ReadPlaceholder(const AText: string; var AIndex: Integer; var ATemplate: TAtlasLogpointTemplate): Boolean;
var
  mClose: Integer;
  mExpression, mFormat: string;
begin
  mClose := Pos('}', AText, AIndex + 1);
  if mClose = 0 then
  begin
    Fail(ATemplate, TAtlasLogpointError.MissingClose, AIndex);
    Exit(False);
  end;
  SplitFormat(Copy(AText, AIndex + 1, mClose - AIndex - 1), mExpression, mFormat);
  if mExpression = '' then
  begin
    Fail(ATemplate, TAtlasLogpointError.EmptyPlaceholder, AIndex);
    Exit(False);
  end;
  AddPart(ATemplate.Parts, TAtlasLogpointPartKind.Expression, mExpression, mFormat);
  AIndex := mClose + 1;
  Result := True;
end;

class function TAtlasLogpointTemplate.Parse(const AText: string): TAtlasLogpointTemplate;
var
  mIndex: Integer;
  mText: TStringBuilder;
begin
  Result := Default(TAtlasLogpointTemplate);
  mText := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      if Doubled(AText, mIndex, '{') or Doubled(AText, mIndex, '}') then
      begin
        mText.Append(AText[mIndex]);
        Inc(mIndex, 2);
      end
      else if AText[mIndex] = '}' then
      begin
        Exit(Fail(Result, TAtlasLogpointError.StrayClose, mIndex));
      end
      else if AText[mIndex] = '{' then
      begin
        FlushText(Result.Parts, mText);
        if not ReadPlaceholder(AText, mIndex, Result) then
        begin
          Exit;
        end;
      end
      else
      begin
        mText.Append(AText[mIndex]);
        Inc(mIndex);
      end;
    end;
    FlushText(Result.Parts, mText);
  finally
    mText.Free;
  end;
end;

function TAtlasLogpointTemplate.Valid: Boolean;
begin
  Result := Error = TAtlasLogpointError.None;
end;

function TAtlasLogpointTemplate.Expressions: TArray<string>;
var
  mPart: TAtlasLogpointPart;
begin
  Result := nil;
  for mPart in Parts do
  begin
    if mPart.Kind = TAtlasLogpointPartKind.Expression then
    begin
      Result := Result + [mPart.Text];
    end;
  end;
end;

function TAtlasLogpointTemplate.SingleRaw: Boolean;
var
  mPart: TAtlasLogpointPart;
  mCount: Integer;
begin
  mCount := 0;
  Result := True;
  for mPart in Parts do
  begin
    if mPart.Kind = TAtlasLogpointPartKind.Expression then
    begin
      Inc(mCount);
      Result := Result and (mPart.Format = '');
    end;
  end;
  Result := Result and (mCount = 1);
end;

{ TAtlasLogpointPlan }

class function TAtlasLogpointPlan.Quoted(const AText: string): string;
begin
  Result := '''' + AText.Replace('''', '''''') + '''';
end;

/// <summary>Ausdruck AExpression nach Formatangabe AFormat als String.</summary>
function Converted(const AExpression, AFormat: string): string;
begin
  case IndexText(AFormat, cPlainFormats) of
    cFormatNone, cFormatString:
      Result := '(' + AExpression + ')';
    cFormatDecimal:
      Result := 'IntToStr(' + AExpression + ')';
    cFormatHex:
      Result := 'IntToHex(' + AExpression + ')';
  else
    if (Pos('0', AFormat) > 0) or (Pos('#', AFormat) > 0) then
    begin
      Result := 'FormatFloat(' + TAtlasLogpointPlan.Quoted(AFormat) + ', ' + AExpression + ')';
    end
    else
    begin
      Result := 'Format(' + TAtlasLogpointPlan.Quoted('%' + AFormat) + ', [' + AExpression + '])';
    end;
  end;
end;

/// <summary>Text der Meldung: Textteile, Platzhalter als „{0}“; AExpression bekommt den (letzten) Ausdruck.</summary>
function MessageText(const AParts: TArray<TAtlasLogpointPart>; out AExpression: string): string;
var
  mPart: TAtlasLogpointPart;
  mText: TStringBuilder;
begin
  AExpression := '';
  mText := TStringBuilder.Create;
  try
    for mPart in AParts do
    begin
      if mPart.Kind = TAtlasLogpointPartKind.Text then
      begin
        mText.Append(mPart.Text);
      end
      else
      begin
        mText.Append(TAtlasLogpointPlan.cValueMark);
        AExpression := mPart.Text;
      end;
    end;
    Result := mText.ToString;
  finally
    mText.Free;
  end;
end;

/// <summary>Pascal-Ausdruck, der alle Teile zu einem String zusammensetzt.</summary>
function Concatenated(const AParts: TArray<TAtlasLogpointPart>): string;
var
  mPart: TAtlasLogpointPart;
  mPieces: TArray<string>;
begin
  mPieces := nil;
  for mPart in AParts do
  begin
    if mPart.Kind = TAtlasLogpointPartKind.Text then
    begin
      mPieces := mPieces + [TAtlasLogpointPlan.Quoted(mPart.Text)];
    end
    else
    begin
      mPieces := mPieces + [Converted(mPart.Text, mPart.Format)];
    end;
  end;
  Result := string.Join(' + ', mPieces);
end;

class function TAtlasLogpointPlan.Build(const ATemplate: TAtlasLogpointTemplate; const APrefix, APlace,
  ACondition: string; APassCount: Integer): TAtlasLogpointPlan;
var
  mText, mPlace: string;
begin
  Result := Default(TAtlasLogpointPlan);
  Result.Condition := ConditionOf(ACondition);
  Result.PassCount := APassCount;
  if Result.PassCount < 0 then
  begin
    Result.PassCount := 0;
  end;
  mPlace := '';
  if APlace <> '' then
  begin
    mPlace := cPlaceMark + APlace;
  end;
  if (Length(ATemplate.Expressions) = 0) or ATemplate.SingleRaw then
  begin
    // Ohne Platzhalter nur Text; mit einem wertet die IDE aus und kennt jeden Typ, Atlas setzt den Wert an „{0}“.
    mText := MessageText(ATemplate.Parts, Result.EvalExpression);
    Result.LogMessage := Trim(APrefix + ' ' + mText) + mPlace;
  end
  else
  begin
    Result.EvalExpression := Concatenated(ATemplate.Parts);
    Result.LogMessage := Trim(APrefix + ' ' + cValueMark) + mPlace;
  end;
end;

class function TAtlasLogpointPlan.ConditionOf(const AText: string): string;
begin
  Result := Trim(AText.Replace('{', '').Replace('}', ''));
end;

{ TAtlasLogpointMerger }

constructor TAtlasLogpointMerger.Create(const APrefix: string);
begin
  inherited Create;
  FPrefix := Trim(APrefix);
end;

class function TAtlasLogpointMerger.ValueOf(const ALine: string): string;
var
  mColon, mEquals, mSplit: Integer;
begin
  Result := Trim(ALine);
  mColon := Pos(cColonMark, Result);
  mEquals := Pos(cEqualsMark, Result);
  mSplit := mColon;
  if (mEquals > 0) and ((mSplit = 0) or (mEquals < mSplit)) then
  begin
    Result := Trim(Copy(Result, mEquals + Length(cEqualsMark), MaxInt));
  end
  else if mSplit > 0 then
  begin
    Result := Trim(Copy(Result, mSplit + Length(cColonMark), MaxInt));
  end;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2).Replace('''''', '''');
  end;
end;

function TAtlasLogpointMerger.Pending: Boolean;
begin
  Result := FPending <> '';
end;

function TAtlasLogpointMerger.Feed(const AText: string; out AOutput: string; out AIsLogpoint: Boolean): Boolean;
var
  mText: string;
begin
  AOutput := '';
  mText := Trim(AText);
  if FPending <> '' then
  begin
    // Die Zeile nach einer Meldung mit „{0}“ ist ihr Wert.
    AIsLogpoint := True;
    AOutput := FPending.Replace(TAtlasLogpointPlan.cValueMark, ValueOf(mText));
    FPending := '';
    Exit(True);
  end;
  AIsLogpoint := (FPrefix <> '') and mText.StartsWith(FPrefix, True);
  if not AIsLogpoint then
  begin
    Exit(False);
  end;
  if Pos(TAtlasLogpointPlan.cValueMark, mText) > 0 then
  begin
    FPending := mText;
    Exit(False);
  end;
  AOutput := mText;
  Result := True;
end;

end.
