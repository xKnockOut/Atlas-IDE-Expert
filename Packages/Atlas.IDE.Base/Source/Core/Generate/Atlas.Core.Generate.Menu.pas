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
  System.SysUtils,
  Atlas.Core.Generate.Contract;

type
  {$SCOPEDENUMS ON}
  TAtlasGenerateKind = (Slash, Snippet, Action);
  TAtlasGenerateArgument = (None, Optional, Required);
  {$SCOPEDENUMS OFF}

  /// <summary>Liegt in Atlas.Core.Generate.Contract; Alias für bestehende Nutzer.</summary>
  TAtlasGenerateGroup = Atlas.Core.Generate.Contract.TAtlasGenerateGroup;

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
    /// <summary>Weiterleitungen an TAtlasGenerateLists (Atlas.Core.Generate.Contract).</summary>
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
    cMaxCount = 20;
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
    cRecentCount = 3;
    cNoMatch = -1;
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
  Atlas.Text.Lines,
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

class function TAtlasGenerateOptions.Default: TAtlasGenerateOptions;
begin
  Result := Create('', '', True, True);
end;

class function TAtlasGenerateOptions.Create(const AGroups, AHidden: string; ARecentFirst,
  AShowCommandNames: Boolean): TAtlasGenerateOptions;
begin
  Result.Groups := ParseGroups(AGroups);
  Result.Hidden := TAtlasGenerateLists.Split(AHidden);
  Result.RecentFirst := ARecentFirst;
  Result.ShowCommandNames := AShowCommandNames;
end;

class function TAtlasGenerateOptions.GroupName(AGroup: TAtlasGenerateGroup): string;
begin
  Result := TAtlasGenerateLists.GroupName(AGroup);
end;

class function TAtlasGenerateOptions.TryParseGroup(const AName: string; out AGroup: TAtlasGenerateGroup): Boolean;
begin
  Result := TAtlasGenerateLists.TryParseGroup(AName, AGroup);
end;

class function TAtlasGenerateOptions.ParseGroups(const AText: string): TArray<TAtlasGenerateGroup>;
begin
  Result := TAtlasGenerateLists.ParseGroups(AText);
end;

class function TAtlasGenerateOptions.NormalizeGroups(const AText: string): string;
begin
  Result := TAtlasGenerateLists.NormalizeGroups(AText);
end;

class function TAtlasGenerateOptions.NormalizeHidden(const AText: string): string;
begin
  Result := TAtlasGenerateLists.NormalizeHidden(AText);
end;

class function TAtlasGenerateOptions.AddHidden(const AText, AId: string): string;
begin
  Result := NormalizeHidden(AText + ',' + AId);
end;

function TAtlasGenerateOptions.IsHidden(const AEntry: TAtlasGenerateEntry): Boolean;
var
  mItem: string;
begin
  Result := False;
  for mItem in Hidden do
  begin
    if SameText(mItem, AEntry.Id) or ((AEntry.Kind <> TAtlasGenerateKind.Action) and (SameText(mItem, AEntry.Name) or
      SameText(mItem, AEntry.CommandName))) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasGenerateOptions.HasGroup(AGroup: TAtlasGenerateGroup): Boolean;
var
  mGroup: TAtlasGenerateGroup;
begin
  Result := False;
  for mGroup in Groups do
  begin
    if mGroup = AGroup then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasGenerateOptions.Only(const AGroups: TArray<TAtlasGenerateGroup>): TAtlasGenerateOptions;
var
  mGroup, mWanted: TAtlasGenerateGroup;
begin
  Result := Self;
  Result.Groups := nil;
  for mGroup in Groups do
  begin
    for mWanted in AGroups do
    begin
      if mGroup = mWanted then
      begin
        Result.Groups := Result.Groups + [mGroup];
      end;
    end;
  end;
  // Ausdrücklich verlangt, aber in den Einstellungen nicht eingeschaltet: trotzdem zeigen.
  if Length(Result.Groups) = 0 then
  begin
    for mWanted in AGroups do
    begin
      if mWanted <> TAtlasGenerateGroup.Recent then
      begin
        Result.Groups := Result.Groups + [mWanted];
      end;
    end;
  end;
end;

{ TAtlasGenerateRecent }

procedure TAtlasGenerateRecent.Chosen(const AId: string);
var
  mIndex: Integer;
begin
  mIndex := IndexText(AId, FIds);
  if mIndex >= 0 then
  begin
    Delete(FIds, mIndex, 1);
  end;
  Insert(AId, FIds, 0);
  if Length(FIds) > cMaxCount then
  begin
    SetLength(FIds, cMaxCount);
  end;
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
  mLine: string;
begin
  FIds := nil;
  for mLine in TTextLines.SplitLines(AText) do
  begin
    if (Trim(mLine) <> '') and (IndexText(Trim(mLine), FIds) < 0) and (Length(FIds) < cMaxCount) then
    begin
      FIds := FIds + [Trim(mLine)];
    end;
  end;
end;

