unit Atlas.Core.Debug.ConsoleCapture;

// Ausgabe von Konsolenprogrammen andocken (#581), ohne VCL und Open Tools API:
// - TAtlasConsoleBuffer: Zeilen aus stdout und stderr (je eine
//   TAtlasOutputLines aus Base: UTF-8, sonst Ersatz-Codepage), dazu Eingaben
//   und Hinweise. Eine angefangene Zeile (die Frage vor einem Readln) zeigt das
//   Fenster als letzte Zeile; eine Eingabe schließt sie ab wie in einer
//   Konsole („Name: Marco“, die Frage in der Farbe der Ausgabe). Höchstens
//   AMaxLines Zeilen, ältere fallen weg (Dropped zählt sie).
// - TAtlasConsoleImage: Konsolen- oder Fensterprogramm aus dem PE-Kopf der EXE
//   (Subsystem 3 bzw. 2), unabhängig von {$APPTYPE} im Quelltext.
// - TAtlasConsoleLocations: Fundstelle „Datei.pas(12)“, „Datei.pas(12,5)“,
//   „Datei.pas:12“ oder „Datei.pas:12:5“ in einer Zeile, damit das Fenster sie
//   anklickbar macht.
// - TAtlasConsoleLaunch: Entscheidung vor dem Start, ob Atlas den Start
//   übernimmt (Einstellung an, Windows-Plattform, Konsolenprogramm, keine
//   Host-Anwendung, kein anderer Lauf im Fenster) oder die IDE startet.
// - TAtlasConsoleColors: stderr rot, Eingaben blau, Hinweise grau, jeweils
//   lesbar auf hellem und dunklem Thema.
// - TAtlasConsoleAttach: nächster Schritt nach dem Anhängen des Debuggers an
//   den angehalten gestarteten Prozess: warten, fortsetzen, sobald die IDE den
//   Prozess laufend oder angehalten führt, oder nach der Wartezeit trotzdem
//   fortsetzen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Style.Color,
  Atlas.Core.Processes.OutputLines;

