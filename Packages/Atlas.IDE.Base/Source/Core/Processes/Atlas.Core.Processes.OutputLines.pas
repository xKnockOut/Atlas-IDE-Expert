unit Atlas.Core.Processes.OutputLines;

// Ausgabe eines Prozesses in Zeilen, ohne VCL und Open Tools API; gemeinsam für
// die Projektaufgaben (#900, Modul Build) und die angedockte Konsolenausgabe
// (#581, Modul Debugger):
// - Feed zerlegt die Bytes in Zeilen, sobald ein Zeilenende (LF) da ist: je
//   Zeile UTF-8, wenn die Bytes gültiges UTF-8 sind, sonst die Codepage des
//   Aufrufers (pwsh und cmd schreiben umgeleitet in der OEM-Codepage); CR und
//   Farbfolgen (ESC [ … m) fallen weg.
// - Pending liefert die angefangene Zeile ohne Zeilenende (etwa die Frage vor
//   einem Readln), ohne sie zu verbrauchen; TakePending nimmt sie heraus.
// - Flush gibt den Rest am Ende des Prozesses.

interface

uses
  System.SysUtils;

type
  TAtlasOutputLines = class
  private
    FPending: TBytes;
    FCodePage: Integer;
    function Decode(const ABytes: TBytes; AStart, ACount: Integer): string;
  public
    /// <summary>ACodePage: Codepage für Zeilen, die kein gültiges UTF-8 sind (GetOEMCP; 0 = nur UTF-8).</summary>
    constructor Create(ACodePage: Integer);
    /// <summary>Neue Bytes; liefert die Zeilen, die damit fertig sind.</summary>
    function Feed(const ABytes: TBytes; ACount: Integer): TArray<string>;
    /// <summary>Rest ohne Zeilenende am Schluss; leer, wenn nichts mehr da ist.</summary>
    function Flush: TArray<string>;
    /// <summary>Angefangene Zeile ohne Zeilenende, dekodiert; bleibt stehen, bis Feed oder Flush sie beenden.
    /// </summary>
    function Pending: string;
    /// <summary>Wie Pending, nimmt die angefangene Zeile aber heraus (eine abgeschnittene UTF-8-Folge am Ende
    /// bleibt): Was das Programm danach schreibt, beginnt eine neue Zeile. Für die Eingabe hinter einer Frage.
    /// </summary>
    function TakePending: string;
    /// <summary>Zeile ohne CR und ohne Farbfolgen.</summary>
    class function Clean(const ALine: string): string; static;
  end;

implementation

uses
  Atlas.Text.Encoding;

{ TAtlasOutputLines }

constructor TAtlasOutputLines.Create(ACodePage: Integer);
begin
  inherited Create;
  FCodePage := ACodePage;
end;

/// <summary>Letztes Zeichen der Steuerfolge, die bei AIndex mit ESC beginnt: CSI „ESC [ … Buchstabe“,
/// OSC „ESC ] … BEL“ bzw. „… ESC \“, sonst ESC mit einem Zeichen.</summary>
function EscapeEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  if (Result <= Length(AText)) and (AText[Result] = '[') then
  begin
    Inc(Result);
    while (Result <= Length(AText)) and not CharInSet(AText[Result], ['@'..'~']) do
    begin
      Inc(Result);
    end;
  end
  else if (Result <= Length(AText)) and (AText[Result] = ']') then
  begin
    while (Result <= Length(AText)) and (AText[Result] <> #7) and not ((AText[Result] = '\') and
      (AText[Result - 1] = #27)) do
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasOutputLines.Decode(const ABytes: TBytes; AStart, ACount: Integer): string;
var
  mEncoding: TEncoding;
begin
  if ACount <= 0 then
  begin
    Exit('');
  end;
  // Gültiges UTF-8 (ohne überlange Formen, Atlas.Text) geht vor der Codepage.
  if (FCodePage = 0) or TTextEncodingProbe.IsValidUtf8(Copy(ABytes, AStart, ACount), 0) then
  begin
    Exit(Clean(TEncoding.UTF8.GetString(ABytes, AStart, ACount)));
  end;
  try
    mEncoding := TEncoding.GetEncoding(FCodePage);
    try
      Result := Clean(mEncoding.GetString(ABytes, AStart, ACount));
    finally
      mEncoding.Free;
    end;
  except
    on Exception do
      Result := Clean(TEncoding.ANSI.GetString(ABytes, AStart, ACount));
  end;
end;

function TAtlasOutputLines.Feed(const ABytes: TBytes; ACount: Integer): TArray<string>;
var
  mData: TBytes;
  mIndex, mStart: Integer;
begin
  Result := nil;
  if ACount <= 0 then
  begin
    Exit;
  end;
  mData := FPending;
  SetLength(mData, Length(FPending) + ACount);
  Move(ABytes[0], mData[Length(FPending)], ACount);
  mStart := 0;
  for mIndex := 0 to High(mData) do
  begin
    if mData[mIndex] = 10 then
    begin
      Result := Result + [Decode(mData, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  FPending := Copy(mData, mStart, Length(mData) - mStart);
end;

function TAtlasOutputLines.Flush: TArray<string>;
begin
  Result := nil;
  if Length(FPending) > 0 then
  begin
    Result := [Decode(FPending, 0, Length(FPending))];
  end;
  FPending := nil;
end;

function TAtlasOutputLines.Pending: string;
var
  mCount: Integer;
begin
  // Eine am Ende abgeschnittene UTF-8-Folge wartet auf ihre Folgebytes und zählt noch nicht.
  mCount := Length(FPending) - TTextEncodingProbe.IncompleteUtf8Tail(FPending);
  Result := Decode(FPending, 0, mCount);
end;

function TAtlasOutputLines.TakePending: string;
var
  mTail: Integer;
begin
  Result := Pending;
  mTail := TTextEncodingProbe.IncompleteUtf8Tail(FPending);
  FPending := Copy(FPending, Length(FPending) - mTail, mTail);
end;

class function TAtlasOutputLines.Clean(const ALine: string): string;
var
  mIndex: Integer;
begin
  Result := ALine;
  if (Result <> '') and (Result[Length(Result)] = #13) then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
  // Steuerfolgen der Konsole (pwsh färbt Fehler).
  mIndex := Pos(#27, Result);
  while mIndex > 0 do
  begin
    Delete(Result, mIndex, EscapeEnd(Result, mIndex) - mIndex + 1);
    mIndex := Pos(#27, Result);
  end;
end;

end.
