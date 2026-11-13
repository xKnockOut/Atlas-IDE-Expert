unit Atlas.Common.Lsp.Completion.TypeConversions;

// Typverträglichkeit für die Vervollständigung (#417) und übliche Umwandlungen in den erwarteten Typ (#490):
// eingebaute Typfamilien, Vergleich ohne Unit-Präfix und die Texte für IntToStr, StrToInt, Helper-Stil usw.

interface

type
{$SCOPEDENUMS ON}
  TTypeFamily = (None, Integer_, Float, String_, Char_, Boolean_);

  /// <summary>Übliche Umwandlung eines Werts in den erwarteten Typ (#490): Text mit dem Ausdruck, benötigte
  /// Units; Lossy bei Gleitkomma nach Ganzzahl (dann ohne Text, nur der Hinweis auf Round und Trunc).</summary>
  TTypeConversion = record
    Text: string;
    Units: TArray<string>;
    Lossy: Boolean;
  end;
{$SCOPEDENUMS OFF}

/// <summary>Typname für den Vergleich: ohne Leerzeichen und Unit-Präfix, klein.</summary>
function PlainType(const AType: string): string;
/// <summary>Familie eingebauter Typen für die Zuweisungsverträglichkeit (#417).</summary>
function TypeFamily(const APlain: string): TTypeFamily;
/// <summary>Ein Wert vom Typ AActual passt zu AExpected: gleich, gleiche Familie eingebauter Typen,
/// Integer zu Gleitkomma, Char zu String. ACheckDescent: Beides sind keine eingebauten Typen; ob AActual
/// von AExpected abstammt, muss die Namensauflösung klären.</summary>
function TypeFits(const AActual, AExpected: string; out ACheckDescent: Boolean): Boolean;
/// <summary>Umwandlung von AExpression (Typ AActual, nach Aliasen) in AExpected (#490): Zahl, Boolean,
/// TDateTime/TDate/TTime und Aufzählung (AEnumType, '' sonst) nach string; string nach Ganzzahl und
/// Gleitkomma. AHelper: Helper-Stil (X.ToString), wo es ihn gibt. False ohne Umwandlung und ohne Hinweis.</summary>
function TypeConversion(const AActual, AExpected, AEnumType, AExpression: string; AHelper: Boolean;
  out AResult: TTypeConversion): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils;

function PlainType(const AType: string): string;
begin
  Result := LowerCase(AType.Replace(' ', ''));
  if (Pos('<', Result) = 0) and (LastDelimiter('.', Result) > 0) then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

function TypeFamily(const APlain: string): TTypeFamily;
begin
  if MatchText(APlain, ['integer', 'cardinal', 'int64', 'uint64', 'byte', 'word', 'shortint', 'smallint', 'longint',
    'longword', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16', 'uint32', 'fixedint',
    'fixeduint']) then
  begin
    Result := TTypeFamily.Integer_;
  end
  else if MatchText(APlain, ['double', 'single', 'extended', 'real', 'currency', 'comp']) then
  begin
    Result := TTypeFamily.Float;
  end
  else if MatchText(APlain, ['string', 'unicodestring', 'ansistring', 'widestring', 'shortstring', 'rawbytestring',
    'utf8string']) then
  begin
    Result := TTypeFamily.String_;
  end
  else if MatchText(APlain, ['char', 'widechar', 'ansichar']) then
  begin
    Result := TTypeFamily.Char_;
  end
  else if MatchText(APlain, ['boolean', 'bytebool', 'wordbool', 'longbool']) then
  begin
    Result := TTypeFamily.Boolean_;
  end
  else
  begin
    Result := TTypeFamily.None;
  end;
end;

function TypeFits(const AActual, AExpected: string; out ACheckDescent: Boolean): Boolean;
var
  mActual, mExpected: TTypeFamily;
begin
  ACheckDescent := False;
  if (AActual = '') or (AExpected = '') then
  begin
    Exit(False);
  end;
  if PlainType(AActual) = PlainType(AExpected) then
  begin
    Exit(True);
  end;
  mActual := TypeFamily(PlainType(AActual));
  mExpected := TypeFamily(PlainType(AExpected));
  if mExpected <> TTypeFamily.None then
  begin
    Exit((mActual = mExpected) or (mExpected = TTypeFamily.Float) and (mActual = TTypeFamily.Integer_) or
      (mExpected = TTypeFamily.String_) and (mActual = TTypeFamily.Char_));
  end;
  ACheckDescent := mActual = TTypeFamily.None;
  Result := False;