type
  {$SCOPEDENUMS ON}
  /// <summary>Herkunft einer Zeile: Ausgabe (stdout), Fehler (stderr), Eingabe, Hinweis von Atlas.</summary>
  TAtlasConsoleStream = (Output, Error, Input, Note);
  /// <summary>Art der EXE nach dem PE-Kopf.</summary>
  TAtlasImageKind = (Unknown, Console, Gui);
  /// <summary>Wer startet: die IDE wie immer, Atlas mit Pipes, oder niemand (ein Lauf ist noch im Fenster).</summary>
  TAtlasConsoleLaunchChoice = (Ide, Capture, Busy);
  /// <summary>Nach dem Anhängen: weiter warten, fortsetzen, nach der Wartezeit trotzdem fortsetzen, Prozess weg.
  /// </summary>
  TAtlasConsoleAttachStep = (Wait, Resume, ResumeLate, Gone);
  {$SCOPEDENUMS OFF}

  TAtlasConsoleLine = record
    Text: string;
    Stream: TAtlasConsoleStream;
    /// <summary>Bei einer Eingabe: Länge der Frage des Programms davor (in der Farbe der Ausgabe).</summary>
    PromptLength: Integer;
  end;

  TAtlasConsoleBuffer = class
  public const
    cDefaultMaxLines = 20000;
  private
    FOutput: TAtlasOutputLines;
    FError: TAtlasOutputLines;
    FLines: TList<TAtlasConsoleLine>;
    FMaxLines: Integer;
    FDropped: Integer;
    FCodePage: Integer;
    procedure Append(AStream: TAtlasConsoleStream; const AText: string; APromptLength: Integer);
    procedure Trim;
    function LinesOf(AStream: TAtlasConsoleStream): TAtlasOutputLines;
  public
    /// <summary>ACodePage für Ausgaben, die kein UTF-8 sind (0 = nur UTF-8); AMaxLines ab 100.</summary>
    constructor Create(ACodePage, AMaxLines: Integer);
    destructor Destroy; override;
    /// <summary>Bytes aus stdout (Output) bzw. stderr (Error); Ergebnis: Zahl der neuen fertigen Zeilen.</summary>
    function Add(AStream: TAtlasConsoleStream; const ABytes: TBytes; ACount: Integer): Integer;
    /// <summary>Eingabe AText (ohne Zeilenende): schließt eine angefangene Zeile der Ausgabe ab.</summary>
    procedure AddInput(const AText: string);
    /// <summary>Hinweis von Atlas (Start, Ende mit Exit-Code).</summary>
    procedure AddNote(const AText: string);
    /// <summary>Prozess beendet: angefangene Zeilen werden fertige.</summary>
    procedure Finish;
    procedure Clear;
    function Count: Integer;
    function Line(AIndex: Integer): TAtlasConsoleLine;
    /// <summary>Angefangene Zeilen von stdout und stderr, ohne leere.</summary>
    function PendingLines: TArray<TAtlasConsoleLine>;
    /// <summary>Alle Zeilen als Text (Kopieren), angefangene am Ende.</summary>
    function Text: string;
    /// <summary>Wegen AMaxLines weggefallene Zeilen.</summary>
    property Dropped: Integer read FDropped;
  end;

  TAtlasConsoleImage = record
  public const
    cHeaderBytes = 4096;
  public
    /// <summary>Art nach dem Kopf einer EXE (die ersten Bytes reichen, cHeaderBytes).</summary>
    class function KindOf(const AHeader: TBytes): TAtlasImageKind; static;
    /// <summary>Art der Datei AFileName; Unknown, wenn sie fehlt oder kein PE ist.</summary>
    class function KindOfFile(const AFileName: string): TAtlasImageKind; static;
  end;

  /// <summary>Fundstelle in einer Zeile; Line und Column 1-basiert (Column 0 = keine), Start 1-basiert im Text.
  /// </summary>
  TAtlasConsoleLocation = record
    FileName: string;
    Line: Integer;
    Column: Integer;
    Start: Integer;
    Length: Integer;
  end;

  TAtlasConsoleLocations = record
  public
    /// <summary>Erste Fundstelle in AText; False ohne.</summary>
    class function Find(const AText: string; out ALocation: TAtlasConsoleLocation): Boolean; static;
  end;

  /// <summary>Was vor dem Start bekannt ist.</summary>
  TAtlasConsoleLaunchFacts = record
    Enabled: Boolean;
    /// <summary>Plattform des Projekts (Win32, Win64, Win64x, Linux64 …).</summary>
    Platform: string;
    Kind: TAtlasImageKind;
    /// <summary>Host-Anwendung aus den Startoptionen ('' = keine).</summary>
    Host: string;
    /// <summary>Ein Lauf im Fenster läuft noch.</summary>
    Busy: Boolean;
  end;

  TAtlasConsoleLaunch = record
  public
    class function Choose(const AFacts: TAtlasConsoleLaunchFacts): TAtlasConsoleLaunchChoice; static;
    /// <summary>Plattform, deren Programme Atlas selbst starten kann (Windows auf diesem Rechner).</summary>
    class function LocalPlatform(const APlatform: string): Boolean; static;
    /// <summary>Exit-Code als Text: dezimal, ab $80000000 (NTSTATUS, etwa Zugriffsverletzung) auch hexadezimal.
    /// </summary>
    class function ExitCodeText(ACode: Cardinal): string; static;
  end;

  /// <summary>Farben der Zeilen, lesbar auf hellem und dunklem Hintergrund.</summary>
  TAtlasConsoleColors = record
  public
    /// <summary>Farbe für AStream auf ABackground; ADefault ist die Schrift der Liste (Ausgabe).</summary>
    class function ForStream(AStream: TAtlasConsoleStream; ABackground, ADefault: TAtlasColor): TAtlasColor; static;
  end;

  /// <summary>Stand nach dem Anhängen.</summary>
  TAtlasConsoleAttachFacts = record
    ElapsedMs: UInt64;
    TimeoutMs: UInt64;
    /// <summary>Der Debugger der IDE führt den Prozess und er läuft oder steht (Anhängen fertig).</summary>
    IdeReady: Boolean;
    /// <summary>Der Prozess lebt noch.</summary>
    Alive: Boolean;
  end;

  TAtlasConsoleAttach = record
  public
    class function Next(const AFacts: TAtlasConsoleAttachFacts): TAtlasConsoleAttachStep; static;
  end;

