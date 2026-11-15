unit Atlas.Core.Lsp.TextOffsets;

// Stellen im Text des Editors, ohne Open Tools API: Der Schreiber der IDE (IOTAEditWriter) zählt UTF-8-Bytes ab
// Pufferanfang, die Server und Modelle Zeilen und Zeichen (UTF-16). Zeilen enden mit #10 (#13 davor zählt zur
// Zeile, aber nicht als Zeichen am Zeilenende).

interface

type
  TAtlasTextOffsets = record
  public
    /// <summary>Zeichenindex (0-basiert) zu ALine/ACharacter (0-basiert) in AText; hinter dem Zeilenende das
    /// Zeilenende.</summary>
    class function CharOffset(const AText: string; ALine, ACharacter: Integer): Integer; static;
    /// <summary>UTF-8-Byte-Offset (0-basiert) zu ALine/ACharacter in AText.</summary>
    class function ByteOffset(const AText: string; ALine, ACharacter: Integer): Integer; static;
    /// <summary>UTF-8-Byte-Offset der ersten AOffset Zeichen von AText.</summary>
    class function BytesBefore(const AText: string; AOffset: Integer): Integer; static;
    /// <summary>Länge von AText in UTF-8-Bytes.</summary>
    class function Utf8Length(const AText: string): Integer; static;
    /// <summary>Zeile ALine (0-basiert) aus AText ohne Zeilenende; '' außerhalb.</summary>
    class function LineOf(const AText: string; ALine: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasTextOffsets }

class function TAtlasTextOffsets.CharOffset(const AText: string; ALine, ACharacter: Integer): Integer;
var
  mLine, mIndex, mLineEnd: Integer;
begin
  mIndex := 1;
  mLine := 0;
  while (mLine < ALine) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  mLineEnd := mIndex;
  while (mLineEnd <= Length(AText)) and not CharInSet(AText[mLineEnd], [#13, #10]) do
  begin
    Inc(mLineEnd);
  end;
  Result := Min(mIndex + ACharacter, mLineEnd) - 1;
end;

class function TAtlasTextOffsets.ByteOffset(const AText: string; ALine, ACharacter: Integer): Integer;
begin
  Result := BytesBefore(AText, CharOffset(AText, ALine, ACharacter));
end;

class function TAtlasTextOffsets.BytesBefore(const AText: string; AOffset: Integer): Integer;
begin
  Result := TEncoding.UTF8.GetByteCount(Copy(AText, 1, AOffset));
end;

class function TAtlasTextOffsets.Utf8Length(const AText: string): Integer;
begin
  Result := TEncoding.UTF8.GetByteCount(AText);
end;

class function TAtlasTextOffsets.LineOf(const AText: string; ALine: Integer): string;
var
  mLines: TArray<string>;
begin
  mLines := AText.Replace(#13, '').Split([#10]);
  if (ALine >= 0) and (ALine <= High(mLines)) then
  begin
    Result := mLines[ALine];
  end
  else
  begin
    Result := '';
  end;
end;

end.
