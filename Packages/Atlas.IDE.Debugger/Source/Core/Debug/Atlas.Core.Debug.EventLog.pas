unit Atlas.Core.Debug.EventLog;

// Ereignisprotokoll beim Debuggen (#580), ohne IDE und VCL:
// - TAtlasEventLog hält die Einträge einer Sitzung (Zeit relativ zum Start,
//   Art, Thread, Text), begrenzt auf Limit Einträge (älteste fallen weg), und
//   schreibt sie als Text zum Speichern.
// - Classify ordnet eine Zeile aus dem Ereignisprotokoll der IDE einer Art zu
//   (deutsche und englische Präfixe wie „Debug Output:“ / „Debug-Ausgabe:“),
//   entfernt den angehängten Prozess und liest die Thread-Kennung.
// - TAtlasEventFilter: Text (jedes Wort muss vorkommen) oder regulärer
//   Ausdruck in Schrägstrichen („/FEHLER|WARN/“), dazu die Arten. Derselbe
//   Text ist der gespeicherte Filter je Projekt.
// - TAtlasEventColors: Farben nach Muster aus debug.eventLogColors
//   („[FEHLER]=#D13438; [WARN]=#C19C00“), erstes passendes Muster gewinnt.
// - TAtlasEventJump: Sprungziel einer Zeile, „Datei.pas(123)“,
//   „Datei.pas:123“ oder „Unit.Routine“.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Style.Color;

type
  {$SCOPEDENUMS ON}
  /// <summary>Art eines Eintrags.</summary>
  TAtlasEventKind = (Output, Breakpoint, Module, Thread, Process, Logpoint, Other);
  /// <summary>Art eines Sprungziels.</summary>
  TAtlasEventJumpKind = (None, FileLine, Symbol);
  {$SCOPEDENUMS OFF}
  TAtlasEventKinds = set of TAtlasEventKind;

  TAtlasEventEntry = record
    /// <summary>Millisekunden seit dem Start der Sitzung.</summary>
    ElapsedMs: Int64;
    Kind: TAtlasEventKind;
    /// <summary>Thread-Kennung als Text; '' ohne.</summary>
    Thread: string;
    Text: string;
    class function Create(AElapsedMs: Int64; AKind: TAtlasEventKind; const AThread, AText: string): TAtlasEventEntry;
      static;
    /// <summary>Zeit relativ zum Start, z. B. "0:12.345" bzw. "1:02:03.004".</summary>
    function TimeText: string;
  end;

  TAtlasEventFilter = record
    /// <summary>Filtertext wie eingegeben: Wörter oder "/Ausdruck/".</summary>
    Text: string;
    Kinds: TAtlasEventKinds;
    class function Create(const AText: string; AKinds: TAtlasEventKinds): TAtlasEventFilter; static;
    /// <summary>Regulärer Ausdruck in Schrägstrichen?</summary>
    function IsRegex: Boolean;
    /// <summary>Ausdruck ohne Schrägstriche; '' ohne Ausdruck.</summary>
    function Pattern: string;
    /// <summary>Lässt sich der Ausdruck übersetzen? Ohne Ausdruck immer True.</summary>
    function Valid: Boolean;
  end;

  TAtlasEventColorRule = record
    Pattern: string;
    Color: TAtlasColor;
  end;

  /// <summary>Farben nach Muster; Vorgabe cDefaultEventLogColors (Atlas.Core.Settings.Plugin.Debug).</summary>
  TAtlasEventColors = record
    Rules: TArray<TAtlasEventColorRule>;
    /// <summary>Liest "Muster=Farbe; …"; Farbe "#RRGGBB" oder red/rot, yellow/gelb, green/grün, blue/blau, orange,
    /// gray/grau. Ungültige Einträge fallen weg.</summary>
    class function Parse(const AText: string): TAtlasEventColors; static;
    /// <summary>Einheitliche Schreibweise ("Muster=#RRGGBB; …"); Ungültiges fällt weg.</summary>
    class function Normalize(const AText: string): string; static;
    /// <summary>Farbe des ersten Musters, das in AText vorkommt (Groß-/Kleinschreibung egal).</summary>
    function TryColorOf(const AText: string; out AColor: TAtlasColor): Boolean;
    function ToText: string;
  end;

  TAtlasEventJump = record
    Kind: TAtlasEventJumpKind;
    /// <summary>Datei wie in der Zeile (relativ oder vollständig).</summary>
    FileName: string;
    /// <summary>Zeile ab 1.</summary>
    Line: Integer;
    /// <summary>Bei Symbol: "Unit.Routine" bzw. "Klasse.Methode".</summary>
    Symbol: string;
    /// <summary>Erstes Sprungziel in AText; Datei mit Zeile vor Symbol.</summary>
    class function Find(const AText: string): TAtlasEventJump; static;
  end;

  TAtlasEventLog = class
  public const
    cDefaultLimit = 20000;
    /// <summary>Stabile Namen der Arten (Textdatei, Tests).</summary>
    cKindNames: array[TAtlasEventKind] of string = ('output', 'breakpoint', 'module', 'thread', 'process',
      'logpoint', 'other');
    cAllKinds = [Low(TAtlasEventKind)..High(TAtlasEventKind)];
  private
    FEntries: TList<TAtlasEventEntry>;
    FLimit: Integer;
    FDropped: Integer;
    function GetItem(AIndex: Integer): TAtlasEventEntry;
  public
    /// <summary>Höchstens cDefaultLimit Einträge.</summary>
    constructor Create; overload;
    constructor Create(ALimit: Integer); overload;
    destructor Destroy; override;
    procedure Add(const AEntry: TAtlasEventEntry);
    procedure Clear;
    function Count: Integer;
    /// <summary>Indizes der Einträge, die AFilter erfüllen, in Reihenfolge; alle bei ungültigem Ausdruck.</summary>
    function Filter(const AFilter: TAtlasEventFilter): TArray<Integer>;
    /// <summary>Alle Einträge als Text: Zeit, Art, Thread, Text durch Tabulator getrennt, Zeilen mit CRLF.</summary>
    function ToText: string;
    /// <summary>Art einer Zeile aus dem Ereignisprotokoll der IDE; AText ohne Präfix und angehängten Prozess,
    /// AThread die Thread-Kennung ('' ohne).</summary>
    class function Classify(const ALine: string; out AText, AThread: string): TAtlasEventKind; static;
    property Items[AIndex: Integer]: TAtlasEventEntry read GetItem; default;
    /// <summary>Wegen Limit verworfene Einträge seit Clear.</summary>
    property Dropped: Integer read FDropped;
    property Limit: Integer read FLimit;
  end;