implementation

uses
  System.Classes;

const
  cMinLines = 100;
  cDosMagic = $5A4D;
  cPeOffsetAt = $3C;
  cPeMagic = $00004550;
  cOptionalHeaderOffset = 24;
  cSubsystemOffset = 68;
  cSubsystemGui = 2;
  cSubsystemConsole = 3;
  cFirstNtStatus = Cardinal($80000000);
  cMaxExtension = 8;
  cHexDigits = 8;
  // Farben je Strom auf dunklem und hellem Grund ($00BBGGRR).
  cErrorOnDark: TAtlasColor = $007878FF;
  cErrorOnLight: TAtlasColor = $000000BE;
  cInputOnDark: TAtlasColor = $00FFB478;
  cInputOnLight: TAtlasColor = $00BE5000;

{ TAtlasConsoleBuffer }

constructor TAtlasConsoleBuffer.Create(ACodePage, AMaxLines: Integer);
begin
  inherited Create;
  FCodePage := ACodePage;
  FMaxLines := AMaxLines;
  if FMaxLines < cMinLines then
  begin
    FMaxLines := cMinLines;
  end;
  FOutput := TAtlasOutputLines.Create(FCodePage);
  FError := TAtlasOutputLines.Create(FCodePage);
  FLines := TList<TAtlasConsoleLine>.Create;
end;

destructor TAtlasConsoleBuffer.Destroy;
begin
  FLines.Free;
  FError.Free;
  FOutput.Free;
  inherited Destroy;
end;

function TAtlasConsoleBuffer.LinesOf(AStream: TAtlasConsoleStream): TAtlasOutputLines;
begin
  Result := FOutput;
  if AStream = TAtlasConsoleStream.Error then
  begin
    Result := FError;
  end;
end;

procedure TAtlasConsoleBuffer.Append(AStream: TAtlasConsoleStream; const AText: string; APromptLength: Integer);
var
  mLine: TAtlasConsoleLine;
begin
  mLine := Default(TAtlasConsoleLine);
  mLine.Text := AText;
  mLine.Stream := AStream;
  mLine.PromptLength := APromptLength;
  FLines.Add(mLine);
end;

procedure TAtlasConsoleBuffer.Trim;
var
  mExcess: Integer;
begin
  if FLines.Count <= FMaxLines then
  begin
    Exit;
  end;
  // Ein Zehntel mehr als nötig auf einmal: Löschen am Anfang verschiebt die ganze Liste.
  mExcess := FLines.Count - FMaxLines + FMaxLines div 10;
  if mExcess > FLines.Count then
  begin
    mExcess := FLines.Count;
  end;
  FLines.DeleteRange(0, mExcess);
  Inc(FDropped, mExcess);
end;

function TAtlasConsoleBuffer.Add(AStream: TAtlasConsoleStream; const ABytes: TBytes; ACount: Integer): Integer;
var
  mText: string;
begin
  Result := 0;
  if not (AStream in [TAtlasConsoleStream.Output, TAtlasConsoleStream.Error]) then
  begin
    Exit;
  end;
  for mText in LinesOf(AStream).Feed(ABytes, ACount) do
  begin
    Append(AStream, mText, 0);
    Inc(Result);
  end;
  Trim;
end;

procedure TAtlasConsoleBuffer.AddInput(const AText: string);
var
  mPrompt: string;
begin
  // Die Frage steht in stdout; eine Konsole zeigt die Eingabe dahinter auf derselben Zeile.
  mPrompt := FOutput.TakePending;
  Append(TAtlasConsoleStream.Input, mPrompt + AText, Length(mPrompt));
  Trim;
end;

procedure TAtlasConsoleBuffer.AddNote(const AText: string);
begin
  Append(TAtlasConsoleStream.Note, AText, 0);
  Trim;
end;

procedure TAtlasConsoleBuffer.Finish;
var
  mText: string;
begin
  for mText in FOutput.Flush do
  begin
    Append(TAtlasConsoleStream.Output, mText, 0);
  end;
  for mText in FError.Flush do
  begin
    Append(TAtlasConsoleStream.Error, mText, 0);
  end;
  Trim;
