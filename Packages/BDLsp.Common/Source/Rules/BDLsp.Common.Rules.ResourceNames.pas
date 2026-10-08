unit BDLsp.Common.Rules.ResourceNames;

// Namen der Ressourcen in einer 32-Bit-Ressourcendatei (.res, .dcr) für #114.
// Aufbau je Eintrag: DataSize, HeaderSize, Typ, Name (jeweils Ordinalzahl $FFFF+Wort oder
// UTF-16 mit Null-Ende), Rest des Kopfes; Daten und nächster Eintrag auf 4 Byte ausgerichtet.

interface

uses
  System.SysUtils;

type
  TResourceNames = class
  public
    /// <summary>Namen aller Einträge mit Textnamen in Großbuchstaben; Ordinalnamen fehlen.
    /// Bei beschädigten Daten die bis dahin gelesenen Namen.</summary>
    class function Read(const AData: TBytes): TArray<string>; static;
  end;

implementation

function ReadWord(const AData: TBytes; AAt: Integer): Integer;
begin
  Result := AData[AAt] or (AData[AAt + 1] shl 8);
end;

function ReadCardinal(const AData: TBytes; AAt: Integer): Int64;
begin
  Result := Int64(ReadWord(AData, AAt)) or (Int64(ReadWord(AData, AAt + 2)) shl 16);
end;

/// <summary>Typ oder Name ab AAt; AName = '' bei Ordinalzahl. False, wenn die Daten nicht reichen.</summary>
function ReadId(const AData: TBytes; var AAt: Integer; ALimit: Integer; out AName: string): Boolean;
var
  Ch: Integer;
begin
  AName := '';
  Result := False;
  if AAt + 2 > ALimit then
    Exit;
  if ReadWord(AData, AAt) = $FFFF then
  begin
    Inc(AAt, 4);
    Exit(AAt <= ALimit);
  end;
  while AAt + 2 <= ALimit do
  begin
    Ch := ReadWord(AData, AAt);
    Inc(AAt, 2);
    if Ch = 0 then
      Exit(True);
    AName := AName + Char(Ch);
  end;
end;

class function TResourceNames.Read(const AData: TBytes): TArray<string>;
var
  At, Next, HeaderEnd, Pos: Integer;
  DataSize, HeaderSize: Int64;
  TypeName, Name: string;
begin
  Result := nil;
  At := 0;
  while At + 8 <= Length(AData) do
  begin
    DataSize := ReadCardinal(AData, At);
    HeaderSize := ReadCardinal(AData, At + 4);
    if (HeaderSize < 8) or (At + HeaderSize + DataSize > Length(AData)) then
      Exit;
    HeaderEnd := At + Integer(HeaderSize);
    Pos := At + 8;
    if not ReadId(AData, Pos, HeaderEnd, TypeName) or not ReadId(AData, Pos, HeaderEnd, Name) then
      Exit;
    if Name <> '' then
      Result := Result + [UpperCase(Name)];
    Next := HeaderEnd + Integer(DataSize);
    At := (Next + 3) and not 3;
  end;
end;

end.
