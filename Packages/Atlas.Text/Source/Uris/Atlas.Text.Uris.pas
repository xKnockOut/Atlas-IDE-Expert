unit Atlas.Text.Uris;

// Umwandlung zwischen file-URIs des LSP und Dateipfaden (gemeinsam für Server
// und Plugin, ADR 0012).
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
  Scheme = 'file://';
  HexDigits = '0123456789ABCDEF';

{ TTextUris }

class function TTextUris.PercentDecode(const AValue: string): string;
var
  Bytes, Chunk: TBytes;
  Count, Index, Code: Integer;
begin
  if Pos('%', AValue) = 0 then
  begin
    Exit(AValue);
  end;
  Bytes := nil;
  SetLength(Bytes, Length(AValue) * 3);
  Count := 0;
  Index := 1;
  while Index <= Length(AValue) do
  begin
    if (AValue[Index] = '%') and (Index + 2 <= Length(AValue)) then
    begin
      Code := StrToIntDef('$' + Copy(AValue, Index + 1, 2), -1);
      if Code >= 0 then
      begin
        Bytes[Count] := Code;
        Inc(Count);
        Inc(Index, 3);
        Continue;
      end;
    end;
    Chunk := TEncoding.UTF8.GetBytes(AValue[Index]);
    if Length(Chunk) > 0 then
    begin
      Move(Chunk[0], Bytes[Count], Length(Chunk));
    end;
    Inc(Count, Length(Chunk));
    Inc(Index);
  end;
  Result := TEncoding.UTF8.GetString(Bytes, 0, Count);
end;

class function TTextUris.PercentEncode(const AValue: string): string;
var
  Bytes: TBytes;
  Value: Byte;
  Builder: TStringBuilder;
begin
  Bytes := TEncoding.UTF8.GetBytes(AValue);
  Builder := TStringBuilder.Create;
  try
    for Value in Bytes do
    begin
      if (Value < $80) and CharInSet(Char(Value), ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~', '/']) then
      begin
        Builder.Append(Char(Value));
      end
      else
      begin
        Builder.Append('%').Append(HexDigits[(Value shr 4) + 1]).Append(HexDigits[(Value and 15) + 1]);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TTextUris.IsWindowsPath(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or (Copy(APath, 1, 2) = '\\');
end;

class function TTextUris.ToPath(const AUri: string): string;
var
  Rest, Host: string;
  Slash: Integer;
begin
  if not SameText(Copy(AUri, 1, Length(Scheme)), Scheme) then
  begin
    Exit('');
  end;
  Rest := Copy(AUri, Length(Scheme) + 1, MaxInt);
  Slash := Pos('/', Rest);
  if Slash = 0 then
  begin
    Slash := Length(Rest) + 1;
  end;
  Host := Copy(Rest, 1, Slash - 1);
  Result := PercentDecode(Copy(Rest, Slash, MaxInt));
  if (Host <> '') and not SameText(Host, 'localhost') then
  begin
    Exit('\\' + PercentDecode(Host) + StringReplace(Result, '/', '\', [rfReplaceAll]));
  end;
  // /c:/... → c:\...
  if (Length(Result) >= 3) and (Result[1] = '/') and (Result[3] = ':') then
  begin
    Result := StringReplace(Copy(Result, 2, MaxInt), '/', '\', [rfReplaceAll]);
  end;
end;

class function TTextUris.FromPath(const APath: string): string;
var
  Path: string;
begin
  Path := StringReplace(NormalizePath(APath), '\', '/', [rfReplaceAll]);
  if Copy(Path, 1, 2) = '//' then
  begin
    Exit(Scheme + PercentEncode(Copy(Path, 3, MaxInt)));
  end;
  if (Length(Path) >= 2) and (Path[2] = ':') then
  begin
    Path := '/' + LowerCase(Path[1]) + ':' + Copy(Path, 3, MaxInt);
  end;
  Result := Scheme + PercentEncode(Path);
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
