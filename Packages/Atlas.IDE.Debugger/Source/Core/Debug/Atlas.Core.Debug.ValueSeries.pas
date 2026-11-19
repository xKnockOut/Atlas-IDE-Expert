unit Atlas.Core.Debug.ValueSeries;

// Werteverlauf aus Logpunkten (#2552), Kern ohne VCL und ohne IDE:
// - TAtlasLogpointNumber liest eine Zahl in deutscher oder englischer
//   Schreibweise („48“, „-3,5“, „1.234,5“, „1,234.5“, „2.5E3“); alles andere
//   ist keine Zahl und wird im Verlauf eine Lücke, keine 0.
// - TAtlasLogpointValue holt den Wert aus der zusammengeführten Zeile im
//   Ereignisprotokoll: Präfix und Ort („ · Datei.pas:12“) ab, dann den Text
//   vor und hinter dem einzigen Platzhalter der Vorlage.
// - TAtlasValueSeries hält je Logpunkt Zeit seit Sitzungsbeginn, Thread, Wert
//   und Zeile, höchstens Limit Treffer (Ring: die ältesten fallen heraus),
//   dazu Threads, Kennzahlen und CSV je Thread.
// - TAtlasValueSeriesSet hält die Reihen der Sitzung je Ort.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin.Debug,
  Atlas.Core.Debug.Logpoint;

type
  TAtlasLogpointNumber = record
  public
    /// <summary>Zahl aus AText; False für Text, Wahrheitswerte, leere Werte.</summary>
    class function TryParse(const AText: string; out AValue: Double): Boolean; static;
  end;

  TAtlasLogpointValue = record
  public
    /// <summary>Zeile ALine des Ereignisprotokolls ohne Präfix APrefix und ohne Ort; APlace ist der Ort ('' ohne).
    /// </summary>
    class function Split(const ALine, APrefix: string; out AMessage, APlace: string): Boolean; static;
    /// <summary>Wert des einzigen Platzhalters von ATemplate in AMessage (ohne Präfix und Ort); False, wenn die
    /// Vorlage nicht genau einen Platzhalter hat oder AMessage nicht zu ihr passt.</summary>
    class function Extract(const ATemplate: TAtlasLogpointTemplate; const AMessage: string;
      out AValue: string): Boolean; static;
    /// <summary>Hat ATemplate genau einen Platzhalter (Voraussetzung für „Zahl aufzeichnen“)?</summary>
    class function CanRecord(const ATemplate: TAtlasLogpointTemplate): Boolean; static;
  end;

  TAtlasValuePoint = record
    /// <summary>Millisekunden seit Beginn der Sitzung.</summary>
    AtMs: Int64;
    Thread: string;
    Value: Double;
    /// <summary>Keine Zahl: Lücke in der Linie.</summary>
    IsGap: Boolean;
    /// <summary>Zeile im Ereignisprotokoll (zum Springen).</summary>
    Line: string;
    /// <summary>Treffer aus der Zeile AMessage (ohne Präfix und Ort) zu ATemplate; ohne Zahl eine Lücke. False,
    /// wenn die Zeile nicht zur Vorlage passt.</summary>
    class function TryOf(const ATemplate: TAtlasLogpointTemplate; const AMessage: string; AAtMs: Int64;
      const AThread, ALine: string; out APoint: TAtlasValuePoint): Boolean; static;
  end;

  TAtlasValueStats = record
    /// <summary>Treffer samt Lücken.</summary>
    Count: Integer;
    /// <summary>Treffer mit Zahl.</summary>
    Numbers: Integer;
    Min: Double;
    Max: Double;
    Last: Double;
  end;

  TAtlasValueSeries = class
  public const
    /// <summary>Wie debug.logpoints.recordLimit.</summary>
    cDefaultLimit = cDefaultLogpointRecordLimit;
    cMinLimit = cMinLogpointRecordLimit;
    cMaxLimit = cMaxLogpointRecordLimit;
  private
    FName: string;
    FPlace: string;
    FItems: TArray<TAtlasValuePoint>;
    FStart: Integer;
    FCount: Integer;
    function GetPoint(AIndex: Integer): TAtlasValuePoint;
  public
    constructor Create(const AName, APlace: string; ALimit: Integer);
    procedure Add(const APoint: TAtlasValuePoint);
    /// <summary>Höchstzahl ändern; bei weniger fallen die ältesten heraus.</summary>
    procedure SetLimit(ALimit: Integer);
    function Limit: Integer;
    /// <summary>Threads in der Reihenfolge ihres ersten Treffers.</summary>
    function Threads: TArray<string>;
    /// <summary>Treffer des Threads AThread ('' = alle) in Zeitfolge.</summary>
    function PointsOf(const AThread: string): TArray<TAtlasValuePoint>;
    function Stats(const AThread: string): TAtlasValueStats;
    /// <summary>„Zeit_s,Thread,Wert“ je Treffer von AThread ('' = alle), Punkt als Dezimaltrenner; Lücken leer.
    /// </summary>
    function ToCsv(const AThread: string): string;
    property Name: string read FName write FName;
    property Place: string read FPlace;
    property Count: Integer read FCount;
    property Points[AIndex: Integer]: TAtlasValuePoint read GetPoint; default;
  end;

  TAtlasValueSeriesSet = class
  private
    FItems: TObjectList<TAtlasValueSeries>;
    function GetItem(AIndex: Integer): TAtlasValueSeries;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    /// <summary>Reihe zu APlace; nil ohne.</summary>
    function Find(const APlace: string): TAtlasValueSeries;
    /// <summary>Reihe zu APlace, neu mit AName und ALimit, wenn es keine gibt; der Name wird übernommen.</summary>
    function Ensure(const APlace, AName: string; ALimit: Integer): TAtlasValueSeries;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TAtlasValueSeries read GetItem; default;
  end;

  /// <summary>Kurzer Text eines Werts: ganze Zahlen ohne Nachkommastellen, sonst bis zu 4 Stellen.</summary>
  TAtlasValueText = record
  public
    class function Text(AValue: Double; const AFormat: TFormatSettings): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils;