end;

procedure TAtlasConsoleBuffer.Clear;
begin
  FLines.Clear;
  FDropped := 0;
  // Angefangene Zeilen gehören zum gelöschten Stand.
  FOutput.TakePending;
  FError.TakePending;
end;

function TAtlasConsoleBuffer.Count: Integer;
begin
  Result := FLines.Count;
end;

function TAtlasConsoleBuffer.Line(AIndex: Integer): TAtlasConsoleLine;
begin
  Result := FLines[AIndex];
end;

function TAtlasConsoleBuffer.PendingLines: TArray<TAtlasConsoleLine>;
var
  mLine: TAtlasConsoleLine;
  mStream: TAtlasConsoleStream;
  mCount: Integer;
begin
  Result := nil;
  // Höchstens eine offene Zeile je Strom.
  SetLength(Result, Ord(High(TAtlasConsoleStream)) + 1);
  mCount := 0;
  for mStream in [TAtlasConsoleStream.Output, TAtlasConsoleStream.Error] do
  begin
    mLine := Default(TAtlasConsoleLine);
    mLine.Text := LinesOf(mStream).Pending;
    mLine.Stream := mStream;
    if mLine.Text <> '' then
    begin
      Result[mCount] := mLine;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

function TAtlasConsoleBuffer.Text: string;
var
  mBuilder: TStringBuilder;
  mLine: TAtlasConsoleLine;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mLine in FLines do
    begin
      mBuilder.Append(mLine.Text).Append(sLineBreak);
    end;
    for mLine in PendingLines do
    begin
      mBuilder.Append(mLine.Text).Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TAtlasConsoleImage }

// PE-Köpfe sind little-endian wie Win32 und Win64.
function ReadWord(const ABytes: TBytes; AOffset: Integer): Cardinal;
var
  mValue: Word;
begin
  mValue := 0;
  Move(ABytes[AOffset], mValue, SizeOf(mValue));
  Result := mValue;
end;

function ReadLong(const ABytes: TBytes; AOffset: Integer): Cardinal;
begin
  Result := 0;
  Move(ABytes[AOffset], Result, SizeOf(Result));
end;

class function TAtlasConsoleImage.KindOf(const AHeader: TBytes): TAtlasImageKind;
var
  mPe: Int64;
  mSubsystemAt: Int64;
begin
  Result := TAtlasImageKind.Unknown;
  if (Length(AHeader) < cPeOffsetAt + SizeOf(Cardinal)) or (ReadWord(AHeader, 0) <> cDosMagic) then
  begin
    Exit;
  end;
  mPe := ReadLong(AHeader, cPeOffsetAt);
  // Das Subsystem steht im optionalen Kopf an derselben Stelle für PE32 (Win32) und PE32+ (Win64).
  mSubsystemAt := mPe + cOptionalHeaderOffset + cSubsystemOffset;
  if (mSubsystemAt + 2 > Length(AHeader)) or (ReadLong(AHeader, Integer(mPe)) <> cPeMagic) then
  begin
    Exit;
  end;
  case ReadWord(AHeader, Integer(mSubsystemAt)) of
    cSubsystemConsole:
      Result := TAtlasImageKind.Console;
    cSubsystemGui:
      Result := TAtlasImageKind.Gui;
  end;
end;

class function TAtlasConsoleImage.KindOfFile(const AFileName: string): TAtlasImageKind;
var
  mStream: TFileStream;
  mHeader: TBytes;
  mRead: Integer;
begin
  Result := TAtlasImageKind.Unknown;
  if (AFileName = '') or not FileExists(AFileName) then
  begin
    Exit;
  end;
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(mHeader, cHeaderBytes);
      mRead := mStream.Read(mHeader[0], cHeaderBytes);
      SetLength(mHeader, mRead);
    finally
      mStream.Free;
    end;
  except
    // Gesperrt oder nicht lesbar: Die IDE startet wie immer.
    on EFOpenError do
      Exit;
  end;
  Result := KindOf(mHeader);
end;

{ TAtlasConsoleLocations }

