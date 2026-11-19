unit Atlas.Core.Debug.ReturnValues;

// Rückgabewerte nach dem Verlassen eigener Funktionen (#844) ohne IDE:
// - Betroffene Funktionen einer Zeile: aus der Antwort von atlas.server.stepTargets (Aufrufe mit den begin-Zeilen
//   ihrer Rümpfe). Je Ziel in eigenem Code (Rückruf) die Routine, deren Anweisungsteil die begin-Zeile enthält, auch
//   lokale Routinen (TAtlasMethodToggle zählt sie zur umgebenden; die Rümpfe hier zählt ein eigener Durchlauf über
//   die Blöcke). Nur Funktionen und Operatoren (Kopf mit function bzw. operator), keine Prozeduren, Konstruktoren und
//   Destruktoren. Beobachtet wird das abschließende end des Anweisungsteils, je Datei und Zeile einmal, in
//   Aufrufreihenfolge.
// - Anzeige: die Ergebnisse eines Schritts am Ende der Aufrufzeile, „→ BerechneNetto = 109,16“, mehrere in der
//   Reihenfolge, in der die Funktionen zurückkehrten.
// - Verlauf „Zuletzt zurückgegeben“: die letzten 20 mit Funktion, Ergebnis, verlassener end-Zeile und Zeitpunkt.
// Zeilen ab 0. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.StepInto;

type
  /// <summary>Funktion, deren Ergebnis Atlas an ihrer end-Zeile abholt.</summary>
  TAtlasReturnWatch = record
    /// <summary>Name ohne Klasse, etwa BerechneNetto.</summary>
    Name: string;
    FileName: string;
    /// <summary>Zeile des abschließenden end (ab 0).</summary>
    EndLine: Integer;
  end;

  /// <summary>Ein abgeholtes Ergebnis.</summary>
  TAtlasReturnEntry = record
    Name: string;
    /// <summary>Anzeigetext des Ergebnisses (auch der Ersatz, wenn es nicht auswertbar war).</summary>
    Value: string;
    FileName: string;
    EndLine: Integer;
    Time: TDateTime;
  end;

  /// <summary>Text der Datei AFileName (Editor oder Platte); False ohne.</summary>
  TAtlasReturnSource = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Gehört AFileName zum eigenen Code?</summary>
  TAtlasReturnOwnFile = reference to function(const AFileName: string): Boolean;

  TAtlasReturnValues = class
  public const
    /// <summary>So viele Ergebnisse bleiben im Verlauf.</summary>
    cMaxEntries = 20;
    /// <summary>Trenner zwischen mehreren Ergebnissen am Zeilenende.</summary>
    cSeparator = '   ';
  private
    FEntries: TArray<TAtlasReturnEntry>;
    FShown: TArray<TAtlasReturnEntry>;
    FFileName: string;
    FLine: Integer;
    FVisible: Boolean;
  public
    constructor Create;
    /// <summary>Neue Sitzung: Verlauf und Anzeige verwerfen.</summary>
    procedure Clear;
    /// <summary>Ein Schritt beginnt: Die Anzeige des vorigen verschwindet, der Verlauf bleibt.</summary>
    procedure BeginStep;
    /// <summary>Ergebnis AValue von AWatch abgeholt (zur Zeit ATime): in den Verlauf und zur Anzeige.</summary>
    procedure Add(const AWatch: TAtlasReturnWatch; const AValue: string; ATime: TDateTime);
    /// <summary>Schritt zu Ende: Die Ergebnisse stehen am Ende der Zeile ALine von AFileName. Ergebnis: Steht jetzt
    /// etwas da?</summary>
    function Show(const AFileName: string; ALine: Integer): Boolean;
    /// <summary>Weitergelaufen bzw. Sitzung beendet: nichts mehr am Zeilenende, der Verlauf bleibt.</summary>
    procedure Hide;
    /// <summary>Text am Ende der Zeile ALine (ab 0) von AFileName; '' ohne.</summary>
    function LineText(const AFileName: string; ALine: Integer): string;
    /// <summary>Datei und Zeile der Anzeige; False ohne Anzeige.</summary>
    function Shown(out AFileName: string; out ALine: Integer): Boolean;
    /// <summary>Ergebnisse, das jüngste zuerst.</summary>
    function Entries: TArray<TAtlasReturnEntry>;
    function Count: Integer;
    /// <summary>„→ BerechneNetto = 109,16“.</summary>
    class function Note(const AEntry: TAtlasReturnEntry): string; static;
    /// <summary>Zeile im Verlauf: „BerechneNetto = 109,16   Preise.pas 42   14:03:12“ (Zeile ab 1).</summary>
    class function HistoryLine(const AEntry: TAtlasReturnEntry): string; static;
    /// <summary>Funktion, deren Anweisungsteil (begin bis end) ALine (ab 0) in AText enthält, auch eine lokale;
    /// False außerhalb jeder Funktion und in Prozeduren.</summary>
    class function FunctionAt(const AText, AFileName: string; ALine: Integer; out AWatch: TAtlasReturnWatch): Boolean;
      static;
    /// <summary>Beobachtete Funktionen der Aufrufe in AAnswer: Ziele im eigenen Code (AOwnFile), deren Rumpf eine
    /// Funktion ist; Text über ASource. Je Datei und end-Zeile einmal, in Aufrufreihenfolge.</summary>
    class function Watches(const AAnswer: TAtlasStepAnswer; const ASource: TAtlasReturnSource;
      const AOwnFile: TAtlasReturnOwnFile): TArray<TAtlasReturnWatch>; static;
  end;