end;

/// <summary>Umwandlung von AExpression (Typ APlain, Familie AActual) nach string; '' ohne. AHelperText: Helper-Stil,
/// '' ohne; AUnits nur, wenn nicht System.SysUtils.</summary>
function ToStringText(const APlain: string; AActual: TTypeFamily; const AEnumType, AExpression: string;
  out AHelperText: string; out AUnits: TArray<string>): string;
begin
  AHelperText := '';
  AUnits := nil;
  Result := '';
  if AEnumType <> '' then
  begin
    Result := 'GetEnumName(TypeInfo(' + AEnumType + '), Ord(' + AExpression + '))';
    AUnits := ['System.TypInfo'];
  end
  else if APlain = 'tdatetime' then
  begin
    Result := 'DateTimeToStr(' + AExpression + ')';
  end
  else if APlain = 'tdate' then
  begin
    Result := 'DateToStr(' + AExpression + ')';
  end
  else if APlain = 'ttime' then
  begin
    Result := 'TimeToStr(' + AExpression + ')';
  end
  else if AActual in [TTypeFamily.Integer_, TTypeFamily.Float] then
  begin
    Result := 'IntToStr(' + AExpression + ')';
    if AActual = TTypeFamily.Float then
    begin
      Result := 'FloatToStr(' + AExpression + ')';
    end;
    AHelperText := AExpression + '.ToString';
  end
  else if AActual = TTypeFamily.Boolean_ then
  begin
    // Ohne TUseBoolStrs.True liefert der Helper "-1" und "0".
    Result := 'BoolToStr(' + AExpression + ', True)';
    AHelperText := AExpression + '.ToString(TUseBoolStrs.True)';
  end;
end;

/// <summary>Umwandlung von AExpression (string) in die Zahlenfamilie AExpected (Typ APlainExpected); '' ohne.
/// </summary>
function FromStringText(const APlainExpected: string; AExpected: TTypeFamily; const AExpression: string;
  out AHelperText: string): string;
begin
  AHelperText := '';
  Result := '';
  if AExpected = TTypeFamily.Float then
  begin
    Result := 'StrToFloat(' + AExpression + ')';
    AHelperText := AExpression + '.ToDouble';
  end
  else if (AExpected = TTypeFamily.Integer_) and MatchText(APlainExpected, ['int64', 'uint64']) then
  begin
    Result := 'StrToInt64(' + AExpression + ')';
    AHelperText := AExpression + '.ToInt64';
  end
  else if AExpected = TTypeFamily.Integer_ then
  begin
    Result := 'StrToInt(' + AExpression + ')';
    AHelperText := AExpression + '.ToInteger';
  end;
end;

function TypeConversion(const AActual, AExpected, AEnumType, AExpression: string; AHelper: Boolean;
  out AResult: TTypeConversion): Boolean;
var
  mActual, mExpected: TTypeFamily;
  mPlain, mText, mHelper: string;
begin
  AResult := Default(TTypeConversion);
  mPlain := PlainType(AActual);
  mActual := TypeFamily(mPlain);
  mExpected := TypeFamily(PlainType(AExpected));
  mText := '';
  mHelper := '';
  if mExpected = TTypeFamily.String_ then
  begin
    mText := ToStringText(mPlain, mActual, AEnumType, AExpression, mHelper, AResult.Units);
  end
  else if mActual = TTypeFamily.String_ then
  begin
    mText := FromStringText(PlainType(AExpected), mExpected, AExpression, mHelper);
  end
  else if (mActual = TTypeFamily.Float) and (mExpected = TTypeFamily.Integer_) then
  begin
    // Verlustbehaftet: kein Vorschlag, nur der Hinweis.
    AResult.Lossy := True;
    Exit(True);
  end;
  Result := mText <> '';
  if not Result then
  begin
    Exit;
  end;
  AResult.Text := mText;
  if AHelper and (mHelper <> '') then
  begin
    AResult.Text := mHelper;
  end;
  if AResult.Units = nil then
  begin
    AResult.Units := ['System.SysUtils'];
  end;
end;

end.
