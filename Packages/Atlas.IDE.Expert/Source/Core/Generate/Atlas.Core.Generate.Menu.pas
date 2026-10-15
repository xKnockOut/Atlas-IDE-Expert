unit Atlas.Core.Generate.Menu;

// Erzeugen-Menü (#719), Teil ohne VCL, Open Tools API und JSON: Einträge,
// Optionen aus den Einstellungen, zuletzt gewählte Einträge und die Zeilen
// des Fensters.
// Einträge kommen aus drei Quellen (Atlas.Core.Generate.Protocol): Schnell-
// befehle des Servers, die an der Stelle passen (Ortsregel aus #293), Code-
// Vorlagen mit passendem Kontext (#51 samt Live Templates der IDE #487 und
// eigenen Vorlagen #665) und Code-Aktionen der Art refactor.
// Gruppen: Erzeugen, Umschließen (der Server liefert sie nur mit Markierung)
// und Vorlagen in der Reihenfolge aus keys.generateMenu.groups; fehlt eine
// Gruppe dort, fehlt sie im Menü. Davor höchstens drei zuletzt gewählte
// Einträge (keys.generateMenu.recentFirst), die dann nicht noch einmal in
// ihrer Gruppe stehen. Ausgeblendet (keys.generateMenu.hidden) wird nach
// Kennung ("slash:ctor", "snippet:tryf", "action:Titel") oder Name ("/ctor",
// "ctor", "tryf"). Tippen filtert unscharf wie die Vervollständigung (#229)
// über Beschriftung und Namen; in jeder Gruppe stehen dann die besten
// Treffer oben. Die ersten neun Einträge tragen die Ziffern 1–9.
// Mit Only (für #759 „Neu mit Atlas“) zeigt das Menü nur die genannten Gruppen.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasGenerateKind = (Slash, Snippet, Action);
  /// <summary>Recent ist keine eigene Herkunft, nur die Gruppe „Zuletzt gewählt“ oben.</summary>
  TAtlasGenerateGroup = (Recent, Generate, Surround, Templates);
  TAtlasGenerateArgument = (None, Optional, Required);
  {$SCOPEDENUMS OFF}

  TAtlasGenerateEntry = record
    Kind: TAtlasGenerateKind;
    /// <summary>Gruppe nach Herkunft (nie Recent).</summary>
    Group: TAtlasGenerateGroup;
    /// <summary>Schnellbefehl ohne "/", Kürzel der Vorlage bzw. Titel der Code-Aktion.</summary>
    Name: string;
    Caption: string;
    /// <summary>Kurzbeschreibung; bei Schnellbefehlen die des Servers.</summary>
    Detail: string;
    /// <summary>Beispiel des Schnellbefehls, z. B. "/ctor owner"; Hinweis für die Eingabe des Arguments.</summary>
    Example: string;
    Argument: TAtlasGenerateArgument;
    /// <summary>Der Server liefert mögliche Argumente (Felder für /ctor, Methoden für /override …).</summary>
    HasChoices: Boolean;
    /// <summary>Mehrere Argumente wählbar, verbunden mit Separator.</summary>
    Multi: Boolean;
    Separator: string;
    /// <summary>Index der Vorlage bzw. Code-Aktion in der Liste des Aufrufers; -1 bei Schnellbefehlen.</summary>
    Source: Integer;
    class function Create(AKind: TAtlasGenerateKind; AGroup: TAtlasGenerateGroup; const AName,
      ACaption: string): TAtlasGenerateEntry; static;
    /// <summary>"slash:ctor", "snippet:tryf" bzw. "action:Titel"; für Verlauf und Ausblenden.</summary>
    function Id: string;
    /// <summary>"/ctor" bei Schnellbefehlen, das Kürzel bei Vorlagen, '' bei Code-Aktionen.</summary>
    function CommandName: string;
    /// <summary>Erst Argument bzw. Auswahl erfragen, dann ausführen?</summary>
    function NeedsStep: Boolean;
  end;

  TAtlasGenerateOptions = record
    /// <summary>Sichtbare Gruppen in ihrer Reihenfolge, ohne Recent.</summary>
    Groups: TArray<TAtlasGenerateGroup>;
    Hidden: TArray<string>;
    RecentFirst: Boolean;
    ShowCommandNames: Boolean;
    /// <summary>generate, surround, templates; Zuletzt gewählt und Befehlsnamen an.</summary>
    class function Default: TAtlasGenerateOptions; static;
    /// <summary>Aus den Einstellungen: AGroups und AHidden als kommagetrennte Listen.</summary>
    class function Create(const AGroups, AHidden: string; ARecentFirst,
      AShowCommandNames: Boolean): TAtlasGenerateOptions; static;
    /// <summary>generate, surround, templates bzw. recent.</summary>
    class function GroupName(AGroup: TAtlasGenerateGroup): string; static;
    class function TryParseGroup(const AName: string; out AGroup: TAtlasGenerateGroup): Boolean; static;
    /// <summary>Bekannte Gruppen ohne Doppelte; leer bzw. ohne bekannte Gruppe: die Vorgabe.</summary>
    class function ParseGroups(const AText: string): TArray<TAtlasGenerateGroup>; static;
    /// <summary>Für die Einstellung: "generate,surround,templates" in der gewählten Reihenfolge.</summary>
    class function NormalizeGroups(const AText: string): string; static;
    /// <summary>Für die Einstellung: getrimmt, ohne leere und doppelte Einträge, mit ", " verbunden.</summary>
    class function NormalizeHidden(const AText: string): string; static;
    /// <summary>AText mit AId dazu (Entf im Menü).</summary>
    class function AddHidden(const AText, AId: string): string; static;
    function IsHidden(const AEntry: TAtlasGenerateEntry): Boolean;
    function HasGroup(AGroup: TAtlasGenerateGroup): Boolean;
    /// <summary>Nur die Gruppen aus AGroups, in der eingestellten Reihenfolge; fehlen alle, in der von AGroups
    /// (#759: „Neu mit Atlas“ öffnet das Menü gefiltert).</summary>
    function Only(const AGroups: TArray<TAtlasGenerateGroup>): TAtlasGenerateOptions;
  end;

  /// <summary>Zuletzt gewählte Einträge, neueste zuerst (höchstens MaxCount).</summary>
  TAtlasGenerateRecent = class
  public const
    MaxCount = 20;
  private
    FIds: TArray<string>;
  public
    procedure Chosen(const AId: string);
    /// <summary>0 = zuletzt gewählt; -1 = nie.</summary>
    function Rank(const AId: string): Integer;
    function Ids: TArray<string>;
    procedure Clear;
    /// <summary>Eine Kennung je Zeile; leere Zeilen und Doppelte entfallen.</summary>
    procedure LoadFromText(const AText: string);
    function ToText: string;
  end;

  /// <summary>Zeile im Fenster: Gruppenkopf oder Eintrag.</summary>
  TAtlasGenerateRow = record
    IsHeader: Boolean;
    Group: TAtlasGenerateGroup;
    /// <summary>Index in den Einträgen; -1 bei Köpfen.</summary>
    Entry: Integer;
    /// <summary>1–9 für die ersten neun Einträge, sonst 0.</summary>
    Digit: Integer;
  end;

  TAtlasGenerateMenu = class
  public const
    RecentCount = 3;
    NoMatch = -1;
  public
    /// <summary>Punktzahl von AEntry für APattern (Beschriftung oder Name, "/" vorn egal); NoMatch, wenn nichts
    /// passt. Leeres Muster passt immer.</summary>
    class function Score(const AEntry: TAtlasGenerateEntry; const APattern: string): Integer; static;
    /// <summary>Zeilen des Fensters: Köpfe und Einträge in Gruppen nach AOptions, gefiltert nach APattern.
    /// ARecent darf nil sein.</summary>
    class function Rows(const AEntries: TArray<TAtlasGenerateEntry>; const AOptions: TAtlasGenerateOptions;
      ARecent: TAtlasGenerateRecent; const APattern: string): TArray<TAtlasGenerateRow>; static;
    /// <summary>Zeile mit der Ziffer ADigit; -1 ohne.</summary>
    class function RowOfDigit(const ARows: TArray<TAtlasGenerateRow>; ADigit: Integer): Integer; static;
    /// <summary>Nächste Eintragszeile ab AFrom in Richtung ADelta (+1/-1), Köpfe übersprungen; bleibt am Rand
    /// stehen. -1 ohne Einträge.</summary>
    class function StepRow(const ARows: TArray<TAtlasGenerateRow>; AFrom, ADelta: Integer): Integer; static;
    class function FirstEntryRow(const ARows: TArray<TAtlasGenerateRow>): Integer; static;
    /// <summary>Indizes der Auswahl (Felder, Methoden …), die zu APattern passen; beste zuerst, sonst in der
    /// Reihenfolge der Liste.</summary>
    class function FilterChoices(const AChoices: TArray<string>; const APattern: string): TArray<Integer>; static;
    /// <summary>Gewählte Werte mit ASeparator verbunden; '' wenn alle oder keiner gewählt sind und AAllMeansEmpty
    /// (bei /ctor bedeutet „ohne Argument“ alle Felder).</summary>
    class function JoinChoices(const AChoices: TArray<string>; const AChecked: TArray<Boolean>;
      const ASeparator: string; AAllMeansEmpty: Boolean): string; static;
    /// <summary>Letzte Zeile der Markierung für den Server: Endet sie am Anfang einer Zeile (ganze Zeilen
    /// markiert), zählt diese nicht mit. -1 ohne Markierung.</summary>
    class function SelectionEndLine(AStartLine, AEndLine, AEndCharacter: Integer;
      AHasSelection: Boolean): Integer; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Core.Completion.Matching;