implementation

uses
  System.Character,
  System.Math,
  System.StrUtils,
  Atlas.Core.Editor.MethodToggle,
  Atlas.Core.Debug.RunTo;

type
  /// <summary>Routine einer Implementierung: Kopf und Anweisungsteil (Zeilen ab 0).</summary>
  TRoutine = record
    Name: string;
    IsFunction: Boolean;
    BeginLine: Integer;
    EndLine: Integer;
  end;

  /// <summary>Liest eine Implementierung Zeile für Zeile: Köpfe am Zeilenanfang kommen auf einen Stapel, jeder
  /// Anweisungsteil auf oberster Ebene (begin bzw. asm bis zum passenden end) schließt den obersten Kopf ab. So
  /// bekommen lokale Routinen ihren eigenen Anweisungsteil, der der umgebenden kommt zuletzt.</summary>
  TRoutineScan = record
    Heads: TArray<TRoutine>;
    Routines: TArray<TRoutine>;
    Depth: Integer;
    Open: Integer;
    /// <summary>Je offenem Block: Record? Dessen varianter Teil (case … of) öffnet keinen Block.</summary>
    Records: TArray<Boolean>;
    procedure Head(const AWords: TArray<string>; const AText: string);
    procedure Feed(const AWords: TArray<string>; ALine: Integer);
    procedure Enter(const AWord: string; ALine: Integer);
    procedure Leave(ALine: Integer);
  end;

/// <summary>Letzter Teil eines qualifizierten Namens: TOuter.TInner.Run → Run.</summary>
function ShortName(const AName: string): string;
var
  mDot: Integer;
begin
  mDot := AName.LastIndexOf('.');
  Result := AName.Substring(mDot + 1);
end;

{ TAtlasReturnValues }

constructor TAtlasReturnValues.Create;
begin
  inherited Create;
  Clear;
end;

procedure TAtlasReturnValues.Clear;
begin
  FEntries := nil;
  BeginStep;
end;

procedure TAtlasReturnValues.BeginStep;
begin
  FShown := nil;
  FFileName := '';
  FLine := -1;
  FVisible := False;
end;

procedure TAtlasReturnValues.Add(const AWatch: TAtlasReturnWatch; const AValue: string; ATime: TDateTime);
var
  mEntry: TAtlasReturnEntry;
begin
  mEntry := Default(TAtlasReturnEntry);
  mEntry.Name := AWatch.Name;
  mEntry.Value := AValue;
  mEntry.FileName := AWatch.FileName;
  mEntry.EndLine := AWatch.EndLine;
  mEntry.Time := ATime;
  SetLength(FShown, Length(FShown) + 1);
  FShown[High(FShown)] := mEntry;
  // Jüngstes zuerst; höchstens cMaxEntries.
  Insert(mEntry, FEntries, 0);
  if Length(FEntries) > cMaxEntries then
  begin
    SetLength(FEntries, cMaxEntries);
  end;
end;

function TAtlasReturnValues.Show(const AFileName: string; ALine: Integer): Boolean;
begin
  FFileName := AFileName;
  FLine := ALine;
  FVisible := (Length(FShown) > 0) and (AFileName <> '') and (ALine >= 0);
  Result := FVisible;
end;

procedure TAtlasReturnValues.Hide;
begin
  FVisible := False;
end;

function TAtlasReturnValues.LineText(const AFileName: string; ALine: Integer): string;
var
  mEntry: TAtlasReturnEntry;