implementation

uses
  System.RegularExpressions;

const
  cMsPerSecond = 1000;
  cSecondsPerMinute = 60;
  cMsPerMinute = cMsPerSecond * cSecondsPerMinute;
  cMsPerHour = cMsPerMinute * 60;
  /// <summary>Kürzester Ausdruck in Schrägstrichen: "/x/".</summary>
  cMinRegexLength = 3;
  /// <summary>"#RRGGBB".</summary>
  cHexColorLength = 7;
  /// <summary>Kleinstes Limit; darunter verwirft Add zu oft.</summary>
  cMinLimit = 10;
  /// <summary>Über dem Limit fällt ein Zehntel auf einmal weg.</summary>
  cDropDivisor = 10;
  /// <summary>Von der IDE an Ausgaben angehängter Prozess: "… Process Demo.exe (1234)".</summary>
  cProcessSuffix = '\s+(?:Process|Prozess)\s+\S+\s+\(\d+\)\s*$';
  cThreadId = 'Thread[ -]?ID:?\s*(\d+)';

{ TAtlasEventEntry }

class function TAtlasEventEntry.Create(AElapsedMs: Int64; AKind: TAtlasEventKind;
  const AThread, AText: string): TAtlasEventEntry;
begin
  Result.ElapsedMs := AElapsedMs;
  Result.Kind := AKind;
  Result.Thread := AThread;
  Result.Text := AText;
end;

function TAtlasEventEntry.TimeText: string;
var
  mMs, mSeconds, mMinutes, mHours: Int64;
begin
  mMs := ElapsedMs;
  if mMs < 0 then
  begin
    mMs := 0;
  end;
  mSeconds := (mMs div cMsPerSecond) mod cSecondsPerMinute;
  mMinutes := (mMs div cMsPerMinute) mod cSecondsPerMinute;
  mHours := mMs div cMsPerHour;
  if mHours > 0 then
  begin
    Result := Format('%d:%.2d:%.2d.%.3d', [mHours, mMinutes, mSeconds, mMs mod cMsPerSecond]);
  end
  else
  begin
    Result := Format('%d:%.2d.%.3d', [mMinutes, mSeconds, mMs mod cMsPerSecond]);
  end;
