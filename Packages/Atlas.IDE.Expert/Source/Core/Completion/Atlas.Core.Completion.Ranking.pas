unit Atlas.Core.Completion.Ranking;

// Reihenfolge der Liste (#229, #418, #419, #422), ohne Fenster:
//   - Treffer nach Güte (TAtlasCompletionMatcher), dazu ein Lernzuschlag unter
//     100 Punkten, damit ein besserer Treffer immer vor einem gelernten bleibt.
//   - Ohne getipptes Präfix und mit GroupInherited: eigene Member zuerst, dann
//     je Vorfahr eine Gruppe mit Überschrift (in der Reihenfolge ein -1 vor dem
//     ersten Eintrag der Gruppe). Mit Präfix keine Überschriften; bei gleicher
//     Güte steht der eigene Member vor dem geerbten.
//   - Chips: Einschränkung auf eine Art (Methoden, Eigenschaften, ...).
//   - Erwarteter Typ (#417, #444): passende Einträge oben, darunter die
//     übrigen, je mit Überschrift, auch mit Präfix. Innerhalb der Gruppe wie
//     oben. Aktionen („Neue Methode …“) passen immer und stehen zuletzt.
//   - Werte einer erwarteten Aufzählung (#448) stehen in der passenden Gruppe
//     zuerst, ohne Präfix in Deklarationsreihenfolge (Ordinal), auch vor
//     Gelerntem.
//   - Angeheftete Einträge („Alle Werte einfügen“, #449) passen immer. Ohne
//     Präfix stehen sie ganz oben; mit Präfix hinter den Treffern, damit Enter
//     nach "skC" den Wert übernimmt und nicht alle Zweige.
//   - Deklarationen eines unbekannten Namens (#471) stehen als Aktionen am
//     Ende, unter der Überschrift UnknownHeader („Name ist unbekannt“).
//   - Hinweise „n Methoden von I fehlen“ (#466) passen immer und stehen ganz oben, auch mit Präfix; der
//     Controller wählt sie nicht vor.
//   - Komponenten aus dem Formular (#455) stehen als eigene Gruppe mit Überschrift („Formular frmMain“) vor allen
//     übrigen Bezeichnern. Passt eine nur über ihren Typ ("button" → btnSave: TButton), hat der Server sie schon
//     gefiltert; sie bleibt sichtbar und steht hinter den Namenstreffern.
//   - Sender mit Typumwandlung (#480): eine Überschrift „Sender ist TButton · btnSave, btnLoad“ über der Liste.
//   - uses-Abschnitt (#469, Item.UsesGroup): Projekt-Units vor RTL/VCL vor Drittanbietern, je Gruppe eine
//     Überschrift.
//   - Favoriten (#458, Item.Favorite): vor allen anderen Gruppen, auch vor Hinweisen und Formularkomponenten,
//     unabhängig von Lernen und Rang, aber nur, wenn sie zum getippten Präfix passen. Ohne Überschrift; die
//     Gruppen danach beginnen wie am Anfang der Liste.
//   - Typkonvertierung (#490): Ein Umwandlungseintrag (Conversion) steht direkt über seinem Original
//     (ConvertFrom) und nur, wenn das Original sichtbar ist; er zählt weder zu Gruppen noch zum Rest.
//   - Rest der Liste (#497, TAtlasListMode): Filter zeigt nur Treffer. All hängt mit Präfix die übrigen Einträge
//     des Kontexts ohne Überschrift hinter die Treffer, Rest unter der Überschrift RestHeader („Weitere
//     Einträge“, gedämpft). Beide in Rang- und Namensfolge, ohne Aktionen, Hinweise und Tippfehler-Treffer,
//     vor der Gruppe des unbekannten Namens.

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Contract;

{$SCOPEDENUMS ON}

