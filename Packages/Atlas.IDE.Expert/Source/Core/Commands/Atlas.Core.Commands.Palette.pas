unit Atlas.Core.Commands.Palette;

// Befehlspalette (#502), Teil ohne Open Tools API: Befehle aus IDE-Aktionen
// und Atlas, Verlauf je Benutzer und Rangfolge. Ausgewählt wird wie in der
// Vervollständigung (#229: genauer Name, Anfang, Wortanfänge, Teilfolge),
// gegen die Beschriftung und ersatzweise „Menüpfad Beschriftung“; zuletzt
// eine einfache Teilfolge ohne Wortgrenzen („bpj“ → „Build Project“), weil
// Befehle aus mehreren Wörtern bestehen. Zuletzt und
// häufig genutzte Befehle bekommen einen Zuschlag unter 100 Punkten; ohne
// Eingabe stehen sie oben, danach alphabetisch.
// Mit AKeepOrder (Code-Aktionen, #399) bleibt ohne Eingabe die Reihenfolge der
// Liste, bei Gleichstand ebenso.
// Der Verlauf (palette.json) wird über TAtlasDataFile gelesen und atomar
// geschrieben (Bericht N3): Eine unbrauchbare Datei liegt danach als .defekt
// daneben, eine gesperrte bleibt unverändert und wird nicht überschrieben.
// Zusatzquelle (#1270, Issues in der Palette): IAtlasPaletteSource erfährt
// jede Eingabe und zeigt ihre Treffer als eigene Gruppe unter den Befehlen
// (TAtlasPaletteGroup), auch später, wenn die Antwort aus dem Netz kommt.
// TAtlasPaletteRows bestimmt die Zeilen (Befehle, Überschrift, Status,
// Einträge), welche wählbar sind und welche Aktion eine Taste auslöst.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Files.DataFile;