end;

{ TAtlasEventFilter }

class function TAtlasEventFilter.Create(const AText: string; AKinds: TAtlasEventKinds): TAtlasEventFilter;
begin
  Result.Text := AText;
  Result.Kinds := AKinds;
end;

function TAtlasEventFilter.IsRegex: Boolean;
var
  mText: string;
begin
  mText := Trim(Text);
  Result := (Length(mText) >= cMinRegexLength) and (mText[1] = '/') and (mText[Length(mText)] = '/');
end;

function TAtlasEventFilter.Pattern: string;
var
  mText: string;
begin
  Result := '';
  if IsRegex then
  begin
    mText := Trim(Text);
    Result := Copy(mText, 2, Length(mText) - 2);
  end;
end;

function TAtlasEventFilter.Valid: Boolean;
begin
  Result := True;
  if not IsRegex then
  begin
    Exit;
  end;
  try
    TRegEx.Create(Pattern, [roIgnoreCase]).IsMatch('');
  except
    on Exception do
      Result := False;
  end;
end;

{ TAtlasEventColors }

type
  TNamedColor = record
    Name: string;
    Hex: string;
  end;

const
  cNamedColors: array[0..10] of TNamedColor = (
    (Name: 'red'; Hex: '#D13438'), (Name: 'rot'; Hex: '#D13438'),
    (Name: 'yellow'; Hex: '#C19C00'), (Name: 'gelb'; Hex: '#C19C00'),
    (Name: 'green'; Hex: '#107C10'), (Name: 'grün'; Hex: '#107C10'),
    (Name: 'blue'; Hex: '#0063B1'), (Name: 'blau'; Hex: '#0063B1'),
    (Name: 'orange'; Hex: '#CA5010'),
    (Name: 'gray'; Hex: '#7A7574'), (Name: 'grau'; Hex: '#7A7574'));

function TryColorText(const AText: string; out AColor: TAtlasColor): Boolean;
var
  mText: string;
  mValue: Integer;
  mNamed: TNamedColor;
begin
  AColor := 0;
  mText := Trim(AText);
  for mNamed in cNamedColors do
  begin
    if SameText(mText, mNamed.Name) then
    begin
      mText := mNamed.Hex;
    end;
  end;
  Result := (Length(mText) = cHexColorLength) and (mText[1] = '#') and
    TryStrToInt('$' + Copy(mText, 2, cHexColorLength - 1), mValue);
  if Result then
  begin
    AColor := TAtlasColorMath.FromHex(mText);
  end;
end;

class function TAtlasEventColors.Parse(const AText: string): TAtlasEventColors;
var
  mPart: string;
  mSplit: Integer;
  mRule: TAtlasEventColorRule;