type
  TAtlasChip = (All, Methods, Properties, Events, Types, Snippets);

  TAtlasChipCounts = array[TAtlasChip] of Integer;

  /// <summary>Was mit Präfix außer den Treffern sichtbar bleibt (#497).</summary>
  TAtlasListMode = (Filter, All, Rest);

  /// <summary>Wo der Listenmodus gilt (#497): nur in Mitgliederlisten nach "." oder überall.</summary>
  TAtlasListScope = (Members, Everywhere);

  /// <summary>Schreibweise der Listenmodi in den Einstellungen.</summary>
  TAtlasListModes = class
  public const
    ModeNames: array[TAtlasListMode] of string = ('filter', 'all', 'rest');
    ScopeNames: array[TAtlasListScope] of string = ('members', 'everywhere');
  public
    /// <summary>Modus zu AName (ohne Groß-/Kleinschreibung); Filter bei Unbekanntem.</summary>
    class function ModeOf(const AName: string): TAtlasListMode; static;
    /// <summary>Geltungsbereich zu AName; Members bei Unbekanntem.</summary>
    class function ScopeOf(const AName: string): TAtlasListScope; static;
  end;

  /// <summary>Lernzuschlag 0..99 je Eintragsindex.</summary>
  TAtlasBoostFunc = reference to function(AIndex: Integer): Integer;

  TAtlasRankOptions = record
    GroupInherited: Boolean;
    Chip: TAtlasChip;
    Boost: TAtlasBoostFunc;
    /// <summary>Übrige Einträge mit Präfix (#497); Filter = nur Treffer.</summary>
    ListMode: TAtlasListMode;
    class function Defaults: TAtlasRankOptions; static;
  end;

  TAtlasRanking = class
  public const
    /// <summary>Markiert in der Reihenfolge eine Gruppenüberschrift vor dem nächsten Eintrag.</summary>
    Header = -1;
    /// <summary>Überschrift „Meintest du“ vor den Tippfehler-Treffern (#485).</summary>
    TypoHeader = -2;
    /// <summary>Überschrift „Name ist unbekannt“ vor den Deklarationen (#471).</summary>
    UnknownHeader = -3;
    /// <summary>Überschrift „Weitere Einträge“ vor dem gedämpften Rest (#497, TAtlasListMode.Rest).</summary>
    RestHeader = -4;
    /// <summary>Höchstens so viele Tippfehler-Treffer; nur bei weniger regulären als MinRegular.</summary>
    MaxTypos = 5;
    MinRegular = 3;
  public
    /// <summary>Art des Eintrags für die Chips; nie All.</summary>
    class function ChipOf(const AItem: TAtlasCompletionItem): TAtlasChip; static;
    class function Matches(const AItem: TAtlasCompletionItem; AChip: TAtlasChip): Boolean; static;
    /// <summary>Ähnliche Namen zu APattern als TypoHeader + Indizes (#485); leer ohne.</summary>
    class function Typos(const AItems: TAtlasCompletionItems; const APattern: string;
      const AOptions: TAtlasRankOptions; const AScores, ABoosts: TArray<Integer>): TArray<Integer>; static;
    /// <summary>Anzeigereihenfolge: Indizes in AItems, Header (-1) vor Gruppen geerbter Member.</summary>
    class function Order(const AItems: TAtlasCompletionItems; const APattern: string;
      const AOptions: TAtlasRankOptions): TArray<Integer>; overload; static;
    /// <summary>Wie oben; ARestStart ist die Position des ersten Eintrags ohne Treffer (#497), -1 ohne.</summary>
    class function Order(const AItems: TAtlasCompletionItems; const APattern: string;
      const AOptions: TAtlasRankOptions; out ARestStart: Integer): TArray<Integer>; overload; static;
    /// <summary>Treffer je Chip für APattern (unabhängig vom gewählten Chip).</summary>
    class function ChipCounts(const AItems: TAtlasCompletionItems; const APattern: string): TAtlasChipCounts; static;
    /// <summary>Einträge ohne Überschriften.</summary>
    class function ItemCount(const AOrder: TArray<Integer>): Integer; static;
    /// <summary>Überschrift statt Eintrag (Header, TypoHeader)?</summary>
    class function IsHeader(AValue: Integer): Boolean; static;
    /// <summary>Nur „Meintest du“-Einträge, kein regulärer Treffer (#485): Die Fußzeile nennt dann
    /// „Keine Treffer für ‚…‘“.</summary>
    class function OnlyTypos(const AOrder: TArray<Integer>): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Completion.Matching;