function TAtlasGenerateRecent.ToText: string;
begin
  Result := string.Join(#13#10, FIds);
end;

{ TAtlasGenerateMenu }

class function TAtlasGenerateMenu.Score(const AEntry: TAtlasGenerateEntry; const APattern: string): Integer;
var
  mPattern: string;
begin
  mPattern := Trim(APattern);
  if mPattern.StartsWith('/') then
  begin
    Delete(mPattern, 1, 1);
  end;
  if mPattern = '' then
  begin
    Exit(0);
  end;
  Result := Max(TAtlasCompletionMatcher.Score(mPattern, AEntry.Caption),
    TAtlasCompletionMatcher.Score(mPattern, AEntry.Name));
  if Result = TAtlasCompletionMatcher.cNoMatch then
  begin
    Result := cNoMatch;
  end;
end;

type
  /// <summary>Zustand von Rows: Punktzahlen, schon unter „Zuletzt“ gezeigte Einträge, Zeilen und nächste
  /// Ziffer.</summary>
  TRowBuilder = record
    Entries: TArray<TAtlasGenerateEntry>;
    Pattern: string;
    Scores: TArray<Integer>;
    InRecent: TArray<Boolean>;
    Rows: TArray<TAtlasGenerateRow>;
    Digit: Integer;
    class function Create(const AEntries: TArray<TAtlasGenerateEntry>; const AOptions: TAtlasGenerateOptions;
      const APattern: string): TRowBuilder; static;
    /// <summary>Zuletzt gewählt: nach Rang, höchstens RecentCount.</summary>
    function RecentOf(ARecent: TAtlasGenerateRecent): TArray<Integer>;
    function MembersOf(AGroup: TAtlasGenerateGroup): TArray<Integer>;
    /// <summary>Bei Eingabe die besten Treffer zuerst, sonst und bei Gleichstand die Reihenfolge der Liste.</summary>
    procedure SortByScore(var AMembers: TArray<Integer>);
    procedure AddGroup(AGroup: TAtlasGenerateGroup; const AMembers: TArray<Integer>);
  end;

class function TRowBuilder.Create(const AEntries: TArray<TAtlasGenerateEntry>;
  const AOptions: TAtlasGenerateOptions; const APattern: string): TRowBuilder;
var
  mIndex: Integer;
begin
  Result := Default(TRowBuilder);
  Result.Entries := AEntries;
  Result.Pattern := APattern;
  Result.Digit := 1;
  SetLength(Result.Scores, Length(AEntries));
  SetLength(Result.InRecent, Length(AEntries));
  for mIndex := 0 to High(AEntries) do
  begin
    Result.Scores[mIndex] := TAtlasGenerateMenu.cNoMatch;
    if not AOptions.IsHidden(AEntries[mIndex]) and AOptions.HasGroup(AEntries[mIndex].Group) then
    begin
      Result.Scores[mIndex] := TAtlasGenerateMenu.Score(AEntries[mIndex], APattern);
    end;
  end;
end;

function TRowBuilder.RecentOf(ARecent: TAtlasGenerateRecent): TArray<Integer>;
var
  mIndex, mOther, mSwap: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(Entries) do
  begin
    if (Scores[mIndex] = TAtlasGenerateMenu.cNoMatch) or (ARecent.Rank(Entries[mIndex].Id) < 0) then
    begin
      Continue;
    end;
    mOther := Length(Result);
    Result := Result + [mIndex];
    while (mOther > 0) and (ARecent.Rank(Entries[Result[mOther - 1]].Id) >
      ARecent.Rank(Entries[Result[mOther]].Id)) do
    begin
      mSwap := Result[mOther - 1];
      Result[mOther - 1] := Result[mOther];
      Result[mOther] := mSwap;
      Dec(mOther);
    end;
  end;
  if Length(Result) > TAtlasGenerateMenu.cRecentCount then
  begin
    SetLength(Result, TAtlasGenerateMenu.cRecentCount);
  end;
  for mIndex in Result do
  begin
    InRecent[mIndex] := True;
  end;
end;

function TRowBuilder.MembersOf(AGroup: TAtlasGenerateGroup): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(Entries) do
  begin
    if (Entries[mIndex].Group = AGroup) and (Scores[mIndex] <> TAtlasGenerateMenu.cNoMatch) and
      not InRecent[mIndex] then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

procedure TRowBuilder.SortByScore(var AMembers: TArray<Integer>);
var
  I, J, mSwap: Integer;
begin
  if Trim(Pattern) = '' then
  begin
    Exit;
  end;
  for I := 1 to High(AMembers) do
  begin
    J := I;
    while (J > 0) and (Scores[AMembers[J - 1]] < Scores[AMembers[J]]) do
    begin
      mSwap := AMembers[J - 1];
      AMembers[J - 1] := AMembers[J];
      AMembers[J] := mSwap;
      Dec(J);
    end;
  end;
end;

procedure TRowBuilder.AddGroup(AGroup: TAtlasGenerateGroup; const AMembers: TArray<Integer>);
var
  mMember: Integer;
  mRow: TAtlasGenerateRow;
begin
  if Length(AMembers) = 0 then
  begin
    Exit;
  end;
  mRow := Default(TAtlasGenerateRow);
  mRow.IsHeader := True;
  mRow.Group := AGroup;
  mRow.Entry := -1;
  Rows := Rows + [mRow];
  for mMember in AMembers do
  begin
    mRow := Default(TAtlasGenerateRow);
    mRow.Group := AGroup;
    mRow.Entry := mMember;
    if Digit <= 9 then
    begin
      mRow.Digit := Digit;
      Inc(Digit);
    end;
    Rows := Rows + [mRow];
  end;
end;
class function TAtlasGenerateMenu.Rows(const AEntries: TArray<TAtlasGenerateEntry>;
  const AOptions: TAtlasGenerateOptions; ARecent: TAtlasGenerateRecent;
  const APattern: string): TArray<TAtlasGenerateRow>;
var
  mBuilder: TRowBuilder;
  mGroup: TAtlasGenerateGroup;
  mRecent, mMembers: TArray<Integer>;
begin
  mBuilder := TRowBuilder.Create(AEntries, AOptions, APattern);
  mRecent := nil;
  if AOptions.RecentFirst and (ARecent <> nil) then
  begin
    mRecent := mBuilder.RecentOf(ARecent);
  end;
  mBuilder.AddGroup(TAtlasGenerateGroup.Recent, mRecent);
  for mGroup in AOptions.Groups do
  begin
    mMembers := mBuilder.MembersOf(mGroup);
    mBuilder.SortByScore(mMembers);
    mBuilder.AddGroup(mGroup, mMembers);
  end;
  Result := mBuilder.Rows;
end;

class function TAtlasGenerateMenu.RowOfDigit(const ARows: TArray<TAtlasGenerateRow>; ADigit: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if ADigit <= 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ARows) do
  begin
    if not ARows[mIndex].IsHeader and (ARows[mIndex].Digit = ADigit) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasGenerateMenu.FirstEntryRow(const ARows: TArray<TAtlasGenerateRow>): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ARows) do
  begin
    if not ARows[mIndex].IsHeader then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasGenerateMenu.StepRow(const ARows: TArray<TAtlasGenerateRow>; AFrom, ADelta: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := FirstEntryRow(ARows);
  if Result < 0 then
  begin
    Exit;
  end;
  if (AFrom < 0) or (AFrom > High(ARows)) then
  begin
    Exit;
  end;
  Result := AFrom;
  mIndex := AFrom + Sign(ADelta);
  while (mIndex >= 0) and (mIndex <= High(ARows)) do
  begin
    if not ARows[mIndex].IsHeader then
    begin
      Exit(mIndex);
    end;
    Inc(mIndex, Sign(ADelta));
  end;
end;

class function TAtlasGenerateMenu.FilterChoices(const AChoices: TArray<string>;
  const APattern: string): TArray<Integer>;
var
  mScores: TArray<Integer>;
  mIndex, mPosition, mSwap: Integer;
begin
  Result := nil;
  SetLength(mScores, Length(AChoices));
  for mIndex := 0 to High(AChoices) do
  begin
    mScores[mIndex] := 0;
    if Trim(APattern) <> '' then
    begin
      mScores[mIndex] := TAtlasCompletionMatcher.Score(Trim(APattern), AChoices[mIndex]);
    end;
    if mScores[mIndex] = TAtlasCompletionMatcher.cNoMatch then
    begin
      Continue;
    end;
    mPosition := Length(Result);
    Result := Result + [mIndex];
    while (mPosition > 0) and (mScores[Result[mPosition - 1]] < mScores[Result[mPosition]]) do
    begin
      mSwap := Result[mPosition - 1];
      Result[mPosition - 1] := Result[mPosition];
      Result[mPosition] := mSwap;
      Dec(mPosition);
    end;
  end;
end;

class function TAtlasGenerateMenu.JoinChoices(const AChoices: TArray<string>; const AChecked: TArray<Boolean>;
  const ASeparator: string; AAllMeansEmpty: Boolean): string;
var
  mIndex, mCount: Integer;
  mChosen: TArray<string>;
begin
  mChosen := nil;
  mCount := 0;
  for mIndex := 0 to High(AChoices) do
  begin
    if (mIndex <= High(AChecked)) and AChecked[mIndex] then
    begin
      mChosen := mChosen + [AChoices[mIndex]];
      Inc(mCount);
    end;
  end;
  if AAllMeansEmpty and ((mCount = 0) or (mCount = Length(AChoices))) then
  begin
    Exit('');
  end;
  Result := string.Join(ASeparator, mChosen);
end;

class function TAtlasGenerateMenu.SelectionEndLine(AStartLine, AEndLine, AEndCharacter: Integer;
  AHasSelection: Boolean): Integer;
begin
  if not AHasSelection then
  begin
    Exit(-1);
  end;
  Result := AEndLine;
  if (AEndCharacter = 0) and (AEndLine > AStartLine) then
  begin
    Result := AEndLine - 1;
  end;
end;

end.
