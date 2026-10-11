unit Atlas.Core.Commands.Palette;

// Befehlspalette (#502), Teil ohne Open Tools API: Befehle aus IDE-Aktionen
// und Atlas, Verlauf je Benutzer und Rangfolge. Ausgewählt wird wie in der
// Vervollständigung (#229: genauer Name, Anfang, Wortanfänge, Teilfolge),
// gegen die Beschriftung und ersatzweise „Menüpfad Beschriftung“; zuletzt
// eine einfache Teilfolge ohne Wortgrenzen („bpj“ → „Build Project“), weil
// Befehle aus mehreren Wörtern bestehen. Zuletzt und
// häufig genutzte Befehle bekommen einen Zuschlag unter 100 Punkten; ohne
// Eingabe stehen sie oben, danach alphabetisch.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

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
  public
    constructor Create;
    destructor Destroy; override;
    procedure Executed(const AId: string);
    /// <summary>Zuschlag 0..99: zuletzt ausgeführt am meisten, Häufigkeit dazu.</summary>
    function Boost(const AId: string): Integer;
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
  end;

  TAtlasCommandPalette = class
  public
    /// <summary>Indizes der passenden Befehle, beste zuerst.</summary>
    class function Order(const ACommands: TArray<TAtlasCommand>; const APattern: string;
      AHistory: TAtlasCommandHistory): TArray<Integer>; static;
    /// <summary>Beschriftung ohne Kürzelzeichen: "&amp;Datei" → "Datei", "&amp;&amp;" → "&amp;", "..." am Ende weg.</summary>
    class function CleanCaption(const ACaption: string): string; static;
  end;

implementation

uses
  System.Math,
  System.IOUtils,
  System.JSON,
  System.Generics.Defaults,
  Atlas.Core.Completion.Matching;

{ TAtlasCommandHistory }

constructor TAtlasCommandHistory.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TEntry>.Create;
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

procedure TAtlasCommandHistory.LoadFromFile(const AFileName: string);
var
  Root: TJSONValue;
  Pair: TJSONPair;
  Entry: TEntry;
begin
  FEntries.Clear;
  FTick := 0;
  if not TFile.Exists(AFileName) then
    Exit;
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  try
    if not (Root is TJSONObject) then
      Exit;
    for Pair in TJSONObject(Root) do
      if Pair.JsonValue is TJSONArray then
      begin
        Entry.Count := TJSONArray(Pair.JsonValue).Items[0].GetValue<Integer>;
        Entry.Last := TJSONArray(Pair.JsonValue).Items[1].GetValue<Int64>;
        FEntries.AddOrSetValue(Pair.JsonString.Value, Entry);
        FTick := Max(FTick, Entry.Last);
      end;
  finally
    Root.Free;
  end;
end;

procedure TAtlasCommandHistory.SaveToFile(const AFileName: string);
var
  Root: TJSONObject;
  Pair: TPair<string, TEntry>;
begin
  Root := TJSONObject.Create;
  try
    for Pair in FEntries do
      Root.AddPair(Pair.Key, TJSONArray.Create.Add(Pair.Value.Count).Add(Pair.Value.Last));
    ForceDirectories(ExtractFileDir(AFileName));
    TFile.WriteAllText(AFileName, Root.ToJSON, TEncoding.UTF8);
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
  AHistory: TAtlasCommandHistory): TArray<Integer>;
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
        if Result = 0 then
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