{ TAtlasRankOptions }

class function TAtlasRankOptions.Defaults: TAtlasRankOptions;
begin
  Result.GroupInherited := False;
  Result.Chip := TAtlasChip.All;
  Result.Boost := nil;
  Result.ListMode := TAtlasListMode.Filter;
end;

{ TAtlasListModes }

class function TAtlasListModes.ModeOf(const AName: string): TAtlasListMode;
var
  Mode: TAtlasListMode;
begin
  Result := TAtlasListMode.Filter;
  for Mode := Low(TAtlasListMode) to High(TAtlasListMode) do
    if SameText(Trim(AName), ModeNames[Mode]) then
      Result := Mode;
end;

class function TAtlasListModes.ScopeOf(const AName: string): TAtlasListScope;
var
  Scope: TAtlasListScope;
begin
  Result := TAtlasListScope.Members;
  for Scope := Low(TAtlasListScope) to High(TAtlasListScope) do
    if SameText(Trim(AName), ScopeNames[Scope]) then
      Result := Scope;
end;

{ TAtlasRanking }

class function TAtlasRanking.ChipOf(const AItem: TAtlasCompletionItem): TAtlasChip;
begin
  case AItem.Kind of
    TAtlasItemKind.Method, TAtlasItemKind.Function_, TAtlasItemKind.Procedure_, TAtlasItemKind.Constructor_,
    TAtlasItemKind.Destructor_:
      Result := TAtlasChip.Methods;
    TAtlasItemKind.Property_, TAtlasItemKind.Field:
      Result := TAtlasChip.Properties;
    TAtlasItemKind.Event:
      Result := TAtlasChip.Events;
    TAtlasItemKind.Type_, TAtlasItemKind.Class_, TAtlasItemKind.Interface_, TAtlasItemKind.Record_,
    TAtlasItemKind.Enum:
      Result := TAtlasChip.Types;
    TAtlasItemKind.Snippet:
      Result := TAtlasChip.Snippets;
  else
    // Variablen, Konstanten, Units, Schlüsselwörter: nur unter "Alle".
    Result := TAtlasChip.All;
  end;
end;

class function TAtlasRanking.Matches(const AItem: TAtlasCompletionItem; AChip: TAtlasChip): Boolean;
begin
  Result := (AChip = TAtlasChip.All) or (ChipOf(AItem) = AChip);
end;

function NameOf(const AItem: TAtlasCompletionItem): string;
begin
  if AItem.FilterText <> '' then
    Result := AItem.FilterText
  else
    Result := AItem.Name;
end;

/// <summary>Bereichsstufe zum Sortieren (#488): ohne Angabe hinter allen Stufen.</summary>
function ScopeRank(const AItem: TAtlasCompletionItem): Integer;
begin
  if AItem.Scope > 0 then
    Result := AItem.Scope
  else
    Result := 9;
end;

/// <summary>Gruppe im uses-Abschnitt (#469): 0 = Projekt (oder keine), 1 = RTL/VCL, 2 = Drittanbieter.</summary>
function UsesRank(const AItem: TAtlasCompletionItem): Integer;
begin
  if AItem.UsesGroup = 'rtl' then
    Result := 1
  else if AItem.UsesGroup = 'library' then
    Result := 2
  else
    Result := 0;
end;

/// <summary>Nach "inherited " (#482): 0 = gleiche Parameter, 1 = andere Überladung, 2 = weiterer Konstruktor
/// bzw. Destruktor, 3 = übrige Einträge.</summary>
function InheritedRank(const AItem: TAtlasCompletionItem): Integer;
begin
  if AItem.InheritedMatch = 'same' then
    Result := 0
  else if AItem.InheritedMatch = 'overload' then
    Result := 1
  else if AItem.InheritedMatch = 'other' then
    Result := 2
  else
    Result := 3;
end;

