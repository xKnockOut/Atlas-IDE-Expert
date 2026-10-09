unit Argus.Common.Documents.Uris;

// Umwandlung zwischen file-URIs des LSP und Dateipfaden sowie eindeutige
// Schlüssel für Dokumente.
//   file:///c%3A/Projekt/A.pas  ↔  c:\Projekt\A.pas
//   file://server/share/A.pas   ↔  \\server\share\A.pas
//   file:///home/a/A.pas        ↔  /home/a/A.pas
// Wie VS Code wird beim Erzeugen der Laufwerksbuchstabe klein geschrieben
// und ":" kodiert; beim Lesen werden alle %XX-Folgen als UTF-8 entschlüsselt.
//
// Key liefert für jede Schreibweise derselben Datei denselben Schlüssel:
// Kodierung, Laufwerksbuchstabe, Groß-/Kleinschreibung, "\\?\"-Präfix,
// "." und ".." werden vereinheitlicht. Junctions und Symlinks löst ein
// optionaler Canonicalizer auf (unter Windows aus Argus.Windows).

interface

uses
  System.SysUtils;

type
  /// <summary>Löst einen Pfad auf seinen kanonischen Pfad auf (Symlinks, Junctions); sonst unverändert.</summary>
  TPathCanonicalizer = reference to function(const APath: string): string;

  TDocumentUris = class
  public
    /// <summary>Pfad zur URI; '' wenn es keine file-URI ist.</summary>
    class function ToPath(const AUri: string): string; static;
    class function FromPath(const APath: string): string; static;
    /// <summary>Vereinheitlicht Trenner, "\\?\"-Präfix, "." und ".."; Windows-Pfade mit "\".</summary>
    class function NormalizePath(const APath: string): string; static;
    /// <summary>Schlüssel für Wörterbücher: gleiche Datei, gleicher Schlüssel.
    /// Andere Schemata (untitled:) bleiben unverändert.</summary>
    class function Key(const AUri: string; const ACanonicalize: TPathCanonicalizer = nil): string; static;
    /// <summary>Gleiche Datei? Vergleicht die Schlüssel.</summary>
    class function SameFile(const AUriA, AUriB: string): Boolean; static;
  end;

implementation

const
  Scheme = 'file://';
  HexDigits = '0123456789ABCDEF';

function PercentDecode(const AValue: string): string;
var
  Bytes: TBytes;
  Count: Integer;
  Index: Integer;
  Code: Integer;
  Chunk: TBytes;
begin
  if Pos('%', AValue) = 0 then
    Exit(AValue);
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
    Move(Chunk[0], Bytes[Count], Length(Chunk));
    Inc(Count, Length(Chunk));
    Inc(Index);
  end;
  Result := TEncoding.UTF8.GetString(Bytes, 0, Count);
end;

function PercentEncode(const AValue: string): string;
var
  Bytes: TBytes;
  Value: Byte;
  Builder: TStringBuilder;
begin
  Bytes := TEncoding.UTF8.GetBytes(AValue);
  Builder := TStringBuilder.Create;
  try
    for Value in Bytes do
      if (Value < $80) and CharInSet(Char(Value), ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~', '/']) then
        Builder.Append(Char(Value))
      else
        Builder.Append('%').Append(HexDigits[(Value shr 4) + 1]).Append(HexDigits[(Value and 15) + 1]);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function IsWindowsPath(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or (Copy(APath, 1, 2) = '\\');
end;

{ TDocumentUris }

class function TDocumentUris.ToPath(const AUri: string): string;
var
  Rest: string;
  Slash: Integer;
  Host: string;
begin
  if not SameText(Copy(AUri, 1, Length(Scheme)), Scheme) then
    Exit('');
  Rest := Copy(AUri, Length(Scheme) + 1, MaxInt);
  Slash := Pos('/', Rest);
  if Slash = 0 then
    Slash := Length(Rest) + 1;
  Host := Copy(Rest, 1, Slash - 1);
  Result := PercentDecode(Copy(Rest, Slash, MaxInt));
  if (Host <> '') and not SameText(Host, 'localhost') then
    Exit('\\' + PercentDecode(Host) + StringReplace(Result, '/', '\', [rfReplaceAll]));
  // /c:/... → c:\...
  if (Length(Result) >= 3) and (Result[1] = '/') and (Result[3] = ':') then
    Result := StringReplace(Copy(Result, 2, MaxInt), '/', '\', [rfReplaceAll]);
end;

class function TDocumentUris.FromPath(const APath: string): string;
var
  Path: string;
begin
  Path := StringReplace(NormalizePath(APath), '\', '/', [rfReplaceAll]);
  if Copy(Path, 1, 2) = '//' then
    Exit(Scheme + PercentEncode(Copy(Path, 3, MaxInt)));
  if (Length(Path) >= 2) and (Path[2] = ':') then
    Path := '/' + LowerCase(Path[1]) + ':' + Copy(Path, 3, MaxInt);
  Result := Scheme + PercentEncode(Path);
end;

class function TDocumentUris.NormalizePath(const APath: string): string;
var
  Path, Prefix, Separator, Part: string;
  Parts: TArray<string>;
  Kept: TArray<string>;
  Count: Integer;
begin
  Path := APath;
  // Lange Pfade: \\?\C:\... und \\?\UNC\server\...
  if SameText(Copy(Path, 1, 8), '\\?\UNC\') then
    Path := '\\' + Copy(Path, 9, MaxInt)
  else if Copy(Path, 1, 4) = '\\?\' then
    Path := Copy(Path, 5, MaxInt);
  if IsWindowsPath(StringReplace(Path, '/', '\', [rfReplaceAll])) then
  begin
    Separator := '\';
    Path := StringReplace(Path, '/', '\', [rfReplaceAll]);
  end
  else
    Separator := '/';

  if Copy(Path, 1, 2) = '\\' then
    Prefix := '\\'
  else if (Length(Path) >= 2) and (Path[2] = ':') then
  begin
    Prefix := UpperCase(Path[1]) + ':' + Separator;
    Delete(Path, 1, 2);
  end
  else if Copy(Path, 1, 1) = Separator then
    Prefix := Separator
  else
    Prefix := '';

  Parts := Path.Split([Separator]);
  SetLength(Kept, Length(Parts));
  Count := 0;
  for Part in Parts do
    if (Part = '') or (Part = '.') then
      Continue
    else if (Part = '..') and (Count > 0) and (Kept[Count - 1] <> '..') then
      Dec(Count)
    else if (Part = '..') and (Prefix <> '') then
      Continue // über die Wurzel hinaus
    else
    begin
      Kept[Count] := Part;
      Inc(Count);
    end;
  SetLength(Kept, Count);
  Result := Prefix + string.Join(Separator, Kept);
end;

class function TDocumentUris.Key(const AUri: string; const ACanonicalize: TPathCanonicalizer): string;
var
  Path: string;
begin
  Path := ToPath(AUri);
  if Path = '' then
    Exit(AUri);
  Path := NormalizePath(Path);
  if Assigned(ACanonicalize) then
    Path := NormalizePath(ACanonicalize(Path));
  // Windows-Dateisysteme unterscheiden Groß-/Kleinschreibung nicht.
  if IsWindowsPath(Path) then
    Path := AnsiLowerCase(Path);
  Result := 'file:' + Path;
end;

class function TDocumentUris.SameFile(const AUriA, AUriB: string): Boolean;
begin
  Result := (ToPath(AUriA) <> '') and (Key(AUriA) = Key(AUriB));
end;

end.
