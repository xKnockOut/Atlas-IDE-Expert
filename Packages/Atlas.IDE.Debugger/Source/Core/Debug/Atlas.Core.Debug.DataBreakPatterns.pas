unit Atlas.Core.Debug.DataBreakPatterns;

// Anhalten bei Datenzugriff (#870), Kern ohne IDE: Musterabgleich für SQL-Texte
// und HTTP-Aufrufe sowie das Lesen von Zeichenketten aus der Auswertung des
// Debuggers.
// - Muster mit * als Platzhalter für beliebig viele Zeichen; das Muster muss den
//   ganzen Text treffen („UPDATE Kunden*“ trifft „UPDATE Kunden SET …“, nicht
//   „SELECT … FROM Kunden“). Leerraum (auch Zeilenumbrüche) zählt in Text und
//   Muster als ein Leerzeichen, vorn und hinten gar nicht. Leeres Muster trifft
//   alles.
// - HTTP-Muster: wahlweise vorn Methoden („POST */api/auftrag*“,
//   „GET,PUT *“), dann das Muster für die URL. Ohne Methoden gilt jede.
// - Zeichenketten des Debuggers: 'It''s', 'Zeile 1'#13#10'Zeile 2',
//   #$D#$A, auch Teile ohne Anführungszeichen dazwischen.

interface

uses
  System.SysUtils;

type
  TAtlasHttpPattern = record
    /// <summary>Methoden in Großbuchstaben; leer = alle.</summary>
    Methods: TArray<string>;
    Url: string;
  end;

  TAtlasDataPatterns = class
  public const
    cHttpMethods: array[0..6] of string = ('GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS');
    /// <summary>Vorsilbe der Werte von TRESTRequestMethod (rmGET, rmPOST …).</summary>
    cRestPrefix = 'rm';
  private
    class function Matches(const APattern, AText: string): Boolean; static;
    class function IsHttpMethod(const AText: string): Boolean; static;
    class function ReadChar(const AValue: string; var AIndex: Integer; AResult: TStringBuilder): Boolean; static;
    class function ReadQuoted(const AValue: string; var AIndex: Integer; AResult: TStringBuilder): Boolean; static;
  public
    /// <summary>Leerraum zusammengefasst und außen entfernt.</summary>
    class function Squeeze(const AText: string): string; static;
    /// <summary>Trifft APattern (mit *) den ganzen Text AText? AIgnoreCase: ohne Groß-/Kleinschreibung.</summary>
    class function Like(const APattern, AText: string; AIgnoreCase: Boolean): Boolean; static;
    /// <summary>„POST */api/auftrag*“ → Methoden [POST], URL-Muster „*/api/auftrag*“.</summary>
    class function ParseHttp(const APattern: string): TAtlasHttpPattern; static;
    /// <summary>Methode (ohne Rücksicht auf Groß-/Kleinschreibung) und URL gegen APattern.</summary>
    class function HttpMatches(const APattern: TAtlasHttpPattern; const AMethod, AUrl: string;
      AIgnoreCase: Boolean): Boolean; static;
    /// <summary>Methode aus dem Namen des Aufrufs (Get → GET) bzw. aus einem Wert wie rmPOST; '' ohne.</summary>
    class function HttpMethodOf(const AText: string): string; static;
    /// <summary>Wert einer Zeichenkette aus der Auswertung des Debuggers; False, wenn AValue keine ist.</summary>
    class function DebuggerString(const AValue: string; out AText: string): Boolean; static;
  end;

implementation

{ TAtlasDataPatterns }