/// <summary>0 = passt zum erwarteten Typ, 1 = übrige, 2 = ohne erwarteten Typ.</summary>
function GroupOf(const AItem: TAtlasCompletionItem; AAnyFits: Boolean): Integer;
begin
  // Gruppen nur, wenn etwas passt: Teilergebnisse (#616) behalten den erwarteten Typ, auch wenn erst ein
  // späteres Teil einen passenden Eintrag bringt.
  if not AAnyFits or (AItem.ExpectedType = '') then
    Result := 2
  else if AItem.Fits then
    Result := 0
  else
    Result := 1;
end;

class function TAtlasRanking.Order(const AItems: TAtlasCompletionItems; const APattern: string;
  const AOptions: TAtlasRankOptions): TArray<Integer>;
var
  RestStart: Integer;
begin
  Result := Order(AItems, APattern, AOptions, RestStart);
end;

/// <summary>Einträge ohne Treffer für den Rest der Liste (#497): passend zum Chip, keine Aktionen, Hinweise oder
/// angehefteten Einträge, nicht schon in AShown; in Rang- und Namensfolge.</summary>
function RestOf(const AItems: TAtlasCompletionItems; const AOptions: TAtlasRankOptions;
  const AScores, AShown: TArray<Integer>): TArray<Integer>;
var
  Items: TAtlasCompletionItems;
  Shown: TArray<Boolean>;
  Rest: TList<Integer>;
  Index: Integer;
begin
  Items := AItems;
  SetLength(Shown, Length(Items));
  for Index in AShown do
    if Index >= 0 then
      Shown[Index] := True;
  Rest := TList<Integer>.Create;
  try
    for Index := 0 to High(Items) do
      if not Shown[Index] and (AScores[Index] = TAtlasCompletionMatcher.NoMatch) and
        TAtlasRanking.Matches(Items[Index], AOptions.Chip) and not Items[Index].IsAction and
        (Items[Index].Conversion = '') and
        not Items[Index].Hint and not Items[Index].Pinned and (Items[Index].Unknown = '') then
        Rest.Add(Index);
    Rest.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Ord(Items[A].Unavailable) - Ord(Items[B].Unavailable);
        if Result = 0 then
          Result := Items[A].Rank - Items[B].Rank;
        if Result = 0 then
          Result := CompareText(Items[A].Name, Items[B].Name);
        if Result = 0 then
          Result := A - B;
      end));
    Result := Rest.ToArray;
  finally
    Rest.Free;
  end;
end;

/// <summary>Umwandlungseinträge (#490) je direkt vor ihr Original in AOrder; jeder höchstens einmal.</summary>
function WithConversions(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  const AOptions: TAtlasRankOptions): TArray<Integer>;
var
  Placed: TArray<Boolean>;
  Index, Conversion: Integer;
  Any: Boolean;
begin
  Any := False;
  for Index := 0 to High(AItems) do
    if AItems[Index].Conversion <> '' then
      Any := True;
  if not Any then
    Exit(AOrder);
  SetLength(Placed, Length(AItems));
  Result := nil;
  for Index in AOrder do
  begin
    if Index >= 0 then
      for Conversion := 0 to High(AItems) do
        if not Placed[Conversion] and (AItems[Conversion].Conversion <> '') and
          SameText(AItems[Conversion].ConvertFrom, AItems[Index].Name) and
          TAtlasRanking.Matches(AItems[Conversion], AOptions.Chip) then
        begin
          Placed[Conversion] := True;
          Result := Result + [Conversion];
          Break;
        end;
    Result := Result + [Index];
  end;
end;

class function TAtlasRanking.Order(const AItems: TAtlasCompletionItems; const APattern: string;
  const AOptions: TAtlasRankOptions; out ARestStart: Integer): TArray<Integer>;
var
  Rest: TArray<Integer>;
  Items: TAtlasCompletionItems;
  Scores, Boosts: TArray<Integer>;
  Found, Ordered: TList<Integer>;
  Index, Position, Depth, Unknown, First: Integer;
  Grouped, AnyFits, NoPattern: Boolean;
  Container: string;
  Group: Integer;
  Options: TAtlasRankOptions;