{ TAtlasGenerateEntry }

class function TAtlasGenerateEntry.Create(AKind: TAtlasGenerateKind; AGroup: TAtlasGenerateGroup; const AName,
  ACaption: string): TAtlasGenerateEntry;
begin
  Result := Default(TAtlasGenerateEntry);
  Result.Kind := AKind;
  Result.Group := AGroup;
  Result.Name := AName;
  Result.Caption := ACaption;
  Result.Source := -1;
end;

function TAtlasGenerateEntry.Id: string;
begin
  case Kind of
    TAtlasGenerateKind.Slash:
      Result := 'slash:' + Name;
    TAtlasGenerateKind.Snippet:
      Result := 'snippet:' + Name;
  else
    Result := 'action:' + Name;
  end;
end;

function TAtlasGenerateEntry.CommandName: string;
begin
  case Kind of
    TAtlasGenerateKind.Slash:
      Result := '/' + Name;
    TAtlasGenerateKind.Snippet:
      Result := Name;
  else
    Result := '';
  end;
end;

function TAtlasGenerateEntry.NeedsStep: Boolean;
begin
  Result := (Kind = TAtlasGenerateKind.Slash) and ((Argument = TAtlasGenerateArgument.Required) or HasChoices);
end;

{ TAtlasGenerateOptions }

