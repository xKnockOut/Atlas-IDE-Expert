unit Atlas.Text.Uris;

// Umwandlung zwischen file-URIs des LSP und Dateipfaden (gemeinsam für Server
// und Plugin).
//   file:///c%3A/Projekt/A.pas  ↔  c:\Projekt\A.pas
//   file://server/share/A.pas   ↔  \\server\share\A.pas
//   file:///home/a/A.pas        ↔  /home/a/A.pas
// Wie VS Code wird beim Erzeugen der Laufwerksbuchstabe klein geschrieben
// und ":" kodiert; beim Lesen werden alle %XX-Folgen als UTF-8 entschlüsselt.

interface

uses
  System.SysUtils;

type
  TTextUris = class
  public
    /// <summary>%XX-Folgen als UTF-8 entschlüsseln; ungültige Folgen bleiben stehen.</summary>
    class function PercentDecode(const AValue: string): string; static;
    /// <summary>Alles außer A–Z, a–z, 0–9, "-", ".", "_", "~" und "/" als %XX (UTF-8).</summary>
    class function PercentEncode(const AValue: string): string; static;
    /// <summary>Vereinheitlicht Trenner, "\\?\"-Präfix, "." und ".."; Windows-Pfade mit "\" und großem
    /// Laufwerksbuchstaben.</summary>
    class function NormalizePath(const APath: string): string; static;
    /// <summary>Pfad → file-URI; Laufwerksbuchstabe klein, ":" kodiert (wie VS Code).</summary>
    class function FromPath(const APath: string): string; static;
    /// <summary>file-URI → Pfad; '' für andere Schemata. Windows-Pfade mit "\", POSIX-Pfade behalten "/".</summary>
    class function ToPath(const AUri: string): string; static;
    /// <summary>Pfad mit Laufwerk ("c:…") oder UNC ("\\…").</summary>
    class function IsWindowsPath(const APath: string): Boolean; static;
  end;

implementation

const
  cScheme = 'file://';
  cHexDigits = '0123456789ABCDEF';

{ TTextUris }

class function TTextUris.PercentDecode(const AValue: string): string;
var
  mBytes, mChunk: TBytes;
  mCount, mIndex, mCode: Integer;
begin
  if Pos('%', AValue) = 0 then
  begin
    Exit(AValue);
  end;
  mBytes := nil;
  SetLength(mBytes, Length(AValue) * 3);
  mCount := 0;
  mIndex := 1;
  while mIndex <= Length(AValue) do
  begin
    if (AValue[mIndex] = '%') and (mIndex + 2 <= Length(AValue)) then
    begin
      mCode := StrToIntDef('$' + Copy(AValue, mIndex + 1, 2), -1);
      if mCode >= 0 then
      begin
        mBytes[mCount] := mCode;
        Inc(mCount);
        Inc(mIndex, 3);
        Continue;
      end;
    end;
    mChunk := TEncoding.UTF8.GetBytes(AValue[mIndex]);
    if Length(mChunk) > 0 then
    begin
      Move(mChunk[0], mBytes[mCount], Length(mChunk));
    end;
    Inc(mCount, Length(mChunk));
    Inc(mIndex);
  end;
  Result := TEncoding.UTF8.GetString(mBytes, 0, mCount);
end;

class function TTextUris.PercentEncode(const AValue: string): string;
var
  mBytes: TBytes;
  mValue: Byte;
  mBuilder: TStringBuilder;