const
  /// <summary>Zeichen, die in einer Zahl vorkommen dürfen.</summary>
  cNumberChars = ['0'..'9', '.', ',', '-', '+', 'e', 'E'];
  /// <summary>Bis hierher sind ganze Zahlen in Double exakt und werden ohne Nachkommastellen gezeigt.</summary>
  cExactWhole = 1E15;

{ TAtlasLogpointNumber }

/// <summary>Letzte Stelle von ',' oder '.' in AText; 0 ohne.</summary>
function LastMark(const AText: string): Integer;
begin
  Result := Max(LastDelimiter('.', AText), LastDelimiter(',', AText));
end;

/// <summary>AText ohne Tausendertrenner, mit Punkt als Dezimaltrenner.</summary>
function Normalized(const AText: string): string;
var
  mMark: Integer;
  mDecimal, mGroup: Char;
begin
  mMark := LastMark(AText);
  if mMark = 0 then
  begin
    Exit(AText);
  end;
  mDecimal := AText[mMark];
  mGroup := '.';
  if mDecimal = '.' then
  begin
    mGroup := ',';
  end;
  // Kommt das letzte Zeichen mehrfach vor und das andere nicht, ist es ein Tausendertrenner („1.234.567“).
  if (Pos(mGroup, AText) = 0) and (Pos(mDecimal, AText) < mMark) then
  begin
    Exit(StringReplace(AText, mDecimal, '', [rfReplaceAll]));
  end;
  Result := StringReplace(Copy(AText, 1, mMark - 1), mGroup, '', [rfReplaceAll]) + '.' +
    Copy(AText, mMark + 1, MaxInt);
end;

class function TAtlasLogpointNumber.TryParse(const AText: string; out AValue: Double): Boolean;
var
  mText: string;
  mChar: Char;
  mFormat: TFormatSettings;
begin
  AValue := 0;
  mText := Trim(AText);
  if (mText = '') or not CharInSet(mText[1], ['0'..'9', '-', '+', '.', ',']) then
  begin
    Exit(False);
  end;
  for mChar in mText do
  begin
    if not CharInSet(mChar, cNumberChars) then
    begin
      Exit(False);
    end;
  end;
  mFormat := TFormatSettings.Invariant;
  Result := TryStrToFloat(Normalized(mText), AValue, mFormat) and not IsNan(AValue) and not IsInfinite(AValue);
  if not Result then
  begin
    AValue := 0;
  end;
end;

{ TAtlasLogpointValue }

class function TAtlasLogpointValue.Split(const ALine, APrefix: string; out AMessage, APlace: string): Boolean;
var
  mText, mPrefix: string;
  mAt: Integer;