function IsDigit(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['0'..'9']);
end;

function IsLetter(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['a'..'z', 'A'..'Z']);
end;

/// <summary>Zeichen, die einen Dateinamen in einer Zeile begrenzen.</summary>
function IsPathStop(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, [' ', #9, '"', '''', '<', '>', '|', '(', ')', '[', ']', ',', ';', '=']);
end;

/// <summary>Doppelpunkt bei AColon gehört zu einem Laufwerk: ein Buchstabe davor am Anfang eines Worts, danach
/// „\“ oder „/“.</summary>
function IsDriveColon(const AText: string; AColon: Integer): Boolean;
begin
  Result := (AColon >= 2) and (AColon < Length(AText)) and IsLetter(AText[AColon - 1]) and
    ((AColon = 2) or IsPathStop(AText[AColon - 2])) and CharInSet(AText[AColon + 1], ['\', '/']);
end;

/// <summary>Ziffern ab AIndex; AValue ihr Wert, Ergebnis der Index dahinter (AIndex, wenn keine).</summary>
function ReadNumber(const AText: string; AIndex: Integer; out AValue: Integer): Integer;
begin
  AValue := 0;
  Result := AIndex;
  while (Result <= Length(AText)) and IsDigit(AText[Result]) and (AValue < MaxInt div 10) do
  begin
    AValue := AValue * 10 + Ord(AText[Result]) - Ord('0');
    Inc(Result);
  end;
end;

/// <summary>Anfang des Dateinamens, der bei AEnd endet; 0, wenn davor keine Endung „.abc“ steht.</summary>
function PathStart(const AText: string; AEnd: Integer): Integer;
var
  mDot: Integer;
begin
  Result := 0;
  mDot := AEnd;
  while (mDot > 0) and IsLetter(AText[mDot]) and (AEnd - mDot < cMaxExtension) do
  begin
    Dec(mDot);
  end;
  if (mDot = AEnd) or (mDot < 2) or (AText[mDot] <> '.') then
  begin
    Exit;
  end;
  Result := mDot;
  // Doppelpunkt nur als Laufwerk („C:\“), sonst trennt er wie ein Leerzeichen.
  while (Result > 1) and not IsPathStop(AText[Result - 1]) and
    ((AText[Result - 1] <> ':') or IsDriveColon(AText, Result - 1)) do
  begin
    Dec(Result);
  end;
  // Kein Name vor der Endung, oder eine Adresse („http://host.de:8080“): keine Datei.
  if (Result = mDot) or ((Result > 1) and (AText[Result - 1] = ':')) then
  begin
    Result := 0;
  end;
end;

/// <summary>„(12)“, „(12,5)“ bzw. „(12:5)“ ab AIndex (auf der Klammer); Ende hinter der Klammer, 0 ohne.</summary>
function ReadParenthesized(const AText: string; AIndex: Integer; var ALocation: TAtlasConsoleLocation): Integer;
var
  mNext: Integer;
begin
  Result := 0;
  mNext := ReadNumber(AText, AIndex + 1, ALocation.Line);
  if mNext = AIndex + 1 then
  begin
    Exit;
  end;
  if (mNext <= Length(AText)) and CharInSet(AText[mNext], [',', ':']) then
  begin
    mNext := ReadNumber(AText, mNext + 1, ALocation.Column);
  end;
  if (mNext <= Length(AText)) and (AText[mNext] = ')') then
  begin
    Result := mNext + 1;
  end;
end;

/// <summary>„:12“ bzw. „:12:5“ ab AIndex (auf dem Doppelpunkt); Ende dahinter, 0 ohne.</summary>
function ReadColon(const AText: string; AIndex: Integer; var ALocation: TAtlasConsoleLocation): Integer;
var
  mNext, mColumnEnd: Integer;
begin
  Result := 0;
  mNext := ReadNumber(AText, AIndex + 1, ALocation.Line);
  if mNext = AIndex + 1 then
  begin
    Exit;
  end;
  if (mNext < Length(AText)) and (AText[mNext] = ':') then
  begin
    mColumnEnd := ReadNumber(AText, mNext + 1, ALocation.Column);
    if mColumnEnd > mNext + 1 then
    begin
      mNext := mColumnEnd;
    end;
  end;
  Result := mNext;
end;

class function TAtlasConsoleLocations.Find(const AText: string; out ALocation: TAtlasConsoleLocation): Boolean;
var
  mIndex, mStart, mEnd: Integer;
begin
  for mIndex := 2 to Length(AText) - 1 do
  begin
    if not CharInSet(AText[mIndex], ['(', ':']) or not IsDigit(AText[mIndex + 1]) then
    begin
      Continue;
    end;
    mStart := PathStart(AText, mIndex - 1);
    if mStart = 0 then
    begin
      Continue;
    end;
    ALocation := Default(TAtlasConsoleLocation);
    if AText[mIndex] = '(' then
    begin
      mEnd := ReadParenthesized(AText, mIndex, ALocation);
    end
    else
    begin
      mEnd := ReadColon(AText, mIndex, ALocation);
    end;
    if (mEnd = 0) or (ALocation.Line < 1) then
    begin
      Continue;
    end;
    ALocation.FileName := Copy(AText, mStart, mIndex - mStart);
    ALocation.Start := mStart;
    ALocation.Length := mEnd - mStart;
    Exit(True);
  end;
  ALocation := Default(TAtlasConsoleLocation);
  Result := False;
end;

{ TAtlasConsoleLaunch }

class function TAtlasConsoleLaunch.LocalPlatform(const APlatform: string): Boolean;
begin
  // Win64x ist die Win64-Plattform mit Clang (Delphi 12.2 und neuer).
  Result := SameText(APlatform, 'Win32') or SameText(APlatform, 'Win64') or SameText(APlatform, 'Win64x');
end;

class function TAtlasConsoleLaunch.Choose(const AFacts: TAtlasConsoleLaunchFacts): TAtlasConsoleLaunchChoice;
begin
  Result := TAtlasConsoleLaunchChoice.Ide;
  if not AFacts.Enabled or (AFacts.Kind <> TAtlasImageKind.Console) or not LocalPlatform(AFacts.Platform) or
    (AFacts.Host <> '') then
  begin
    Exit;
  end;
  Result := TAtlasConsoleLaunchChoice.Capture;
  if AFacts.Busy then
  begin
    Result := TAtlasConsoleLaunchChoice.Busy;
  end;
end;

class function TAtlasConsoleLaunch.ExitCodeText(ACode: Cardinal): string;
begin
  Result := IntToStr(Integer(ACode));
  if ACode >= cFirstNtStatus then
  begin
    Result := Result + ' ($' + IntToHex(ACode, cHexDigits) + ')';
  end;
end;

{ TAtlasConsoleColors }

class function TAtlasConsoleColors.ForStream(AStream: TAtlasConsoleStream;
  ABackground, ADefault: TAtlasColor): TAtlasColor;
const
  cNoteAlpha = 0.55;
var
  mDark: Boolean;
begin
  mDark := TAtlasColorMath.IsDark(ABackground);
  case AStream of
    TAtlasConsoleStream.Error:
      if mDark then
      begin
        Result := cErrorOnDark;
      end
      else
      begin
        Result := cErrorOnLight;
      end;
    TAtlasConsoleStream.Input:
      if mDark then
      begin
        Result := cInputOnDark;
      end
      else
      begin
        Result := cInputOnLight;
      end;
    TAtlasConsoleStream.Note:
      Result := TAtlasColorMath.Mix(ADefault, ABackground, cNoteAlpha);
  else
    Result := ADefault;
  end;
end;

{ TAtlasConsoleAttach }

class function TAtlasConsoleAttach.Next(const AFacts: TAtlasConsoleAttachFacts): TAtlasConsoleAttachStep;
begin
  if not AFacts.Alive then
  begin
    Exit(TAtlasConsoleAttachStep.Gone);
  end;
  if AFacts.IdeReady then
  begin
    Exit(TAtlasConsoleAttachStep.Resume);
  end;
  Result := TAtlasConsoleAttachStep.Wait;
  if AFacts.ElapsedMs >= AFacts.TimeoutMs then
  begin
    Result := TAtlasConsoleAttachStep.ResumeLate;
  end;
end;

end.
