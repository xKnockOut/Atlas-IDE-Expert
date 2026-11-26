unit Atlas.Common.Pascal.TypeTexts;

// Typtexte, wie sie im Quelltext stehen, ohne Index: Elementtyp von Arrays und
// Mengen, Familien eingebauter Typen (String, Boolean, Zeiger) und das
// Einsetzen generischer Bindungen ("T=TKunde"). Gemeinsam für Vervollständigung,
// Inlay Hints, Signaturhilfe, Postfix-Vorlagen und Namensvorschläge (NameFromType).

interface

type
  TPascalTypeTexts = record
  public
    /// <summary>Elementtyp aus 'TArray&lt;T&gt;', 'array of T', 'array[..] of T', 'set of T'; '' sonst.</summary>
    class function ElementOf(const ATypeText: string): string; static;
    /// <summary>String-Typen.</summary>
    class function IsStringType(const ATypeText: string): Boolean; static;
    /// <summary>Boolesche Typen.</summary>
    class function IsBooleanType(const ATypeText: string): Boolean; static;
    /// <summary>Zeigertypen: Pointer, ^T, PChar, PByte …</summary>
    class function IsPointerType(const ATypeText: string): Boolean; static;
    /// <summary>Setzt Bindungen "T=TKunde" wortweise in AText ein (#466).</summary>
    class function SubstituteWords(const AText: string; const ABindings: TArray<string>): string; static;
    /// <summary>"IComparer&lt;TKunde&gt;" aus Container und Bindungen; ohne Bindungen der Container.</summary>
    class function GenericName(const AContainer: string; const ABindings: TArray<string>): string; static;
    /// <summary>Name aus dem Typ (#452): ohne T- bzw. I-Präfix, Unit und Typargumente; Text, Ch, Flag bzw. Value
    /// für eingebaute Typen und Platzhalter in geschweiften Klammern.</summary>
    class function NameFromType(const ATypeName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions;

{ TPascalTypeTexts }

class function TPascalTypeTexts.ElementOf(const ATypeText: string): string;
var
  mText: string;
  mOfPos: Integer;
begin
  Result := '';
  mText := Trim(ATypeText);
  if StartsText('TArray<', mText) and EndsStr('>', mText) then
  begin
    Exit(Trim(Copy(mText, Length('TArray<') + 1, Length(mText) - Length('TArray<') - 1)));
  end;
  if StartsText('array', mText) or StartsText('set ', mText) then
  begin
    mOfPos := Pos(' OF ', UpperCase(mText));
    if mOfPos > 0 then
    begin
      Result := Trim(Copy(mText, mOfPos + Length(' of '), MaxInt));
    end;
    // array of const hat keinen Elementtyp, über den sich schreiben ließe.
    if SameText(Result, 'const') then
    begin
      Result := '';
    end;
  end;
end;

class function TPascalTypeTexts.IsStringType(const ATypeText: string): Boolean;
begin
  Result := MatchText(Trim(ATypeText), ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString',
    'UTF8String', 'RawByteString', 'System.string', 'System.UnicodeString']);
end;

class function TPascalTypeTexts.IsBooleanType(const ATypeText: string): Boolean;
begin
  Result := MatchText(Trim(ATypeText), ['Boolean', 'ByteBool', 'WordBool', 'LongBool', 'System.Boolean']);
end;

class function TPascalTypeTexts.IsPointerType(const ATypeText: string): Boolean;
var
  mText: string;
begin
  mText := Trim(ATypeText);
  Result := MatchText(mText, ['Pointer', 'PChar', 'PAnsiChar', 'PWideChar', 'PByte']) or StartsStr('^', mText);
end;

class function TPascalTypeTexts.SubstituteWords(const AText: string; const ABindings: TArray<string>): string;
var
  mBinding: string;
  mEqual: Integer;
begin
  Result := AText;
  for mBinding in ABindings do
  begin
    mEqual := Pos('=', mBinding);
    Result := TRegEx.Replace(Result, '(?<![\w.])' + TRegEx.Escape(Copy(mBinding, 1, mEqual - 1)) + '(?![\w])',
      Copy(mBinding, mEqual + 1, MaxInt).Replace('$', '$$'));
  end;
end;

class function TPascalTypeTexts.GenericName(const AContainer: string; const ABindings: TArray<string>): string;
var
  mBinding: string;
  mValues: TArray<string>;
begin
  Result := AContainer;
  if Length(ABindings) = 0 then
  begin
    Exit;
  end;
  mValues := nil;
  for mBinding in ABindings do
  begin
    mValues := mValues + [Copy(mBinding, Pos('=', mBinding) + 1, MaxInt)];
  end;
  Result := Result + '<' + string.Join(', ', mValues) + '>';
end;

class function TPascalTypeTexts.NameFromType(const ATypeName: string): string;
begin
  Result := ATypeName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Result.Substring(Result.LastIndexOf('.') + 1);
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 'I']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  if MatchText(Result, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String',
    'ShortString']) then
  begin
    Result := 'Text';
  end
  else if MatchText(Result, ['Char', 'WideChar', 'AnsiChar']) then
  begin
    Result := 'Ch';
  end
  else if SameText(Result, 'Boolean') then
  begin
    Result := 'Flag';
  end
  else if MatchText(Result, ['Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Byte', 'Word',
    'SmallInt', 'ShortInt', 'LongInt', 'LongWord', 'Double', 'Single', 'Extended', 'Real', 'Currency', 'Comp',
    'Variant', 'Pointer', '']) or StartsStr('{', Result) then
  begin
    Result := 'Value';
  end;
end;

end.