begin
  mText := Trim(ALine);
  mPrefix := Trim(APrefix);
  AMessage := '';
  APlace := '';
  Result := (mPrefix = '') or mText.StartsWith(mPrefix, True);
  if not Result then
  begin
    Exit;
  end;
  mText := Trim(Copy(mText, Length(mPrefix) + 1, MaxInt));
  mAt := mText.LastIndexOf(TAtlasLogpointPlan.cPlaceMark);
  if mAt >= 0 then
  begin
    APlace := Trim(mText.Substring(mAt + Length(TAtlasLogpointPlan.cPlaceMark)));
    mText := mText.Substring(0, mAt);
  end;
  AMessage := Trim(mText);
end;

class function TAtlasLogpointValue.CanRecord(const ATemplate: TAtlasLogpointTemplate): Boolean;
begin
  Result := ATemplate.Valid and (Length(ATemplate.Expressions) = 1);
end;

class function TAtlasLogpointValue.Extract(const ATemplate: TAtlasLogpointTemplate; const AMessage: string;
  out AValue: string): Boolean;
var
  mPart: TAtlasLogpointPart;
  mBuilders: array[Boolean] of TStringBuilder;
  mSeen: Boolean;
  mBefore, mAfter: string;
begin
  AValue := '';
  if not CanRecord(ATemplate) then
  begin
    Exit(False);
  end;
  // Text vor (False) und hinter (True) dem Platzhalter.
  mBuilders[False] := TStringBuilder.Create;
  mBuilders[True] := TStringBuilder.Create;
  try
    mSeen := False;
    for mPart in ATemplate.Parts do
    begin
      if mPart.Kind = TAtlasLogpointPartKind.Expression then
      begin
        mSeen := True;
        Continue;
      end;
      mBuilders[mSeen].Append(mPart.Text);
    end;
    // Die Meldung ist getrimmt: Leerraum am Rand der Vorlage zählt nicht.
    mBefore := TrimLeft(mBuilders[False].ToString);
    mAfter := TrimRight(mBuilders[True].ToString);
  finally
    mBuilders[True].Free;
    mBuilders[False].Free;
  end;
  Result := AMessage.StartsWith(mBefore) and AMessage.EndsWith(mAfter) and
    (Length(AMessage) >= Length(mBefore) + Length(mAfter));
  if Result then
  begin
    AValue := Trim(Copy(AMessage, Length(mBefore) + 1, Length(AMessage) - Length(mBefore) - Length(mAfter)));
  end;
end;

{ TAtlasValuePoint }

class function TAtlasValuePoint.TryOf(const ATemplate: TAtlasLogpointTemplate; const AMessage: string;
  AAtMs: Int64; const AThread, ALine: string; out APoint: TAtlasValuePoint): Boolean;
var
  mValue: string;
begin
  APoint := Default(TAtlasValuePoint);
  Result := TAtlasLogpointValue.Extract(ATemplate, AMessage, mValue);
  if not Result then
  begin
    Exit;
  end;
  APoint.AtMs := AAtMs;
  APoint.Thread := AThread;
  APoint.Line := ALine;
  APoint.IsGap := not TAtlasLogpointNumber.TryParse(mValue, APoint.Value);
end;

{ TAtlasValueSeries }

constructor TAtlasValueSeries.Create(const AName, APlace: string; ALimit: Integer);
begin
  inherited Create;
  FName := AName;
  FPlace := APlace;
  SetLength(FItems, EnsureRange(ALimit, cMinLimit, cMaxLimit));
end;

function TAtlasValueSeries.Limit: Integer;
begin
  Result := Length(FItems);
end;

function TAtlasValueSeries.GetPoint(AIndex: Integer): TAtlasValuePoint;
begin
  Result := FItems[(FStart + AIndex) mod Length(FItems)];
end;

procedure TAtlasValueSeries.Add(const APoint: TAtlasValuePoint);
begin
  if FCount < Length(FItems) then
  begin
    FItems[(FStart + FCount) mod Length(FItems)] := APoint;
    Inc(FCount);
    Exit;
  end;
  // Voll: der älteste Platz bekommt den neuen Treffer.
  FItems[FStart] := APoint;
  FStart := (FStart + 1) mod Length(FItems);
end;

procedure TAtlasValueSeries.SetLimit(ALimit: Integer);
var
  mItems: TArray<TAtlasValuePoint>;
  mKeep, mIndex: Integer;
begin
  ALimit := EnsureRange(ALimit, cMinLimit, cMaxLimit);
  if ALimit = Length(FItems) then
  begin
    Exit;
  end;
  mKeep := Min(FCount, ALimit);
  SetLength(mItems, ALimit);
  for mIndex := 0 to mKeep - 1 do
  begin
    mItems[mIndex] := GetPoint(FCount - mKeep + mIndex);
  end;
  FItems := mItems;
  FStart := 0;
  FCount := mKeep;