const
  DefaultGroups: array[0..2] of TAtlasGenerateGroup = (TAtlasGenerateGroup.Generate, TAtlasGenerateGroup.Surround,
    TAtlasGenerateGroup.Templates);

function SplitList(const AText: string): TArray<string>;
var
  Item: string;
begin
  Result := nil;
  for Item in AText.Split([',', ';', #10]) do
    if Trim(Item) <> '' then
      Result := Result + [Trim(Item)];
end;

class function TAtlasGenerateOptions.Default: TAtlasGenerateOptions;
begin
  Result := Create('', '', True, True);
end;

class function TAtlasGenerateOptions.Create(const AGroups, AHidden: string; ARecentFirst,
  AShowCommandNames: Boolean): TAtlasGenerateOptions;
begin
  Result.Groups := ParseGroups(AGroups);
  Result.Hidden := SplitList(AHidden);
  Result.RecentFirst := ARecentFirst;
  Result.ShowCommandNames := AShowCommandNames;
end;

class function TAtlasGenerateOptions.GroupName(AGroup: TAtlasGenerateGroup): string;
begin
  case AGroup of
    TAtlasGenerateGroup.Generate:
      Result := 'generate';
    TAtlasGenerateGroup.Surround:
      Result := 'surround';
    TAtlasGenerateGroup.Templates:
      Result := 'templates';
  else
    Result := 'recent';
  end;
end;

class function TAtlasGenerateOptions.TryParseGroup(const AName: string; out AGroup: TAtlasGenerateGroup): Boolean;
var
  Group: TAtlasGenerateGroup;
begin
  for Group := Low(TAtlasGenerateGroup) to High(TAtlasGenerateGroup) do
    if SameText(Trim(AName), GroupName(Group)) then
    begin
      AGroup := Group;
      Exit(True);
    end;
  AGroup := TAtlasGenerateGroup.Generate;
  Result := False;
end;

class function TAtlasGenerateOptions.ParseGroups(const AText: string): TArray<TAtlasGenerateGroup>;
var
  Item: string;
  Group, Known: TAtlasGenerateGroup;
  Seen: Boolean;
begin
  Result := nil;
  for Item in SplitList(AText) do
  begin
    // "recent" ist keine Gruppe der Liste; dafür gibt es recentFirst.
    if not TryParseGroup(Item, Group) or (Group = TAtlasGenerateGroup.Recent) then
      Continue;
    Seen := False;
    for Known in Result do
      if Known = Group then
        Seen := True;
    if not Seen then
      Result := Result + [Group];
  end;
  if Length(Result) = 0 then
    for Group in DefaultGroups do
      Result := Result + [Group];
end;

class function TAtlasGenerateOptions.NormalizeGroups(const AText: string): string;
var
  Group: TAtlasGenerateGroup;
begin
  Result := '';
  for Group in ParseGroups(AText) do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + GroupName(Group);
  end;
end;

class function TAtlasGenerateOptions.NormalizeHidden(const AText: string): string;
var
  Item: string;
  Items: TArray<string>;
begin
  Items := nil;
  for Item in SplitList(AText) do
    if IndexText(Item, Items) < 0 then
      Items := Items + [Item];
  Result := string.Join(', ', Items);
end;

class function TAtlasGenerateOptions.AddHidden(const AText, AId: string): string;
begin
  Result := NormalizeHidden(AText + ',' + AId);
end;

function TAtlasGenerateOptions.IsHidden(const AEntry: TAtlasGenerateEntry): Boolean;
var
  Item: string;
begin
  Result := False;
  for Item in Hidden do
    if SameText(Item, AEntry.Id) or ((AEntry.Kind <> TAtlasGenerateKind.Action) and (SameText(Item, AEntry.Name) or
      SameText(Item, AEntry.CommandName))) then
      Exit(True);
end;

function TAtlasGenerateOptions.HasGroup(AGroup: TAtlasGenerateGroup): Boolean;
var
  Group: TAtlasGenerateGroup;
begin
  Result := False;
  for Group in Groups do
    if Group = AGroup then
      Exit(True);
end;

function TAtlasGenerateOptions.Only(const AGroups: TArray<TAtlasGenerateGroup>): TAtlasGenerateOptions;
var
  Group, Wanted: TAtlasGenerateGroup;
begin
  Result := Self;
  Result.Groups := nil;
  for Group in Groups do
    for Wanted in AGroups do
      if Group = Wanted then
        Result.Groups := Result.Groups + [Group];
  // Ausdrücklich verlangt, aber in den Einstellungen nicht eingeschaltet: trotzdem zeigen.
  if Length(Result.Groups) = 0 then
    for Wanted in AGroups do
      if Wanted <> TAtlasGenerateGroup.Recent then
        Result.Groups := Result.Groups + [Wanted];
end;

{ TAtlasGenerateRecent }

procedure TAtlasGenerateRecent.Chosen(const AId: string);
var
  Index: Integer;
begin
  Index := IndexText(AId, FIds);
  if Index >= 0 then
    Delete(FIds, Index, 1);
  Insert(AId, FIds, 0);
  if Length(FIds) > MaxCount then
    SetLength(FIds, MaxCount);
end;

function TAtlasGenerateRecent.Rank(const AId: string): Integer;
begin
  Result := IndexText(AId, FIds);
end;

function TAtlasGenerateRecent.Ids: TArray<string>;
begin
  Result := Copy(FIds);
end;

procedure TAtlasGenerateRecent.Clear;
begin
  FIds := nil;
end;

procedure TAtlasGenerateRecent.LoadFromText(const AText: string);
var
  Line: string;
begin
  FIds := nil;
  for Line in AText.Replace(#13, '').Split([#10]) do
    if (Trim(Line) <> '') and (IndexText(Trim(Line), FIds) < 0) and (Length(FIds) < MaxCount) then
      FIds := FIds + [Trim(Line)];
end;

function TAtlasGenerateRecent.ToText: string;
begin
  Result := string.Join(#13#10, FIds);
end;

{ TAtlasGenerateMenu }

class function TAtlasGenerateMenu.Score(const AEntry: TAtlasGenerateEntry; const APattern: string): Integer;
var
  Pattern: string;
begin
  Pattern := Trim(APattern);
  if Pattern.StartsWith('/') then
    Delete(Pattern, 1, 1);
  if Pattern = '' then
    Exit(0);
  Result := Max(TAtlasCompletionMatcher.Score(Pattern, AEntry.Caption),
    TAtlasCompletionMatcher.Score(Pattern, AEntry.Name));
  if Result = TAtlasCompletionMatcher.NoMatch then
    Result := NoMatch;
end;

class function TAtlasGenerateMenu.Rows(const AEntries: TArray<TAtlasGenerateEntry>;
  const AOptions: TAtlasGenerateOptions; ARecent: TAtlasGenerateRecent;
  const APattern: string): TArray<TAtlasGenerateRow>;
var
  Scores: TArray<Integer>;
  InRecent: TArray<Boolean>;
  Recent, Members: TArray<Integer>;
  Index, Other, Digit, Swap: Integer;
  Group: TAtlasGenerateGroup;
  Row: TAtlasGenerateRow;
  Rows_: TArray<TAtlasGenerateRow>;

  procedure AddGroup(AGroup: TAtlasGenerateGroup; const AMembers: TArray<Integer>);
  var
    Member: Integer;
  begin
    if Length(AMembers) = 0 then
      Exit;
    Row := Default(TAtlasGenerateRow);
    Row.IsHeader := True;
    Row.Group := AGroup;
    Row.Entry := -1;
    Rows_ := Rows_ + [Row];
    for Member in AMembers do
    begin
      Row := Default(TAtlasGenerateRow);
      Row.Group := AGroup;
      Row.Entry := Member;
      if Digit <= 9 then
      begin
        Row.Digit := Digit;
        Inc(Digit);
      end;
      Rows_ := Rows_ + [Row];
    end;
  end;

  /// <summary>Bei Eingabe die besten Treffer zuerst, sonst und bei Gleichstand die Reihenfolge der Liste.</summary>
  procedure SortByScore(var AMembers: TArray<Integer>);
  var
    I, J: Integer;
  begin
    if Trim(APattern) = '' then
      Exit;
    for I := 1 to High(AMembers) do
    begin
      J := I;
      while (J > 0) and (Scores[AMembers[J - 1]] < Scores[AMembers[J]]) do
      begin
        Swap := AMembers[J - 1];
        AMembers[J - 1] := AMembers[J];
        AMembers[J] := Swap;
        Dec(J);
      end;
    end;
  end;

begin
  Rows_ := nil;
  SetLength(Scores, Length(AEntries));
  SetLength(InRecent, Length(AEntries));
  for Index := 0 to High(AEntries) do
  begin
    Scores[Index] := NoMatch;
    if AOptions.IsHidden(AEntries[Index]) or not AOptions.HasGroup(AEntries[Index].Group) then
      Continue;
    Scores[Index] := Score(AEntries[Index], APattern);
  end;
  // Zuletzt gewählt: nach Rang, höchstens RecentCount.
  Recent := nil;
  if AOptions.RecentFirst and (ARecent <> nil) then
  begin
    for Index := 0 to High(AEntries) do
      if (Scores[Index] <> NoMatch) and (ARecent.Rank(AEntries[Index].Id) >= 0) then
      begin
        Other := Length(Recent);
        Recent := Recent + [Index];
        while (Other > 0) and (ARecent.Rank(AEntries[Recent[Other - 1]].Id) >
          ARecent.Rank(AEntries[Recent[Other]].Id)) do
        begin
          Swap := Recent[Other - 1];
          Recent[Other - 1] := Recent[Other];
          Recent[Other] := Swap;
          Dec(Other);
        end;
      end;
    if Length(Recent) > RecentCount then
      SetLength(Recent, RecentCount);
    for Index in Recent do
      InRecent[Index] := True;
  end;
  Digit := 1;
  AddGroup(TAtlasGenerateGroup.Recent, Recent);
  for Group in AOptions.Groups do
  begin
    Members := nil;
    for Index := 0 to High(AEntries) do
      if (AEntries[Index].Group = Group) and (Scores[Index] <> NoMatch) and not InRecent[Index] then
        Members := Members + [Index];
    SortByScore(Members);
    AddGroup(Group, Members);
  end;
  Result := Rows_;
end;

class function TAtlasGenerateMenu.RowOfDigit(const ARows: TArray<TAtlasGenerateRow>; ADigit: Integer): Integer;
var
  Index: Integer;
begin
  Result := -1;
  if ADigit <= 0 then
    Exit;
  for Index := 0 to High(ARows) do
    if not ARows[Index].IsHeader and (ARows[Index].Digit = ADigit) then
      Exit(Index);
end;

class function TAtlasGenerateMenu.FirstEntryRow(const ARows: TArray<TAtlasGenerateRow>): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(ARows) do
    if not ARows[Index].IsHeader then
      Exit(Index);
end;

class function TAtlasGenerateMenu.StepRow(const ARows: TArray<TAtlasGenerateRow>; AFrom, ADelta: Integer): Integer;
var
  Index: Integer;
begin
  Result := FirstEntryRow(ARows);
  if Result < 0 then
    Exit;
  if (AFrom < 0) or (AFrom > High(ARows)) then
    Exit;
  Result := AFrom;
  Index := AFrom + Sign(ADelta);
  while (Index >= 0) and (Index <= High(ARows)) do
  begin
    if not ARows[Index].IsHeader then
      Exit(Index);
    Inc(Index, Sign(ADelta));
  end;
end;

class function TAtlasGenerateMenu.FilterChoices(const AChoices: TArray<string>;
  const APattern: string): TArray<Integer>;
var
  Scores: TArray<Integer>;
  Index, Position, Swap: Integer;
begin
  Result := nil;
  SetLength(Scores, Length(AChoices));
  for Index := 0 to High(AChoices) do
  begin
    Scores[Index] := 0;
    if Trim(APattern) <> '' then
      Scores[Index] := TAtlasCompletionMatcher.Score(Trim(APattern), AChoices[Index]);
    if Scores[Index] = TAtlasCompletionMatcher.NoMatch then
      Continue;
    Position := Length(Result);
    Result := Result + [Index];
    while (Position > 0) and (Scores[Result[Position - 1]] < Scores[Result[Position]]) do
    begin
      Swap := Result[Position - 1];
      Result[Position - 1] := Result[Position];
      Result[Position] := Swap;
      Dec(Position);
    end;
  end;
end;

class function TAtlasGenerateMenu.JoinChoices(const AChoices: TArray<string>; const AChecked: TArray<Boolean>;
  const ASeparator: string; AAllMeansEmpty: Boolean): string;
var
  Index, Count: Integer;
  Chosen: TArray<string>;
begin
  Chosen := nil;
  Count := 0;
  for Index := 0 to High(AChoices) do
    if (Index <= High(AChecked)) and AChecked[Index] then
    begin
      Chosen := Chosen + [AChoices[Index]];
      Inc(Count);
    end;
  if AAllMeansEmpty and ((Count = 0) or (Count = Length(AChoices))) then
    Exit('');
  Result := string.Join(ASeparator, Chosen);
end;

class function TAtlasGenerateMenu.SelectionEndLine(AStartLine, AEndLine, AEndCharacter: Integer;
  AHasSelection: Boolean): Integer;
begin
  if not AHasSelection then
    Exit(-1);
  Result := AEndLine;
  if (AEndCharacter = 0) and (AEndLine > AStartLine) then
    Result := AEndLine - 1;
end;

end.