begin
  ARestStart := -1;
  Items := AItems;
  Options := AOptions;
  SetLength(Scores, Length(Items));
  SetLength(Boosts, Length(Items));
  Grouped := Options.GroupInherited and (APattern = '');
  NoPattern := APattern = '';
  AnyFits := False;
  for Index := 0 to High(Items) do
    if Items[Index].Fits then
    begin
      AnyFits := True;
      Break;
    end;
  Found := TList<Integer>.Create;
  Ordered := TList<Integer>.Create;
  try
    for Index := 0 to High(Items) do
    begin
      Scores[Index] := TAtlasCompletionMatcher.NoMatch;
      // Umwandlungen (#490) setzt WithConversions vor ihr Original.
      if not TAtlasRanking.Matches(Items[Index], Options.Chip) or (Items[Index].Conversion <> '') then
        Continue;
      if Items[Index].IsAction or Items[Index].Pinned or Items[Index].Hint or Items[Index].ByType then
        Scores[Index] := 0
      else
        Scores[Index] := TAtlasCompletionMatcher.Score(APattern, NameOf(Items[Index]));
      if Scores[Index] = TAtlasCompletionMatcher.NoMatch then
        Continue;
      if Assigned(Options.Boost) then
        Boosts[Index] := EnsureRange(Options.Boost(Index), 0, 99);
      Found.Add(Index);
    end;
    Found.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        // Angeheftete Favoriten (#458) vor allem anderen.
        Result := Ord(Items[B].Favorite) - Ord(Items[A].Favorite);
        if Result = 0 then
          Result := Ord(Items[B].Hint) - Ord(Items[A].Hint);
        if Result = 0 then
          Result := Ord(Items[B].Form <> '') - Ord(Items[A].Form <> '');
        if (Result = 0) and (Items[A].Form <> '') then
          Result := Ord(Items[A].ByType) - Ord(Items[B].ByType);
        if Result = 0 then
          Result := Ord(Items[B].Pinned and NoPattern) - Ord(Items[A].Pinned and NoPattern);
        if Result = 0 then
          Result := Ord(Items[A].IsAction) - Ord(Items[B].IsAction);
        // Echte Mitglieder immer vor Postfix-Vorlagen (#188).
        if Result = 0 then
          Result := Ord(Items[A].Postfix) - Ord(Items[B].Postfix);
        // In der aktiven Konfiguration nicht vorhanden: ans Ende (#476).
        if Result = 0 then
          Result := Ord(Items[A].Unavailable) - Ord(Items[B].Unavailable);
        if Result = 0 then
          Result := GroupOf(Items[A], AnyFits) - GroupOf(Items[B], AnyFits);
        // Vollständige inherited-Aufrufe vor den Namen der Vorfahrmethoden (#482).
        if Result = 0 then
          Result := InheritedRank(Items[A]) - InheritedRank(Items[B]);
        // uses-Abschnitt (#469): Projekt vor RTL/VCL vor Drittanbietern.
        if Result = 0 then
          Result := UsesRank(Items[A]) - UsesRank(Items[B]);
        // Aufzählungswerte vor den übrigen passenden Einträgen, ohne Präfix in Deklarationsreihenfolge (#448).
        if Result = 0 then
          Result := Ord(Items[B].Ordinal > 0) - Ord(Items[A].Ordinal > 0);
        if (Result = 0) and (Items[A].Ordinal > 0) and NoPattern then
          Result := Items[A].Ordinal - Items[B].Ordinal;
        if Result <> 0 then
          Exit;
        if Grouped then
        begin
          // Ohne Präfix: nach Bereich (lokal vor Parameter vor Feld …, #488), dann Gruppen nach Tiefe,
          // darin Gelerntes zuerst.
          Result := ScopeRank(Items[A]) - ScopeRank(Items[B]);
          if Result = 0 then
            Result := Items[A].Depth - Items[B].Depth;
          if (Result = 0) and (Items[A].Depth > 0) then
            Result := CompareText(Items[A].DeclaringClass, Items[B].DeclaringClass);
          if Result = 0 then
            Result := Boosts[B] - Boosts[A];
        end
        else
        begin
          // Güte, dann Bereich (#488), dann Gelerntes (#418).
          Result := Scores[B] - Scores[A];
          if Result = 0 then
            Result := ScopeRank(Items[A]) - ScopeRank(Items[B]);
          if Result = 0 then
            Result := Boosts[B] - Boosts[A];
          if (Result = 0) and Options.GroupInherited then
            Result := Items[A].Depth - Items[B].Depth;
        end;
        if Result = 0 then
          Result := Items[A].Rank - Items[B].Rank;
        if Result = 0 then
          Result := CompareText(Items[A].Name, Items[B].Name);
        if Result = 0 then
          Result := A - B;
      end));
    // In einer Liste sammeln: Anhängen an das Array kopierte es bei jedem Eintrag (#616).
    Depth := 0;
    Container := '';
    Group := -1;
    // Favoriten (#458) stehen vorne und ohne Überschrift; die übrigen Gruppen beginnen bei First.
    First := 0;
    while (First < Found.Count) and Items[Found[First]].Favorite do
      Inc(First);
    for Position := 0 to Found.Count - 1 do
    begin
      Index := Found[Position];
      if Position < First then
      begin
        Ordered.Add(Index);
        Continue;
      end;
      // Überschrift je Gruppe zum erwarteten Typ (#417), sonst vor jeder Gruppe geerbter Member (#419).
      if Items[Index].Unknown <> '' then
      begin
        if (Position = First) or (Items[Found[Position - 1]].Unknown = '') then
          Ordered.Add(UnknownHeader);
      end
      else if Items[Index].Form <> '' then
      begin
        if (Position = First) or (Items[Found[Position - 1]].Form = '') then
          Ordered.Add(Header);
      end
      else if (Items[Index].Sender <> '') and (Position = First) then
        Ordered.Add(Header)
      // Typargumente (#450): eine Überschrift mit dem Constraint über der Liste.
      else if (Items[Index].TypeParam <> '') and (Position = First) then
        Ordered.Add(Header)
      // uses-Abschnitt (#469): eine Überschrift je Gruppe (Projekt, RTL/VCL, Drittanbieter).
      else if Items[Index].UsesGroup <> '' then
      begin
        if (Position = First) or (Items[Found[Position - 1]].UsesGroup <> Items[Index].UsesGroup) then
          Ordered.Add(Header);
      end
      // Nach der Formulargruppe eine Überschrift über dem Rest („Weitere“ bzw. die Gruppe zum erwarteten Typ).
      else if (Position > First) and (Items[Found[Position - 1]].Form <> '') then
        Ordered.Add(Header)
      else if AnyFits and (Items[Index].ExpectedType <> '') and not Items[Index].IsAction then
      begin
        if GroupOf(Items[Index], AnyFits) <> Group then
          Ordered.Add(Header);
      end
      else if Grouped and (Items[Index].Depth > 0) and ((Items[Index].Depth <> Depth) or
        not SameText(Items[Index].DeclaringClass, Container)) then
        Ordered.Add(Header);
      Group := GroupOf(Items[Index], AnyFits);
      Depth := Items[Index].Depth;
      Container := Items[Index].DeclaringClass;
      Ordered.Add(Index);
    end;
    Result := WithConversions(Items, Ordered.ToArray, Options);
    // Tippfehler (#485): wenig reguläre Treffer, dann bis zu MaxTypos ähnliche Namen unter „Meintest du“, vor
    // der Gruppe des unbekannten Namens (#471), die nicht als Treffer zählt.
    Unknown := Length(Result);
    for Position := 0 to High(Result) do
      if Result[Position] = UnknownHeader then
      begin
        Unknown := Position;
        Break;
      end;
    if (ItemCount(Copy(Result, 0, Unknown)) < MinRegular) and (TAtlasCompletionMatcher.TypoLimit(APattern) > 0) then
      Result := Copy(Result, 0, Unknown) + Typos(Items, APattern, Options, Scores, Boosts) +
        Copy(Result, Unknown, MaxInt);
    // Rest der Liste (#497): hinter Treffern und Tippfehlern, vor dem unbekannten Namen.
    if (Options.ListMode <> TAtlasListMode.Filter) and not NoPattern then
    begin
      Rest := RestOf(Items, Options, Scores, Result);
      if Length(Rest) > 0 then
      begin
        Unknown := Length(Result);
        for Position := 0 to High(Result) do
          if Result[Position] = UnknownHeader then
          begin
            Unknown := Position;
            Break;
          end;
        if Options.ListMode = TAtlasListMode.Rest then
        begin
          ARestStart := Unknown + 1;
          Result := Copy(Result, 0, Unknown) + [RestHeader] + Rest + Copy(Result, Unknown, MaxInt);
        end
        else
        begin
          ARestStart := Unknown;
          Result := Copy(Result, 0, Unknown) + Rest + Copy(Result, Unknown, MaxInt);
        end;
      end;
    end;
  finally
    Ordered.Free;
    Found.Free;
  end;