begin
  mBytes := TEncoding.UTF8.GetBytes(AValue);
  mBuilder := TStringBuilder.Create;
  try
    for mValue in mBytes do
    begin
      if (mValue < $80) and CharInSet(Char(mValue), ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~', '/']) then
      begin
        mBuilder.Append(Char(mValue));
      end
      else
      begin
        mBuilder.Append('%').Append(cHexDigits[(mValue shr 4) + 1]).Append(cHexDigits[(mValue and 15) + 1]);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TTextUris.IsWindowsPath(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or (Copy(APath, 1, 2) = '\\');
end;

class function TTextUris.ToPath(const AUri: string): string;
var
  mRest, mHost: string;
  mSlash: Integer;
begin
  if not SameText(Copy(AUri, 1, Length(cScheme)), cScheme) then
  begin
    Exit('');
  end;
  mRest := Copy(AUri, Length(cScheme) + 1, MaxInt);
  mSlash := Pos('/', mRest);
  if mSlash = 0 then
  begin
    mSlash := Length(mRest) + 1;
  end;
  mHost := Copy(mRest, 1, mSlash - 1);
  Result := PercentDecode(Copy(mRest, mSlash, MaxInt));
  if (mHost <> '') and not SameText(mHost, 'localhost') then
  begin
    Exit('\\' + PercentDecode(mHost) + StringReplace(Result, '/', '\', [rfReplaceAll]));
  end;
  // /c:/... → c:\...
  if (Length(Result) >= 3) and (Result[1] = '/') and (Result[3] = ':') then
  begin
    Result := StringReplace(Copy(Result, 2, MaxInt), '/', '\', [rfReplaceAll]);
  end;
end;

class function TTextUris.FromPath(const APath: string): string;
var
  mPath: string;
begin
  mPath := StringReplace(NormalizePath(APath), '\', '/', [rfReplaceAll]);
  if Copy(mPath, 1, 2) = '//' then
  begin
    Exit(cScheme + PercentEncode(Copy(mPath, 3, MaxInt)));
  end;
  if (Length(mPath) >= 2) and (mPath[2] = ':') then
  begin
    mPath := '/' + LowerCase(mPath[1]) + ':' + Copy(mPath, 3, MaxInt);
  end;
  Result := cScheme + PercentEncode(mPath);
end;

// Lange Pfade: \\?\C:\... und \\?\UNC\server\... in die kurze Form.
function WithoutLongPrefix(const APath: string): string;
begin
  if SameText(Copy(APath, 1, 8), '\\?\UNC\') then
  begin
    Result := '\\' + Copy(APath, 9, MaxInt);
  end
  else if Copy(APath, 1, 4) = '\\?\' then
  begin
    Result := Copy(APath, 5, MaxInt);
  end
  else
  begin
    Result := APath;
  end;
end;

// Wurzel des Pfads (\\, C:\, / oder ''); ein Laufwerk wird aus APath entfernt.
function TakeRoot(var APath: string; const ASeparator: string): string;
begin
  if Copy(APath, 1, 2) = '\\' then
  begin
    Result := '\\';
  end
  else if (Length(APath) >= 2) and (APath[2] = ':') then
  begin
    Result := UpperCase(APath[1]) + ':' + ASeparator;
    Delete(APath, 1, 2);
  end
  else if Copy(APath, 1, 1) = ASeparator then
  begin
    Result := ASeparator;
  end
  else
  begin
    Result := '';
  end;
end;

// Löst . und .. auf; mit Wurzel (ARooted) fällt .. über die Wurzel hinaus weg.
function ResolveParts(const AParts: TArray<string>; ARooted: Boolean): TArray<string>;
var
  mPart: string;
  mCount: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AParts));
  mCount := 0;
  for mPart in AParts do
  begin
    if (mPart = '..') and (mCount > 0) and (Result[mCount - 1] <> '..') then
    begin
      Dec(mCount);
    end
    else if not ((mPart = '') or (mPart = '.') or ((mPart = '..') and ARooted)) then
    begin
      Result[mCount] := mPart;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TTextUris.NormalizePath(const APath: string): string;
var
  mPath, mRoot, mSeparator: string;
begin
  mPath := WithoutLongPrefix(APath);
  if IsWindowsPath(StringReplace(mPath, '/', '\', [rfReplaceAll])) then
  begin
    mSeparator := '\';
    mPath := StringReplace(mPath, '/', '\', [rfReplaceAll]);
  end
  else
  begin
    mSeparator := '/';
  end;
  mRoot := TakeRoot(mPath, mSeparator);
  Result := mRoot + string.Join(mSeparator, ResolveParts(mPath.Split([mSeparator]), mRoot <> ''));
end;

end.