type
  TAtlasCommand = record
    /// <summary>Eindeutig, z. B. Name der Aktion oder "Atlas.Options".</summary>
    Id: string;
    Caption: string;
    /// <summary>Menüpfad bzw. Kategorie, gedimmt angezeigt ("Projekt › Erzeugen").</summary>
    Path: string;
    ShortCut: string;
    Description: string;
    IsAtlas: Boolean;
    /// <summary>Abzeichen rechts in der Zeile (Zustand eines Issues, #1270); '' ohne.</summary>
    Badge: string;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Wie ein Eintrag einer Zusatzgruppe ausgeführt wird: Enter (Open), Strg+Enter (Start),
  /// Umschalt+Enter (Browse), Strg+C (Copy, die Palette bleibt offen).</summary>
  TAtlasPaletteAction = (Open, Start, Browse, Copy);
{$SCOPEDENUMS OFF}

  /// <summary>Gruppe einer Zusatzquelle unter den Befehlen (#1270).</summary>
  TAtlasPaletteGroup = record
    /// <summary>Überschrift ("Issues"); '' = keine Gruppe.</summary>
    Title: string;
    /// <summary>Zeile unter der Überschrift ("Suche im Tracker …", Fehler, Tastenhinweis); '' ohne.</summary>
    Status: string;
    /// <summary>Text, dessen Zeichen in den Einträgen hervorgehoben werden.</summary>
    Highlight: string;
    Items: TArray<TAtlasCommand>;
    class function None: TAtlasPaletteGroup; static;
    class function Create(const ATitle, AStatus, AHighlight: string;
      const AItems: TArray<TAtlasCommand>): TAtlasPaletteGroup; static;
    function Visible: Boolean;
  end;

  /// <summary>Art einer Zeile: Befehl, Überschrift und Status der Zusatzgruppe, Eintrag der Gruppe.</summary>
{$SCOPEDENUMS ON}
  TAtlasPaletteRowKind = (Command, Header, Status, Item);
{$SCOPEDENUMS OFF}

  /// <summary>Zeilen der Palette (#1270): zuerst die Treffer der Befehle, darunter die Zusatzgruppe mit
  /// Überschrift, optionaler Statuszeile und Einträgen. Überschrift und Status sind nicht wählbar.</summary>
  TAtlasPaletteRows = record
  private
    FCommands: Integer;
    FGroup: Boolean;
    FStatus: Boolean;
    FItems: Integer;
  public
    class function Create(ACommands: Integer; const AGroup: TAtlasPaletteGroup): TAtlasPaletteRows; static;
    function Count: Integer;
    /// <summary>Art der Zeile ARow; AIndex: Befehl in der Trefferliste bzw. Eintrag der Gruppe.</summary>
    function Kind(ARow: Integer; out AIndex: Integer): TAtlasPaletteRowKind;
    function Selectable(ARow: Integer): Boolean;
    /// <summary>Erste wählbare Zeile; -1 ohne.</summary>
    function First: Integer;
    /// <summary>Von AFrom um ADelta weiter, Überschrift und Status in Schrittrichtung übersprungen (am Rand
    /// zurück); AFrom, wenn es keine wählbare Zeile gibt.</summary>
    function Step(AFrom, ADelta: Integer): Integer;
    /// <summary>Enter auf einem Eintrag: Strg = Start, sonst Umschalt = Browse, sonst Open.</summary>
    class function ActionOf(ACtrl, AShift: Boolean): TAtlasPaletteAction; static;
  end;

  /// <summary>Zusatzquelle der Palette (#1270), z. B. Issues im Tracker. Alle Aufrufe im Hauptthread.</summary>
  IAtlasPaletteSource = interface
    ['{D1D5D951-0AD7-4D3E-80D8-5021BD5F0C41}']
    /// <summary>Palette geöffnet; AShow zeigt bzw. ersetzt die Gruppe, auch später (nach Closed wirkungslos).
    /// </summary>
    procedure Opened(const AShow: TProc<TAtlasPaletteGroup>);
    /// <summary>Eingabe geändert (auch auf leer).</summary>
    procedure Changed(const APattern: string);
    /// <summary>Eintrag der Gruppe ausgeführt; außer bei Copy ist die Palette danach geschlossen.</summary>
    procedure Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
    /// <summary>Palette geschlossen: laufende Anfragen abbrechen, AShow nicht mehr rufen.</summary>
    procedure Closed;
  end;

  /// <summary>Atlas-Befehle anmelden (Palette, #520); ohne VCL und Open Tools API. Features melden ihre Befehle
  /// darüber an, statt die Palette der IDE-Schicht zu importieren (A-09). Ohne Referenzzählung: Die Palette
  /// gehört der Composition; Empfänger speichern die Schnittstelle nicht.</summary>
  IAtlasCommandRegistry = interface
    ['{57AA1265-60F8-4655-BC7B-1AE31AC48481}']
    /// <summary>Atlas-Befehl für die Palette (Beschriftung mit „Atlas: “ davor).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc); overload;
    /// <summary>Wie oben; der Befehl erscheint nur, solange AVisible True liefert (#520).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc;
      const AVisible: TFunc<Boolean>); overload;
  end;

  TAtlasCommandHistory = class
  private type
    TEntry = record
      Count: Integer;
      Last: Int64;
    end;
  private
    FEntries: TDictionary<string, TEntry>;
    FTick: Int64;
    /// <summary>Vorhandene Datei, die LoadFromFile nicht lesen konnte: SaveToFile überschreibt sie nicht.</summary>
    FKept: string;
    FKind: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Executed(const AId: string);
    /// <summary>Zuschlag 0..99: zuletzt ausgeführt am meisten, Häufigkeit dazu.</summary>
    function Boost(const AId: string): Integer;
    /// <summary>Übernimmt AText ({"Befehl": [Anzahl, Zeitpunkt], …}); Einträge anderer Form fallen weg. False,
    /// wenn AText kein Objekt ist.</summary>
    function Parse(const AText: string): Boolean;
    /// <summary>Liest über TAtlasDataFile.Load; fehlt die Datei oder ist sie unbrauchbar, beginnt der Verlauf
    /// leer. Ergebnis Kept: Die Datei bleibt unverändert, SaveToFile schreibt sie nicht.</summary>
    function LoadFromFile(const AFileName: string): TAtlasDataLoad;
    /// <summary>Schreibt atomar; False, wenn LoadFromFile die vorhandene Datei nicht lesen konnte.</summary>
    function SaveToFile(const AFileName: string): Boolean;
    /// <summary>Name der Ablage im Protokoll; Vorgabe „Verlauf der Befehlspalette“ (Schnell öffnen nutzt die
    /// Klasse auch).</summary>
    property Kind: string read FKind write FKind;
  end;

  TAtlasCommandPalette = class
  public
    /// <summary>Indizes der passenden Befehle, beste zuerst. AKeepOrder: ohne Eingabe und bei
    /// Gleichstand die Reihenfolge von ACommands statt alphabetisch.</summary>
    class function Order(const ACommands: TArray<TAtlasCommand>; const APattern: string;
      AHistory: TAtlasCommandHistory; AKeepOrder: Boolean = False): TArray<Integer>; static;
    /// <summary>Beschriftung ohne Kürzelzeichen: "&amp;Datei" → "Datei", "&amp;&amp;" → "&amp;", "..." am Ende weg.</summary>
    class function CleanCaption(const ACaption: string): string; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.Generics.Defaults,
  Atlas.Core.Completion.Matching;

