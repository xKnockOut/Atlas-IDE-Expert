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
  private
    class function Matches(const APattern, AText: string; APatternIndex, ATextIndex: Integer): Boolean; static;
    class function IsHttpMethod(const AText: string): Boolean; static;
    class function ReadChar(const AValue: string; var AIndex: Integer; var AResult: string): Boolean; static;
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

class function TAtlasDataPatterns.Matches(const APattern, AText: string; APatternIndex, ATextIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  // Rekursion nur an *: Folgen von * zählen wie eines.
  while APatternIndex <= Length(APattern) do
  begin
    if APattern[APatternIndex] = '*' then
    begin
      while (APatternIndex <= Length(APattern)) and (APattern[APatternIndex] = '*') do
      begin
        Inc(APatternIndex);
      end;
      if APatternIndex > Length(APattern) then
      begin
        Exit(True);
      end;
      for mIndex := ATextIndex to Length(AText) do
      begin
        if (AText[mIndex] = APattern[APatternIndex]) and Matches(APattern, AText, APatternIndex, mIndex) then
        begin
          Exit(True);
        end;
      end;
      Exit(False);
    end;
    if (ATextIndex > Length(AText)) or (AText[ATextIndex] <> APattern[APatternIndex]) then
    begin
      Exit(False);
    end;
    Inc(APatternIndex);
    Inc(ATextIndex);
  end;
  Result := ATextIndex > Length(AText);
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
  Result := Matches(mPattern, mText, 1, 1);
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
  mText: string;
begin
  mText := Trim(AText);
  // TRESTRequestMethod: rmGET, rmPOST …
  if (Length(mText) > 2) and SameText(Copy(mText, 1, 2), 'rm') and IsHttpMethod(Copy(mText, 3, MaxInt)) then
  begin
    mText := Copy(mText, 3, MaxInt);
  end;
  Result := '';
  if IsHttpMethod(mText) then
  begin
    Result := UpperCase(mText);
  end;
end;

class function TAtlasDataPatterns.ReadChar(const AValue: string; var AIndex: Integer; var AResult: string): Boolean;
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
    AResult := AResult + Char(mCode);
  end;
end;

class function TAtlasDataPatterns.DebuggerString(const AValue: string; out AText: string): Boolean;
var
  mValue: string;
  mIndex: Integer;
begin
  AText := '';
  mValue := Trim(AValue);
  Result := (mValue <> '') and CharInSet(mValue[1], ['''', '#']);
  mIndex := 1;
  while Result and (mIndex <= Length(mValue)) do
  begin
    if mValue[mIndex] = '#' then
    begin
      Result := ReadChar(mValue, mIndex, AText);
    end
    else if mValue[mIndex] = '''' then
    begin
      Inc(mIndex);
      while mIndex <= Length(mValue) do
      begin
        if mValue[mIndex] <> '''' then
        begin
          AText := AText + mValue[mIndex];
        end
        else if (mIndex < Length(mValue)) and (mValue[mIndex + 1] = '''') then
        begin
          AText := AText + '''';
          Inc(mIndex);
        end
        else
        begin
          Break;
        end;
        Inc(mIndex);
      end;
      Result := mIndex <= Length(mValue);
      Inc(mIndex);
    end
    else
    begin
      // Lange Texte kürzt der Debugger mit „...“ am Ende.
      AText := AText + Copy(mValue, mIndex, MaxInt);
      mIndex := Length(mValue) + 1;
    end;
  end;
  if not Result then
  begin
    AText := '';
  end;
end;

end.
