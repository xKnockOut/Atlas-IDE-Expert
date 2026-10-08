unit BDLsp.Common.Lsp.Uris;

// Umwandlung zwischen file-URIs des LSP und Dateipfaden.
//   file:///c%3A/Projekt/A.pas  ↔  c:\Projekt\A.pas
//   file://server/share/A.pas   ↔  \\server\share\A.pas
//   file:///home/a/A.pas        ↔  /home/a/A.pas
// Wie VS Code wird beim Erzeugen der Laufwerksbuchstabe klein geschrieben
// und ":" kodiert; beim Lesen werden alle %XX-Folgen als UTF-8 entschlüsselt.

interface

uses
  System.SysUtils;

type
  TLspUris = class
  public
    /// <summary>Pfad zur URI; '' wenn es keine file-URI ist.</summary>
    class function ToPath(const AUri: string): string; static;
    class function FromPath(const APath: string): string; static;
    /// <summary>Gleiche Datei? Vergleicht die Pfade ohne Groß-/Kleinschreibung.</summary>
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

{ TLspUris }

class function TLspUris.ToPath(const AUri: string): string;
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

class function TLspUris.FromPath(const APath: string): string;
var
  Path: string;
begin
  Path := StringReplace(APath, '\', '/', [rfReplaceAll]);
  if Copy(Path, 1, 2) = '//' then
    Exit(Scheme + PercentEncode(Copy(Path, 3, MaxInt)));
  if (Length(Path) >= 2) and (Path[2] = ':') then
    Path := '/' + LowerCase(Path[1]) + ':' + Copy(Path, 3, MaxInt);
  Result := Scheme + PercentEncode(Path);
end;

class function TLspUris.SameFile(const AUriA, AUriB: string): Boolean;
var
  PathA: string;
begin
  PathA := ToPath(AUriA);
  Result := (PathA <> '') and SameText(PathA, ToPath(AUriB));
end;

end.