{ TAtlasPaletteGroup }

class function TAtlasPaletteGroup.None: TAtlasPaletteGroup;
begin
  Result.Title := '';
  Result.Status := '';
  Result.Highlight := '';
  Result.Items := nil;
end;

class function TAtlasPaletteGroup.Create(const ATitle, AStatus, AHighlight: string;
  const AItems: TArray<TAtlasCommand>): TAtlasPaletteGroup;
begin
  Result.Title := ATitle;
  Result.Status := AStatus;
  Result.Highlight := AHighlight;
  Result.Items := AItems;
end;

function TAtlasPaletteGroup.Visible: Boolean;
begin
  Result := Title <> '';
end;

{ TAtlasPaletteRows }

class function TAtlasPaletteRows.Create(ACommands: Integer; const AGroup: TAtlasPaletteGroup): TAtlasPaletteRows;
begin
  Result.FCommands := ACommands;
  if Result.FCommands < 0 then
    Result.FCommands := 0;
  Result.FGroup := AGroup.Visible;
  Result.FStatus := Result.FGroup and (AGroup.Status <> '');
  Result.FItems := 0;
  if Result.FGroup then
    Result.FItems := Length(AGroup.Items);
end;

function TAtlasPaletteRows.Count: Integer;
begin
  Result := FCommands;
  if not FGroup then
    Exit;
  Inc(Result, 1 + FItems);
  if FStatus then
    Inc(Result);
end;

function TAtlasPaletteRows.Kind(ARow: Integer; out AIndex: Integer): TAtlasPaletteRowKind;
begin
  AIndex := ARow;
  Result := TAtlasPaletteRowKind.Command;
  if ARow < FCommands then
    Exit;
  AIndex := ARow - FCommands;
  if AIndex = 0 then
    Exit(TAtlasPaletteRowKind.Header);
  Dec(AIndex);
  if FStatus then
  begin
    if AIndex = 0 then
      Exit(TAtlasPaletteRowKind.Status);
    Dec(AIndex);
  end;
  Result := TAtlasPaletteRowKind.Item;
end;