begin
  Result := Default(TAtlasEventColors);
  for mPart in AText.Split([';', #13, #10]) do
  begin
    // Das letzte "=" trennt: Muster dürfen selbst "=" enthalten.
    mSplit := mPart.LastIndexOf('=');
    if mSplit < 0 then
    begin
      Continue;
    end;
    mRule.Pattern := Trim(mPart.Substring(0, mSplit));
    if (mRule.Pattern <> '') and TryColorText(mPart.Substring(mSplit + 1), mRule.Color) then
    begin
      Result.Rules := Result.Rules + [mRule];
    end;
  end;
end;

class function TAtlasEventColors.Normalize(const AText: string): string;
begin
  Result := Parse(AText).ToText;
end;

function TAtlasEventColors.ToText: string;
var
  mRule: TAtlasEventColorRule;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mRule in Rules do
  begin
    mParts := mParts + [mRule.Pattern + '=' + TAtlasColorMath.ToHex(mRule.Color)];
  end;
  Result := string.Join('; ', mParts);
end;

function TAtlasEventColors.TryColorOf(const AText: string; out AColor: TAtlasColor): Boolean;
var
  mRule: TAtlasEventColorRule;
  mText: string;
begin
  AColor := 0;
  mText := AnsiUpperCase(AText);
  for mRule in Rules do
  begin
    if Pos(AnsiUpperCase(mRule.Pattern), mText) > 0 then
    begin
      AColor := mRule.Color;
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasEventJump }

const
  cSourceExt = '(?:pas|dpr|dpk|inc|pp|lpr)';
  cPathChars = '[^\s"''<>|:*?()\[\]]*';
  // Datei.pas(123) oder Datei.pas(123,4), auch mit Laufwerk.
  cFileParen = '((?:[A-Za-z]:[\\/])?' + cPathChars + '\.' + cSourceExt + ')\((\d+)(?:,\s*\d+)?\)';
  // Datei.pas:123
  cFileColon = '((?:[A-Za-z]:[\\/])?' + cPathChars + '\.' + cSourceExt + '):(\d+)';
  cSymbol = '(?<![\w.])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+)';
  // Endungen, die kein Symbol sind.
  cNoSymbolExt: array[0..14] of string = ('exe', 'dll', 'bpl', 'dcp', 'dcu', 'pas', 'dpr', 'dpk', 'inc', 'txt',
    'log', 'ini', 'json', 'xml', 'com');

function NotSymbolExt(const ASymbol: string): Boolean;
var
  mExt, mName: string;
begin
  mExt := ASymbol.Substring(ASymbol.LastIndexOf('.') + 1);
  for mName in cNoSymbolExt do
  begin
    if SameText(mExt, mName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasEventJump.Find(const AText: string): TAtlasEventJump;
var
  mMatch: TMatch;
  mPattern: string;
begin
  Result := Default(TAtlasEventJump);
  for mPattern in TArray<string>.Create(cFileParen, cFileColon) do
  begin
    mMatch := TRegEx.Match(AText, mPattern, [roIgnoreCase]);
    if mMatch.Success and (mMatch.Groups[1].Value <> '') then
    begin
      Result.Kind := TAtlasEventJumpKind.FileLine;
      Result.FileName := mMatch.Groups[1].Value;
      Result.Line := StrToIntDef(mMatch.Groups[2].Value, 1);
      if Result.Line < 1 then
      begin
        Result.Line := 1;
      end;
      Exit;
    end;
  end;
  mMatch := TRegEx.Match(AText, cSymbol);
  while mMatch.Success do
  begin
    if not NotSymbolExt(mMatch.Groups[1].Value) then
    begin
      Result.Kind := TAtlasEventJumpKind.Symbol;
      Result.Symbol := mMatch.Groups[1].Value;
      Exit;
    end;
    mMatch := mMatch.NextMatch;
  end;
end;

{ TAtlasEventLog }

constructor TAtlasEventLog.Create;
begin
  Create(cDefaultLimit);
end;

constructor TAtlasEventLog.Create(ALimit: Integer);
begin
  inherited Create;
  FEntries := TList<TAtlasEventEntry>.Create;
  FLimit := ALimit;
  if FLimit < cMinLimit then
  begin
    FLimit := cMinLimit;
  end;
end;

destructor TAtlasEventLog.Destroy;
begin
  FreeAndNil(FEntries);
  inherited Destroy;
end;

function TAtlasEventLog.GetItem(AIndex: Integer): TAtlasEventEntry;
begin
  Result := FEntries[AIndex];
end;

procedure TAtlasEventLog.Add(const AEntry: TAtlasEventEntry);
var
  mDrop: Integer;
begin
  if FEntries.Count >= FLimit then
  begin
    // Ein Zehntel auf einmal: nicht bei jedem Eintrag die ganze Liste verschieben.
    mDrop := FLimit div cDropDivisor;
    FEntries.DeleteRange(0, mDrop);
    Inc(FDropped, mDrop);
  end;
  FEntries.Add(AEntry);
end;

procedure TAtlasEventLog.Clear;
begin
  FEntries.Clear;
  FDropped := 0;
end;

function TAtlasEventLog.Count: Integer;
begin
  Result := FEntries.Count;
end;

/// <summary>Wörter des Filters in Großbuchstaben.</summary>
function FilterWords(const AText: string): TArray<string>;
var
  mWord: string;
begin
  Result := nil;
  for mWord in AnsiUpperCase(AText).Split([' ', #9]) do
  begin
    if mWord <> '' then
    begin
      Result := Result + [mWord];
    end;
  end;
end;

function HasAllWords(const AText: string; const AWords: TArray<string>): Boolean;
var
  mText, mWord: string;
begin
  mText := AnsiUpperCase(AText);
  for mWord in AWords do
  begin
    if Pos(mWord, mText) = 0 then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TAtlasEventLog.Filter(const AFilter: TAtlasEventFilter): TArray<Integer>;
var
  mIndex: Integer;
  mEntry: TAtlasEventEntry;
  mRegex: TRegEx;
  mUseRegex: Boolean;
  mWords: TArray<string>;
  mHit: Boolean;
begin
  Result := nil;
  mUseRegex := AFilter.IsRegex and AFilter.Valid;
  mWords := nil;
  mRegex := Default(TRegEx);
  if mUseRegex then
  begin
    mRegex := TRegEx.Create(AFilter.Pattern, [roIgnoreCase]);
  end
  else if not AFilter.IsRegex then
  begin
    mWords := FilterWords(AFilter.Text);
  end;
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    mEntry := FEntries[mIndex];
    if not (mEntry.Kind in AFilter.Kinds) then
    begin
      Continue;
    end;
    if mUseRegex then
    begin
      mHit := mRegex.IsMatch(mEntry.Text);
    end
    else
    begin
      mHit := HasAllWords(mEntry.Text, mWords);
    end;
    if mHit then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function TAtlasEventLog.ToText: string;
var
  mBuilder: TStringBuilder;
  mEntry: TAtlasEventEntry;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mEntry in FEntries do
    begin
      mBuilder.Append(mEntry.TimeText).Append(#9).Append(cKindNames[mEntry.Kind]).Append(#9).Append(mEntry.Thread)
        .Append(#9).Append(mEntry.Text.Replace(#13#10, ' ').Replace(#13, ' ').Replace(#10, ' ')).Append(#13#10);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

type
  TKindWord = record
    Word: string;
    Kind: TAtlasEventKind;
  end;

const
  // Reihenfolge zählt: „Breakpoint Message“ vor „Message“, „Thread“ vor „Process“ (Thread-Zeilen nennen den Prozess
  // nicht im Präfix, aber sicher ist sicher).
  cKindWords: array[0..10] of TKindWord = (
    (Word: 'BREAKPOINT'; Kind: TAtlasEventKind.Breakpoint), (Word: 'HALTEPUNKT'; Kind: TAtlasEventKind.Breakpoint),
    (Word: 'LOGPOINT'; Kind: TAtlasEventKind.Logpoint), (Word: 'LOGPUNKT'; Kind: TAtlasEventKind.Logpoint),
    (Word: 'MODUL'; Kind: TAtlasEventKind.Module),
    (Word: 'THREAD'; Kind: TAtlasEventKind.Thread),
    (Word: 'PROCESS'; Kind: TAtlasEventKind.Process), (Word: 'PROZESS'; Kind: TAtlasEventKind.Process),
    (Word: 'OUTPUT'; Kind: TAtlasEventKind.Output), (Word: 'AUSGABE'; Kind: TAtlasEventKind.Output),
    (Word: 'ODS'; Kind: TAtlasEventKind.Output));
  // Längstes Präfix vor dem Doppelpunkt, das noch als Art gilt.
  cMaxPrefix = 32;

class function TAtlasEventLog.Classify(const ALine: string; out AText, AThread: string): TAtlasEventKind;
var
  mColon: Integer;
  mHead: string;
  mWord: TKindWord;
  mMatch: TMatch;
begin
  Result := TAtlasEventKind.Other;
  AText := Trim(ALine);
  AThread := '';
  mColon := Pos(':', AText);
  if (mColon > 1) and (mColon <= cMaxPrefix) then
  begin
    mHead := AnsiUpperCase(Copy(AText, 1, mColon - 1));
    for mWord in cKindWords do
    begin
      if Pos(mWord.Word, mHead) > 0 then
      begin
        Result := mWord.Kind;
        AText := Trim(Copy(AText, mColon + 1, MaxInt));
        Break;
      end;
    end;
  end;
  mMatch := TRegEx.Match(AText, cThreadId, [roIgnoreCase]);
  if mMatch.Success then
  begin
    AThread := mMatch.Groups[1].Value;
  end;
  // Die IDE hängt an Ausgaben und Haltepunkt-Meldungen den Prozess an: "… Process Demo.exe (1234)".
  if Result in [TAtlasEventKind.Output, TAtlasEventKind.Breakpoint, TAtlasEventKind.Logpoint] then
  begin
    AText := TRegEx.Replace(AText, cProcessSuffix, '', [roIgnoreCase]);
  end;
end;

end.