end;

class function TAtlasRanking.Typos(const AItems: TAtlasCompletionItems; const APattern: string;
  const AOptions: TAtlasRankOptions; const AScores, ABoosts: TArray<Integer>): TArray<Integer>;
var
  Items: TAtlasCompletionItems;
  Distances: TArray<Integer>;
  Candidates: TList<Integer>;
  Index, Limit: Integer;
  Boosts: TArray<Integer>;
begin
  Result := nil;
  Items := AItems;
  Boosts := ABoosts;
  Limit := TAtlasCompletionMatcher.TypoLimit(APattern);
  SetLength(Distances, Length(Items));
  Candidates := TList<Integer>.Create;
  try
    for Index := 0 to High(Items) do
    begin
      // Nur, was nicht schon regulär passt; keine Aktionen.
      if Items[Index].IsAction or not Matches(Items[Index], AOptions.Chip) or (Items[Index].Conversion <> '') or
        (AScores[Index] <> TAtlasCompletionMatcher.NoMatch) then
        Continue;
      Distances[Index] := TAtlasCompletionMatcher.TypoDistance(APattern, NameOf(Items[Index]));
      if Distances[Index] <= Limit then
        Candidates.Add(Index);
    end;
    if Candidates.Count = 0 then
      Exit;
    Candidates.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Distances[A] - Distances[B];
        if Result = 0 then
          Result := Boosts[B] - Boosts[A];
        if Result = 0 then
          Result := CompareText(Items[A].Name, Items[B].Name);
      end));
    Result := [TypoHeader];
    for Index := 0 to Min(Candidates.Count, MaxTypos) - 1 do
      Result := Result + [Candidates[Index]];
  finally
    Candidates.Free;
  end;