class function TAtlasDataPatterns.Squeeze(const AText: string): string;
var
  mChar: Char;
  mBlank: Boolean;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBlank := False;
    for mChar in AText do
    begin
      if CharInSet(mChar, [' ', #9, #10, #13]) then
      begin
        mBlank := mBuilder.Length > 0;
        Continue;
      end;
      if mBlank then
      begin
        mBuilder.Append(' ');
        mBlank := False;
      end;
      mBuilder.Append(mChar);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasDataPatterns.Matches(const APattern, AText: string): Boolean;
var
  mPattern, mText, mStar, mRetry: Integer;
begin
  // Platzhalter mit Rücksprung: Passt ein Zeichen nicht, schluckt der letzte * eines mehr.
  mPattern := 1;
  mText := 1;
  mStar := 0;
  mRetry := 0;
  while mText <= Length(AText) do
  begin
    if (mPattern <= Length(APattern)) and (APattern[mPattern] = '*') then
    begin
      mStar := mPattern;
      mRetry := mText;
      Inc(mPattern);
    end
    else if (mPattern <= Length(APattern)) and (APattern[mPattern] = AText[mText]) then
    begin
      Inc(mPattern);
      Inc(mText);
    end
    else if mStar > 0 then
    begin
      mPattern := mStar + 1;
      Inc(mRetry);
      mText := mRetry;
    end
    else
    begin
      Exit(False);
    end;
  end;
  while (mPattern <= Length(APattern)) and (APattern[mPattern] = '*') do
  begin
    Inc(mPattern);
  end;
  Result := mPattern > Length(APattern);
end;

class function TAtlasDataPatterns.Like(const APattern, AText: string; AIgnoreCase: Boolean): Boolean;
var
  mPattern, mText: string;
begin
  mPattern := Squeeze(APattern);
  if mPattern = '' then
  begin
    Exit(True);
  end;
  mText := Squeeze(AText);
  if AIgnoreCase then
  begin
    mPattern := AnsiUpperCase(mPattern);
    mText := AnsiUpperCase(mText);
  end;
  Result := Matches(mPattern, mText);
end;

class function TAtlasDataPatterns.IsHttpMethod(const AText: string): Boolean;
var
  mMethod: string;
begin
  Result := False;
  for mMethod in cHttpMethods do
  begin
    if SameText(mMethod, AText) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasDataPatterns.ParseHttp(const APattern: string): TAtlasHttpPattern;
var
  mText, mHead, mPart: string;
  mSpace: Integer;
  mMethods: TArray<string>;
begin
  Result := Default(TAtlasHttpPattern);
  mText := Squeeze(APattern);
  mSpace := Pos(' ', mText);
  if mSpace = 0 then
  begin
    mHead := mText;
  end
  else
  begin
    mHead := Copy(mText, 1, mSpace - 1);
  end;
  mMethods := nil;
  for mPart in mHead.Split([',']) do
  begin
    if not IsHttpMethod(Trim(mPart)) then
    begin
      // Kein Methodenkopf: alles ist das URL-Muster.
      Result.Url := mText;
      Exit;
    end;
    mMethods := mMethods + [UpperCase(Trim(mPart))];
  end;
  Result.Methods := mMethods;
  if mSpace > 0 then
  begin
    Result.Url := Trim(Copy(mText, mSpace + 1, MaxInt));
  end;
end;

class function TAtlasDataPatterns.HttpMatches(const APattern: TAtlasHttpPattern; const AMethod, AUrl: string;
  AIgnoreCase: Boolean): Boolean;
var
  mMethod: string;
begin
  Result := Length(APattern.Methods) = 0;
  for mMethod in APattern.Methods do
  begin
    Result := Result or SameText(mMethod, AMethod);
  end;
  Result := Result and Like(APattern.Url, AUrl, AIgnoreCase);
end;

class function TAtlasDataPatterns.HttpMethodOf(const AText: string): string;
var
  mText, mRest: string;
begin
  mText := Trim(AText);
  mRest := Copy(mText, Length(cRestPrefix) + 1, MaxInt);
  if mText.StartsWith(cRestPrefix, True) and IsHttpMethod(mRest) then
  begin
    mText := mRest;
  end;
  Result := '';
  if IsHttpMethod(mText) then
  begin
    Result := UpperCase(mText);
  end;
end;

class function TAtlasDataPatterns.ReadChar(const AValue: string; var AIndex: Integer;
  AResult: TStringBuilder): Boolean;
var
  mStart: Integer;
  mCode: Integer;
  mDigits: string;
begin
  // #13, #$D: Zahl bis zum nächsten Zeichen, das keine Ziffer ist.
  Inc(AIndex);
  mStart := AIndex;
  if (AIndex <= Length(AValue)) and (AValue[AIndex] = '$') then
  begin
    Inc(AIndex);
    while (AIndex <= Length(AValue)) and CharInSet(AValue[AIndex], ['0'..'9', 'a'..'f', 'A'..'F']) do
    begin
      Inc(AIndex);
    end;
  end
  else
  begin
    while (AIndex <= Length(AValue)) and CharInSet(AValue[AIndex], ['0'..'9']) do
    begin
      Inc(AIndex);
    end;
  end;
  mDigits := Copy(AValue, mStart, AIndex - mStart);
  Result := TryStrToInt(mDigits, mCode) and (mCode >= 0) and (mCode <= $FFFF);
  if Result then
  begin
    AResult.Append(Char(mCode));
  end;
end;

class function TAtlasDataPatterns.ReadQuoted(const AValue: string; var AIndex: Integer;
  AResult: TStringBuilder): Boolean;
begin
  // AIndex steht auf dem öffnenden Hochkomma; danach hinter dem schließenden.
  Inc(AIndex);
  while AIndex <= Length(AValue) do
  begin
    if AValue[AIndex] <> '''' then
    begin
      AResult.Append(AValue[AIndex]);
    end
    else if (AIndex < Length(AValue)) and (AValue[AIndex + 1] = '''') then
    begin
      AResult.Append('''');
      Inc(AIndex);
    end
    else
    begin
      Inc(AIndex);
      Exit(True);
    end;
    Inc(AIndex);
  end;
  Result := False;
end;

class function TAtlasDataPatterns.DebuggerString(const AValue: string; out AText: string): Boolean;
var
  mValue: string;
  mIndex: Integer;
  mText: TStringBuilder;
begin
  AText := '';
  mValue := Trim(AValue);
  Result := (mValue <> '') and CharInSet(mValue[1], ['''', '#']);
  mIndex := 1;
  mText := TStringBuilder.Create;
  try
    while Result and (mIndex <= Length(mValue)) do
    begin
      case mValue[mIndex] of
        '#':
          Result := ReadChar(mValue, mIndex, mText);
        '''':
          Result := ReadQuoted(mValue, mIndex, mText);
      else
        // Lange Texte kürzt der Debugger mit „...“ am Ende.
        mText.Append(Copy(mValue, mIndex, MaxInt));
        mIndex := Length(mValue) + 1;
      end;
    end;
    if Result then
    begin
      AText := mText.ToString;
    end;
  finally
    mText.Free;
  end;
end;

end.