begin
  Result := '';
  if not FVisible or (ALine <> FLine) or not SameText(AFileName, FFileName) then
  begin
    Exit;
  end;
  for mEntry in FShown do
  begin
    if Result <> '' then
    begin
      Result := Result + cSeparator;
    end;
    Result := Result + Note(mEntry);
  end;
end;

function TAtlasReturnValues.Shown(out AFileName: string; out ALine: Integer): Boolean;
begin
  AFileName := FFileName;
  ALine := FLine;
  Result := FVisible;
end;

function TAtlasReturnValues.Entries: TArray<TAtlasReturnEntry>;
begin
  Result := Copy(FEntries);
end;

function TAtlasReturnValues.Count: Integer;
begin
  Result := Length(FEntries);
end;

class function TAtlasReturnValues.Note(const AEntry: TAtlasReturnEntry): string;
begin
  Result := '→ ' + AEntry.Name + ' = ' + AEntry.Value;
end;

class function TAtlasReturnValues.HistoryLine(const AEntry: TAtlasReturnEntry): string;
begin
  Result := AEntry.Name + ' = ' + AEntry.Value + cSeparator + ExtractFileName(AEntry.FileName) + ' ' +
    IntToStr(AEntry.EndLine + 1) + cSeparator + FormatDateTime('hh:nn:ss', AEntry.Time,
    TFormatSettings.Invariant);
end;

{ TRoutineScan }