end;

class function TAtlasRanking.ChipCounts(const AItems: TAtlasCompletionItems;
  const APattern: string): TAtlasChipCounts;
var
  Chip: TAtlasChip;
  Item: TAtlasCompletionItem;
begin
  for Chip := Low(TAtlasChip) to High(TAtlasChip) do
    Result[Chip] := 0;
  // Umwandlungen (#490) zählen nicht doppelt.
  for Item in AItems do
    if (Item.Conversion = '') and (TAtlasCompletionMatcher.Score(APattern, NameOf(Item)) <>
      TAtlasCompletionMatcher.NoMatch) then
    begin
      Inc(Result[TAtlasChip.All]);
      if ChipOf(Item) <> TAtlasChip.All then
        Inc(Result[ChipOf(Item)]);
    end;
end;

class function TAtlasRanking.ItemCount(const AOrder: TArray<Integer>): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index in AOrder do
    if not IsHeader(Index) then
      Inc(Result);
end;

class function TAtlasRanking.IsHeader(AValue: Integer): Boolean;
begin
  Result := AValue < 0;
end;

class function TAtlasRanking.OnlyTypos(const AOrder: TArray<Integer>): Boolean;
begin
  Result := (Length(AOrder) > 1) and (AOrder[0] = TypoHeader);
end;

end.
