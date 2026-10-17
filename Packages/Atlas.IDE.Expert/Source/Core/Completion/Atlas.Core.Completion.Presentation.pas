unit Atlas.Core.Completion.Presentation;

// Darstellung eines Eintrags in der Liste (#420, #421), ohne Fenster:
//   - Badge: Kürzel und Farbart nach der Art; Funktion oder Prozedur nach
//     der Signatur, solange der Server beides als Methode meldet.
//   - Detail: gedämpfter Text rechts (Typ, Klasse, Unit-Datei).
//   - Tags: "+ Unit" für Einträge aus nicht eingebundenen Units (#180),
//     "deprecated", "constructor"/"destructor", "+2" bei drei Überladungen
//     (#425), "Helper" (#456), "zuletzt"/"häufig" (#418), Anzahl fehlender
//     Werte bei „Alle Werte einfügen“ (#449), "Snippet" bei Code-Vorlagen (#51).
//   - Geerbte Member (#419): Detail beginnt mit der deklarierenden Klasse.
//   - Treffer: Positionen der getippten Zeichen im Namen zum Hervorheben,
//     nach denselben Regeln wie TAtlasCompletionMatcher.

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Style.Palette;

type
  TAtlasBadge = record
    Kind: TAtlasBadgeKind;
    /// <summary>Zwei Buchstaben, z. B. "fn".</summary>
    Code: string;
  end;

  TAtlasTagKind = (Neutral, Accent, Add, Warn);

  /// <summary>Übersetzbare Marken (#446); Plain = Text unverändert zeigen.</summary>
  TAtlasTagId = (Plain, Recent, Frequent);

  TAtlasTag = record
    Text: string;
    Kind: TAtlasTagKind;
    Id: TAtlasTagId;
  end;

  TAtlasTags = TArray<TAtlasTag>;

  TAtlasItemPresentation = class
  public
    class function Badge(const AItem: TAtlasCompletionItem): TAtlasBadge; static;
    class function Detail(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>Ansage für Screenreader (#447): "Name, Art, Position von Anzahl. Kurzbeschreibung";
    /// AOf ist das Format von "Position von Anzahl" (z. B. "%d von %d").</summary>
    class function Announcement(const AItem: TAtlasCompletionItem; const AKind, AOf: string;
      APosition, ACount: Integer): string; static;
    class function Tags(const AItem: TAtlasCompletionItem): TAtlasTags; static;
    /// <summary>Unit, die beim Übernehmen in uses ergänzt wird; '' wenn eingebunden.</summary>
    class function MissingUnit(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>1-basierte Positionen in AName, die APattern trifft; leer ohne Treffer.</summary>
    class function Highlights(const APattern, AName: string): TArray<Integer>; static;
    /// <summary>SQL-Anweisung, aus der die Feld- oder Parameternamen der Liste stammen (#461), für die
    /// Fußzeile; '' bei anderen Listen.</summary>
    class function DataSource(const AItems: TAtlasCompletionItems): string; static;
    /// <summary>Ausgeblendete Arten der Typargumente (#450), "records,enums"; '' ohne.</summary>
    class function HiddenKinds(const AItems: TAtlasCompletionItems): string; static;
    /// <summary>Nur das Angebot „Mit try…finally absichern“ (#489) in der Liste?</summary>
    class function Guarding(const AItems: TAtlasCompletionItems): Boolean; static;
  end;

implementation

uses
  System.Character,
  System.StrUtils,
  Atlas.Core.Completion.Matching;

const
  UsesSuffix = ' (uses ergänzen)';

function MakeBadge(AKind: TAtlasBadgeKind; const ACode: string): TAtlasBadge;
begin
  Result.Kind := AKind;
  Result.Code := ACode;
end;

function MakeTag(const AText: string; AKind: TAtlasTagKind): TAtlasTag;
begin
  Result.Text := AText;
  Result.Kind := AKind;
  Result.Id := TAtlasTagId.Plain;
end;

function IsWordStart(const AName: string; AIndex: Integer): Boolean;
begin
  Result := TAtlasCompletionMatcher.IsWordStart(AName, AIndex);
end;

function SameChar(A, B: Char): Boolean;
begin
  Result := UpCase(A) = UpCase(B);
end;

function Range(AStart, ACount: Integer): TArray<Integer>;
var
  Index: Integer;
begin
  SetLength(Result, ACount);
  for Index := 0 to ACount - 1 do
    Result[Index] := AStart + Index;
end;

function WordStartPositions(const APattern, AName: string): TArray<Integer>;
var
  PatternIndex, NameIndex: Integer;
begin
  Result := nil;
  PatternIndex := 1;
  for NameIndex := 1 to Length(AName) do
    if (PatternIndex <= Length(APattern)) and IsWordStart(AName, NameIndex) and
      SameChar(AName[NameIndex], APattern[PatternIndex]) then
    begin
      Result := Result + [NameIndex];
      Inc(PatternIndex);
    end;
  if PatternIndex <= Length(APattern) then
    Result := nil;
end;

function SubsequencePositions(const APattern, AName: string): TArray<Integer>;
var
  Reached: TArray<TArray<Boolean>>;
  PatternIndex, NameIndex, Previous: Integer;
  Before: Boolean;
begin
  // Wie MatchesSubsequence, aber mit allen Zwischenständen, um den Weg zurückzuverfolgen.
  Result := nil;
  SetLength(Reached, Length(APattern) + 1, Length(AName) + 1);
  for NameIndex := 1 to Length(AName) do
    Reached[1][NameIndex] := IsWordStart(AName, NameIndex) and SameChar(AName[NameIndex], APattern[1]);
  for PatternIndex := 2 to Length(APattern) do
  begin
    Before := False;
    for NameIndex := 1 to Length(AName) do
    begin
      Reached[PatternIndex][NameIndex] := SameChar(AName[NameIndex], APattern[PatternIndex]) and
        (Reached[PatternIndex - 1][NameIndex - 1] or (Before and IsWordStart(AName, NameIndex)));
      Before := Before or Reached[PatternIndex - 1][NameIndex - 1];
    end;
  end;
  // Frühestes Ende des ganzen Musters, dann rückwärts: bevorzugt direkt davor.
  NameIndex := 0;
  for Previous := 1 to Length(AName) do
    if Reached[Length(APattern)][Previous] then
    begin
      NameIndex := Previous;
      Break;
    end;
  if NameIndex = 0 then
    Exit;
  SetLength(Result, Length(APattern));
  for PatternIndex := Length(APattern) downto 1 do
  begin
    Result[PatternIndex - 1] := NameIndex;
    if PatternIndex = 1 then
      Break;
    if Reached[PatternIndex - 1][NameIndex - 1] then
      Dec(NameIndex)
    else
    begin
      Previous := NameIndex - 2;
      while (Previous >= 1) and not Reached[PatternIndex - 1][Previous] do
        Dec(Previous);
      NameIndex := Previous;
    end;
  end;
end;

{ TAtlasItemPresentation }

class function TAtlasItemPresentation.Badge(const AItem: TAtlasCompletionItem): TAtlasBadge;
var
  Signature: string;
begin
  Signature := LowerCase(TrimLeft(AItem.Signature));
  case AItem.Kind of
    TAtlasItemKind.Procedure_, TAtlasItemKind.Destructor_:
      Result := MakeBadge(TAtlasBadgeKind.Procedure_, 'pr');
    TAtlasItemKind.Function_, TAtlasItemKind.Constructor_:
      Result := MakeBadge(TAtlasBadgeKind.Function_, 'fn');
    TAtlasItemKind.Method:
      if Signature.StartsWith('procedure') or Signature.StartsWith('destructor') then
        Result := MakeBadge(TAtlasBadgeKind.Procedure_, 'pr')
      else
        Result := MakeBadge(TAtlasBadgeKind.Function_, 'fn');
    TAtlasItemKind.Property_:
      Result := MakeBadge(TAtlasBadgeKind.Property_, 'pp');
    TAtlasItemKind.Field:
      Result := MakeBadge(TAtlasBadgeKind.Field, 'fd');
    TAtlasItemKind.Event:
      Result := MakeBadge(TAtlasBadgeKind.Event, 'ev');
    TAtlasItemKind.Constant, TAtlasItemKind.EnumMember:
      Result := MakeBadge(TAtlasBadgeKind.Constant, 'co');
    TAtlasItemKind.Type_, TAtlasItemKind.Class_, TAtlasItemKind.Interface_, TAtlasItemKind.Record_,
    TAtlasItemKind.Enum:
      Result := MakeBadge(TAtlasBadgeKind.Type_, 'ty');
    TAtlasItemKind.Variable, TAtlasItemKind.Parameter:
      Result := MakeBadge(TAtlasBadgeKind.Variable, 'va');
    TAtlasItemKind.Unit_:
      Result := MakeBadge(TAtlasBadgeKind.Unit_, 'un');
    TAtlasItemKind.Keyword:
      Result := MakeBadge(TAtlasBadgeKind.Keyword, 'kw');
    TAtlasItemKind.Snippet:
      Result := MakeBadge(TAtlasBadgeKind.Snippet, 'sn');
    TAtlasItemKind.XmlDocTag:
      Result := MakeBadge(TAtlasBadgeKind.XmlDoc, 'xd');
  else
    Result := MakeBadge(TAtlasBadgeKind.Variable, '··');
  end;
end;

class function TAtlasItemPresentation.MissingUnit(const AItem: TAtlasCompletionItem): string;
var
  Edit: TAtlasTextEdit;
  Text: string;
begin
  Result := '';
  if AItem.UnitUsed then
    Exit;
  // Der Server nennt die Unit im Detail ("System.Classes (uses ergänzen)").
  if EndsText(UsesSuffix, AItem.Signature) then
    Exit(Copy(AItem.Signature, 1, Length(AItem.Signature) - Length(UsesSuffix)));
  // Sonst aus der Ergänzung selbst (", System.Classes" bzw. "uses System.Classes;").
  for Edit in AItem.AdditionalEdits do
  begin
    Text := Trim(Edit.NewText.Replace(',', ' ').Replace(';', ' '));
    if StartsText('uses', Text) and ((Length(Text) = 4) or not Text[5].IsLetter) then
      Text := Trim(Copy(Text, 5, MaxInt));
    if Text <> '' then
      Exit(Text);
  end;
end;

class function TAtlasItemPresentation.Announcement(const AItem: TAtlasCompletionItem; const AKind, AOf: string;
  APosition, ACount: Integer): string;
var
  Short: string;
begin
  Result := AItem.Name;
  if AKind <> '' then
    Result := Result + ', ' + AKind;
  Result := Result + ', ' + Format(AOf, [APosition, ACount]) + '.';
  Short := Detail(AItem);
  if (Short <> '') and not SameText(Short, AItem.Name) then
    Result := Result + ' ' + Short;
end;

class function TAtlasItemPresentation.Detail(const AItem: TAtlasCompletionItem): string;
begin
  if MissingUnit(AItem) <> '' then
    Exit('');
  Result := AItem.Signature;
  // Units: nur der Dateiname statt des ganzen Pfads.
  if AItem.Kind = TAtlasItemKind.Unit_ then
    Result := ExtractFileName(Result);
  // Geerbt (#419): Herkunft vorn, damit sie beim Kürzen bleibt.
  if (AItem.Depth > 0) and (AItem.DeclaringClass <> '') then
    if (Result <> '') and not SameText(Result, AItem.DeclaringClass) then
      Result := AItem.DeclaringClass + ' · ' + Result
    else
      Result := AItem.DeclaringClass;
end;

class function TAtlasItemPresentation.Tags(const AItem: TAtlasCompletionItem): TAtlasTags;
var
  Directive, MissingName: string;
begin
  Result := nil;
  if AItem.Count > 0 then
    Result := Result + [MakeTag(IntToStr(AItem.Count), TAtlasTagKind.Accent)];
  MissingName := MissingUnit(AItem);
  if MissingName <> '' then
    Result := Result + [MakeTag('+ ' + MissingName, TAtlasTagKind.Add)];
  case AItem.Kind of
    TAtlasItemKind.Constructor_: Result := Result + [MakeTag('constructor', TAtlasTagKind.Neutral)];
    TAtlasItemKind.Destructor_: Result := Result + [MakeTag('destructor', TAtlasTagKind.Neutral)];
  end;
  for Directive in AItem.Directives do
    if SameText(Directive, 'deprecated') then
      Result := Result + [MakeTag('deprecated', TAtlasTagKind.Warn)];
  // Herkunft (#488): woher ein Name ohne Punkt davor stammt.
  case AItem.Scope of
    1: Result := Result + [MakeTag('lokal', TAtlasTagKind.Accent)];
    2: Result := Result + [MakeTag('Parameter', TAtlasTagKind.Accent)];
    3:
      if AItem.Kind = TAtlasItemKind.Property_ then
        Result := Result + [MakeTag('Eigenschaft', TAtlasTagKind.Neutral)]
      else if AItem.Kind = TAtlasItemKind.Field then
        Result := Result + [MakeTag('Feld', TAtlasTagKind.Neutral)]
      else if AItem.DeclaringClass <> '' then
        // Methoden von Self: die Klasse, die sie deklariert.
        Result := Result + [MakeTag(AItem.DeclaringClass, TAtlasTagKind.Neutral)];
    4: Result := Result + [MakeTag('Unit', TAtlasTagKind.Neutral)];
    5:
      if AItem.DeclaringUnit <> '' then
        Result := Result + [MakeTag(AItem.DeclaringUnit, TAtlasTagKind.Neutral)];
  end;
  // Bedingte Deklarationen (#476): "nur WIN64"; in der aktiven Konfiguration nicht vorhanden als Warnung.
  if SameText(AItem.Condition, 'platform') then
    Result := Result + [MakeTag('platform', TAtlasTagKind.Warn)]
  else if AItem.Condition <> '' then
    if AItem.Unavailable then
      Result := Result + [MakeTag('nur ' + AItem.Condition, TAtlasTagKind.Warn)]
    else
      Result := Result + [MakeTag('nur ' + AItem.Condition, TAtlasTagKind.Neutral)];
  if AItem.OverloadCount > 1 then
    Result := Result + [MakeTag('+' + IntToStr(AItem.OverloadCount - 1), TAtlasTagKind.Neutral)];
  if AItem.IsHelper then
    Result := Result + [MakeTag('Helper', TAtlasTagKind.Accent)];
  // Postfix-Vorlagen (#188) und Code-Vorlagen (#51).
  if AItem.Postfix then
    Result := Result + [MakeTag('Postfix', TAtlasTagKind.Neutral)]
  else if AItem.Snippet <> '' then
    Result := Result + [MakeTag('Snippet', TAtlasTagKind.Neutral)];
  // Sender mit Typumwandlung (#480).
  if AItem.Sender <> '' then
    Result := Result + [MakeTag('als ' + AItem.Sender, TAtlasTagKind.Accent)];
  case AItem.Usage of
    TAtlasUsageMark.Recent:
      begin
        Result := Result + [MakeTag('zuletzt', TAtlasTagKind.Accent)];
        Result[High(Result)].Id := TAtlasTagId.Recent;
      end;
    TAtlasUsageMark.Frequent:
      begin
        Result := Result + [MakeTag('häufig', TAtlasTagKind.Neutral)];
        Result[High(Result)].Id := TAtlasTagId.Frequent;
      end;
  end;
end;

class function TAtlasItemPresentation.Highlights(const APattern, AName: string): TArray<Integer>;
var
  Score, Found: Integer;
begin
  Result := nil;
  Score := TAtlasCompletionMatcher.Score(APattern, AName);
  if (APattern = '') or (Score = TAtlasCompletionMatcher.NoMatch) then
    Exit;
  if Score >= TAtlasCompletionMatcher.ScorePrefix then
    Exit(Range(1, Length(APattern)));
  if Score = TAtlasCompletionMatcher.ScoreWordStarts then
    Exit(WordStartPositions(APattern, AName));
  if Score = TAtlasCompletionMatcher.ScoreSubstring then
  begin
    Found := Pos(APattern.ToUpper, AName.ToUpper);
    Exit(Range(Found, Length(APattern)));
  end;
  Result := SubsequencePositions(APattern, AName);
end;

class function TAtlasItemPresentation.HiddenKinds(const AItems: TAtlasCompletionItems): string;
var
  Item: TAtlasCompletionItem;
begin
  for Item in AItems do
    if Item.HiddenKinds <> '' then
      Exit(Item.HiddenKinds);
  Result := '';
end;

class function TAtlasItemPresentation.DataSource(const AItems: TAtlasCompletionItems): string;
var
  Item: TAtlasCompletionItem;
begin
  for Item in AItems do
    if Item.DataSource <> '' then
      Exit(Item.DataSource);
  Result := '';
end;

class function TAtlasItemPresentation.Guarding(const AItems: TAtlasCompletionItems): Boolean;
var
  Item: TAtlasCompletionItem;
begin
  Result := Length(AItems) > 0;
  for Item in AItems do
    if not Item.Guard then
      Exit(False);
end;

end.