/// <summary>Name hinter dem Schlüsselwort AKeyword in AText ohne Klasse und Typparameter: „function TA.Run&lt;T&gt;(“
/// → Run.</summary>
function NameAfter(const AText, AKeyword: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := Pos(AKeyword, LowerCase(AText));
  if mIndex = 0 then
  begin
    Exit;
  end;
  Inc(mIndex, Length(AKeyword));
  while (mIndex <= Length(AText)) and (AText[mIndex] = ' ') do
  begin
    Inc(mIndex);
  end;
  while (mIndex <= Length(AText)) and (AText[mIndex].IsLetterOrDigit or CharInSet(AText[mIndex], ['_', '.'])) do
  begin
    Result := Result + AText[mIndex];
    Inc(mIndex);
  end;
  Result := ShortName(Result);
end;

procedure TRoutineScan.Head(const AWords: TArray<string>; const AText: string);
var
  mFirst: Integer;
  mRoutine: TRoutine;
begin
  // Nur ein Kopf am Zeilenanfang: „TF = function: Integer“ und „F: procedure“ sind Typen.
  mFirst := 0;
  if (Length(AWords) > 1) and (AWords[0] = 'class') then
  begin
    mFirst := 1;
  end;
  if (Depth > 0) or (Length(AWords) = 0) or
    not MatchStr(AWords[mFirst], ['function', 'procedure', 'constructor', 'destructor', 'operator']) then
  begin
    Exit;
  end;
  mRoutine := Default(TRoutine);
  mRoutine.Name := NameAfter(AText, AWords[mFirst]);
  mRoutine.IsFunction := MatchStr(AWords[mFirst], ['function', 'operator']);
  mRoutine.BeginLine := -1;
  mRoutine.EndLine := -1;
  SetLength(Heads, Length(Heads) + 1);
  Heads[High(Heads)] := mRoutine;
end;

procedure TRoutineScan.Feed(const AWords: TArray<string>; ALine: Integer);
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    if MatchStr(mWord, ['begin', 'asm', 'try', 'record']) or ((mWord = 'case') and
      not ((Depth > 0) and Records[Depth - 1])) then
    begin
      Enter(mWord, ALine);
    end
    else if (mWord = 'end') and (Depth > 0) then
    begin
      Leave(ALine);
    end;
  end;
end;

procedure TRoutineScan.Enter(const AWord: string; ALine: Integer);
begin
  if (Depth = 0) and ((AWord = 'begin') or (AWord = 'asm')) then
  begin
    Open := ALine;
  end;
  Inc(Depth);
  SetLength(Records, Depth);
  Records[Depth - 1] := AWord = 'record';
end;

procedure TRoutineScan.Leave(ALine: Integer);
var
  mRoutine: TRoutine;
begin
  Dec(Depth);
  SetLength(Records, Depth);
  if (Depth > 0) or (Open < 0) or (Length(Heads) = 0) then
  begin
    Exit;
  end;
  // Anweisungsteil zu Ende: gehört zum obersten Kopf.
  mRoutine := Heads[High(Heads)];
  SetLength(Heads, Length(Heads) - 1);
  mRoutine.BeginLine := Open;
  mRoutine.EndLine := ALine;
  SetLength(Routines, Length(Routines) + 1);
  Routines[High(Routines)] := mRoutine;
  Open := -1;
end;

/// <summary>Routinen der Implementierung APlace (samt lokalen) in den Zeilen ALines.</summary>
function RoutinesOf(const ALines: TArray<string>; const APlace: TAtlasMethodPlace): TArray<TRoutine>;
var
  mWords: TArray<TArray<string>>;
  mScan: TRoutineScan;
  mIndex: Integer;
begin
  mScan := Default(TRoutineScan);
  mScan.Open := -1;
  mWords := TAtlasRunTo.CodeWords(ALines, APlace.FirstLine, Min(APlace.LastLine, High(ALines)));
  for mIndex := 0 to High(mWords) do
  begin
    mScan.Head(mWords[mIndex], ALines[APlace.FirstLine + mIndex]);
    mScan.Feed(mWords[mIndex], APlace.FirstLine + mIndex);
  end;
  Result := mScan.Routines;
  // Der umgebende Kopf: Name aus der Implementierung (mit Klasse aufgelöst).
  if Length(Result) > 0 then
  begin
    Result[High(Result)].Name := ShortName(APlace.Name);
  end;
end;

class function TAtlasReturnValues.FunctionAt(const AText, AFileName: string; ALine: Integer;
  out AWatch: TAtlasReturnWatch): Boolean;
var
  mPlace: TAtlasMethodPlace;
  mRoutine: TRoutine;
begin
  AWatch := Default(TAtlasReturnWatch);
  AWatch.EndLine := -1;
  Result := False;
  if not TAtlasMethodToggle.BodyAt(TAtlasMethodToggle.Places(AText), ALine, mPlace) then
  begin
    Exit;
  end;
  for mRoutine in RoutinesOf(AText.Split([#13#10, #10]), mPlace) do
  begin
    if (ALine >= mRoutine.BeginLine) and (ALine <= mRoutine.EndLine) then
    begin
      Result := mRoutine.IsFunction;
      if Result then
      begin
        AWatch.Name := mRoutine.Name;
        AWatch.FileName := AFileName;
        AWatch.EndLine := mRoutine.EndLine;
      end;
      Exit;
    end;
  end;
end;

/// <summary>Steht AWatch unter den ersten ACount von AWatches (gleiche Datei und end-Zeile)?</summary>
function Contains(const AWatches: TArray<TAtlasReturnWatch>; ACount: Integer; const AWatch: TAtlasReturnWatch): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to ACount - 1 do
  begin
    if (AWatches[mIndex].EndLine = AWatch.EndLine) and SameText(AWatches[mIndex].FileName, AWatch.FileName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Beobachtete Funktion zum Ziel ATarget; False außerhalb des eigenen Codes, ohne Text oder ohne Funktion.
/// </summary>
function WatchOf(const ATarget: TAtlasStepTarget; const ASource: TAtlasReturnSource;
  const AOwnFile: TAtlasReturnOwnFile; out AWatch: TAtlasReturnWatch): Boolean;
var
  mText: string;
begin
  AWatch := Default(TAtlasReturnWatch);
  Result := Assigned(AOwnFile) and AOwnFile(ATarget.FileName) and Assigned(ASource) and
    ASource(ATarget.FileName, mText) and TAtlasReturnValues.FunctionAt(mText, ATarget.FileName, ATarget.Line, AWatch);
end;

class function TAtlasReturnValues.Watches(const AAnswer: TAtlasStepAnswer; const ASource: TAtlasReturnSource;
  const AOwnFile: TAtlasReturnOwnFile): TArray<TAtlasReturnWatch>;
var
  mCall: TAtlasStepCall;
  mTarget: TAtlasStepTarget;
  mWatch: TAtlasReturnWatch;
  mCount: Integer;
begin
  Result := nil;
  mCount := 0;
  for mCall in AAnswer.Calls do
  begin
    Inc(mCount, Length(mCall.Targets));
  end;
  SetLength(Result, mCount);
  mCount := 0;
  for mCall in AAnswer.Calls do
  begin
    for mTarget in mCall.Targets do
    begin
      if WatchOf(mTarget, ASource, AOwnFile, mWatch) and not Contains(Result, mCount, mWatch) then
      begin
        Result[mCount] := mWatch;
        Inc(mCount);
      end;
    end;
  end;
  SetLength(Result, mCount);
end;

end.
