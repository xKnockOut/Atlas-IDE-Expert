unit Atlas.Common.Rules.ResourceNames;

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
  mCh: Integer;
begin
  AName := '';
  Result := False;
  if AAt + 2 > ALimit then
  begin
    Exit;
  end;
  if ReadWord(AData, AAt) = $FFFF then
  begin
    Inc(AAt, 4);
    Exit(AAt <= ALimit);
  end;
  while AAt + 2 <= ALimit do
  begin
    mCh := ReadWord(AData, AAt);
    Inc(AAt, 2);
    if mCh = 0 then
    begin
      Exit(True);
    end;
    AName := AName + Char(mCh);
  end;
end;

class function TResourceNames.Read(const AData: TBytes): TArray<string>;
var
  mAt, mNext, mHeaderEnd, mPos: Integer;
  mDataSize, mHeaderSize: Int64;
  mTypeName, mName: string;
begin
  Result := nil;
  mAt := 0;
  while mAt + 8 <= Length(AData) do
  begin
    mDataSize := ReadCardinal(AData, mAt);
    mHeaderSize := ReadCardinal(AData, mAt + 4);
    if (mHeaderSize < 8) or (mAt + mHeaderSize + mDataSize > Length(AData)) then
    begin
      Exit;
    end;
    mHeaderEnd := mAt + Integer(mHeaderSize);
    mPos := mAt + 8;
    if not ReadId(AData, mPos, mHeaderEnd, mTypeName) or not ReadId(AData, mPos, mHeaderEnd, mName) then
    begin
      Exit;
    end;
    if mName <> '' then
    begin
      Result := Result + [UpperCase(mName)];
    end;
    mNext := mHeaderEnd + Integer(mDataSize);
    mAt := (mNext + 3) and not 3;
  end;
end;

end.