function TAtlasPaletteRows.Selectable(ARow: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := (ARow >= 0) and (ARow < Count) and
    (Kind(ARow, mIndex) in [TAtlasPaletteRowKind.Command, TAtlasPaletteRowKind.Item]);
end;

function TAtlasPaletteRows.First: Integer;
var
  mRow: Integer;
begin
  for mRow := 0 to Count - 1 do
    if Selectable(mRow) then
      Exit(mRow);
  Result := -1;
end;

function TAtlasPaletteRows.Step(AFrom, ADelta: Integer): Integer;
var
  mRow, mDirection: Integer;
begin
  Result := AFrom;
  if (Count = 0) or (ADelta = 0) then
    Exit;
  mDirection := Sign(ADelta);
  mRow := EnsureRange(AFrom + ADelta, 0, Count - 1);
  while (mRow >= 0) and (mRow < Count) and not Selectable(mRow) do
    Inc(mRow, mDirection);
  // Am Rand nur Überschrift oder Status: zurück zur nächsten wählbaren Zeile.
  if (mRow < 0) or (mRow >= Count) then
  begin
    mRow := EnsureRange(AFrom + ADelta, 0, Count - 1);
    while (mRow >= 0) and (mRow < Count) and not Selectable(mRow) do
      Dec(mRow, mDirection);
  end;
  if (mRow >= 0) and (mRow < Count) then
    Result := mRow;
end;

class function TAtlasPaletteRows.ActionOf(ACtrl, AShift: Boolean): TAtlasPaletteAction;
begin
  if ACtrl then
    Result := TAtlasPaletteAction.Start
  else if AShift then
    Result := TAtlasPaletteAction.Browse
  else
    Result := TAtlasPaletteAction.Open;
end;

{ TAtlasCommandHistory }

constructor TAtlasCommandHistory.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TEntry>.Create;
  FKind := 'Verlauf der Befehlspalette';
end;

destructor TAtlasCommandHistory.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TAtlasCommandHistory.Executed(const AId: string);
var
  Entry: TEntry;
begin
  if not FEntries.TryGetValue(AId, Entry) then
    Entry := Default(TEntry);
  Inc(Entry.Count);
  Inc(FTick);
  Entry.Last := FTick;
  FEntries.AddOrSetValue(AId, Entry);
end;

function TAtlasCommandHistory.Boost(const AId: string): Integer;
var
  Entry: TEntry;
begin
  Result := 0;
  if not FEntries.TryGetValue(AId, Entry) then
    Exit;
  // Der zuletzt ausgeführte Befehl steht vorn (bis 70), Häufigkeit gibt bis 29 dazu.
  Result := Max(0, 70 - Integer(FTick - Entry.Last) * 10) + Min(29, Entry.Count * 3);
end;

function TAtlasCommandHistory.Parse(const AText: string): Boolean;
var
  Root: TJSONValue;
  Pair: TJSONPair;
  Values: TJSONArray;
  Entry: TEntry;
begin
  FEntries.Clear;
  FTick := 0;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    Result := Root is TJSONObject;
    if not Result then
      Exit;
    for Pair in TJSONObject(Root) do
    begin
      // Früher brach ein kurzes oder falsch getyptes Paar das Lesen mit einer Ausnahme ab.
      if not (Pair.JsonValue is TJSONArray) then
        Continue;
      Values := TJSONArray(Pair.JsonValue);
      if (Values.Count < 2) or not Values.Items[0].TryGetValue<Integer>(Entry.Count) or
        not Values.Items[1].TryGetValue<Int64>(Entry.Last) then
        Continue;
      FEntries.AddOrSetValue(Pair.JsonString.Value, Entry);
      FTick := Max(FTick, Entry.Last);
    end;
  finally
    Root.Free;
  end;
end;

function TAtlasCommandHistory.LoadFromFile(const AFileName: string): TAtlasDataLoad;
begin
  FEntries.Clear;
  FTick := 0;
  FKept := '';
  Result := TAtlasDataFile.Load(AFileName, FKind,
    function(const AText: string): Boolean
    begin
      Result := Parse(AText);
    end);
  if not TAtlasDataFile.Writable(Result) then
    FKept := AFileName;
  if Result <> TAtlasDataLoad.Loaded then
  begin
    FEntries.Clear;
    FTick := 0;
  end;
end;

function TAtlasCommandHistory.SaveToFile(const AFileName: string): Boolean;
var
  Root: TJSONObject;
  Pair: TPair<string, TEntry>;
begin
  Result := not SameFileName(AFileName, FKept);
  if not Result then
    Exit;
  Root := TJSONObject.Create;
  try
    for Pair in FEntries do
      Root.AddPair(Pair.Key, TJSONArray.Create.Add(Pair.Value.Count).Add(Pair.Value.Last));
    TAtlasDataFile.Write(AFileName, Root.ToJSON);
  finally
    Root.Free;
  end;
end;

/// <summary>Alle Zeichen von APattern kommen in AText in dieser Reihenfolge vor (Großschreibung egal).</summary>
function IsSubsequence(const APattern, AText: string): Boolean;
var
  PatternIndex, TextIndex: Integer;
begin
  PatternIndex := 1;
  for TextIndex := 1 to Length(AText) do
    if (PatternIndex <= Length(APattern)) and (UpCase(AText[TextIndex]) = UpCase(APattern[PatternIndex])) then
      Inc(PatternIndex);
  Result := PatternIndex > Length(APattern);
end;

const
  ScoreLoose = 100;

{ TAtlasCommandPalette }

class function TAtlasCommandPalette.CleanCaption(const ACaption: string): string;
var
  Index: Integer;
begin
  Result := '';
  Index := 1;
  while Index <= Length(ACaption) do
  begin
    if ACaption[Index] = '&' then
    begin
      if (Index < Length(ACaption)) and (ACaption[Index + 1] = '&') then
      begin
        Result := Result + '&';
        Inc(Index);
      end;
    end
    else
      Result := Result + ACaption[Index];
    Inc(Index);
  end;
  Result := Trim(Result);
  if Result.EndsWith('...') then
    Result := TrimRight(Copy(Result, 1, Length(Result) - 3))
  else if Result.EndsWith('…') then
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
end;

class function TAtlasCommandPalette.Order(const ACommands: TArray<TAtlasCommand>; const APattern: string;
  AHistory: TAtlasCommandHistory; AKeepOrder: Boolean): TArray<Integer>;
var
  Scores, Boosts: TArray<Integer>;
  Found: TList<Integer>;
  Index, Score: Integer;
  Commands: TArray<TAtlasCommand>;
begin
  Commands := ACommands;
  SetLength(Scores, Length(Commands));
  SetLength(Boosts, Length(Commands));
  Found := TList<Integer>.Create;
  try
    for Index := 0 to High(Commands) do
    begin
      Score := TAtlasCompletionMatcher.Score(APattern, Commands[Index].Caption);
      // Ersatzweise mit Menüpfad: "projekt erz" findet „Erzeugen“ unter „Projekt“.
      if (Score = TAtlasCompletionMatcher.NoMatch) and (Commands[Index].Path <> '') then
      begin
        Score := TAtlasCompletionMatcher.Score(APattern, Commands[Index].Path + ' ' + Commands[Index].Caption);
        if Score <> TAtlasCompletionMatcher.NoMatch then
          Score := Score div 2;
      end;
      if (Score = TAtlasCompletionMatcher.NoMatch) and IsSubsequence(APattern.Replace(' ', ''), Commands[Index].Caption) then
        Score := ScoreLoose;
      if Score = TAtlasCompletionMatcher.NoMatch then
        Continue;
      Scores[Index] := Score;
      if AHistory <> nil then
        Boosts[Index] := AHistory.Boost(Commands[Index].Id);
      Found.Add(Index);
    end;
    Found.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        if APattern = '' then
          Result := Boosts[B] - Boosts[A]
        else
          Result := (Scores[B] + Boosts[B]) - (Scores[A] + Boosts[A]);
        if (Result = 0) and not AKeepOrder then
          Result := CompareText(Commands[A].Caption, Commands[B].Caption);
        if Result = 0 then
          Result := A - B;
      end));
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

end.