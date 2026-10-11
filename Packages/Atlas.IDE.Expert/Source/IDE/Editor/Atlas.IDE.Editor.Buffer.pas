unit Atlas.IDE.Editor.Buffer;

// Lesen aus dem Editorpuffer der IDE und Umrechnen von Positionen. Der Puffer
// ist UTF-8; LSP-Positionen sind 0-basierte Zeilen und UTF-16-Zeichen, die
// Schreib- und Lesepositionen der IDE sind Byte-Offsets im Puffer.

interface

uses
  System.SysUtils,
  ToolsAPI;

type
  TAtlasEditorBuffer = class
  public
    /// <summary>Ganzer Text des Puffers, auch ungespeichert.</summary>
    class function Text(const ABuffer: IOTAEditBuffer): string; static;
    /// <summary>Text der Zeile ALine (1-basiert) ohne Zeilenende.</summary>
    class function LineText(const AView: IOTAEditView; ALine: Integer): string; static;
    /// <summary>Erste Tabulatorweite der Editoroptionen, sonst 8.</summary>
    class function TabWidth(const ABuffer: IOTAEditBuffer): Integer; static;
    /// <summary>Byte-Offset im UTF-8-Puffer zu Zeile/Zeichen (0-basiert, UTF-16) in AText.</summary>
    class function ByteOffset(const AText: string; ALine, ACharacter: Integer): Integer; static;
    /// <summary>Zeichenindex (0-basiert) zu ALine/ACharacter in AText.</summary>
    class function CharOffset(const AText: string; ALine, ACharacter: Integer): Integer; static;
  end;

implementation

uses
  System.Math;

class function TAtlasEditorBuffer.Text(const ABuffer: IOTAEditBuffer): string;
const
  ChunkSize = 65536;
var
  Reader: IOTAEditReader;
  Chunk: AnsiString;
  Bytes: TBytes;
  Position, Count: Integer;
begin
  Reader := ABuffer.CreateReader;
  Position := 0;
  repeat
    SetLength(Chunk, ChunkSize);
    Count := Reader.GetText(Position, PAnsiChar(Chunk), ChunkSize);
    if Count > 0 then
    begin
      SetLength(Bytes, Length(Bytes) + Count);
      Move(Chunk[1], Bytes[Length(Bytes) - Count], Count);
      Inc(Position, Count);
    end;
  until Count < ChunkSize;
  Result := TEncoding.UTF8.GetString(Bytes);
end;

class function TAtlasEditorBuffer.LineText(const AView: IOTAEditView; ALine: Integer): string;
const
  MaxLine = 8192;
var
  CharPos: TOTACharPos;
  Reader: IOTAEditReader;
  Chunk: AnsiString;
  Count, Stop: Integer;
begin
  CharPos.Line := ALine;
  CharPos.CharIndex := 0;
  Reader := AView.Buffer.CreateReader;
  SetLength(Chunk, MaxLine);
  Count := Reader.GetText(AView.CharPosToPos(CharPos), PAnsiChar(Chunk), MaxLine);
  Stop := 1;
  while (Stop <= Count) and not (Chunk[Stop] in [#13, #10]) do
    Inc(Stop);
  Result := UTF8ToString(Copy(Chunk, 1, Stop - 1));
end;

class function TAtlasEditorBuffer.TabWidth(const ABuffer: IOTAEditBuffer): Integer;
var
  Stops: string;
begin
  Result := 8;
  if ABuffer.BufferOptions <> nil then
  begin
    Stops := Trim(ABuffer.BufferOptions.TabStops);
    if Stops <> '' then
      Result := StrToIntDef(Stops.Split([' '])[0], 8);
    if Result < 1 then
      Result := 8;
  end;
end;

class function TAtlasEditorBuffer.CharOffset(const AText: string; ALine, ACharacter: Integer): Integer;
var
  Line, Index, LineEnd: Integer;
begin
  Index := 1;
  Line := 0;
  while (Line < ALine) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  LineEnd := Index;
  while (LineEnd <= Length(AText)) and not CharInSet(AText[LineEnd], [#13, #10]) do
    Inc(LineEnd);
  Result := Min(Index + ACharacter, LineEnd) - 1;
end;

class function TAtlasEditorBuffer.ByteOffset(const AText: string; ALine, ACharacter: Integer): Integer;
begin
  Result := TEncoding.UTF8.GetByteCount(Copy(AText, 1, CharOffset(AText, ALine, ACharacter)));
end;

end.