end;

function TAtlasValueSeries.Threads: TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mIndex: Integer;
  mThread: string;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to FCount - 1 do
    begin
      mThread := GetPoint(mIndex).Thread;
      if not mSeen.ContainsKey(mThread) then
      begin
        mSeen.Add(mThread, True);
        Result := Result + [mThread];
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

function TAtlasValueSeries.PointsOf(const AThread: string): TArray<TAtlasValuePoint>;
var
  mIndex, mCount: Integer;
  mPoint: TAtlasValuePoint;
begin
  Result := nil;
  SetLength(Result, FCount);
  mCount := 0;
  for mIndex := 0 to FCount - 1 do
  begin
    mPoint := GetPoint(mIndex);
    if (AThread = '') or (mPoint.Thread = AThread) then
    begin
      Result[mCount] := mPoint;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

function TAtlasValueSeries.Stats(const AThread: string): TAtlasValueStats;
var
  mPoint: TAtlasValuePoint;
begin
  Result := Default(TAtlasValueStats);
  for mPoint in PointsOf(AThread) do
  begin
    Inc(Result.Count);
    if mPoint.IsGap then
    begin
      Continue;
    end;
    if Result.Numbers = 0 then
    begin
      Result.Min := mPoint.Value;
      Result.Max := mPoint.Value;
    end;
    Inc(Result.Numbers);
    Result.Min := Min(Result.Min, mPoint.Value);
    Result.Max := Max(Result.Max, mPoint.Value);
    Result.Last := mPoint.Value;
  end;
end;

/// <summary>Feld für CSV: mit Komma, Anführungszeichen oder Zeilenumbruch in Anführungszeichen.</summary>
function CsvField(const AText: string): string;
begin
  Result := AText;
  if (Pos(',', Result) > 0) or (Pos('"', Result) > 0) or (Pos(#10, Result) > 0) or (Pos(#13, Result) > 0) then
  begin
    Result := '"' + StringReplace(Result, '"', '""', [rfReplaceAll]) + '"';
  end;
end;

function TAtlasValueSeries.ToCsv(const AThread: string): string;
var
  mBuilder: TStringBuilder;
  mPoint: TAtlasValuePoint;
  mFormat: TFormatSettings;
begin
  mFormat := TFormatSettings.Invariant;
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('time_s,thread,value').Append(sLineBreak);
    for mPoint in PointsOf(AThread) do
    begin
      mBuilder.Append(FormatFloat('0.000', mPoint.AtMs / 1000, mFormat)).Append(',');
      mBuilder.Append(CsvField(mPoint.Thread)).Append(',');
      if not mPoint.IsGap then
      begin
        mBuilder.Append(FloatToStr(mPoint.Value, mFormat));
      end;
      mBuilder.Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TAtlasValueSeriesSet }

constructor TAtlasValueSeriesSet.Create;
begin
  inherited Create;
  FItems := TObjectList<TAtlasValueSeries>.Create(True);
end;

destructor TAtlasValueSeriesSet.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TAtlasValueSeriesSet.Clear;
begin
  FItems.Clear;
end;

function TAtlasValueSeriesSet.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TAtlasValueSeriesSet.GetItem(AIndex: Integer): TAtlasValueSeries;
begin
  Result := FItems[AIndex];
end;

function TAtlasValueSeriesSet.Find(const APlace: string): TAtlasValueSeries;
var
  mSeries: TAtlasValueSeries;
begin
  for mSeries in FItems do
  begin
    if SameText(mSeries.Place, APlace) then
    begin
      Exit(mSeries);
    end;
  end;
  Result := nil;
end;

function TAtlasValueSeriesSet.Ensure(const APlace, AName: string; ALimit: Integer): TAtlasValueSeries;
begin
  Result := Find(APlace);
  if Result = nil then
  begin
    Result := TAtlasValueSeries.Create(AName, APlace, ALimit);
    FItems.Add(Result);
    Exit;
  end;
  Result.Name := AName;
  Result.SetLimit(ALimit);
end;

{ TAtlasValueText }

class function TAtlasValueText.Text(AValue: Double; const AFormat: TFormatSettings): string;
begin
  if (Abs(AValue) < cExactWhole) and (Frac(AValue) = 0) then
  begin
    Exit(FormatFloat('0', AValue, AFormat));
  end;
  Result := FormatFloat('0.####', AValue, AFormat);
end;

end.
